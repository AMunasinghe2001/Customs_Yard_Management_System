import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/error_view.dart';
import '../../widgets/tooltip_text.dart';

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
    // Distinguishes "no warehouses at all" from "warehouses, but empty" —
    // two different situations that need two different next actions.
    final hasWarehouses =
        (ref.watch(warehousesProvider).valueOrNull ?? const []).isNotEmpty;

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
                  final totalCap =
                      rows.fold<int>(0, (s, r) => s + (r['capacity'] as int));
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
                    onRetry: () => ref.refresh(yardWarehouseCapacityProvider),
                  ),
                  data: (rows) {
                    if (rows.isEmpty) {
                      // "No stock" implies there is somewhere to put it. A
                      // yard with no warehouses yet needs to be told to add
                      // one, not to wait for packages that can never arrive.
                      return EmptyStateCard(
                        icon: hasWarehouses
                            ? Icons.inventory_2_outlined
                            : Icons.warehouse_rounded,
                        message: hasWarehouses
                            ? 'No active warehouse stock in your yard'
                            : 'No warehouses in your yard yet',
                        subtitle: hasWarehouses
                            ? 'Admitted packages for this yard will appear here.'
                            : 'Add a warehouse and its zones from the Admin '
                                'Panel to start tracking capacity.',
                      );
                    }
                    // One card per warehouse, listing its ZONES — capacity
                    // is managed zone by zone, so that is the level the yard
                    // needs to see. The warehouse line is just their total.
                    return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Gap(12),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final used = r['used'] as int;
                        final capacity = r['capacity'] as int;
                        final percent = r['percent'] as double;
                        // Null-safe: a cached row from before zones existed,
                        // or a warehouse whose zones have not loaded yet, has
                        // no `zoneRows` at all — treat that as "no zones" and
                        // let the card say so rather than crashing the page.
                        final zoneRows = ((r['zoneRows'] as List?) ?? const [])
                            .cast<Map<String, dynamic>>();
                        final unzoned = (r['unzoned'] as int?) ?? 0;
                        final color = _fillColor(context, percent);

                        return Container(
                          decoration: BoxDecoration(
                            color: context.colors.cardDark,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: context.colors.borderColor),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── The warehouse, and its zones' total ──
                              Row(children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(r['warehouseName'] as String,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                      Text(
                                          '${r['warehouseCode']}  \u00b7  '
                                          '${zoneRows.length} zone'
                                          '${zoneRows.length == 1 ? '' : 's'}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: context.colors.textMuted)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('$used / $capacity',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color:
                                              context.colors.accentLightBlue)),
                                ),
                                const Gap(16),
                                Expanded(
                                  flex: 4,
                                  child: _UtilisationBar(
                                      percent: percent, color: color),
                                ),
                              ]),
                              const Gap(12),
                              Divider(
                                  height: 1, color: context.colors.borderColor),
                              const Gap(12),

                              // ── Zone by zone ──
                              if (zoneRows.isEmpty)
                                Text(
                                    'No zones defined \u2014 add them in the '
                                    'Admin Panel so goods can be placed here.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: context.colors.textMuted))
                              else
                                ...zoneRows.map((z) {
                                  final zUsed = z['used'] as int;
                                  final zCap = z['capacity'] as int;
                                  final zPct = z['percent'] as double;
                                  final zFree = z['free'] as int;
                                  final zColor = _fillColor(context, zPct);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(children: [
                                      Expanded(
                                        flex: 3,
                                        child: Row(children: [
                                          Icon(Icons.grid_view_rounded,
                                              size: 14,
                                              color: context.colors.textMuted),
                                          const Gap(8),
                                          Flexible(
                                            child: TooltipText(
                                                'Zone ${z['name']}',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ),
                                        ]),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text('$zUsed / $zCap',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                                fontSize: 12.5,
                                                color: context
                                                    .colors.textSecondary)),
                                      ),
                                      const Gap(16),
                                      Expanded(
                                        flex: 4,
                                        child: _UtilisationBar(
                                            percent: zPct, color: zColor),
                                      ),
                                      const Gap(12),
                                      SizedBox(
                                        width: 96,
                                        child: Text(
                                            zFree == 0 ? 'FULL' : '$zFree free',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: zFree == 0
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                color: zFree == 0
                                                    ? context.colors.dangerRed
                                                    : context
                                                        .colors.successGreen)),
                                      ),
                                    ]),
                                  );
                                }),

                              // Goods held under no zone still occupy space,
                              // so they are reported rather than hidden.
                              if (unzoned > 0) ...[
                                const Gap(4),
                                Row(children: [
                                  Icon(Icons.help_outline_rounded,
                                      size: 14,
                                      color: context.colors.warningAmber),
                                  const Gap(8),
                                  Expanded(
                                    child: Text(
                                        '$unzoned item'
                                        '${unzoned == 1 ? '' : 's'} held '
                                        'outside any defined zone',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color:
                                                context.colors.warningAmber)),
                                  ),
                                ]),
                              ],
                            ],
                          ),
                        );
                      },
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
