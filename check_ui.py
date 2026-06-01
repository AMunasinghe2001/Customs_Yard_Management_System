
path = r'd:\Company\Cus_Yard_Management\lib\screens\forfeited_packages\forfeited_packages_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

import re
print('Number of matches for rows map:', text.count('rows: filtered.map((pkg)'))
print('Number of matches for col size S:', text.count('DataColumn2(label: Center(child: Text(\'Status\')), size: ColumnSize.S)'))

