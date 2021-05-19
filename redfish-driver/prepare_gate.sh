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

source /home/ubuntu/proxy

function install_packages {
    sudo apt -y update
    sudo apt -y purge python3-yaml python3-httplib2
    sudo apt -y install apache2 python3.8 python-pip isc-dhcp-server webfs python3-setuptools python3-pip socat vlan liberasurecode-dev libssl-dev ovmf virtualenv
    sudo chmod 600 /home/ubuntu/zuul_id_rsa
}

function configure_interface {
    ip1=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sudo sh -c 'echo web_root='/opt/stack/devstack/files' >> /etc/webfsd.conf'
    sudo sh -c 'echo web_ip='$ip1' >> /etc/webfsd.conf'
    sudo sh -c 'echo web_port=8010 >> /etc/webfsd.conf'
    sudo service webfs restart
}

function run_stack {

    local ironic_node
    local capabilities

    cd /opt/stack/devstack
    wget http://169.16.1.54:9999/ir-deploy-ilo.iso -P files/
    wget http://169.16.1.54:9999/rhel_7.6-uefi.img -P files/
    echo  >> /tmp/hardware_info
    cp /tmp/redfish-driver/HPE-CI-JOBS/redfish-driver/local.conf.sample local.conf
    ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sed -i "s/192.168.1.2/$ip/g" local.conf

    ./stack.sh

    sleep 30

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

function update_proliantutils {
    echo "Updating and installing proliantutils"
    cd /opt/stack/proliantutils
    git config --global user.email "proliantutils@gmail.com"
    git config --global user.name "proliantci"
    #git fetch https://review.opendev.org/x/proliantutils refs/changes/33/707933/1 && git cherry-pick FETCH_HEAD
    sudo pip3 install cryptography==3.2.0 setuptools
    sudo pip3 install -r requirements.txt
    sudo python3 setup.py install
}

install_packages
configure_interface
#update_ironic
#update_ironic_tempest_plugin
update_proliantutils
run_stack
