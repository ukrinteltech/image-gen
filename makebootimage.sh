#!/bin/bash

TOPDIR=$PWD

mkdir -p out

TARGET=$1

COREURL=$2

PARTBOOT=/tmp/boot$$
PARTSYS=/tmp/sys$$

error() {
    echo "ERROR: $@"

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
    error "disk already exists!"
fi

create_disk_image() {
    case $TARGET in
    vmware)
	vmware-vdiskmanager -c -s 2GB -a lsilogic -t 2 ${IMAGENAME}${IMAGESUFFIX}
	echo -ne "n\n1\n2048\n+100M\nef00\nn\n\n\n\n\nw\nY\nq\n" | gdisk ${IMAGENAME}-flat${IMAGESUFFIX}
	;;
    *)
	error "Unsupported target $TARGET"
	;;
    esac
}

mount_disk_image() {
    local offboot=$(gdisk -l ${IMAGENAME}-flat${IMAGESUFFIX} | grep '^\s*.1' | awk '{ print $2*512; }')
    local sizeboot=$(($(gdisk -l ${IMAGENAME}-flat${IMAGESUFFIX} | grep '^\s*.1' | awk '{ print $3*512; }') - $offboot))
    local offsys=$(gdisk -l ${IMAGENAME}-flat${IMAGESUFFIX} | grep '^\s*.2' | awk '{ print $2*512; }')
    local sizesys=$(($(gdisk -l ${IMAGENAME}-flat${IMAGESUFFIX} | grep '^\s*.2' | awk '{ print $3*512; }') - $offsys))

    mkdir -p $PARTBOOT
    sudo losetup /dev/loop0 ${IMAGENAME}-flat${IMAGESUFFIX} -o $offboot --sizelimit $sizeboot || error "losetup for boot partition"
    sudo mkfs.vfat /dev/loop0
    sudo mount /dev/loop0 $PARTBOOT

    mkdir -p $PARTSYS
    sudo losetup /dev/loop1 ${IMAGENAME}-flat${IMAGESUFFIX} -o $offsys --sizelimit $sizesys || error "losetup for system partition"
    sudo mkfs.ext4 /dev/loop1
    sudo mount /dev/loop1 $PARTSYS
}

umount_disk_image() {
    sudo umount $PARTBOOT
    sudo losetup -d /dev/loop0
    sudo umount $PARTSYS
    sudo losetup -d /dev/loop1
}

unpack_root_archive() {
    local FILE=$1
    local PART=$2

    case "$FILE" in
    http://*|https://*|ftp://*)
	ROOTFSTMP="/tmp/rootfs$$.dat"
	wget "$FILE" -O "$ROOTFSTMP" || error "downloading archive!"
	sudo tar -xf $ROOTFSTMP -C $PART
	rm -f "$TOOLSTMP"
	;;
    *)
	sudo tar -xf $FILE -C $PART
	;;
    esac
}

create_disk_image

mount_disk_image

make -C packages/core-tweaks package

if test "$COREURL" != ""; then
    unpack_root_archive $COREURL $PARTSYS
    sudo cp -f /etc/resolv.conf ${PARTSYS}/etc/
    sudo mount -o bind /proc ${PARTSYS}/proc
    sudo chroot $PARTSYS locale-gen ru_RU.UTF-8 en_US.UTF-8
    sudo chroot $PARTSYS sed -ie 's/^\# deb /deb /' /etc/apt/sources.list
    sudo chroot $PARTSYS apt-get update
    sudo chroot $PARTSYS bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get -y install linux-signed-image-generic sudo net-tools nano iputils-ping'
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

    sudo chroot $PARTSYS bash -c 'kill -9 $(cat /run/dbus/pid)'
    sudo umount ${PARTSYS}/proc

    CONF=/tmp/linux.conf$$

cat > $CONF << EOF
"Boot with standard options"        "ro root=/dev/disk/by-uuid/$(sudo blkid -o value -s UUID /dev/loop1) quiet splash intel_pstate=enable"
"Boot to single-user mode"          "ro root=/dev/disk/by-uuid/$(sudo blkid -o value -s UUID /dev/loop1) quiet splash single"
"Boot with minimal options"         "ro root=/dev/disk/by-uuid/$(sudo blkid -o value -s UUID /dev/loop1)"
EOF
    sudo cp $CONF ${PARTSYS}/boot/refind_linux.conf

cat > $CONF << EOF
UUID=$(sudo blkid -o value -s UUID /dev/loop1) /               ext4    noatime,errors=remount-ro 0       0
UUID=$(sudo blkid -o value -s UUID /dev/loop0) /boot/efi       vfat    umask=0077      0       1
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

    ls -l $PARTSYS
    ls -l $PARTSYS/boot
    ls -l $PARTSYS/lib
else
    umount_disk_image
    error "No system root archive!"
fi

if test "$TARGET" = "vmware"; then
    XTMP=/tmp/efi$$
    mkdir -p $XTMP
    unzip files/refind-bin-0.9.0.zip -d $XTMP
    sudo mkdir -p $PARTBOOT/EFI/boot
    sudo cp -R ${XTMP}/refind-bin-0.9.0/refind/* $PARTBOOT/EFI/boot
    sudo cp -f files/refind.conf $PARTBOOT/EFI/boot/
    cd $PARTBOOT/EFI/boot
    sudo mv refind_x64.efi bootx64.efi
    sudo mv refind_ia32.efi bootia32.efi
    cd $TOPDIR
    ls -l $PARTBOOT/EFI/boot
    cp files/DDESK.vmx out/
fi

umount_disk_image

rm -f packages/*.changes packages/*.deb
