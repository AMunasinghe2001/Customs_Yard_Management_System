import re

def process_inspection_screen():
    with open('lib/screens/inspection/inspection_screen.dart', 'r', encoding='utf-8') as f:
        text = f.read()

    text = text.replace(
        "Expanded(child: TextFormField(controller: _declarantCtrl,",
        "Expanded(child: TextFormField(controller: _caseNumberCtrl,"
    )
    text = text.replace(
        "decoration: const InputDecoration(labelText: 'Declarant Name *'),",
        "decoration: const InputDecoration(labelText: 'Case Number'),"
    )
    
    # Consignee section rewrite
    old_consignee_match = re.search(r'(Row\(children: \[\s*Expanded\(child: TextFormField\(controller: _consigneeCtrl,.*?\]\)),\s*const Gap\(16\),\s*(TextFormField\(controller: _consigneePhoneCtrl,.*?\})', text, re.DOTALL)
    
    if old_consignee_match:
        # We rewrite it
        consignee_name_part = "Expanded(child: TextFormField(controller: _consigneeCtrl,\n                              decoration: const InputDecoration(labelText: 'Consignee Name *'),\n                              validator: (v) => v!.isEmpty ? 'Required' : null))"
        declarant_name_part = "Expanded(child: TextFormField(controller: _declarantCtrl,\n                              decoration: const InputDecoration(labelText: 'Declarant Name *'),\n                              validator: (v) => v!.isEmpty ? 'Required' : null))"
        nic_part = "Expanded(child: TextFormField(controller: _consigneeNicCtrl,\n                              decoration: const InputDecoration(labelText: 'Declarant Address')))"
        phone_part = "Expanded(child: TextFormField(controller: _consigneePhoneCtrl,\n                              decoration: const InputDecoration(labelText: 'Declarant Phone Number (10 digits)'),\n                              keyboardType: TextInputType.phone,\n                              validator: (v) {\n                                if (v != null && v.isNotEmpty && !RegExp(r'^\\\\d{10}$').hasMatch(v)) {\n                                  return 'Must be exactly 10 digits';\n                                }\n                                return null;\n                              }))"
        
        new_chunk = f"Row(children: [\n                          {consignee_name_part},\n                          const Gap(12),\n                          {declarant_name_part},\n                        ]),\n                        const Gap(16),\n                        Row(children: [\n                          {nic_part},\n                          const Gap(12),\n                          {phone_part},\n                        ])"
        
        text = text.replace(old_consignee_match.group(0), new_chunk)
    else:
        print("Could not find consignee block in inspection_screen.dart")

    # additional info rewrite
    add_info = re.search(r'(\s*_SectionCard\(\s*title:\s*\'Additional Info \(Optional\)\'.*?\]\)\.animate\(\)\.slideY.*?\.fadeIn\(\),)', text, re.DOTALL)
    if add_info:
        text = text.replace(add_info.group(1), '')
        
    with open('lib/screens/inspection/inspection_screen.dart', 'w', encoding='utf-8') as f:
        f.write(text)

process_inspection_screen()

# Now patch details dialog
def process_dialog():
    with open('lib/widgets/package_details_dialog.dart', 'r', encoding='utf-8') as f:
        text = f.read()
    
    # Add to details view (_DetailItem for caseNumber)
    text = text.replace(
        "label: 'Cusdec Number',",
        "label: 'Case Number',\n                                value: p.caseNumber ?? 'N/A',\n                              ),\n                              _DetailItem(\n                                icon: Icons.receipt_long_rounded,\n                                label: 'Cusdec Number',"
    )
    
    # Consignee in Details View
    text = text.replace("label: 'NIC / Passport',", "label: 'Declarant Address',")
    text = text.replace("label: 'Contact Number',", "label: 'Declarant Phone',")

    # Remove additional info from Details View
    add_info_detail = re.search(r'(_DetailSection\(\s*title:\s*\'Additional Info\'.*?children:\s*\[.*?\]\s*\),)', text, re.DOTALL)
    if add_info_detail:
        text = text.replace(add_info_detail.group(0), '')
        
    # Remove from Update form
    add_info_update = re.search(r'(\s*_UpdateSectionCard\(\s*title:\s*\'Additional Info \(Optional\)\'.*?\]\s*\),)', text, re.DOTALL)
    if add_info_update:
        text = text.replace(add_info_update.group(0), '')

    # Update form case number replacing declarant
    text = text.replace(
        "Expanded(\n                                    child: TextFormField(\n                                      controller: _declarantCtrl,\n                                      decoration: const InputDecoration(labelText: 'Declarant Name *'),\n                                      validator: (v) => v!.isEmpty ? 'Required' : null,\n                                    ),\n                                  ),",
        "Expanded(\n                                    child: TextFormField(\n                                      controller: _caseNumberCtrl,\n                                      decoration: const InputDecoration(labelText: 'Case Number'),\n                                    ),\n                                  ),"
    )

    # Consignee section rewrite in Update Form
    old_consignee_match_up = re.search(r'(Row\(children: \[\s*Expanded\(\s*child: TextFormField\(\s*controller: _consigneeCtrl,.*?\]\s*\)),\s*const Gap\(12\),\s*TextFormField\(\s*controller: _consigneeNicCtrl,.*?\),\s*const Gap\(12\),\s*TextFormField\(\s*controller: _consigneePhoneCtrl,.*?\}\s*\),', text, re.DOTALL)
    if old_consignee_match_up:
         # Replace with Row(s)
        consignee_name_part = "Expanded(child: TextFormField(controller: _consigneeCtrl,\n                                      decoration: const InputDecoration(labelText: 'Consignee Name *'),\n                                      validator: (v) => v!.isEmpty ? 'Required' : null))"
        declarant_name_part = "Expanded(child: TextFormField(controller: _declarantCtrl,\n                                      decoration: const InputDecoration(labelText: 'Declarant Name *'),\n                                      validator: (v) => v!.isEmpty ? 'Required' : null))"
        nic_part = "Expanded(child: TextFormField(controller: _consigneeNicCtrl,\n                                      decoration: const InputDecoration(labelText: 'Declarant Address')))"
        phone_part = "Expanded(child: TextFormField(controller: _consigneePhoneCtrl,\n                                      decoration: const InputDecoration(labelText: 'Declarant Phone Number (10 digits)'),\n                                      keyboardType: TextInputType.phone,\n                                      validator: (v) {\n                                        if (v != null && v.isNotEmpty && !RegExp(r'^\\\\d{10}$').hasMatch(v)) {\n                                          return 'Must be exactly 10 digits';\n                                        }\n                                        return null;\n                                      }))"
        
        new_chunk = f"Row(children: [\n                                  {consignee_name_part},\n                                  const Gap(12),\n                                  {declarant_name_part},\n                                ]),\n                                const Gap(12),\n                                Row(children: [\n                                  {nic_part},\n                                  const Gap(12),\n                                  {phone_part},\n                                ]),\n"
        text = text.replace(old_consignee_match_up.group(0), new_chunk)

    with open('lib/widgets/package_details_dialog.dart', 'w', encoding='utf-8') as f:
        f.write(text)

process_dialog()
print('Done everything')
