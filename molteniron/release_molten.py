#!/usr/bin/env python
import subprocess
import json
import sys

print "Molteniron release node"
owner_name = sys.argv[1]
out = subprocess.check_output(['bash', '-c', "molteniron -c /tmp/molteniron/molteniron release '%s'" % owner_name])
out_d = json.loads(out)
if int(out_d['status']) == 200:
    subprocess.call(['rm', '-f', '/tmp/hardware_info'])
    print "Node released Successfully"
