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
use Fcntl ':flock'; # import LOCK_* constants
use au::com::company::scandocs::documentService qw( :all );
use au::com::company::scandocs::pgService qw( :all );
use Log::Log4perl;

my $now_string = localtime;
my $imd_local_path = "/export/track/misc/millman_pdfs/imd_pdfs/";
my $eft_local_path = "/export/track/misc/millman_pdfs/eft_pdfs/";
my $millman_host = "edifice.company.int.au";
my $millman_user = "hidingUser";
my $millman_pass = 'dummyPassword';
my $imd_millman_path = '/usr/hidingUser/pdfs/imd_files/';
my $eft_millman_path = '/usr/hidingUser/pdfs/eft_files/';

my $numOfFilesProcessed=0;
my $error_count = 0; #keep track of number of errors sent..... stop sending errors after 10
my $verbose = 1;   #set to 1 for extra program output/debugging messages
my %existing;
my ($sftp, $ftp, $country, $branch, $pfile, @files);

my $basedir="/export/track/misc/millman_pdfs";
my $codedir="/usr/home/track/misc/millman_pdfs";
my $indir;
my $app=$0;
my $error_to="support\@company.com";
my $from="ScriptedApplication\@company.com";
Log::Log4perl->init("$codedir/log.conf");
my $logger = Log::Log4perl->get_logger("Millman::PDFs");
$logger->error( "\n\n---------------Starting process millman_pdfs.pl at $now_string -----------------\n");

open(LOCK, ">>$0.lock");
eval {
  unless (flock(LOCK,LOCK_EX|LOCK_NB)) {
    $logger->error("$0 already running\n");
    exit;
  }

  get_pdfs();

  process_pdfs("imd_pdfs");
  process_pdfs("eft_pdfs");

  flock(LOCK,LOCK_UN);
  close(LOCK);
  unlink("$app.lock");
};
if ($@) {
    flock(LOCK,LOCK_UN);
    close(LOCK);
    unlink("$app.lock");
    $logger->error( $@ . "\n" );
    send_email($error_to, $from, "Error: $app", "$@");
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
  sendmail(%mail) || $logger->error("Error: $Mail::Sendmail::error\n");
}

sub get_pdfs {

  $ftp = Net::FTP->new($millman_host, Debug => 0) || die $@;
  $ftp->login($millman_user, $millman_pass) || die $@;
  $ftp->binary() || die $@;


  $logger->debug("Sub get_millman_pdfs\n");

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
 
  $logger->debug("Transfering from $rpath to $lpath\n");


  $ftp->cwd($rpath);
  $logger->debug( $rpath."\n");
  my @dir = grep {/\.PDF$/} $ftp->ls(".");

  $logger->debug( "\n $rpath no of files = ". scalar(@files) ."\n". join("\n", @files)."\n\n" );

  $count = 0; 
  my $total_files = scalar(@dir);

  foreach $pfile (@dir) {
    $count += 1; 

    $logger->debug("\n".$count."/".$total_files."\n");
    $logger->debug("File     : ".$pfile."\n");    #eg. "-rw-rw-rw-   1 informix     163 Feb 25 15:10 00001028.txt" if ($verbose);
    $logger->debug("Filename    : ".$pfile."\n")  if ($verbose);    #eg. "00001028.txt"

    $rfile = $rpath . $pfile;
    $logger->debug("Remote      : ".$rfile."\n")  if ($verbose);

    $lfile = $lpath . $pfile;
    $logger->debug("Local       : ".$lfile."\n")  if ($verbose);

    $rfile_tr = $rpath_tr . $pfile;
    $logger->debug("Transferred : ".$rfile_tr."\n")  if ($verbose);

    $rsize = $ftp->size($rfile);
    $logger->debug("Size        : ".$rsize."\n")  if ($verbose);

    $logger->debug("Getting...  ".$rfile."  to  ".$lfile . " \n");

    $ftp->get($rfile, $lfile);

    if ($sb=stat("$lfile")) {
      $lsize = $sb->size;
    } else {
      $lsize = 0;
    }

    if ($rsize != $lsize) {
      $logger->debug("DEST FILE INCOMPLETE: $lsize bytes instead of $rsize\n");
      send_email($error_to, $from, "Millman receiving PDFs FTP error transferring file",
      "Host: $ftp\nOperation: GET\n  File: $pfile
      Remote: $rsize\n Local: $lsize\n") if ($error_count < 10);
    } else {
      $logger->debug("Renaming... " . $rfile . "  ...  " . $rfile_tr ); 
      $ftp->rename($rfile, $rfile_tr);
    }

    $logger->debug( "\n");
  }
}

sub process_pdfs {
  my ($pdfdir) = @_;
  $indir="$basedir/$pdfdir";
  my $tmpAmsTxtDir = "$codedir/scan_docs_txt_files";
  my ($file, $type, $absolutePathToSourcePdf);
  my ($department, $brch, $doc_type, $docid, $shipno, $version, $datetime, $file_type, $insertAppendFlag);
  my ($msgCode, $msgDesc);
  my $doc_date;

  opendir(DIR, $indir) || $logger->logdie( "can't opendir $indir: $!" );
  foreach $file (grep { -f "$indir/$_" } readdir(DIR)) {
    $logger->debug( "FILE: $file \n" );
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
    $logger->debug( "File type: $doc_type \n" );
    $logger->debug( "Type: $type \n" );
    $logger->debug( "Shipment: $shipno \n" );
    $logger->debug( "Version: $version \n" );
    $logger->debug( "Datetime: $datetime \n" );
    $logger->debug( "File extension: $file_type \n");

    $doc_date = (substr ($datetime, 0, 4)."-".substr ($datetime, 4, 2)."-".substr ($datetime, 6, 2));
    $logger->debug( "Date of Document: $doc_date\n" ); 
    
    # ANR (2013-01-11):: using local-perl-module
    ($docid, $brch, $department, $insertAppendFlag, $msgDesc) = findDocumentInPGServer($shipno, $type); 
#    $logger->debug( "docid: $docid \n" );
#    $logger->debug( "brch: $brch \n" );
#    $logger->debug( "department: $department \n" );
#    $logger->debug( "insertAppendFlag: $insertAppendFlag \n" );
#    $logger->debug( "msgDesc: $msgDesc \n" );
    if($docid eq "ERROR") {
        $logger->error( "problem with shipno: $msgDesc\n" );
        move("$indir/$file", "$indir/heldfiles/$file");
        next;
    }
    $logger->debug( "SHIPMENT: $shipno\n" );
    $logger->debug( "Department: $department\n" );
    $logger->debug( "BRANCH: $brch\n" );
    $absolutePathToSourcePdf = "$indir/$file";

    # ANR (2013-01-11):: using local-perl-module
    ($msgCode, $msgDesc) = createDocumentInScandocs($absolutePathToSourcePdf, $shipno, $docid, $department, $brch, $type, $tmpAmsTxtDir, $doc_date);

    if ($msgCode eq "OK") {
        $logger->error( "successfully created $file in scandocs \n");
        move("$indir/$file", "$indir/archive/$file");
    } else {
        $logger->error( "$msgDesc \n");
        move("$indir/$file", "$indir/heldfiles/$file");
    }
  }
  $logger->error("numOfFilesProcessed = $numOfFilesProcessed \n");
  $logger->error("completed processing $pdfdir  ***********************  \n");
}


