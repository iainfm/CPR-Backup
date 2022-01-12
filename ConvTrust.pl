# ConvTrust.pl a script to convert trustees
#
# Requires: Perl. Almost any version should be OK
#
# Author:   Iain F. McLaren October 2004
#
# Warranty: Use this script is your own risk. No responsibilty will be taken for
#           the use/misuse of it.
#
# Usage:    perl <path>\ConvTrust.pl -i=input_file -o=output_file
#                                    -s=search_string -r=replace_string
#           Where input_file is a CSV file of trustees, created by trustee.nlm
#                 output_file is the file to write (these can be the same)
#                 search_string is the volume/path details to be changed
#                 replace_string is what to change the volume/path details to.
#                 If output_file is omitted, input_file is overwritten
#
# There is also a 'batch' mode used for processing multiple CDV files:

# Usage:    perl <path>\ConvTrust.pl -f=batch_file
#           Where batch_file is itself a CSV file containing the format
#           input_file,[output_file],search_string,replace_string
#
# Example:  Suppose your main file server holds data in a volume called DATA:,
#           and you have rsync'd these files to a backup server. The path on the
#           backup server is RSYNC:\SERVER1\DATA. Your main server crashes
#           horribly, but luckily you have got an rsync backup from just moments
#           ago.
#
#           First of all, you'll need to find the CSV file that trustee.nlm made
#           for you (hopefully you backed this up). Copy the file somewhere
#           handy and run this script. It can be run from any platform that
#           perl is installed on eg NetWare or Windows.
#
#           Enter the command:
#           perl ConvTrust.pl -i=DATA.txt -o=ConvData.txt ...
#                             -s=DATA: -r=RSYNC:\SERVER1\DATA
#
#           Give it a moment or two and you should have a new file called
#           ConvData.txt that contains the information trustee.nlm needs to
#           import to give trustee rights back to the backup copy of the data.
#
#           It's kind of important that your main server and rsync server are
#           in the same tree (and preferably same container) for this to work!
#
#           Copy the ConvData.txt file to the rsync (backup) server and enter
#           the following command at the server prompt:
#
#           LOAD TRUSTEE /V RESTORE SYS:ConvData.TXT
#
#           Check the logfile that the /V file creates (SYS:TRUSTEE.LOG) for
#           any problems.
#
#           Assuming there aren't any (or no important ones anyway), change
#           your login script (or map objects) to map users drives to the rsync
#           server. Tell users to log out and back in and they should be none
#           the wiser...
#
# Note:     The trick to this working properly is getting the search-and-
#           replace fields right. Adding the colon after the volume to search
#           for will probably prevent Perl from matching anything in a filename
#           that looks like the volume name.
#
#           You are strongly advised to examine the input and output files after
#           processing to see if they are ok, and test the procedure before
#           having to do it 'for real'.
#
# Version:  1.0.5 (Beta release)

# Read the arguments that the user has given us
getargs();

if ($autofile) {
   undef $/;

   # Read in the file for batch-processing
   print "\nReading $autofile\n";
   open IN, $autofile or die $!;
   $intext = <IN>;
   close IN;

   # Split the file read into lines
   @lines=split(/\n/,$intext);
   print 1+$#lines ." files to process\n";
   
   # Process the lines
   # Set a counter (just to report any bad lines)
   $counter=0;
   
   # Start processing the lines
   foreach $l (@lines) {
      $counter++;
      # Split the line at commas
      @parts=split(/\,/,$l);
      
      # Reset the check variable
      $ok=1;

      # See how many entries were in the line
      if ($#parts == 3) {
         ($infile, $outfile, $orgtext, $newtext) = (@parts);
         }

      # If there's 3 components, assume the user has omitted the destination
      # file.
      elsif ($#parts == 2) {
         ($infile, $orgtext, $newtext)= (@parts);
         $outfile = $infile;
         }
         
      # Don't process any lines with fewer than 3 components
      else {
         print "Warning: Invalid entry detected at line $counter\n";
         $ok=0;
         }
         
      # Pass on the details to the S&R routine
      search_and_replace($infile, $outfile, $orgtext, $newtext) if ($ok);
      }

   }

else {
   # The user just wants a one-off process
   search_and_replace($infile, $outfile, $orgtext, $newtext);
   }
   
exit;

sub search_and_replace {
   my ($infile, $outfile, $orgtext, $newtext) = @_ ;
   
   # Set slurp mode so we can a) process quicker and b) use the same file for
   # input and output
   undef $/;

   # Read in the file
   print "\nReading $infile\n";
   open IN, $infile or die $!;
   $intext = <IN>;
   close IN;

   # Perform the search-and-replace. Isn't Perl great at this?!?!
   print "Processing $orgtext =\> $newtext\n";
   $intext =~ s/$orgtext/$newtext/g;

   # Write the modified file back out.
   print "Writing $outfile\n";
   open OUT, ">$outfile" or die $!;
   print OUT $intext;
   close OUT;

   # Inform the user we've finished.
   print "\nFinished.\n\n";
   }

sub getargs {
   # Get the user's request
   while (@ARGV && $ARGV[0] =~ /^-/) {
      $_ = shift(@ARGV);
      # print "$_\n";
      last if /^--$/;
      
      if (/^-i/i)  {
         # Input file
         ($scrap,$infile)=split(/=/, $_);
         }
         
      if (/^-o/i)  {
         # Output file
         ($scrap,$outfile)=split(/=/, $_);
         }

      if (/^-s/i)  {
         # Search string
         ($scrap,$orgtext)=split(/=/, $_);
         }
         
      if (/^-r/i)  {
         # Replace string
         ($scrap,$newtext)=split(/=/, $_);
         }
         
      if (/^-f/i)  {
         # Automatic (batch) processing
         ($scrap,$autofile)=split(/=/, $_);
         }

       if (/^-l/i)  {
         # Logfile (not implemented yet)
         ($scrap,$logfile)=split(/=/, $_);
         print "Warning: Log file function not implemented\n";
         }
         
      if ((/^-h/i) || (/^-\?/)) {
          # User help
          print "Performs a search-and-replace on a text file\n\n";
          print "ConvTrust.pl -i=Input_File [-o=Output File]\n";
          print "             -s=Search_String -r=Replace_String\n";
          print "             [-l=Log_File]\n\n";
          print "If Output_File is not specified, the Input_File will be ".
                "overwritten\n\n";
          print "For batch processing use:\n";
          print "ConvTrust.pl -f=Batch_File [-l=Log_File]\n\n";
          print "Batch files are comma-delimted text files consisting of:\n";
          print "Input_File,[Output_File],Search_String,Replace_String\n";
          exit;
         }
         
      }
      
   # Check everything is in order
   
   # Assume we'll reuse the file if there's no output file been specified
   $outfile=$infile if (not $outfile);
   
   # Check we've got everything we need...
   if ((not $infile) && (not $autofile)) {
      print "Error: No input file specified\n";
      exit;
      }

   if ((not $autofile) && (not($orgtext && $newtext))) {
      print "Error: Both the search and replace strings must be specified\n";
      exit;
      }
      
   if (($autofile) && ($infile || $outfile || $orgtext || $newtext)) {
      print "Warning: Additional parameters will be ignored in batch ".
            "operation\n";
      }
   }
