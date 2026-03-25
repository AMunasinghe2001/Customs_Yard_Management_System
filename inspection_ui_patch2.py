import re

with open('lib/screens/inspection/inspection_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_block = '''                          Wrap(
                            spacing: 8,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 160),
                              child: IntrinsicWidth(child: TextFormField(controller: _srNumberCtrl,
                                  decoration: const InputDecoration(labelText: 'SR Number *', hintText: 'e.g. GL 1/SR/01/2025'),
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                  onFieldSubmitted: (_) => _loadBySrNumber())),
                            ),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.colors.surfaceDark,
                                  foregroundColor: context.colors.accentLightBlue,
                                  side: BorderSide(color: context.colors.borderColor),
                                ),
                                icon: _isLookingUp
                                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.accentLightBlue))
                                    : const Icon(Icons.search_rounded, size: 18),
                                label: const Text('Load'),
                                onPressed: _isLookingUp ? null : _loadBySrNumber,
                              ),
                            ),
                            ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 160),
                              child: IntrinsicWidth(child: DropdownButtonFormField<String>(
                                value: ['pending', 'held', 'cleared', 'confiscated'].contains(_statusValue) ? _statusValue : 'pending',
                                decoration: const InputDecoration(labelText: 'Status *'),
                                items: ['pending', 'held', 'cleared', 'confiscated']
                                    .map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase()))).toList(),
                                onChanged: (v) => setState(() => _statusValue = v!),
                              )),
                            ),
                            ]),'''

new_block = '''                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _srNumberCtrl,
                                  decoration: const InputDecoration(labelText: 'SR Number *', hintText: 'e.g. GL 1/SR/01/2025'),
                                  validator: (v) => v!.isEmpty ? 'Required' : null,
                                  onFieldSubmitted: (_) => _loadBySrNumber()
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

if old_block in content:
    content = content.replace(old_block, new_block)
    with open('lib/screens/inspection/inspection_screen.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print('UI patch 2 complete')
else:
    print('Could not find old_block')
