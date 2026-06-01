
import re
path = r'd:\Company\Cus_Yard_Management\lib\services\services.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(
    r'\.select\(\'\*,\s*packages\(\*\)\'\)',
    r'''.select('*, packages(*, package_items(*))')''',
    text
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

