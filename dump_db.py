import requests
import json

URL = 'https://tstlaauujhrrpjxhvorf.supabase.co'
KEY = 'sb_publishable_6uuQQPPvKqKVfbP4WbEDRw_6sb6DQTa'

headers = {
    'apikey': KEY,
    'Authorization': f'Bearer {KEY}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation'
}

def main():
    res = requests.get(f'{URL}/rest/v1/package_items?select=*', headers=headers)
    items = res.json()
    items_map = {i['id']: i for i in items}
    
    res = requests.get(f'{URL}/rest/v1/warehouse_entries?select=*', headers=headers)
    entries = res.json()
    
    for entry in entries:
        item_id = entry.get('package_item_id')
        if not item_id: continue
        item = items_map.get(item_id)
        if not item: continue
        
        true_quantity = item.get('quantity', 1)
        
        print(f"Entry item: {item.get('item_name')} - item_count: {entry.get('item_count')}, true_quantity: {true_quantity}, is_returned: {entry.get('is_returned')}")

if __name__ == '__main__':
    main()
