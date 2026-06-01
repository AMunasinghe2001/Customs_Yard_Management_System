
path = r'd:\Company\Cus_Yard_Management\lib\services\services.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

import re

# In createPackage tracking loop:
# Before: we checked if ANY item had forfeit status. That creates 1 forfeited record for the SR
# What we need: For EACH item that is forfeited, create a record? 
# Wait, the UI shows SR Number. If they added 2 items under the SAME SR, how does it show?
# Ah, if we create a row in forfeited_packages per PACKAGE (SR), they will group together, unless we make it per item.
print('Checked python')

