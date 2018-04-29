#version=DEVEL
# Keyboard layouts
keyboard 'us'
# Root password
rootpw --iscrypted --lock locked
# System language
lang en_US.UTF-8
# Firewall configuration
firewall --enabled --service ssh
# Shutdown after installation
shutdown
# System timezone
timezone Etc/UTC --isUtc
# Use text mode install
text
# Network information
network --bootproto=dhcp --device link
repo --name="fedora" --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-$releasever&arch=$basearch
repo --name="updates" --mirrorlist=https://mirrors.fedoraproject.org/mirrorlist?repo=updates-released-f$releasever&arch=$basearch
# Use network installation
url --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-$releasever&arch=$basearch"
# System authorization information
#auth --useshadow --passalgo=sha512
# SELinux configuration
selinux --enforcing

# System services
services --enabled="sshd,systemd-networkd,systemd-resolved"

# System bootloader configuration
bootloader --append="no_timer_check net.ifnames=0 console=tty1 console=ttyS0,115200n8" --location=mbr --timeout=1
autopart --type=plain --nohome --noboot --noswap
# Clear the Master Boot Record
zerombr
# Partition clearing information
clearpart --all

user --name tobi --groups adm,systemd-journal,users,wheel --lock
sshkey --username tobi "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC6ETkRJbIpxOboarOL2fQyqDcUcK1Z4zYJFHj27uMmv+8/6pl5pn6MrunaTG2lsLjI+uwi3XBl1xagFypuKRzVZN6qIAICmToZlPYkdEXby6DRcFFDpziYS06zE97fKgzucjK+4RIkUccpmanlEDwm0UJzc55Jlpqj39ACYwkftXx7UZqVeMSOEultD1Z+buw+9wDQdkeAbeU8gabuMU00CGspmsB7jWiNuYY+DPeuZ3+GTP+SHM1wowucvbaOue4d208SwoY5We9w3iHdXDn2G9XHn1keRjHfUwjclaFY/xYTywlcsLTUaKK1sU1z0Po5q6m6El9BdSrMHx76LUC+qdkZDvDAbd5C2i0WZZUlHUKpqZAf9jNGkdjpgWkyKHQyPzyKr5M6TwyVJghe0gyKaBqOZf8oxdqj6aIqi5fFaYIcbTt8dU7JTOKS9pahS8IjC/GiLPixvzhatc5Zbt7FodhOzLDUN2iyhOX5hhNTYyUW75xnyuIg/WXSAwJJbusF5vIHBgMcd5F7H5Rd1XDpC/hAA8V9eqtu9woZMFdlRrC9bKn60e3G67bP8mX8/mzttDFT7hh74QZA98BTRjeDU6/I9YSI+dRjfPRSlneK4+jqiACD4Qjn+bPLhevCHaqQ1+1KyIEseyCYQe39pOkdk5/HEcK9qv06HT4KozHERw== tobi"

%post --erroronfail

mkdir -p /srv/formulas/salt-formula
git clone https://github.com/saltstack-formulas/salt-formula.git /srv/formulas/salt-formula

# setup systemd to boot to the right runlevel
echo -n "Setting default runlevel to multiuser text mode"
rm -f /etc/systemd/system/default.target
ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target
echo .

# this is installed by default but we don't need it in virt
# Commenting out the following for #1234504
# rpm works just fine for removing this, no idea why dnf can't cope
echo "Removing linux-firmware package."
rpm -e linux-firmware

# Another one needed at install time but not after that, and it pulls
# in some unneeded deps (like, newt and slang)
echo "Removing authconfig."
dnf -C -y erase authconfig

# instlang hack. (Note! See bug referenced above package list)
find /usr/share/locale -mindepth  1 -maxdepth 1 -type d -not -name en_US -exec rm -rf {} +
localedef --list-archive | grep -v ^en_US | xargs localedef --delete-from-archive
# this will kill a live system (since it's memory mapped) but should be safe offline
mv -f /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
build-locale-archive
echo '%_install_langs C:en:en_US:en_US.UTF-8' >> /etc/rpm/macros.image-language-conf


echo -n "Getty fixes"
# although we want console output going to the serial console, we don't
# actually have the opportunity to login there. FIX.
# we don't really need to auto-spawn _any_ gettys.
sed -i '/^#NAutoVTs=.*/ a\
NAutoVTs=0' /etc/systemd/logind.conf

echo -n "Network fixes"
# initscripts don't like this file to be missing.
# and https://bugzilla.redhat.com/show_bug.cgi?id=1204612
cat > /etc/systemd/network/10-default.network << EOF
[Match]
Name=eth0

[Network]
DHCP=yes
EOF

# use systemd-resolved
ln -sf /usr/lib/systemd/resolv.conf /etc/resolv.conf

# For cloud images, 'eth0' _is_ the predictable device name, since
# we don't want to be tied to specific virtual (!) hardware
rm -f /etc/udev/rules.d/70*
ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules

