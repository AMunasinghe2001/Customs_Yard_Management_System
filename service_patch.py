with open('lib/services/services.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_block = '''        case 'prohibited_category':
          final prohibited = rule.stringValue?.toLowerCase() ?? '';
          for (final item in items) {
            if ((item.category?.toLowerCase() ?? '').contains(prohibited) || item.isProhibited) {
              violations.add('${rule.ruleName}: Item "${item.itemName}" falls under prohibited category');
              break;
            }
          }
          break;'''

new_block = '''        case 'prohibited_category':
          final prohibited = rule.stringValue?.toLowerCase() ?? '';
          if (prohibited.isNotEmpty) {
            for (final item in items) {
              if ((item.category?.toLowerCase() ?? '').contains(prohibited)) {
                if (!violations.any((v) => v.contains(item.itemName) && v.contains(rule.ruleName))) {
                  violations.add('${rule.ruleName}: Item "${item.itemName}" falls under prohibited category');
                }
              }
            }
          }
          break;'''

content = content.replace(old_block, new_block)

insert_point = '    return violations;'
explicit_check = '''    for (final item in items) {
      if (item.isProhibited) {
        if (!violations.any((v) => v.toLowerCase().contains('marked as prohibited') && v.contains(item.itemName))) {
          violations.add('Explicitly marked as prohibited: Item "${item.itemName}"');
        }
      }
    }

    return violations;'''

if old_block in content:
    content = content.replace(insert_point, explicit_check)
    with open('lib/services/services.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Service patch complete')
else:
    print('Could not find old_block in services.dart')
