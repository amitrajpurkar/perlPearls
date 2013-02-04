package au::com::company::scandocs::pgService;

use 5.008008;
use strict;
use warnings;

use DBI;
use Scalar::Util qw(looks_like_number);

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use au::com::company::scandocs::pgService ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
    findDocumentInPGServer
    createDocumentInPGServer
    updateDocumentInPGServer
    removeUnsuccessfulRecordFromPGServer
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '1.00';

# postgresql related class variables
my $sUsername = "booka";
my $sPassword = "aiii";
my $sServer = "dbi:Pg:dbname=track;host=pgserver;port=5432;";
my ($dbh, $sth, $qString, $rows);


# Preloaded methods go here.

sub findDocumentInPGServer{
    my ($shipnoParam, $docTypeParam) = @_;
    my ($docid, $mode, $branch, $department, $insertAppendFlag);
    my $mgsDesc;
    
    
    $qString = "SELECT shpxarea, shpxbra FROM shipx WHERE shpxsndn = '$shipnoParam' ";
    eval {
        if(not looks_like_number($shipnoParam)){
            die("Error:: supplied shipment $shipnoParam is not numeric \n");
        }
        $dbh = DBI->connect( "$sServer", $sUsername, $sPassword ) or die("Error: Cannot open database-connection: $DBI::errstr\n");
        $sth = $dbh->prepare($qString) or die( $DBI::errstr );
        $rows = $sth->execute();
        if ($rows > 0) {
           ($mode, $branch) = $sth->fetchrow;
            $sth->finish;
        } else {
            $sth->finish;
        }
        unless ($rows > 0) {
          die("Error:: Can't find shipment $shipnoParam in shipx\n");
        }
        if ($mode eq 'AI') {
            $department = 'Air Import';
        } elsif ($mode eq 'SI') {
            $department = 'Sea Import';
        } elsif ($mode eq 'AE') {
            $department = 'Air Export';
        } elsif ($mode eq 'SE') {
            $department = 'Sea Export';
        }
    
        $qString = "SELECT docid from scan_docs where branch = ? and shipno = ? and type = ? and department = ? order by created desc LIMIT 1";
        $sth = $dbh->prepare($qString) or die( $DBI::errstr );
        $rows = $sth->execute($branch, $shipnoParam, $docTypeParam, $department) or die( $DBI::errstr );
        if ($rows > 0) {
           ($docid) = $sth->fetchrow;
            $sth->finish;
            $insertAppendFlag = "UPDATE";
        } else {
            $docid = "NODOCID";
            $sth->finish();
            $insertAppendFlag = "INSERT";
        }
        $dbh->disconnect;
        $mgsDesc = "Successfully completed executing findDocumentInPGServer";
    };
    if ($@) {
        if (defined $dbh) {
            $dbh->disconnect;
        }
        $docid = "ERROR";
        $mgsDesc = $@;
    }
    
    return ($docid, $branch, $department, $insertAppendFlag, $mgsDesc);
}

sub createDocumentInPGServer{
    my ($shipnoParam, $filesizeParam, $dateParam, $filenameParam, $dptParam, $branchParam, $docTypeParam) = @_;
    my $docid;
    my $mgsDesc;
    
    $qString = "INSERT INTO scan_docs(scan,type,department,file_type,file_size,date_scan,branch,shipno,sent_by) VALUES (null,?,?,'pdf',?,?,?,?,?)";
    eval {
        $dbh = DBI->connect( "$sServer", $sUsername, $sPassword ) or die("Error: Cannot open database-connection: $DBI::errstr\n");
        
        $dbh->{'AutoCommit'} = 1;
        $sth = $dbh->prepare($qString) or die( $DBI::errstr );
        $sth->execute($docTypeParam, $dptParam, $filesizeParam, $dateParam, $branchParam, $shipnoParam, "pgService perl module adding File: $filenameParam") or die( $DBI::errstr );
        $sth->finish;
    
        $qString = "SELECT docid from scan_docs where branch = ? and shipno = ? and type = ? and department = ? order by created desc LIMIT 1";
        $sth = $dbh->prepare($qString) or die( $DBI::errstr );
        $rows = $sth->execute($branchParam, $shipnoParam, $docTypeParam, $dptParam) or die( $DBI::errstr );
        if ($rows > 0) {
           ($docid) = $sth->fetchrow;
            $sth->finish;
            $mgsDesc = "Successfully created new document record for $docid in PGServer";
        } else {
            $docid = "ERROR";
            $sth->finish();
            $mgsDesc = "Something wrong, cannot find the record just inserted :: $branchParam, $shipnoParam, $docTypeParam, $dptParam ";
        }
        $dbh->disconnect;
    };
    if ($@) {
        if (defined $dbh) {
            $dbh->disconnect;
        }
        $docid = "ERROR";
        $mgsDesc = $@;
    }

    return ($docid, $mgsDesc);
}

