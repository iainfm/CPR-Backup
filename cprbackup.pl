# CPR Backup. A Perl script to automate rsync
#
# Requires: Perl (only tested on version 5.8.0)
#           Sendmail.pm for email reports (tested with 0.79, quite old but ships
#           with NW6.5)
#
#           NRM (and therefore NSS) to be running and operational on the
#           sending server. (Check for _ADMIN:Novell\NSS folder).
#
# Notes:    Do not use this Perl prior to 5.80!
#
#           Before running this script, rsync must be installed, configured and
#           functional between the source server and the destination server.
#           Also, the log directory must exist.
#
# Author:   Iain F. McLaren March 2005
#
# Refs:     Mail module: http://alma.ch/perl/mail.htm
#
# Warranty: Use this script is your own risk. No responsibilty will be taken for
#           the use/misuse of it.
#
# Usage:    perl <path>\cprbackup.pl <input_file> <repeat_interval>
#           Where <input_file> is a CSV file of:
#           <VOLUME>:,<SOURCE_PATH>,RSYNC_SERVER::DESTINATION
#           and <repeat_interval> is the time in minutes for the task to repeat.
#           Don't use the repeat interval if running from a Cron job!
#
#           User-defined rsync options can be included into the CSV file by
#           entering them between square brackets, separated by **commas**. Eg:
#
#           [-ravW,--delete,--dry-run]
#
#           Note: These settings will affect EVERYTHING below them in the CSV
#           file, unless another setting line is encountered. Use alternative
#           settings with caution, and you are sure that you know what you and
#           doing!!! It would, for example, be a daft idea to have --daemon as
#           one of the paremeters...
#
#           Auto-expansion of paths: New to v1.0.8 is the ability for cprbackup
#           to automatically expand a target folder into a number of individual
#           targets. Simply put a '>' at the beginning of the line in question.
#           See the docs for further info
#
#           Run this script on the netware server you want to copy from, not the
#           one where the rsync daemon is running!
#
# Version:  1.0.9

###### Initial parameters, and other things that we need to do  ######
use Mail::Sendmail;

# Name of the module to check for
$nlm="RSYNC.NLM";

# The NRM XML file that keeps a note of which modules are loaded
$nrm_file="_admin:/Novell/NRM/NRMModules.xml";

# Where the logs live.
$log_dir="SYS:rsync\\log";

# Exit if the log directory's not there.
die "Log folder $log_dir does not exist" if (not -d $log_dir);

# The overall log file. Indicidual job logs will have incremental numbers
$log_file="$log_dir\\cpr-backup.log";

# Our version number
$version="1.0.9";
mylog("CPR Backup verion $version starting", $log_file);

# Quit nicely if this file is discovered.
$stop_file="SYS:STOP.TXT";

# Check the stop file's not there before we go any further
check_stop();

# Get the first parameter supplied. Moan if the user's not given us one.
$target_file=$ARGV[0];
die "No target file supplied" if (not $target_file);

# Time in seconds to wait before re-testing whether the rync's finished.
# Anything less than 5 seconds might be asking for trouble...
$delay=5;

# This file keeps track of the last job number user
$job_file="$log_dir\\job.id";

# Number of separate logs to keep before re-using them.
$reuse_limit=1000;

# Parameters we need for emailing reports, the SMTP server and email details
#
# Your smtp server
$smtp_server="smtp.domain.com";

# Who you want the email to originate from. Watch out for anti-relay measures on
# your mail server.
$smtp_sender="Rsync Report <rsync\@domain.com>";

# Whou you want the reports to be sent to. Don't remove the backslash before the
# 'at' sign.
$smtp_recipient="your.admin\@domain.com";

# The subject of the email. The log's filename will be appended to this.
$smtp_subject="CPR Backup Report";
#
# What we want to email
$smtp_send_cprbackup_log=0; # (The overall log, set to 1 to enable)
$smtp_send_rsync_log=0;     # (Individual rsync reports, set to 1 to enable)

# Words to look for in the rsync log that indicate failure
@failures=("rsync error:","rsync: failed");

# Shall we stay loaded and repeat on a regular basis?
$stay_loaded=0;              # Default operation is not to repeat the task (Cron jobs)
$repeat_interval=30;  # How often to repeat (in minutes)

# Check if the user wants to override the repeat option (2nd argument is the
# number of seconds to repeat)
if ($ARGV[1]) {
   $stay_loaded=1;
   $repeat_interval=$ARGV[1];
   mylog("User-specified restart interval of $repeat_interval minutes",
        $log_file);
   }

# Report volume errors? We might not want to if we're running on a cluster node.
$report_volume_errors=0;

