#!/bin/bash -x

env

set -e
set -x
set -o pipefail
echo "Cloning Projects"

export no_proxy=169.16.1.54
wget http://169.16.1.54:9999/proxy -P /home/ubuntu/

source /home/ubuntu/proxy

sudo chmod 0600 /home/ubuntu/zuul_id_rsa
wget http://169.16.1.54:9999/log_upload_ssh -P /home/ubuntu/
wget http://169.16.1.54:9999/config -P /home/ubuntu/.ssh/
sudo chmod 0600 /home/ubuntu/zuul_id_rsa
sudo chmod 0664 /home/ubuntu/.ssh/config

function clone_projects {
    sudo mkdir -p /opt/stack
    sudo chown ubuntu.ubuntu /opt/stack
    sudo chmod 0777 /opt/stack
    cd /opt/stack
    git clone https://opendev.org/openstack-dev/devstack.git
    git clone https://opendev.org/openstack/ironic.git
    git clone https://opendev.org/openstack/ironic-tempest-plugin.git
    git clone https://opendev.org/x/proliantutils.git
    git clone https://opendev.org/openstack/neutron.git
}

clone_projects
