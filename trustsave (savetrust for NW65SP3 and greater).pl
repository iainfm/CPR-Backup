# TrustSave.pl
# Script to save all the trustees on a server
#  
# This script has been modified from the original 
# version to support NetWare 6.5 SP3 and above.  The
# original maintainer, Ian McLaren no longer supports
# CPR-Backup, or this script.  
#
# The Authors cannot be held liable in any way for
# any damages that may result from the use of this program.
#
# Requires: NSS
#           Perl (only tested on version 5.8.0)
#           trustee.nlm (tested with 1.10.04 and 1.10.06)
#
# Modifications By:  Ryan Kather
#                    Roush Industries, Inc.
#                    RDKath@Roushind.com
#
# Version : 1.0.1-NSS

# Set up the parameters for trustee.nlm
@cmd=("TRUSTEE", "/D", "/ET", "SAVE");
$last_cmd=$#cmd;

# Define the name of the module to look for
$nlm="TRUSTEE.NLM";

# The NRM XML file that keeps a note of which modules are loaded
$nrm_file="_admin:/Novell/NRM/NRMModules.xml";

# A get-out. Die if the following file exists (safer than unloading)
$stop="SYS:STOP.TXT";

# Set the interval that we'll check to see if trustee.nlm has completed
$delay=5;

# Read the volumes on the server
@volumes=getvolumes();

print "Found the following volumes:\n\n\t";
print join "\n\t",@volumes;
print "\n\n";

foreach $vol (@volumes) {
    

    $nlm_running=get_module_status($nlm);

    while ($nlm_running==1) {

        die "STOP file encountered" if (-e $stop);

        # print "$nlm is running. Waiting $delay seconds\n";        
        sleep($delay);

        $nlm_running=get_module_status($nlm);        
    
        }

    # print "$nlm has finished. Continuing.\n";
    
    $cmd[$last_cmd + 1]="$vol\:";
    $cmd[$last_cmd + 2]="SYS:\\Trustees\\$vol\.txt";

    print "Saving trustees in $vol\tto\t$cmd[5]...\n";
    $result=system(@cmd);

    # Give the task chance to start
    sleep($delay);
}

exit;

###### Subroutines and functions ######

# 
# Get Volume List
#

sub getvolumes
{

   # Initialize Array Counter
   $i = 0;

   #Open List of All NSS Volumes
   opendir(VOLDIR, "_admin:/Volumes/") 
       or die "Error opening NSS management file ($!) on server";

   #Initialize Volume Names into Array
   @vol_names = readdir(VOLDIR);
 
   #Do Not Keep Volume List Open Longer then Necessary
   closedir(VOLDIR);

   $ending_value = scalar(@vol_names);

   # Restrict the Array to Real Volumes Only
   while ($i < $ending_value) {
      if (((@vol_names[$i]) eq "SYS") || ((@vol_names[$i]) eq "_ADMIN") || 
      ((@vol_names[$i]) =~ m/IV_$/) || ((@vol_names[$i]) eq ".") || 
      ((@vol_names[$i]) eq "..")) {
         splice(@vol_names, $i, 1);
      } else {
         $i++;
      }
   }
   return @vol_names;
}

#
# Get Module Load Status
#

sub get_module_status 
{
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
