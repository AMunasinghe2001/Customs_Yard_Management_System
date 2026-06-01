
with open(r'd:\Company\Cus_Yard_Management\lib\services\services.dart', 'r') as f:
    text = f.read()

import re
res = re.search(r'class PackageService \{.*?(Future<PackageModel> createPackage.*?)Future<void> sendToWarehouse', text, re.DOTALL)
if res:
    print(res.group(1))

