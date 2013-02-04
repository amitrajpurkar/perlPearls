package au::com::company::scandocs::documentService;

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

# This allows declaration	use au::com::company::scandocs::documentService ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
    createDocumentInScandocs
    overwriteDocumentInScandocs
    appendDocumentInScandocs
    viewDocumentFromScandocs
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '1.00';


# Preloaded methods go here.

sub createDocumentInScandocs {
    my ($absolutePathToSourcePdf, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate) = @_;
    my ($msgCode, $msgDesc, $errCode, $errDesc);
    my $insertAppendParam = "INSERT";
    
    my $localFileStats = stat( $absolutePathToSourcePdf );
    my $filesize = $localFileStats->size; ## size in bytes
    $filesize = $filesize / 1024 ; ## size in KiloBytes
    $filesize = POSIX::floor ( $filesize ); ## without decimals
    $msgCode = "OK";
    
    ($docid, $msgDesc) = createDocumentInPGServer($shipno, $filesize, $todaysDate, $absolutePathToSourcePdf, $dptParam, $branchParam, $docType);
    if($docid eq "ERROR") {
        $errCode = "FAILED";
        $errDesc = $msgDesc;
        
        return ($errCode, $errDesc);
    } 
    
    my $documentReferenceId = $shipno . "-" . $docid;
    my $absolutePathForTempTXTFile = $tempFolderLocation;
    
    ($msgCode, $msgDesc) = pushDocumentIntoAms($documentReferenceId, $absolutePathToSourcePdf, $insertAppendParam, $docid, $docType, $dptParam, $filesize, $branchParam, $shipno, $todaysDate, $absolutePathForTempTXTFile);

    if($msgCode eq "OK") {
        $errCode = $msgCode;
        $errDesc = $msgDesc;
    } else {
        $errCode = "FAILED";
        $errDesc = $msgDesc;
        ($msgCode, $msgDesc) = removeUnsuccessfulRecordFromPGServer($docid);
        if($msgCode ne "OK") {
            $errDesc = $errDesc . $msgDesc;
        }
    } 
    return ($errCode, $errDesc);
}

sub overwriteDocumentInScandocs {
    my ($absolutePathToSourcePdf, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate) = @_;
    my ($msgCode, $msgDesc, $errCode, $errDesc);
    my $insertAppendParam = "UPDATE";
    
    my $localFileStats = stat( $absolutePathToSourcePdf );
    my $filesize = $localFileStats->size; ## size in bytes
    $filesize = $filesize / 1024 ; ## size in KiloBytes
    $filesize = POSIX::floor ( $filesize ); ## without decimals
    $msgCode = "OK";
    
    ($docid, $msgDesc) = updateDocumentInPGServer($docid, $shipno, $filesize, $todaysDate, $absolutePathToSourcePdf);
    if($docid eq "ERROR" || $msgCode eq "FAILED") {
        $errCode = "FAILED";
        $errDesc = $msgDesc;
        
        return ($errCode, $errDesc);
    } 
    
    my $documentReferenceId = $shipno . "-" . $docid;
    my $absolutePathForTempTXTFile = $tempFolderLocation;
    
    ## no merging with existing PDF is needed as intention is to overwrite.
    ($msgCode, $msgDesc) = pushDocumentIntoAms($documentReferenceId, $absolutePathToSourcePdf, $insertAppendParam, $docid, $docType, $dptParam, $filesize, $branchParam, $shipno, $todaysDate, $absolutePathForTempTXTFile);
    $errCode = $msgCode;
    $errDesc = $msgDesc;

    return ($errCode, $errDesc);
}

sub appendDocumentInScandocs {
    my ($absolutePathToSourcePdf, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate) = @_;
    my ($msgCode, $msgDesc, $errCode, $errDesc);
    my $insertAppendParam = "UPDATE";
    
    my $localFileStats = stat( $absolutePathToSourcePdf );
    my $filesize = $localFileStats->size; ## size in bytes
    $filesize = $filesize / 1024 ; ## size in KiloBytes
    $filesize = POSIX::floor ( $filesize ); ## without decimals
    $msgCode = "OK";
    
    
    ($docid, $msgDesc) = updateDocumentInPGServer($docid, $shipno, $filesize, $todaysDate, $absolutePathToSourcePdf);
    if($docid ne "ERROR") {
        ($msgCode, $msgDesc) = mergeNewDocumentWithOld($docid, $shipno, $absolutePathToSourcePdf);
    }
    if($docid eq "ERROR" || $msgCode eq "FAILED") {
        $errCode = "FAILED";
        $errDesc = $msgDesc;
        
        return ($errCode, $errDesc);
    } 
    
    my $documentReferenceId = $shipno . "-" . $docid;
    my $absolutePathForTempTXTFile = $tempFolderLocation;
    
    ($msgCode, $msgDesc) = pushDocumentIntoAms($documentReferenceId, $absolutePathToSourcePdf, $insertAppendParam, $docid, $docType, $dptParam, $filesize, $branchParam, $shipno, $todaysDate, $absolutePathForTempTXTFile);
    $errCode = $msgCode;
    $errDesc = $msgDesc;

    return ($errCode, $errDesc);
}

