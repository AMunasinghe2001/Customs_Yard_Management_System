import requests
import json
import os

URL = 'https://tstlaauujhrrpjxhvorf.supabase.co'
KEY = 'sb_publishable_6uuQQPPvKqKVfbP4WbEDRw_6sb6DQTa'

headers = {
    'apikey': KEY,
    'Authorization': f'Bearer {KEY}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation'
}

with open(r'd:\Company\Cus_Yard_Management\supabase\migrations\20260611_taxes_and_delivery.sql', 'r') as f:
    sql = f.read()

payload = {'query': sql}

res = requests.post(f'{URL}/rest/v1/rpc/exec_sql', headers=headers, json=payload)
if res.status_code != 200:
    print("Error executing via rpc/exec_sql. Let's try raw REST query if possible or just use python library.")
    print(res.text)
else:
    print("Success")