sub updateDocumentInPGServer {
    my ($docidParam, $shipnoParam, $filesizeParam, $dateParam, $filenameParam) = @_;
    my $mgsDesc;
    
    $qString = "UPDATE scan_docs set scan = null, date_scan = ? , sent_by = ?, file_size = ? where docid = ? and shipno = ? ";
    eval {
        $dbh = DBI->connect( "$sServer", $sUsername, $sPassword ) or die("Error: Cannot open database-connection: $DBI::errstr\n");
        
        $dbh->{'AutoCommit'} = 1;
        $sth = $dbh->prepare($qString) or die( $DBI::errstr );
        $sth->execute( $dateParam, "pgService perl module appending File: $filenameParam", $filesizeParam, $docidParam, $shipnoParam) or die( $DBI::errstr );
        $sth->finish;
        $dbh->disconnect;
        $mgsDesc = "Successfully updated document record for $docidParam in PGServer";
    };
    if ($@) {
        if (defined $dbh) {
            $dbh->disconnect;
        }
        $mgsDesc = $@;
    }
    
    return ($docidParam, $mgsDesc);
}

sub removeUnsuccessfulRecordFromPGServer{
    my ($docidParam) = @_;
    my $mgsDesc;
    my $msgCode;
    
    $qString = "DELETE from scan_docs where docid = ?";
    eval {
        $dbh = DBI->connect( "$sServer", $sUsername, $sPassword ) or die("Error: Cannot open database-connection: $DBI::errstr\n");
        
        $dbh->{'AutoCommit'} = 1;
        $sth = $dbh->prepare($qString) or die( $DBI::errstr );
        $sth->execute( $docidParam) or die( $DBI::errstr );
        $sth->finish;
        $dbh->disconnect;
        $msgCode = 1;
        $mgsDesc = "Successfully removed document record for $docidParam from PGServer";
    };
    if ($@) {
        if (defined $dbh) {
            $dbh->disconnect;
        }
        $mgsDesc = $@;
        $msgCode = 0;
    }
    
    return ($msgCode, $mgsDesc);
}


1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

au::com::company::scandocs::pgService - houses reusable sub-routines related to ScanDocs inter-acting with PGServer database

=head1 SYNOPSIS

  use au::com::company::scandocs::pgService qw( :all );
  findDocumentInPGServer($shipno, $docType);
  createDocumentInPGServer($shipno, $filesize, $date, $filename, $department, $branch, $docType);
  updateDocumentInPGServer($docid, $shipno, $filesize, $date, $sentByMsg);
  removeUnsuccessfulRecordFromPGServer($docid);

=head1 DESCRIPTION

Stub documentation for au::com::company::scandocs::pgService, created by h2xs. 

This module has been created to help maximize reuse of tried and tested CRUD sub-routines for ScanDocs related to PGServer.
Developers should be able to re-use this module across all LDW linux servers like proc1, posti, etc seamlessly.

=head2 EXPORT

None by default.

=head1 METHODS

=over 4

=item * common-to-all-methods;

To get access for any method/sub-routine use import tag ':all'
This method opens DB connection and closes it at the end;

=item * findDocumentInPGServer($shipno, $docType);

This method returns a list of four values ($docid, $branch, $department, $insertAppendFlag);
In case the document for supplied shipment number and document type exists, returned DOCID has valid value else it gives a string "NODOCID";

=item * createDocumentInPGServer($shipno, $filesize, $date, $filename, $department, $branch, $docType);

This method inserts a record in scan_docs table of PGServer database;
It returns back a list of two values ($docid, $mgsDesc) related to the record it creates;
In case of problems docid value returned is "ERROR" and msgDesc tells what happened;

=item * updateDocumentInPGServer($docid, $shipno, $filesize, $date, $sentByMsg);

This method updates a record in scan_docs table of PGServer database for the values supplied;
It returns back the DOCID of the record it updates;

=item * removeUnsuccessfulRecordFromPGServer($docid);

This method deletes a record in scan_docs table of PGServer database for the docid supplied;
It returns back int value 1 if everything completes successfully;
This method is to be used when PDF/TXT transfer to AMS for a new record fails

=back


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
