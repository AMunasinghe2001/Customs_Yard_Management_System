import requests
import json

URL = "https://tstlaauujhrrpjxhvorf.supabase.co"
KEY = "sb_publishable_6uuQQPPvKqKVfbP4WbEDRw_6sb6DQTa"

headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=representation"
}

def main():
    # 1. Fetch all package_items
    res = requests.get(f"{URL}/rest/v1/package_items", headers=headers)
    items = res.json()
    items_map = {i['id']: i for i in items}
    
    # 2. Fetch all warehouse_entries
    res = requests.get(f"{URL}/rest/v1/warehouse_entries", headers=headers)
    entries = res.json()
    
    # 3. Fix warehouse_entries
    for entry in entries:
        item_id = entry.get('package_item_id')
        if not item_id: continue
        
        item = items_map.get(item_id)
        if not item: continue
        
        true_quantity = item.get('quantity', 1)
        
        # If the warehouse entry is returning 1, but item has 13, and it's marked as returned
        if entry.get('item_count') == 1 and true_quantity > 1:
            print(f"Fixing entry {entry['id']} for item {item.get('itemName')}. Setting to {true_quantity} and held.")
            
            # Reset the warehouse entry
            update_res = requests.patch(
                f"{URL}/rest/v1/warehouse_entries?id=eq.{entry['id']}",
                headers=headers,
                json={
                    "item_count": true_quantity,
                    "is_returned": False,
                    "return_notes": None,
                    "returned_at": None,
                    "returned_by": None
                }
            )
            print("Entry reset:", update_res.status_code)
            
            # Reset the package item
            update_item = requests.patch(
                f"{URL}/rest/v1/package_items?id=eq.{item_id}",
                headers=headers,
                json={"status": "pending"}
            )
            print("Item reset:", update_item.status_code)

if __name__ == "__main__":
    main()
