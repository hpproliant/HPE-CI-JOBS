#!/bin/bash -x

source /home/ubuntu/proxy

#Updating ironic.conf "pxe_append_param"
sed -i "s/^pxe_append_params .*$/pxe_append_params = \"console=ttyS1 ipa-insecure=True\"/g" /etc/ironic/ironic.conf

#Restart ir-cond service
sudo systemctl restart devstack@ir-cond
sleep 30

# Configure dhcp server
wget http://169.16.1.54:9999/uefi_https_dhcp_server.txt -P /opt/stack/devstack/files/
mac=$(cat /tmp/hardware_info | awk '{print $2}')
#mac=70:10:6f:b4:cd:b6
sed -i "s/8c:dc:d4:af:78:ec/$mac/g" /opt/stack/devstack/files/uefi_https_dhcp_server.txt
sudo sh -c 'cat /opt/stack/devstack/files/uefi_https_dhcp_server.txt >> /etc/dhcp/dhcpd.conf'
sudo service isc-dhcp-server restart

#Create Node
#source /opt/stack/devstack/openrc admin admin
ilo_ip=$(cat /tmp/hardware_info | awk '{print $1}')
mac=$(cat /tmp/hardware_info | awk '{print $2}')
#ilo_ip=169.16.1.14
#mac=70:10:6f:b4:cd:b6

#Add Certificate to node
python3 /tmp/uefi-https/HPE-CI-JOBS/ilo5-uefi-https/files/ilo5_upload_cert.py $ilo_ip

#Updating tempest.conf
ip=$(ip addr show ens2 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
sed -i "s/^whole_disk_image_url .*$/whole_disk_image_url = https:\/\/${ip}:443\/rhel_7.6-uefi.img/g" /opt/stack/tempest/etc/tempest.conf
sed -i 's/^whole_disk_image_checksum .*$/whole_disk_image_checksum = fd9b31d6b754b078166387c86e7fd8ce/' /opt/stack/tempest/etc/tempest.conf

unset OS_REGION_NAME OS_PROJECT_DOMAIN_ID OS_AUTH_URL OS_TENANT_NAME OS_USER_DOMAIN_ID OS_USERNAME OS_VOLUME_API_VERSION OS_AUTH_TYPE OS_PROJECT_NAME OS_PASSWORD OS_IDENTITY_API_VERSION

export OS_AUTH_TYPE=none
export OS_ENDPOINT=http://$ip/baremetal

openstack baremetal node create --driver ilo5 --driver-info ilo_address=$ilo_ip --driver-info ilo_username=Administrator --driver-info ilo_password=weg0th@ce@r --driver-info console_port=5000 --driver-info ilo_verify_ca=False

ironic_node=$(openstack baremetal node list | grep -v UUID | grep "\w" | awk '{print $2}' | tail -n1)

openstack baremetal node manage $ironic_node
openstack baremetal node provide $ironic_node
openstack baremetal node set --driver-info ilo_deploy_kernel=https://$ip:443/ipa-centos8-master_18_05_21.kernel --driver-info ilo_deploy_ramdisk=https://$ip:443/ipa-centos8-master-password_18_05_21.initramfs --driver-info ilo_bootloader=https://$ip:443/ir-deploy-redfish.efiboot --instance-info image_source=https://$ip:443/rhel_7.6-uefi.img --instance-info image_checksum=fd9b31d6b754b078166387c86e7fd8ce --instance-info capabilities='{"boot_mode": "uefi"}' --property capabilities='boot_mode:uefi' $ironic_node

openstack baremetal port create --node $ironic_node $mac
openstack baremetal node power off $ironic_node

# Run the tempest test.
cd /opt/stack/tempest
export OS_TEST_TIMEOUT=3000
sudo tox -e all -- ironic_standalone.test_basic_ops.BaremetalIlo5UefiHTTPSWholediskHttpsLink.test_ip_access_to_server
