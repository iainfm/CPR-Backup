# CPR-Backup
NetWare backup based on Cron, Perl and Rsync

I thought this had been lost in the mists of time, but came across it on an old hard disk. Uploaded here for nostalgia / archaeology purposes.

Original readme is below. It doesn't seem to have been updated for the 1.0.9 release, but the differences after this readme are detailed (poorly) in the ChangeLog.

CPR-Backup - Installation and Execution of Perl script
Version 1.0.7 (March 2005)

Please read this document before trying the script. Despite what it may look like there is really
very little to do to get things working... Simplicity is very much the aim of this project, aside
from getting good backups that is!


1) Terminology
==============

The CPR-Backup Perl script uses Rsync to copy files from one server to another. The server where
the files were originally (usually a production server) will be known as the "source" server. The
"destination" server is where the files end up, and it's this server that runs rsync.nlm in
daemon mode.


2) Prerequisites / Introduction
===============================

Rsync must be installed and tested on both the source and destination servers, and running as a
daemon on the destination.

The script has only been tested on NetWare 6.5 SP2, with Perl 5.8.0 and Rsync 2.6. Testing has been
done on NetWare 6.0 and it was found (in a test enviroment) that it was compatible providing that
perl 5.8.0 was installed on the server.

Version 1.0.2 introduced routines to send CPR-Backup and Rsync logs as emails. For this you'll need
a Perl module called SendMail.pm. On my NW6.5 SP2 servers, this might already installed in
SYS:\Perl\Lib\Mail. The version I've got (and the one that this release works with) is 0.74. A
quick web search found the current version is 2.09, but I'm going to stick with 0.74 for the time
being as it will make life easier if that is the current shipping version with NetWare products.

If you don't have this module or you don't want to use email reporting, comment out the
use Mail::Sendmail line and anything to do with the mail_log_file() subroutine.

Log-file rollover was implemented in version 1.0.3. The default is to keep 1000 log files and re-use
them cyclically. This can be changed in the main script.

Users of NetWare 6.5 SP3 (which includes Perl 5.8.4) *may* have to change the exec() call on line 226
to sysem().


3) Create a 'targets' file
==========================

A CSV text file (see sample) should be created with one line per rsync operation required. The
format of the file is strict - the volume (suffixed with a colon) comes first, then the source
path within that volume, then the server name / rsync 'module' on the destination server. These
are basically what you use when running rsync from the command line.

Any lines starting with a hash (#) character, or do not have 3 parameters are ignored.

For example:

# These are the folders we wish to rsync:
SYS:,Apache2,WWWSERVER::Web
VOL1:,DATA,BACKUPSERVER::DATA
VOL2:,Home/User,REMOTE::DR
# End of file (this line is not necessary)

Save this file somewhere on the server (eg SYS:\ or SYS:Etc - wherever you like).

Hint: Start with a folder containing a small amount of files. You will probably have to do a bit
of trial-and-error before what you want to rsync goes where you want rsync to put it. I know I
had to!

New to version 1.0.8 is the ability of CPR-Backup to automatically expand a given path into a number
of separate targets. Say you had a large USERS folder, which people were constantly being added to or
removed from. You wouldn't want to keep updating your targets file, would you? So, add a line to the
targets file like this:

>USERS:,/,BACKUP::USERS

Note the '>' at the start of the line. This tells CPR-Backup to expand the path in the targets file
into separate targets based on what it finds in the folder when it looks. The new targets are
inserted into the targets list and processed in order. To recurse further, add more >'s. For example:

>>DATA:,/Department,BACKUP::DATA

would expand the folders in DATA:/Department, then the folders within those folders.

*** IMPORTANT NOTE *** When using recursion (especially two or more levels) it is a good idea to use
the rsync option -R. Otherwise you'll wonder where your data has gone ;-) You can do this by
modifying the script, or using the user-defined options (see section 11).


4) Set up the log folders
=========================

As the script stands, it expects to be able to write to a log directory nominated as SYS:Rsync\Log.
If this folder doesn't exist CPR-Backup will abort.

It only has to be created (or the script changed to an existing folder). No special rights are
required.


5) Running the script
=====================

