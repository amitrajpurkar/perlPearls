#!/usr/bin/perl -w

BEGIN { unshift @INC, ".." }    # to test MIME:: stuff before installing it!

require 5.001;

use strict;
use MIME::Parser;
use File::Copy;
use File::Path qw(make_path remove_tree rmtree); 
use File::stat;
use Getopt::Std;
use Mail::Sendmail;
use Fcntl ':flock'; # import LOCK_* constants
use Log::Log4perl;
use HTML::HTMLDoc;

## NOTE 1:: ---------------------------------------
use au::com::schenker::scandocs::ams qw( :all );
use au::com::schenker::scandocs::pdfExtractionService qw( :all );
use au::com::schenker::scandocs::pgService qw( :all );
## Q. Where does that module come from? A. Installed locally on POSTI / not from CPAN
## Q. Where is the source code? A. Subversion
## repository = https://AUSCC01.schenker.int.au/svn/posti/trunk
## ------------------------------------------------
## NOTE 2:: ---------------------------------------
## Q. Who fires this script? A. Run by system-cron-job.. look under /etc/crontab
## ------------------------------------------------

# global variables for this script
my $BASE_DIR="/export/email/domino/home/aqis_docs";
my $OUT_DIR="$BASE_DIR/output";
my $CODE_DIR="$BASE_DIR/code";
my $APP = "$CODE_DIR/processIncomingEmails.pl";
my $MAIL_DIR="$BASE_DIR/Maildir/new";
#$MAIL_DIR="$BASE_DIR/archive/held";
#$MAIL_DIR="$BASE_DIR/archive/test";
my $ARCHIVE_DIR="$BASE_DIR/archive/success";
my $HELD_DIR="$BASE_DIR/archive/held";
my $TEMP_DIR="$BASE_DIR/tempFiles";
my $MSG_NO = 1;
my $TO="amit.rajpurkar\@dbschenker.com";
my $FROM="aqis_docs\@domino.schenker.com.au";
## Log4perl expects the config file to be present from where this script is called..
## .. so its advisable to provide absolute path to log.conf file so that this script can be ran from any place.
Log::Log4perl->init("$CODE_DIR/log.conf");

# application specific class variables
my $DOCUMENT_TYPE = "AQIS Direction";
my $TODAYS_DATE;

my $logger = Log::Log4perl->get_logger("Schenker::AqisDocs");
my $now_string = localtime;
#------------------------------------------------------------
#       Start executing the script
#------------------------------------------------------------
open(LOCK, ">>$APP.lock");
eval {
    $logger->debug( "-------------------------------------------------- \n" );
    $logger->error( "INFO:: Triggering script at $now_string \n" );
    
    
    unless (flock(LOCK,LOCK_EX|LOCK_NB)) {
      die("AQIS Direction Error: $APP already running\n");
    }
    $logger->debug("DEBUG:: file locking operation done \n");
    
    &resetEnvPathIfNeeded();
    &initializeToday();
    &pollMaildir();
    &cleanupOutputDir();
    
    flock(LOCK,LOCK_UN);
    close(LOCK);
    unlink("$APP.lock");
};
if ($@) {
    $logger->debug("DEBUG:: something went wrong in main method \n");
    flock(LOCK,LOCK_UN);
    close(LOCK);
    $logger->debug("DEBUG:: lock released \n");
    unlink("$APP.lock");
    $logger->debug("DEBUG:: lock file purged.. now the error message \n");
    $logger->error( "ERROR:: " . $@ );
    sendEmail("AQIS Direction Error from: $APP", "$@");
}
#------------------------------------------------------------
#       End of script
#------------------------------------------------------------

