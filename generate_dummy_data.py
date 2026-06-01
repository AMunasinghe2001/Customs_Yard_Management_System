import requests
import json
import uuid
import random
from datetime import datetime, timedelta

URL = "https://tstlaauujhrrpjxhvorf.supabase.co"
KEY = "sb_publishable_6uuQQPPvKqKVfbP4WbEDRw_6sb6DQTa"

headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json",
    "Prefer": "return=representation"
}

def main():
    # 1. Fetch some packages
    print("Fetching packages...")
    res = requests.get(f"{URL}/rest/v1/packages?select=id,sr_number,consignee_name&limit=30", headers=headers)
    if res.status_code != 200:
        print(f"Error fetching packages: {res.text}")
        return
    packages = res.json()
    if not packages:
        print("No packages found to forfeit.")
        return

    # 2. Create Forfeited Packages
    print(f"Creating forfeited packages using {len(packages)} packages...")
    fori_data = []
    for i, pkg in enumerate(packages):
        # mix of expired and non-expired
        is_expired = i < (len(packages) * 0.7) # 70% expired
        if is_expired:
            forfeited_at = datetime.now() - timedelta(days=random.randint(40, 60))
            appeal_deadline = forfeited_at + timedelta(days=30)
        else:
            forfeited_at = datetime.now() - timedelta(days=random.randint(5, 15))
            appeal_deadline = forfeited_at + timedelta(days=30)
            
        fori_data.append({
            "package_id": pkg['id'],
            "sr_number": pkg['sr_number'],
            "consignee_name": pkg['consignee_name'] or "Unknown",
            "forfeited_at": forfeited_at.isoformat(),
            "appeal_deadline": appeal_deadline.isoformat(),
            "reason": "Test dummy data forfeit"
        })
    
    res = requests.post(f"{URL}/rest/v1/forfeited_packages", headers=headers, json=fori_data)
    if res.status_code not in [200, 201]:
        print(f"Error creating forfeited packages: {res.text}")
        return
    forfeited_pkgs = res.json()
    print(f"Created {len(forfeited_pkgs)} forfeited packages.")

    # 3. Create a Tender for inspired packages
    expired_ids = [p['id'] for p in forfeited_pkgs if datetime.fromisoformat(p['appeal_deadline'].replace('Z', '+00:00')) < datetime.now().astimezone()]
    
    if len(expired_ids) >= 5:
        print("Creating dummy tender...")
        tender_ids_for_this = expired_ids[:5]
        tender_data = {
            "tender_number": f"TND-{random.randint(1000, 9999)}",
            "tender_date": datetime.now().isoformat(),
            "forfeited_package_ids": tender_ids_for_this,
        }
        res = requests.post(f"{URL}/rest/v1/tenders", headers=headers, json=tender_data)
        if res.status_code not in [200, 201]:
            print(f"Error creating tender: {res.text}")
        else:
            tender = res.json()[0]
            print(f"Created tender: {tender['tender_number']}")
            
            # 4. Record Disposal for some in this tender
            disposal_data = []
            for i in range(3): # Disposed 3 out of 5
                disposal_data.append({
                    "tender_package_id": tender['id'],
                    "forfeited_package_id": tender_ids_for_this[i],
                    "disposal_type": random.choice(['sold', 're_export', 'govt_use', 'destroy']),
                    "receipt_number": f"REC-{random.randint(10000, 99999)}" if i==0 else None,
                    "disposed_at": datetime.now().isoformat()
                })
            
            res = requests.post(f"{URL}/rest/v1/tender_disposals", headers=headers, json=disposal_data)
            print(f"Created {res.status_code} disposals.")

if __name__ == "__main__":
    main()
