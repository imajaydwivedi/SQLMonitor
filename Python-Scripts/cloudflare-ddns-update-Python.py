import socket
from cloudflare_ddns import CloudFlare
# https://pypi.org/project/cloudflare-ddns/
# GDrive -> Websites > sqlmonitor.ajaydwivedi.com > cloudflare-ddns-update-Python.py

api_key = "youapikeyherewhichshouldbeverylong"
sqlmonitor_subdomain = "sqlmonitor.ajaydwivedi.com"
email = "sqlagentservice@gmail.com"
noip_domain = 'ajaydwivedi.ddns.net'

new_ip_address = socket.gethostbyname(noip_domain)
print(f'new_ip_address => {new_ip_address}')

cf = CloudFlare(email, api_key, sqlmonitor_subdomain)
dns_a_record_info = cf.get_record('A', sqlmonitor_subdomain)
old_ip_address = dns_a_record_info['content']
print(f'old_ip_address => {old_ip_address}\n')

if old_ip_address == new_ip_address:
  print("Active ip address is correct.")
else:
  print(f"Update of ip address is required from {old_ip_address} to {new_ip_address}.")
  cf.update_record('A',sqlmonitor_subdomain,new_ip_address)

'''
python ~/GitHub/SqlServerLab/Private/cloudflare-ddns-update-Python.py 

sudo touch /etc/cron.d/cloudflare-ddns-update-Python.cron
Save following content in above cron file

#https://stackoverflow.com/a/21648491/4449743

# run script every 5 minutes
*/5 * * * *   saanvi  

# run script after system (re)boot
@reboot       saanvi  python ~/GitHub/SqlServerLab/Private/cloudflare-ddns-update-Python.py


'''