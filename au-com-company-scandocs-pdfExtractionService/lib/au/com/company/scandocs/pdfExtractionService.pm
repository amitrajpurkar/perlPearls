package au::com::company::scandocs::pdfExtractionService;

use 5.008008;
use strict;
use warnings;

use File::Copy;
use File::Path;
use File::stat;
use Getopt::Std;
use POSIX;
use CAM::PDF;
use au::com::company::scandocs::ams qw( :all );
use au::com::company::scandocs::pgService qw( :all );

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use au::com::company::scandocs::pdfExtractionService ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	processEachPdfAttachment
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';


# Preloaded methods go here.


sub processEachPdfAttachment {
    my ($attFileParam, $insertAppendParam, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate) = @_;
    my ($msgCode, $msgDesc, $errCode, $errDesc);
    
    my $filesize = getFileSize( $attFileParam );
    $msgCode = "OK";
    
    if($insertAppendParam eq "INSERT" ) {
        ($docid, $msgDesc) = createDocumentInPGServer($shipno, $filesize, $todaysDate, $attFileParam, $dptParam, $branchParam, $docType);
    } else {
        ($msgCode, $msgDesc) = mergeNewDocumentWithOld($docid, $shipno, $attFileParam);
        if($msgCode ne "FAILED") {
            $filesize = getFileSize( $attFileParam );
            ($docid, $msgDesc) = updateDocumentInPGServer($docid, $shipno, $filesize, $todaysDate, $attFileParam);
        }
    }
    if($docid eq "ERROR" || $msgCode eq "FAILED") {
        $errCode = "FAILED";
        $errDesc = $msgDesc;
        
        return ($errCode, $errDesc);
    } 
    
    my $documentReferenceId = $shipno . "-" . $docid;
    my $absolutePathForTempTXTFile = $tempFolderLocation;
    
    ($msgCode, $msgDesc) = pushDocumentIntoAms($documentReferenceId, $attFileParam, $insertAppendParam, $docid, $docType, $dptParam, $filesize, $branchParam, $shipno, $todaysDate, $absolutePathForTempTXTFile);

    if($msgCode eq "OK") {
        $errCode = $msgCode;
        $errDesc = $msgDesc;
    } elsif ($insertAppendParam eq "INSERT") {
        ($msgCode, $msgDesc) = removeUnsuccessfulRecordFromPGServer($docid);
        if($msgCode ne "OK") {
            $errDesc = $errDesc . $msgDesc;
        }
        $errCode = "FAILED";
    } else {
        $errCode = "FAILED";
        $errDesc = $msgDesc;
    }
    return ($errCode, $errDesc);
}

sub getFileSize {
    my ($givenDocument) = @_;
    
    my $localFileStats = stat( $givenDocument );
    my $filesize = $localFileStats->size; ## size in bytes
    $filesize = $filesize / 1024 ; ## size in KiloBytes
    $filesize = POSIX::floor ( $filesize ); ## without decimals
    
    return $filesize;
}

sub mergeNewDocumentWithOld {
    my ($docid, $shipno, $newDocument) = @_;
    my ($path, $filename, $ext);
    my ($documentReferenceId, $tempOldDocument);
    my $errCode = "OK";
    my $errDesc;
    
    $documentReferenceId = $shipno . "-" . $docid;
    ($path, $filename, $ext) = ($newDocument=~ /^(.*)\/(.*?)\.(.*)$/);   
    $tempOldDocument = "$path/$documentReferenceId.pdf";
    
    ($errCode, $errDesc) = fetchFromAms($documentReferenceId, $tempOldDocument);
    if ($errCode eq "OK") {
        ($errCode, $errDesc) = prependOldDocumentToNew($tempOldDocument, $newDocument);
    } 
        
    return ($errCode, $errDesc);
}

sub prependOldDocumentToNew {
    my ($tempOldDocument, $newDocument) = @_;
    my $newDoc;
    my $errCode = "OK";
    my $errDesc = "successfully completed merging PDF files";
    
    eval{
        $newDoc = CAM::PDF->new($newDocument);
        $newDoc->prependPDF(CAM::PDF->new($tempOldDocument));
        $newDoc->cleansave();
        $newDoc->cleanoutput($newDocument);
    };
    if ($@) {
        $errCode = "FAILED";
        $errDesc = $@;
    }
    return ($errCode, $errDesc);
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

au::com::company::scandocs::pdfExtractionService - provides single method to handle and process given PDF attachment into Scan-Docs 

=head1 SYNOPSIS

  use au::com::company::scandocs::pdfExtractionService;
  processEachPdfAttachment($attachmentFile, $insertAppendFlag, $shipno, $docid, $department, $branch, $docType, $tempFolderLocation, $todaysDate);

=head1 DESCRIPTION

This module was created to help re-use of similar functionality -- thats DRY principle..
For example AQIS docs and ODM Docs both do exactly same thing -- poll mailbox, extract pdf attachment and push into scandocs..
As the name suggests, this module does exactly that thing.. assists in processing of supplied PDF attachment into scan-docs.. 
Now thats KISS principle.. 
to elaborate further, the single public-static method uses other modules and CAM::PDF library to do its work..

Now what this module does not do... its not going to do polling into the mailbox.. why? 
For one, each mailbox is different. Though the polling action is same, reading each mail item one by one is same.
The shipment number extraction method for each mailbox is likely to be different.
also at the end of processing each email fully, one needs to archive that email.. 
All these can be housed in another module or better still be taken care of by respective mailbox's script file.

=head2 EXPORT

None by default.
you have to use the tag ":all"

=head2 DEPENDENCIES

please note that these dependencies must be installed on the linux server where you wish to use this module.. 
the pdfExtractionService module uses the following libraries and modules.. 
    CAM::PDF
    au::com::company::scandocs::ams
    use au::com::company::scandocs::pgService

=head1 METHODS

processEachPdfAttachment($attachmentFile, $insertAppendFlag, $shipno, $docid, $department, $branch, $docType, $tempFolderLocation, $todaysDate);

The method returns back following ($errCode, $errDesc);
If everything goes well the returned error-code is OK; if something goes wrong error-code returned is "FAILED";
error-description will explain briefly what went wrong in case of failure.. the method is designed to handle all error scenarios;


=head2 digging inside.. 

    ..this method derives file parameters from attachment-file;
    ..it calls pgService methods to create or update record in scan_docs table in postgres;
    ..for update scenario, it gets old pdf and merges with given attachment file;
    ..next it pushes pdf file into AMS using ams-service (perl-module);
    ..In case of failure in pushing to AMS, if it was a insert scenario, it takes away record inserted into postgres table.


=head1 SEE ALSO

Mention other useful documentation.
For this section best places are project documents, specifically BRS and Systems Narrative, that will convey the Functional specification / high level design that got made existance of such module necessary



=head1 AUTHOR

Amit Rajpurkar, for E<lt>Aust.Support@company.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Root

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
