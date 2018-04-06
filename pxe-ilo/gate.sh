#!/bin/bash -x

# Gate script for running tempest tests with iLO drivers in different
# configurations.  The following environment variables are expected:
#
# ILO_HWINFO_GEN8_SYSTEM - Hardware info for Gen8 system.
# ILO_HWINFO_GEN9_SYSTEM - Hardware info for Gen9 system.
# IRONIC_ELILO_EFI - Absolute path of elilo.efi file
# IRONIC_FEDORA_SHIM - Absolute path of fedora signed shim.efi
# IRONIC_FEDORA_GRUBX64 - Absolute path of fedora signed grubx64.efi
# IRONIC_UBUNTU_SHIM - Absolute path of ubuntu signed shim.efi
# IRONIC_UBUNTU_GRUBX64 - Absolute path of grub signed grubx64.efi
# http_proxy - Proxy settings
# https_proxy - Proxy settings
# HTTP_PROXY - Proxy settings
# HTTPS_PROXY - Proxy settings
# no_proxy - Proxy settings

env

set -e
set -x
set -o pipefail
echo "We are inside agent gate"
export PATH=$PATH:/var/lib/gems/1.8/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games
export DIB_DEPLOY_ISO_KERNEL_CMDLINE_ARGS="console=ttyS1"
export IRONIC_USER_IMAGE_PREFERRED_DISTRO=${IRONIC_USER_IMAGE_PREFERRED_DISTRO:-fedora}
export BOOT_LOADER=${BOOT_LOADER:-grub2}

function install_packages {
    sudo apt -y install apache2
    sudo apt -y install python-pip
    sudo apt -y install isc-dhcp-server
    sudo pip install setuptools
    sudo pip install proliantutils
    sudo chown ubuntu.ubuntu /var/www/html
    #wget http://mirror.ord.rax.openstack.org/wheel/ubuntu-16.04-x86_64/tinyrpc/tinyrpc-0.7-py2-none-any.whl
    #sudo pip install tinyrpc-0.7-py2-none-any.whl
}

function clone_projects {
    sudo mkdir -p /opt/stack
    sudo chown ubuntu.ubuntu /opt/stack
    sudo chmod 0777 /opt/stack
    cd /opt/stack
    git clone https://github.com/openstack-dev/devstack.git
    git clone https://github.com/openstack/ironic.git
    git clone https://github.com/openstack/ironic-tempest-plugin.git
}

function configure_dhcp_server {
    wget http://10.13.120.214:9999/pxe_dhcp_server.txt -P /opt/stack/devstack/files/
    ip=$(ip addr show ens3 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    mac=$(cat hardware_info |cut -f2 -d ' ')
    sed -i "s/8.8.8.8/$ip/g" /opt/stack/devstack/files/pxe_dhcp_server.txt
    sed -i "s/8c:dc:d4:af:7d:ac/$mac/g" /opt/stack/devstack/files/pxe_dhcp_server.txt
    sudo cp /opt/stack/devstack/files/pxe_dhcp_server.txt /etc/dhcp/dhcpd.conf
    sudo service isc-dhcp-server restart
}

function configure_interface {
    ip1=$(ip addr show ens3 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sudo ip route add 10.0.0.0/8 via 10.13.120.193 dev ens3
    sudo modprobe 8021q
    sudo vconfig add ens3 100
    sudo ifconfig ens3.100 inet $ip1 netmask 255.255.255.224
}

function run_stack {

    local ironic_node
    local capabilities

    cd /opt/stack/devstack/files
    wget http://10.13.120.214:9999/cirros-0.3.5-x86_64-uec.tar.gz
    wget http://10.13.120.214:9999/cirros-0.3.5-x86_64-disk.img
    wget http://10.13.120.214:9999/ir-deploy-pxe_ilo.initramfs
    wget http://10.13.120.214:9999/ir-deploy-pxe_ilo.kernel
    wget http://10.13.120.214:9999/fedora-wd-uefi.img
    wget http://10.13.120.214:9999/grubx64.efi
    wget http://10.13.120.214:9999/bootx64.efi
    wget http://10.13.120.214:9999/shim.efi
    wget http://10.13.120.214:9999/ipxe.efi
    cd /opt/stack/devstack/
    cp /tmp/pxe-ilo/HPE-CI-JOBS/pxe-ilo/local.conf.sample local.conf
    ip=$(ip addr show ens3 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sed -i "s/192.168.1.2/$ip/g" local.conf
    # Run stack.sh
    ./stack.sh
    cp /opt/stack/devstack/files/ipxe.efi /opt/stack/data/ironic/tftpboot/
    
    # Modify the node to reflect the boot_mode and secure_boot capabilities.
    # Also modify the nova flavor accordingly.
    sudo ovs-vsctl del-br br-ens3.100
    source /opt/stack/devstack/openrc admin admin
    ironic_node=$(ironic node-list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)
    #ironic node-update $ironic_node add driver_info/ilo_deploy_iso=http://10.13.120.214:9999/fedora-raid-deploy-ank-proliant-tools.iso
    ironic node-update $ironic_node add driver_info/deploy_kernel=http://10.13.120.214:9999/ir-deploy-pxe_ilo.kernel driver_info/deploy_ramdisk=http://10.13.120.214:9999/ir-deploy-pxe_ilo.initramfs 
    ironic node-update $ironic_node add instance_info/image_source=http://10.13.120.214:9999/fedora-wd-uefi.img instance_info/image_checksum=17a6c6df66d4c90b05554cdc2285d851
    ironic node-set-power-state $ironic_node off

    # Run the tempest test.
    cd /opt/stack/tempest
    export OS_TEST_TIMEOUT=3000
    sudo tox -e all-plugin -- ironic_tempest_plugin.tests.scenario.ironic_standalone.test_basic_ops.BaremetalIloPxeWholediskHttpLink.test_ip_access_to_server
}

function update_ironic {
    cd /opt/stack/ironic
    git config --global user.email "proliantutils@gmail.com"
    git config --global user.name "proliantci"
    git fetch https://git.openstack.org/openstack/ironic refs/changes/51/535651/3 && git cherry-pick FETCH_HEAD
    git fetch https://git.openstack.org/openstack/ironic refs/changes/25/454625/18 && git cherry-pick FETCH_HEAD
    git fetch https://git.openstack.org/openstack/ironic refs/changes/26/454026/24 && git cherry-pick FETCH_HEAD
}

function update_ironic_tempest_plugin {
    cd /opt/stack/ironic-tempest-plugin
    git fetch https://git.openstack.org/openstack/ironic-tempest-plugin refs/changes/52/535652/8 && git cherry-pick FETCH_HEAD
    sudo python setup.py install
}

install_packages
clone_projects
configure_dhcp_server
configure_interface
update_ironic
update_ironic_tempest_plugin
run_stack
