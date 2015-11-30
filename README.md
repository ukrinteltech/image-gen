Ubuntu packages:

sudo apt-get install cdbs debhelper gdisk scons qemu-utils

Build image:

./makebootimage.sh TARGET COREURL
   TARGET:
     vmware
     a10 (yet don't work)
   COREURL
     (for example )http://cdimage.ubuntu.com/ubuntu-core/releases/15.10/release/ubuntu-core-15.10-core-amd64.tar.gz
