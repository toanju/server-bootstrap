#!/bin/bash

set -e

[ -f .config ] && . .config

VERSION=29
KICKSTART_URL=${KICKSTART_URL:-'updatethis'}
BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKDIR=${BASEDIR}/net-installer
ISO=$BASEDIR/${FTP_FILE}
ISO_ORIG=${WORKDIR}/boot.iso
MNT=${WORKDIR}/mnt
ISODIR=${WORKDIR}/iso

DL=https://download.fedoraproject.org/pub/fedora/linux/releases/$VERSION/Server/x86_64/os/images/boot.iso

pushd $BASEDIR

mkdir -p $ISODIR $MNT

# get net installer
[ -e $ISO_ORIG ] || curl -L $DL -o $ISO_ORIG

# extract net installer
sudo mount -o loop -o ro $ISO_ORIG $MNT
sudo rsync -av --delete $MNT/* $ISODIR
sudo umount $MNT

# *modifications*
# update permissions
sudo find $ISODIR -type d -exec chmod 755 {} \;
# update timeout 600 -> 10
sudo sed -i 's/^timeout 600$/timeout 10/' $ISODIR/isolinux/isolinux.cfg

# inject server.ks in append
#sudo sed -i "/^ \+append/ s/$/ ks=hd:LABEL=Fedora-S-dvd-x86_64-27:\/server.ks net.ifnames=0 ip=dhcp rd.info=1 inst.repo=cdrom:sr0 inst.ks=hd:sr0/" $ISODIR/isolinux/isolinux.cfg
#sudo sed -i "/^ \+append/ s/$/ ip=dhcp inst.repo=cdrom net.ifnames=0 inst.ks=hd:LABEL=Fedora-S-dvd-x86_64-27:\/ks.cfg/" $ISODIR/isolinux/isolinux.cfg
sudo sed -i "/^ \+append/ s@\$@ ip=dhcp inst.ks=${KICKSTART_URL} net.ifnames=0@" $ISODIR/isolinux/isolinux.cfg

# clean some files
#sudo rm -rf $ISODIR/images/{efiboot.img,macboot.img,product.img,pxeboot}
#sudo rm -rf $ISODIR/EFI

# create iso
[ -f $ISO ] && rm -f $ISO
pushd $ISODIR
sudo mkisofs -o $ISO -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -R -V "Fedora-S-dvd-x86_64-${VERSION}" .
popd

# add md5sum
sudo implantisomd5 $ISO

# pop basedir
popd
