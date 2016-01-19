#!/bin/bash -i

USEPROXY="y"

TOPDIR=$PWD

mkdir -p out

TARGET=$1

COREURL=$2

PARTBOOT=/tmp/boot$$
PARTSYS=/tmp/sys$$



umount_disk_image() {
  if [ -d "$PARTBOOT" ] 
  then
   sudo umount $PARTBOOT
   rm -r $PARTBOOT
  fi

  if [ -d "$PARTSYS" ] 
  then
   sudo umount $PARTSYS
   rm -r $PARTSYS
  fi

  if [ -n "$NLOOP0" ]
  then
     sudo losetup -d "$NLOOP0"
     echo "Remove: $NLOOP0"
  fi

  if [ -n "$NLOOP1" ]
  then
     sudo losetup -d "$NLOOP1"
     echo "Remove: $NLOOP1"
  fi
}




error() {
    echo "ERROR: $@"
    umount_disk_image
    exit 1
}

case $TARGET in
vmware)
    IMAGESUFFIX=".vmdk"
    ;;
a10)
    IMAGESUFFIX=".img"
    ;;
*)
    error "Unsupported target $TARGET"
    ;;
esac

IMAGENAME=out/ddesk-system-${TARGET}

if test -f ${IMAGENAME}${IMAGESUFFIX}; then
    error "image already exists!"
fi

create_disk_image() {
    local util=$(which qemu-img)
    case $TARGET in
    vmware)
	if test ! "$util" = ""; then
	    qemu-img create -f vmdk -o subformat=monolithicFlat ${IMAGENAME}${IMAGESUFFIX} 3.8G
	else
	    vmware-vdiskmanager -c -s 3.8GB -a lsilogic -t 2 ${IMAGENAME}${IMAGESUFFIX}
	fi
	echo -ne "n\n1\n2048\n+100M\nef00\nn\n\n\n\n\nw\nY\nq\n" | gdisk ${IMAGENAME}-flat${IMAGESUFFIX}
	;;
    *)
	error "Unsupported target $TARGET"
	;;
    esac
}

mount_disk_image() {
    local offboot=$(gdisk -l ${IMAGENAME}-flat${IMAGESUFFIX} | grep '^\s*.1' | awk '{ print $2; }')
    offboot=$(($offboot*512))
    local sizeboot=$(($(gdisk -l ${IMAGENAME}-flat${IMAGESUFFIX} | grep '^\s*.1' | awk '{ print $3; }')*512 - $offboot))
    local offsys=$(gdisk -l ${IMAGENAME}-flat${IMAGESUFFIX} | grep '^\s*.2' | awk '{ print $2; }')
    offsys=$(($offsys*512))
    local sizesys=$(($(gdisk -l ${IMAGENAME}-flat${IMAGESUFFIX} | grep '^\s*.2' | awk '{ print $3; }')*512 - $offsys))

    mkdir -p $PARTBOOT
    NLOOP0=$(sudo losetup -f)
    sudo losetup $NLOOP0 ${IMAGENAME}-flat${IMAGESUFFIX} -o $offboot --sizelimit $sizeboot || error "losetup for boot partition"
    sudo mkfs.vfat $NLOOP0
    sudo mount $NLOOP0 $PARTBOOT

    NLOOP1=$(sudo losetup -f)
    mkdir -p $PARTSYS
    sudo losetup $NLOOP1 ${IMAGENAME}-flat${IMAGESUFFIX} -o $offsys --sizelimit $sizesys || error "losetup for system partition"
    sudo mkfs.ext4 $NLOOP1
    sudo mount $NLOOP1 $PARTSYS
}


unpack_root_archive() {
    local FILE=$1
    local PART=$2

    case "$FILE" in
    http://*|https://*|ftp://*)
	ROOTFSTMP="/tmp/rootfs$$.dat"
	wget "$FILE" -O "$ROOTFSTMP" || error "downloading archive!"
	sudo tar -xf $ROOTFSTMP -C $PART || error "unpacking!!!"
	rm -f "$TOOLSTMP"
	;;
    *)
	sudo tar -xf $FILE -C $PART || error "unpacking!!!"
	;;
    esac
}

create_disk_image

mount_disk_image

make -C packages/core-tweaks  package
make -C packages/core-updater package
cp -f packages/ddeskshell/ddeskshell_0.1-1_amd64.deb packages/

