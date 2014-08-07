What it does (presently)
-----------------
- Downloads latest commits from the [Raspberry Pi github repo](https://github.com/raspberrypi)
- Downloads the latest [kernel](http://japan.proximity.on.ca/koji/packageinfo?packageID=11981) and [firmware](http://japan.proximity.on.ca/koji/packageinfo?packageID=11987) builds from the Pidora koji
- Unpackages the build, updates tarballs, config file (using defaults), and spec file, then repackages
- Uploads to koji as a scratch build
- Hangs for a really long time as it waits on koji, then reports back with status as 'failed' or 'closed'

What it should do (eventually)
-----------------
- Send email notification in case of failed upload
- Send email notification of all changed config settings
- Handle errors (gracefully)
- Be able to run as a cron job with little outside input
