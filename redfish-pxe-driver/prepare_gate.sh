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
export PATH=$PATH:/var/lib/gems/1.8/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games
export DIB_DEPLOY_ISO_KERNEL_CMDLINE_ARGS="console=ttyS1"
export IRONIC_USER_IMAGE_PREFERRED_DISTRO=${IRONIC_USER_IMAGE_PREFERRED_DISTRO:-fedora}
export BOOT_LOADER=${BOOT_LOADER:-grub2}

source /home/ubuntu/proxy

function install_packages {
    sudo apt -y update
    sudo apt -y install apache2
    sudo apt -y install python-pip
    sudo apt -y install python3-pip
    sudo apt -y install python3-setuptools
    sudo apt -y install isc-dhcp-server ovmf virtualenv
    sudo pip install setuptools
    sudo chown ubuntu.ubuntu /var/www/html
}

function configure_interface {
    ip1=$(ip addr show ens3 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sudo modprobe 8021q
    sudo vconfig add ens3 100
    sudo ifconfig ens3.100 inet $ip1 netmask 255.255.255.0
}

function run_stack {

    local ironic_node
    local capabilities

    cd /opt/stack/devstack/files
    wget http://169.16.1.54:9999/ir-deploy-redfish.initramfs
    wget http://169.16.1.54:9999/ir-deploy-redfish.kernel
    wget http://169.16.1.54:9999/rhel_7.6-uefi.img
    wget http://169.16.1.54:9999/grubx64.efi
    wget http://169.16.1.54:9999/bootx64.efi
    wget http://169.16.1.54:9999/shim.efi
    wget http://169.16.1.54:9999/ipxe.efi
    cp ir-deploy-redfish.initramfs ir-deploy-redfish.kernel rhel_7.6-uefi.img /var/www/html
    # Add new line character in hardware_info so it will readable
    #sed -i 's|ironmantesting|ironmantesting /redfish/v1/Systems/1|' /tmp/hardware_info
    #echo  >> /tmp/hardware_info

    cd /opt/stack/devstack/
    cp /tmp/redfish-pxe-driver/HPE-CI-JOBS/redfish-pxe-driver/local.conf.sample local.conf
    ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sed -i "s/192.168.1.2/$ip/g" local.conf

    # Run stack.sh
    ./stack.sh

    sleep 30
    cp /opt/stack/devstack/files/ipxe.efi /opt/stack/data/ironic/tftpboot/
    sudo sed -i "s/bootx64.efi/ipxe.efi/g" /etc/ironic/ironic.conf
    sudo sed -i "s/pxe_grub_config.template/ipxe_config.template/g" /etc/ironic/ironic.conf
    sudo systemctl restart devstack@ir-api
    sleep 10
    sudo systemctl restart devstack@ir-cond
    sleep 10

    #Reaccess to private network
    sudo ovs-vsctl del-br br-ens2
    sudo ip link set ens2 down
    sudo ip link set ens2 up
}

function update_ironic {
    cd /opt/stack/ironic
    git config --global user.email "proliantutils@gmail.com"
    git config --global user.name "proliantci"
}

function update_ironic_tempest_plugin {
    cd /opt/stack/ironic-tempest-plugin
    git config --global user.email "proliantutils@gmail.com"
    git config --global user.name "proliantci"
    #git fetch https://review.opendev.org/openstack/ironic-tempest-plugin refs/changes/79/708379/3 && git cherry-pick FETCH_HEAD
    sudo python3 setup.py install
}

function update_proliantutils {
    echo "Updating and installing proliantutils"
    cd /opt/stack/proliantutils
    git config --global user.email "proliantutils@gmail.com"
    git config --global user.name "proliantci"
    #git fetch https://review.opendev.org/x/proliantutils refs/changes/33/707933/1 && git cherry-pick FETCH_HEAD
    sudo pip3 install cryptography==3.2.0
    sudo pip3 install -r requirements.txt
    sudo python3 setup.py install
}

install_packages
#configure_interface
#update_ironic
#update_ironic_tempest_plugin
update_proliantutils
run_stack
