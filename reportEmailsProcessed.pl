#!/usr/bin/perl -w

BEGIN { unshift @INC, ".." }    # to test MIME:: stuff before installing it!

require 5.001;

use strict;
use MIME::Parser;
use MIME::Base64;
use MIME::QuotedPrint;
use File::Copy;
use File::Path;
use File::stat;
use Getopt::Std;
use Mail::Sendmail;
use Fcntl ':flock'; # import LOCK_* constants
use Log::Log4perl;
use File::DirList;
use Scalar::Util qw(looks_like_number);
use Spreadsheet::WriteExcel;


# qmail-email related class variables
my $BASE_DIR="/export/email/domino/home/aqis_docs";
my $CODE_DIR="$BASE_DIR/code";
my $APP = "$CODE_DIR/reportAqisEmailsProcessed.pl";
my $ARCHIVE_DIR="$BASE_DIR/archive/success";
my $HELD_DIR="$BASE_DIR/archive/held";
my $TO="amit.rajpurkar\@dbschenker.com";
my $FROM="aqis_docs\@domino.schenker.com.au";
my $WORKBOOK;
my $EXCELFILE = "$CODE_DIR/aqisEmailReport.xls";

 
# Logger Configuration in a string ...
my $conf = q(
  log4perl.category.Aqis.Listing     = INFO, Logfile
 
  log4perl.appender.Logfile          = Log::Log4perl::Appender::File
  log4perl.appender.Logfile.filename = lastReceivedEmailsHeldInArchive.log
  log4perl.appender.Logfile.layout   = Log::Log4perl::Layout::PatternLayout
  log4perl.appender.Logfile.layout.ConversionPattern = [%d] %F %L %m%n
);
 
# ... passed as a reference to init()
#Log::Log4perl::init( \$conf );

# untaint the PATH... doesn't do any real validation
my $envpath = $ENV{'PATH'};
$envpath =~ /^(.*)$/;
$ENV{'PATH'} = $1;
my $TODAYS_DATE;

#my $logger = Log::Log4perl->get_logger("Aqis::Listing");
my $now_string = localtime;
#------------------------------------------------------------
#       Start executing the script
#------------------------------------------------------------
eval {
    print( "Triggering script at $now_string \n" );
    my $numberOfArgumentsPassed = $#ARGV + 1;
    my $msgCountLimit = $ARGV[0];
    if(not looks_like_number($msgCountLimit)) {$msgCountLimit = 50;}
    
    &createPrepareReport();
    &pollArchivedir($msgCountLimit, $ARCHIVE_DIR);
    &pollArchivedir($msgCountLimit, $HELD_DIR);
    if (defined $WORKBOOK) {
        $WORKBOOK->close();
    }
    &email_excel();
    
};
if ($@) {
#    $logger->error( "ERROR:: " . $@ );
    print( "ERROR:: " . $@ );
    sendEmail("Error from: $APP", "$@");
}
#------------------------------------------------------------
#       End of script
#------------------------------------------------------------

sub createPrepareReport {
    ## no need of parameters.. create std report in current directory
    $WORKBOOK  = Spreadsheet::WriteExcel->new($EXCELFILE);
    my $successSheet = $WORKBOOK->add_worksheet('Successful');
    my $FailedSheet = $WORKBOOK->add_worksheet('NotSuccessful');
    
    my $desired_bg_color = $WORKBOOK->set_custom_color(40, 255, 235, 156);
    my $desired_font_color = $WORKBOOK->set_custom_color(41, 156, 101, 0);
    
    # Create a format for the column headings
    my $header = $WORKBOOK->add_format();
    $header->set_bold();
    $header->set_size(12);
    $header->set_color($desired_font_color);
    $header->set_bg_color($desired_bg_color);
    $header->set_top(6);
    $header->set_bottom(6);
    
    $successSheet->set_column('A:F', 30); ## set column width
    $FailedSheet->set_column('A:F', 30); ## set column width
    
    # Write out the data
    $successSheet->write(0, 0, 'Email',$header);
    $successSheet->write(0, 1, 'Date',  $header);
    $successSheet->write(0, 2, 'Subject', $header);
    $successSheet->write(0, 3, 'From', $header);
    $successSheet->write(0, 4, 'To', $header);
    $successSheet->write(0, 5, 'Attachments', $header);

    $FailedSheet->write(0, 0, 'Email',$header);
    $FailedSheet->write(0, 1, 'Date',  $header);
    $FailedSheet->write(0, 2, 'Subject', $header);
    $FailedSheet->write(0, 3, 'From', $header);
    $FailedSheet->write(0, 4, 'To', $header);
    $FailedSheet->write(0, 5, 'Attachments', $header);
    
}

sub pollArchivedir {
    my ($msgCountLimit, $pollingDir) = @_;
  # Sanity:
  (-w ".") or die "pwd not writable...";
  my $message_file;
  my $returnFlag;

  opendir(DIR, $pollingDir) or die("cannot open $pollingDir \n"); ## NOTE: these "die" messages get logged when caught by top-level method
  my @new_messages = grep { -f "$pollingDir/$_" } readdir(DIR); 
  my $numOfMsgFound = @new_messages;

  my $noOfMsgProcessed = 0;
  foreach $message_file (@new_messages) {
      ++$noOfMsgProcessed;
      $returnFlag = processEachEmail($message_file, $pollingDir, $noOfMsgProcessed) or die ("problem processing email..");
  }
  closedir(DIR);
  return "OK";
}


