#!/bin/bash

# Setup
auto_tag='f20-rpfr-updates-automated'
build_tag='f20-rpfr-updates'
branch='master'
u_branch='master'
date=$(date +'%Y%m%d')
target_email='ceya931@gmail.com'

if [ ! -d ~/pidora-build ]
then
        mkdir ~/pidora-build
fi

if [ ! -d ~/pidora-build/firmware ]
then
        mkdir ~/pidora-build/firmware
fi

cd ~/pidora-build/firmware

# Retrieves latest firmware and userland commits
commit_long=$(git ls-remote https://github.com/raspberrypi/firmware.git | grep $branch | cut -f1)
commit_short=$(echo $commit_long | cut -c1-7)
u_commit_long=$(git ls-remote https://github.com/raspberrypi/userland.git | grep $u_branch | cut -f1)
u_commit_short=$(echo $u_commit_long | cut -c1-7)

find . ! -name $commit_long ! -name $u_commit_long -type f -delete

if [ -e $commit_long ] && [ -e $u_commit_long ]
then
	exit
else
	if [ ! -e $commit_long ]
	then
		wget https://github.com/raspberrypi/firmware/tarball/$commit_long
	fi

	if [ ! -e $u_commit_long ]
	then	
		wget https://github.com/raspberrypi/userland/tarball/$u_commit_long
	fi
fi

# Retrieves and extracts latest raspberry pi firmware build from koji
latest_vc=$(armv6-koji latest-build $build_tag raspberrypi-vc | awk 'NR==3 {print $1}')
armv6-koji download-build --arch=src $latest_vc
rpm2cpio $latest_vc.src.rpm | cpio -imdv

# Updates the spec file
sed -i "0,/%global commit_date\s*.*/{s/%global commit_date\s*.*/%global commit_date  $date/}" raspberrypi-vc.spec
sed -i "0,/%global commit_short\s*.*/{s/%global commit_short\s*.*/%global commit_short $commit_short/}" raspberrypi-vc.spec
sed -i "0,/%global commit_long\s*.*/{s/%global commit_long\s*.*/%global commit_long  $commit_long/}" raspberrypi-vc.spec
sed -i "s/%global commit_userland_date\s*.*/%global commit_userland_date    $date/" raspberrypi-vc.spec
sed -i "s/%global commit_short_userland\s*.*/%global commit_short_userland   $u_commit_short/" raspberrypi-vc.spec
sed -i "s/%global commit_long_userland\s*.*/%global commit_long_userland    $u_commit_long/" raspberrypi-vc.spec
rpmdev-bumpspec -c 'updated to latest commit' -u 'pidora-auto-build' raspberrypi-vc.spec
sed -i "s/Release:\s*[0-9]*/Release:        1/" raspberrypi-vc.spec

# Sets up the document tree and moves files
rpmdev-setuptree
rpmdev-wipetree
cp raspberrypi-vc-demo-source-path-fixup.patch ~/rpmbuild/SOURCES
cp $commit_long ~/rpmbuild/SOURCES
cp $u_commit_long ~/rpmbuild/SOURCES
cp libs.conf ~/rpmbuild/SOURCES
cp raspberrypi-vc.spec ~/rpmbuild/SPECS

# Builds the rpm and uploads to koji
cd ~/rpmbuild/SPECS
rpmbuild -bs raspberrypi-vc.spec
cd ~/rpmbuild/SRPMS
file_name="raspberrypi-vc-${date}git${commit_short}-1.rpfr20.src.rpm"
echo 'Uploading to koji...'
task_id=$(armv6-koji build --scratch --wait $auto_tag $file_name | grep 'Created task:' | grep -o '[0-9]*')

# Reports success/failure
task_status=$(armv6-koji taskinfo $task_id | grep 'State:' | cut -d ' ' -f2)
echo "$task_status (ID: $task_id)"

# Sends email report
msg="Pidora firmware autobuild ${version} ${commit_long}\n
Status: $task_status\n
Task ID: $task_id\n
Link: http://japan.proximity.on.ca/koji/taskinfo?taskID=$task_id"

echo -e $msg | mail -s "[$task_status]Pidora firmware autobuild $(date +'%d/%m/%y')" $target_email
