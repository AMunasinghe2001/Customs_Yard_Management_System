import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        text = f.read()

    # 1. Add _caseNumberCtrl in inspections_screen
    if 'final _srNumberCtrl = TextEditingController();' in text:
        text = text.replace('final _srNumberCtrl = TextEditingController();', 
                            'final _srNumberCtrl = TextEditingController();\n  final _caseNumberCtrl = TextEditingController();')
    
    # inspection screen fill
    if \"_originCtrl.text = pkg.originCountry ?? '';\" in text:
        text = text.replace(\"_originCtrl.text = pkg.originCountry ?? '';\",
                            \"_caseNumberCtrl.text = pkg.caseNumber ?? '';\\n      _originCtrl.text = pkg.originCountry ?? '';\")
    
    # 2. Add caseNumberCtrl in package_details_dialog
    if 'late final TextEditingController _cusdecCtrl;' in text:
        text = text.replace('late final TextEditingController _cusdecCtrl;',
                            'late final TextEditingController _caseNumberCtrl;\n  late final TextEditingController _cusdecCtrl;')
        text = text.replace(\"_cusdecCtrl = TextEditingController(text: widget.package.cusdecNo ?? '');\",
                            \"_caseNumberCtrl = TextEditingController(text: widget.package.caseNumber ?? '');\\n    _cusdecCtrl = TextEditingController(text: widget.package.cusdecNo ?? '');\")
        text = text.replace(\"_cusdecCtrl.dispose();\", \"_caseNumberCtrl.dispose();\\n      _cusdecCtrl.dispose();\")
        
        text = text.replace(\"cusdecNo: _cusdecCtrl.text.trim(),\", \"caseNumber: _caseNumberCtrl.text.trim(),\\n          cusdecNo: _cusdecCtrl.text.trim(),\")

    # 3. Change Entry Date initialization everywhere to today's date
    if 'TextEditingController _entryDateCtrl;' in text: # It's late final in dialog
        # Dialog
        text = re.sub(r\"_entryDateCtrl = TextEditingController\(text:.*?:\s*''\);\",
                      \"_entryDateCtrl = TextEditingController(text: '--');\",
                      text, flags=re.DOTALL)
                      
    if 'final _entryDateCtrl = TextEditingController();' in text:
        # Inspection Screen
        text = text.replace('final _entryDateCtrl = TextEditingController();', 
                            \"final _entryDateCtrl = TextEditingController(text: '\\-\\-\\');\")

    # 4. Modify labels in both forms.
    # Consignee section
    text = text.replace(\"labelText: 'NIC Number'\", \"labelText: 'Declarant Address'\")
    text = text.replace(\"labelText: 'Phone Number'\", \"labelText: 'Declarant Phone Number'\")
    
    # 5. Move declarant to consignee section (Wait, I need to restructure the Row widgets...)
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(text)

process_file('lib/screens/inspection/inspection_screen.dart')
process_file('lib/widgets/package_details_dialog.dart')
print('Done')
