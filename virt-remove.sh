#!/bin/bash

virsh destroy test
virsh undefine test --remove-all-storage
