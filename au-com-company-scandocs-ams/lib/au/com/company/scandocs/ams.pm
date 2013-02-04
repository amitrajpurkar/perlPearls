package au::com::company::scandocs::ams;

use 5.008008;
use strict;
use warnings;

use File::Copy;
use File::Path;
use File::stat;
use Getopt::Std;
use Filesys::SmbClient;
use LWP::Simple;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use au::com::company::scandocs::ams ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
        fetchFromAms
        pushDocumentIntoAms
    )], 
    'read' => [ qw(
        fetchFromAms
    )],
    'write' => [ qw(
        pushDocumentIntoAms
    )] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '1.00';

my $DEFAULT_FILE_EXTENSION = "pdf";
my $smb;
my $amsPdfDestLocation;
my $amsPdfBaseLocation = "smb://sydams01/ldw_archive/scan_dump_archive/";
my $amsTxtDestLocation = "smb://sydams01/in\$";
my $TODAYS_DATE;
my $AMS_USER = "dummyUserid";
my $AMS_PASSWD = "dummyPassword";
my $AMS_WRKGRP = "dummyWorkgroup";
my ($statusCode, $errorMessage);

# Preloaded methods go here.

# private method not exposed
sub constructAmsUrl {
    my ($docRefId) = @_;
    my $baseUrl = "http://ams1.company.com.au/ams4/tsearch.aspx";
    my $fixedParameters = "?database=pgserver&table=View_PGServerDocs&field=shipnoid&application=companyDocumentScanner&user=companyAppUser&type=sampleType&data=";
    return ($baseUrl . $fixedParameters . $docRefId); 
}

sub fetchFromAms {
    my ($docRefId, $tempOldDocument) = @_;
    my $amsUrl = constructAmsUrl($docRefId);
    my $httpStatusCode = LWP::Simple::getstore($amsUrl, $tempOldDocument);
    
    if( is_success($httpStatusCode) ){
        return ("OK", "document is fetched successfully");
    } else {
        return ("FAILED", "url fetch status-code = $httpStatusCode");
    }
}

sub pushDocumentIntoAms {
    my ($docRefId, $absolutePathToSourcePdf, $insertAppendParam, $docidParam, $docTypeParam, $departmentParam, $filesizeParam, $branchParam, $shipnoParam, $docDateParam, $absolutePathForTempTXTFile) = @_;
    $statusCode = "initialize";
    $errorMessage = "initialize";
    ## -------------------First initialize samba conn in try-catch-----------------------------------------
    eval {
        initializeSambaConnection();
    };
    if ($@) {
        $statusCode = "FAILED";
        $errorMessage =  $@;
    }
    if($statusCode eq "FAILED") {
        return ($statusCode, $errorMessage);
    }
    ## -------------------If alls good, transfer PDF file in try-catch--------------------------------------
    eval {
        ($statusCode, $errorMessage) = pushPdfFile($docRefId, $absolutePathToSourcePdf);
    };
    if ($@) {
        $statusCode = "FAILED";
        $errorMessage =  $@;
    }
    if($statusCode eq "FAILED") {
        return ($statusCode, $errorMessage);
    }
    ## -------------------If alls good so far, transfer TXT file in try-catch------------------------------
    eval {
        ($statusCode, $errorMessage) = pushTxtFile($docRefId, $insertAppendParam, $docidParam, $docTypeParam, $departmentParam, $filesizeParam, $branchParam, $shipnoParam, $docDateParam, $absolutePathForTempTXTFile);
    };
    if ($@) {
        $statusCode = "FAILED";
        $errorMessage =  $@;
    }
    if($statusCode eq "FAILED") {
        return ($statusCode, $errorMessage);
    } else {
        ## -------------------If you reached this point, alls good--------------------------------------------
        $errorMessage = "Both PDF and TXT files have been pushed successfully to AMS";
        return ($statusCode, $errorMessage);
    }
}

