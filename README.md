####Script to automate Pidora kernel and firmware builds.
- Downloads latest commits from the [Raspberry Pi github repo](https://github.com/raspberrypi)
- Checks whether new commits have been made since last build (only runs if necessary)
- Downloads the latest [kernel](http://japan.proximity.on.ca/koji/packageinfo?packageID=11981) and [firmware](http://japan.proximity.on.ca/koji/packageinfo?packageID=11987) builds from the Pidora koji
- Unpackages the build, updates tarballs, config file (using defaults), and spec file, then repackages
- Uploads to koji in test tag
- Sends an email notification containing task info and changed config settings

####Dependencies
- **fedora-packager** must be [installed](https://fedoraproject.org/wiki/Using_the_Koji_build_system?rd=PackageMaintainers/UsingKoji#Fedora_Account_System</u>.28FAS2.29_Setup) and [configured for armv6hl](http://blog.chris.tylers.info/index.php?/archives/272-Acessing-the-armv6hl-Koji-Buildsystem.html)

####Preferences
#####Parameters:
- **-k or --kernel:** Only builds new kernel
- **-f or --firmware:** Only builds new firmware
- **--force:** Forces the script to execute regardless of whether or not a new commit has been made
- **--scratch:** Submits the build as a scratch build

#####The following can be customized by modifying .buildconfig:
- Source and destination tag(s)
- Target email for reports
- Path to desired build directory
- Most stable git branches
- (Optional) Git commit ids to use for build
- (Optional) Koji build sources for use as 'framework' for build