# Warn when individual log (job) files are being overwritten?
$warn_overwrite=0;

###### Start processing and loop if required ######

do {

   # Read the targets file in 'slurp' mode.  There's no point leaving it open
   # any longer than we have to.
   open IN, $target_file or die "Can't open target file $target_file\n";
   $/=undef;
   # Read the file
   $targets=<IN>;
   close IN;

   # The command we're going to use to start rsync. Add any options here, but
   # don't add the volume and paths. They are added later...
   @cmd1=("rsync", "-rav", "--delete", "--stats");

   # Note the last element of the array so we can tack other parameters on later
   $last_cmd=$#cmd1;

   # Split the targets into their constituent lines.
   @line=split(/\n/,$targets);

   mylog("Using target file $target_file",$log_file);
   mylog("Repeating every $repeat_interval minutes (after completion)",
         $log_file) if $stay_loaded;
         
   # Pre-process the target file
   process_target_file();

   # Targets are processed - begin the backup
   foreach $target (@line) {

      # Check for the stop file
      check_stop();

      # Get rid of any pesky newline chars (again - just in case).
      chomp;

      # Check to see if the line contains parameters for rsync (these are
      # enclosed in square brackets
      if ((substr($target,0,1) eq "[") && (substr($target,$#target,1) eq
                                             "]")) {
        change_rsync_setting($target);
        }

      # Split the line into the parts we need
      @detail=split(/\,/,$target);

      # Check the target to see whether it should be expanded. At present,
      # expanded targets are added to the END of the targets list. Expandable
      # targets are identified by a '>' symbol at the beginning of the line.

      # Don't process settings, incomplete or comment lines, or expansion paths
      # (not that there should be any exp. paths by this point...)
      if (($#detail==2) && (substr($detail[0],0,1) ne "#") &&
          (substr($detail[0],0,1) ne "[") &&
          (substr($detail[0],0,1) ne ">") &&
	  (substr($detail[0],length($detail[0])-1,1) ne ".")) {

      # Extract the info from the targets file
         $volume=$detail[0];
         $src=$detail[1];
         $dest=$detail[2];

         # Check that the volume exists. Skip if it doesn't
         if (-d $volume) {

            # Check if rsync's already running
            wait_for_rsync();

            # Determine, and update the current job ID
            $job_id=1 + get_job_id($job_file);

            # Reset the job id if it has exceeded our limit
            if ($job_id > $reuse_limit) {
               $job_id=1;
               mylog("The log limit was reached and has been reset",$log_file);
               }

            # Delete the previous log file if it exists - rsync will append to
            # it otherwise
            if ((-e "$log_dir\\$job_id\.log") && ($warn_overwrite)) {
               mylog("Log file #$job_id already exists. Deleting", $log_file);
               unlink "$log_dir\\$job_id\.log";
               }

            $update_id=write_job_id($job_file,$job_id);
            # Warn if that might have gone wrong
            mylog("Warning: Failed to update job id",
                  $log_file) if (not $update_id);

            # Add the details about what we're rsyncing to the command:

            # The volume we're rsyncing...
            $cmd1[$last_cmd + 1]="--volume\=$volume";

            # the log file to write to...
            $cmd1[$last_cmd + 2]="--log-file=$log_dir\\$job_id\.log";

            # the source path...
            $cmd1[$last_cmd + 3]="\"$src\"";

            # ...and desination server/module.
            $cmd1[$last_cmd + 4]="$dest";

            # Write what's happening to the log
            mylog("RSYNC $volume\\$src to $dest\. Job #$job_id",$log_file);

            # The actual command to start rsync.nlm
            # For debugging: print "\n",join(" ",@cmd1),"\n";
            # For NW6.5SP3 / Perl 5.8.4, change exec() to system()!!!

            $result=exec(@cmd1);

            # Give it chance to start. It may have to auto-load other nlms.
            sleep($delay);

            # Don't proceed until rsync's finished
            wait_for_rsync();
            
            # Have a look and see what rsync told us.
            process_rsync_log("$log_dir\\$job_id\.log");

            # And email it if required
            if ($smtp_send_rsync_log) {
               mail_log_file("$log_dir\\$job_id\.log");
               }
            }
            else {
               mylog("Volume $volume is not mounted and has been skipped.",
               $log_file) if $report_volume_errors;
               }
            }
         }

   # Log the completion of the task
   mylog("Finished.",$log_file);

   # If we're staying loaded, report what's going on.
   if ($stay_loaded) {
      mylog("Waiting $repeat_interval minutes before restart", $log_file);
      }

   # Email the log file to someone special, if we've been asked to.
   if ($smtp_send_cprbackup_log) {
      mail_log_file($log_file);
      }

   # Pause the specified time
   if ($stay_loaded) {
      for ($sl=0; $sl<$repeat_interval; $sl++) {
         # Check for termination every minute
         check_stop();
         sleep(60);
         }
      }

   } until (not $stay_loaded);

exit;


###### Subroutines and functions ######

sub get_module_status {

  # Check whether a nlm is loaded. Returns 0 if not running, >=1 otherwise
  # Relies on NRM XML files
  #
  # Input:  Name of NLM to test (case sensitive)
  # Outout: Number of instances found (zero if not found)
  
  my $COUNT=0;
  open nrmfile, "<$nrm_file"  or die "Unable to open $nrm_file. Is NSS loaded?";
  while (<nrmfile>) {if (/$_[0]/) {++$COUNT}}
  close nrmfile;
  return $COUNT;
   }

sub mylog {

   # log output to screen and (optionally) to file
   # $_[0] is the string to be logged, $_[1] is the logfile

   ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime;

   $out=sprintf("%02d",$mday);
   $out.="/";
   $out.=sprintf("%02d",$mon+1);
   $out.="/";
   $out.=1900+$year;
   $out.=" ";
   $out.=sprintf("%02d",$hour);
   $out.=":";
   $out.=sprintf("%02d",$min);
   $out.=":";
   $out.=sprintf("%02d",$sec);
   $out.=" $_[0]";
   $out.="\n";
   print $out;
   if ($_[1]) {
      $LOGFILE=">>" . $_[1];
      open LOGFILE or die "Can't open log file $_[1]: $!";
      print LOGFILE $out;
      close LOGFILE;
      }
   }

sub get_job_id {
   # Function to read the id for the *last* job that ran.

   # Set the string up for read-only file access
   $JID_FILE="<" . $_[0];

   # If this is the first time there will be no job id file, so start counting.
   open JID_FILE or return "0";

   # Read the first (and hopfully only) line. Anything else will be ignored.
   $jid=<JID_FILE>;
   close JID_FILE;
   return $jid;
   }

sub write_job_id {
   # Function to write the id for the *last* job that ran.
   $JID_FILE=">" . $_[0];
   # Open the id file for writing (clobber mode). If it doesn't open, deal with
   # it in the main program
   open JID_FILE or return 0;
   # Write job ID back to the holiding file
   print JID_FILE $_[1];
   close JID_FILE;
   # Return what we already know
   return $_[1];
   close JID_FILE;
   }

sub process_rsync_log {
   # This function will (one day) peruse the log that rsync produces and return
   # the useful info to the screen and log. To start with, we're just going to
   # see if the log file exists. If there's something wrong with the search path
   # (for example), Rsync tends to report nothing.
   #
   # The function takes 1 parameter, which is the full name of the log file to
   # be processed. In future it may take a second parameter - the severity
   # levels that should be reported/ignored.
    
   return mylog("Warning: ** Rsync produced no output **",
                $log_file) if (not -e $_[0]);

   # Read in the rsync log for processing, in 'slurp' mode
   open IN, $_[0] or return mylog(
                                  "Could not open log file $target_file for
                                   processing",$log_file);
   $/=undef;
   # Read the file
   $log_to_parse=<IN>;
   close IN;

   # Check for failure/error conditions
   foreach $f (@failures) {
      return mylog("ERROR: ** See Rsync log file for details **",$log_file) if
                  ($log_to_parse =~ m/$f/i);
      }
   }

sub wait_for_rsync {
   # Subroutine that waits for Rsync to complete
   $rsync_status=get_module_status($nlm);
   while ($rsync_status != 0) {

   check_stop();

      # Wait a little while...
      sleep($delay);
      # ...before trying again.
      $rsync_status=get_module_status($nlm);
      }
   }

sub mail_log_file {
   # Subroutine to email the contents of file $_[0] using the details defined at
   # the top of the script

   # Check the log file exists before going any further
   return mylog("Warning: Can't email file $_[0]", $log_file) if (not -e $_[0]);

   # Read the log file in 'slurp' mode
   open IN, $_[0] or
      return mylog("Could not open log file $target_file for emailing",
      $log_file);
      
   $/=undef;
   # Read the file
   $log_to_email=<IN>;
   close IN;


   # Set up the hash to send to the Sendmail module
   %mail = (
      To      => $smtp_recipient,
      From    => $smtp_sender,
      Subject => "$smtp_subject ($_[0])",
      'X-Mailer' => "Mail::Sendmail version $Mail::Sendmail::VERSION",
      );

   # Define the SMTP server
   $mail{Smtp} = $smtp_server;

   # Populate the body of the email with the file we read earlier
   $mail{'mESSaGE : '} = "CPR Backup log file $_[0]\n\n$log_to_email";
    
   # Ask sendmail to deliver the message, and report back what happened.
   if (sendmail %mail) {
      mylog("Report $_[0] sent to $smtp_recipient",$log_file);
      }
   else {
      chop $Mail::Sendmail::error;
      mylog("Warning: Email failed ($Mail::Sendmail::error)",$log_file);
      }
   }
 
sub check_stop {
  # Check to see whether the 'abort' file exists and exit if it does

  if (-e $stop_file) {
    mylog("STOP file ($stop_file) exists. Terminating.\n", $log_file);
    exit;
    }
  }

sub change_rsync_setting {
  # Settings required will be in $_[0]
  my $newopts=$_[0];
  
  # Chop off the square brackets
  $newopts=substr($newopts, 1, $#newopts);

  # Log the change
  mylog("New options used: $newopts", $log_file);
  
  # Set the cmd1 array and the last item. Always include --stats because it'll
  # probably be useful for log parsing.
  @cmd1=("rsync",split(/\,/,$newopts),"--stats");
  $last_cmd=$#cmd1;
  }
  
sub process_target_file {
  # Pre-process the targets file to expand any paths etc

  $target_index=0; # keep track of which line we're on
  
  foreach $target (@line) {

    # Get rid of any pesky newline chars.
    chomp;

    @detail=split(/\,/,$target);
    
    $target_index++;  # increment the counter

      if (substr($target,0,1) eq ">") {

        # To log the discovery uncomment the line below
        # mylog("Found expansion path $detail[0]\\$detail[1]", $log_file);

        # Count how deep we're going. There's got to be a 'perlier' way of
        # doing this...answers on a postcard please.
        $depth=0;
        @chars=split(//,$detail[0]);

        foreach $c (@chars) {
          $depth++ if ($c eq ">");
          }
          
        $next_depth=$depth-1;
        $add_depth="";
        # Prepare a string containing a number of >'s to add at the start of the
        # new target if we're going deeper.
        $add_depth=">" x $next_depth if ($next_depth > 0);
        
        # Debugging output
        # mylog("Recursing $depth levels", $log_file);
        
        # Take a note of the volume name (without the '>') for processing
        #$exp_vol=substr($detail[0],1,length($detail[0])-1);
        $exp_vol=substr($detail[0],$depth);
        
        # Chop off the trailing '/' or '\' if there is one
        chop($detail[1]) if (
          (substr($detail[1],length($detail[1])-1,1) eq '/') or
          (substr($detail[1],length($detail[1])-1,1) eq '\\'));

        # This is the path to read:
        $dir_to_expand=$exp_vol.$detail[1];

        # Empty folders cause problems, so try to treat them as a single
        # target if there's an error opening the folder.
        $failed_dir=0;
        
        if (-d $dir_to_expand) {
          # Open the directory for reading the contents, if it is a directory
          opendir(EXPDIR, $dir_to_expand) or $failed_dir=1;
          
          # Read the directory into an array...
          @expdirs=readdir EXPDIR;
          # ... and close it
          closedir EXPDIR;

          @newline=();  # Initialise the new array
          if ($failed_dir==0) {
            # If the opendir was OK, add each of the resulting directory
            # entries to the array
            foreach $expdir (@expdirs) {
		
		if (($expdir ne ".") && ($expdir ne "..")) {
		   # Filter out the current and parent folders returned (NW65SP4?)
	           $add_target=$add_depth."$exp_vol,$detail[1]/$expdir,$detail[2]";
       		   @newline=(@newline,$add_target);
		   }

                }
            }
          else {
            # opendir() causes an error when opening emptyy folders. Add the
            # offending folder to the list and let rsync deal with it.
            mylog("Warning: Could not expand $dir_to_expand : $!", $log_file);
            @f=split(/:/,$dir_to_expand);
            @newline=("$exp_vol,$f[1],$detail[2]");
            }
        }
        
        # If the new target is a file then add this to the targets list after
        # stripping unwanted information (ie the volume name)
        if (-f $dir_to_expand) {
          # include the file as a target
          @f=split(/:/,$dir_to_expand);
          @newline=("$exp_vol,$f[1],$detail[2]");
          }

        # @newline is now an array of expanded targets, ready for splicing
        # into the original targets list (@line).
        # Remove the expansion path from the array...
        splice(@line,$target_index-1,1,"# Target removed by expansion process");
        # ... and merge the expanded targets into where they should go
        splice(@line,$target_index,0,@newline);
        }
     }
  # Uncomment the following line to log the new targets file for inspection
  # mylog(join("\n",@line),$log_file);
  }
