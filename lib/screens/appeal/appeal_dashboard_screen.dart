import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../core/yards.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/disposal_profile_dialog.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/tooltip_text.dart';

final _appealSearchProvider = StateProvider<String>((ref) => '');
final _appealYardProvider = StateProvider<String?>((ref) => null); // null = all

/// Appeal Directorate dashboard: a cross-yard list of forfeited packages, where
/// the directorate can place / lift an appeal hold while the 30-day window is
/// still open. A held package can no longer be sold or destroyed.
class AppealDashboardScreen extends ConsumerStatefulWidget {
  const AppealDashboardScreen({super.key});
  @override
  ConsumerState<AppealDashboardScreen> createState() =>
      _AppealDashboardScreenState();
}

class _AppealDashboardScreenState extends ConsumerState<AppealDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _activePage = 0;
  int _decidedPage = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _itemName(ForfeitedPackageModel f) {
    // If expanded per-item row, show exact item name
    if (f.itemName != null) return f.itemName!;
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.appealPurple;
    final profile = ref.watch(currentProfileProvider);
    final async = ref.watch(appealForfeitedPackagesProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    // Pre-compute counts for tab labels
    final allList = async.valueOrNull ?? [];
    final activeCount = allList
        .where((f) => !f.hasAppealDecision &&
            (!f.isAppealExpired || f.isAppealHeld))
        .length;
    final decidedCount = allList.where((f) => f.hasAppealDecision).length;
    final bidsCount =
        ref.watch(packagesWithBidsProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [accent.withOpacity(0.08), context.colors.cardDark],
              ),
              border: Border(
                  bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.3)),
                ),
                child: SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                    width: 30, height: 30, theme: SvgTheme(currentColor: accent)),
              ),
              const Gap(14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Appeal Directorate',
                      style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  Text('Review forfeited packages · hold appeals before disposal',
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 12)),
                ],
              ),
              const Spacer(),
              if (profile != null)
                Tooltip(
                  message: 'View profile',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => DisposalProfileDialog(accent: accent),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: accent.withOpacity(0.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.balance_rounded, color: accent, size: 16),
                        const Gap(8),
                        Text(profile.fullName,
                            style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const Gap(6),
                        Icon(Icons.chevron_right_rounded,
                            color: accent.withOpacity(0.7), size: 16),
                      ]),
                    ),
                  ),
                ),
              const Gap(8),
              IconButton(
                tooltip: 'Toggle theme',
                icon: Icon(
                    ref.watch(themeModeProvider) == ThemeMode.dark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: context.colors.textPrimary),
                onPressed: () {
                  final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
                  ref.read(themeModeProvider.notifier).state =
                      isDark ? ThemeMode.light : ThemeMode.dark;
                },
              ),
              const Gap(4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.dangerRed,
                  side: BorderSide(
                      color: context.colors.dangerRed.withOpacity(0.5)),
                ),
                icon: const Icon(Icons.logout_rounded, size: 16),
                label: const Text('Sign Out'),
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  ref.read(currentProfileProvider.notifier).state = null;
                  if (context.mounted) context.go('/');
                },
              ),
            ]),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.15),

          // ── Tab bar ───────────────────────────────────────────
          Container(
            color: context.colors.cardDark,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderColor),
              ),
              child: TabBar(
                controller: _tabController,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: accent.withOpacity(0.5)),
                ),
                labelColor: accent,
                unselectedLabelColor: context.colors.textMuted,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13),
                tabs: [
                  Tab(
                    height: 44,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.balance_rounded, size: 18),
                      const Gap(8),
                      const Flexible(child: Text('Active Appeals', overflow: TextOverflow.ellipsis)),
                      if (activeCount > 0) ...[
                        const Gap(6),
                        _TabBadge(activeCount, accent),
                      ],
                    ]),
                  ),
                  Tab(
                    height: 44,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.gavel_rounded, size: 18),
                      const Gap(8),
                      const Flexible(child: Text('Decided Packages', overflow: TextOverflow.ellipsis)),
                      if (decidedCount > 0) ...[
                        const Gap(6),
                        _TabBadge(decidedCount, accent),
                      ],
                    ]),
                  ),
                  Tab(
                    height: 44,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.sell_rounded, size: 18),
                      const Gap(8),
                      const Flexible(child: Text('Tender Bids', overflow: TextOverflow.ellipsis)),
                      if (bidsCount > 0) ...[
                        const Gap(6),
                        _TabBadge(bidsCount, accent),
                      ],
                    ]),
                  ),
                ],
              ),
            ),
          ),

          // ── Tab views ─────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ActiveTab(
                  async: async,
                  accent: accent,
                  storageRate: storageRate,
                  page: _activePage,
                  onPageChanged: (p) => setState(() => _activePage = p),
                  onPageReset: () => setState(() => _activePage = 0),
                  itemName: _itemName,
                  buildRow: _buildRow,
                  openDetails: _openDetails,
                  listCard: _listCard,
                ),
                _DecidedTab(
                  async: async,
                  accent: accent,
                  storageRate: storageRate,
                  page: _decidedPage,
                  onPageChanged: (p) => setState(() => _decidedPage = p),
                  onPageReset: () => setState(() => _decidedPage = 0),
                  itemName: _itemName,
                  buildDecidedRow: _buildDecidedRow,
                  listCard: _listCard,
                ),
                _BidsTab(accent: accent, itemName: _itemName),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, ForfeitedPackageModel f) {
    final (label, color) = f.isAppealHeld
        ? ('On Appeal Hold', context.colors.warningAmber)
        : f.hasAppealDecision
            ? ('Decided · ${f.appealDecisionLabel}', context.colors.accentLightBlue)
            : f.isAppealExpired
                ? ('Window Passed', context.colors.dangerRed)
                : ('In Appeal · ${f.daysUntilDeadline}d',
                    context.colors.successGreen);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  DataRow _buildRow(BuildContext context, ForfeitedPackageModel f,
      Map<DateTime, double> storageRate) {
    return DataRow(cells: [
      DataCell(TooltipText(f.srNumber,
          style: TextStyle(
              color: context.colors.accentLightBlue,
              fontWeight: FontWeight.w600))),
      DataCell(TooltipText(_itemName(f), overflow: TextOverflow.ellipsis)),
      DataCell(TooltipText(f.consigneeName, overflow: TextOverflow.ellipsis)),
      DataCell(TooltipText(yardName(f.yard), overflow: TextOverflow.ellipsis)),
      DataCell(TooltipText(DateFormat('yyyy-MM-dd').format(f.appealDeadline),
          style: TextStyle(
              color: f.isAppealExpired
                  ? context.colors.dangerRed
                  : context.colors.textSecondary,
              fontWeight: FontWeight.w600))),
      DataCell(Center(child: _statusChip(context, f))),
      DataCell(Center(
        child: IconButton(
          icon: Icon(Icons.info_outline_rounded,
              color: context.colors.accentLightBlue, size: 18),
          onPressed: f.packageDetails == null
              ? null
              : () => _openDetails(context, f, storageRate),
        ),
      )),
    ]);
  }

  DataRow _buildDecidedRow(BuildContext context, ForfeitedPackageModel f,
      Map<DateTime, double> storageRate) {
    final decisionColor = context.colors.accentLightBlue;
    return DataRow(cells: [
      DataCell(TooltipText(f.srNumber,
          style: TextStyle(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w600))),
      DataCell(TooltipText(_itemName(f), overflow: TextOverflow.ellipsis)),
      DataCell(TooltipText(f.consigneeName, overflow: TextOverflow.ellipsis)),
      DataCell(TooltipText(yardName(f.yard), overflow: TextOverflow.ellipsis)),
      DataCell(TooltipText(DateFormat('yyyy-MM-dd').format(f.appealDeadline),
          style: TextStyle(
              color: context.colors.textMuted,
              fontWeight: FontWeight.w500))),
      DataCell(Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: decisionColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: decisionColor.withOpacity(0.4)),
        ),
        child: Text('Decided · ${f.appealDecisionLabel ?? ''}',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: decisionColor,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      ))),
      DataCell(Center(
        child: IconButton(
          icon: Icon(Icons.info_outline_rounded,
              color: context.colors.accentLightBlue, size: 18),
          onPressed: f.packageDetails == null
              ? null
              : () => _openDetails(context, f, storageRate),
        ),
      )),
    ]);
  }

  // Opens the package details popup with a footer Hold-Appeal / Release action.
  void _openDetails(BuildContext context, ForfeitedPackageModel f,
      Map<DateTime, double> storageRate) {
    String? label;
    IconData? icon;
    Color? color;
    String? hint;
    VoidCallback? action;
    // No action buttons for packages that already have a decision.
    if (!f.hasAppealDecision) {
      if (f.isAppealHeld) {
        label = 'Release Hold & Decide';
        icon = Icons.gavel_rounded;
        color = context.colors.successGreen;
        hint = 'Lift the hold and record what the yard should do with this package';
        action = () => _showDecisionDialog(context, f);
      } else if (!f.isAppealExpired) {
        label = 'Hold Appeal';
        icon = Icons.gavel_rounded;
        color = context.colors.warningAmber;
        hint = 'Place an appeal hold — blocks sale/destruction of this package';
        action = () => _setHold(context, f, true);
      }
    }
    showDialog(
      context: context,
      builder: (_) => PackageDetailsDialog(
        package: f.packageDetails!,
        storageRate: storageRate,
        headerAccentColor: AppTheme.appealPurple,
        useLegacySummary: true,
        highlightItemId: f.itemId ??
            (f.packageDetails!.items.isNotEmpty
                ? f.packageDetails!.items.first.id
                : null),
        yardLabel: f.yard != null ? yardName(f.yard!) : null,
        footerActionLabel: label,
        footerActionIcon: icon,
        footerActionColor: color,
        footerActionHint: hint,
        onFooterAction: action,
      ),
    );
  }

  Future<void> _setHold(
      BuildContext context, ForfeitedPackageModel f, bool hold) async {
    try {
      await ref.read(appealServiceProvider).setAppealHold(
            f.id,
            hold,
            itemId: f.itemId, // per-item hold — only this item affected
          );
      ref.invalidate(appealForfeitedPackagesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: hold
              ? context.colors.warningAmber
              : context.colors.successGreen,
          content: Text(hold
              ? 'Appeal hold placed — ${f.srNumber} cannot be sold or destroyed.'
              : 'Appeal hold lifted for ${f.srNumber}.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        final msg = e.toString().contains('appeal_window_passed')
            ? 'The appeal window for this package has already passed.'
            : 'Error: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.dangerRed,
          content: Text(msg),
        ));
      }
    }
  }

  Future<void> _showDecisionDialog(
      BuildContext context, ForfeitedPackageModel f) async {
    final result = await showDialog<_AppealDecisionResult>(
      context: context,
      builder: (_) => _AppealDecisionDialog(srNumber: f.srNumber),
    );
    if (result == null) return;
    if (!context.mounted) return;
    try {
      // First release the per-item hold for this specific item
      await ref.read(appealServiceProvider).setAppealHold(
            f.id,
            false,
            itemId: f.itemId,
          );
      await ref.read(appealServiceProvider).releaseAppealWithDecision(
            f.id,
            result.decision,
            note: result.note,
            itemId: f.itemId, // per-item decision — only this item is decided
          );
      ref.invalidate(appealForfeitedPackagesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.successGreen,
          content: Text(
              'Hold lifted — ${f.srNumber} forwarded to yard for: ${result.label}.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: context.colors.dangerRed,
          content: Text('Error: $e'),
        ));
      }
    }
  }

  Widget _listCard(BuildContext context, Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }
}

