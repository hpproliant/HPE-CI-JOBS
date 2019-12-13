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
export no_proxy=169.16.1.54
wget http://169.16.1.54:9999/proxy -P /home/ubuntu/
source /home/ubuntu/proxy
sudo chmod 0600 /home/ubuntu/zuul_id_rsa
wget http://169.16.1.54:9999/log_upload_ssh -P /home/ubuntu/
wget http://169.16.1.54:9999/config -P /home/ubuntu/.ssh/
sudo chmod 0600 /home/ubuntu/log_upload_ssh
sudo chmod 0664 /home/ubuntu/.ssh/config

function install_packages {
    sudo apt -y install apache2
    sudo apt -y install python-pip
    sudo apt -y install python3-pip
    sudo apt -y install python3-setuptools
    sudo apt -y install isc-dhcp-server ovmf
    sudo pip install setuptools
    sudo pip3 install proliantutils
    sudo chown ubuntu.ubuntu /var/www/html
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
    wget http://169.16.1.54:9999/redfish_pxe_dhcp_server.txt -P /opt/stack/devstack/files/
    ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    mac=$(cat /tmp/hardware_info |cut -f2 -d ' ')
    sed -i "s/8.8.8.8/$ip/g" /opt/stack/devstack/files/redfish_pxe_dhcp_server.txt
    sed -i "s/8c:dc:d4:af:7d:ac/$mac/g" /opt/stack/devstack/files/redfish_pxe_dhcp_server.txt
    sudo cp /opt/stack/devstack/files/redfish_pxe_dhcp_server.txt /etc/dhcp/dhcpd.conf
    sudo service isc-dhcp-server restart
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
    sed -i 's|ironmantesting|ironmantesting /redfish/v1/Systems/1|' /tmp/hardware_info
    echo  >> /tmp/hardware_info

    cd /opt/stack/devstack/
    cp /tmp/redfish-pxe-driver/HPE-CI-JOBS/redfish-pxe-driver/local.conf.sample local.conf
    ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sed -i "s/192.168.1.2/$ip/g" local.conf

    # Run stack.sh
    ./stack.sh
    cp /opt/stack/devstack/files/ipxe.efi /opt/stack/data/ironic/tftpboot/
    sudo sed -i "s/bootx64.efi/ipxe.efi/g" /etc/ironic/ironic.conf
    sudo sed -i "s/pxe_grub_config.template/ipxe_config.template/g" /etc/ironic/ironic.conf
    sudo systemctl restart devstack@ir-api
    sudo systemctl restart devstack@ir-cond

    #Reaccess to private network
    sudo ovs-vsctl del-br br-ens2
    sudo ip link set ens2 down
    sudo ip link set ens2 up

    #Create Node
    source /opt/stack/devstack/openrc admin admin
    ilo_ip=$(cat /tmp/hardware_info | awk '{print $1}')
    mac=$(cat /tmp/hardware_info | awk '{print $2}')

    openstack baremetal node create --driver ilo --driver-info ilo_address=$ilo_ip --driver-info ilo_username=Administrator --driver-info ilo_password=weg0th@ce@r --driver-info console_port=5000

    ironic_node=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)

    openstack baremetal node manage $ironic_node
    openstack baremetal node provide $ironic_node
    openstack baremetal node set --driver-info deploy_kernel=http://169.16.1.54:9999/ir-deploy-pxe_ilo.kernel --driver-info deploy_ramdisk=http://169.16.1.54:9999/ir-deploy-pxe_ilo.initramfs --instance-info image_source=http://169.16.1.54:9999/ubuntu-uefi.img --instance-info image_checksum=a46f6297446f1197510839ef70d667c5 --instance-info capabilities='{"boot_mode": "uefi"}' --instance-info capabilities='{"boot_option": "local"}' --property capabilities='boot_mode:uefi' $ironic_node

    openstack baremetal port create --node $ironic_node $mac
    openstack baremetal node power off $ironic_node

    # Run the tempest test.
    cd /opt/stack/tempest
    export OS_TEST_TIMEOUT=3000
    sudo tox -e all -- ironic_standalone.test_basic_ops.BaremetalIloPxeWholediskHttpLink.test_ip_access_to_server
}

function update_ironic {
    cd /opt/stack/ironic
    git config --global user.email "proliantutils@gmail.com"
    git config --global user.name "proliantci"
}

function update_ironic_tempest_plugin {
    cd /opt/stack/ironic-tempest-plugin
    #git fetch https://git.openstack.org/openstack/ironic-tempest-plugin refs/changes/52/535652/11 && git cherry-pick FETCH_HEAD
    sudo python3 setup.py install
}

install_packages
clone_projects
configure_dhcp_server
#configure_interface
update_ironic
update_ironic_tempest_plugin
run_stack
