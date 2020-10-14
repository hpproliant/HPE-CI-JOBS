import sys
import time
import proliantutils.ilo.client as client

ilo_ip = sys.argv[1]

cl=client.IloClient(ilo_ip, "Administrator", "weg0th@ce@r")

#add certificate
cl.add_tls_certificate(['/home/ubuntu/ssl_files/uefi_signed.crt'])
time.sleep(10)

print("Certificate upload completed. Now resetting the server.")

#Server reboot
#cl.reset_server()
#time.sleep(600)



