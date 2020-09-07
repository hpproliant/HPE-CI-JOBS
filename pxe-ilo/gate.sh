#!/bin/bash -x

source /home/ubuntu/proxy

# Configure dhcp server {
wget http://169.16.1.54:9999/pxe_dhcp_server.txt -P /opt/stack/devstack/files/
ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
mac=$(cat /tmp/hardware_info |cut -f2 -d ' ')
#mac=94:57:a5:55:9f:34
sed -i "s/8.8.8.8/$ip/g" /opt/stack/devstack/files/pxe_dhcp_server.txt
sed -i "s/8c:dc:d4:af:7d:ac/$mac/g" /opt/stack/devstack/files/pxe_dhcp_server.txt
sudo cp /opt/stack/devstack/files/pxe_dhcp_server.txt /etc/dhcp/dhcpd.conf
sudo service isc-dhcp-server restart

#Create Node
source /opt/stack/devstack/openrc admin admin
ilo_ip=$(cat /tmp/hardware_info | awk '{print $1}')
mac=$(cat /tmp/hardware_info | awk '{print $2}')
#ilo_ip=169.16.1.16
#mac=94:57:a5:55:9f:34

unset OS_REGION_NAME OS_PROJECT_DOMAIN_ID OS_AUTH_URL OS_TENANT_NAME OS_USER_DOMAIN_ID OS_USERNAME OS_VOLUME_API_VERSION OS_AUTH_TYPE OS_PROJECT_NAME OS_PASSWORD OS_IDENTITY_API_VERSION

ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
export OS_AUTH_TYPE=none
export OS_ENDPOINT=http://$ip/baremetal

openstack baremetal node create --driver ilo --driver-info ilo_address=$ilo_ip --driver-info ilo_username=Administrator --driver-info ilo_password=weg0th@ce@r --driver-info console_port=5000 --driver-info ilo_verify_ca=False

ironic_node=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)

openstack baremetal node manage $ironic_node
openstack baremetal node provide $ironic_node
openstack baremetal node set --driver-info deploy_kernel=http://169.16.1.54:9999/fedora_04_06_20.kernel --driver-info deploy_ramdisk=http://169.16.1.54:9999/fedora_04_06_20.initramfs --instance-info image_source=http://169.16.1.54:9999/ubuntu-uefi.img --instance-info image_checksum=a46f6297446f1197510839ef70d667c5 --instance-info capabilities='{"boot_mode": "uefi"}' --instance-info capabilities='{"boot_option": "local"}' --property capabilities='boot_mode:uefi' $ironic_node

openstack baremetal port create --node $ironic_node $mac
openstack baremetal node power off $ironic_node

# Run the tempest test.
cd /opt/stack/tempest
export OS_TEST_TIMEOUT=3000
sudo tox -e all -- ironic_standalone.test_basic_ops.BaremetalIloIPxeWholediskHttpLink.test_ip_access_to_server
