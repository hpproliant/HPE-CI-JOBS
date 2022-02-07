#!/usr/bin/env python
import subprocess
import json
import time
import sys

print "Molteniron dynamic allocation of node"
flag = 1
owner_name = sys.argv[1]
nodepool = sys.argv[2]
hardware_info = open("/tmp/hardware_info", "w")
while flag == 1:
    try:
        status = subprocess.check_output(['bash', '-c', "molteniron -c /tmp/molteniron/molteniron -o result status|grep %s|awk -F '|' '{print $6}'" % nodepool])
        check = status.split()
        if 'ready' in check:
            out = subprocess.check_output(['bash', '-c', "molteniron -c /tmp/molteniron/molteniron allocate %s 1 %s" %(owner_name, nodepool)])
            d = json.loads(out)
            if int(d['status']) == 200:
                ip = subprocess.check_output(['bash', '-c', "molteniron -c /tmp/molteniron/molteniron get_field '%s' 'ipmi_ip'" % owner_name])
                ip_d = json.loads(ip)
                hardware_info.write(ip_d['result'][0]['field'])
                mac = subprocess.check_output(['bash', '-c', "molteniron -c /tmp/molteniron/molteniron get_field '%s' 'port_hwaddr'" % owner_name])
                mac_d = json.loads(mac)
                hardware_info.write(" ")
                hardware_info.write(mac_d['result'][0]['field'])
                user = subprocess.check_output(['bash', '-c', "molteniron -c /tmp/molteniron/molteniron get_field '%s' 'ipmi_user'" % owner_name])
                user_d = json.loads(user)
                hardware_info.write(" ")
                hardware_info.write(user_d['result'][0]['field'])
                pwd = subprocess.check_output(['bash', '-c', "molteniron -c /tmp/molteniron/molteniron get_field '%s' 'ipmi_password'" % owner_name])
                pwd_d = json.loads(pwd)
                hardware_info.write(" ")
                hardware_info.write(pwd_d['result'][0]['field'])
                hardware_info.close()
                flag = 0
                print "Node allocated Successfully"
        else:
            raise Exception('No nodes')
    except:
        print "All nodes are busy. Waiting for node."
        time.sleep(120)
print("Allocation done")
