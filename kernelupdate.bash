#!/bin/bash

# Setup
auto_tag='f20-rpfr-updates-automated'
build_tag='f20-rpfr-updates'
branch='rpi-3.12.y'
date=$(date +'%Y%m%d')
target_email='ceya931@gmail.com'

if [ ! -d ~/pidora-build ]
then
	mkdir ~/pidora-build
fi

if [ ! -d ~/pidora-build/kernel ]
then
	mkdir ~/pidora-build/kernel
fi

cd ~/pidora-build/kernel

# Retrieves latest commit in default (most stable) branch
commit_long=$(git ls-remote https://github.com/raspberrypi/linux.git | grep $branch | cut -f1)
commit_short=$(echo $commit_long | cut -c1-7)
wget https://github.com/raspberrypi/linux/tarball/$commit_long

# Retrieves and extracts latest raspberry pi kernel from koji
latest_kernel=$(armv6-koji latest-build $build_tag raspberrypi-kernel | awk 'NR==3 {print $1}')
armv6-koji download-build --arch=src $latest_kernel
rpm2cpio $latest_kernel.src.rpm | cpio -imdv

# Determines version number
sublevel=$(curl -s https://raw.githubusercontent.com/raspberrypi/linux/$branch/Makefile | grep -o 'SUBLEVEL = [0-9]*' | grep -o '[0-9]*')
version="$(echo $branch | grep -o -m1 '[0-9]*\.[0-9]*\.')$sublevel"

# Updates the config file
tar -xvf $commit_long
old_version=$(grep -o 'Version:\s*.*' raspberrypi-kernel.spec | grep -o '[0-9]*\.[0-9]*\.[0-9]*')
old_commit=$(grep -o '%global commit_short\s*.*' raspberrypi-kernel.spec | cut -d ' ' -f3)
bunzip2 pidora-config-$old_version-$old_commit.bz2
mv pidora-config-$old_version-$old_commit ./raspberrypi-linux-$commit_short/.config
cd raspberrypi-linux-$commit_short
changes=$(yes '' | make oldconfig ARCH=arm | grep '(NEW)')
cp .config ../pidora-config-$version-$commit_short
cd ..
bzip2 pidora-config-$version-$commit_short

# Updates the spec file
sed -i "s/%global commit_date\s*.*/%global commit_date  $date/" raspberrypi-kernel.spec
sed -i "s/%global commit_short\s*.*/%global commit_short $commit_short/" raspberrypi-kernel.spec
sed -i "s/%global commit_long\s*.*/%global commit_long  $commit_long/" raspberrypi-kernel.spec
sed -i "s/Version:\s*.*/Version:        $version/" raspberrypi-kernel.spec

# Fixes that annoying warning -- remove after it's been implemented in a koji build
sed -i "s/Mon Feb 05 2013/Mon Feb 04 2013/" raspberrypi-kernel.spec

rpmdev-bumpspec -c 'updated to latest commit' -u 'pidora-auto-build' raspberrypi-kernel.spec
sed -i "s/Release:\s*[0-9]*/Release:        1/" raspberrypi-kernel.spec
exit

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
task_id=$(armv6-koji build --scratch --wait $auto_tag $file_name | grep 'Created task:' | grep -o '[0-9]*')

# Reports success/failure
task_status=$(armv6-koji taskinfo $task_id | grep 'State:' | cut -d ' ' -f2)
echo "$task_status (ID: $task_id)"

# Sends email report
msg="Pidora kernel autobuild ${version} ${commit_long}\n
Status: $task_status\n
Task ID: $task_id\n
Link: http://japan.proximity.on.ca/koji/taskinfo?taskID=$task_id\n
Configuration changes (set to default):\n----------------------\n"


echo -e "$msg$(echo $changes | sed "s/\s\[/: /g" | sed "s/\/[^ ]*\s(NEW)/\n/g")" | mail -s "Pidora kernel autobuild $(date +'%d/%m/%y')" $target_email
