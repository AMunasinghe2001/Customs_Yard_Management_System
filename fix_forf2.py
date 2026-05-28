
path = r'd:\Company\Cus_Yard_Management\lib\screens\forfeited_packages\forfeited_packages_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

import re
replacement = '''DataCell(Text(
                                  isExpired ? \\' overdue\\' : \\'\\',
                                  style: TextStyle(
                                    color: isExpired ? context.colors.dangerRed : context.colors.successGreen,
                                    fontWeight: FontWeight.bold
                                  ),
                                )),'''

# clean the replacement escaping
replacement = replacement.replace('\\'','')

text = re.sub(r'DataCell\(Text\(\n.*\n\s*style: TextStyle\(\n\s*color: isExpired \? context\.colors\.dangerRed : context\.colors\.successGreen,\n\s*fontWeight: FontWeight\.bold\n\s*\),\n\s*\)\),', '''DataCell(Text(
                                  isExpired ? '\\ overdue' : '\\',
                                  style: TextStyle(
                                    color: isExpired ? context.colors.dangerRed : context.colors.successGreen,
                                    fontWeight: FontWeight.bold
                                  ),
                                )),'''.replace('\\',''), text)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

