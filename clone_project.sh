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
    sudo chown -R ubuntu.ubuntu /opt
    sudo chmod -R 0777 /opt
    cd /opt/stack
    git clone https://opendev.org/openstack-dev/devstack.git
    git clone https://opendev.org/openstack/ironic.git
    git clone https://opendev.org/openstack/ironic-tempest-plugin.git
    git clone https://opendev.org/x/proliantutils.git
    while true; do
        git clone https://opendev.org/openstack/neutron.git
	RESULT=$?
        if [ $RESULT == 0 ]; then
            echo "Cloning neutron completed. Exiting.."
            break
        else
            echo "Failed cloning neutron. Trying again.."
            rm -rf neutron
        fi
    done
    echo "Cloning of all projects completed.."
}

clone_projects
