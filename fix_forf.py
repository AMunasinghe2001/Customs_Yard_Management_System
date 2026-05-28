
path = r'd:\Company\Cus_Yard_Management\lib\screens\forfeited_packages\forfeited_packages_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

import re
replacement = '''DataCell(Text(
                                  isExpired ? f'{(-daysRemaining)} overdue' : f'{daysRemaining}',
                                  style: TextStyle(
                                    color: isExpired ? context.colors.dangerRed : context.colors.successGreen,
                                    fontWeight: FontWeight.bold
                                  ),
                                )),'''

replacement = replacement.replace('f', r'$') # a trick to get dart interpolation into python string

text = re.sub(r'DataCell\(Text\(\s*isExpired \? \' overdue\' : \'\\\',\s*style: TextStyle\(\s*color: isExpired \? context\.colors\.dangerRed : context\.colors\.successGreen,\s*fontWeight: FontWeight\.bold\s*\),\s*\)\),', replacement, text)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