Extract the Perl script (cprbackup.pl) somewhere (SYS:\ or SYS:\System work well). It is called by
running perl and passing it the path/name of the CSV file you created in accordance withsection 3.
For example, at the server console type:

perl SYS:cprbackup.pl SYS:targets.txt

All being well, the script will start without any errors, closely followed by Rsync. You'll have to
change between the Rsync and Perl screens - each time Rsync loads it gets 'focus'.

When the CPR-Backup script completes the Perl screen will remain, open for inspection, until you
press a key. To avoid this use the auto-destroy Perl option:

perl --autodestroy sys:cprbackup.pl sys:targets.txt

You might want to put this in a little ncf file to save typing.

Specifying a number (of minutes) after the targets file in the command line will make CPR-Backup
remain loaded, and repeat its given task after that number of minutes has elapsed following the
task completion. This is for use when *not* automating CPR-Backup via cron jobs. The targets file
is read each time, so there is no need to unload and re-load CPR-Backup if changes are made.

Example:

perl sys:cprbackup.pl sys:targets.txt 10    Process the targets.txt file every 10 minutes.

When running in 'repeat' mode the 'stop' file (see section 8) is looked for every minute. Therefore
it may take up to 60 seconds to terminate. Please be patient - it's more becoming than an abend!


6) Automating with Cron (Optional)
==================================

Once you're happy the CPR-Backup script is doing what it should, you will probably want to automate
the process.

Create (or edit) the SYS:Etc\crontab file with a text editor. (There's plenty of info about cron on
the web). Each line of the file needs 6 columns. These represent a schedule:

The minute of the hour on which to run (0-59),
The hour of the day on which to run (0-23),
The day of the month on which to run (1-31),
The month of the year on which to run (1-12),
The day of the week on which to run (0-7, with Sunday being 0 and 7), and finally
The command to run.

So, you might want something that runs hourly through the week so Rsync important data, and
something that runs at weekends to rsync less important stuff (or perhaps off-site).

Such a schedule would look like:

# Run the 'houly' script every hour of the day between 6am and 9pm, Mon-Fri
0    6-21    *    *    1-5     hourly.ncf
# Run the 'weekend' script on Saturdays and Sundays at 6pm
0    18      *    *    0,6     weekend.ncf

I think this is right...(!)

Obviously hourly.ncf and weekend.ncf would have to be created and put somewhere in the server's
search path. They would probably contain something like:

perl --autodestroy SYS:CPRBACKUP.PL SYS:HOURLY.TXT      and
perl --autodestroy SYS:CPRBACKUP.PL SYS:WEEKEND.TXT

For its simplicity, Cron is very powerful and can be used to run things every 15 minutes, or on
every other Tuesday, or both! As I say, the info's on the web (search for 'cron man page' or,
if you've got a unix/linux box, type 'man cron' and see what it knows).

Oh, and don't forget to load cron.nlm if it's not already. (You might want to put this in your
autoexec.ncf file as well.)

NB: When using Cron, let it handle repeating tasks (it's what it's good at) - don't use the
'repeat' mode.


7) Logging
==========

CPR-Backup writes to 3 log files while it works (actually, it writes to 2 and rsync writes to 1,
but the end result is the same). Assuming you haven't changed the script, these are:

SYS:Rsync\Log\cprbackup.log, which is a record of what has been displayed on the Perl screen
SYS:Rsync\Log\job.id, which holds the number of the last job run

and

SYS:Rsync\Log\nnnnnn.log, where nnnnnn is an incremental number of the job. (This is the one that
rsync writes to).

So, to see what happened during a certain backup, skim down the cprbackup.log file for what you're
interested in, then open up the job log to see what rsync had to say.

CPR-Backup will parse the rsync job log after completion and see if it can spot any problems (like
it doesn't exist!) and incorporate a message into its own log.

A log rollover threshold was implemented in version 1.0.3, so that only the last 1000 log records
are kept. This can be altered by changing the $reuse_limit variable.


8) Aborting running sessions
============================

A 'panic' function has been built-in to CPR-Backup. Experience has shown that if a Perl script
gets a bit lairy it can be difficult to kill off. Ctrl+C at the console screen can hang it, and
'unload perl' is just asking for an abend.

