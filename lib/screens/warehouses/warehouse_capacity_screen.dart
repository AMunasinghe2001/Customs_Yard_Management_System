import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';

/// Admin view of how full each warehouse in their own yard is — total capacity,
/// the quantity currently held, the fill percentage, and which zones are in use.
class WarehouseCapacityScreen extends ConsumerWidget {
  const WarehouseCapacityScreen({super.key});

  Color _fillColor(BuildContext context, double percent) {
    if (percent >= 90) return context.colors.dangerRed;
    if (percent >= 70) return context.colors.heldOrange;
    return context.colors.successGreen;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capacityAsync = ref.watch(yardWarehouseCapacityProvider);

    return AppShell(
      currentRoute: '/zone-capacity',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Warehouse Zone Capacity',
                      style: Theme.of(context).textTheme.headlineLarge),
                  const Gap(4),
                  Text(
                    'Capacity utilisation of the warehouses in your yard',
                    style: TextStyle(
                        color: context.colors.textSecondary, fontSize: 14),
                  ),
                ],
              ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
              const Gap(24),

              // ── Summary chips ──
              capacityAsync.maybeWhen(
                data: (rows) {
                  final totalCap = rows.fold<int>(
                      0, (s, r) => s + (r['capacity'] as int));
                  final totalUsed =
                      rows.fold<int>(0, (s, r) => s + (r['used'] as int));
                  final overall =
                      totalCap > 0 ? (totalUsed / totalCap) * 100 : 0.0;
                  return Row(
                    children: [
                      _StatChip(
                          label: 'Warehouses',
                          value: '${rows.length}',
                          color: context.colors.accentLightBlue),
                      const Gap(8),
                      _StatChip(
                          label: 'Total Used',
                          value: '$totalUsed',
                          color: context.colors.primaryGold),
                      const Gap(8),
                      _StatChip(
                          label: 'Total Capacity',
                          value: '$totalCap',
                          color: context.colors.textSecondary),
                      const Gap(8),
                      _StatChip(
                          label: 'Overall Fill',
                          value: '${overall.toStringAsFixed(1)}%',
                          color: _fillColor(context, overall)),
                    ],
                  ).animate().fadeIn(delay: 100.ms);
                },
                orElse: () => const SizedBox(),
              ),
              const Gap(20),

              // ── Table ──
              Expanded(
                child: capacityAsync.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (error, _) => ErrorView(
                    error: error.toString(),
                    onRetry: () =>
                        ref.refresh(yardWarehouseCapacityProvider),
                  ),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return const EmptyTableState(
                              message: 'No active warehouse stock in your yard')
                          .animate()
                          .fadeIn();
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: context.colors.cardDark,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.colors.borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DataTable2(
                          columnSpacing: 12,
                          horizontalMargin: 16,
                          fixedTopRows: 1,
                          headingRowColor: WidgetStateProperty.all(
                              context.colors.surfaceDark),
                          columns: const [
                            DataColumn2(label: Text('Warehouse'), size: ColumnSize.L),
                            DataColumn2(label: Text('Zones'), size: ColumnSize.L),
                            DataColumn2(
                                label: Text('Used'),
                                size: ColumnSize.S,
                                fixedWidth: 80,
                                numeric: true),
                            DataColumn2(
                                label: Text('Capacity'),
                                size: ColumnSize.S,
                                fixedWidth: 90,
                                numeric: true),
                            DataColumn2(label: Text('Utilisation'), size: ColumnSize.L),
                          ],
                          rows: rows.map((r) {
                            final used = r['used'] as int;
                            final capacity = r['capacity'] as int;
                            final percent = (r['percent'] as double);
                            final zones = (r['zones'] as List).cast<String>();
                            final color = _fillColor(context, percent);
                            return DataRow(cells: [
                              DataCell(Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r['warehouseName'] as String,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  Text(r['warehouseCode'] as String,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: context.colors.textMuted)),
                                ],
                              )),
                              DataCell(Text(
                                  zones.isEmpty ? '—' : zones.join(', '),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12))),
                              DataCell(Text('$used',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: context.colors.accentLightBlue))),
                              DataCell(Text('$capacity')),
                              DataCell(_UtilisationBar(
                                  percent: percent, color: color)),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UtilisationBar extends StatelessWidget {
  final double percent;
  final Color color;
  const _UtilisationBar({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    final clamped = (percent / 100).clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 8,
              backgroundColor: context.colors.surfaceDark,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const Gap(10),
        SizedBox(
          width: 48,
          child: Text('${percent.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.1)),
          Text(label,
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}
