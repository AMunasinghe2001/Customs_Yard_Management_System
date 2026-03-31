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
        
        if entry.get('item_count') == 1 and true_quantity > 1 and entry.get('is_returned') == True:
            # FIX:
            # 1. DELETE the returned entry
            requests.delete(f"{URL}/rest/v1/warehouse_entries?id=eq.{entry['id']}", headers=headers)
            print(f"Deleted buggy return entry {entry['id']}")
            
            # 2. Add full amount back to held entry or if it doesn't exist, create it
            # Wait, let's just find if there's a held entry for this item_id
            held_entries = [e for e in entries if e.get('package_item_id') == item_id and e.get('is_returned') == False]
            if held_entries:
                held = held_entries[0]
                requests.patch(f"{URL}/rest/v1/warehouse_entries?id=eq.{held['id']}", headers=headers, json={"item_count": true_quantity})
                print(f"Updated held entry {held['id']} to {true_quantity}")
            else:
                entry['is_returned'] = False
                entry['item_count'] = true_quantity
                entry.pop('id', None)
                entry['returned_at'] = None
                entry['returned_by'] = None
                entry['return_notes'] = None
                requests.post(f"{URL}/rest/v1/warehouse_entries", headers=headers, json=entry)
                print(f"Created new held entry with {true_quantity}")
                
            # item pending
            requests.patch(f"{URL}/rest/v1/package_items?id=eq.{item_id}", headers=headers, json={"status": "pending"})

            # wait, if the original entry was returning 1, but supposed to be 13.
            # maybe the item_count itself was saved as 1 when inserting originally?
            # Let's fix those too!
        elif entry.get('item_count') == 1 and true_quantity > 1 and entry.get('is_returned') == False:
            requests.patch(f"{URL}/rest/v1/warehouse_entries?id=eq.{entry['id']}", headers=headers, json={"item_count": true_quantity})
            print(f"Fixed pending entry {entry['id']} to {true_quantity}")
            

if __name__ == '__main__':
    main()
