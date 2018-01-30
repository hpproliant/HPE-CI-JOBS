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
export BOOT_OPTION=${BOOT_OPTION:-}
export SECURE_BOOT=${SECURE_BOOT:-}
export BOOT_LOADER=${BOOT_LOADER:-grub2}
export IRONIC_IPA_RAMDISK_DISTRO=ubuntu
export BRANCH=${ZUUL_BRANCH:-master}

function install_packages {
    sudo apt -y install apache2
    sudo apt -y install python-pip
    sudo apt -y install bridge-utils
    sudo pip install setuptools
    sudo pip install proliantutils
}

function configure_bridge_interface {
    sudo brctl addbr br0
    sudo brctl addif br0 ens3
    sudo ifconfig br0 inet 10.13.120.209 netmask 255.255.255.224
    sudo ip addr flush dev ens3
    sudo ip route add 10.0.0.0/8 via 10.13.120.193 dev br0
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

function run_stack {

    local ironic_node
    local capabilities

    cd /opt/stack/devstack
    wget http://10.13.120.210:81/fedora-raid-deploy-ank-proliant-tools.iso -O files/ir-deploy-ilo.iso
    wget http://10.13.120.210:81/fedora-wd-uefi.qcow2 -O files/fedora-wd-uefi.img
    cp /tmp/agent-ilo/HPE-CI-JOBS/agent-ilo/local.conf.sample local.conf
    ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    sed -i "s/192.168.1.2/$ip/g" local.conf

    # Run stack.sh
    ./stack.sh

    # Modify the node to reflect the boot_mode and secure_boot capabilities.
    # Also modify the nova flavor accordingly.
    source /opt/stack/devstack/openrc admin admin
    ironic_node=$(ironic node-list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)
    capabilities="boot_mode:$BOOT_MODE"
    if [[ "$SECURE_BOOT" = "true" ]]; then
        capabilities="$capabilities,secure_boot:true"
        nova flavor-key baremetal set capabilities:secure_boot="true"
    fi
    ironic node-update $ironic_node add driver_info/ilo_deploy_iso=http://10.13.120.210:81/fedora-raid-deploy-ank-proliant-tools.iso
    ironic node-update $ironic_node add instance_info/image_source=http://10.13.120.210:81/fedora-wd-uefi.img instance_info/image_checksum=83b0671c9dfef5315c78de6da133c902
    ironic node-set-power-state $ironic_node off
    ironic node-update $ironic_node add properties/capabilities="$capabilities"

    # Run the tempest test.
    cd /opt/stack/ironic-tempest-plugin
    export OS_TEST_TIMEOUT=3000
    #tox -eall -- test_baremetal_server_ops
    tox -eall -- ironic_tempest_plugin.tests.scenario.ironic_standalone.test_basic_ops.BaremetalAgentIloWholediskHttpLink
#    tox -eall -- ironic_tempest_plugin.tests.scenario.ironic_standalone.test_basic_ops.BaremetalAgentIloPartitioned

}

function update_ironic {
    cd /opt/stack/ironic
    git config --global user.email "proliantutils@gmail.com"
    git config --global user.name "proliantci"
    git fetch https://git.openstack.org/openstack/ironic refs/changes/51/535651/1 && git cherry-pick FETCH_HEAD
    git fetch https://git.openstack.org/openstack/ironic refs/changes/25/454625/18 && git cherry-pick FETCH_HEAD
}

function update_ironic_tempest_plugin {
    cd /opt/stack/ironic-tempest-plugin
    git fetch https://git.openstack.org/openstack/ironic-tempest-plugin refs/changes/52/535652/2 && git cherry-pick FETCH_HEAD
}

install_packages
configure_bridge_interface
clone_projects
update_ironic
update_ironic_tempest_plugin
run_stack
