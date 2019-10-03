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
export BOOT_OPTION=${BOOT_OPTION:-}
export SECURE_BOOT=${SECURE_BOOT:-}
export BOOT_LOADER=${BOOT_LOADER:-grub2}
export IRONIC_IPA_RAMDISK_DISTRO=ubuntu
export BRANCH=${ZUUL_BRANCH:-master}
export no_proxy=169.16.1.54
wget http://169.16.1.54:9999/proxy -P /home/ubuntu/
source /home/ubuntu/proxy
sudo chmod 0600 /home/ubuntu/zuul_id_rsa
wget http://169.16.1.54:9999/log_upload_ssh -P /home/ubuntu/
wget http://169.16.1.54:9999/config -P /home/ubuntu/.ssh/
sudo chmod 0600 /home/ubuntu/log_upload_ssh
sudo chmod 0664 /home/ubuntu/.ssh/config

function install_packages {
    sudo apt -y install apache2 python-pip isc-dhcp-server webfs python3-setuptools python3-pip socat vlan liberasurecode-dev libssl-dev
    sudo pip install setuptools
    sudo pip3 install proliantutils
    sudo chmod 600 /home/ubuntu/zuul_id_rsa
}

function clone_projects {
    sudo mkdir -p /opt/stack
    sudo chown ubuntu.ubuntu /opt/stack
    sudo chmod 0777 /opt/stack
    cd /opt/stack
    git clone https://opendev.org/openstack-dev/devstack.git
    git clone https://opendev.org/openstack/ironic.git
    git clone https://opendev.org/openstack/ironic-tempest-plugin.git
}

function configure_dhcp_server {
    wget http://169.16.1.54:9999/redfish_dhcp_server.txt -P /opt/stack/devstack/files/
    #mac=$(cat /tmp/hardware_info | awk '{print $2}')
    mac=98:f2:b3:2a:0e:3c
    sed -i "s/8c:dc:d4:af:78:ec/$mac/g" /opt/stack/devstack/files/redfish_dhcp_server.txt
    sudo sh -c 'cat /opt/stack/devstack/files/redfish_dhcp_server.txt >> /etc/dhcp/dhcpd.conf'
    sudo service isc-dhcp-server restart
}

function configure_interface {
    ip1=$(ip addr show ens3 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sudo sh -c 'echo web_root='/opt/stack/devstack/files' >> /etc/webfsd.conf'
    sudo sh -c 'echo web_ip='$ip1' >> /etc/webfsd.conf'
    sudo sh -c 'echo web_port=9999 >> /etc/webfsd.conf'
    sudo service webfs restart
    sudo modprobe 8021q
    sudo vconfig add ens3 100
    sudo ifconfig ens3.100 inet $ip1 netmask 255.255.255.0
}

function run_stack {

    local ironic_node
    local capabilities

    cd /opt/stack/devstack
    wget http://169.16.1.54:9999/ir-deploy-ilo.iso -P files/
    wget http://169.16.1.54:9999/fedora-wd-uefi.img -P files/
    echo  >> /tmp/hardware_info
    cp /tmp/redfish-driver/HPE-CI-JOBS/redfish-driver/local.conf.sample local.conf
    ip=$(ip addr show ens3 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sed -i "s/192.168.1.2/$ip/g" local.conf

    ./stack.sh

    #Reaccess to private network
    sudo ovs-vsctl del-br br-ens3
    sudo ip link set ens3 down
    sudo ip link set ens3 up

    #Create Node
    source /opt/stack/devstack/openrc admin admin
    #ilo_ip=$(cat /tmp/hardware_info | awk '{print $1}')
    #mac=$(cat /tmp/hardware_info | awk '{print $2}')
    ilo_ip=169.16.1.17
    mac=98:f2:b3:2a:0e:3c

    openstack baremetal node create --driver ilo --driver-info ilo_address=$ilo_ip --driver-info ilo_username=Administrator --driver-info ilo_password=weg0th@ce@r --driver-info console_port=5000

    ironic_node=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)

    openstack baremetal node manage $ironic_node
    openstack baremetal node provide $ironic_node
    openstack baremetal node set --driver-info ilo_deploy_iso=http://169.16.1.54:9999/fedora-raid-deploy-ank-proliant-tools.iso --instance-info image_source=http://169.16.1.54:9999/fedora-wd-uefi.img --instance-info image_checksum=17a6c6df66d4c90b05554cdc2285d851 --instance-info capabilities='{"boot_mode": "uefi"}' --property capabilities='boot_mode:uefi' $ironic_node

    openstack baremetal port create --node $ironic_node $mac
    openstack baremetal node power off $ironic_node

    # Run the tempest test.
    cd /opt/stack/tempest
    export OS_TEST_TIMEOUT=3000
    sudo tox -e all-plugin -- ironic_tempest_plugin.tests.scenario.ironic_standalone.test_basic_ops.BaremetalIloDirectWholediskHttpLink.test_ip_access_to_server
}

function update_ironic {
    cd /opt/stack/ironic
    git config --global user.email "proliantutils@gmail.com"
    git config --global user.name "proliantci"
    git fetch https://review.opendev.org/openstack/ironic refs/changes/25/454625/19 && git cherry-pick FETCH_HEAD
}

function update_ironic_tempest_plugin {
    cd /opt/stack/ironic-tempest-plugin
    #git fetch https://git.openstack.org/openstack/ironic-tempest-plugin refs/changes/52/535652/9 && git cherry-pick FETCH_HEAD
    sudo python3 setup.py install
}

install_packages
clone_projects
configure_dhcp_server
configure_interface
update_ironic
update_ironic_tempest_plugin
run_stack
