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

function singapore_proxy {
    cd /home/ubuntu
    wget http://169.16.1.54:9999/singapore_proxy
    source /home/ubuntu/singapore_proxy
}

function install_packages {
    sudo apt -y update
    sudo apt -y purge python3-yaml python3-httplib2
    sudo apt -y install apache2 isc-dhcp-server ovmf webfs socat vlan liberasurecode-dev libssl-dev python3-pip python3-setuptools virtualenv
    #sudo pip install setuptools
    sudo pip3 install cryptography==3.2.0 setuptools
    sudo pip3 install proliantutils
    sudo chown ubuntu.ubuntu /var/www/html
    sudo chmod 600 /home/ubuntu/zuul_id_rsa
}

function install_requirements {
    sudo apt -y update
    cd /opt/stack/
    sudo pip install -r ironic/requirements.txt
    sudo pip install -r neutron/requirements.txt
    sudo pip install -r glance/requirements.txt
    sudo pip install -r requirements/requirements.txt
    sudo pip install -r swift/requirements.txt
    sudo pip install -r keystone/requirements.txt
    sudo pip install -r tempest/requirements.txt
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
    wget http://169.16.1.54:9999/ir-deploy-pxe_ilo.initramfs
    wget http://169.16.1.54:9999/ir-deploy-pxe_ilo.kernel
    wget http://169.16.1.54:9999/ubuntu-uefi.img
    wget http://169.16.1.54:9999/grubx64.efi
    wget http://169.16.1.54:9999/bootx64.efi
    wget http://169.16.1.54:9999/shim.efi
    wget http://169.16.1.54:9999/ipxe.efi
    cp ubuntu-uefi.img ir-deploy-pxe_ilo.kernel ir-deploy-pxe_ilo.initramfs /var/www/html
    # Add new line character in hardware_info so it will readable
    echo  >> /tmp/hardware_info

    cd /opt/stack/devstack/
    cp /tmp/pxe-ilo/HPE-CI-JOBS/pxe-ilo/local.conf.sample local.conf
    ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sed -i "s/192.168.1.2/$ip/g" local.conf
    sed -i "s/\$ADD_DEFAULT_ROUTE; \$ARP_CMD/\$ADD_DEFAULT_ROUTE/g" lib/neutron-legacy

    # Run stack.sh
    ./stack.sh

    sleep 30

    cp /opt/stack/devstack/files/ipxe.efi /opt/stack/data/ironic/tftpboot/
    sudo sed -i "s/bootx64.efi/ipxe.efi/g" /etc/ironic/ironic.conf
    sudo sed -i "s/pxe_grub_config.template/ipxe_config.template/g" /etc/ironic/ironic.conf

    #Reinstall Proliantutils
    sudo pip3 install proliantutils
    sleep 10
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
    #git fetch https://review.opendev.org/openstack/ironic-tempest-plugin refs/changes/79/708379/2 && git cherry-pick FETCH_HEAD
    sudo python3 setup.py install
}

singapore_proxy
install_packages
#configure_interface
#update_ironic
#update_ironic_tempest_plugin
#install_requirements
run_stack
