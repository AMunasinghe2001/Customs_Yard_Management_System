import re

with open('lib/screens/inspection/inspection_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Add _caseNumberCtrl
text = text.replace('final _srNumberCtrl = TextEditingController();', 'final _srNumberCtrl = TextEditingController();\n  final _caseNumberCtrl = TextEditingController();')

# _entryDateCtrl default initialization
text = text.replace('final _entryDateCtrl = TextEditingController();', 
'''final _entryDateCtrl = TextEditingController(
    text: \"\-\-\\"
  );''')

# Add to fetching existing logic
text = text.replace(\"_originCtrl.text = pkg.originCountry ?? '';\", 
\"_caseNumberCtrl.text = pkg.caseNumber ?? '';\\n      _originCtrl.text = pkg.originCountry ?? '';\")

# Additional Info removal in UI
additional_info_block = re.search(r'_SectionCard\(\s*title:\s*\'Additional Info \(Optional\)\'.*?\.animate\(\)\.slideY.*?\.fadeIn\(\),', text, re.DOTALL)
if additional_info_block:
    text = text.replace(additional_info_block.group(0), '')

# Moving Declarant Name, changing nic and phone
text = re.sub(r\"(Expanded\(child: TextFormField\(controller: _declarantCtrl,.*?decoration: const InputDecoration\(labelText: 'Declarant Name \*\*'\)(?:.*?))\", '', text, flags=re.DOTALL)
# Wait, let's just do more targeted replacements based on exact code... this regex might be dangerous.
with open('lib/screens/inspection/inspection_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)
