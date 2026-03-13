import os
import re

def process_dart_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Skip files that don't have AppTheme.
    if 'AppTheme.' not in content:
        return

    # Replace AppTheme.foo with context.colors.foo
    # Exceptions: AppTheme.darkTheme, AppTheme.lightTheme, AppTheme.scaffoldBg which might be used outside widget tree if any.
    # Actually context.colors.scaffoldBg is valid.

    # Find all colors being referenced
    colors = [
        'customsBlue', 'customsBlueDark', 'customsBlueLight', 'primaryNavy', 
        'primaryGold', 'accentBlue', 'accentLightBlue', 'successGreen', 
        'warningAmber', 'dangerRed', 'heldOrange', 'surfaceDark', 'cardDark', 
        'borderColor', 'textPrimary', 'textSecondary', 'textMuted', 'scaffoldBg'
    ]

    for color_name in colors:
        content = re.sub(rf'AppTheme\.{color_name}', rf'context.colors.{color_name}', content)

    # Some consts will be broken. Naive regex to remove const before common widgets that take color args.
    # For example: const Text(..., style: TextStyle(color: context.colors...))
    # It's better to remove all `const ` that appear before widgets using context.colors.
    # We will just remove const keywords preceding any Widget constructor on exactly the same line if context.colors is on that line.
    
    # Or, a quick hack: since context.colors breaks const anywhere in the subtree, 
    # let's write a simple multi-pass const remover.
    # Actually, let's just do a naive pass:
    new_lines = []
    for line in content.split('\n'):
        if 'context.colors' in line:
            line = re.sub(r'\bconst\s+(Text|Icon|BoxDecoration|BorderSide|TextStyle|InputBorder|OutlineInputBorder|Padding|Gap|SizedBox|Row|Column|Container|Center|Align)', r'\1', line)
            # Remove isolated consts
            line = re.sub(r'const\s+\[', r'[', line)
        new_lines.append(line)
    
    content = '\n'.join(new_lines)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Updated {filepath}")

def main():
    lib_dir = os.path.join(os.path.dirname(__file__), 'lib')
    for root, dirs, files in os.walk(lib_dir):
        for file in files:
            if file.endswith('.dart') and file != 'theme.dart' and file != 'main.dart':
                filepath = os.path.join(root, file)
                process_dart_file(filepath)

if __name__ == '__main__':
    main()
