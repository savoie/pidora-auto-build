#!/bin/bash

# Setup
auto_tag='f20-rpfr-updates-automated'
build_tag='f20-rpfr-updates'
date=$(date +'%Y%m%d')
mkdir vctemp
cd vctemp

# Retrieves latest firmware commit in default (most stable) branch
commit_long=$(git ls-remote https://github.com/raspberrypi/firmware.git | grep HEAD | cut -f1)
commit_short=$(echo $commit_long | cut -c1-7)
wget https://github.com/raspberrypi/firmware/tarball/$commit_long

# Retrieves latest userland commit in default (most stable) branch
u_commit_long=$(git ls-remote https://github.com/raspberrypi/userland.git | grep HEAD | cut -f1)
u_commit_short=$(echo $u_commit_long | cut -c1-7)
wget https://github.com/raspberrypi/userland/tarball/$u_commit_long

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
sed -i "s/Release:\s*[0-9]*/Release:        1/" raspberrypi-vc.spec

# Sets up the document tree and moves files
rpmdev-setuptree
rpmdev-wipetree
mv raspberrypi-vc-demo-source-path-fixup.patch ~/rpmbuild/SOURCES
mv $commit_long ~/rpmbuild/SOURCES
mv $u_commit_long ~/rpmbuild/SOURCES
mv libs.conf ~/rpmbuild/SOURCES
mv raspberrypi-vc.spec ~/rpmbuild/SPECS

# Cleans up after itself
rm *
cd ..
rmdir vctemp

# Builds the rpm and uploads to koji
cd ~/rpmbuild/SPECS
rpmbuild -bs raspberrypi-vc.spec
cd ~/rpmbuild/SRPMS
file_name="raspberrypi-vc-${date}git${commit_short}-1.rpfr20.src.rpm"
echo 'Uploading to koji...'
task_id=$(armv6-koji build --scratch --wait $auto_tag $file_name | grep 'Created task:' | grep -o '[0-9]*')

# Reports success/failure
task_status=$(armv6-koji taskinfo $task_id | grep 'State:' | cut -d ' ' -f2)
echo $task_status
