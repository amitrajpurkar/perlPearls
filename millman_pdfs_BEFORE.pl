#!/usr/bin/perl -w

use lib '/home/track/lib';

use SCH_DW;

use strict;
use File::Copy;
use File::stat;
use Mail::Sendmail;
use MIME::QuotedPrint;
use MIME::Base64;
use Net::FTP;
use DBI;
use Fcntl ':flock'; # import LOCK_* constants
use Filesys::SmbClient;

my $now_string = localtime;
print "\n\nStarting process millman_pdfs.pl at $now_string \n";

my $imd_local_path = "/export/track/misc/millman_pdfs/imd_pdfs/";
my $eft_local_path = "/export/track/misc/millman_pdfs/eft_pdfs/";
my $millman_host = "edifice.company.int.au";
my $millman_user = "hidingUser";
my $millman_pass = 'dummyPassword';
my $imd_millman_path = '/usr/hidingUser/pdfs/imd_files/';
my $eft_millman_path = '/usr/hidingUser/pdfs/eft_files/';

# ANR (2012-07-02): new global variables for pushing pdf files to AMS
my $amsPdfBaseLocation = "smb://sydams01/ldw_archive/scan_dump_archive/";
my $amsDestLocation = "smb://sydams01/in\$";
my ($amsPdfDestLocation, $pdfFileName, $tempSourceFile, $fileNameForAms);
my $todaysDate;
my $amsUser = "hidingUser";
my $amsPass = "dummyPassword";
my $smb;
my ($localFileStats, $dir_fh, $file_fh, $remote_size, $local_size);
my @remoteFileStats;
my ($pdfTransferFlag, $txtTransferFlag);
my ($docid, $scan, $count, $filesize, $file_contents);
my $numOfFilesProcessed=0;

my $error_count = 0; #keep track of number of errors sent..... stop sending errors after 10

my $verbose = 1;   #set to 1 for extra program output/debugging messages
my %existing;
my ($sftp, $ftp, $country, $branch, $pfile, @files);

my $basedir="/export/track/misc/millman_pdfs";
my $indir;
my $app=$0;
my $error_to="support\@company.com";
my $from="ScriptedApplication\@company.com";

#define postgresql variables
my $sUsername = "hidingUser";
my $sPassword = "dummyPassword";
my $sServer = "dbi:Pg:dbname=track;host=pgserver;port=5432;";
my ($dbh, $sth, $qString, $qString1, $sth1, $sth2, $rows);

eval {
  open(LOCK, ">>$0.lock");
  unless (flock(LOCK,LOCK_EX|LOCK_NB)) {
    print "$0 already running\n";
    exit;
  }

  $dbh = DBI->connect( "$sServer", $sUsername, $sPassword );
  if (!defined $dbh) {
    die "Cannot connect to server: $DBI::errstr\n";
  }
  $smb = new Filesys::SmbClient( username => $amsUser, password => $amsPass );

  get_pdfs();
  &init_for_pdf_transfer();

  process_pdfs("imd_pdfs");
  process_pdfs("eft_pdfs");

  $dbh->disconnect;

  flock(LOCK,LOCK_UN);
  close(LOCK);
};

if ($@) {
  print $@."\n";
  send_email($error_to, $from, "Error: $app", "$@");
}


sub init_for_pdf_transfer(){
    my (
         $second,     $minute,    $hour,
         $dayOfMonth, $month,     $yearOffset,
         $dayOfWeek,  $dayOfYear, $daylightSavings
    ) = localtime();
    my $year = 1900 + $yearOffset;
    $month = $month + 1;
    $todaysDate = sprintf( "%4d%02d%02d", $year, $month, $dayOfMonth );
    my $dirname = $todaysDate;
    
    $amsPdfDestLocation = $amsPdfBaseLocation . $dirname;
}

sub send_email {
  my ($to, $from, $subject, $message, $html) = @_;
  my %mail;

  $mail{'To'} = $to;
  $mail{'From'} = $from;
  $mail{'Message'} = $message;
  $mail{'Subject'} = $subject;
  $mail{'smtp'} = "imap";
  if ($html) {
    $mail{'content-type'} = 'text/html; charset="iso-8859-1"';
  } else {
    $mail{'content-type'} = 'text/plain';
  }
  sendmail(%mail);
}

