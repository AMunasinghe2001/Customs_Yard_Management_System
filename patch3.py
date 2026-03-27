import re

def modify_inspection_screen():
    with open('lib/screens/inspection/inspection_screen.dart', 'r', encoding='utf-8') as f:
        text = f.read()

    # 1. Replace declarant location with Case Number
    text = text.replace(
        \"Expanded(child: TextFormField(controller: _declarantCtrl,\",
        \"Expanded(child: TextFormField(controller: _caseNumberCtrl,\"
    )
    text = text.replace(
        \"decoration: const InputDecoration(labelText: 'Declarant Name *'),\",
        \"decoration: const InputDecoration(labelText: 'Case Number'),\"
    )
    
    # 2. Modify Consignee Information
    old_consignee_info = '''                        Row(children: [
                          Expanded(child: TextFormField(controller: _consigneeCtrl,
                              decoration: const InputDecoration(labelText: 'Consignee Name *'),
                              validator: (v) => v!.isEmpty ? 'Required' : null)),
                          const Gap(12),
                          Expanded(child: TextFormField(controller: _consigneeNicCtrl,
                              decoration: const InputDecoration(labelText: 'NIC Number'))),
                        ]),
                        const Gap(16),
                        TextFormField(controller: _consigneePhoneCtrl,
                            decoration: const InputDecoration(labelText: 'Phone Number (10 digits)'),
                            keyboardType: TextInputType.phone,
                            validator: (v) {
                              if (v != null && v.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(v)) {
                                return 'Must be exactly 10 digits';
                              }
                              return null;
                            })'''
                            
    new_consignee_info = '''                        Row(children: [
                          Expanded(child: TextFormField(controller: _consigneeCtrl,
                              decoration: const InputDecoration(labelText: 'Consignee Name *'),
                              validator: (v) => v!.isEmpty ? 'Required' : null)),
                          const Gap(12),
                          Expanded(child: TextFormField(controller: _declarantCtrl,
                              decoration: const InputDecoration(labelText: 'Declarant Name *'),
                              validator: (v) => v!.isEmpty ? 'Required' : null)),
                        ]),
                        const Gap(16),
                        Row(children: [
                          Expanded(child: TextFormField(controller: _consigneeNicCtrl,
                              decoration: const InputDecoration(labelText: 'Declarant Address'))),
                          const Gap(12),
                          Expanded(child: TextFormField(controller: _consigneePhoneCtrl,
                              decoration: const InputDecoration(labelText: 'Declarant Phone Number (10 digits)'),
                              keyboardType: TextInputType.phone,
                              validator: (v) {
                                if (v != null && v.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(v)) {
                                  return 'Must be exactly 10 digits';
                                }
                                return null;
                              }))
                        ])'''
    text = text.replace(old_consignee_info, new_consignee_info)
    
    # 3. Remove Additional Info block
    add_info_block = re.search(r'(\s*_SectionCard\(\s*title:\s*\'Additional Info \(Optional\)\'.*?\]\)\.animate\(\)\.slideY.*?\.fadeIn\(\),)', text, re.DOTALL)
    if add_info_block:
        text = text.replace(add_info_block.group(1), '')

    with open('lib/screens/inspection/inspection_screen.dart', 'w', encoding='utf-8') as f:
        f.write(text)

modify_inspection_screen()
print(\"Done screening\")
