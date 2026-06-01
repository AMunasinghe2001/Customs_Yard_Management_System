
path = r'd:\Company\Cus_Yard_Management\lib\services\services.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

print('Count of missing packages(*): ', text.count('select(\'*, packages(*)\')'))
print('Count of new packages(*, package_items(*)): ', text.count('select(\'*, packages(*, package_items(*))\')'))