if test "$COREURL" != ""; then
    unpack_root_archive $COREURL $PARTSYS
    sudo cp -f /etc/resolv.conf ${PARTSYS}/etc/
    sudo mount -o bind /proc ${PARTSYS}/proc
    sudo chroot $PARTSYS locale-gen ru_RU.UTF-8 en_US.UTF-8

    CONF=/tmp/linux.conf$$

    sudo chroot $PARTSYS sed -ie 's/^\# deb /deb /' /etc/apt/sources.list
    if test "$USEPROXY" = "y"; then
	sudo chroot $PARTSYS bash -c "echo \"Acquire::http::Proxy \\\"${APT_PROXY-http://127.0.0.1:3142}\\\";\" > /etc/apt/apt.conf.d/01proxy"
    fi
    sudo chroot $PARTSYS apt-get update
    sudo chroot $PARTSYS bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get -y install linux-signed-image-generic sudo net-tools nano iputils-ping unity-control-center'
    EXTRAPACKAGES=
    if test -f files/packages; then
	EXTRAPACKAGES=$(cat files/packages)
    fi
    if test "$EXTRAPACKAGES" != ""; then
	sudo chroot $PARTSYS bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get -y install $EXTRAPACKAGES"
    fi

    sudo chroot $PARTSYS useradd -d /home/ubuntu -m ubuntu
    sudo chroot $PARTSYS passwd -d ubuntu
    sudo chroot $PARTSYS addgroup ubuntu adm
    sudo chroot $PARTSYS addgroup ubuntu sudo

    pkg=""
    instpkgs=""
    for pkg in packages/*.deb; do
	echo "Custom package: $(basename $pkg)"
	cp -f $pkg ${PARTSYS}/tmp/
	instpkgs="$instpkgs /tmp/$(basename $pkg)"
    done
    ls -l ${PARTSYS}/tmp/
    echo "Packages for installation: $instpkgs"
    if test "$instpkgs" != ""; then
	sudo chroot $PARTSYS dpkg -i $instpkgs
	sudo chroot $PARTSYS rm -f $instpkgs
	sudo chroot $PARTSYS bash -c "export DEBIAN_FRONTEND=noninteractive; apt-get -y install -f"
    fi

	sudo chroot $PARTSYS bash -c 'update-alternatives --install /usr/bin/x-session-manager \
                        x-session-manager /usr/bin/openbox-session 100 --slave \
                        /usr/share/man/man1/x-session-manager.1.gz \
                        x-session-manager.1.gz /usr/share/man/man1/openbox-session.1.gz'



    if test "$USEPROXY" = "y"; then
	sudo rm -f ${PARTSYS}/etc/apt/apt.conf.d/01proxy
    fi
    sudo rm -f -r ${PARTSYS}/usr/share/applications
    sudo unzip files/applications.zip -d ${PARTSYS}/usr/share
    sudo rm -f -r ${PARTSYS}/usr/share/unity-control-center
    sudo unzip files/unity-control-center.zip -d ${PARTSYS}/usr/share
    mkdir -p ${PARTSYS}/home/ubuntu/.config/openbox/
    sudo cp -f files/rc.xml ${PARTSYS}/home/ubuntu/.config/openbox/
    sudo cp -f files/locale ${PARTSYS}/etc/default/locale
   
    sudo chroot $PARTSYS rm -rf /var/cache/apt/*
    sudo chroot $PARTSYS bash -c 'kill -9 $(cat /run/dbus/pid)'
    sudo umount ${PARTSYS}/proc

cat > $CONF << EOF
"Boot with standard options"        "ro root=/dev/disk/by-uuid/$(sudo blkid -o value -s UUID $NLOOP1) quiet splash intel_pstate=enable"
"Boot to single-user mode"          "ro root=/dev/disk/by-uuid/$(sudo blkid -o value -s UUID $NLOOP1) quiet splash single"
"Boot with minimal options"         "ro root=/dev/disk/by-uuid/$(sudo blkid -o value -s UUID $NLOOP1)"
EOF
    sudo cp $CONF ${PARTSYS}/boot/refind_linux.conf

cat > $CONF << EOF
UUID=$(sudo blkid -o value -s UUID $NLOOP1) /               ext4    noatime,errors=remount-ro 0       0
UUID=$(sudo blkid -o value -s UUID $NLOOP0) /boot/efi       vfat    umask=0077      0       1
tmpfs      /tmp          tmpfs      defaults,noatime,mode=1777    0    0
EOF
    sudo cp -f $CONF ${PARTSYS}/etc/fstab

cat > $CONF << EOF
auto eth0
iface eth0 inet dhcp
EOF
    sudo cp -f $CONF ${PARTSYS}/etc/network/interfaces.d/eth0

    rm -f $CONF

    sudo mkdir -p ${PARTSYS}/boot/efi
    sudo kill -9 $(sudo lsof $PARTSYS 2>/dev/null | awk '{ print $2; }' | uniq | grep '^[0-9]')

    ls -l $PARTSYS
    ls -l ${PARTSYS}/boot
    ls -l ${PARTSYS}/lib
else
        error "No system root archive!"
fi

if test "$TARGET" = "vmware"; then
    XTMP=/tmp/efi$$
    mkdir -p $XTMP
    unzip files/refind-bin-0.9.0.zip -d $XTMP
    sudo mkdir -p ${PARTBOOT}/EFI/boot
    sudo cp -R ${XTMP}/refind-bin-0.9.0/refind/* ${PARTBOOT}/EFI/boot
    sudo cp -f files/refind.conf ${PARTBOOT}/EFI/boot/
    cd ${PARTBOOT}/EFI/boot
    sudo mv refind_x64.efi bootx64.efi
    sudo mv refind_ia32.efi bootia32.efi
    cd $TOPDIR
    ls -l ${PARTBOOT}/EFI/boot
    cp files/DDESK.vmx out/
fi

umount_disk_image

rm -f packages/*.changes packages/*.deb
