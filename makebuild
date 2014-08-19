#!/bin/bash

# Setup
auto_tag='f20-rpfr-updates-automated' # Destination tag
build_tag='f20-rpfr-updates'    # Source tag
target_email='ceya931@gmail.com' # Destination email for reports
branch='rpi-3.12.y'

# Gets latest src rpm from koji and extracts it
# - Requires build type ('kernel'/'vc')
function get_build {
        latest_build=$(armv6-koji latest-build $build_tag raspberrypi-$1 | sed -n "s/\([^ ]*\)\s*$build_tag\s*.*/\1/p") # Gets name of latest build
	armv6-koji download-build --arch=src $latest_build # Downloads src.rpm file
	rpm -i $latest_build.src.rpm # Extracts src.rpm to ~/rpmbuild/SOURCES and ~/rpmbuild/SPECS
}

# Updates kernel config file and sets version number
function update_config {
        tar -xf $k_commit # Extracts tarball to directory raspberrypi-linux-${k_commit:0:7}

        # Determines current version number
        sublevel=$(cat raspberrypi-linux-${k_commit:0:7}/Makefile | sed -n 's/SUBLEVEL = \([0-9]*\)/\1/p') # Retrieves version sublevel (z in version number x.y.z) from Makefile
        version=$(echo $branch | sed -n "s/.*-\([0-9]*\.[0-9]*\.\).*/\1$sublevel/p") # Combines branch and sublevel numbers to get version number

        # Updates the configuration file
        bunzip2 $sources/pidora-config*
        mv $sources/pidora-config* ./raspberrypi-linux-${k_commit:0:7}/.config
        cd raspberrypi-linux-${k_commit:0:7}

        # - Makes a new configuration file based on the settings declared in the old config file
        # - Sets any new options to the default recommendation
        # - Stores changed settings in variable 'changes'
        changes=$(yes '' | make oldconfig ARCH=arm | sed -n 's/[ \t]*\(.*\)\[\(.\)\/.*(NEW)/\n\1\2/p')

        cp .config $sources/pidora-config-$version-${k_commit:0:7}
        bzip2 $sources/pidora-config-$version-${k_commit:0:7}
        cd $HOME/pidora-build
}

# Updates spec file
# - Requires one or two 40-char commit IDs
# - If single commit is passed, assumes it is kernel commit
# - If two commits are passed, expects firmware followed by userland
function update_spec {
	if [ -n "$2" ] # If userland commit id is present
	then
		file="$specs/raspberrypi-vc.spec" # Set to update firmware spec
		sed -i -e "s/%global commit_userland_date\s*.*/%global commit_userland_date  $(date +'%Y%m%d')/"\
        		-e "s/%global commit_short_userland\s*.*/%global commit_short_userland ${2:0:7}/"\
			-e "s/%global commit_long_userland\s*.*/%global commit_long_userland  $2/" $file # Update userland info
	else # If only kernel commit is present
	        file="$specs/raspberrypi-kernel.spec" # Set to update kernel spec
		sed -i "s/Version:\s*.*/Version:        $version/" $file # Update kernel version
	fi

	# Update remaining fields
	sed -i -e "s/%global commit_date\s*.*/%global commit_date  $(date +'%Y%m%d')/"\
        	-e "s/%global commit_short[^_}]\s*.*/%global commit_short ${1:0:7}/"\
	        -e "s/%global commit_long[^_]\s*.*/%global commit_long  $1/"\
		-e "s/Release:\s*[0-9]*/Release:        00/" $file # Set to 00 so bumpspec will set it to 1

	rpmdev-bumpspec -c 'updated to latest commit' -u 'pidora-auto-build' $file
}

# Builds src rpm file and uploads to koji
# - Requires build type ('kernel'/'vc')
function build_rpm {
	file=$(rpmbuild -bs $specs/raspberrypi-$1.spec | sed -n "s|Wrote: \($srpms/.*\)|\1|p") # Builds src.rpm from spec file
	task_id=$(armv6-koji build --scratch --nowait $auto_tag $file | sed -n 's/Created task: \([0-9]*\)/\1/p') # Uploads to koji and gets parent task id
	watch_build $task_id $1 & # Waits for completion as a background process
}

# Waits until task completion then sends report
# - Requires task id and build type ('kernel'/'vc')
function watch_build {
	arch_id=$(armv6-koji watch-task $1 | sed -n 's/  \([0-9]*\) buildArch.*/\1/p') # Gets buildArch id (will hang until task completes)
	task_status=$(armv6-koji taskinfo $arch_id | sed -n 's/State: \(.*\)/\1/p') # Gets task status (typically closed/failed)

	# Sends email confirmation	
	[ $2 = 'kernel' ] && commit=$k_commit || commit=$f_commit
	
	msg="Pidora $2 autobuild $commit\n
	Status: $task_status\n
	Task ID: $arch_id\n
	Link: http://japan.proximity.on.ca/koji/taskinfo?taskID=$arch_id"

	echo -e "$msg\n$changes" | mail -s "[$task_status]Pidora $2 autobuild $(date +'%d/%m/%y')" $target_email
}

k_commit=$(git ls-remote https://github.com/raspberrypi/linux.git | sed -n "s/\(.*\)\s.*rpi-3.12.y/\1/p") # Kernel commit id
f_commit=$(git ls-remote https://github.com/raspberrypi/firmware.git | sed -n "s/\(.*\)\s.*master/\1/p") # Firmware commit id
u_commit=$(git ls-remote https://github.com/raspberrypi/userland.git | sed -n "s/\(.*\)\s.*master/\1/p") # Userland commit id

# Setup
mkdir -p $HOME/pidora-build
cd $HOME/pidora-build	
rpmdev-setuptree # Creates tree at $HOME/rpmbuild if not exists
rpmdev-wipetree # Empties rpmbuild tree
sources="$HOME/rpmbuild/SOURCES" # Location of SOURCES
specs="$HOME/rpmbuild/SPECS" # Location of SPECS
srpms="$HOME/rpmbuild/SRPMS" # Location of SRPMS
find $HOME/pidora-build -mindepth 1 ! -name $k_commit ! -name $f_commit ! -name $u_commit -exec rm -rf {} \; # Delete all files except tarballs of latest git commits

# Perform a kernel build	
if [ ! -e $k_commit ] # If latest kernel commit not already present
then
	wget https://github.com/raspberrypi/linux/tarball/$k_commit # Get latest tarball
        cp $k_commit $sources # Copy to ~/rpmbuild/SOURCES
	get_build 'kernel'
	update_config 
        update_spec $k_commit
        build_rpm 'kernel'
fi	

# Perform a firmware build	
if [ ! -e $f_commit ] || [ ! -e $u_commit ] # If both latest firmware & userland commits not already present
then
	# Get missing tarball(s)
	[ ! -e $f_commit ] && wget https://github.com/raspberrypi/firmware/tarball/$f_commit
	[ ! -e $u_commit ] && wget https://github.com/raspberrypi/userland/tarball/$u_commit
	
	# Copy to ~/rpmbuild/SOURCES
        cp $f_commit $sources
        cp $u_commit $sources
	        
	get_build 'vc'
       	update_spec $f_commit $u_commit
        build_rpm 'vc'
fi