sub send_files {
  my ($to, $from, $subject, $message, @files) = @_;
  my ($boundary, %mail, $file, $attach_name, $nbytes, $buffer);

  $boundary = "====" . time() . "====";

  $mail{'To'} = $to;
  $mail{'From'} = $from;
  $mail{'Subject'} = $subject;
  $mail{'content-type'} = "multipart/mixed; boundary=\"$boundary\"";
  $mail{'smtp'} = "imap";

  $boundary = '--'.$boundary;

  foreach $file (@files) {
    ($attach_name) = ($file =~ /^.*\/(.*)$/);
    $mail{'body'} .= <<END_OF_FILE_HEADER;
$boundary
Content-Type: text/plain; name="$attach_name"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="$attach_name"

END_OF_FILE_HEADER

    open(INFILE, "$file");
    while ($nbytes = read(INFILE, $buffer, 57)) {
      $mail{'body'} .= encode_base64($buffer);
    }
  }

  $mail{'body'} .= $boundary."--";
  sendmail(%mail) || print "Error: $Mail::Sendmail::error\n";
}

sub get_pdfs {

  $ftp = Net::FTP->new($millman_host, Debug => 0) || die $@;
  $ftp->login($millman_user, $millman_pass) || die $@;
  $ftp->binary() || die $@;


  print "Sub get_millman_pdfs\n";

  get_millman_pdfs($ftp, $imd_local_path, $imd_millman_path);
  get_millman_pdfs($ftp, $eft_local_path, $eft_millman_path);

  #get_millman_pdfs($ftp, $imd_local_path, $test_millman_path);

  $ftp->quit;

}

