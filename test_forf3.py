
import requests

URL = 'https://tstlaauujhrrpjxhvorf.supabase.co/rest/v1/forfeited_packages'
KEY = 'sb_publishable_6uuQQPPvKqKVfbP4WbEDRw_6sb6DQTa'

headers = {
    'apikey': KEY,
    'Authorization': f'Bearer {KEY}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation'
}

data = {
    'package_id': '00000000-0000-0000-0000-000000000000',
    'sr_number': 'test',
    'consignee_name': 'test'
}

res = requests.post(URL, headers=headers, json=data)
print(res.text)