So, if you want to stop CPR-Backup in its tracks, simply create a file at the root of the source
server's SYS volume called STOP.TXT. It doesn't have to contain anything, but if it's there
CPR-Backup will terminate at its earliest convenience.

If you get into difficulty with Rsync not stopping, the best solution is usually to kill its
connections on the destination server using TCPCON.NLM, then unload the daemon. The rsyncstp.ncf
file might also work. I'm not sure.

Occasionally, rsync will hang. The usual cause of this is if the server running the daemon abends
or has other problems. There's probably a built-in timeout in rsync, but if you can't wait usually
'unload rsync' on the sending server works. No guarantees though.


9) Saving Trustees
==================

As Rsync originates from the Linux/Unix world, it doesn't really have any notion of trustee
rights. Therefore these are not synchronised along with the files. At least not at the time of
writing.

To take a backup of these, TRUSTEE.NLM (download it from Novell) comes in fairly handy. The
script savetrust.pl automates this process. It reads the mounted volumes on the server and
calls upon TRUSTEE.NLM to do its stuff. It saves the trustees to the SYS volume as

SYS:Trustees\<VolumeName>.txt

eg

SYS:\Trustees\VOL1.txt

It doesn't save trustees in SYS or _ADMIN, but you can change this if you want. There's no reason
why it couldn't. Remeber to create the SYS:Trustees folder before trying it. It may be wise to
test it on a non-critical server as well...

This has NOT been tested with anything other than 6.5SP2. When I did some brief testing on NW6 SP2,
I found that the routine to read volumes worked OK, but didn't list clustered volumes for some
reason.

Savetrust.pl is pretty much an alpha release. It doesn't do any fancy logging at the moment. It's not
particularly well commented either! I'll get round to improving it soon.

Once you've got it working you'll probably want to include SYS:Trustees in your Rsync backup,
and automate it with a Cron job. Unless you're creating many trustee assignments daily an
overnight, or even weekly execution of savetrust.pl would probably suffice.

Another script will appear in due course that will so a search-and-replace on the trustee files
allowing the rights to be restored on the 'destination' server, so it can be brought into battle
in the event of a crisis.


10) Email Reports
=================

These are fairly primitive at the moment. All that happens is the main CPR-Backup and/or Rsync
logs are emailed to a given address. To use the system you'll have to se the various SMTP settings
(mail server, sender, recipient etc) near the start of the script.

The CPR-Backup script ships with email logging disabled (so you can play with it without having
to do the above). To enable it, change the two lines

$smtp_send_cprbackup_log=0; and
$smtp_send_rsync_log=0

to =1 at the end. In fact any number will do, but it may confuse others if you use something else!

Be wary of your SMTP server refusing to deliver the emails if it suspects you are trying to relay
unsolicited emails. Some may refuse connections to anything other than trusted sources and email
addresses.


11) User-defined options
========================

You may want to change the options that CPRLBackup uses to call the rsync NLM. One option would be
to change the script, but what if you wanted to specify different options between jobs?

New to version 1.0.6 is the ability to do this. In the targets file, simply add a line containing
the rsync options you want, separated by **commas** and enclosed in square brackets. For example:

[-rav,--delete,--backup,--suffix=".old"]

These settings will become the default for all targets below this line. If you don't want to add a
line of your own, CPRBackup will continue to use the 'hard-coded' settings.

If you aren't using Cron to automate your backups, the default settings are re-loaded every time
the backup runs, so any user-defined setting won't be carried forward to the next run. Obviously
this applies to Cron-controlled backups as well.

This option is intended for advanced users of rsync. Please only use it if you know what the option
do!

Note also that the '--stats' option is added automatically for log-parsing purposes.


12) Liability
=============

This script is under development. Use it at your own risk. No responsibility will be taken for
consequences arising from the use or misuse of this script.


13) Summary
===========

Get rsync installed and working.
Extract the cprbackup.pl file to the server
Create a targets file
Create the log folder
Try it!
Backup the trustees if you need to.
Put it all together in a nice cron-controlled NCF file (or files)