sub resetEnvPathIfNeeded() {
    # untaint the PATH... doesn't do any real validation
    my $envpath = $ENV{'PATH'};
    $envpath =~ /^(.*)$/;
    $logger->debug( "DEBUG:: env var path = $envpath \n" );
    ## expect to see.. "/sbin:/bin:/usr/sbin:/usr/bin:/usr/games:/usr/local/sbin:/usr/local/bin:/usr/X11R6/bin:/root/bin"
    ## we got ..       "/etc:/bin:/sbin:/usr/bin:/usr/sbin"
    ## NOTE:: This happens when cronjob runs this script.. we got to reset this Environment Variable.
    if(index($envpath, "/usr/local/bin") == -1) {
        $envpath = "/sbin:/bin:/usr/sbin:/usr/bin:/usr/games:/usr/local/sbin:/usr/local/bin:/usr/X11R6/bin:/root/bin";
        $logger->debug( "DEBUG:: resetting env var path = $envpath \n" );
    }
    $ENV{'PATH'} = $envpath;
}

sub initializeToday(){
    my (
         $second,     $minute,    $hour,
         $dayOfMonth, $month,     $yearOffset,
         $dayOfWeek,  $dayOfYear, $daylightSavings
    ) = localtime();
    my $year = 1900 + $yearOffset;
    $month = $month + 1;
    $TODAYS_DATE = sprintf( "%4d%02d%02d", $year, $month, $dayOfMonth );
}

sub pollMaildir {
  $logger->debug("DEBUG:: entering pollMaildir method \n");
  # Sanity:
  (-w ".") or die "pwd not writable...";
  
  my ($msgCodeAMS, $mgsDescAMS) = isAMSAvailable();
  my ($msgCodePG, $mgsDescPG) = isPGAvailable();
  if($msgCodeAMS ne "OK" || $msgCodePG ne "OK") {
      $logger->error("Check AMS Availability -- $mgsDescAMS \n");
      $logger->error("Check PG Availability -- $mgsDescPG \n");
      return "OK";
  }
  
  
  my $message_file;
  my $returnFlag;

  opendir(DIR, $MAIL_DIR) or die("cannot open $MAIL_DIR \n"); ## NOTE: these "die" messages get logged when caught by top-level method
  my @new_messages = grep { -f "$MAIL_DIR/$_" } readdir(DIR); 
  my $numOfMsgFound = @new_messages;
  if($numOfMsgFound < 1) {
      $logger->error("INFO:: no new messages \n");
      return "OK";
  }

  my $numOfMsgProcessed = 0;
  foreach $message_file (@new_messages) {
    $numOfMsgProcessed++;
    $logger->error("INFO:: msg no = $numOfMsgProcessed \n");
    eval{
        $returnFlag = processEachEmail($message_file);
    };
    if ($@) {
        $logger->error( "ERROR processing email $message_file :: " . $@ );
        next; ## process next email.. skip this one
    } 
  }
  closedir(DIR);
  
  $logger->debug("DEBUG:: polling for ($numOfMsgFound) messages completed \n");
  $logger->error("INFO:: no. of messages processed = $numOfMsgProcessed \n");
  $logger->error( "-------------------------------------------------- \n" );
  return "OK";
}

sub cleanupOutputDir {
    rmtree ($OUT_DIR);
    mkdir $OUT_DIR,0777 ;
    
    return 1;
}

