
import os
path = r'd:\Company\Cus_Yard_Management\lib\screens\warehouses\warehouses_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace('_WarehousesHeaderWithStats(ws),\n                ),', '_WarehousesHeaderWithStats(ws),')
text = text.replace(r'\', r'')
text = text.replace(r'\', r'')
text = text.replace(r'\', r'')

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