sub viewDocumentFromScandocs {
    my ($docid, $shipno, $tempFolderLocation) = @_;
    my ($documentReferenceId, $tempOldDocument);
    my $errCode = "OK";
    my $errDesc;
    
    $documentReferenceId = $shipno . "-" . $docid;
    $tempOldDocument = "$tempFolderLocation/$documentReferenceId.pdf";
    
    ($errCode, $errDesc) = fetchFromAms($documentReferenceId, $tempOldDocument);
    return ($errCode, $errDesc);
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

au::com::company::scandocs::documentService - provides single module for all features expected in Scandocs

=head1 SYNOPSIS

  use au::com::company::scandocs::documentService;
  createDocumentInScandocs($absolutePathToSourcePdf, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate);
  overwriteDocumentInScandocs($absolutePathToSourcePdf, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate);
  appendDocumentInScandocs($absolutePathToSourcePdf, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate);
  viewDocumentFromScandocs($docid, $shipno, $tempFolderLocation);

=head1 DESCRIPTION

This module was created to help re-use of similar functionality -- thats DRY principle..
For example, on posti server, AQIS docs and ODM Docs both do exactly same thing -- poll mailbox, extract pdf attachment and push into scandocs..
Then on proc1, millman_pdfs and tl_shipdocs both push documents into scandocs.. 
As the name suggests, this module does exactly that thing.. assists in processing of supplied PDF attachment into scan-docs.. 
Now thats KISS principle.. to elaborate further, as expected for scandocs module, it allows caller to create, overwrite, append and view documents into/from scandocs..


=head2 EXPORT

None by default.
you have to use the tag ":all"


=head2 DEPENDENCIES

please note that these dependencies must be installed on the linux server where you wish to use this module.. 
the documentService module uses the following libraries and modules.. 
    CAM::PDF
    au::com::company::scandocs::ams
    au::com::company::scandocs::pgService

=head1 METHODS

common to all methods...

    ..The method returns back following ($errCode, $errDesc);
    ..If everything goes well the returned error-code is OK; if something goes wrong error-code returned is "FAILED";
    ..Error-description will explain briefly what went wrong in case of failure.. the method is designed to handle all error scenarios;


createDocumentInScandocs($absolutePathToSourcePdf, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate);

    as the name suggests, it creates a new document in scandocs...
    its the callers responsibility to check before-hand if document exists in pgserver's scan_docs table... only then should the caller invoke this method..
    the method internally adds record in pgserver (scan_docs table) and pushes document (pdf + txt) in AMS
    in case of failure in pushing to AMS, this method makes sure the entry in PGServer is cleared off.

overwriteDocumentInScandocs($absolutePathToSourcePdf, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate);

    as the name suggests, it over-writes an existing document in scandocs...
    its the callers responsibility to check before-hand that the document exists in pgserver's scan_docs table... 
    also its the callers responsibility to wisely choose between overwrite and append functions as per the business needs..
    the method internally updates record in pgserver (scan_docs table) and places new PDF in AMS; the TXT file push into AMS updates the database record in AMS.

appendDocumentInScandocs($absolutePathToSourcePdf, $shipno, $docid, $dptParam, $branchParam, $docType, $tempFolderLocation, $todaysDate);

    as the name suggests, it appends a new document to an existing one in scandocs...
    its the callers responsibility to check before-hand that the document exists in pgserver's scan_docs table... 
    the method internally updates record in pgserver (scan_docs table) and pushes new merged document (pdf + txt) in AMS

viewDocumentFromScandocs($docid, $shipno, $tempFolderLocation);

    as the name suggests, it provides a document from scandocs to the caller...
    its the callers responsibility to check before-hand if parameters supplied are valid.. 
    note that this method is internally making a call to an http-service on AMS.. 
    so the success corresponds to a http response code of 200


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
