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

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$DIR/functions.sh"

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

#function stop_ilo_gate_process {
#    local pid
#    local stopped#
#
#    pid=$(pidof $1 || true)
#    if [[ -n "$pid" ]]; then
#        stopped=$(sudo kill $pid)
#    fi
#}

function restart_service {
    local restarted

    echo "Restarting $1 ..."
    restarted=$(sudo service $1 restart)
}

function install_packages{
    sudo apt install apache2
	sudo apt install openvswitch-switch
}

function clone_projects{
    sudo mkdir -p /opt/stack
    cd /opt/stack
    git clone https://github.com/openstack-dev/devstack.git
    git clone https://github.com/openstack/ironic.git
    git clone https://github.com/openstack/ironic-tempest-plugin.git
}

function run_stack {

    local ironic_node
    local capabilities
    local hardware_info
    local root_device_hint

    # Move the current local.conf to the logs directory.
    #cp /opt/stack/devstack/local.conf $LOGDIR

    cd /opt/stack/devstack
    wget http://10.13.120.196:9999/fedora-wd-uefi.qcow2 -O files/fedora-wd-uefi.qcow2
    cp /tmp/agent-ilo/HPE-CI-JOBS/agent-ilo/local.conf.sample local.conf
    ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    echo "HOST_IP=$ip" >> local.conf
    # Do unstack to make sure there aren't any previous leftover services.
    #./unstack.sh

    #Restart services
    #restart_service "openvswitch-switch"

    # Final environment variable list.
    echo "-----------------------------------"
    echo "Final list of environment variables"
    echo "-----------------------------------"
    env
    echo "-----------------------------------"

    # Run stack.sh
    ./stack.sh

    # Modify the node to reflect the boot_mode and secure_boot capabilities.
    # Also modify the nova flavor accordingly.
    source /opt/stack/devstack/openrc admin admin
    ironic_node=$(ironic node-list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)
    capabilities="boot_mode:$BOOT_MODE"
    if [[ "$BOOT_OPTION" = "local" ]]; then
        capabilities="$capabilities,boot_option:local"
        nova flavor-key baremetal set capabilities:boot_option="local"
    fi
    if [[ "$SECURE_BOOT" = "true" ]]; then
        capabilities="$capabilities,secure_boot:true"
        nova flavor-key baremetal set capabilities:secure_boot="true"
    fi
    ironic node-update $ironic_node add driver_info/ilo_deploy_iso=http://10.13.120.207:9999/fedora-raid-deploy-ank-proliant-tools.iso
    ironic node-update $ironic_node add instance_info/image_source=http://10.13.120.207:9999/fedora-wd-uefi.qcow2 instance_info/image_checksum=83b0671c9dfef5315c78de6da133c902
    ironic node-set-power-state $ironic_node off
    ironic node-update $ironic_node add properties/capabilities="$capabilities"

    # Update the root device hint if it was specified for some node.
    hardware_info=${IRONIC_ILO_HWINFO}
    root_device_hint=$(echo $hardware_info |awk '{print $5}')
    if [[ -n "$root_device_hint" ]]; then
        ironic node-update $ironic_node add properties/root_device="{\"size\": \"$root_device_hint\"}"
    fi



    # Enable tcpdump for pxe drivers
    if [[ "$ILO_DRIVER" = "pxe_ilo" ]]; then
        local interface
        interface=$(awk -F'=' '/PUBLIC_INTERFACE/{print $2}' /opt/stack/devstack/local.conf)
        if [[ -n "$interface" ]]; then
            sudo tcpdump -i eth1 >& $LOGDIR/tcpdump &
        fi
    fi

    # Run the tempest test.
    cd /opt/stack/ironic
    export OS_TEST_TIMEOUT=3000
    #tox -eall -- test_baremetal_server_ops
    tox -eall -- ironic_tempest_plugin.tests.scenario.ironic_standalone.test_basic_ops.BaremetalAgentIloWholediskHttpLink
    tox -eall -- ironic_tempest_plugin.tests.scenario.ironic_standalone.test_basic_ops.BaremetalAgentIloPartitioned

    git reset --hard HEAD~2
    # Stop console and tcpdump processes.
    stop_console
    stop_tcpdump
}

function update_ironic {
    cd /opt/stack/ironic
    git fetch https://git.openstack.org/openstack/ironic refs/changes/51/535651/1 && git cherry-pick FETCH_HEAD
}

function update_ironic_tempest_plugin {
    cd /opt/stack/ironic-tempest-plugin
    git fetch https://git.openstack.org/openstack/ironic-tempest-plugin refs/changes/52/535652/2 && git cherry-pick FETCH_HEAD
}
 
install_packages
clone_projects
update_ironic
update_ironic_tempest_plugin
run_stack
