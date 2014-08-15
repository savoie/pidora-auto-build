#!/bin/bash

# Setup
auto_tag='f20-rpfr-updates-automated' # destination tag
build_tag='f20-rpfr-updates'	# source tag
branch='rpi-3.12.y' # most stable github branch
date=$(date +'%Y%m%d') # preferred date format (YYYYMMDD)
target_email='ceya931@gmail.com' # email to send reports to

mkdir -p ~/pidora-build/kernel
cd ~/pidora-build/kernel

# Retrieves latest commit from github
commit_long=$(git ls-remote https://github.com/raspberrypi/linux.git | sed -n "s/\(.*\)\s.*$branch/\1/p") # 40-character unique commmit ID
commit_short=$(echo $commit_long | cut -c1-7) # First 7 characters of full commit ID

: <<'END'

if [ -e $commit_long ]
then
	exit
else
	find . -type d -name "raspberrypi-linux*" | xargs rm -rf
	rm *
fi

END

wget https://github.com/raspberrypi/linux/tarball/$commit_long # Downloads a tarball of the latest commit with filename $commit_long

# Retrieves and extracts latest raspberry pi kernel from koji
latest_kernel=$(armv6-koji latest-build $build_tag raspberrypi-kernel | sed -n "s/\([^ ]*\)\s*$build_tag\s*.*/\1/p") # Gets name of latest kernel build from koji
armv6-koji download-build --arch=src $latest_kernel # Downloads source rpm file (filename $latest_kernel.src.rpm)
rpm2cpio $latest_kernel.src.rpm | cpio -imd

# Gets information about the older build (to correctly name files extracted from the old src rpm)
old_version=$(sed -n 's/Version:\s*\(.*\)/\1/p' raspberrypi-kernel.spec)
old_commit=$(sed -n 's/%global commit_short\s*\(.*\)/\1/p' raspberrypi-kernel.spec)

# Extracts tarball into directory called raspberrypi-linux-$commit_short
tar -xf $commit_long

# Determines current version number
sublevel=$(cat raspberrypi-linux-$commit_short/Makefile | sed -n 's/SUBLEVEL = \([0-9]*\)/\1/p') # Retrieves version sublevel (z in version number x.y.z) from Makefile
version=$(echo $branch | sed -n "s/.*-\([0-9]*\.[0-9]*\.\).*/\1$sublevel/p") # Combines branch and sublevel numbers to get version number
#version="$(echo $branch | grep -o -m1 '[0-9]*\.[0-9]*\.')$sublevel" # Combines branch and sublevel numbers to get version number

# Updates the configuration file
bunzip2 pidora-config-$old_version-$old_commit.bz2
mv pidora-config-$old_version-$old_commit ./raspberrypi-linux-$commit_short/.config
cd raspberrypi-linux-$commit_short

# - Makes a new configuration file based on the settings declared in the old config file
# - Sets any new options to the default recommendation
# - Stores changed settings in variable 'changes'
changes=$(yes '' | make oldconfig ARCH=arm | grep '(NEW)')

cp .config ../pidora-config-$version-$commit_short
cd ..
bzip2 pidora-config-$version-$commit_short

# Updates the spec file
sed -i -e "s/%global commit_date\s*.*/%global commit_date  $date/"\
	-e "s/%global commit_short\s*.*/%global commit_short $commit_short/"\
	-e "s/%global commit_long\s*.*/%global commit_long  $commit_long/"\
	-e "s/Version:\s*.*/Version:        $version/"\
	-e "s/Release:\s*[0-9]*/Release:        00/" raspberrypi-kernel.spec # Set to 00 so bumpspec will set it to 1
rpmdev-bumpspec -c 'updated to latest commit' -u 'pidora-auto-build' raspberrypi-kernel.spec

# Sets up the document tree and moves files
rpmdev-setuptree
rpmdev-wipetree
cp first32k.bin.bz2 ~/rpmbuild/SOURCES
cp $commit_long ~/rpmbuild/SOURCES
cp pidora-config-$version-$commit_short.bz2 ~/rpmbuild/SOURCES
cp raspberrypi-kernel.spec ~/rpmbuild/SPECS

# Builds the rpm and uploads to koji
cd ~/rpmbuild/SPECS
rpmbuild -bs raspberrypi-kernel.spec
cd ~/rpmbuild/SRPMS
echo 'Uploading to koji...'
file_name="raspberrypi-kernel-${version}-1.${date}git${commit_short}.rpfr20.src.rpm"
task_id=$(armv6-koji build --scratch --wait $auto_tag $file_name | sed -n 's/Created task: \([0-9]*\)/\1/p')
#task_id=$(armv6-koji build --scratch --wait $auto_tag $file_name | grep 'Created task:' | grep -o '[0-9]*')

# Reports success/failure
task_status=$(armv6-koji taskinfo $task_id | sed -n 's/State: \(.*\)/\1/p')
#task_status=$(armv6-koji taskinfo $task_id | grep 'State:' | cut -d ' ' -f2)
echo "$task_status (ID: $task_id)"

if [ "$task_status" = "closed" ]
then
	if [ -n "$changes" ]
	then
		task_status='updated config'
	fi
fi

# Sends email report
msg="Pidora kernel autobuild ${version} ${commit_long}\n
Status: $task_status\n
Task ID: $task_id\n
Link: http://japan.proximity.on.ca/koji/taskinfo?taskID=$task_id\n\n"

echo -e "$msg$(echo $changes | sed "s/\s\[/: /g" | sed "s/\/[^ ]*\s(NEW)/\n/g")" | mail -s "[$task_status]Pidora kernel autobuild $(date +'%d/%m/%y')" $target_email
