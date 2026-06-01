
path = r'd:\Company\Cus_Yard_Management\lib\screens\forfeited_packages\forfeited_packages_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

# Replace rows mapping more generally
import re

pattern = r'rows:\s+filtered\.map\(\(pkg\)\s*\{[^\}]+\}\)\.toList\(\),'
match = re.search(r'rows:\s+filtered\.map\(\(pkg\)\s*\{.*?\}\)\.toList\(\),', text, re.DOTALL)

if match:
    print('Found the mapping block')
else:
    print('Could not find the mapping block mapping')

rows_old = match.group(0)

rows_new = r'''rows: filtered.expand((pkg) {
                            final forfeitedItems = pkg.packageDetails?.items.where((i) => i.status.toLowerCase() == 'forfiet' || i.status.toLowerCase() == 'forfeited').toList() ?? [];
                            // If no items are explicitly marked, just show one row for the package
                            final itemsToShow = forfeitedItems.isEmpty ? [null] : forfeitedItems;
                            
                            return itemsToShow.map((item) {
                              final isExpired = pkg.isAppealExpired;
                              final daysRemaining = pkg.appealDeadline.difference(DateTime.now()).inDays;
                              
                              return DataRow(
                                color: WidgetStateProperty.resolveWith<Color?>((states) {
                                  if (isExpired) return context.colors.dangerRed.withOpacity(0.04);
                                  return null;
                                }),
                                cells: [
                                  DataCell(Text(pkg.srNumber, style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.bold))),
                                  DataCell(Text(item?.itemName ?? 'Multiple/Unspecified', style: const TextStyle(fontWeight: FontWeight.w500))),
                                  DataCell(Text(pkg.consigneeName)),
                                  DataCell(Text(DateFormat('yyyy-MM-dd').format(pkg.forfeitedAt))),
                                  DataCell(Text(
                                    DateFormat('yyyy-MM-dd').format(pkg.appealDeadline),
                                    style: TextStyle(
                                      color: isExpired ? context.colors.dangerRed : context.colors.textPrimary,
                                      fontWeight: isExpired ? FontWeight.bold : FontWeight.normal
                                    ),
                                  )),
                                  DataCell(Text(
                                    isExpired ? ' overdue' : '',
                                    style: TextStyle(
                                      color: isExpired ? context.colors.dangerRed : context.colors.successGreen,
                                      fontWeight: FontWeight.bold
                                    ),
                                  )),
                                  DataCell(Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isExpired ? context.colors.dangerRed.withOpacity(0.1) : context.colors.successGreen.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isExpired ? context.colors.dangerRed.withOpacity(0.3) : context.colors.successGreen.withOpacity(0.3)),
                                      ),
                                      child: Text(
                                        isExpired ? 'Appeal Expired' : 'Appealing',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isExpired ? context.colors.dangerRed : context.colors.successGreen,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  )),
                                ],
                              );
                            });
                          }).toList(),'''

text = text.replace(rows_old, rows_new)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

