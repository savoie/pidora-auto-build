#!/bin/bash

. .buildconfig # Use config file

exec > /dev/null 2>&1 # Redirect all output to /dev/null

# Set defaults
build_f=True
build_k=True
force_build=False

# Process positional parameters
while [ "$1" != "" ]
do
	case $1 in
		-k | --kernel ) # Only build kernel
			build_f=False;;
		-f | --firmware ) # Only build firmware
			build_k=False;;
		--force ) # Force a new build
			force_build=True;;
		--scratch ) # Upload as scratch build
			scratch='--scratch ';;		
	esac
	shift
done

# Gets latest src rpm from koji and extracts it
# - Requires build type ('kernel'/'vc')
function get_build {
        if [ "$1" = 'kernel' ] && [ -z "$k_build" ] || [ "$1" = 'vc' ] && [ -z "$f_build" ] # If build not specified in config
	then
		latest_build=$(armv6-koji latest-build $build_tag raspberrypi-$1 | sed -n "s/\([^ ]*\)\s*$build_tag\s*.*/\1/p") # Gets name of latest build
	else
		# Get build name from config
		[ "$1" = 'kernel' ] && latest_build=$k_build
		[ "$1" = 'vc' ] && latest_build=$f_build
	fi

	armv6-koji download-build --arch=src $latest_build # Downloads src.rpm file
	rpm -i $latest_build.src.rpm # Extracts src.rpm to ~/rpmbuild/SOURCES and ~/rpmbuild/SPECS
}

# Updates kernel config file and sets version number
function update_config {
        tar -xf $k_commit # Extracts tarball to directory raspberrypi-linux-${k_commit:0:7}

        # Determines current version number
        sublevel=$(cat raspberrypi-linux-${k_commit:0:7}/Makefile | sed -n 's/SUBLEVEL = \([0-9]*\)/\1/p') # Retrieves version sublevel (z in version number x.y.z) from Makefile
        version=$(echo $k_branch | sed -n "s/.*-\([0-9]*\.[0-9]*\.\).*/\1$sublevel/p") # Combines branch and sublevel numbers to get version number

        # Updates the configuration file
        bunzip2 $sources/pidora-config*
        mv $sources/pidora-config* ./raspberrypi-linux-${k_commit:0:7}/.config
        cd raspberrypi-linux-${k_commit:0:7}

        # - Makes a new configuration file based on the settings declared in the old config file
        # - Sets any new options to the default recommendation
        # - Stores changed settings in variable 'changes'
        changes=$(yes '' | make oldconfig ARCH=arm | sed -n 's/[ \t]*\(.*\)\[\(.\)\/.*(NEW)/\n\1\2/p')
	[ -z "$changes" ] && changes="\nNo config changes"

        cp .config $sources/pidora-config-$version-${k_commit:0:7}
        bzip2 $sources/pidora-config-$version-${k_commit:0:7}
        cd $build_dir
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

	
	rpmdev-bumpspec -c 'updated to latest commit' -u $username $file
}

# Builds src rpm file and uploads to koji
# - Requires build type ('kernel'/'vc')
function build_rpm {
	file=$(rpmbuild -bs $specs/raspberrypi-$1.spec | sed -n "s|Wrote: \($srpms/.*\)|\1|p") # Builds src.rpm from spec file
	task_id=$(armv6-koji build ${scratch}--nowait $auto_tag $file | sed -n 's/Created task: \([0-9]*\)/\1/p') # Uploads to koji and gets parent task id
	watch_build $task_id $1 & # Waits for completion as a background process
}

# Waits until task completion then sends report
# - Requires task id and build type ('kernel'/'vc')
function watch_build {
	# Hang until task complete; take final status update
	output=$(armv6-koji watch-task $1 | grep 'buildArch')
	output=$(echo "$output" | tail -1)

	arch_id=$(echo $output | sed -n 's/^[ \t]*\([0-9]*\).*/\1/p') # Gets buildArch id
	task_status=${output##* } # Gets task status (last word of output)
	
	msg="Pidora $2 autobuild $commit\n
	Status: $task_status\n
	Task ID: $arch_id\n
	Link: https://japan.proximity.on.ca/koji/taskinfo?taskID=$arch_id"

	[ "$2" = 'kernel' ] && msg="$msg\n$changes"

	echo -e "$msg" | mail -s "Pidora $2 autobuild [$task_status] $(date +'%d/%m/%y')" $target_email
}

# Get commit ids from config file or latest git commit
[ -z "$k_commit" ] && k_commit=$(git ls-remote https://github.com/raspberrypi/linux.git | sed -n "s/\(.*\)\s.*$k_branch/\1/p") # Kernel
[ -z "$f_commit" ] && f_commit=$(git ls-remote https://github.com/raspberrypi/firmware.git | sed -n "s/\(.*\)\s.*$f_branch/\1/p") # Firmware
[ -z "$u_commit" ] && u_commit=$(git ls-remote https://github.com/raspberrypi/userland.git | sed -n "s/\(.*\)\s.*$u_branch/\1/p") # Userland

# Setup
mkdir -p $build_dir # Make build directory if not exists
cd $build_dir	
rpmdev-setuptree # Creates tree at $HOME/rpmbuild if not exists
rpmdev-wipetree # Empties rpmdev tree

find $build_dir -mindepth 1 ! -name $k_commit ! -name $f_commit ! -name $u_commit -exec rm -rf {} \; # Deletes all files except for tarballs that are still up-to-date (filename matches latest commit)

# Perform a kernel build	
if [ "$build_k" = 'True' ]
then	
	[ "$force_build" = 'True' ] && rm $k_commit # Force a new build by deleting existing tarball
	
	if [ ! -e "$k_commit" ] # If latest kernel tarball not already present
	then
		wget https://github.com/raspberrypi/linux/tarball/$k_commit # Get latest tarball
	        cp $k_commit $sources # Copy to ~/rpmbuild/SOURCES
		get_build 'kernel'
		update_config 
	        update_spec $k_commit
        	build_rpm 'kernel'
	fi
fi	

# Perform a firmware build	
if [ "$build_f" = 'True' ]
then
        [ "$force_build" = 'True' ] && rm $f_commit $u_commit # Force a new build by deleting existing tarball

	if [ ! -e "$f_commit" ] || [ ! -e "$u_commit" ] # If both latest firmware & userland commits not already present
	then
		# Get missing tarball(s)
		[ ! -e "$f_commit" ] && wget https://github.com/raspberrypi/firmware/tarball/$f_commit
		[ ! -e "$u_commit" ] && wget https://github.com/raspberrypi/userland/tarball/$u_commit
	
		# Copy to ~/rpmbuild/SOURCES
        	cp $f_commit $sources
	        cp $u_commit $sources
	        
		get_build 'vc'
	       	update_spec $f_commit $u_commit
        	build_rpm 'vc'
	fi
fi
