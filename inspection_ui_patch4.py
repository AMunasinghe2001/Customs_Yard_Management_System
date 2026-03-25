import re

with open('lib/screens/inspection/inspection_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

match = re.search(r'\s*Wrap\(\s*spacing: 8,\s*runSpacing: 12,\s*crossAxisAlignment: WrapCrossAlignment\.center,\s*children: \[\s*ConstrainedBox\([\s\S]*?\}\)\),\s*\),\s*\]\),', content)
if match:
    new_block = '''                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _srNumberCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'SR Number *', 
                                    hintText: 'e.g. GL 1/SR/01/2025',
                                    suffixIcon: IconButton(
                                      icon: _isLookingUp 
                                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.primaryGold))
                                          : Icon(Icons.search_rounded, color: _srNumberCtrl.text.isNotEmpty ? context.colors.primaryGold : context.colors.textMuted), 
                                      onPressed: _isLookingUp ? null : _loadBySrNumber
                                    ),
                                  ),
                                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                  onFieldSubmitted: (_) => _loadBySrNumber(),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const Gap(12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: ['pending', 'held', 'cleared', 'confiscated'].contains(_statusValue) ? _statusValue : 'pending',
                                  decoration: const InputDecoration(labelText: 'Status *'),
                                  items: ['pending', 'held', 'cleared', 'confiscated']
                                      .map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase()))).toList(),
                                  onChanged: (v) => setState(() => _statusValue = v!),
                                ),
                              ),
                            ],
                          ),'''
    content = content.replace(match.group(0), new_block)
    with open('lib/screens/inspection/inspection_screen.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('UI patch 4 complete')
else:
    print('Could not find match')