sub get_millman_pdfs {
  my ($ftp, $lpath, $rpath) = @_;

  my ($err, $lfile, $rfile, $lstat, $rstat);
  my ($rsize, $lsize, $sb);
  my ($filename, $rfile_tr);
  my ($dirlist, $count);

  my $rpath_tr = $rpath."transferred/";
 
  print "Transfering from $rpath to $lpath\n";


  $ftp->cwd($rpath);
  print $rpath."\n";
  my @dir = grep {/\.PDF$/} $ftp->ls(".");

  print "\n";
  print "$rpath no of files = ". scalar(@files) ."\n". join("\n", @files)."\n";;
  print "\n";

  $count = 0; 
  my $total_files = scalar(@dir);

  foreach $pfile (@dir) {
    $count += 1; 

    print "\n".$count."/".$total_files."\n";
    print "File     : ".$pfile."\n";    #eg. "-rw-rw-rw-   1 informix     163 Feb 25 15:10 00001028.txt" if ($verbose);
    print "Filename    : ".$pfile."\n" if ($verbose);    #eg. "00001028.txt"

    $rfile = $rpath . $pfile;
    print "Remote      : ".$rfile."\n" if ($verbose);

    $lfile = $lpath . $pfile;
    print "Local       : ".$lfile."\n" if ($verbose);

    $rfile_tr = $rpath_tr . $pfile;
    print "Transferred : ".$rfile_tr."\n" if ($verbose);

    $rsize = $ftp->size($rfile);
    print "Size        : ".$rsize."\n" if ($verbose);

    print "Getting...  ".$rfile."  to  ".$lfile;
    print "\n";

    $ftp->get($rfile, $lfile);

    if ($sb=stat("$lfile")) {
      $lsize = $sb->size;
    } else {
      $lsize = 0;
    }

    if ($rsize != $lsize) {
      print "DEST FILE INCOMPLETE: $lsize bytes instead of $rsize\n";
      send_email($error_to, $from, "Millman receiving PDFs FTP error transferring file",
      "Host: $ftp\nOperation: GET\n  File: $pfile
      Remote: $rsize\n Local: $lsize\n") if ($error_count < 10);
    } else {
      print "Renaming... ".$rfile."  ...  ".$rfile_tr; 
      $ftp->rename($rfile, $rfile_tr);
    }

    print "\n";
  }
}


sub process_pdfs {
  my ($pdfdir) = @_;
  $indir="$basedir/$pdfdir";
  my ($file, $type);
  my ($mode, $department, $brch);
  my ($doc_type, $shipno, $version, $datetime, $file_type);

  my $doc_date;

  opendir(DIR, $indir) || die "can't opendir $indir: $!";
  foreach $file (grep { -f "$indir/$_" } readdir(DIR)) {
    print "FILE: $file\n";
    $numOfFilesProcessed += 1;

    #IMD_6220221093_01_V01_20120531171102.PDF

    $file =~ /^(\w+)_(\w+)_(\w+)_(\w+)_(\w+)\.(PDF)/;

    $doc_type = $1;
    $shipno = $2;
    $version = $4;
    $datetime = $5;
    $file_type = $6;

    $type = 'Import Declaration';
    if ($version ne 'V01') {
        $type = 'Import Declaration Amendment';
    }
    if ($doc_type eq 'EFT') {
        $type = 'Electronic Funds Transfer Receipt';
    }

    print "File type: $doc_type\n";
    print "Type: $type\n";
    print "Shipment: $shipno\n";
    print "Version: $version\n";
    print "Datetime: $datetime\n";
    print "File extension: $file_type\n";

    $doc_date = (substr ($datetime, 0, 4)."-".substr ($datetime, 4, 2)."-".substr ($datetime, 6, 2));
    print "Date of Document: $doc_date\n"; 

    $qString = "SELECT shpxarea, shpxbra FROM shipx WHERE shpxsndn=?";
    $sth = $dbh->prepare($qString) || die $DBI::errstr;
    $rows = $sth->execute($shipno);
    if ($rows > 0) {
       ($mode, $brch) = $sth->fetchrow;
        $sth->finish;
    } else {
        $sth->finish();
    }
    unless ($rows > 0) {
      print "Can't find shipment $shipno in shipx\n";
      move("$indir/$file", "$indir/heldfiles/$file");
      next;
    }
    print "SHIPMENT: $shipno\n";
    print "MODE: $mode\n";

    if ($mode eq 'AI') {
        $department = 'Air Import';
    } elsif ($mode eq 'SI') {
        $department = 'Sea Import';
    } elsif ($mode eq 'AE') {
        $department = 'Air Export';
    } elsif ($mode eq 'SE') {
        $department = 'Sea Export';
    }

    print "Department: $department\n";
    print "BRANCH: $brch\n";

    $count = 0;
    $filesize = 0;
    $file_contents = "";

    $filesize = -s ("$indir/$file");
    print "File Size is : $filesize\n";


    $dbh->{'AutoCommit'}=0;

    print "File name=$file\n";
    print "File Size=$filesize\n";

    # ANR (2012-07-02):: do not insert blob
    #my $blob = oid2lo(insert_blob($file_contents));

    $qString1 = "INSERT INTO scan_docs(scan,type,department,file_type,file_size,date_scan,branch,shipno,sent_by) VALUES (null,?,?,?,?,?,?,?,?)";
    $sth1 = $dbh->prepare($qString1) || die $DBI::errstr;
    $sth1->execute($type, $department, $file_type, $filesize, $doc_date, $brch, $shipno, $file) || die $DBI::errstr;
    $sth1->finish;
    $dbh->commit;
    
    # ANR (2012-07-02):: read the docid for the new row inserted in scan_docs table
    $qString1 = "SELECT docid from scan_docs where branch = ? and shipno = ? and type = ? and department = ? order by created desc LIMIT 1";
    $sth2 = $dbh->prepare($qString1) || die $DBI::errstr;
    $rows = $sth2->execute($brch, $shipno, $type, $department) || die $DBI::errstr;
    if ($rows > 0) {
       ($docid) = $sth2->fetchrow;
        $sth2->finish;
    } else {
        $docid = "NODOCID";
        $sth2->finish();
    }
    unless ($rows > 0) {
      print "Can't find docid for $shipno in scan_docs\n";
      move("$indir/$file", "$indir/heldfiles/noDocId/$file");
      next;
    }
    $fileNameForAms = $shipno . "-" . $docid;
    
    $pdfTransferFlag = transfer_each_pdf_file($indir, $file, $fileNameForAms);
    $txtTransferFlag = create_transfer_txt_file($docid, $type, $department, $file_type, $filesize, $brch, $shipno, $file, $doc_date, $fileNameForAms);

    if($pdfTransferFlag == 1 && $txtTransferFlag == 1) {
        move("$indir/$file", "$indir/archive/$file");
    } elsif ($docid != "NODOCID") {
        #### if PDF push is not successful, remove the record from PG-scan-docs
    }
  }
}



sub transfer_each_pdf_file{
    my ($sourceLocation, $sourceFile, $destinationFileName) = @_;
    $destinationFileName = $destinationFileName . ".pdf"; 
    
    $dir_fh = $smb->opendir("$amsPdfDestLocation");
    if ( $dir_fh == 0 ) {
        $smb->mkdir( "$amsPdfDestLocation", '0666' );
    }
    $file_fh = $smb->open( ">$amsPdfDestLocation/$destinationFileName", 0666 ) or print "Can't create file:", $!, "\n";
    open( INFILE, "$sourceLocation/$sourceFile" ) or print "Can't open $sourceLocation/$sourceFile\n";
    while ( my $line = <INFILE> ) {
        $smb->write( $file_fh, $line ) or print $!, "\n";
    }
    close(INFILE);
    $smb->close($file_fh);
    $smb->close($dir_fh);
    
    @remoteFileStats = $smb->stat("$amsPdfDestLocation/$destinationFileName");
    $remote_size = $remoteFileStats[7];
    if ( $localFileStats = stat("$sourceLocation/$sourceFile") ) {
        $local_size = $localFileStats->size;
    } else {
        $local_size = 0;
    }
    if ( $remote_size != $local_size ) {
        print "DEST FILE INCOMPLETE: $remote_size bytes instead of $local_size\n\n";
        return 0;
    } else {
        print "FILE TRANSFER success for file $destinationFileName\n\n";
        return 1;
    }
}

sub create_transfer_txt_file{
    my ($docidParam, $typeParam, $departmentParam, $filetypeParam, $filesizeParam, $branchParam, $shipnoParam, $fileParam, $docDateParam, $destinationFileName) = @_;
    $pdfFileName = $todaysDate . "\\" . $destinationFileName . ".pdf";
    $destinationFileName = $destinationFileName . "-I.txt";
    $docDateParam =~ s/-//g; #### Date Format changed from YYYY-MM-DD to YYYYMMDD
    
    $tempSourceFile="/home/track/misc/millman_pdfs/scan_docs_txt_files/$destinationFileName";
    open(OUT, ">$tempSourceFile") or print "Could not write to $tempSourceFile\n";
    print OUT "action\nINSERT\n";
    print OUT "docid\n$docidParam\n";
    print OUT "type\n$typeParam\n";
    print OUT "department\n$departmentParam\n";
    print OUT "file_type\n$filetypeParam\n";
    print OUT "file_size\n$filesizeParam\n";
    print OUT "branch\n$branchParam\n";
    print OUT "shipno\n$shipnoParam\n";
    print OUT "created\n$todaysDate\n";
    print OUT "updated\n$todaysDate\n";
    print OUT "sentby\n$fileParam\n";      #### NeoDocs ignores this value.
    print OUT "date_scan\n$todaysDate\n";  #### NeoDocs uses this date to create value for system_filename column
    print OUT "file_name\n$pdfFileName\n";
    close(OUT);
    
    $file_fh = $smb->open( ">$amsDestLocation/$destinationFileName", 0666 ) or print "Can't create file:", $!, "\n";
    open( INFILE, "$tempSourceFile" ) or print "Can't open $tempSourceFile\n";
    while ( my $line = <INFILE> ) {
        $smb->write( $file_fh, $line ) or print $!, "\n";
    }
    close(INFILE);
    $smb->close($file_fh);
    
    @remoteFileStats = $smb->stat("$amsDestLocation/$destinationFileName");
    $remote_size = $remoteFileStats[7];
    if ( $localFileStats = stat("$tempSourceFile") ) {
        $local_size = $localFileStats->size;
    } else {
        $local_size = 0;
    }
    unlink($tempSourceFile); #### delete temp file after use -- successful or not

    if ( $remote_size != $local_size ) {
        print "DEST FILE INCOMPLETE: $remote_size bytes instead of $local_size\n\n";
        return 0;
    } else {
        print "FILE TRANSFER success for file $destinationFileName\n\n";
        return 1;
    }
}

