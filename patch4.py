
import re

def modify_inspection_screen():
    with open("lib/screens/inspection/inspection_screen.dart", "r", encoding="utf-8") as f:
        text = f.read()

    # 1. Replace declarant location with Case Number
    text = text.replace(
        "Expanded(child: TextFormField(controller: _declarantCtrl,",
        "Expanded(child: TextFormField(controller: _caseNumberCtrl,"
    )
    text = text.replace(
        "decoration: const InputDecoration(labelText: 'Declarant Name *'),",
        "decoration: const InputDecoration(labelText: 'Case Number'),"
    )
    
    # 3. Remove Additional Info block
    add_info_block = re.search(r"(\s*_SectionCard\(\s*title:\s*'Additional Info \(Optional\)'.*?\]\)\.animate\(\)\.slideY.*?\.fadeIn\(\),)", text, re.DOTALL)
    if add_info_block:
        text = text.replace(add_info_block.group(1), "")

    with open("lib/screens/inspection/inspection_screen.dart", "w", encoding="utf-8") as f:
        f.write(text)

modify_inspection_screen()
print("Done screening")

