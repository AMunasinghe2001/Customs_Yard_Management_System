
import requests

URL = 'https://tstlaauujhrrpjxhvorf.supabase.co/rest/v1/forfeited_packages?limit=1'
KEY = 'sb_publishable_6uuQQPPvKqKVfbP4WbEDRw_6sb6DQTa'

headers = {
    'apikey': KEY,
    'Authorization': f'Bearer {KEY}'
}

res = requests.get(URL, headers=headers)
print(res.json())

