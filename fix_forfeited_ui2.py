
path = r'd:\Company\Cus_Yard_Management\lib\screens\forfeited_packages\forfeited_packages_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    text = f.read()

import re

# Replace DataColumn2 list
cols_old = '''                            DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(label: Text('Consignee'), size: ColumnSize.L),
                            DataColumn2(label: Text('Forfeited Date'), size: ColumnSize.M),
                            DataColumn2(label: Text('Appeal Deadline'), size: ColumnSize.M),
                            DataColumn2(label: Text('Days Remaining'), size: ColumnSize.M),
                            DataColumn2(label: Center(child: Text('Status')), size: ColumnSize.S),'''

cols_new = '''                            DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(label: Text('Item Name'), size: ColumnSize.L),
                            DataColumn2(label: Text('Consignee'), size: ColumnSize.L),
                            DataColumn2(label: Text('Forfeited Date'), size: ColumnSize.M),
                            DataColumn2(label: Text('Appeal Deadline'), size: ColumnSize.M),
                            DataColumn2(label: Text('Days Remaining'), size: ColumnSize.S),
                            DataColumn2(label: Center(child: Text('Status')), size: ColumnSize.S),'''

text = text.replace(cols_old, cols_new)

# Replace rows mapping
rows_old = '''                          rows: filtered.map((pkg) {
                            final isExpired = pkg.isAppealExpired;
                            final daysRemaining = pkg.appealDeadline.difference(DateTime.now()).inDays;
                            
                            return DataRow(
                              color: WidgetStateProperty.resolveWith<Color?>((states) {
                                if (isExpired) return context.colors.dangerRed.withOpacity(0.04);
                                return null;
                              }),
                              cells: [
                                DataCell(Text(pkg.srNumber, style: TextStyle(color: context.colors.accentLightBlue, fontWeight: FontWeight.bold))),
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
                                  isExpired ? '\ overdue' : '\',
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
                          }).toList(),'''

rows_new = r'''                          rows: filtered.expand((pkg) {
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

text = text.replace(cols_old, cols_new)
text = text.replace(rows_old, rows_new)

with open(path, 'w', encoding='utf-8') as f:
    f.write(text)