sub initializeSambaConnection {
    $smb = new Filesys::SmbClient( username => $AMS_USER, password => $AMS_PASSWD, workgroup => $AMS_WRKGRP );
    if (!defined $smb) {
      die("Error: Cannot open samba-client connection to sydams01 using supplied credentials. \n");
    }
    my (
         $second,     $minute,    $hour,
         $dayOfMonth, $month,     $yearOffset,
         $dayOfWeek,  $dayOfYear, $daylightSavings
    ) = localtime();
    my $year = 1900 + $yearOffset;
    $month = $month + 1;
    $TODAYS_DATE = sprintf( "%4d%02d%02d", $year, $month, $dayOfMonth );
    
    $amsPdfDestLocation = $amsPdfBaseLocation . $TODAYS_DATE;
}

sub pushPdfFile{
    my ($docRefId, $sourceFileFullPath) = @_;
    my ($local_size, $localFileStats, $remote_size, $dir_fh, $file_fh);
    my $destinationFileName = $docRefId . ".pdf"; 
    
    $dir_fh = $smb->opendir("$amsPdfDestLocation");
    if ( $dir_fh == 0 ) {
        $smb->mkdir( "$amsPdfDestLocation", '0666' );
    }
    $file_fh = $smb->open( ">$amsPdfDestLocation/$destinationFileName", 0666 ) or die("ERROR:: Can't create file:", $!, "\n");
    open( INFILE, "$sourceFileFullPath" ) or die("ERROR:: Can't open $sourceFileFullPath\n");
    while ( my $line = <INFILE> ) {
        $smb->write( $file_fh, $line ) or die("ERROR:: $! \n" );
    }
    close(INFILE);
    $smb->close($file_fh);
    $smb->close($dir_fh);
    
    my @remoteFileStats = $smb->stat("$amsPdfDestLocation/$destinationFileName");
    $remote_size = $remoteFileStats[7];
    if ( $localFileStats = stat("$sourceFileFullPath") ) {
        $local_size = $localFileStats->size;
    } else {
        $local_size = 0;
    }
    if ( $remote_size != $local_size ) {
        return ("ERR","DEST FILE INCOMPLETE: $remote_size bytes instead of $local_size");
    } else {
        return ("OK", "FILE TRANSFER success for file $destinationFileName");
    }
}

sub pushTxtFile{
    my ($docRefId, $insertAppendParam, $docidParam, $docTypeParam, $departmentParam, $filesizeParam, $branchParam, $shipnoParam, $docDateParam, $tempSourceFilePath) = @_;
    my $filetypeParam = $DEFAULT_FILE_EXTENSION;
    my ($local_size, $localFileStats, $remote_size, $dir_fh, $file_fh);
    
    my $pdfFileName = $TODAYS_DATE . "\\" . $docRefId . ".pdf";
    my $txtFileName = "";
    if ($insertAppendParam eq "INSERT") {
        $txtFileName = $docRefId . "-I.txt";
    } else {
        $txtFileName = $docRefId . "-U.txt";
    }
    
    $docDateParam =~ s/-//g; #### Date Format changed from YYYY-MM-DD to YYYYMMDD
    
    my $tempSourceFile="$tempSourceFilePath/$txtFileName";
    open(OUT, ">$tempSourceFile") or die( "ERROR:: Could not write to $tempSourceFile\n" );
    print OUT "action\n$insertAppendParam\n";
    print OUT "docid\n$docidParam\n";
    print OUT "type\n$docTypeParam\n";
    print OUT "department\n$departmentParam\n";
    print OUT "file_type\n$filetypeParam\n";
    print OUT "file_size\n$filesizeParam\n";
    print OUT "branch\n$branchParam\n";
    print OUT "shipno\n$shipnoParam\n";
    print OUT "created\n$TODAYS_DATE\n";
    print OUT "updated\n$TODAYS_DATE\n";
    print OUT "sentby\nAQIS Direction email from POSTI\n";      
    print OUT "date_scan\n$TODAYS_DATE\n";  #### NeoDocs uses this date to create value for system_filename column
    print OUT "file_name\n$pdfFileName\n";
    close(OUT);
    
    $file_fh = $smb->open( ">$amsTxtDestLocation/$txtFileName", 0666 ) or die( "Can't create file: $! \n" );
    open( INFILE, "$tempSourceFile" ) or die( "ERROR:: Can't open $tempSourceFile\n" );
    while ( my $line = <INFILE> ) {
        $smb->write( $file_fh, $line ) or die("ERROR:: $! \n" );
    }
    close(INFILE);
    $smb->close($file_fh);
    
    my @remoteFileStats = $smb->stat("$amsTxtDestLocation/$txtFileName");
    $remote_size = $remoteFileStats[7];
    if ( $localFileStats = stat("$tempSourceFile") ) {
        $local_size = $localFileStats->size;
    } else {
        $local_size = 0;
    }
    unlink($tempSourceFile); #### delete temp file after use -- successful or not

    if ( $remote_size != $local_size ) {
        return ("ERR", "DEST FILE INCOMPLETE: $remote_size bytes instead of $local_size");
    } else {
        return ("OK", "FILE TRANSFER success for file $txtFileName");
    }
}


