#!/bin/bash

# Setup
auto_tag='f20-rpfr-updates-automated'
build_tag='f20-rpfr-updates'
date=$(date +'%Y%m%d')
mkdir kerneltemp
cd kerneltemp

# Retrieves latest commit in default (most stable) branch
commit_long=$(git ls-remote https://github.com/raspberrypi/linux.git | grep HEAD | cut -f1)
commit_short=$(echo $commit_long | cut -c1-7)
wget https://github.com/raspberrypi/linux/tarball/$commit_long

# Retrieves and extracts latest raspberry pi kernel from koji
latest_kernel=$(armv6-koji latest-build $build_tag raspberrypi-kernel | awk 'NR==3 {print $1}')
armv6-koji download-build --arch=src $latest_kernel
rpm2cpio $latest_kernel.src.rpm | cpio -imdv

# Determines version number
branch=$(git ls-remote https://github.com/raspberrypi/linux.git | grep $commit_long | grep -o 'rpi-[0-9]*\.[0-9]*\..*')
sublevel=$(curl -s https://raw.githubusercontent.com/raspberrypi/linux/$branch/Makefile | grep -o 'SUBLEVEL = [0-9]*' | grep -o '[0-9]*')
version="$(echo $branch | grep -o -m1 '[0-9]*\.[0-9]*\.')$sublevel"

# Renames the config file
old_version=$(grep -o 'Version:\s*.*' raspberrypi-kernel.spec | grep -o '[0-9]*\.[0-9]*\.[0-9]*')
old_commit=$(grep -o '%global commit_short\s*.*' raspberrypi-kernel.spec | cut -d ' ' -f3)
bunzip2 pidora-config-$old_version-$old_commit.bz2
mv pidora-config-$old_version-$old_commit pidora-config-$version-$commit_short
bzip2 pidora-config-$version-$commit_short

# Updates the spec file
sed -i "s/%global commit_date\s*.*/%global commit_date  $date/" raspberrypi-kernel.spec
sed -i "s/%global commit_short\s*.*/%global commit_short $commit_short/" raspberrypi-kernel.spec
sed -i "s/%global commit_long\s*.*/%global commit_long  $commit_long/" raspberrypi-kernel.spec
sed -i "s/Version:\s*.*/Version:        $version/" raspberrypi-kernel.spec
sed -i "s/Release:\s*[0-9]*/Release:        1/" raspberrypi-kernel.spec

# Sets up the document tree and moves files
rpmdev-setuptree
rpmdev-wipetree
mv first32k.bin.bz2 ~/rpmbuild/SOURCES
mv $commit_long ~/rpmbuild/SOURCES
mv pidora-config-$version-$commit_short.bz2 ~/rpmbuild/SOURCES
mv raspberrypi-kernel.spec ~/rpmbuild/SPECS

# Cleans up after itself
rm *
cd ..
rmdir kerneltemp

# Builds the rpm and uploads to koji
cd ~/rpmbuild/SPECS
rpmbuild -bs raspberrypi-kernel.spec
cd ~/rpmbuild/SRPMS
echo 'Uploading to koji...'
file_name="raspberrypi-kernel-${version}-1.${date}git${commit_short}.rpfr20.src.rpm"
task_id=$(armv6-koji build --scratch --wait $auto_tag $file_name | grep 'Created task:' | grep -o '[0-9]*')

# Reports success/failure
task_status=$(armv6-koji taskinfo $task_id | grep 'State:' | cut -d ' ' -f2)
echo $task_status
