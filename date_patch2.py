import re

with open('lib/screens/inspection/inspection_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace('final _entryDateCtrl = TextEditingController();', 
    'final _entryDateCtrl = TextEditingController(text: "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, \'0\')}-${DateTime.now().day.toString().padLeft(2, \'0\')}");')

text = text.replace('_entryDateCtrl.clear();', '_entryDateCtrl.text = "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, \'0\')}-${DateTime.now().day.toString().padLeft(2, \'0\')}";')

with open('lib/screens/inspection/inspection_screen.dart', 'w', encoding='utf-8') as f:
    f.write(text)

with open('lib/widgets/package_details_dialog.dart', 'r', encoding='utf-8') as f:
    text = f.read()

text = re.sub(r"_entryDateCtrl = TextEditingController\(text: widget.package.entryDate.*?:\s*''\);",
    r"_entryDateCtrl = TextEditingController(text: widget.package.entryDate != null ? '${widget.package.entryDate!.year}-${widget.package.entryDate!.month.toString().padLeft(2, \'0\')}-${widget.package.entryDate!.day.toString().padLeft(2, \'0\')}' : '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, \'0\')}-${DateTime.now().day.toString().padLeft(2, \'0\')}');",
    text, flags=re.DOTALL)

with open('lib/widgets/package_details_dialog.dart', 'w', encoding='utf-8') as f:
    f.write(text)
