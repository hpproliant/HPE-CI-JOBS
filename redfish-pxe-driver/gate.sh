#!/bin/bash -x 

source /home/ubuntu/proxy

function run_redfish_ipxe_test {
    # Configure dhcp server
    wget http://169.16.1.54:9999/redfish_pxe_dhcp_server.txt -P /opt/stack/devstack/files/
    ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    mac=$(cat /tmp/hardware_info |cut -f2 -d ' ')
    sed -i "s/8.8.8.8/$ip/g" /opt/stack/devstack/files/redfish_pxe_dhcp_server.txt
    sed -i "s/8c:dc:d4:af:7d:ac/$mac/g" /opt/stack/devstack/files/redfish_pxe_dhcp_server.txt
    sudo cp /opt/stack/devstack/files/redfish_pxe_dhcp_server.txt /etc/dhcp/dhcpd.conf
    sudo service isc-dhcp-server restart

    #Create Node
    source /opt/stack/devstack/openrc admin admin
    ilo_ip=$(cat /tmp/hardware_info | awk '{print $1}')
    mac=$(cat /tmp/hardware_info | awk '{print $2}')

    openstack baremetal node create --driver redfish --driver-info redfish_address=$ilo_ip --driver-info redfish_username=Administrator --driver-info redfish_password=weg0th@ce@r --driver-info console_port=5000 --deploy-interface=direct --boot-interface=ipxe --driver-info redfish_verify_ca="False" --driver-info redfish_system_id=/redfish/v1/Systems/1

    #Update Boot Mode to UEFI
    change_boot_mode_uefi

    ironic_node=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)

    openstack baremetal node manage $ironic_node
    openstack baremetal node provide $ironic_node
    openstack baremetal node set --driver-info deploy_kernel=http://169.16.1.54:9999/ipa-centos8-master_18_05_21.kernel --driver-info deploy_ramdisk=http://169.16.1.54:9999/ipa-centos8-master_tls_disabled.initramfs --instance-info image_source=http://172.17.1.134:8010/rhel_7.6-uefi.img --instance-info image_checksum=fd9b31d6b754b078166387c86e7fd8ce --instance-info capabilities='{"boot_mode": "uefi"}' --instance-info capabilities='{"boot_option": "local"}' --property capabilities='boot_mode:uefi' $ironic_node

    openstack baremetal port create --node $ironic_node $mac
    openstack baremetal node power off $ironic_node

    # Run the tempest test.
    cd /opt/stack/tempest
    export OS_TEST_TIMEOUT=3000
    sudo tox -e all -- ironic_standalone.test_basic_ops.BaremetalRedfishIPxeWholediskHttpLink.test_ip_access_to_server
}

function change_boot_mode_uefi {
    ilo_ip=$(cat /tmp/hardware_info | awk '{print $1}')
    ilo_user=$(cat /tmp/hardware_info | awk '{print $3}')
    ilo_password=$(cat /tmp/hardware_info | awk '{print $4}')
    cat <<EOF >./change_boot_mode.py
import proliantutils.ilo.client as client
cl=client.IloClient("$ilo_ip", "$ilo_user", "$ilo_password")
cl.set_host_power('OFF')
cl.set_pending_boot_mode('uefi')
EOF

    python3 ./change_boot_mode.py
}

run_redfish_ipxe_test
