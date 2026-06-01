
path = r'd:\Company\Cus_Yard_Management\lib\services\services.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace(
    '''select('*, packages(*)').order('forfeited_at', ascending: false);''',
    '''select('*, packages(*, package_items(*))').order('forfeited_at', ascending: false);'''
)
with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

