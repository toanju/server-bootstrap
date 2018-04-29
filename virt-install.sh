#!/bin/bash

BRIDGE=virbr0

virt-install --connect qemu:///system --name test --ram 1024 --vcpus 1 --disk size=4,format=qcow2,bus=virtio --cdrom ./my-net-installer.iso --network bridge=${BRIDGE},model=virtio --os-type=linux