# generic localhost names
cat > /etc/hosts << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

EOF
echo .


# Because memory is scarce resource in most cloud/virt environments,
# and because this impedes forensics, we are differing from the Fedora
# default of having /tmp on tmpfs.
echo "Disabling tmpfs for /tmp."
systemctl mask tmp.mount

# make sure firstboot doesn't start
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

echo "Removing random-seed so it's not the same in every image."
rm -f /var/lib/systemd/random-seed

echo "Cleaning old dnf repodata."
# FIXME: clear history?
dnf clean all
truncate -c -s 0 /var/log/dnf.log
truncate -c -s 0 /var/log/dnf.rpm.log

echo "Update dnf.conf"
cat >> /etc/dnf/dnf.conf << EOF
install_weak_deps=False
EOF

echo "Import RPM GPG key"
releasever=$(rpm -q --qf '%{version}\n' fedora-release)
basearch=$(uname -i)
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-$releasever-$basearch

echo "Packages within this image:"
echo "-----------------------------------------------------------------------"
rpm -qa
echo "-----------------------------------------------------------------------"
# Note that running rpm recreates the rpm db files which aren't needed/wanted
rm -f /var/lib/rpm/__db*

# FIXME: is this still needed?
echo "Fixing SELinux contexts."
touch /var/log/cron
touch /var/log/boot.log
# ignore return code because UEFI systems with vfat filesystems
# that don't support selinux will give us errors
/usr/sbin/fixfiles -R -a restore || true

# remove ifcfg file created by anaconda
rm -f /etc/sysconfig/network-scripts/ifcfg-*

# add tobi to sudo users
echo -n "Setting sudoer permissions"
echo 'tobi ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/tobi-nopasswd
echo "."

if [ -n "$HOSTNAME" -a "$HOSTNAME" != "localhost" ]; then
  echo "Using hostname $HOSTNAME"
else
  IP=$(ip -j a l dev eth0 | jq -r '.[] | .addr_info[0].local // empty')
  IP=$(echo $IP | awk -F. '{print $4"."$3"." $2"."$1}')
  HOSTNAME=$(curl -qL "https://dns.google.com/resolve?name=${IP}.in-addr.arpa&type=PTR" | jq -r '.Answer[0].data' | sed -e 's/\.$//')
fi

[ -n "$HOSTNAME" ] && hostnamectl set-hostname $HOSTNAME

echo -n "Setting up salt provisioning"
STATES_REPO="/opt/git/states"
PILLAR_REPO="/opt/git/pillar"
GIT_REPOS="${STATES_REPO} ${PILLAR_REPO}"
for r in $GIT_REPOS
do
  mkdir -p $r
  pushd $r
  # maybe add --shared and change to git group
  git init --bare
  popd
done
chown -R tobi:tobi /opt/git

cat > /etc/salt/minion << EOF
master: 127.0.0.1
log_file: file:///dev/log
EOF

cat > /etc/salt/master << EOF
log_file: file:///dev/log
fileserver_backend:
  - roots
  - git

file_roots:
  base:
    - /srv/salt
    - /srv/formulas/salt-formula

gitfs_remotes:
  - file://${STATES_REPO}
ext_pillar:
  - git:
    - master file://${PILLAR_REPO}
EOF

systemctl enable salt-minion salt-master

# setup keys
salt-key --gen-keys=${HOSTNAME}
mkdir -p /etc/salt/pki/master/minions /etc/salt/pki/minion
cp ${HOSTNAME}.pub /etc/salt/pki/master/minions/${HOSTNAME}
mv ${HOSTNAME}.pem /etc/salt/pki/minion/minion.pem
mv ${HOSTNAME}.pub /etc/salt/pki/minion/minion.pub

echo $HOSTNAME > /etc/salt/minion_id
echo "."

# setup git hooks
mkdir -p /srv/reactor

cat > /srv/reactor/update_fileserver.sls << EOF
update_fileserver:
  runner.fileserver.update
apply_states:
  local.state.apply:
    - tgt: '${HOSTNAME}'
EOF

cat > /etc/salt/master.d/reactor.conf << EOF
reactor:
  - 'salt/fileserver/gitfs/update':
    - /srv/reactor/update_fileserver.sls
EOF

for r in $GIT_REPOS
do
cat > ${r}/hooks/post-receive << EOF
#!/usr/bin/env sh
sudo systemctl -q --no-pager status salt-master 2>&1 >/dev/null || sudo systemctl restart salt-master
sudo -u root salt-call event.fire_master update salt/fileserver/gitfs/update
EOF
chmod 755 ${r}/hooks/post-receive
done

%end

%packages --excludedocs --nocore --excludeWeakdeps
dnf
firewalld
git
grubby
hostname
iproute
jq
kernel-core
openssh-server
passwd
python2-pygit2
salt-master
salt-minion
sudo
systemd-udev
which
%end
