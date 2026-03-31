import requests

URL = 'https://tstlaauujhrrpjxhvorf.supabase.co'
KEY = 'sb_publishable_6uuQQPPvKqKVfbP4WbEDRw_6sb6DQTa'

headers = {
    'apikey': KEY,
    'Authorization': f'Bearer {KEY}',
    'Content-Type': 'application/json'
}

print(requests.get(f'{URL}/rest/v1/warehouse_entries?select=*', headers=headers).text)