1;
__END__
# Below is documentation for this module. Lets keep this up.to.date!

=head1 NAME

au::com::company::scandocs::ams - houses reusable sub-routines for fetching document from AMS and inserting documents into AMS

=head1 SYNOPSIS

  use au::com::company::scandocs::ams;
  my $scandocs = new au::com::company::scandocs::ams;
  $scandocs->fetchFromAms($documentReferenceId, $absolutePathToTempDocument);
  $scandocs->pushDocumentIntoAms($documentReferenceId, $absolutePathToSourcePdf, $insertUpdateFlag, $docid, $docType, $department, $filesize, $branch, $shipno, $docDate, $absolutePathForTempTXTFile);

=head1 DESCRIPTION

documentation for au::com::company::scandocs::ams, created by h2xs. 

This module has been created to help maximize reuse of tried and tested sub-routines of fetching / inserting documents with AMS.
Developers should be able to re-use this module across all LDW linux servers like proc1, posti, etc seamlessly.

=head2 EXPORT

None by default.

=head2 METHODS

=over 4

=item * $scandocs->fetchFromAms($documentReferenceId, $absolutePathToTempDocument);

This one is a "read" method for Scan-Docs.. so from the module use import tags ':all' or ':read' so that this method can be used
This method returns two-valued-list; meaning it returns a list having two items, one the status code 'OK' or 'FAILED' and second the descriptive message 
Successful call to this method, creates a valid, non-zero-sized, PDF file in the location specified by 'absolutePathToTempDocument'; the return value for success is a list giving return-code 'OK' and a descriptive message;
Unsuccessful call will not create the file in the location specified by that parameter; the return value for success is a list giving return-code 'FAILED' and a descriptive message;

=item * $scandocs->pushDocumentIntoAms($documentReferenceId, $absolutePathToSourcePdf, $insertUpdateFlag, $docid, $docType, $department, $filesize, $branch, $shipno, $docDate, $absolutePathForTempTXTFile);

This one is under ":write" and ":all" tags.. so from the module use these import tags so that this method can be accessed
Behind the scene this method first initializes Samba connection to AMS server, then pushes the PDF file into archive location, followed by the TXT file push for NeoDocs process.
This method returns two-valued-list; meaning it returns a list having two items, one the status code 'OK' or 'FAILED' and second the descriptive message 
This method will return a list ("OK","success-message") if all three sub-steps are successful;
If any sub-step fails the method returns a list ("FAILED","detailed-failure-message");
The method does not throw exception .. so caller does not need to have try-catch and rely just on STATUS-CODES 'OK' and 'FAILED' and respective messages; 


=back

=head1 SEE ALSO

Mention other useful documentation.
For this section best places are project documents, specifically BRS and Systems Narrative, that will convey the Functional specification / high level design that got made existance of such module necessary
First such project was Project#2012-289:: Scan Docs Phase 1; this was followed by Project#2012-445:: AQIS Document Solution.

=head1 AUTHOR

Amit Rajpurkar, for E<lt>Aust.Support@company.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by company 

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