// ── Small badge shown on tab labels ──────────────────────────────────────────
class _TabBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _TabBadge(this.count, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$count',
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ── Tender Bids tab (read-only view of bids recorded by Central Disposal) ─────
class _BidsTab extends ConsumerWidget {
  final Color accent;
  final String Function(ForfeitedPackageModel) itemName;
  const _BidsTab({required this.accent, required this.itemName});

  static final _money = NumberFormat('#,##0.##', 'en_US');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(packagesWithBidsProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Tender Bids',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Gap(10),
            Text('Bid values recorded on unsold tender packages',
                style: TextStyle(
                    color: context.colors.textMuted, fontSize: 13)),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: accent)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(packagesWithBidsProvider)),
              data: (list) {
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
                      minWidth: 900,
                      empty: const EmptyTableState(
                          message: 'No bids recorded yet'),
                      headingRowColor: WidgetStateProperty.all(
                          context.colors.surfaceDark),
                      columns: const [
                        DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                        DataColumn2(label: Text('Item'), size: ColumnSize.M),
                        DataColumn2(
                            label: Text('Consignee'), size: ColumnSize.M),
                        DataColumn2(
                            label: Text('Yard'),
                            size: ColumnSize.S,
                            fixedWidth: 110),
                        DataColumn2(
                            label: Center(child: Text('Bids')),
                            size: ColumnSize.S,
                            fixedWidth: 70),
                        DataColumn2(
                            label: Center(child: Text('Highest')),
                            size: ColumnSize.S,
                            fixedWidth: 130),
                        DataColumn2(
                            label: Center(child: Text('View')),
                            size: ColumnSize.S,
                            fixedWidth: 70),
                      ],
                      rows: list.map((e) {
                        final f = e.forfeited;
                        final rounds = e.rounds;
                        final bidCount = rounds.fold<int>(
                            0, (s, r) => s + r.bids.length);
                        final highest = rounds.fold<double>(0, (m, r) =>
                            r.bids.isNotEmpty && r.bids.first > m
                                ? r.bids.first
                                : m);
                        return DataRow(cells: [
                          DataCell(TooltipText(f.srNumber,
                              style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w600))),
                          DataCell(TooltipText(itemName(f),
                              overflow: TextOverflow.ellipsis)),
                          DataCell(TooltipText(f.consigneeName,
                              overflow: TextOverflow.ellipsis)),
                          DataCell(TooltipText(yardName(f.yard),
                              overflow: TextOverflow.ellipsis)),
                          DataCell(Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('$bidCount',
                                  style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w800)),
                            ),
                          )),
                          DataCell(Center(
                            child: Text('Rs. ${_money.format(highest)}',
                                style: TextStyle(
                                    color: context.colors.successGreen,
                                    fontWeight: FontWeight.w700)),
                          )),
                          DataCell(Center(
                            child: IconButton(
                              icon: Icon(Icons.visibility_rounded,
                                  size: 18, color: accent),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) => _ViewBidsDialog(
                                    forfeited: f,
                                    rounds: rounds,
                                    itemName: itemName(f)),
                              ),
                            ),
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only popup listing the bid amounts recorded for a package, grouped by
/// tender ROUND (attempt), newest round first; each round's highest is
/// highlighted. Modelled on the Central Disposal tender-history.
class _ViewBidsDialog extends StatelessWidget {
  final ForfeitedPackageModel forfeited;
  // rounds newest-first; each round's bids already highest-first.
  final List<({TenderSaleModel? sale, List<double> bids})> rounds;
  final String itemName;
  const _ViewBidsDialog({
    required this.forfeited,
    required this.rounds,
    required this.itemName,
  });

  static final _money = NumberFormat('#,##0.##', 'en_US');

  String _roundTitle(({TenderSaleModel? sale, List<double> bids}) r, int n) {
    final s = r.sale;
    final parts = <String>['Tender $n'];
    if (s?.saleNumber != null && s!.saleNumber!.isNotEmpty) {
      parts.add(s.saleNumber!);
    }
    if (s?.saleDate != null) {
      parts.add(DateFormat('yyyy-MM-dd').format(s!.saleDate!));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.appealPurple;
    // Number the rounds oldest→newest for the labels, but keep display newest-first.
    final total = rounds.length;
    return StyledFormDialog(
      label: 'Recorded Bids',
      title: forfeited.srNumber,
      headerAccentColor: accent,
      icon: Icons.sell_rounded,
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rounds.isEmpty)
            StyledFormSection(
              title: itemName,
              icon: Icons.payments_rounded,
              children: [
                Text('No bids recorded.',
                    style: TextStyle(color: context.colors.textMuted)),
              ],
            )
          else
            for (int r = 0; r < rounds.length; r++) ...[
              if (r > 0) const Gap(14),
              StyledFormSection(
                title: _roundTitle(rounds[r], total - r),
                icon: Icons.gavel_rounded,
                children: [
                  for (int i = 0; i < rounds[r].bids.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: context.colors.cardDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: i == 0
                                ? context.colors.successGreen.withOpacity(0.5)
                                : context.colors.borderColor),
                      ),
                      child: Row(children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Text('${i + 1}',
                              style: TextStyle(
                                  color: accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const Gap(12),
                        Text('Rs. ${_money.format(rounds[r].bids[i])}',
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800)),
                        const Spacer(),
                        if (i == 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.colors.successGreen
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Highest',
                                style: TextStyle(
                                    color: context.colors.successGreen,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ]),
                    ),
                ],
              ),
            ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}

// ── Active Appeals tab ────────────────────────────────────────────────────────
class _ActiveTab extends ConsumerStatefulWidget {
  final AsyncValue<List<ForfeitedPackageModel>> async;
  final Color accent;
  final Map<DateTime, double> storageRate;
  final int page;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onPageReset;
  final String Function(ForfeitedPackageModel) itemName;
  final DataRow Function(BuildContext, ForfeitedPackageModel, Map<DateTime, double>) buildRow;
  final void Function(BuildContext, ForfeitedPackageModel, Map<DateTime, double>) openDetails;
  final Widget Function(BuildContext, Widget) listCard;

  const _ActiveTab({
    required this.async,
    required this.accent,
    required this.storageRate,
    required this.page,
    required this.onPageChanged,
    required this.onPageReset,
    required this.itemName,
    required this.buildRow,
    required this.openDetails,
    required this.listCard,
  });

  @override
  ConsumerState<_ActiveTab> createState() => _ActiveTabState();
}

class _ActiveTabState extends ConsumerState<_ActiveTab> {
  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search + yard filter row
          Row(children: [
            Text('Active Appeals',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            SizedBox(
              width: 320,
              child: TextField(
                onChanged: (v) {
                  ref.read(_appealSearchProvider.notifier).state = v;
                  widget.onPageReset();
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search SR / item / consignee…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: accent.withOpacity(0.06),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: accent.withOpacity(0.4))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: accent.withOpacity(0.4))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: accent, width: 1.5)),
                ),
              ),
            ),
            const Gap(12),
            _AppealYardFilter(
              accent: accent,
              value: ref.watch(_appealYardProvider),
              onChanged: (v) {
                ref.read(_appealYardProvider.notifier).state = v;
                widget.onPageReset();
              },
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          // Stat chips
          widget.async.maybeWhen(
            data: (list) {
              final active = list
                  .where((f) => !f.hasAppealDecision &&
                      (!f.isAppealExpired || f.isAppealHeld))
                  .toList();
              final held = active.where((f) => f.isAppealHeld).length;
              final openWindow = active.where((f) => !f.isAppealHeld).length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  _StatChip(label: 'Active', value: '${active.length}', color: context.colors.accentLightBlue),
                  const Gap(12),
                  _StatChip(label: 'In Appeal Window', value: '$openWindow', color: context.colors.successGreen),
                  const Gap(12),
                  _StatChip(label: 'On Appeal Hold', value: '$held', color: context.colors.warningAmber),
                ]),
              ).animate().fadeIn(duration: 300.ms);
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: widget.async.when(
              skipLoadingOnReload: true,
              loading: () => Center(child: CircularProgressIndicator(color: accent)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(appealForfeitedPackagesProvider)),
              data: (list) {
                final q = ref.watch(_appealSearchProvider).toLowerCase();
                final yard = ref.watch(_appealYardProvider);
                var rows = list
                    .where((f) => !f.hasAppealDecision &&
                        (!f.isAppealExpired || f.isAppealHeld))
                    .toList();
                if (yard != null) rows = rows.where((f) => f.yard == yard).toList();
                if (q.isNotEmpty) {
                  rows = rows.where((f) =>
                      f.srNumber.toLowerCase().contains(q) ||
                      f.consigneeName.toLowerCase().contains(q) ||
                      widget.itemName(f).toLowerCase().contains(q)).toList();
                }
                return Column(children: [
                  Expanded(
                    child: widget.listCard(context,
                      DataTable2(
                        columnSpacing: 12,
                        horizontalMargin: 16,
                        fixedTopRows: 1,
                        minWidth: 1000,
                        empty: const EmptyTableState(message: 'No active forfeited packages'),
                        headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
                        columns: const [
                          DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                          DataColumn2(label: Text('Item'), size: ColumnSize.M),
                          DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                          DataColumn2(label: Text('Yard'), size: ColumnSize.S, fixedWidth: 110),
                          DataColumn2(label: Text('Appeal Deadline'), size: ColumnSize.S),
                          DataColumn2(label: Center(child: Text('Status')), size: ColumnSize.S, fixedWidth: 140),
                          DataColumn2(label: Center(child: Text('Details')), size: ColumnSize.S, fixedWidth: 70),
                        ],
                        rows: pageSlice(rows, widget.page, kClientPageSize)
                            .map((f) => widget.buildRow(context, f, widget.storageRate))
                            .toList(),
                      ),
                    ),
                  ),
                  TablePager(
                    total: rows.length,
                    page: widget.page,
                    pageSize: kClientPageSize,
                    onPageChanged: widget.onPageChanged,
                  ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Decided Packages tab ──────────────────────────────────────────────────────
class _DecidedTab extends ConsumerStatefulWidget {
  final AsyncValue<List<ForfeitedPackageModel>> async;
  final Color accent;
  final Map<DateTime, double> storageRate;
  final int page;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onPageReset;
  final String Function(ForfeitedPackageModel) itemName;
  final DataRow Function(BuildContext, ForfeitedPackageModel, Map<DateTime, double>) buildDecidedRow;
  final Widget Function(BuildContext, Widget) listCard;

  const _DecidedTab({
    required this.async,
    required this.accent,
    required this.storageRate,
    required this.page,
    required this.onPageChanged,
    required this.onPageReset,
    required this.itemName,
    required this.buildDecidedRow,
    required this.listCard,
  });

  @override
  ConsumerState<_DecidedTab> createState() => _DecidedTabState();
}

class _DecidedTabState extends ConsumerState<_DecidedTab> {
  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Decided Packages',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            SizedBox(
              width: 320,
              child: TextField(
                onChanged: (v) {
                  ref.read(_appealSearchProvider.notifier).state = v;
                  widget.onPageReset();
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search SR / item / consignee…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: accent.withOpacity(0.06),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: accent.withOpacity(0.4))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: accent.withOpacity(0.4))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: accent, width: 1.5)),
                ),
              ),
            ),
            const Gap(12),
            _AppealYardFilter(
              accent: accent,
              value: ref.watch(_appealYardProvider),
              onChanged: (v) {
                ref.read(_appealYardProvider.notifier).state = v;
                widget.onPageReset();
              },
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          Expanded(
            child: widget.async.when(
              skipLoadingOnReload: true,
              loading: () => Center(child: CircularProgressIndicator(color: accent)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(appealForfeitedPackagesProvider)),
              data: (list) {
                final q = ref.watch(_appealSearchProvider).toLowerCase();
                final yard = ref.watch(_appealYardProvider);
                var rows = list.where((f) => f.hasAppealDecision).toList();
                if (yard != null) rows = rows.where((f) => f.yard == yard).toList();
                if (q.isNotEmpty) {
                  rows = rows.where((f) =>
                      f.srNumber.toLowerCase().contains(q) ||
                      f.consigneeName.toLowerCase().contains(q) ||
                      widget.itemName(f).toLowerCase().contains(q)).toList();
                }
                return Column(children: [
                  Expanded(
                    child: widget.listCard(context,
                      DataTable2(
                        columnSpacing: 12,
                        horizontalMargin: 16,
                        fixedTopRows: 1,
                        minWidth: 1000,
                        empty: const EmptyTableState(message: 'No decided packages'),
                        headingRowColor: WidgetStateProperty.all(context.colors.surfaceDark),
                        columns: const [
                          DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                          DataColumn2(label: Text('Item'), size: ColumnSize.M),
                          DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                          DataColumn2(label: Text('Yard'), size: ColumnSize.S, fixedWidth: 110),
                          DataColumn2(label: Text('Appeal Deadline'), size: ColumnSize.S),
                          DataColumn2(label: Center(child: Text('Decision')), size: ColumnSize.S, fixedWidth: 160),
                          DataColumn2(label: Center(child: Text('Details')), size: ColumnSize.S, fixedWidth: 70),
                        ],
                        rows: pageSlice(rows, widget.page, kClientPageSize)
                            .map((f) => widget.buildDecidedRow(context, f, widget.storageRate))
                            .toList(),
                      ),
                    ),
                  ),
                  TablePager(
                    total: rows.length,
                    page: widget.page,
                    pageSize: kClientPageSize,
                    onPageChanged: widget.onPageChanged,
                  ),
                ]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Yard dropdown ("All Yards" + every yard) tinted to the appeal accent.
class _AppealYardFilter extends StatelessWidget {
  final Color accent;
  final String? value; // null = all
  final ValueChanged<String?> onChanged;
  const _AppealYardFilter(
      {required this.accent, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));
    return SizedBox(
      width: 220,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme:
              Theme.of(context).inputDecorationTheme.copyWith(
                    filled: true,
                    fillColor: accent.withOpacity(0.06),
                    border: border(accent.withOpacity(0.4)),
                    enabledBorder: border(accent.withOpacity(0.4)),
                    focusedBorder: border(accent, 1.5),
                  ),
        ),
        child: StyledDropdownFormField<String>(
          value: value ?? '_all',
          label: 'Yard',
          helperText: null,
          isDense: true,
          menuWidth: 220,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon:
              Icon(Icons.warehouse_rounded, color: accent, size: 20),
          options: [
            const StyledDropdownOption('_all', 'All Yards'),
            for (final y in kYards) StyledDropdownOption(y.code, y.name),
          ],
          onChanged: (v) => onChanged((v == null || v == '_all') ? null : v),
        ),
      ),
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

// ── Appeal decision picker ────────────────────────────────────────────────────
// Returned when the directorate lifts a hold and chooses what the owning yard
// should do next with the package.
class _AppealDecisionResult {
  final String decision; // RELEASE / SALE / DESTROY / RE-EXPORT / OTHER
  final String? note; // custom outcome text for OTHER
  final String label; // human-friendly label for the snackbar
  const _AppealDecisionResult(this.decision, this.label, {this.note});
}

class _AppealDecisionOption {
  final String key;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  const _AppealDecisionOption(
      this.key, this.label, this.description, this.icon, this.color);
}

class _AppealDecisionDialog extends StatefulWidget {
  final String srNumber;
  const _AppealDecisionDialog({required this.srNumber});

  @override
  State<_AppealDecisionDialog> createState() => _AppealDecisionDialogState();
}

class _AppealDecisionDialogState extends State<_AppealDecisionDialog> {
  String? _selected;
  final _otherCtrl = TextEditingController();

  static const _options = [
    _AppealDecisionOption('RELEASE', 'Release to owner',
        'Return the goods to the owner.', Icons.assignment_return_rounded,
        Color(0xFF43A047)),
    _AppealDecisionOption('SALE', 'Sell',
        'Dispose of the goods by sale.', Icons.sell_rounded,
        Color(0xFFE8A826)),
    _AppealDecisionOption('DESTROY', 'Destroy',
        'Destroy the goods.', Icons.delete_forever_rounded,
        Color(0xFFE64A19)),
    _AppealDecisionOption('RE-EXPORT', 'Re-export',
        'Send the goods back to country of origin.',
        Icons.flight_takeoff_rounded, Color(0xFF00ACC1)),
    _AppealDecisionOption('OTHER', 'Other',
        'A custom outcome — describe below.', Icons.more_horiz_rounded,
        Color(0xFF7E57C2)),
  ];

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.appealPurple;
    final isOther = _selected == 'OTHER';
    final canConfirm = _selected != null &&
        (!isOther || _otherCtrl.text.trim().isNotEmpty);

    return StyledFormDialog(
      label: 'APPEAL DECISION',
      title: widget.srNumber,
      icon: Icons.gavel_rounded,
      headerAccentColor: accent,
      width: 520,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Confirm & Release Hold'),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor:
                context.colors.textMuted.withOpacity(0.3),
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 14),
          ),
          onPressed: !canConfirm
              ? null
              : () {
                  final opt = _options
                      .firstWhere((o) => o.key == _selected);
                  final note = isOther
                      ? _otherCtrl.text.trim()
                      : null;
                  final label =
                      isOther ? _otherCtrl.text.trim() : opt.label;
                  Navigator.pop(
                      context,
                      _AppealDecisionResult(opt.key, label,
                          note: note));
                },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The appeal has been processed. Choose what the owning yard '
            'should do with this package — the yard will act on this decision.',
            style: TextStyle(
                color: context.colors.textSecondary, fontSize: 13),
          ),
          const Gap(16),
          ..._options.map((o) {
            final selected = _selected == o.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _selected = o.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: o.color
                        .withOpacity(selected ? 0.10 : 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: o.color.withOpacity(selected ? 0.7 : 0.2),
                      width: selected ? 1.6 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: o.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(o.icon, color: o.color, size: 20),
                    ),
                    const Gap(14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(o.label,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: o.color)),
                          const Gap(2),
                          Text(o.description,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.colors.textMuted)),
                        ],
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected
                          ? o.color
                          : context.colors.textMuted,
                      size: 20,
                    ),
                  ]),
                ),
              ),
            );
          }),
          if (isOther) ...[
            const Gap(4),
            TextField(
              controller: _otherCtrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Describe the outcome *',
                hintText: 'e.g. Transfer to another authority',
                isDense: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
