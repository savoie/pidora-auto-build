#!/bin/bash

# Setup
auto_tag='f20-rpfr-updates-automated' # destination tag
build_tag='f20-rpfr-updates'	# source tag
branch='rpi-3.12.y' # most stable github branch
date=$(date +'%Y%m%d') # preferred date format (YYYYMMDD)
target_email='ceya931@gmail.com' # email to send reports to

mkdir -p ~/pidora-build/kernel
cd ~/pidora-build/kernel

# Configures rpmbuild directories
rpmdev-setuptree # Builds directory tree at ~/rpmbuild if not exists
rpmdev-wipetree # Erases all files from rpmdev tree
sources="$HOME/rpmbuild/SOURCES" # Location of SOURCES
specs="$HOME/rpmbuild/SPECS" # Location of SPECS
srpms="$HOME/rpmbuild/SRPMS" # Location of SRPMS

# Retrieves and extracts latest commit from github
commit_long=$(git ls-remote https://github.com/raspberrypi/linux.git | sed -n "s/\(.*\)\s.*$branch/\1/p") # 40-character unique commmit ID
commit_short=$(echo $commit_long | cut -c1-7) # First 7 characters of full commit ID
wget https://github.com/raspberrypi/linux/tarball/$commit_long # Downloads a tarball of the latest commit with filename $commit_long
cp $commit_long $sources # Copies the new tarball to ~/rpmbuild/SOURCES
tar -xf $commit_long # Extracts tarball into directory called raspberrypi-linux-$commit_short

# Retrieves and extracts latest kernel build from koji
latest_kernel=$(armv6-koji latest-build $build_tag raspberrypi-kernel | sed -n "s/\([^ ]*\)\s*$build_tag\s*.*/\1/p") # Gets name of latest kernel build from koji
armv6-koji download-build --arch=src $latest_kernel # Downloads source rpm file (filename $latest_kernel.src.rpm)
rpm -i $latest_kernel.src.rpm # Extracts src.rpm to ~/rpmbuild/SOURCES and ~/rpmbuild/SPECS

# Determines current version number
sublevel=$(cat raspberrypi-linux-$commit_short/Makefile | sed -n 's/SUBLEVEL = \([0-9]*\)/\1/p') # Retrieves version sublevel (z in version number x.y.z) from Makefile
version=$(echo $branch | sed -n "s/.*-\([0-9]*\.[0-9]*\.\).*/\1$sublevel/p") # Combines branch and sublevel numbers to get version number

# Updates the configuration file
bunzip2 $sources/pidora-config*
mv $sources/pidora-config* ./raspberrypi-linux-$commit_short/.config
cd raspberrypi-linux-$commit_short

# - Makes a new configuration file based on the settings declared in the old config file
# - Sets any new options to the default recommendation
# - Stores changed settings in variable 'changes'
changes=$(yes '' | make oldconfig ARCH=arm | grep '(NEW)')

cp .config $sources/pidora-config-$version-$commit_short
bzip2 $sources/pidora-config-$version-$commit_short

# Updates the spec file
sed -i -e "s/%global commit_date\s*.*/%global commit_date  $date/"\
	-e "s/%global commit_short\s*.*/%global commit_short $commit_short/"\
	-e "s/%global commit_long\s*.*/%global commit_long  $commit_long/"\
	-e "s/Version:\s*.*/Version:        $version/"\
	-e "s/Release:\s*[0-9]*/Release:        00/" $specs/raspberrypi-kernel.spec # Set to 00 so bumpspec will set it to 1
rpmdev-bumpspec -c 'updated to latest commit' -u 'pidora-auto-build' $specs/raspberrypi-kernel.spec

# Builds the rpm into ~/rpmbuild/SRPMS
rpmbuild -bs $specs/raspberrypi-kernel.spec

# Uploads src rpm to koji
echo 'Uploading to koji...'
file_name="$srpms/raspberrypi-kernel-${version}-1.${date}git${commit_short}.rpfr20.src.rpm"
#task_id=$(armv6-koji build --scratch --wait $auto_tag $file_name | sed -n 's/Created task: \([0-9]*\)/\1/p')
task_id=$(armv6-koji build --scratch --wait $auto_tag $file_name | grep 'Created task:' | grep -o '[0-9]*')

# Reports success/failure
#task_status=$(armv6-koji taskinfo $task_id | sed -n 's/State: \(.*\)/\1/p')
task_status=$(armv6-koji taskinfo $task_id | grep 'State:' | cut -d ' ' -f2)
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
