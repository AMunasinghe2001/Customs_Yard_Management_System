import os, re

files = [
    'lib/screens/admin/admin_screen.dart', 
    'lib/screens/appeal/appeal_dashboard_screen.dart', 
    'lib/screens/dashboard/dashboard_screen.dart', 
    'lib/screens/disposal/disposal_dashboard_screen.dart', 
    'lib/screens/disposal/taxes_tab.dart', 
    'lib/screens/forfeited_packages/forfeited_packages_screen.dart', 
    'lib/screens/forfeited_packages/tender_disposal_screen.dart', 
    'lib/screens/packages/abandoned_packages_screen.dart', 
    'lib/screens/packages/disposition_category_screen.dart', 
    'lib/screens/packages/other_packages_screen.dart', 
    'lib/screens/packages/packages_screen.dart', 
    'lib/screens/packages/returned_packages_screen.dart', 
    'lib/screens/valuation/valuation_dashboard_screen.dart', 
    'lib/screens/warehouses/warehouses_screen.dart', 
    'lib/screens/warehouses/warehouse_capacity_screen.dart'
]

targets = ['Status', 'Delivery', 'Decision', 'Source', 'Payment', 'State', 'Stage']

for f in files:
    if not os.path.exists(f): continue
    content = open(f, encoding='utf-8').read()
    
    # Fix double commas from previous run
    for t in targets:
        content = content.replace(f"DataColumn2(label: Center(child: Text('{t}')),,", f"DataColumn2(label: Center(child: Text('{t}')),")
        
    # Center un-centered DataColumn2
    for t in targets:
        content = re.sub(rf"DataColumn2\(\s*label:\s*Text\('{t}'\)\s*,", f"DataColumn2(label: Center(child: Text('{t}')),", content)

    # For cells containing Container for status chip, let's carefully replace them.
    # The pattern is usually: DataCell(\s*Container\(\s*padding: const EdgeInsets.symmetric\(horizontal: 8, vertical: 4\).*?\)\s*\)
    # But because of nested parens, a regex is fragile. 
    # Let's find index of 'padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)'
    # Then go backwards to find 'DataCell(' and 'Container('. 
    
    idx = 0
    while True:
        idx = content.find("padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)", idx)
        if idx == -1: break
        
        # Go backwards to find Container
        container_idx = content.rfind("Container(", 0, idx)
        # Go backwards to find DataCell
        datacell_idx = content.rfind("DataCell(", 0, container_idx)
        
        # Check if it's right before Container
        if datacell_idx != -1 and content[datacell_idx:container_idx].strip() == "DataCell(":
            # Wrap Container in Center(child: ...)
            # We need to find the end of DataCell. We can just add 'Center(child: ' before Container, 
            # and then we need an extra ')' at the end.
            # To find the end, count parentheses from DataCell(
            count = 0
            end_idx = -1
            for i in range(datacell_idx, len(content)):
                if content[i] == '(': count += 1
                elif content[i] == ')': count -= 1
                if count == 0:
                    end_idx = i
                    break
            
            if end_idx != -1:
                # Add 'Center(child: ' at container_idx
                # Add ')' before the final ')' of DataCell
                content = content[:container_idx] + "Center(child: " + content[container_idx:end_idx] + ")" + content[end_idx:]
                idx = end_idx + 20 # Skip past this to avoid infinite loops
        else:
            idx += 1

    with open(f, 'w', encoding='utf-8') as out:
        out.write(content)
print('Done')