sub processEachEmail {
    my ($msgFileParam) = @_;
    my ($path, $filename, $ext);
    my ($parser, $msgdir, $entity, $attachmentFile);
    my ($shipnoFromEmail, $docid, $branch, $department, $insertAppendFlag);
    my ($msgCode, $mgsDesc, $tempFolderLocation);
    $tempFolderLocation = $OUT_DIR;
    $msgCode = "initialize";
    $logger->error("INFO:: ------->> found message file = $msgFileParam <<------------ \n");
    
    ($entity, $msgdir) = readAndParseEmail($msgFileParam);
    
    $shipnoFromEmail = extractShipno( $entity->head->get('Subject') );
    $logger->error("INFO:: shipno = $shipnoFromEmail \n");

    # perldoc au::com::schenker::scandocs::pgService
    ($docid, $branch, $department, $insertAppendFlag, $mgsDesc) = findDocumentInPGServer($shipnoFromEmail, $DOCUMENT_TYPE);
        $logger->debug("DEBUG:: docid = $docid \n");
        if(defined $branch && $logger->is_debug()) { $logger->debug("DEBUG:: branch = $branch \n"); }
        if(defined $department && $logger->is_debug()) { $logger->debug("DEBUG:: department = $department \n"); }
        if(defined $insertAppendFlag && $logger->is_debug()) { $logger->debug("DEBUG:: insertAppendFlag = $insertAppendFlag \n"); }
        $logger->debug("DEBUG:: mgsDesc = $mgsDesc \n");
    if($docid eq "ERROR") {
        $logger->error("ERROR:: Problem with shipment number $shipnoFromEmail :: $mgsDesc");
        move("$MAIL_DIR/$msgFileParam", "$HELD_DIR/$msgFileParam");
        return "ERROR";
    } 
    my $convertedAndMergedAttachments;
    my $convertedAttachment;
    my $attachmentCounter = 0;

    foreach $attachmentFile (<$msgdir/*>) {
      $attachmentFile =~ /^(.*)$/;   # this is to make taint checking shutup
      $attachmentFile = $1;
      ($path, $filename, $ext) = ($attachmentFile=~ /^(.*)\/(.*?)\.(.*)$/);   #get the file extension

      if ($ext=~/pdf/i || $ext=~/htm/i || $ext=~/html/i) {
          if (($ext=~/htm/i || $ext=~/html/i) && $filename ne "service") {
              $logger->error("INFO:: eligible attachment = $attachmentFile \n");
              ++$attachmentCounter;
              $convertedAttachment = "$path/attachment_$attachmentCounter.pdf"; 
              ($msgCode, $mgsDesc) = convertHtmlToPdf($attachmentFile, $convertedAttachment);
              if($msgCode eq "ERROR") {
                  $logger->error("ERROR:: Problem converting html attachment into PDF :: $mgsDesc");
                  move("$MAIL_DIR/$msgFileParam", "$HELD_DIR/$msgFileParam");
                  return "ERROR";
              }
              $convertedAndMergedAttachments = prependOldDocumentToNew($convertedAndMergedAttachments, $convertedAttachment);
          } elsif ($ext=~/pdf/i) {
              $logger->error("INFO:: eligible attachment = $attachmentFile \n");
              $convertedAndMergedAttachments = prependOldDocumentToNew($convertedAndMergedAttachments, $attachmentFile);
          }
      } 
    }
    if(defined $convertedAndMergedAttachments) {
        ## perldoc au::com::schenker::scandocs::pdfExtractionService
        ($msgCode, $mgsDesc, $docid) = processEachPdfAttachment($convertedAndMergedAttachments,$insertAppendFlag,$shipnoFromEmail,$docid, $department, $branch, $DOCUMENT_TYPE, $tempFolderLocation, $TODAYS_DATE, $APP);
        $logger->debug("DEBUG:: msgCode = $msgCode \n");
        $logger->debug("DEBUG:: msgDesc = $mgsDesc \n");
        $logger->debug("DEBUG:: docid = $docid \n");
    } else {
         $logger->debug("DEBUG:: no eligible attachment found in this email \n");
    }
    
    ## once all attachments in particular email are processed, then archive it anyways
    if($msgCode eq "OK") {
        $logger->debug("DEBUG:: should archive message:: $ARCHIVE_DIR/$msgFileParam \n");
        move("$MAIL_DIR/$msgFileParam", "$ARCHIVE_DIR/$msgFileParam");
    } else {
        $logger->debug("DEBUG:: should archive message:: $HELD_DIR/$msgFileParam \n");
        $logger->error("WARN:: msgCode = $msgCode , desc = $mgsDesc \n");
        move("$MAIL_DIR/$msgFileParam", "$HELD_DIR/$msgFileParam");
    }
    
    
    return "OK"; 
}

sub readAndParseEmail {
    my ($msgFileParam) = @_;
    my ($parser, $msgdir, $entity, $attachmentFile);
    
    $parser = new MIME::Parser;
    $msgdir = makeMsgFolder() or $logger->logdie ("problem creating temp output directory");
    $logger->debug("DEBUG:: got msgdir = $msgdir .. thats where email-parser will place attachments found in the email \n");
    $parser->output_dir("$msgdir");

    # Parse an input stream:
    open FILE, "<", "$MAIL_DIR/$msgFileParam" or $logger->logdie("couldn't open $msgFileParam \n") ;
    $entity = $parser->read(\*FILE) or $logger->logdie("The last email cannot be processed. Check the last email to confirm this.\n Message from $APP");
    close FILE;
    
    return ($entity, $msgdir);
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

sub makeMsgFolder {
  while (-d "$OUT_DIR/msg$MSG_NO") {
    ++$MSG_NO;
    if($MSG_NO == 1000) {
        die("self-imposed limit reached \n");
    } 
  }
  mkdir "$OUT_DIR/msg$MSG_NO",0777 or $logger->logdie("couldn't make $OUT_DIR/msg$MSG_NO: $! \n" );
  return "$OUT_DIR/msg$MSG_NO";
}

sub extractShipno {
    my($emailSubjectParam) = @_;
    my $shipnoExtracted;
    
    ## example email-subject-line::
    ## AQIS, FSR and DIR, ACAPRPGGA, ROSEHIP VITAL PTY LIMITED, 6220302410, AUSYD

    ## we choosing the style of searching SHIPNO from right, because  
    ## other area in subject line can have marker characters embedded within
    ## also, we know for sure that SHIPNO is located towards the right end of the subject line
    $logger->debug("DEBUG:: check the email subject = $emailSubjectParam \n");
    my $lastTokenizerPos = rindex($emailSubjectParam,",");
    my $firstTokenizerPos = rindex($emailSubjectParam,",", (int($lastTokenizerPos)-1));
    chomp( $shipnoExtracted = substr($emailSubjectParam, 0, $lastTokenizerPos) );
    chomp( $shipnoExtracted = substr($shipnoExtracted, ($firstTokenizerPos + 1)) );

    $shipnoExtracted =~ s/^\s+//;## left-trim
    $shipnoExtracted =~ s/\s+$//;## right-trim
    $logger->debug("DEBUG:: check shipno_from_email = ->$shipnoExtracted<- \n");
    
    return $shipnoExtracted;
}

sub convertHtmlToPdf {
    my ($attachmentFile, $convertedFile) = @_;
    my $pdf;
    my $htmldoc;
    
    my ($path, $filename, $ext) = ($attachmentFile=~ /^(.*)\/(.*?)\.(.*)$/);
    
    eval{
        (-w $path) or die "$path not writable...";
        
        $htmldoc = new HTML::HTMLDoc();
        $htmldoc->set_input_file($attachmentFile);
        $pdf = $htmldoc->generate_pdf();
        my $lastError = $htmldoc->error(); ## its possible to get -- @allErrors = $htmldoc->error()
        if(defined $lastError && $lastError ne "") { die("error generating pdf from html.. $lastError \n"); }
        
        my $isSuccessful = $pdf->to_file($convertedFile);
        if(! $isSuccessful) { die("print to pdf not successful"); }
        
        sleep(3);
        if( -z $convertedFile) { die("the converted file is empty"); }
        if( -s $convertedFile) { $logger->debug("DEBUG:: the converted file has non-zero size"); }
    };
    if ($@) {
        $logger->error( "ERROR convertHtmlToPdf:: " . $@ );
        return ("ERROR", "html to pdf conversion failed.. $@ \n");
    }    
    return ("OK", "converted html to pdf \n");
}

sub prependOldDocumentToNew {
    my ($tempOldDocument, $newDocument) = @_;
    my $newDoc;
    if(defined $tempOldDocument) {
        eval{
            $newDoc = CAM::PDF->new($newDocument);
            $newDoc->prependPDF(CAM::PDF->new($tempOldDocument));
            $newDoc->cleansave();
            $newDoc->cleanoutput($newDocument);
        };
        if ($@) {
            $logger->error("ERROR:: $@ \n");
        }
    }
    
    return $newDocument;
}

