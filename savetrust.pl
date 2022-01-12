# SaveTrust.pl
# Script to save all the trustees on a server
#
# Requires: Perl2UCs for checking running NLMs
#           Perl (only tested on version 5.8.0)
#           trustee.nlm (tested with 1.10.04)
#
# Version : 1.0.0A

# include the module we need

use Perl2UCS;

# Set up the parameters for trustee.nlm
@cmd=("TRUSTEE", "/D", "/ET", "SAVE");
$last_cmd=$#cmd;

# Define the name of the module to look for
$nlm="TRUSTEE.NLM";

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
	
	if (($vol ne "SYS") && ($vol ne "_ADMIN")) {

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
		$result=exec(@cmd);

		# Give the task chance to start
		sleep($delay);
		}
	}


exit;

sub getvolumes {

	$vol_mgr = Perl2UCS->new("UCX:VolumeMgr") or die "Unable to create VolumeMgr object!\n";
	$volumes = $vol_mgr->{"VOLUMES"} or die "Can't get VOLUMES from ucx:volumemgr object";

	$i=0;

	while ($volumes->hasMoreElements()) {
		$volume = $volumes->Next() or die "Can't get Next volume from volumes object";
		($name, $size, $free, $bksz, $tdir) = @{$volume}{"Name", "TotalSpace", "FreeSpace", "BlockSize", "TotalDir"};
		$vol_names[$i]="$name";
		$i++;
		}
	
	return @vol_names;

	}

sub get_module_status {

    # Check to see whether a nlm is loaded. Returns 0 of not running, 1 if running

    $server = Perl2UCS->new("ucx:server") or die "Can't get ucx:server object";
    $mods = $server->{"Modules"} or die "Can't get Modules from ucx:server object";
    $module = $mods->Element($_[0]);

    if ($module) {
	return $module->{"Loaded"};
	}
	else
	{
	return 0;
	}
    }