sub processEachEmail {
    my ($msgFileParam, $pollingDir, $rowNum) = @_;
    my ($path, $filename, $ext);
    my ($parser, $msgdir, $entity, $attachmentFile);
    my $printingSheet;
    
    $parser = new MIME::Parser;
    $msgdir = "$BASE_DIR/archive/listingArchivedMails";
    if(-d $msgdir) {
        rmtree ($msgdir);
    } 
    mkdir $msgdir,0755 or die("couldn't make $msgdir $! \n" );
    $parser->output_dir("$msgdir");

    # Parse an input stream:
    open FILE, "<", "$pollingDir/$msgFileParam" or die("couldn't open $msgFileParam \n") ;
    $entity = $parser->read(\*FILE) or
    &sendEmail("Error: Couldn't open email for reading",
                "There is a problem with the last email received. It cannot be processed.
                 Check the last email to confirm this.\n Message from $APP");
    close FILE;
    
    if ( rindex($pollingDir, "success") != -1) {
        $printingSheet = $WORKBOOK->sheets(0);
    } else {
        $printingSheet = $WORKBOOK->sheets(1);
    }
    
    my $emailDate = $entity->head->get('Date');
    my $emailSubject = $entity->head->get('Subject');
    my $emailFrom = $entity->head->get('From');
    my $emailTo = $entity->head->get('To');
    $emailDate =~ s/^\s+//;
    $emailDate =~ s/\s+$//;
    $emailSubject =~ s/^\s+//;
    $emailSubject =~ s/\s+$//;
    $emailFrom =~ s/^\s+//;
    $emailFrom =~ s/\s+$//;
    $emailTo =~ s/^\s+//;
    $emailTo =~ s/\s+$//;
    my $emailAttachments = "";
    
#    $emailInformation = "| Email | $msgFileParam | Date | $emailDate | Subject | $emailSubject | From | $emailFrom | To | $emailTo | attachments | ";

    foreach $attachmentFile (<$msgdir/*>) {
      $attachmentFile =~ /^(.*)$/;   # this is to make taint checking shutup
      $attachmentFile = $1;
      ($path, $filename, $ext) = ($attachmentFile=~ /^(.*)\/(.*?)\.(.*)$/);   #get the file extension
      $emailAttachments .= "$filename.$ext | ";

    }
    
    $printingSheet->write($rowNum, 0, $msgFileParam);
    $printingSheet->write($rowNum, 1, $emailDate);
    $printingSheet->write($rowNum, 2, $emailSubject);
    $printingSheet->write($rowNum, 3, $emailFrom);
    $printingSheet->write($rowNum, 4, $emailTo);
    $printingSheet->write($rowNum, 5, $emailAttachments);
    
    rmtree ($msgdir);
    return "OK"; 
}

sub sendEmail {
  my ($subject,$message) = @_;
  my %mail;

  $mail{'To'} = $TO;
  $mail{'From'} = $FROM;
  $mail{'Message'} = $message;
  $mail{'Subject'} = $subject;
  $mail{'smtp'} = "imap";
  $mail{'content-type'} = 'text/html; charset="iso-8859-1"';

  sendmail(%mail);
}

sub email_excel()
{
   my (
         $second,     $minute,    $hour,
         $dayOfMonth, $month,     $yearOffset,
         $dayOfWeek,  $dayOfYear, $daylightSavings
    ) = localtime();
    my $year = 1900 + $yearOffset;
    $month = $month + 1;
    my ($date) = sprintf( "%02d\/%02d\/%04d", $year, $month, $dayOfMonth );

  my %mail;
  my $boundary = "====" . time() . "====";
  my $message = "Please find report attached.\n";

  $mail{'To'} =  $TO; 
#  $mail{'Cc'} =  "kristy.winchester\@dbschenker.com"; 
  $mail{'From'} = $FROM;
  $mail{'Subject'} = "AQIS Email Report  - $date";
  $mail{'content-type'} = "multipart/mixed; boundary=\"$boundary\"";
  $mail{'Precedence'} = "bulk";
  $mail{'smtp'} = "imap";
  
  $mail{'body'} = encode_qp($message);

  $boundary = '--'.$boundary;

  $mail{'body'} .= <<END_OF_FILE_HEADER;
$boundary
Content-Type: text/plain; charset=us-ascii
Content-Transfer-Encoding: 7bit 

$message

$boundary
Content-Type: application/vnd.ms-excel; name="$EXCELFILE"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="$EXCELFILE"

END_OF_FILE_HEADER

  open(FILE, $EXCELFILE) or die "$!";
  binmode(FILE);
  my $buf;
  while (read(FILE, $buf, 60*57)) {
    $mail{'body'} .= encode_base64($buf);
  }
  $mail{'body'} .= $boundary."--";
  close(FILE);

  sendmail(%mail);

  unlink($EXCELFILE);
}

sub investigateLater {
    #  my $sortMode =  'C';
    #  my $noLinks = 1; ## true
    #  my $hideDotFiles = 0; ## false
    #  my $showSelf = 0; ## false
    #  my @listOfContents = File::DirList::list($pollingDir, $sortMode, $noLinks, $hideDotFiles, $showSelf); 
    # my $numOfMsgFound = @new_messages;
    #  print "num of messages found in $pollingDir are $numOfMsgFound \n";
    #  print join(', ', @listOfContents);
    #  print "\n";
}

