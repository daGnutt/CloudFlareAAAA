#!/usr/bin/env python3

import json
import requests

HOSTNAME="server.f-lg9.gnutt.se"
APIKEY="3uXCpBMuvOD2h0lrcYEQOrzMv5RfXgLESuDfUAlD"
CLOUDFLARE_ZONE_ID="3567bb2acf4f93be3663c5cf62483f70"

def create_dns_post(type, name, content):
  newdata = {"type": type, "name": name, "content": content}
  response = requests.post(
    url="https://api.cloudflare.com/client/v4/zones/{zone_identifier}/dns_records".format(
      zone_identifier=CLOUDFLARE_ZONE_ID
    ),
    headers={"Authorization":"Bearer {APIKEY}".format(APIKEY=APIKEY)},
    data=json.dumps(newdata)
  )
  return response

def fetch_all_dns():
  data=requests.get(
    url="https://api.cloudflare.com/client/v4/zones/{ZONE}/dns_records".format(ZONE=CLOUDFLARE_ZONE_ID),
    headers={"Authorization":"Bearer {APIKEY}".format(APIKEY=APIKEY)}
  )
  return data.json()['result']

def update_dns_post(id, type, name, content):
  newdata = {"type": type, "name": name, "content": content}
  result = requests.patch(
    url="https://api.cloudflare.com/client/v4/zones/{zone_identifier}/dns_records/{identifier}".format(
      zone_identifier=CLOUDFLARE_ZONE_ID,
      identifier=id
    ),
    headers={"Authorization":"Bearer {APIKEY}".format(APIKEY=APIKEY)},
    data=json.dumps(newdata)
  )
  return result.json()['result']

def delete_dns_post(id):
  result = requests.delete(
    url="https://api.cloudflare.com/client/v4/zones/{zone_identifier}/dns_records/{identifier}".format(
      zone_identifier=CLOUDFLARE_ZONE_ID,
      identifier=id
    ),
    headers={"Authorization":"Bearer {APIKEY}".format(APIKEY=APIKEY)}
  )
  return result.json()['result']

def __main():
  public_ipv6 = requests.get('https://v6.ipinfo.io/ip').text

  allposts = fetch_all_dns()
  stored_posts = [post for post in allposts if post['name'] == HOSTNAME and post['type'] == "AAAA"]
  if len(stored_posts) == 0:
    print("Cloudflare had no knowledge of this hostname. Adding with ip {}".format(public_ipv6))
    create_dns_post("AAAA", HOSTNAME, public_ipv6)

  if len(stored_posts) > 0:
    stored_post = stored_posts[0]
    if stored_post['content'] != public_ipv6:
      print("Cloudflare IP not same as public ip. Updating from {} to {}".format(stored_post['content'], public_ipv6))
      update_dns_post(stored_post['id'],"AAAA", HOSTNAME, public_ipv6)

  if len(stored_posts) > 1:
    print("Spare Cloudflare posts exists. Removing Extra")
    for stored_post in stored_posts[1:]: # Skip first post in list (should have been potentially update in previous step)
      print("Removing post with id {id} and ip-address {address}".format(
        id=stored_post['id'],
        address=stored_post['content']
      ))
      delete_dns_post(stored_post['id'])

  return 0

if __name__ == '__main__':
  __main()
