import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../widgets/sealed_valuation.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import 'disposal_shared.dart';
import 'taxes_tab.dart';
import 'expenses_tab.dart';
import '../reports/reports_screen.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/one_tap_date_picker.dart';
import '../../widgets/disposal_profile_dialog.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/tooltip_text.dart';
import '../../widgets/destruction_status_pill.dart';
import '../executive/unsold_shared.dart';

/// The quantity actually forfeited & sent for disposal for a request row.
/// Prefers the stored [entryQty]; otherwise derives it from the item's forfeit
/// warehouse entries ([FORFEIT]/[CONFISCATED]) — so a partial forfeit (e.g. 6
/// of 10) is priced/shown on 6, not the full item quantity. Null if unknown.
int? _disposalForfeitedQty(DisposalRequestItemModel it, PackageItem? pkgItem) {
  if (it.forfeited?.entryQty != null) return it.forfeited!.entryQty;
  final pkg = it.forfeited?.packageDetails;
  final targetId = pkgItem?.id ?? it.forfeited?.itemId;
  if (pkg == null || targetId == null) return null;
  final q = pkg.warehouseEntries.where((e) {
    if (!e.isReturned || e.packageItemId != targetId) return false;
    final n = (e.returnNotes ?? '').trim().toUpperCase();
    return n.startsWith('[FORFEIT') || n.startsWith('[CONFISCATED');
  }).fold<int>(0, (s, e) => s + e.itemCount);
  return q > 0 ? q : null;
}

class DisposalDashboardScreen extends ConsumerWidget {
  const DisposalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final profile = ref.watch(currentProfileProvider);
    return DefaultTabController(
      length: 15,
      child: Scaffold(
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
                  colors: [
                    green.withOpacity(0.08),
                    context.colors.cardDark,
                  ],
                ),
                border: Border(
                    bottom: BorderSide(color: context.colors.borderColor)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: green.withOpacity(0.3)),
                  ),
                  child: SvgPicture.asset('Sri_Lanka_Customs_logo_tinted.svg',
                      width: 30,
                      height: 30,
                      theme: SvgTheme(currentColor: green)),
                ),
                const Gap(14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Central Disposal Directorate',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w800)),
                    Text(
                        'Sold & forfeited items across all yards · tender sales',
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
                        builder: (_) => const DisposalProfileDialog(),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: green.withOpacity(0.35)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.verified_user_rounded,
                              color: green, size: 16),
                          const Gap(8),
                          Text(profile.fullName,
                              style: TextStyle(
                                  color: green,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                          // Amber dot when the password is within its 7-day
                          // expiry window — a quiet nudge to open the profile.
                          if (profile.isPasswordExpiringSoon ||
                              profile.isPasswordExpired) ...[
                            const Gap(8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: profile.isPasswordExpired
                                    ? context.colors.dangerRed
                                    : context.colors.warningAmber,
                              ),
                            ),
                          ],
                          const Gap(4),
                          Icon(Icons.chevron_right_rounded,
                              color: green.withOpacity(0.7), size: 16),
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
                    final isDark =
                        ref.read(themeModeProvider) == ThemeMode.dark;
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
            // ── Tabs ─────────────────────────────────────────────
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
                  // 10 tabs no longer fit at a readable width — scroll instead
                  // of truncating every label to "Destroyed ...".
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.all(4),
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: green.withOpacity(0.5)),
                  ),
                  labelColor: green,
                  unselectedLabelColor: context.colors.textMuted,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: const [
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.sell_rounded, size: 18),
                              Gap(8),
                              Text('Sold Goods'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.pending_actions_rounded, size: 18),
                              Gap(8),
                              Text('Unsold Goods'),
                            ])),
                    // ── The Top Management Directorate's outcomes, one tab each ──
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.account_balance_rounded, size: 18),
                              Gap(8),
                              Text('Government Use'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.reply_all_rounded, size: 18),
                              Gap(8),
                              Text('Remanded'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.gavel_rounded, size: 18),
                              Gap(8),
                              Text('Auction'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.autorenew_rounded, size: 18),
                              Gap(8),
                              Text('Converted'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout_rounded, size: 18),
                              Gap(8),
                              Text('Removed'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.delete_forever_rounded, size: 18),
                              Gap(8),
                              Text('Destroyed Goods'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_turned_in_rounded,
                                  size: 18),
                              Gap(8),
                              Text('Disposal Requests'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.storefront_rounded, size: 18),
                              Gap(8),
                              Text('Tender Sales'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.replay_rounded, size: 18),
                              Gap(8),
                              Text('Unsold Tenders'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.groups_rounded, size: 18),
                              Gap(8),
                              Text('Committees'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_rounded, size: 18),
                              Gap(8),
                              Text('Taxes'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.payments_rounded, size: 18),
                              Gap(8),
                              Text('Expenses'),
                            ])),
                    Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assessment_rounded, size: 18),
                              Gap(8),
                              Text('Reports'),
                            ])),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 350.ms, delay: 80.ms),
            const Expanded(
              child: TabBarView(children: [
                _SoldPackagesTab(),
                UnsoldProposalsTab(),
                UnsoldProposalsTab(
                    title: 'Government Use Goods',
                    countNoun: 'For government use',
                    proposalFilter: 'government_use',
                    tabKey: 'outcome-government-use'),
                UnsoldProposalsTab(
                    title: 'Remanded Goods',
                    countNoun: 'Remanded',
                    proposalFilter: 'remand',
                    tabKey: 'outcome-remand'),
                UnsoldProposalsTab(
                    title: 'Auction Goods',
                    countNoun: 'For auction',
                    proposalFilter: 'auction',
                    tabKey: 'outcome-auction'),
                UnsoldProposalsTab(
                    title: 'Converted Goods',
                    countNoun: 'Converted',
                    proposalFilter: 'convert',
                    tabKey: 'outcome-convert'),
                UnsoldProposalsTab(
                    title: 'Removed from the Premises',
                    countNoun: 'Removed',
                    proposalFilter: 'remove_from_premises',
                    tabKey: 'outcome-removed'),
                _DestroyedPackagesTab(),
                _DisposalRequestsTab(),
                _TenderSalesTab(),
                _UnsoldReTenderTab(),
                _CommitteesTab(),
                TaxesTab(),
                ExpensesTab(),
                ReportsScreen(disposalMode: true),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────

/// Page index for the Unsold Packages tab's client-side pager.
/// Page index, keyed by tab — the outcome tabs share this widget, so a single
/// provider would carry one tab's page number into the next.
final _unsoldPageProvider =
    StateProvider.family<int, String>((ref, tabKey) => 0);

/// Packages that exhausted every avenue — the Valuation Tender, Tender 1-3 and
/// the committee-valued tender all failed. READ-ONLY here: the DG decides the
/// final outcome on the Top Management Directorate portal, this directorate carries it out.
///
/// Uses the shared Unsold table (see `unsold_shared.dart`) so this tab, the
/// yard's Unsold page and the Top Management Directorate's tab show identical details.
class UnsoldProposalsTab extends ConsumerWidget {
  /// Page title, and the word inside the count pill.
  final String title;
  final String countNoun;

  /// One of [kUnsoldProposals], or null to list every unsold package.
  ///
  /// Null keeps this the Unsold Goods tab; set to an outcome code it lists
  /// only the goods the Top Management Directorate decided that way, so Government Use /
  /// Remand / Convert / Removed each get a tab without a copy of this file.
  final String? proposalFilter;

  /// Keys this tab's own search box, yard filter and pager, so switching tabs
  /// does not carry one tab's search into another.
  final String tabKey;

  const UnsoldProposalsTab({
    super.key,
    this.title = 'Unsold Goods',
    this.countNoun = 'Unsold',
    this.proposalFilter,
    this.tabKey = 'unsold-proposals',
  });

  static const int _pageSize = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final amber = context.colors.warningAmber;
    final blue = context.colors.accentLightBlue;
    // The shared "every avenue exhausted" list, so this tab, the yard page and
    // the Top Management Directorate all show exactly the same packages.
    final async = ref.watch(exhaustedUnsoldProvider);
    // Top Management tender committees, keyed by forfeited_package_id — their
    // valuation supersedes the original for an unsold package.
    final committees = ref.watch(tenderCommitteesProvider).valueOrNull ??
        const <String, TenderCommitteeModel>{};
    final q = ref.watch(disposalSearchProvider(tabKey)).toLowerCase();
    final yardFilter = ref.watch(disposalYardFilterProvider(tabKey));
    final proposals =
        ref.watch(unsoldProposalsProvider).valueOrNull ?? const {};
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        const <DateTime, double>{};

    final rows = async.when(
      skipLoadingOnReload: true,
      loading: () => const <ReTenderSaleInfo>[],
      error: (_, __) => const <ReTenderSaleInfo>[],
      data: (list) {
        var filtered = list;
        // The outcome this tab is for. Applied FIRST so the count pill, the
        // table and the pager all describe the same set.
        if (proposalFilter != null) {
          filtered = filtered
              .where((info) =>
                  proposals[info.forfeited.id]?.proposal == proposalFilter)
              .toList();
        }
        if (yardFilter != null) {
          filtered = filtered
              .where((info) => matchesYardFilter(
                  yardFilter, info.forfeited.yard, info.forfeited.srNumber))
              .toList();
        }
        if (q.isNotEmpty) {
          filtered = filtered.where((info) {
            final f = info.forfeited;
            return f.srNumber.toLowerCase().contains(q) ||
                f.consigneeName.toLowerCase().contains(q) ||
                unsoldItemName(f).toLowerCase().contains(q) ||
                (f.packageDetails?.caseNumber ?? '').toLowerCase().contains(q);
          }).toList();
        }
        return filtered;
      },
    );

    final maxPage = rows.isEmpty ? 0 : (rows.length - 1) ~/ _pageSize;
    final page = ref.watch(_unsoldPageProvider(tabKey)).clamp(0, maxPage);
    final pageRows = rows.skip(page * _pageSize).take(_pageSize).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Same header shape as the Sold Packages tab: title, then search and
          // the yard filter pushed to the right.
          Row(
            children: [
              // Flexible, not a bare Text + Spacer: the search box and the yard
              // filter have fixed widths, so on a narrow window the title had
              // nowhere to give and the Row overflowed (47px at 752px wide).
              // Now the title ellipsises and the controls stay reachable.
              // Expanded (not Text + Spacer) absorbs the leftover width AND
              // gives it back when there isn't enough: the search box is a
              // fixed 300 and the yard filter a fixed 220, so a bare Text had
              // nowhere to shrink and the Row overflowed by 47px at 752 wide.
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Gap(12),
              DisposalSearch(
                tabKey: tabKey,
                hint: 'Search SR / item / consignee...',
              ),
              const Gap(12),
              YardAllFilter(
                value: yardFilter,
                onChanged: (v) {
                  ref.read(disposalYardFilterProvider(tabKey).notifier).state =
                      v;
                  ref.read(_unsoldPageProvider(tabKey).notifier).state = 0;
                },
              ),
            ],
          ).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          // Count pill, same as the Sold Packages tab.
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: StatChip(
                label:
                    '$countNoun in ${yardFilter == null ? 'all yards' : yardName(yardFilter)}',
                value: '${rows.length}',
                color: amber),
          ),
          Expanded(
            child: rows.isEmpty
                ? _listCard(
                    context,
                    const EmptyTableState(
                      icon: Icons.refresh_rounded,
                      message: 'No unresolved unsold packages',
                      subtitle:
                          'Packages that remain unsold after re-opening will appear here.',
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: _listCard(
                          context,
                          DataTable2(
                            columnSpacing: 12,
                            horizontalMargin: 16,
                            fixedTopRows: 1,
                            minWidth: kUnsoldTableMinWidth,
                            headingRowColor: _headingColor(context),
                            // An outcome tab already filters to one outcome,
                            // so a Final Outcome column would repeat the tab
                            // title on every row; it shows the date instead.
                            columns: proposalFilter == null
                                ? kUnsoldColumns
                                : kUnsoldDecidedColumns,
                            rows: pageRows.map((info) {
                              final f = info.forfeited;
                              final pkg = f.packageDetails;
                              final qty = unsoldQty(f);
                              return DataRow(
                                cells: unsoldCells(
                                  context,
                                  info: info,
                                  srColor: blue,
                                  // The SUBMITTED figure: what the package
                                  // was actually tendered at.
                                  committeeUnitValue:
                                      committees[f.id]?.submittedValue,
                                  // READ-ONLY: the DG decides the outcome,
                                  // this directorate carries it out.
                                  outcome: proposalFilter == null
                                      ? Center(
                                          child: UnsoldOutcomeChip(
                                              proposal: proposals[f.id]),
                                        )
                                      : unsoldDecidedOnCell(
                                          context, proposals[f.id]),
                                  onDetails: pkg == null
                                      ? null
                                      : () => showDialog(
                                            context: context,
                                            builder: (_) =>
                                                PackageDetailsDialog(
                                              package: pkg,
                                              storageRate: storageRate,
                                              // Green: this portal's accent.
                                              // Every other Central Disposal
                                              // popup uses it; only this tab
                                              // was passing blue.
                                              headerAccentColor:
                                                  context.colors.successGreen,
                                              useLegacySummary: true,
                                              highlightItemId: f.itemId,
                                              yardLabel: yardName(f.yard),
                                              valuationUnitCost:
                                                  f.valuationCost,
                                              valuationTotalCost:
                                                  f.valuationCost != null
                                                      ? f.valuationCost! * qty
                                                      : null,
                                              valuationQty: qty,
                                              tenderHistoryFor: f,
                                              // Sealed while the newest round
                                              // is still open.
                                              valuationSealedUntilSale:
                                                  info.latestSale?.saleEnded ==
                                                      false,
                                            ),
                                          ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      TablePager(
                        total: rows.length,
                        page: page,
                        pageSize: _pageSize,
                        onPageChanged: (p) => ref
                            .read(_unsoldPageProvider(tabKey).notifier)
                            .state = p,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _YardFilter extends ConsumerWidget {
  const _YardFilter();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedYard = ref.watch(disposalSelectedYardProvider);
    // A physical-yard picker, not a filter -- "create this sale AT yard X" --
    // so it lists bare yards, never split by directorate.
    final yards = ref.watch(yardsProvider).valueOrNull?.where((y) => y.isActive) ??
        kYards.map((y) => YardModel(code: y.code, name: y.name, srPrefix: y.srPrefix));
    return _StyledYardPicker(
      value: selectedYard,
      yards: yards.toList(),
      onChanged: (v) => ref.read(disposalSelectedYardProvider.notifier).state =
          v ?? kYards.first.code,
    );
  }
}

/// A single-yard picker styled exactly like the page header's Yard dropdown
/// (gold fill, rounded border, styled options menu). Reused by the header
/// filter AND the Tender / Destruction forms so they share one look.
class _StyledYardPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;
  final double width;

  /// Bare physical yards -- this picker always selects ONE yard to act as,
  /// never a directorate-split filter entry. Defaults to the const seed for
  /// callers that have not been updated to pass the live list.
  final List<YardModel> yards;
  _StyledYardPicker({
    required this.value,
    required this.onChanged,
    this.width = 240,
    List<YardModel>? yards,
  }) : yards = yards ??
            [for (final y in kYards) YardModel(code: y.code, name: y.name, srPrefix: y.srPrefix)];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                filled: true,
                fillColor: context.colors.primaryGold.withOpacity(0.06),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: context.colors.primaryGold.withOpacity(0.4))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: context.colors.primaryGold.withOpacity(0.4))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                        color: context.colors.primaryGold, width: 1.5)),
              ),
        ),
        child: StyledDropdownFormField<String>(
          value: value,
          label: 'Yard',
          helperText: null,
          isDense: true,
          menuWidth: width,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon: Icon(Icons.warehouse_rounded,
              color: context.colors.primaryGold, size: 20),
          options: [
            for (final y in yards) StyledDropdownOption(y.code, y.name),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

Widget _listCard(BuildContext context, Widget child) {
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.colors.cardDark,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: context.colors.borderColor),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: child,
    ),
  ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.06);
}

WidgetStateProperty<Color?> _headingColor(BuildContext context) =>
    WidgetStateProperty.all(context.colors.surfaceDark);

// ── Sold Packages (cross-yard, yard dropdown) ─────────────────────

bool _isSoldEntry(WarehouseEntryModel e) {
  final notes = (e.returnNotes ?? '').trim().toUpperCase();
  final m = RegExp(r'^\[([^\]]+)\]').firstMatch(notes);
  if (m == null) return false;
  final tag = m.group(1)!.trim();
  return tag == 'FINAL:SOLD' || tag == 'SOLD';
}

/// Format a [TimeOfDay] as a locale-independent 24-hour "HH:mm" string for the
/// DB. (TimeOfDay.format() yields a localized 12-hour string like "3:30 PM"
/// which the sale-time parser cannot read, leaving Mark Sold always unlocked.)
String _timeOfDayToHHmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The reason shown in the disposal tables' "Reason" column. The column is
/// generic (not "Forfeit Reason") because an item's origin may be Forfeit,
/// Abandoned or Other — the Source chip already conveys which. Prefers
/// the item's own SR-form hold reasons (the clean text the officer entered,
/// e.g. "No phytosanitary certificate"); falls back to the forfeited package's
/// stored reason. Strips any synthetic "Held — " / "Held: " prefix that older
/// disposition records prepended, so the table mirrors the SR form exactly.
String _forfeitReasonText(PackageItem? item, ForfeitedPackageModel? f) {
  String clean(String s) {
    var t = s.trim();
    // Remove a leading "Held" marker followed by a dash/colon separator.
    final m = RegExp(r'^held\s*[—–:-]\s*', caseSensitive: false).firstMatch(t);
    if (m != null) t = t.substring(m.end).trim();
    return t;
  }

  final itemReasons = item?.reasons?.trim();
  if (itemReasons != null && itemReasons.isNotEmpty) return clean(itemReasons);
  final fpReason = f?.reason.trim() ?? '';
  return clean(fpReason);
}

/// The warehouse · zone an item currently sits in (latest entry for the item,
/// or the package's latest entry). Used by the Unsold / Undestroyed tables'
/// "Location" column.
String _warehouseLocation(PackageModel? pkg, String? itemId) {
  if (pkg == null) return '—';
  var entries = itemId != null
      ? pkg.warehouseEntries.where((e) => e.packageItemId == itemId).toList()
      : <WarehouseEntryModel>[];
  if (entries.isEmpty) entries = [...pkg.warehouseEntries];
  if (entries.isEmpty) return '—';
  entries.sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
  final w = entries.first;
  return w.zone != null && w.zone!.isNotEmpty
      ? '${w.warehouseName} · ${w.zone}'
      : w.warehouseName;
}

/// A live countdown chip to a [deadline] — shown on the Tender / Destruction
/// cards. Ticks every second; reads "Xd Yh", "Yh Zm", or "Zm Ws" as it nears 0.
/// Once the deadline passes it shows "Window closed" (the package then drops to
/// the Unsold / Undestroyed pool on the next refresh).
class _DeadlineCountdown extends StatefulWidget {
  final DateTime? deadline;
  final String label; // e.g. 'Sell within' / 'Destroy within'
  const _DeadlineCountdown({required this.deadline, required this.label});
  @override
  State<_DeadlineCountdown> createState() => _DeadlineCountdownState();
}

class _DeadlineCountdownState extends State<_DeadlineCountdown> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes >= 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final dl = widget.deadline;
    if (dl == null) return const SizedBox.shrink();
    final remaining = dl.difference(DateTime.now());
    final closed = remaining.isNegative;
    final color = closed
        ? context.colors.dangerRed
        : remaining.inHours < 6
            ? context.colors.warningAmber
            : context.colors.successGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(closed ? Icons.timer_off_rounded : Icons.timer_rounded,
            size: 13, color: color),
        const Gap(5),
        Text(
          closed ? 'Window closed' : '${widget.label} ${_fmt(remaining)}',
          style: TextStyle(
              color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }
}

/// A small status chip (icon + label) used in the disposal tables' Status
/// column — e.g. read-only "Pending".
Widget _statusChipWidget(
    BuildContext context, String label, IconData icon, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const Gap(5),
      Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    ]),
  );
}

/// A small coloured chip for a forfeited package's source — Forfeit / Abandoned
/// / Other — used in the disposal tables' "Source" column.
Widget _sourceChip(BuildContext context, String? source) {
  final s = (source ?? '').trim().toLowerCase();
  final (label, color) = switch (s) {
    'abandoned' => ('Abandoned', context.colors.heldOrange),
    'other' => ('Other', context.colors.warningAmber),
    'forfeit' || 'forfeited' || 'forfiet' => (
        'Forfeit',
        context.colors.accentBlue
      ),
    _ => (
        source == null || source.isEmpty ? '—' : source,
        context.colors.textMuted
      ),
  };
  if (label == '—') {
    return Text('—', style: TextStyle(color: context.colors.textMuted));
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(label,
        overflow: TextOverflow.ellipsis,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

class _SoldRow {
  final PackageModel package;
  final WarehouseEntryModel entry;
  final String itemName;
  final String officer;
  const _SoldRow(this.package, this.entry, this.itemName, this.officer);

  /// The receipt number this specific [FINAL:SOLD] entry recorded — parsed from
  /// its "[FINAL:SOLD] — Receipt: <no>" note. Disambiguates which of an item's
  /// several partial-sale TSI rows (same package_item_id) this row maps to.
  String get receiptNo {
    final notes = entry.returnNotes ?? '';
    final m =
        RegExp(r'Receipt:\s*([^\|—]+)', caseSensitive: false).firstMatch(notes);
    return m == null ? '' : m.group(1)!.trim();
  }

  /// Key for saleItemForPackageItemProvider:
  /// "packageId|packageItemId|receiptNo" — the receipt pins the exact TSI row
  /// (price/taxes) for this partial sale.
  String get saleItemKey =>
      '${package.id}|${entry.packageItemId ?? ''}|$receiptNo';
}

/// Sold-tab delivery sub-filter: null = all, true = delivered, false = pending.
final _soldDeliveryFilterProvider = StateProvider<bool?>((ref) => null);

class _SoldPackagesTab extends ConsumerStatefulWidget {
  const _SoldPackagesTab();
  @override
  ConsumerState<_SoldPackagesTab> createState() => _SoldPackagesTabState();
}

class _SoldPackagesTabState extends ConsumerState<_SoldPackagesTab> {
  static const int _pageSize = 20;
  int _page = 0;

  List<_SoldRow> _rows(List<PackageModel> packages) {
    final rows = <_SoldRow>[];
    for (final p in packages) {
      for (final e in p.warehouseEntries) {
        if (!_isSoldEntry(e)) continue;
        final item = p.items.where((i) => i.id == e.packageItemId).firstOrNull;
        // Resolve the item name from the entry's own package_item_id. NEVER fall
        // back to items.first for a multi-item package — that mislabels an
        // un-linked (legacy NULL-item) entry as the wrong product (the old
        // "Palm Oil" bug). Only a single-item package can safely use its sole
        // item's name.
        final itemName = item?.itemName ??
            (p.items.length == 1 ? p.items.first.itemName : '—');
        rows.add(_SoldRow(
          p,
          e,
          itemName,
          e.returnedByName ?? e.returnedByBadge ?? '—',
        ));
      }
    }
    rows.sort((a, b) => (b.entry.returnedAt ?? b.entry.admittedAt)
        .compareTo(a.entry.returnedAt ?? a.entry.admittedAt));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final green = context.colors.successGreen;
    final yardFilter = ref.watch(disposalSoldYardFilterProvider);
    final sold = ref.watch(disposalSoldPackagesProvider);
    final deliveryFilter = ref.watch(_soldDeliveryFilterProvider);
    final deliveredMap =
        ref.watch(packageDeliveredMapProvider).valueOrNull ?? const {};
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final yardLabel = yardFilter == null ? 'all yards' : yardName(yardFilter);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Sold Goods',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const DisposalSearch(
                tabKey: 'sold', hint: 'Search SR / item / sold by…'),
            const Gap(12),
            YardAllFilter(
              value: yardFilter,
              onChanged: (v) {
                ref.read(disposalSoldYardFilterProvider.notifier).state = v;
                setState(() => _page = 0);
              },
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(12),
          // Delivered / Pending segmented filter.
          _DeliverySegmentedFilter(
            value: deliveryFilter,
            onChanged: (v) {
              ref.read(_soldDeliveryFilterProvider.notifier).state = v;
              setState(() => _page = 0);
            },
          ),
          const Gap(14),
          Expanded(
            child: sold.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(disposalSoldPackagesProvider)),
              data: (packages) {
                final q =
                    ref.watch(disposalSearchProvider('sold')).toLowerCase();
                var rows = _rows(packages);
                if (q.isNotEmpty) {
                  rows = rows
                      .where((r) =>
                          r.package.srNumber.toLowerCase().contains(q) ||
                          r.itemName.toLowerCase().contains(q) ||
                          r.officer.toLowerCase().contains(q))
                      .toList();
                }
                if (deliveryFilter != null) {
                  rows = rows
                      .where((r) =>
                          (deliveredMap[r.saleItemKey] ??
                              deliveredMap[r.package.id] ??
                              false) ==
                          deliveryFilter)
                      .toList();
                }
                final total = rows.length;
                if (_page * _pageSize >= total && _page > 0) _page = 0;
                final pageRows = pageSlice(rows, _page, _pageSize);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: StatChip(
                          label: 'Sold in $yardLabel',
                          value: '$total',
                          color: green),
                    ),
                    Expanded(
                      child: _listCard(
                        context,
                        DataTable2(
                          columnSpacing: 12,
                          horizontalMargin: 16,
                          fixedTopRows: 1,
                          empty: EmptyTableState(
                              message: 'No sold packages in $yardLabel'),
                          headingRowColor: _headingColor(context),
                          columns: const [
                            DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Goods Name'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 60),
                            DataColumn2(
                                label: Text('Sold Date'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Receipt No'), size: ColumnSize.S),
                            DataColumn2(
                                label: Text('Valuation'),
                                size: ColumnSize.S,
                                fixedWidth: 132),
                            DataColumn2(
                                label: Text('Sold Price'), size: ColumnSize.M),
                            DataColumn2(
                                label: Center(child: Text('Delivery')),
                                fixedWidth: 120),
                            DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                          ],
                          rows: pageRows
                              .map((r) => DataRow(cells: [
                                    DataCell(TooltipText(r.package.srNumber,
                                        style: TextStyle(
                                            color:
                                                context.colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(TooltipText(r.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(
                                        TooltipText('${r.entry.itemCount}')),
                                    DataCell(TooltipText(
                                        r.entry.returnedAt != null
                                            ? DateFormat('yyyy-MM-dd')
                                                .format(r.entry.returnedAt!)
                                            : '—')),
                                    DataCell(_SaleReceiptCell(
                                        saleItemKey: r.saleItemKey)),
                                    DataCell(_SaleValuationCell(
                                        saleItemKey: r.saleItemKey,
                                        qty: r.entry.itemCount)),
                                    DataCell(_SaleFinancialsCell(
                                        saleItemKey: r.saleItemKey)),
                                    DataCell(Center(
                                        child: _DeliveryStatusCell(
                                            package: r.package,
                                            saleItemKey: r.saleItemKey))),
                                    DataCell(Center(
                                      child: IconButton(
                                        icon: Icon(Icons.info_outline_rounded,
                                            color:
                                                context.colors.accentLightBlue,
                                            size: 18),
                                        onPressed: () => showDialog(
                                          context: context,
                                          builder: (_) => PackageDetailsDialog(
                                            package: r.package,
                                            storageRate: storageRate,
                                            headerAccentColor:
                                                context.colors.successGreen,
                                            highlightEntry: r.entry,
                                            useLegacySummary: true,
                                            isSoldPage: true,
                                            // Same qty the table's Valuation
                                            // cell multiplies by, so the popup
                                            // cannot disagree with the row.
                                            valuationQty: r.entry.itemCount,
                                          ),
                                        ),
                                      ),
                                    )),
                                  ]))
                              .toList(),
                        ),
                      ),
                    ),
                    TablePager(
                      total: total,
                      page: _page,
                      pageSize: _pageSize,
                      onPageChanged: (p) => setState(() => _page = p),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact "All · Delivered · Pending" segmented filter for the Sold tab.
class _DeliverySegmentedFilter extends StatelessWidget {
  final bool? value; // null = all
  final ValueChanged<bool?> onChanged;
  /// Label for the `true` state -- "Delivered" on Sold, "Destroyed" on
  /// Destroyed Goods, since a destruction has no delivery concept.
  final String trueLabel;
  const _DeliverySegmentedFilter(
      {required this.value, required this.onChanged, this.trueLabel = 'Delivered'});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool? v, IconData icon) {
      final selected = value == v;
      final color = context.colors.primaryGold;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? color.withOpacity(0.6)
                    : context.colors.borderColor),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 15,
                color: selected ? color : context.colors.textSecondary),
            const Gap(6),
            Text(label,
                style: TextStyle(
                    color: selected ? color : context.colors.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      );
    }

    return Row(children: [
      seg('All', null, Icons.all_inbox_rounded),
      const Gap(8),
      seg(trueLabel, true, Icons.check_circle_rounded),
      const Gap(8),
      seg('Pending', false, Icons.schedule_rounded),
    ]);
  }
}

// ── Destroyed Packages (cross-yard, yard dropdown) ────────────────
// Mirrors the Sold Packages tab. A yard/Central marking a package destroyed
// writes a "[FINAL:DESTROYED]" warehouse entry (see disposal_mark_destruction_
// item_destroyed), which this tab surfaces — auto-updating via realtime.

bool _isDestroyedEntry(WarehouseEntryModel e) {
  final notes = (e.returnNotes ?? '').trim().toUpperCase();
  final m = RegExp(r'^\[([^\]]+)\]').firstMatch(notes);
  if (m == null) return false;
  final tag = m.group(1)!.trim();
  // 'FINAL:DESTROY' (no ED) is the PENDING tag disposeWarehouseItem writes.
  // It belongs on this tab too -- the row shows a Pending status until the
  // yard confirms the destruction, which rewrites it as FINAL:DESTROYED.
  return tag == 'FINAL:DESTROYED' ||
      tag == 'FINAL:DESTROY' ||
      tag == 'DESTROYED' ||
      tag == 'DESTROY';
}

class _DestroyedPackagesTab extends ConsumerStatefulWidget {
  const _DestroyedPackagesTab();
  @override
  ConsumerState<_DestroyedPackagesTab> createState() =>
      _DestroyedPackagesTabState();
}

class _DestroyedRow {
  final PackageModel package;
  final WarehouseEntryModel? entry;
  final PackageItem? item;
  final String itemName;
  final String officer;
  final bool isDestroyed;

  _DestroyedRow({
    required this.package,
    this.entry,
    this.item,
    required this.itemName,
    required this.officer,
    required this.isDestroyed,
  });
}

class _DestroyedPackagesTabState extends ConsumerState<_DestroyedPackagesTab> {
  static const int _pageSize = 20;
  int _page = 0;

  List<_DestroyedRow> _rows(List<PackageModel> packages) {
    final rows = <_DestroyedRow>[];
    for (final p in packages) {
      final coveredItemIds = <String>{};
      for (final e in p.warehouseEntries) {
        if (!_isDestroyedEntry(e)) continue;
        final item = p.items.where((i) => i.id == e.packageItemId).firstOrNull;
        if (e.packageItemId != null) coveredItemIds.add(e.packageItemId!);
        final itemName = item?.itemName ??
            (p.items.length == 1 ? p.items.first.itemName : '—');
        final isDest = (e.returnNotes ?? '')
                .toUpperCase()
                .contains('FINAL:DESTROYED') ||
            (e.returnNotes ?? '').toUpperCase().contains('DESTROYED');
        rows.add(_DestroyedRow(
          package: p,
          entry: e,
          item: item,
          itemName: itemName,
          officer: e.returnedByName ?? e.returnedByBadge ?? '—',
          isDestroyed: isDest,
        ));
      }
      for (final item in p.items) {
        if (coveredItemIds.contains(item.id)) continue;
        final st = (item.status ?? '').toLowerCase();
        if (st == 'destroyed' ||
            st == 'supposed to be destroyed' ||
            st == 'destroy') {
          rows.add(_DestroyedRow(
            package: p,
            entry: null,
            item: item,
            itemName: item.itemName,
            officer: '—',
            isDestroyed: st == 'destroyed',
          ));
        }
      }
    }
    rows.sort((a, b) {
      final aDate =
          a.entry?.returnedAt ?? a.entry?.admittedAt ?? a.package.updatedAt;
      final bDate =
          b.entry?.returnedAt ?? b.entry?.admittedAt ?? b.package.updatedAt;
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    // Central Disposal's accent is green — keep the Destroyed tab on-brand
    // (loading spinner, stat chip, popup header) rather than danger-red.
    final green = context.colors.successGreen;
    final yardFilter = ref.watch(disposalDestroyedYardFilterProvider);
    final destroyed = ref.watch(disposalDestroyedPackagesProvider);
    final deliveryFilter = ref.watch(_destroyedDeliveryFilterProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final yardLabel = yardFilter == null ? 'all yards' : yardName(yardFilter);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Destroyed Goods',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const DisposalSearch(
                tabKey: 'destroyed', hint: 'Search SR / item / by…'),
            const Gap(12),
            YardAllFilter(
              value: yardFilter,
              onChanged: (v) {
                ref.read(disposalDestroyedYardFilterProvider.notifier).state =
                    v;
                setState(() => _page = 0);
              },
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(12),
          _DeliverySegmentedFilter(
            value: deliveryFilter,
            trueLabel: 'Destroyed',
            onChanged: (v) {
              ref.read(_destroyedDeliveryFilterProvider.notifier).state = v;
              setState(() => _page = 0);
            },
          ),
          const Gap(14),
          Expanded(
            child: destroyed.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () =>
                      ref.refresh(disposalDestroyedPackagesProvider)),
              data: (packages) {
                final q = ref
                    .watch(disposalSearchProvider('destroyed'))
                    .toLowerCase();
                var rows = _rows(packages);
                if (q.isNotEmpty) {
                  rows = rows
                      .where((r) =>
                          r.package.srNumber.toLowerCase().contains(q) ||
                          r.itemName.toLowerCase().contains(q) ||
                          r.officer.toLowerCase().contains(q))
                      .toList();
                }
                if (deliveryFilter != null) {
                  rows = rows
                      .where((r) => r.isDestroyed == deliveryFilter)
                      .toList();
                }
                final total = rows.length;
                if (_page * _pageSize >= total && _page > 0) _page = 0;
                final pageRows = pageSlice(rows, _page, _pageSize);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: StatChip(
                          label: 'Destroyed in $yardLabel',
                          value: '$total',
                          color: green),
                    ),
                    Expanded(
                      child: _listCard(
                        context,
                        DataTable2(
                          columnSpacing: 12,
                          horizontalMargin: 16,
                          fixedTopRows: 1,
                          empty: EmptyTableState(
                              message: 'No destroyed packages in $yardLabel'),
                          headingRowColor: _headingColor(context),
                          columns: const [
                            DataColumn2(
                                label: Text('SR Number'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Goods Name'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 60),
                            DataColumn2(
                                label: Text('Date'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Destruction Expenses'),
                                size: ColumnSize.M),
                            // The record/edit action gets its own column rather
                            // than riding inside the money cell, so the figure
                            // reads cleanly and the button sits under a header
                            // that says what it does.
                            DataColumn2(
                                label: Center(child: Text('Costs')),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                            DataColumn2(
                                label: Center(child: Text('Status')),
                                fixedWidth: kDestructionStatusColumnWidth),
                            DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 60),
                          ],
                          rows: pageRows
                              .map((r) => DataRow(cells: [
                                    DataCell(TooltipText(r.package.srNumber,
                                        style: TextStyle(
                                            color:
                                                context.colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(TooltipText(r.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(TooltipText(
                                        '${r.entry?.itemCount ?? r.item?.quantity ?? 0}')),
                                    DataCell(TooltipText(r.entry?.returnedAt !=
                                            null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(r.entry!.returnedAt!)
                                        : (r.entry?.admittedAt != null
                                            ? DateFormat('yyyy-MM-dd')
                                                .format(r.entry!.admittedAt!)
                                            : DateFormat('yyyy-MM-dd')
                                                .format(r.package.updatedAt)))),
                                    DataCell(DestructionExpenseCell(
                                        srNumber: r.package.srNumber)),
                                    DataCell(Center(
                                        child: _RecordCostsButton(
                                            srNumber: r.package.srNumber))),
                                    DataCell(Center(
                                      // Read-only here: only the yard confirms
                                      // a destruction, so no onMark.
                                      child: DestructionStatusPill(
                                          destroyed: r.isDestroyed),
                                    )),
                                    DataCell(Center(
                                      child: IconButton(
                                        icon: Icon(Icons.info_outline_rounded,
                                            color:
                                                context.colors.accentLightBlue,
                                            size: 18),
                                        onPressed: () => showDialog(
                                          context: context,
                                          builder: (_) => PackageDetailsDialog(
                                            package: r.package,
                                            storageRate: storageRate,
                                            headerAccentColor: green,
                                            highlightEntry: r.entry,
                                            useLegacySummary: true,
                                            // Same lookup the "Destruction
                                            // Expenses" column beside this
                                            // uses -- without it the popup
                                            // showed "not available" while the
                                            // table it opened from showed a
                                            // real figure.
                                            srFinancials: ref
                                                .watch(srFinancialsProvider)
                                                .valueOrNull
                                                ?.where((f) =>
                                                    f.srNumber.trim() ==
                                                    r.package.srNumber.trim())
                                                .firstOrNull,
                                          ),
                                        ),
                                      ),
                                    )),
                                  ]))
                              .toList(),
                        ),
                      ),
                    ),
                    TablePager(
                      total: total,
                      page: _page,
                      pageSize: _pageSize,
                      onPageChanged: (p) => setState(() => _page = p),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Destroyed-tab delivery sub-filter: null = all, true = delivered, false = pending.
final _destroyedDeliveryFilterProvider = StateProvider<bool?>((ref) => null);

/// The record/edit-costs action for one SR's destruction, in its own column.
///
/// Opens the same cost form the Expenses tab uses, in its destruction shape:
/// what is saved here is the SAME `financial_expenses` data that tab reads, so
/// a figure entered on either screen shows on the other.
class _RecordCostsButton extends ConsumerWidget {
  final String srNumber;
  const _RecordCostsButton({required this.srNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sr = ref
        .watch(srFinancialsProvider)
        .valueOrNull
        ?.where((f) => f.srNumber.trim() == srNumber.trim())
        .firstOrNull;
    return IconButton(
      tooltip: 'Record / edit destruction costs',
      icon: Icon(Icons.edit_note_rounded,
          size: 20, color: context.colors.successGreen),
      onPressed: sr == null
          ? null
          : () => showDialog(
                context: context,
                builder: (_) =>
                    RecordExpenseDialog(sr: sr, forDestruction: true),
              ),
    );
  }
}

/// Parse the receipt from a "[FINAL:DESTROYED] — Receipt/Notes: <no>" note.
String? _parseDestroyReceipt(String? returnNotes) {
  if (returnNotes == null) return null;
  var s = returnNotes;
  final tag =
      RegExp(r'Receipt/Notes:\s*(.+)$', caseSensitive: false).firstMatch(s);
  if (tag != null) s = tag.group(1)!;
  // Peel an inner "Receipt No:" prefix and drop any "| Notes:" tail → just the no.
  s = s.replaceFirst(RegExp(r'^\s*Receipt No:\s*', caseSensitive: false), '');
  s = s.split(RegExp(r'\|?\s*Notes:', caseSensitive: false)).first.trim();
  return s.isEmpty ? null : s;
}

/// The Valuation Directorate's valuation (unit × qty) for a destroyed item.
class _DestructionValuationCell extends ConsumerWidget {
  final PackageModel package;
  final String? packageItemId;

  /// The quantity shown in the row's Qty column — the valuation must multiply
  /// by exactly this so "@ unit × qty" stays consistent with what the row shows.
  final int? qty;
  const _DestructionValuationCell(
      {required this.package, this.packageItemId, this.qty});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '${package.id}|${packageItemId ?? ''}';
    final async = ref.watch(destructionItemForPackageItemProvider(key));
    return async.when(
      // Keep the previous value while re-fetching: without this every
      // realtime event drops every row's cell to a spinner and back,
      // which reads as the whole table constantly refreshing.
      skipLoadingOnReload: true,
      loading: () => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) =>
          Text('—', style: TextStyle(color: context.colors.textMuted)),
      data: (item) {
        final fp = item?.forfeited;
        final unitCost = fp?.valuationCost;
        if (unitCost == null || fp == null) {
          return Text('—', style: TextStyle(color: context.colors.textMuted));
        }
        final int effQty;
        if (qty != null && qty! > 0) {
          effQty = qty!;
        } else if (fp.entryQty != null) {
          effQty = fp.entryQty!;
        } else if (fp.itemId != null) {
          effQty = fp.packageDetails?.items
                  .where((i) => i.id == fp.itemId)
                  .firstOrNull
                  ?.quantity ??
              1;
        } else {
          effQty =
              fp.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ??
                  1;
        }
        final total = unitCost * effQty;
        final fmt = NumberFormat('#,##0');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Rs ${fmt.format(total)}',
                style: TextStyle(
                    color: context.colors.primaryGold,
                    fontWeight: FontWeight.w700)),
            Text('@ ${fmt.format(unitCost)} × $effQty',
                style:
                    TextStyle(fontSize: 11, color: context.colors.textMuted)),
          ],
        );
      },
    );
  }
}

/// The actual destruction price recorded when the item was destroyed (no taxes).
class _DestructionPriceCell extends ConsumerWidget {
  final PackageModel package;
  final String? packageItemId;
  const _DestructionPriceCell({required this.package, this.packageItemId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '${package.id}|${packageItemId ?? ''}';
    final async = ref.watch(destructionItemForPackageItemProvider(key));
    return async.when(
      // Keep the previous value while re-fetching: without this every
      // realtime event drops every row's cell to a spinner and back,
      // which reads as the whole table constantly refreshing.
      skipLoadingOnReload: true,
      loading: () => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        if (item == null) return const Text('—');
        return Text('Rs ${item.destroyedPrice.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold));
      },
    );
  }
}

// Read-only sold price + tax total (watches the per-item provider so each sold
// row shows its own price when a package has multiple separately-priced items).
// Receipt number for a sold package item (watches the same per-item provider
// as the financials cell so it matches the specific sold row).
class _SaleReceiptCell extends ConsumerWidget {
  final String saleItemKey;
  const _SaleReceiptCell({required this.saleItemKey});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saleItemForPackageItemProvider(saleItemKey));
    return async.when(
      // Keep the previous value while re-fetching: without this every
      // realtime event drops every row's cell to a spinner and back,
      // which reads as the whole table constantly refreshing.
      skipLoadingOnReload: true,
      loading: () => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        final receipt = item?.receiptNumber?.trim();
        return Text(
          (receipt != null && receipt.isNotEmpty) ? receipt : '—',
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

// The Valuation Directorate's valuation (unit × qty) for a sold item — shown
// next to the actual Sold Price so both can be compared.
class _SaleValuationCell extends ConsumerWidget {
  final String saleItemKey;
  // The quantity actually sold (the table's Qty column). Valuation = unit × this
  // — otherwise it wrongly falls back to the forfeited item's registered qty
  // (often 1), showing e.g. "@120 × 1" for a row whose Qty is 5.
  final int? qty;
  const _SaleValuationCell({required this.saleItemKey, this.qty});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saleItemForPackageItemProvider(saleItemKey));
    return async.when(
      // Keep the previous value while re-fetching: without this every
      // realtime event drops every row's cell to a spinner and back,
      // which reads as the whole table constantly refreshing.
      skipLoadingOnReload: true,
      loading: () => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        final fp = item?.forfeited;
        if (fp == null) {
          return Text('—', style: TextStyle(color: context.colors.textMuted));
        }
        // Prefer the LATEST tender re-valuation for this package, if any.
        final revals =
            ref.watch(tenderRevaluationsProvider(fp.id)).asData?.value ??
                const <String, TenderRevaluationModel>{};
        final reval = _latestReval(revals);
        final isRevalued = reval != null;
        final unitCost = reval?.valuationCost ?? fp.valuationCost;
        if (unitCost == null) {
          return Text('—', style: TextStyle(color: context.colors.textMuted));
        }
        final int effQty;
        if (qty != null && qty! > 0) {
          effQty = qty!; // the sold qty from the table (source of truth)
        } else if (fp.entryQty != null) {
          effQty = fp.entryQty!;
        } else if (fp.itemId != null) {
          effQty = fp.packageDetails?.items
                  .where((i) => i.id == fp.itemId)
                  .firstOrNull
                  ?.quantity ??
              1;
        } else {
          effQty =
              fp.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ??
                  1;
        }
        final total = unitCost * effQty;
        final fmt = NumberFormat('#,##0');
        final priceColor = isRevalued
            ? context.colors.accentLightBlue
            : context.colors.primaryGold;
        // mainAxisSize.min + a single-line, ellipsised sub-label: without both,
        // the "· re-valued" suffix wraps onto a second line and overflows the
        // DataRow by ~1px ("BOTTOM OVERFLOWED BY 1.00 PIXELS").
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Rs ${fmt.format(total)}',
                  style: TextStyle(
                      color: priceColor, fontWeight: FontWeight.w700)),
              if (isRevalued) ...[
                const Gap(5),
                Icon(Icons.price_change_rounded,
                    size: 12, color: context.colors.accentLightBlue),
              ],
            ]),
            Text(
                '@ ${fmt.format(unitCost)} × $effQty${isRevalued ? ' · re-valued' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 11, color: context.colors.textMuted)),
          ],
        );
      },
    );
  }
}

class _SaleFinancialsCell extends ConsumerWidget {
  final String saleItemKey;
  const _SaleFinancialsCell({required this.saleItemKey});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saleItemForPackageItemProvider(saleItemKey));
    return async.when(
      // Keep the previous value while re-fetching: without this every
      // realtime event drops every row's cell to a spinner and back,
      // which reads as the whole table constantly refreshing.
      skipLoadingOnReload: true,
      loading: () => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        if (item == null) return const Text('—');
        double taxSum = 0;
        for (final t in item.appliedTaxes) {
          taxSum += parseDbNum(t['amount']) ?? 0;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Rs ${item.soldPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Tax: Rs ${taxSum.toStringAsFixed(2)}',
                style:
                    TextStyle(fontSize: 11, color: context.colors.textMuted)),
          ],
        );
      },
    );
  }
}

// Read-only delivery STATUS chip (the action button lives in the details
// dialog, enabled for yards only). Watches the per-item provider so delivery
// state matches the specific sold row.
class _DeliveryStatusCell extends ConsumerWidget {
  final PackageModel package;
  final String saleItemKey;
  const _DeliveryStatusCell({required this.package, required this.saleItemKey});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saleItemForPackageItemProvider(saleItemKey));
    return async.when(
      // Keep the previous value while re-fetching: without this every
      // realtime event drops every row's cell to a spinner and back,
      // which reads as the whole table constantly refreshing.
      skipLoadingOnReload: true,
      loading: () => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) => item == null
          ? const Text('—')
          : DeliveryStatusChip(delivered: item.isDelivered),
    );
  }
}

/// Small read-only Delivered/Pending chip shared by the Sold tables.
class DeliveryStatusChip extends StatelessWidget {
  final bool delivered;
  const DeliveryStatusChip({super.key, required this.delivered});
  @override
  Widget build(BuildContext context) {
    final color =
        delivered ? context.colors.successGreen : context.colors.warningAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(delivered ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 13, color: color),
        const Gap(5),
        Text(delivered ? 'Delivered' : 'Pending',
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ── Disposal Requests (per yard, per submission) ──────────────────
// null = all yards.
final _requestYardFilterProvider = StateProvider<String?>((ref) => null);

class _DisposalRequestsTab extends ConsumerWidget {
  const _DisposalRequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final requests = ref.watch(disposalRequestsProvider);
    final yardFilter = ref.watch(_requestYardFilterProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Disposal Requests',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const DisposalSearch(
                tabKey: 'requests', hint: 'Search SR / consignee…'),
            const Gap(12),
            YardAllFilter(
              value: yardFilter,
              onChanged: (v) =>
                  ref.read(_requestYardFilterProvider.notifier).state = v,
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),
          Expanded(
            child: requests.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(disposalRequestsProvider)),
              data: (list) {
                final q =
                    ref.watch(disposalSearchProvider('requests')).toLowerCase();
                var filtered = yardFilter == null
                    ? list
                    // Per item, not the request's own yard: a request filed
                    // at a multi-directorate yard can list items whose SR
                    // numbers carry different directorate prefixes.
                    : list
                        .where((r) => r.items.any((i) => matchesYardFilter(
                            yardFilter, r.yard, i.forfeited?.srNumber ?? '')))
                        .toList();
                if (q.isNotEmpty) {
                  filtered = filtered
                      .where((r) => r.items.any((i) =>
                          (i.forfeited?.srNumber ?? '')
                              .toLowerCase()
                              .contains(q) ||
                          (i.forfeited?.consigneeName ?? '')
                              .toLowerCase()
                              .contains(q)))
                      .toList();
                }
                if (filtered.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        icon: Icons.assignment_turned_in_outlined,
                        message: 'No disposal requests yet',
                        subtitle:
                            'Forwarded requests from the Valuation Directorate will appear here.'),
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, i) =>
                      _RequestCard(request: filtered[i]),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final DisposalRequestModel request;
  const _RequestCard({required this.request});

  String _itemName(DisposalRequestItemModel it) {
    final items = it.forfeited?.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    final itemId = it.forfeited?.itemId;
    if (itemId != null) {
      final match = items.where((i) => i.id == itemId).firstOrNull;
      if (match != null) return match.itemName;
    }
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final red = context.colors.dangerRed;
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final items = request.items;

    // Items already covered by a dedicated per-item request row (correct
    // partial qty) — keyed "<packageId>:<itemId>". A package-level row must not
    // re-expand these at the full registered qty (would duplicate the partials).
    final perItemKeys = <String>{};
    for (final it in items) {
      final iid = it.forfeited?.itemId;
      final pid = it.forfeited?.packageId;
      if (iid != null && pid != null) perItemKeys.add('$pid:$iid');
    }
    // Expand package-level FP rows (itemId==null, multiple pkg items) so each
    // item appears as its own table row.
    final expandedRows =
        <({DisposalRequestItemModel it, PackageItem? pkgItem})>[];
    for (final it in items) {
      final fpItems = it.forfeited?.packageDetails?.items ?? const [];
      final pid = it.forfeited?.packageId;
      if (it.forfeited?.itemId == null && fpItems.length > 1) {
        for (final pkgItem in fpItems) {
          if (pid != null && perItemKeys.contains('$pid:${pkgItem.id}')) {
            continue;
          }
          expandedRows.add((it: it, pkgItem: pkgItem));
        }
      } else {
        expandedRows.add((it: it, pkgItem: null));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: green.withOpacity(0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warehouse_rounded, size: 16, color: green),
                  const Gap(8),
                  Text(yardName(request.yard),
                      style: TextStyle(
                          color: green,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                ]),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 12, color: context.colors.textMuted),
                      const Gap(4),
                      Text(DateFormat('yyyy-MM-dd').format(request.requestDate),
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      if (request.createdByName != null) ...[
                        const Gap(12),
                        Icon(Icons.person_rounded,
                            size: 12, color: context.colors.textMuted),
                        const Gap(4),
                        Text(request.createdByName!,
                            style: TextStyle(
                                color: context.colors.textMuted, fontSize: 12)),
                      ],
                    ]),
                    const Gap(2),
                    Text(
                        '${expandedRows.length} package${expandedRows.length == 1 ? '' : 's'} requested',
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              _CountPill(
                  icon: Icons.delete_forever_rounded,
                  label: 'Destruction',
                  count: request.destructionCount,
                  color: red),
              const Gap(8),
              _CountPill(
                  icon: Icons.sell_rounded,
                  label: 'Sale',
                  count: request.saleCount,
                  color: green),
            ]),
          ),
          Divider(height: 1, color: context.colors.borderColor),
          // Items table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: (expandedRows.length * 48.0 + 52).clamp(100, 320),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DataTable2(
                  columnSpacing: 12,
                  horizontalMargin: 14,
                  fixedTopRows: 1,
                  headingRowColor: _headingColor(context),
                  empty: const EmptyTableState(
                      message: 'No packages in this request'),
                  columns: const [
                    DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                    DataColumn2(label: Text('Goods Name'), size: ColumnSize.M),
                    DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('HS Code'),
                        size: ColumnSize.S,
                        fixedWidth: 110),
                    DataColumn2(
                        label: Text('Qty'),
                        size: ColumnSize.S,
                        fixedWidth: 64,
                        numeric: true),
                    DataColumn2(
                        label: Center(child: Text('Source')),
                        size: ColumnSize.S,
                        fixedWidth: 110),
                    DataColumn2(
                        label: Center(child: Text('Disposition')),
                        size: ColumnSize.S,
                        fixedWidth: 130),
                    DataColumn2(
                        label: Text('Valuation'),
                        size: ColumnSize.S,
                        fixedWidth: 150),
                    DataColumn2(
                        label: Center(child: Text('Details')),
                        size: ColumnSize.S,
                        fixedWidth: 70),
                  ],
                  rows: expandedRows.map((row) {
                    final it = row.it;
                    final pkgItem = row.pkgItem;
                    final f = it.forfeited;
                    final displayName = pkgItem?.itemName ?? _itemName(it);
                    final displayHs = pkgItem?.hsCode ?? it.hsCodeLabel;
                    // Show/price only the forfeited quantity (e.g. 6 of 10).
                    final displayQty = _disposalForfeitedQty(it, pkgItem) ??
                        (pkgItem != null ? pkgItem.quantity : it.totalQuantity);
                    final highlightId = pkgItem?.id ??
                        f?.itemId ??
                        (f?.packageDetails?.items.isNotEmpty == true
                            ? f!.packageDetails!.items.first.id
                            : null);
                    return DataRow(cells: [
                      DataCell(TooltipText(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(TooltipText(displayName,
                          overflow: TextOverflow.ellipsis)),
                      DataCell(TooltipText(f?.consigneeName ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(TooltipText(displayHs ?? '—',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12))),
                      DataCell(TooltipText('$displayQty',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12))),
                      DataCell(Center(
                          child: _SourceChip(source: f?.source ?? 'forfeit'))),
                      DataCell(Center(
                          child:
                              _DispositionChip(disposition: it.disposition))),
                      // This screen NEVER shows a package that has already been
                      // placed in a tender_sale_items row (getDisposalRequests
                      // excludes it), so the figure is always the reserve
                      // price for whichever tender it eventually joins — there
                      // is no "the sale hasn't run yet" gate to check, because
                      // no sale exists at all yet. Always sealed.
                      DataCell(it.valuationCost != null
                          ? const SealedValuation(compact: true)
                          : Text('—',
                              style:
                                  TextStyle(color: context.colors.textMuted))),
                      DataCell(Center(
                        child: IconButton(
                          icon: Icon(Icons.info_outline_rounded,
                              color: context.colors.accentLightBlue, size: 18),
                          onPressed: f?.packageDetails == null
                              ? null
                              : () => showDialog(
                                    context: context,
                                    builder: (_) => PackageDetailsDialog(
                                      package: f!.packageDetails!,
                                      storageRate: storageRate,
                                      headerAccentColor:
                                          context.colors.successGreen,
                                      useLegacySummary: true,
                                      highlightItemId: highlightId,
                                      yardLabel:
                                          yardName(f.yard ?? request.yard),
                                      // Always sealed here too — see the
                                      // table cell above.
                                      valuationSealedUntilSale: true,
                                      valuationUnitCost: it.unitCost,
                                      valuationTotalCost: it.totalCost,
                                      valuationQty: displayQty,
                                    ),
                                  ),
                        ),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forfeit / Abandoned / Other origin tag for a requested package.
class _SourceChip extends StatelessWidget {
  final String source; // 'forfeit' | 'abandoned' | 'other'
  const _SourceChip({required this.source});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source) {
      'abandoned' => ('Abandoned', context.colors.heldOrange),
      'other' => ('Other', context.colors.warningAmber),
      _ => ('Forfeit', context.colors.accentBlue),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _DispositionChip extends StatelessWidget {
  final String disposition;
  const _DispositionChip({required this.disposition});
  @override
  Widget build(BuildContext context) {
    final isSale = disposition == 'sale';
    final color =
        isSale ? context.colors.successGreen : context.colors.dangerRed;
    final icon = isSale ? Icons.sell_rounded : Icons.delete_forever_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const Gap(5),
        Text(dispositionLabel(disposition),
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _CountPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  const _CountPill(
      {required this.icon,
      required this.label,
      required this.count,
      required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const Gap(6),
        Text('$count',
            style: TextStyle(
                color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        const Gap(6),
        Text(label,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Unsold packages → Re-tender (separate page/tab) ───────────────

class _UnsoldReTenderTab extends ConsumerWidget {
  const _UnsoldReTenderTab();

  String _itemName(ForfeitedPackageModel f) {
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    if (f.itemId != null) {
      final match = items.where((i) => i.id == f.itemId).firstOrNull;
      if (match != null) return match.itemName;
    }
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final amber = context.colors.warningAmber;
    final storageRate = ref.watch(storageRateProvider).valueOrNull ?? const {};
    final async = ref.watch(unsoldTenderSalesProvider);
    final eligible =
        ref.watch(reTenderEligibleProvider).valueOrNull ?? const <String>{};
    // Packages whose committee-priced tender ALSO failed have run out of
    // tender rounds — they belong to the Unsold Packages tab (where the DG
    // rules on them), not to this re-tender pool.
    final exhausted = {
      for (final i in ref.watch(exhaustedUnsoldProvider).valueOrNull ??
          const <ReTenderSaleInfo>[])
        i.forfeited.id
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Unsold Goods — Re-tender',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const DisposalSearch(
                tabKey: 'unsold', hint: 'Search SR / item / consignee…'),
            const Gap(12),
            YardAllFilter(
              value: ref.watch(disposalYardFilterProvider('unsold')),
              onChanged: (v) => ref
                  .read(disposalYardFilterProvider('unsold').notifier)
                  .state = v,
            ),
            const Gap(12),
            async.maybeWhen(
              data: (list) => ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: green, foregroundColor: Colors.white),
                icon: const Icon(Icons.gavel_rounded, size: 18),
                label: const Text('Re-tender',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onPressed: list.isEmpty
                    ? null
                    : () => showDialog(
                          context: context,
                          builder: (_) =>
                              const _TenderSaleFormDialog(reTender: true),
                        ).then((_) {
                          ref.invalidate(unsoldTenderSalesProvider);
                          ref.invalidate(tenderSalesProvider);
                        }),
              ),
              orElse: () => const SizedBox(),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          async.maybeWhen(
            data: (list) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: StatChip(
                  label: 'Unsold — re-tenderable',
                  // Counts the SAME rows the table shows — exhausted packages
                  // are excluded there, so they must not be counted here.
                  value:
                      '${list.where((i) => !exhausted.contains(i.forfeited.id)).length}',
                  color: amber),
            ).animate().fadeIn(duration: 300.ms),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(unsoldTenderSalesProvider)),
              data: (list) {
                // Every avenue exhausted → handled on Unsold Packages.
                list = list
                    .where((info) => !exhausted.contains(info.forfeited.id))
                    .toList();
                final q =
                    ref.watch(disposalSearchProvider('unsold')).toLowerCase();
                final yf = ref.watch(disposalYardFilterProvider('unsold'));
                if (yf != null) {
                  list = list
                      .where((info) => matchesYardFilter(
                          yf, info.forfeited.yard, info.forfeited.srNumber))
                      .toList();
                }
                if (q.isNotEmpty) {
                  list = list
                      .where((info) =>
                          info.forfeited.srNumber.toLowerCase().contains(q) ||
                          info.forfeited.consigneeName
                              .toLowerCase()
                              .contains(q) ||
                          _itemName(info.forfeited).toLowerCase().contains(q))
                      .toList();
                }
                if (list.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        icon: Icons.refresh_rounded,
                        message: 'No unsold packages to re-tender',
                        subtitle:
                            'Everything tendered is sold or still in an active sale window.'),
                  );
                }
                return _listCard(
                  context,
                  DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 16,
                    fixedTopRows: 1,
                    minWidth: 880,
                    headingRowColor: _headingColor(context),
                    columns: const [
                      DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                      DataColumn2(label: Text('Case No'), size: ColumnSize.S),
                      DataColumn2(
                          label: Text('Goods Name'), size: ColumnSize.M),
                      DataColumn2(
                          label: Center(child: Text('Source')),
                          size: ColumnSize.S),
                      DataColumn2(
                          label: Text('Qty'),
                          size: ColumnSize.S,
                          fixedWidth: 56),
                      DataColumn2(label: Text('Reason'), size: ColumnSize.M),
                      DataColumn2(label: Text('Location'), size: ColumnSize.M),
                      DataColumn2(
                          // "Latest": the cell shows the newest valuation —
                          // sealed while the round it prices is still open.
                          label: Text('Latest Valuation'),
                          size: ColumnSize.S,
                          fixedWidth: 145),
                      DataColumn2(
                          label: Center(child: Text('Tenders')),
                          size: ColumnSize.S,
                          fixedWidth: 110),
                      DataColumn2(
                          label: Center(child: Text('Bids')),
                          size: ColumnSize.S,
                          fixedWidth: 92),
                      DataColumn2(
                          label: Center(child: Text('Re-valuation')),
                          size: ColumnSize.S,
                          fixedWidth: 150),
                      DataColumn2(
                          label: Center(child: Text('Details')),
                          size: ColumnSize.S,
                          fixedWidth: 64),
                    ],
                    rows: list.map((info) {
                      final f = info.forfeited;
                      final pkg = f.packageDetails;
                      final item = f.itemId != null
                          ? (pkg?.items
                              .where((i) => i.id == f.itemId)
                              .firstOrNull)
                          : null;
                      return DataRow(cells: [
                        DataCell(TooltipText(f.srNumber,
                            style: TextStyle(
                                color: context.colors.accentLightBlue,
                                fontWeight: FontWeight.w600))),
                        DataCell(TooltipText(pkg?.caseNumber ?? '—',
                            overflow: TextOverflow.ellipsis)),
                        DataCell(TooltipText(_itemName(f),
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Center(child: _SourceChip(source: f.source))),
                        DataCell(TooltipText(
                            '${f.entryQty ?? item?.quantity ?? '—'}')),
                        DataCell(Builder(builder: (_) {
                          final reason = _forfeitReasonText(item, f);
                          return Tooltip(
                            message: reason,
                            child: Text(reason.isNotEmpty ? reason : '—',
                                overflow: TextOverflow.ellipsis),
                          );
                        })),
                        DataCell(TooltipText(_warehouseLocation(pkg, f.itemId),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12))),
                        DataCell(_UnsoldValuationCell(
                            info: info,
                            // The same signal the Re-valuation chip uses, so
                            // the two columns can never disagree.
                            reTenderable: eligible.contains(f.id),
                            qty: f.entryQty ?? item?.quantity)),
                        DataCell(Center(
                          child: _AttemptsBadge(
                            count: info.tenderCount,
                            color: amber,
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) =>
                                  _TenderSaleHistoryDialog(info: info),
                            ),
                          ),
                        )),
                        DataCell(Center(child: _BidsCell(info: info))),
                        DataCell(Center(
                          child: _ReTenderStatusCell(
                              info: info, eligible: eligible.contains(f.id)),
                        )),
                        DataCell(Center(
                          child: pkg != null
                              ? IconButton(
                                  icon: Icon(Icons.info_outline_rounded,
                                      color: context.colors.accentLightBlue,
                                      size: 18),
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => PackageDetailsDialog(
                                      package: pkg,
                                      storageRate: storageRate,
                                      headerAccentColor: green,
                                      useLegacySummary: true,
                                      highlightItemId: f.itemId,
                                      yardLabel: yardName(f.yard),
                                      valuationUnitCost: f.valuationCost,
                                      valuationTotalCost: f.valuationCost !=
                                              null
                                          ? f.valuationCost! * (f.entryQty ?? 1)
                                          : null,
                                      valuationQty: f.entryQty,
                                      // Sealed while the newest round is open.
                                      valuationSealedUntilSale:
                                          info.latestSale?.saleEnded == false,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        )),
                      ]);
                    }).toList(),
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

// ── Tender Sales ──────────────────────────────────────────────────

class _TenderSalesTab extends ConsumerWidget {
  const _TenderSalesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final sales = ref.watch(tenderSalesProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Tender Sales',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const DisposalSearch(
                tabKey: 'tendersales', hint: 'Search sale no / SR…'),
            const Gap(12),
            YardAllFilter(
              value: ref.watch(disposalYardFilterProvider('tendersales')),
              onChanged: (v) => ref
                  .read(disposalYardFilterProvider('tendersales').notifier)
                  .state = v,
            ),
            const Gap(12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: green, foregroundColor: Colors.white),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Tender Sale',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _TenderSaleFormDialog()),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),
          Expanded(
            child: sales.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.refresh(tenderSalesProvider)),
              data: (list) {
                final q = ref
                    .watch(disposalSearchProvider('tendersales'))
                    .toLowerCase();
                // Hide sales with no actionable rows left: every item sold
                // (fully consumed), OR the sell window has closed (un-sold items
                // have dropped to the Unsold Tenders pool).
                var visible = list.where((s) {
                  final hasPending = s.items.any((i) => !i.sold);
                  if (!hasPending) return false;
                  final windowClosed = s.unsoldDeadline != null &&
                      DateTime.now().isAfter(s.unsoldDeadline!);
                  return !windowClosed;
                }).toList();
                final yf = ref.watch(disposalYardFilterProvider('tendersales'));
                if (yf != null) {
                  // Match on any item's own yard + SR number, not the sale's
                  // yard alone — a tender sale can mix items from a
                  // multi-directorate yard (NNR items filed under CED sitting
                  // beside ones filed under PSD), so the sale-level yard code
                  // cannot tell them apart.
                  visible = visible
                      .where((s) => s.items.any((i) => matchesYardFilter(
                          yf, i.yard, i.forfeited?.srNumber ?? '')))
                      .toList();
                }
                if (q.isNotEmpty) {
                  visible = visible
                      .where((s) =>
                          (s.saleNumber ?? '').toLowerCase().contains(q) ||
                          s.items.any((i) =>
                              (i.forfeited?.srNumber ?? '')
                                  .toLowerCase()
                                  .contains(q) ||
                              (i.forfeited?.consigneeName ?? '')
                                  .toLowerCase()
                                  .contains(q)))
                      .toList();
                }
                if (visible.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        icon: Icons.storefront_outlined,
                        message: 'No active tender sales',
                        subtitle:
                            'Create a tender sale, or check the Unsold Tenders tab for items whose window has closed.'),
                  );
                }
                // Detect re-tenders against ALL sales (the earlier tender's
                // window may have closed and dropped out of `visible`).
                final retenderIds = retenderTenderSaleIds(list);
                return ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, i) => TenderSaleCard(
                      sale: visible[i],
                      isRetender: retenderIds.contains(visible[i].id)),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tender Sale card (header + per-item detail table + Mark Sold) ─────────

class _TsRow {
  final TenderSaleItemModel saleItem;
  final PackageItem? item;
  final String warehouse;
  const _TsRow(this.saleItem, this.item, this.warehouse);
}

// A re-tender reuses the SAME package ITEM (a fresh forfeited_packages row is
// created, so its id changes — but it still points to the same package_item).
// Match on the specific item id so re-tender is detected per item, NOT per
// package: two DIFFERENT items of one SR in two sales are not a re-tender.
// Falls back to the (per-sale, unique) forfeited id when no item id exists, so
// such rows never falsely match across sales.
String _tenderItemKey(TenderSaleItemModel i) =>
    i.forfeited?.itemId ?? i.forfeitedPackageId;
String _destItemKey(DestructionItemModel i) =>
    i.forfeited?.itemId ?? i.forfeitedPackageId;

/// Ids of tender sales that RE-TENDER an item — i.e. a sale that shares a
/// package (SR) with an EARLIER-created tender sale (the item went unsold there
/// and was placed in this newer sale).
Set<String> retenderTenderSaleIds(List<TenderSaleModel> sales) {
  final ids = <String>{};
  for (final s in sales) {
    final keys = s.items.map(_tenderItemKey).toSet();
    final isRe = sales.any((o) =>
        o.id != s.id &&
        o.createdAt.isBefore(s.createdAt) &&
        o.items.any((i) => keys.contains(_tenderItemKey(i))));
    if (isRe) ids.add(s.id);
  }
  return ids;
}

/// Same as [retenderTenderSaleIds] but for destruction sales (re-destruction).
Set<String> retenderDestructionIds(List<DestructionModel> sales) {
  final ids = <String>{};
  for (final s in sales) {
    final keys = s.items.map(_destItemKey).toSet();
    final isRe = sales.any((o) =>
        o.id != s.id &&
        o.createdAt.isBefore(s.createdAt) &&
        o.items.any((i) => keys.contains(_destItemKey(i))));
    if (isRe) ids.add(s.id);
  }
  return ids;
}

/// A small amber "Re-tender" pill shown in a sale card header when the sale
/// re-tenders (or re-schedules destruction for) an item that went unsold /
/// undestroyed in an earlier sale.
Widget _retenderBadge(BuildContext context, {String label = 'Re-tender'}) {
  final c = context.colors.warningAmber;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withOpacity(0.14),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: c.withOpacity(0.45)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.repeat_rounded, size: 12, color: c),
      const Gap(4),
      Text(label,
          style:
              TextStyle(color: c, fontSize: 10.5, fontWeight: FontWeight.w800)),
    ]),
  );
}

class TenderSaleCard extends ConsumerStatefulWidget {
  final TenderSaleModel sale;

  /// Yard-side, view-only mode: shows every item (sold included) with a
  /// read-only Sold/Pending status chip instead of the Mark-Sold action.
  final bool readOnly;

  /// True when this sale re-tenders an item that went unsold in an earlier
  /// tender sale — shown as a "Re-tender" badge in the card header.
  final bool isRetender;
  const TenderSaleCard(
      {required this.sale, this.readOnly = false, this.isRetender = false});

  @override
  ConsumerState<TenderSaleCard> createState() => _TenderSaleCardState();
}

class _TenderSaleCardState extends ConsumerState<TenderSaleCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The Mark-Sold button unlocks purely on the clock (widget.sale.saleEnded),
    // so with no trigger the card never re-evaluates it. Rebuild every 20s so
    // the button enables shortly after the scheduled sale time passes without a
    // manual page refresh.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _warehouseFor(PackageModel? pkg, String itemId) {
    if (pkg == null) return '—';
    final entries = pkg.warehouseEntries
        .where((e) => e.packageItemId == itemId)
        .toList()
      ..sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
    if (entries.isEmpty) return '—';
    final w = entries.first;
    return w.zone != null && w.zone!.isNotEmpty
        ? '${w.warehouseName} · ${w.zone}'
        : w.warehouseName;
  }

  List<_TsRow> _rows() {
    // Central Disposal hides sold items (they move to Sold Packages); the
    // yard view-only page keeps them so the yard can see the full outcome.
    // Once the sell window has CLOSED, the un-sold items have moved to the
    // Unsold Tenders pool — drop them here too (Central Disposal view only).
    final windowClosed = !widget.readOnly &&
        widget.sale.unsoldDeadline != null &&
        DateTime.now().isAfter(widget.sale.unsoldDeadline!);
    final Iterable<TenderSaleItemModel> source = widget.readOnly
        ? widget.sale.items
        : windowClosed
            ? const []
            : widget.sale.items.where((s) => !s.sold);

    // De-duplicate: same (forfeitedPackageId, packageItemId) may appear as
    // multiple TSI rows when the per-item RPC created extra entries. Keep the
    // sold row when one exists, otherwise the latest (highest soldAt / id).
    final dedupMap = <String, TenderSaleItemModel>{};
    for (final si in source) {
      final key = '${si.forfeitedPackageId}|${si.forfeited?.itemId ?? ''}';
      final existing = dedupMap[key];
      if (existing == null) {
        dedupMap[key] = si;
      } else {
        // Prefer sold over pending; if both same, keep later soldAt.
        if (si.sold && !existing.sold) {
          dedupMap[key] = si;
        } else if (si.sold == existing.sold) {
          final siTime = si.soldAt ?? DateTime(2000);
          final exTime = existing.soldAt ?? DateTime(2000);
          if (siTime.isAfter(exTime)) dedupMap[key] = si;
        }
      }
    }

    final rows = <_TsRow>[];
    for (final si in dedupMap.values) {
      final pkg = si.forfeited?.packageDetails;
      final pkgItems = pkg?.items ?? const [];
      final fpItemId = si.forfeited?.itemId;
      if (pkgItems.isEmpty) {
        rows.add(_TsRow(si, null, '—'));
      } else if (fpItemId != null) {
        // Per-item FP row — show only the specific item it refers to.
        final match = pkgItems.where((i) => i.id == fpItemId).firstOrNull;
        rows.add(_TsRow(
            si, match, match != null ? _warehouseFor(pkg!, match.id) : '—'));
      } else {
        // Package-level FP row — show one row per package item (legacy data).
        for (final it in pkgItems) {
          rows.add(_TsRow(si, it, _warehouseFor(pkg!, it.id)));
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final green = context.colors.successGreen;
    final storageRate = ref.watch(storageRateProvider).valueOrNull ?? const {};
    final rows = _rows();
    // Central Disposal: no actionable rows left (all sold, or the window closed
    // and the un-sold items moved to Unsold Tenders) → drop the whole card. The
    // yard view-only page (widget.readOnly) keeps the card to show the full outcome.
    if (!widget.readOnly && rows.isEmpty) return const SizedBox.shrink();
    final total = widget.sale.totalCount;
    final sold = widget.sale.soldCount;
    final allSold = total > 0 && sold == total;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color:
                allSold ? green.withOpacity(0.4) : context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_rounded, color: green, size: 20),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                            widget.sale.saleNumber?.isNotEmpty == true
                                ? widget.sale.saleNumber!
                                : 'Tender Sale',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                      ),
                      if (widget.isRetender) ...[
                        const Gap(8),
                        _retenderBadge(context),
                      ],
                    ]),
                    const Gap(2),
                    Row(children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 12, color: context.colors.textMuted),
                      const Gap(4),
                      Text(
                          widget.sale.saleDate != null
                              ? DateFormat('yyyy-MM-dd')
                                  .format(widget.sale.saleDate!)
                              : '—',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12)),
                      const Gap(12),
                      Flexible(
                        child: Text(widget.sale.typeLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textMuted, fontSize: 12)),
                      ),
                    ]),
                    // Live "Sell within" countdown to the unsold deadline — once
                    // it closes, the remaining items drop to Unsold Tenders.
                    // Central Disposal only — the yard's read-only view never
                    // shows the timer (the window is the directorate's concern).
                    if (!widget.readOnly &&
                        !allSold &&
                        widget.sale.unsoldDeadline != null) ...[
                      const Gap(6),
                      _DeadlineCountdown(
                          deadline: widget.sale.unsoldDeadline,
                          label: 'Sell within'),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (allSold ? green : context.colors.warningAmber)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: (allSold ? green : context.colors.warningAmber)
                          .withOpacity(0.4)),
                ),
                child: Text(
                  total == 0 ? 'No packages' : '$sold / $total sold',
                  style: TextStyle(
                      color: allSold ? green : context.colors.warningAmber,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: context.colors.borderColor),
          // Items table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: (rows.length * 48.0 + 56).clamp(115, 380),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DataTable2(
                  columnSpacing: 10,
                  horizontalMargin: 12,
                  fixedTopRows: 1,
                  minWidth: 1280,
                  headingRowColor: _headingColor(context),
                  empty: const EmptyTableState(
                      message: 'No packages in this sale'),
                  columns: [
                    DataColumn2(label: Text('SR Number'), size: ColumnSize.S, fixedWidth: 135),
                    DataColumn2(label: Text('Case No'), size: ColumnSize.S, fixedWidth: 130),
                    DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
                    DataColumn2(
                        label: Center(child: Text('Source')),
                        size: ColumnSize.S,
                        fixedWidth: 65),
                    DataColumn2(
                        label: Center(child: Text('Qty')),
                        size: ColumnSize.S,
                        fixedWidth: 50),
                    DataColumn2(label: Text('Reason'), size: ColumnSize.M),
                    DataColumn2(label: Text('Location'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Goods Description'), size: ColumnSize.L),
                    // Both the yard's own view (SR item declared value) and
                    // Central's (the reserve price) are commercially sensitive
                    // to a bidder, so both are named and sealed the same way.
                    DataColumn2(
                        label: Center(child: const Text('Latest Valuation')),
                        size: ColumnSize.S,
                        fixedWidth: 140),
                    DataColumn2(
                        label: Center(child: Text('Status')),
                        size: ColumnSize.M,
                        fixedWidth: 235),
                    DataColumn2(
                        label: Center(child: Text('Details')),
                        size: ColumnSize.S,
                        fixedWidth: 55),
                  ],
                  rows: rows.map((r) {
                    final f = r.saleItem.forfeited;
                    final pkg = f?.packageDetails;
                    return DataRow(cells: [
                      DataCell(TooltipText(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(TooltipText(pkg?.caseNumber ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(TooltipText(
                          r.item?.itemName ?? 'Multiple/Unspecified',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Center(child: _sourceChip(context, f?.source))),
                      DataCell(Center(
                          child: Text(
                              '${f?.entryQty ?? r.item?.quantity ?? '—'}'))),
                      DataCell(Builder(builder: (_) {
                        final reason = _forfeitReasonText(r.item, f);
                        return Tooltip(
                          message: reason,
                          child: Text(reason.isNotEmpty ? reason : '—',
                              overflow: TextOverflow.ellipsis),
                        );
                      })),
                      DataCell(TooltipText(
                          '${yardName(r.saleItem.yard)} / ${r.warehouse}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12))),
                      DataCell(Tooltip(
                        message: r.item?.goodsDescription ?? '',
                        child: Text(
                            r.item?.goodsDescription?.isNotEmpty == true
                                ? r.item!.goodsDescription!
                                : '—',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12)),
                      )),
                      DataCell(Center(
                          child: _ValuationCell(
                              f: f,
                              useItemValue: widget.readOnly,
                              // Same clock that gates Mark Sold below.
                              sealedUntilSale: !widget.sale.saleEnded,
                              qty: f?.entryQty ?? r.item?.quantity))),
                      DataCell(Center(
                        child: r.saleItem.sold
                            ? _statusChip(context, 'Sold',
                                Icons.check_circle_rounded, green)
                            : (() {
                                final deadline = widget.sale.unsoldDeadline;
                                final isUnsold = r.saleItem.unsold ||
                                    (deadline != null &&
                                        DateTime.now().isAfter(deadline));
                                if (isUnsold) {
                                  return _statusChip(
                                      context,
                                      'Unsold',
                                      Icons.cancel_outlined,
                                      context.colors.dangerRed);
                                }
                                if (widget.readOnly) {
                                  return _statusChip(
                                      context,
                                      'Pending',
                                      Icons.schedule_rounded,
                                      context.colors.warningAmber);
                                }
                                final canSell = widget.sale.saleTimePassed;
                                final btnRow = FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: green,
                                          backgroundColor:
                                              green.withOpacity(0.08),
                                          side: BorderSide(
                                              color: green.withOpacity(0.5)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 5),
                                          minimumSize: const Size(0, 31),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(7.5),
                                          ),
                                        ),
                                        icon: const Icon(Icons.sell_rounded,
                                            size: 13),
                                        label: const Text('Mark Sold',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                        onPressed: canSell
                                            ? () => _markSold(
                                                context, ref, r.saleItem)
                                            : null,
                                      ),
                                      const Gap(6),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              context.colors.dangerRed,
                                          backgroundColor: context
                                              .colors.dangerRed
                                              .withOpacity(0.08),
                                          side: BorderSide(
                                              color: context.colors.dangerRed
                                                  .withOpacity(0.5)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 5),
                                          minimumSize: const Size(0, 31),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(7.5),
                                          ),
                                        ),
                                        icon: const Icon(
                                            Icons.cancel_outlined,
                                            size: 13),
                                        label: const Text('Mark Unsold',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                        onPressed: canSell
                                            ? () => _markUnsold(context, ref,
                                                r.saleItem, f?.srNumber)
                                            : null,
                                      ),
                                    ],
                                  ),
                                );
                                return canSell
                                    ? btnRow
                                    : Tooltip(
                                        message:
                                            _saleLockMessage(widget.sale),
                                        child: btnRow);
                              }()),
                      )),
                      DataCell(Center(
                        child: pkg != null
                            ? IconButton(
                                icon: Icon(Icons.info_outline_rounded,
                                    color: context.colors.accentLightBlue,
                                    size: 18),
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => PackageDetailsDialog(
                                    package: pkg,
                                    storageRate: storageRate,
                                    // Yard (read-only) uses the default blue
                                    // header like Forfeited; Central keeps green.
                                    headerAccentColor:
                                        widget.readOnly ? null : green,
                                    useLegacySummary: true,
                                    highlightItemId: f?.itemId,
                                    yardLabel: yardName(r.saleItem.yard),
                                    // Shown in BOTH views now: the yard's own
                                    // column already carries this figure (see
                                    // _ValuationCell's useItemValue branch),
                                    // so hiding it here just meant the same
                                    // number was reachable one way but not the
                                    // other. Sealing — not hiding — is what
                                    // actually protects a reserve price.
                                    valuationUnitCost: f?.valuationCost,
                                    valuationTotalCost:
                                        f?.valuationCost != null
                                            ? f!.valuationCost! *
                                                (f.entryQty ??
                                                    r.item?.quantity ??
                                                    1)
                                            : null,
                                    valuationQty:
                                        f?.entryQty ?? r.item?.quantity,
                                    // Sealed until the sale has ended — the
                                    // popup is just another way to read the
                                    // same reserve price.
                                    valuationSealedUntilSale:
                                        !widget.sale.saleEnded,
                                    // The per-round chain this package went
                                    // through to reach the current price —
                                    // Valuation Tender, any re-valued rounds,
                                    // and now this one. Each round's OWN price
                                    // is sealed until that round has ended, the
                                    // same rule Unsold Tenders already uses.
                                    tenderHistoryFor: f,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(
      BuildContext context, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13.5, color: color),
        const Gap(5),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  /// Tooltip shown on a disabled Mark Sold button — tells the officer when the
  /// scheduled sale moment unlocks the action.
  String _saleLockMessage(TenderSaleModel sale) {
    final moment = widget.sale.saleMoment;
    if (moment == null) return 'No sale date set yet';
    final when = DateFormat('yyyy-MM-dd HH:mm').format(moment);
    return 'Available after the scheduled sale time ($when)';
  }

  Future<void> _markSold(
      BuildContext context, WidgetRef ref, TenderSaleItemModel item) async {
    // Pre-load the active taxes BEFORE opening the dialog so the form renders
    // once, fully (Sold Price + Taxes + Grand Total), instead of flickering in
    // when the async tax fetch completes after the dialog is already shown.
    final taxes = await ref.read(disposalServiceProvider).getTaxes();
    final activeTaxes = taxes.where((t) => t.isActive).toList();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) =>
          _MarkSoldDialog(item: item, ref: ref, activeTaxes: activeTaxes),
    );
  }

  Future<void> _markUnsold(BuildContext context, WidgetRef ref,
      TenderSaleItemModel item, String? srNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.colors.borderColor),
        ),
        title: Row(children: [
          Icon(Icons.cancel_outlined,
              color: context.colors.dangerRed, size: 20),
          const Gap(10),
          Text('Mark as Unsold',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Mark ${srNumber ?? 'this package'} as Unsold? It will be moved to the Unsold Tenders page for re-valuation.',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: context.colors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.dangerRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Unsold'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(disposalServiceProvider)
          .markTenderSaleItemUnsold(tenderSaleItemId: item.id);
      ref.read(tenderSaleItemsRefreshProvider.notifier).trigger();
      ref.invalidate(unsoldTenderSalesProvider);
      ref.invalidate(reTenderEligibleProvider);
      if (context.mounted) {
        DefaultTabController.of(context).animateTo(10);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${srNumber ?? 'Package'} marked as Unsold — moved to Unsold Tenders'),
          backgroundColor: context.colors.dangerRed,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: context.colors.dangerRed,
        ));
      }
    }
  }
}

class _MarkSoldDialog extends StatefulWidget {
  final TenderSaleItemModel item;
  final WidgetRef ref;
  final List<DisposalTaxModel> activeTaxes;
  const _MarkSoldDialog(
      {required this.item, required this.ref, required this.activeTaxes});
  @override
  State<_MarkSoldDialog> createState() => _MarkSoldDialogState();
}

class _MarkSoldDialogState extends State<_MarkSoldDialog> {
  final _receiptC = TextEditingController();
  final _soldPriceC = TextEditingController();
  bool _loading = false;
  String? _error;
  // Active taxes are pre-loaded by _markSold and passed in, so the form renders
  // complete on first frame (no flicker).
  late final List<DisposalTaxModel> _activeTaxes = widget.activeTaxes;

  @override
  void initState() {
    super.initState();
    _soldPriceC.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _receiptC.dispose();
    _soldPriceC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(_soldPriceC.text) ?? 0.0;
    double totalTax = 0.0;
    final List<Map<String, dynamic>> appliedTaxesList = [];
    for (var t in _activeTaxes) {
      final taxAmount = price * (t.percentage / 100);
      totalTax += taxAmount;
      appliedTaxesList.add({
        'id': t.id,
        'name': t.name,
        'percentage': t.percentage,
        'amount': taxAmount,
      });
    }
    final double grandTotal = price + totalTax;

    return StyledFormDialog(
      label: 'Tender Sale',
      title: 'Mark Package Sold',
      headerAccentColor: context.colors.successGreen,
      icon: Icons.sell_rounded,
      width: 460,
      child: StyledFormSection(
        title: 'Sale Confirmation',
        icon: Icons.receipt_rounded,
        children: [
          Text(
              '${widget.item.forfeited?.srNumber ?? 'Package'} — ${yardName(widget.item.yard)}. '
              'This records the package as SOLD.',
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 13)),
          TextField(
            controller: _receiptC,
            decoration: const InputDecoration(labelText: 'Receipt Number *'),
          ),
          const Gap(16),
          TextField(
            controller: _soldPriceC,
            decoration: const InputDecoration(
                labelText: 'Sold Price *', prefixText: 'Rs '),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          if (_activeTaxes.isNotEmpty) ...[
            const Gap(16),
            const Text('Taxes:', style: TextStyle(fontWeight: FontWeight.bold)),
            for (var t in _activeTaxes)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${t.name} (${t.percentage}%)'),
                  Text(
                      'Rs ${(price * (t.percentage / 100)).toStringAsFixed(2)}'),
                ],
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Grand Total:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Rs ${grandTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
          if (_error != null) ...[
            const Gap(12),
            Text(_error!,
                style:
                    TextStyle(color: context.colors.dangerRed, fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        StyledDialogPrimaryButton(
          labelText: 'Confirm Sold',
          icon: Icons.check_circle_rounded,
          loading: _loading,
          onPressed: () async {
            // Receipt Number and Sold Price are mandatory.
            final receiptNo = _receiptC.text.trim();
            final enteredPrice =
                double.tryParse(_soldPriceC.text.trim()) ?? 0.0;
            if (receiptNo.isEmpty) {
              setState(() => _error = 'Receipt Number is required.');
              return;
            }
            if (_soldPriceC.text.trim().isEmpty || enteredPrice <= 0) {
              setState(() => _error = 'Enter a valid Sold Price.');
              return;
            }
            setState(() {
              _error = null;
              _loading = true;
            });
            try {
              await widget.ref
                  .read(disposalServiceProvider)
                  .markTenderSaleItemSold(
                    tenderSaleItemId: widget.item.id,
                    receipt: receiptNo,
                    soldPrice: enteredPrice,
                    appliedTaxes: appliedTaxesList,
                  );
              // Fire every related trigger so this session's views update
              // instantly (the realtime round-trip handles other sessions).
              widget.ref.read(tenderSalesRefreshProvider.notifier).trigger();
              widget.ref
                  .read(tenderSaleItemsRefreshProvider.notifier)
                  .trigger();
              widget.ref
                  .read(packagesRefreshTriggerProvider.notifier)
                  .trigger();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Package marked sold'),
                  backgroundColor: context.colors.successGreen,
                ));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_appealHoldMessage(e)),
                  backgroundColor: context.colors.dangerRed,
                ));
              }
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
        ),
      ],
    );
  }
}

/// Maps the `appeal_hold_active` RPC error to a clear message, else a generic one.
String _appealHoldMessage(Object e) {
  if (e.toString().contains('appeal_hold_active')) {
    return 'This package is under an appeal hold and cannot be sold or destroyed.';
  }
  return 'Error: $e';
}

// ── New Tender Sale form (details + Sale-only package picker) ─────────────

class _TenderSaleFormDialog extends ConsumerStatefulWidget {
  /// In [reTender] mode the package pool is the unsold tender-sale packages
  /// (not fresh "Sale" requests) — used by the Unsold Tenders page.
  final bool reTender;
  const _TenderSaleFormDialog({this.reTender = false});
  @override
  ConsumerState<_TenderSaleFormDialog> createState() =>
      _TenderSaleFormDialogState();
}

class _TenderSaleFormDialogState extends ConsumerState<_TenderSaleFormDialog> {
  final _numberC = TextEditingController();
  final _serialC = TextEditingController();
  final _yearC = TextEditingController(text: DateTime.now().year.toString());
  DateTime? _openDate;
  DateTime? _closeDate;
  TimeOfDay? _closeTime;
  TimeOfDay? _startTime;
  String? _tenderType;
  bool _loading = false;
  String? _error;
  // forfeited_package_id → yard
  final Map<String, String> _selected = {};
  // The yard this tender sale belongs to. The package pool is filtered to this
  // yard's forwarded requests, and the created sale is assigned to it.
  late String _formYard;

  String? _validate() {
    if (_openDate == null) return 'Tender Open Date is required.';
    if (_closeDate == null) return 'Tender Close Date is required.';
    if (_closeDate!.isBefore(DateTime(_openDate!.year, _openDate!.month, _openDate!.day))) {
      return 'Tender Close Date cannot be before Tender Open Date.';
    }
    if (_closeTime == null) return 'Tender Close Time is required.';
    if (_startTime == null) return 'Tender Start Time is required.';
    final closeM = _closeTime!.hour * 60 + _closeTime!.minute;
    final startM = _startTime!.hour * 60 + _startTime!.minute;
    if (startM <= closeM) {
      return 'Tender Start Time must be after the Close Time.';
    }
    if (_tenderType == null || _tenderType!.isEmpty)
      return 'Tender Sale Type is required.';
    if (_selected.isEmpty) return 'Select at least one package.';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _formYard = ref.read(disposalSelectedYardProvider);
    _yearC.addListener(_onYearChanged);
    _serialC.addListener(_updateSaleNumber);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSerialForYear();
    });
  }

  @override
  void dispose() {
    _yearC.removeListener(_onYearChanged);
    _serialC.removeListener(_updateSaleNumber);
    _numberC.dispose();
    _serialC.dispose();
    _yearC.dispose();
    super.dispose();
  }

  void _onYearChanged() {
    if (_yearC.text.length == 4) {
      _loadSerialForYear();
    }
  }

  Future<void> _loadSerialForYear() async {
    final year = int.tryParse(_yearC.text);
    if (year == null) return;
    try {
      // Serial runs per-yard: GL1's 6th tender is serial 6 even if GL2 has 3.
      final nextSerial = await ref
          .read(disposalServiceProvider)
          .getNextTenderSaleSerial(year, yard: _formYard);
      if (mounted) {
        _serialC.text = nextSerial.toString();
        _updateSaleNumber();
      }
    } catch (e) {
      // ignore
    }
  }

  void _updateSaleNumber() {
    final year = _yearC.text;
    final serial = _serialC.text;
    if (year.isEmpty || serial.isEmpty) return;

    String saleNum = 'CDU/TS/$year/$serial';
    if (_tenderType == 'special') {
      saleNum += '(Special)';
    }
    _numberC.text = saleNum;
  }

  String _summary(DisposalRequestItemModel it) {
    final pkgItems = it.forfeited?.packageDetails?.items ?? const [];
    if (pkgItems.isEmpty) return 'Multiple/Unspecified';
    final itemId = it.forfeited?.itemId;
    if (itemId != null) {
      final match = pkgItems.where((i) => i.id == itemId).firstOrNull;
      if (match != null) return match.itemName;
    }
    if (pkgItems.length == 1) return pkgItems.first.itemName;
    return '${pkgItems.first.itemName} +${pkgItems.length - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final green = context.colors.successGreen;
    // Fresh sale → "Sale"-tagged requests. Re-tender → only the unsold packages
    // that the Valuation Directorate has RE-VALUED (others await re-valuation).
    // Either way, only packages in the yard selected in this form are shown.
    final eligible =
        ref.watch(reTenderEligibleProvider).valueOrNull ?? const <String>{};
    final AsyncValue<List<DisposalRequestItemModel>> pool = (widget.reTender
            ? ref.watch(unsoldTenderSalesProvider).whenData((list) => list
                .where((info) => eligible.contains(info.forfeited.id))
                .map((info) => DisposalRequestItemModel(
                      id: info.forfeited.id,
                      requestId: '',
                      forfeitedPackageId: info.forfeited.id,
                      disposition: 'sale',
                      forfeited: info.forfeited,
                    ))
                .toList())
            : ref.watch(saleRequestItemsProvider))
        .whenData((list) =>
            list.where((it) => it.forfeited?.yard == _formYard).toList());
    return StyledFormDialog(
      label: 'Tender Sale',
      title: widget.reTender ? 'Re-tender Sale' : 'New Tender Sale',
      headerAccentColor: context.colors.successGreen,
      icon: Icons.gavel_rounded,
      width: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.dangerRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: context.colors.dangerRed.withOpacity(0.4)),
              ),
              child: Row(children: [
                Icon(Icons.error_outline,
                    color: context.colors.dangerRed, size: 18),
                const Gap(10),
                Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            color: context.colors.dangerRed, fontSize: 13))),
              ]),
            ),
            const Gap(12),
          ],
          StyledFormSection(
            title: 'Sale Details',
            icon: Icons.receipt_long_rounded,
            children: [
              _StyledYardPicker(
                value: _formYard,
                width: double.infinity,
                yards: ref.watch(yardsProvider).valueOrNull
                        ?.where((y) => y.isActive)
                        .toList() ??
                    [for (final y in kYards) YardModel(code: y.code, name: y.name, srPrefix: y.srPrefix)],
                onChanged: (v) {
                  if (v == null) return;
                  // Switching yards clears any selection from the previous yard
                  // and reloads the serial scoped to the newly selected yard.
                  setState(() {
                    _formYard = v;
                    _selected.clear();
                  });
                  _loadSerialForYear();
                },
              ),
              TextField(
                controller: _numberC,
                readOnly: true,
                decoration:
                    const InputDecoration(labelText: 'Tender Sale Number'),
              ),
              Row(children: [
                Expanded(
                  child: _OneTapDateField(
                    label: 'Tender Open Date',
                    value: _openDate,
                    onChanged: (d) => setState(() {
                      _openDate = d;
                      if (d != null) {
                        _closeDate = d.add(const Duration(days: 14));
                      }
                    }),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _OneTapDateField(
                    label: 'Tender Close Date',
                    value: _closeDate,
                    onChanged: (d) => setState(() => _closeDate = d),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: _OneTapTimeField(
                    label: 'Tender Close Time',
                    value: _closeTime,
                    onChanged: (t) => setState(() {
                      _closeTime = t;
                      if (t != null) {
                        _startTime =
                            TimeOfDay(hour: (t.hour + 1) % 24, minute: t.minute);
                      }
                    }),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _OneTapTimeField(
                    label: 'Tender Start Time',
                    value: _startTime,
                    onChanged: (t) => setState(() => _startTime = t),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _serialC,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Serial'),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: TextField(
                    controller: _yearC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Year'),
                  ),
                ),
              ]),
              StyledDropdownFormField<String>(
                value: _tenderType,
                label: 'Tender Sale Type',
                helperText: null,
                isDense: true,
                menuWidth: 400,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                options: [
                  for (final e in kTenderSaleTypes.entries)
                    StyledDropdownOption(e.key, e.value),
                ],
                onChanged: (v) {
                  setState(() => _tenderType = v);
                  _updateSaleNumber();
                },
              ),
            ],
          ),
          const Gap(16),
          StyledFormSection(
            title: 'Select Packages — for Sale (${_selected.length} selected)',
            icon: Icons.inventory_2_rounded,
            children: [
              pool.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.refresh(widget.reTender
                        ? unsoldTenderSalesProvider
                        : saleRequestItemsProvider)),
                data: (items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          widget.reTender
                              ? 'No re-valued unsold packages for this yard.\n'
                                  'A package can be re-tendered only after the '
                                  'Valuation Directorate sets a new valuation '
                                  'for it.'
                              : 'No "Sale" packages awaiting a tender sale.\n'
                                  'Yards mark packages for Sale in a Disposal Request.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.textSecondary),
                        ),
                      ),
                    );
                  }
                  // Items already covered by a dedicated per-item row (correct
                  // partial qty) — a package-level row must not re-expand them
                  // at the full registered qty.
                  final perItemKeys = <String>{};
                  for (final it in items) {
                    final iid = it.forfeited?.itemId;
                    final pid = it.forfeited?.packageId;
                    if (iid != null && pid != null) {
                      perItemKeys.add('$pid:$iid');
                    }
                  }
                  // Expand package-level DR items (itemId==null, multiple pkg
                  // items) so each item appears as its own selectable row.
                  final rows =
                      <({DisposalRequestItemModel it, PackageItem? pkgItem})>[];
                  for (final it in items) {
                    final fpItems =
                        it.forfeited?.packageDetails?.items ?? const [];
                    final pid = it.forfeited?.packageId;
                    if (it.forfeited?.itemId == null && fpItems.length > 1) {
                      for (final pkgItem in fpItems) {
                        if (pid != null &&
                            perItemKeys.contains('$pid:${pkgItem.id}')) {
                          continue;
                        }
                        rows.add((it: it, pkgItem: pkgItem));
                      }
                    } else {
                      rows.add((it: it, pkgItem: null));
                    }
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SelectAllBar(
                        selectedCount: _selected.length,
                        totalCount: rows.length,
                        onSelectAll: () => setState(() {
                          for (final r in rows) {
                            final rowKey = r.pkgItem != null
                                ? '${r.it.id}_${r.pkgItem!.id}'
                                : r.it.id;
                            _selected[rowKey] = r.it.forfeited?.yard ?? '';
                          }
                        }),
                        onClearAll: () => setState(_selected.clear),
                      ),
                      const Gap(8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color:
                                  context.colors.borderColor.withOpacity(0.5)),
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            final it = r.it;
                            final pkgItem = r.pkgItem;
                            final rowKey = pkgItem != null
                                ? '${it.id}_${pkgItem.id}'
                                : it.id;
                            final yard = it.forfeited?.yard ?? '';
                            final selected = _selected.containsKey(rowKey);
                            final displayName =
                                pkgItem?.itemName ?? _summary(it);
                            // Show the forfeited quantity (e.g. 6 of 10).
                            final qty = _disposalForfeitedQty(it, pkgItem) ??
                                (pkgItem != null
                                    ? pkgItem.quantity
                                    : it.totalQuantity);
                            return InkWell(
                              onTap: () => setState(() {
                                if (selected) {
                                  _selected.remove(rowKey);
                                } else {
                                  _selected[rowKey] = yard;
                                }
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 6),
                                child: Row(children: [
                                  Checkbox(
                                    activeColor: green,
                                    value: selected,
                                    onChanged: (_) => setState(() {
                                      if (selected) {
                                        _selected.remove(rowKey);
                                      } else {
                                        _selected[rowKey] = yard;
                                      }
                                    }),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Flexible(
                                            child: Text(
                                                it.forfeited?.srNumber ?? '—',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: context.colors
                                                        .accentLightBlue)),
                                          ),
                                          const Gap(8),
                                          _SourceChip(
                                              source: it.forfeited?.source ??
                                                  'forfeit'),
                                        ]),
                                        Text(displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: context
                                                    .colors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                        it.forfeited?.consigneeName ?? '—',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: context.colors.textPrimary)),
                                  ),
                                  const Gap(10),
                                  Text('Qty $qty',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: context.colors.textMuted)),
                                  const Gap(8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: green.withOpacity(0.3)),
                                    ),
                                    child: Text(yardName(yard),
                                        style: TextStyle(
                                            color: green,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        StyledDialogPrimaryButton(
          labelText: 'Save Tender Sale',
          icon: Icons.save_rounded,
          loading: _loading,
          onPressed: () async {
            final err = _validate();
            if (err != null) {
              setState(() => _error = err);
              return;
            }
            setState(() {
              _loading = true;
              _error = null;
            });
            // Build forfeitedPackageId→yard from composite _selected keys.
            // Re-tender picks from the UNSOLD pool (mapped the same way the form
            // builds its rows); a fresh sale picks from the sale-request pool.
            // Using the wrong pool here left packageYards empty so the re-tender
            // created no tender_sale_items — the package never moved sales.
            final allDrItems = widget.reTender
                ? (ref.read(unsoldTenderSalesProvider).valueOrNull ?? const [])
                    .map((info) => DisposalRequestItemModel(
                          id: info.forfeited.id,
                          requestId: '',
                          forfeitedPackageId: info.forfeited.id,
                          disposition: 'sale',
                          forfeited: info.forfeited,
                        ))
                    .toList()
                : (ref.read(saleRequestItemsProvider).valueOrNull ?? const []);
            final packageYards = <String, String>{};
            // forfeited_package_id → the specific package_item id it covers, so
            // the TSI row is item-scoped (Mark Sold sells only that item).
            final packageItems = <String, String?>{};
            for (final key in _selected.keys) {
              final drItemId = key.contains('_') ? key.split('_').first : key;
              final drItem =
                  allDrItems.where((it) => it.id == drItemId).firstOrNull;
              if (drItem != null) {
                packageYards[drItem.forfeitedPackageId] =
                    drItem.forfeited?.yard ?? _formYard;
                // Resolve the item id: an expanded composite key carries the
                // pkgItem id after '_'; otherwise the FP's own item_id.
                final pkgItemId = key.contains('_')
                    ? key.split('_').last
                    : drItem.forfeited?.itemId;
                packageItems[drItem.forfeitedPackageId] = pkgItemId;
              }
            }
            try {
              await ref.read(disposalServiceProvider).createTenderSale(
                    saleNumber: _numberC.text.trim().isEmpty
                        ? null
                        : _numberC.text.trim(),
                    saleDate: _closeDate,
                    saleTime: _startTime == null
                        ? null
                        : _timeOfDayToHHmm(_startTime!),
                    saleEndTime: _closeTime == null
                        ? null
                        : _timeOfDayToHHmm(_closeTime!),
                    serial: _serialC.text.trim().isEmpty
                        ? null
                        : _serialC.text.trim(),
                    year: int.tryParse(_yearC.text.trim()),
                    tenderType: _tenderType,
                    yard: _formYard,
                    packageYards: packageYards,
                    packageItems: packageItems,
                  );
              // New sale → its items leave the request pool; refresh both.
              ref.read(tenderSalesRefreshProvider.notifier).trigger();
              ref.read(tenderSaleItemsRefreshProvider.notifier).trigger();
              if (mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Tender sale recorded'),
                  backgroundColor: green,
                ));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: context.colors.dangerRed,
                ));
              }
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
        ),
      ],
    );
  }
}

// ── Tender Committees (read-only view of DG-appointed committees) ─────────────
final _committeesYardProvider =
    StateProvider<String?>((ref) => null); // null=all

String _committeeItemName(ForfeitedPackageModel f) {
  if (f.itemName != null) return f.itemName!;
  final items = f.packageDetails?.items ?? const [];
  if (items.isEmpty) return 'Multiple/Unspecified';
  // Forfeiture is recorded PER ITEM, so a multi-item package produces one row
  // per item. Resolve THIS row's own item from item_id — falling straight
  // through to items.first labelled every row of the package with the first
  // item's name (e.g. three "Wash Basins +2" rows).
  if (f.itemId != null) {
    final match = items.where((i) => i.id == f.itemId).firstOrNull;
    if (match != null) return match.itemName;
  }
  if (items.length == 1) return items.first.itemName;
  return '${items.first.itemName} +${items.length - 1}';
}

/// Central Disposal read-only tab: packages the ADG has appointed a committee for
/// (unsold >3 times). Each row expands to show the 5 committee members.
class _CommitteesTab extends ConsumerWidget {
  const _CommitteesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = context.colors.accentLightBlue;
    final eligible = ref.watch(committeeEligibleProvider);
    final committees =
        ref.watch(tenderCommitteesProvider).valueOrNull ?? const {};
    // Packages that have moved on to the Unsold Packages table: the
    // committee-priced tender ran and failed too, so the committee's work is
    // finished and its card leaves this tab.
    final movedOn = {
      for (final i in ref.watch(exhaustedUnsoldProvider).valueOrNull ??
          const <ReTenderSaleInfo>[])
        i.forfeited.id
    };
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Tender Committees',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Gap(10),
            Expanded(
              child: Text(
                  'Committees appointed by the Top Management Directorate for packages still unsold after Tender 3',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 13)),
            ),
            const Gap(12),
            const DisposalSearch(
                tabKey: 'committees', hint: 'Search SR / item / consignee…'),
            const Gap(12),
            YardAllFilter(
              value: ref.watch(_committeesYardProvider),
              onChanged: (v) =>
                  ref.read(_committeesYardProvider.notifier).state = v,
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),
          Expanded(
            child: eligible.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: accent)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(committeeEligibleProvider)),
              data: (list) {
                // Only packages that actually have a committee appointed AND
                // have not yet moved on to the Unsold Packages table.
                var rows = list
                    .where((i) =>
                        committees.containsKey(i.forfeited.id) &&
                        !movedOn.contains(i.forfeited.id))
                    .toList();
                final yf = ref.watch(_committeesYardProvider);
                if (yf != null) {
                  rows = rows
                      .where((i) => matchesYardFilter(
                          yf, i.forfeited.yard, i.forfeited.srNumber))
                      .toList();
                }
                final qq = ref
                    .watch(disposalSearchProvider('committees'))
                    .toLowerCase();
                if (qq.isNotEmpty) {
                  rows = rows.where((info) {
                    final f = info.forfeited;
                    return f.srNumber.toLowerCase().contains(qq) ||
                        f.consigneeName.toLowerCase().contains(qq) ||
                        _committeeItemName(f).toLowerCase().contains(qq);
                  }).toList();
                }
                if (rows.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        icon: Icons.groups_rounded,
                        message: 'No committees appointed yet',
                        subtitle:
                            'The Top Management Directorate appoints a committee for packages still unsold after Tender 3.'),
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Gap(14),
                  itemBuilder: (context, i) => _CommitteeCard(
                      info: rows[i],
                      committee: committees[rows[i].forfeited.id]!,
                      storageRate: storageRate),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A package + its appointed committee (read-only card).
class _CommitteeCard extends StatelessWidget {
  final ReTenderSaleInfo info;
  final TenderCommitteeModel committee;
  final Map<DateTime, double> storageRate;
  const _CommitteeCard(
      {required this.info, required this.committee, required this.storageRate});

  @override
  Widget build(BuildContext context) {
    // Central Disposal team colour is green.
    final green = context.colors.successGreen;
    final f = info.forfeited;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: package identity + times tendered.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.groups_rounded, size: 18, color: green),
              ),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(f.srNumber,
                          style: TextStyle(
                              color: green,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const Gap(10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.colors.warningAmber.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${info.tenderCount}× unsold',
                            style: TextStyle(
                                color: context.colors.warningAmber,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const Gap(2),
                    Text(
                        '${_committeeItemName(f)} · ${f.consigneeName} · ${yardName(f.yard)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              const Gap(8),
              // Package details popup for this committee's package.
              Tooltip(
                message: 'Package details',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: green,
                    side: BorderSide(color: green.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  icon: const Icon(Icons.info_outline_rounded, size: 16),
                  label: const Text('Details'),
                  onPressed: f.packageDetails == null
                      ? null
                      : () {
                          final item = f.itemId != null
                              ? f.packageDetails!.items
                                  .where((i) => i.id == f.itemId)
                                  .firstOrNull
                              : null;
                          final qty = f.entryQty ?? item?.quantity;
                          showDialog(
                            context: context,
                            builder: (_) => PackageDetailsDialog(
                              package: f.packageDetails!,
                              storageRate: storageRate,
                              headerAccentColor: green,
                              useLegacySummary: true,
                              highlightItemId: f.itemId,
                              yardLabel: yardName(f.yard),
                              // Central Disposal's Committees tab: the
                              // package can still be re-tendered, so the
                              // reserve price is sealed here too.
                              valuationSealedUntilSale:
                                  info.latestSale?.saleEnded == false,
                              valuationUnitCost: f.valuationCost,
                              valuationTotalCost: f.valuationCost != null
                                  ? f.valuationCost! * (qty ?? 1)
                                  : null,
                              valuationQty: qty,
                            ),
                          );
                        },
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: context.colors.borderColor),
          // Members.
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('COMMITTEE (${committee.members.length} MEMBERS)',
                    style: TextStyle(
                        color: green,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8)),
                const Gap(10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < committee.members.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.colors.borderColor),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 22,
                            height: 22,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: green.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    color: green,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const Gap(8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(committee.members[i].name,
                                  style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                              Builder(builder: (_) {
                                final m = committee.members[i];
                                final bits = <String>[
                                  if (m.designation != null &&
                                      m.designation!.isNotEmpty)
                                    m.designation!,
                                  if (m.salaryNo != null &&
                                      m.salaryNo!.isNotEmpty)
                                    'Salary No. ${m.salaryNo}',
                                ];
                                if (bits.isEmpty)
                                  return const SizedBox.shrink();
                                return Text(bits.join(' · '),
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 11));
                              }),
                            ],
                          ),
                        ]),
                      ),
                  ],
                ),
                if (committee.note != null && committee.note!.isNotEmpty) ...[
                  const Gap(10),
                  Text(committee.note!,
                      style: TextStyle(
                          color: context.colors.textMuted, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TenderSaleHistoryDialog extends StatelessWidget {
  final ReTenderSaleInfo info;
  const _TenderSaleHistoryDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final sales = info.sales;
    return StyledFormDialog(
      label: 'Tender Sale History',
      title: info.forfeited.srNumber,
      headerAccentColor: context.colors.successGreen,
      icon: Icons.history_rounded,
      width: 540,
      child: StyledFormSection(
        title: 'Tendered ${info.tenderCount} time(s)',
        icon: Icons.gavel_rounded,
        children: [
          for (int i = 0; i < sales.length; i++)
            _saleCard(context, sales[i], i == 0),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }

  Widget _saleCard(BuildContext context, dynamic t, bool isLatest) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isLatest
                ? context.colors.primaryGold.withOpacity(0.5)
                : context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.gavel_rounded,
                size: 16, color: context.colors.primaryGold),
            const Gap(8),
            Text(t.saleNumber ?? 'No Number',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
            if (isLatest) ...[
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Latest',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const Gap(8),
          _kv(
              context,
              'Tender Close Date',
              t.saleDate != null
                  ? DateFormat('yyyy-MM-dd').format(t.saleDate!)
                  : '—'),
          if (t.saleEndTime != null)
            _kv(context, 'Tender Close Time', t.saleEndTime!),
          if (t.saleTime != null)
            _kv(context, 'Tender Start Time', t.saleTime!),
          if (t.createdByName != null)
            _kv(context, 'Created By', t.createdByName!),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(k,
              style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ── Tender bids (recorded on unsold packages) ─────────────────

/// Unsold-tenders "Valuation" cell: shows the LATEST tender re-valuation (blue,
/// tagged "re-valued") when the Valuation Directorate has set one for the
/// current round; otherwise the package's original valuation.
class _UnsoldValuationCell extends ConsumerWidget {
  final ReTenderSaleInfo info;
  final int? qty;

  /// True when the package can be re-tendered NOW — the "Re-valued" chip.
  /// The Valuation Directorate has priced the next tender, so that price is a
  /// live reserve and stays sealed.
  final bool reTenderable;
  const _UnsoldValuationCell(
      {required this.info, this.reTenderable = false, this.qty});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = info.forfeited;
    final revals =
        ref.watch(tenderRevaluationsProvider(f.id)).valueOrNull ?? const {};
    final committee = ref.watch(tenderCommitteesProvider).valueOrNull?[f.id];

    // A `tender_revaluations` row is the RESERVE PRICE OF THE ROUND IT IS
    // KEYED TO — proven against live data, see TenderHistorySection. So the
    // LATEST valuation is simply the newest round's own figure, and the only
    // question is whether that round has been tendered yet.
    final ordered = [...info.sales]..sort((a, b) {
        final am = a.saleMoment, bm = b.saleMoment;
        if (am == null || bm == null) return 0;
        return am.compareTo(bm);
      });

    double? unit;
    bool revalued = false;
    bool sealed = false;

    if (ordered.isEmpty) {
      unit = f.valuationCost;
    } else {
      // Sealed whenever a price exists for a tender that has NOT been held:
      //   * the newest round is still to run — its reserve is live; or
      //   * the package is re-tenderable ("Re-valued"): the Valuation
      //     Directorate has priced the next tender; or
      //   * a committee figure is set ("Committee valued") — a package leaves
      //     this table once its committee-priced tender has run, so while it
      //     is here that price is still to come.
      //
      // NOT "Awaiting ADG": re-valued but past Tender 3, so it cannot be
      // re-tendered until the committee and the ADG act. Nothing is pending
      // and the last concluded price is safe to show.
      sealed = !ordered.last.saleEnded ||
          reTenderable ||
          committee?.committeeValue != null;
      for (var i = ordered.length - 1; i >= 0; i--) {
        final own = revals[ordered[i].id]?.valuationCost;
        if (own != null) {
          unit = own;
          revalued = true;
          break;
        }
        // Round 1 carries no re-valuation — it ran at the original figure.
        if (i == 0) unit = f.valuationCost;
      }
    }

    return _ValuationCell(
      f: f,
      qty: qty,
      overrideUnitCost: unit,
      isRevalued: revalued,
      sealedUntilSale: sealed,
    );
  }
}

/// The newest tender re-valuation across all rounds of a package (by createdAt),
/// or null if none. Used to show the LATEST valuation in any table.
TenderRevaluationModel? _latestReval(Map<String, TenderRevaluationModel> m) {
  TenderRevaluationModel? best;
  for (final r in m.values) {
    if (best == null || r.createdAt.isAfter(best.createdAt)) best = r;
  }
  return best;
}

/// Valuation cell that surfaces the LATEST tender re-valuation for a package
/// (blue, "re-valued") when one exists, else the original valuation. Works for
/// any table that has a [ForfeitedPackageModel] (Unsold, Undestroyed, …).
class _LatestValuationCell extends ConsumerWidget {
  final ForfeitedPackageModel f;
  final int? qty;

  /// True while the goods sit in a sale round that has not yet run — the
  /// valuation is then a live reserve price. See [valuationSealed].
  final bool sealedUntilSale;
  const _LatestValuationCell(
      {required this.f, this.qty, this.sealedUntilSale = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revals =
        ref.watch(tenderRevaluationsProvider(f.id)).valueOrNull ?? const {};
    final reval = _latestReval(revals);
    return _ValuationCell(
      f: f,
      qty: qty,
      sealedUntilSale: sealedUntilSale,
      overrideUnitCost: reval?.valuationCost,
      isRevalued: reval != null,
    );
  }
}

/// A clickable "N×" attempts badge that opens the tender/destruction history
/// popup — merges the old "Times …" count column with the "…" history button.
class _AttemptsBadge extends StatelessWidget {
  final int count;
  final Color color;
  final VoidCallback onTap;
  const _AttemptsBadge(
      {required this.count, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'View history',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$count×',
                style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            const Gap(5),
            Icon(Icons.history_rounded, size: 14, color: color),
          ]),
        ),
      ),
    );
  }
}

/// Resolves whether this package's current round already carries a price —
/// either a Valuation Directorate re-valuation, or a committee value the ADG
/// has recorded but not yet submitted — and renders the chip accordingly.
class _ReTenderStatusCell extends ConsumerWidget {
  final ReTenderSaleInfo info;
  final bool eligible;
  const _ReTenderStatusCell({required this.info, required this.eligible});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fpId = info.forfeited.id;
    final current = info.latestSale?.id;

    final revals =
        ref.watch(tenderRevaluationsProvider(fpId)).valueOrNull ?? const {};
    final committees =
        ref.watch(tenderCommitteesProvider).valueOrNull ?? const {};

    // "Re-valued" means the NEXT round is priced — the PENDING row. A figure
    // on the current round is that round's own reserve, which every held round
    // has, so counting it showed "Re-valued" for packages the Valuation
    // Directorate had not yet acted on.
    final hasReval = revals[''] != null;
    // A committee value counts as "valued" even before the ADG submits it —
    // that is exactly the "Committee valued" state.
    final hasCommitteeValue = committees[fpId]?.committeeValue != null;

    return _ReTenderStatusChip(
        eligible: eligible,
        valued: hasReval || hasCommitteeValue,
        committeeValued: hasCommitteeValue);
  }
}

/// Re-tender status chip. FOUR states — a package can be valued but still not
/// re-tenderable, and "the committee has priced it" is NOT the same wait as
/// "nobody has priced it yet":
///   * valued + eligible            -> "Re-valued"        (green, ready)
///   * committee priced it, unsent  -> "Committee valued" (blue) — the ADG
///                                     still has to submit it as final
///   * valued, awaiting the ADG     -> "Awaiting ADG"     (blue)
///   * no valuation for the round   -> "Awaiting value"   (amber)
/// Showing `eligible` alone made committee packages that HAD a valuation read
/// as "Awaiting value"; showing "Awaiting ADG" for both committee states made
/// a priced package look identical to an unpriced one.
class _ReTenderStatusChip extends StatelessWidget {
  final bool eligible;

  /// The current round already carries a valuation (Valuation Directorate
  /// re-valuation, or a committee value the ADG has not submitted yet).
  final bool valued;

  /// The COMMITTEE has recorded its own figure; only the ADG's submission is
  /// outstanding. Distinguishes "priced, waiting to be sent" from "not priced".
  final bool committeeValued;
  const _ReTenderStatusChip(
      {required this.eligible,
      this.valued = false,
      this.committeeValued = false});

  @override
  Widget build(BuildContext context) {
    final green = context.colors.successGreen;
    final amber = context.colors.warningAmber;
    final blue = context.colors.accentLightBlue;
    // Valued but not yet re-tenderable == the committee's figure is waiting on
    // the ADG's submission.
    final awaitingAdg = !eligible && valued;
    final color = eligible ? green : (awaitingAdg ? blue : amber);
    final tip = eligible
        ? 'Priced for the next round — ready to re-tender.'
        : (awaitingAdg
            ? (committeeValued
                ? 'The tender committee has recorded its valuation. '
                    'Waiting for the ADG to submit it as the final price.'
                : 'Waiting for the ADG to submit the committee valuation.')
            : 'No valuation recorded for the current round yet.');
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              eligible
                  ? Icons.check_circle_rounded
                  : (awaitingAdg
                      ? (committeeValued
                          ? Icons.price_check_rounded
                          : Icons.how_to_reg_rounded)
                      : Icons.hourglass_bottom_rounded),
              size: 13,
              color: color),
          const Gap(5),
          Flexible(
            child: Text(
                eligible
                    ? 'Re-valued'
                    : (awaitingAdg
                        ? (committeeValued
                            ? 'Committee valued'
                            : 'Awaiting ADG')
                        : 'Awaiting value'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

/// Unsold-tenders "Bids" cell: shows the total recorded bid count across all
/// tender rounds (or a "+ Bids" prompt when empty), opens the entry form on tap.
class _BidsCell extends ConsumerWidget {
  final ReTenderSaleInfo info;
  const _BidsCell({required this.info});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final async = ref.watch(tenderBidsProvider(info.forfeited.id));
    // valueOrNull, NOT asData?.value: asData is null while the provider
    // re-fetches, so the count flips to 0 and back — the table then looks
    // like it is constantly refreshing.
    final count =
        async.valueOrNull?.values.fold<int>(0, (s, l) => s + l.length) ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog(
        context: context,
        builder: (_) => _EnterBidsDialog(info: info),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: green.withOpacity(count > 0 ? 0.14 : 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: green.withOpacity(count > 0 ? 0.5 : 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(count > 0 ? Icons.sell_rounded : Icons.add_rounded,
              size: 14, color: green),
          const Gap(4),
          Text(count > 0 ? '$count' : 'Bids',
              style: TextStyle(
                  color: green, fontWeight: FontWeight.w800, fontSize: 12)),
        ]),
      ),
    );
  }
}

/// Form to record the bid amounts for an unsold tender package, grouped by
/// tender ROUND (attempt). Past rounds are shown READ-ONLY (their bids were
/// already recorded); only the CURRENT (latest) round is editable — the
/// Add-button spawns more amount fields and Save writes just that round.
class _EnterBidsDialog extends ConsumerStatefulWidget {
  final ReTenderSaleInfo info;
  const _EnterBidsDialog({required this.info});

  @override
  ConsumerState<_EnterBidsDialog> createState() => _EnterBidsDialogState();
}

class _EnterBidsDialogState extends ConsumerState<_EnterBidsDialog> {
  // Editable controllers for the CURRENT (latest) round only.
  final _controllers = <TextEditingController>[];
  // Saved amounts of the earlier rounds, for read-only display (round id → amts).
  Map<String, List<double>> _past = const {};
  // Re-valuations the Valuation Directorate set, per round (read-only here).
  Map<String, TenderRevaluationModel> _revals = const {};
  bool _loading = true;
  bool _saving = false;

  // Tender rounds oldest→newest so they read as Tender 1, 2, 3…
  List<TenderSaleModel> get _rounds => [...widget.info.sales]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  TenderSaleModel get _current => _rounds.last;

  @override
  void initState() {
    super.initState();
    // The unsold row already watches tenderBidsProvider(fpId), so the bids are
    // usually cached — seed synchronously for an instant open. Fall back to a
    // fetch only when the cache is not yet populated.
    final cached =
        ref.read(tenderBidsProvider(widget.info.forfeited.id)).asData?.value;
    if (cached != null) {
      _seed(cached);
      _loading = false;
    } else {
      _load();
    }
    _loadRevals(); // async, non-blocking — the re-valuations are supplementary.
  }

  void _seed(Map<String, List<double>> saved) {
    _past = saved;
    final current = saved[_current.id] ?? const <double>[];
    for (final b in current) {
      _controllers.add(TextEditingController(
          text: b == b.roundToDouble() ? b.toInt().toString() : b.toString()));
    }
    if (_controllers.isEmpty) _controllers.add(TextEditingController());
  }

  Future<void> _load() async {
    Map<String, List<double>> saved = const {};
    try {
      saved = await ref
          .read(disposalServiceProvider)
          .getTenderBidsByRound(widget.info.forfeited.id);
    } catch (_) {}
    _seed(saved);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadRevals() async {
    try {
      final r = await ref
          .read(disposalServiceProvider)
          .getTenderRevaluationsByRound(widget.info.forfeited.id);
      if (mounted) setState(() => _revals = r);
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addRow() => setState(() => _controllers.add(TextEditingController()));

  void _removeRow(int i) => setState(() {
        _controllers.removeAt(i).dispose();
        if (_controllers.isEmpty) _controllers.add(TextEditingController());
      });

  Future<void> _save() async {
    setState(() => _saving = true);
    final fpId = widget.info.forfeited.id;
    final yard = widget.info.forfeited.yard;
    final amounts = <double>[];
    for (final c in _controllers) {
      final v = double.tryParse(c.text.trim());
      if (v != null && v > 0) amounts.add(v);
    }
    try {
      await ref
          .read(disposalServiceProvider)
          .saveTenderRoundBids(fpId, _current.id, amounts, yard: yard);
      ref.invalidate(tenderBidsProvider(fpId));
      ref.invalidate(packagesWithBidsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${amounts.length} bid(s) saved'),
          backgroundColor: context.colors.successGreen));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save bids: $e'),
          backgroundColor: context.colors.dangerRed));
    }
  }

  String _roundLabel(TenderSaleModel s, int attempt) {
    // Attempt 1 is the Valuation Tender (priced from the Pending Valuation, not
    // from bids); attempts 2-4 are Tender 1/2/3. Shared with the Valuation
    // portal via tenderRoundLabel so both read the same.
    final parts = <String>[tenderRoundLabel(attempt)];
    if (s.saleNumber != null && s.saleNumber!.isNotEmpty) {
      parts.add(s.saleNumber!);
    }
    if (s.saleDate != null) {
      parts.add(DateFormat('yyyy-MM-dd').format(s.saleDate!));
    }
    return parts.join(' · ');
  }

  // NumberFormat, not toString(): a raw double prints its binary artefacts
  // (e.g. 222272.63999999998 for 222272.64).
  String _fmt(double b) => b == b.roundToDouble()
      ? NumberFormat('#,##0').format(b)
      : NumberFormat('#,##0.00').format(b);

  // Forfeited quantity being valued (for the total).
  // Quantity valued — MUST match the Unsold table's Valuation cell
  // (_ValuationCell effQty) so the popup's "× qty" agrees with the table:
  // entryQty, else the matched item's qty, else the sum of all item quantities.
  int get _qty {
    final f = widget.info.forfeited;
    if (f.entryQty != null) return f.entryQty!;
    if (f.itemId != null) {
      final it =
          f.packageDetails?.items.where((i) => i.id == f.itemId).firstOrNull;
      if (it != null) return it.quantity;
    }
    return f.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 1;
  }

  // The valuation shown for a round. Tender 1 uses the ORIGINAL valuation (set
  // directly in the disposal request). Tender 2+ are re-tenders whose value is
  // decided ONLY by the Valuation Directorate after reviewing the prior round's
  // bids — so they show the tender re-valuation, or an amber "Awaiting" chip.
  Widget _revalLine(String roundId, int attempt) {
    final reval = _revals[roundId];
    // Tender 1 falls back to the original valuation; later rounds do NOT.
    final unit = reval?.valuationCost ??
        (attempt == 1 ? widget.info.forfeited.valuationCost : null);
    final isReval = reval != null;

    // Heading in the same style as the round header ("Tender N · CDU/TS…").
    Widget heading(String? tag) => Row(children: [
          Icon(Icons.price_change_rounded,
              size: 15, color: context.colors.primaryGold),
          const Gap(8),
          Text('Valuation',
              style: TextStyle(
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13)),
          if (tag != null) ...[
            const Gap(8),
            Text(tag,
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ]);

    if (unit == null) {
      final amber = context.colors.warningAmber;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading(null),
          const Gap(8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: amber.withOpacity(0.4)),
            ),
            child: Text('Awaiting Valuation Directorate',
                style: TextStyle(
                    color: amber, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const Gap(4),
          Text('Valuation reviews the bids, then sets a new value.',
              style: TextStyle(color: context.colors.textMuted, fontSize: 11)),
        ],
      );
    }
    final blue = context.colors.accentLightBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(isReval ? 'Re-valued' : null),
        const Gap(8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: blue.withOpacity(0.4)),
          ),
          child: RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: 'LKR ${_fmt(unit * _qty)}',
                  style: TextStyle(
                      color: blue, fontWeight: FontWeight.w800, fontSize: 13)),
              TextSpan(
                  text: '  (@ ${_fmt(unit)} × $_qty)',
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 11)),
            ]),
          ),
        ),
        if (reval?.note != null && reval!.note!.isNotEmpty) ...[
          const Gap(6),
          Text(reval.note!,
              style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
        ],
      ],
    );
  }

  // A locked, already-recorded earlier round.
  Widget _pastRoundCard(TenderSaleModel s, int attempt, List<double> amounts) {
    final muted = context.colors.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lock_outline_rounded, size: 15, color: muted),
            const Gap(8),
            Expanded(
              child: Text(_roundLabel(s, attempt),
                  style: TextStyle(
                      color: context.colors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
            Text('Recorded',
                style: TextStyle(
                    color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
          const Gap(12),
          // Valuation first (the value is decided before/at tendering) …
          _revalLine(s.id, attempt),
          const Gap(12),
          // … then the bids that came in for this round.
          Row(children: [
            Icon(Icons.sell_rounded,
                size: 15, color: context.colors.primaryGold),
            const Gap(8),
            Text('Bids',
                style: TextStyle(
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ]),
          const Gap(8),
          if (amounts.isEmpty)
            Text('No bids recorded',
                style: TextStyle(color: muted, fontSize: 12))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in amounts)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.colors.cardDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.colors.borderColor),
                    ),
                    child: Text('Rs. ${_fmt(b)}',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// The Top Management Directorate committee's figure for this package, if one exists.
  ///
  /// Past Tender 3 the price is no longer a Valuation Directorate decision — a
  /// committee inspects the goods and the ADG submits their figure. Central
  /// Disposal needs to see both the number and whether it is final, because
  /// the package only becomes re-tenderable once the ADG has submitted.
  /// The Valuation Directorate's price for the NEXT tender, once it has been
  /// set but before that tender is held.
  ///
  /// Central Disposal needs to know the package is priced and ready to
  /// re-tender, but the figure itself is a live reserve price — so this says a
  /// valuation exists and withholds it, exactly as [_committeeValueSection]
  /// does for the committee's.
  Widget _nextTenderValuationSection() {
    // For committee rounds (Tender 4+), the Valuation Directorate no longer
    // sets the price — the Top Management Committee does. Showing both sealed
    // messages is confusing, so hide this section for committee packages.
    if (_rounds.length > kMaxBidTenderRounds) return const SizedBox.shrink();

    final revals = ref
            .watch(tenderRevaluationsProvider(widget.info.forfeited.id))
            .valueOrNull ??
        const <String, TenderRevaluationModel>{};
    // A PENDING row (no round yet, key '') is a price for a tender that has
    // not been placed. A figure keyed to a round belongs to that round and is
    // already shown in the history above.
    if (revals[''] == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: StyledFormSection(
        gap: 0,
        title: 'Valuation Directorate · Next Tender',
        icon: Icons.price_change_rounded,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.surfaceDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.colors.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SealedValuation(),
                const Gap(6),
                Text(
                    'The Valuation Directorate has set the valuation for the '
                    'next tender. It is shown once that tender has been held.',
                    style: TextStyle(
                        fontSize: 11, color: context.colors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _committeeValueSection() {
    final c = ref
        .watch(tenderCommitteesProvider)
        .valueOrNull?[widget.info.forfeited.id];
    if (c == null || c.committeeValue == null) return const SizedBox.shrink();

    final submitted = c.submittedValue != null;
    final colour = submitted
        ? context.colors.successGreen
        : context.colors.accentLightBlue;
    final unit = c.submittedValue ?? c.committeeValue!;
    final total = unit * _qty;

    // The committee's figure is the price the package will be RE-TENDERED at,
    // so it is a reserve price like any other and stays sealed until that
    // round has actually run. Sealed both while the ADG has yet to submit it
    // and after submission but before the tender takes place — in either case
    // bidding at that price has not happened yet.
    final submittedAt = c.submittedAt;
    final priced = submittedAt != null &&
        widget.info.sales.any((x) {
          final m = x.saleMoment;
          return m != null && m.isAfter(submittedAt) && x.saleEnded;
        });
    if (!priced) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: StyledFormSection(
          gap: 0,
          title: 'Top Management Directorate Committee Valuation',
          icon: Icons.groups_rounded,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.colors.surfaceDark,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SealedValuation(),
                  const Gap(6),
                  Text(
                      submitted
                          ? 'The ADG has submitted the committee figure. It '
                              'is shown once the package has been re-tendered '
                              'at that price.'
                          : 'The committee has recorded a value. It is shown '
                              'once the ADG submits it and the package has '
                              'been re-tendered at that price.',
                      style: TextStyle(
                          fontSize: 11, color: context.colors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: StyledFormSection(
        gap: 0,
        title: 'Top Management Directorate Committee Valuation',
        icon: Icons.groups_rounded,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colour.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colour.withOpacity(0.4)),
            ),
            child: RichText(
              text: TextSpan(children: [
                TextSpan(
                    text: 'LKR ${_fmt(total)}',
                    style: TextStyle(
                        color: colour,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
                TextSpan(
                    text: '  (@ ${_fmt(unit)} × $_qty)',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 11)),
              ]),
            ),
          ),
          const Gap(8),
          Row(children: [
            Icon(
                submitted
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_bottom_rounded,
                size: 13,
                color: colour),
            const Gap(6),
            Expanded(
              child: Text(
                  submitted
                      ? 'Submitted by the ADG as the final valuation — the '
                          'package can now be re-tendered.'
                      : 'Recorded by the committee. Awaiting the ADG to submit '
                          'it as the final valuation.',
                  style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11,
                      height: 1.35)),
            ),
          ]),
          if (c.committeeNote?.trim().isNotEmpty == true) ...[
            const Gap(6),
            Text(c.committeeNote!.trim(),
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 11,
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  /// True once the Valuation Directorate has set this round's re-valuation,
  /// OR once the Top Management Directorate committee has valued the package.
  ///
  /// The valuation is decided BY reading these bids, so once it exists the bids
  /// are evidence for a decision already taken — editing them would leave the
  /// valuation resting on numbers that no longer exist. The round becomes
  /// read-only; the next round's bids go on the next round.
  /// Bids close once the Valuation Directorate has priced the NEXT round FROM
  /// them — that is the PENDING row (no round yet, key '').
  ///
  /// ⚠️ NOT `_revals[_current.id]`: that is this round's OWN reserve price,
  /// which exists from the moment the round is priced — i.e. BEFORE any bid is
  /// recorded against it. Locking on it stopped Central Disposal recording the
  /// round's bids at all.
  ///
  /// Committee valued also locks: once the committee has priced the goods the
  /// bids are evidence for a decision already taken and must not change.
  bool get _currentRoundLocked {
    if (_revals[''] != null) return true;
    final c = ref
        .read(tenderCommitteesProvider)
        .valueOrNull?[widget.info.forfeited.id];
    return c?.committeeValue != null;
  }

  /// The saved bids of a locked round, shown as read-only chips (highest first)
  /// — the same presentation a past round gets.
  Widget _lockedBidChips() {
    final amounts = [
      ..._controllers.map((c) => double.tryParse(c.text.trim()) ?? 0)
    ].where((a) => a > 0).toList()
      ..sort((a, b) => b.compareTo(a));
    if (amounts.isEmpty) {
      return Text('No bids recorded',
          style: TextStyle(color: context.colors.textMuted, fontSize: 12));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (int i = 0; i < amounts.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.colors.cardDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: i == 0
                      ? context.colors.successGreen.withOpacity(0.5)
                      : context.colors.borderColor),
            ),
            child: Text('Rs. ${_fmt(amounts[i])}',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
      ],
    );
  }

  /// Explains why the bids can no longer be edited.
  Widget _lockedNotice() {
    final blue = context.colors.accentLightBlue;
    // Pick the right explanation: committee-valued vs Valuation Directorate.
    final c = ref
        .read(tenderCommitteesProvider)
        .valueOrNull?[widget.info.forfeited.id];
    final isCommitteeLock =
        _revals[''] == null && c?.committeeValue != null;
    final message = isCommitteeLock
        ? 'The Top Management Directorate committee has valued this package, '
          'so the bids can no longer be changed.'
        : 'The Valuation Directorate has set this round’s valuation from '
          'these bids, so they can no longer be changed. Record the next '
          'round’s bids after the package is re-tendered.';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: blue.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: blue),
        const Gap(8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 11,
                height: 1.35),
          ),
        ),
      ]),
    );
  }

  Widget _bidField(int i, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 26,
          alignment: Alignment.center,
          child: Text('${i + 1}',
              style: TextStyle(
                  color: context.colors.textMuted,
                  fontWeight: FontWeight.w700)),
        ),
        const Gap(6),
        Expanded(
          child: TextField(
            controller: _controllers[i],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              prefixText: 'Rs. ',
              hintText: '0.00',
              filled: true,
              fillColor: context.colors.cardDark,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.colors.borderColor)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.colors.borderColor)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: accent, width: 1.4)),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded,
              size: 18, color: context.colors.textMuted),
          tooltip: 'Remove',
          onPressed: () => _removeRow(i),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.successGreen;
    final rounds = _rounds;
    final lastIdx = rounds.length - 1;
    return StyledFormDialog(
      label: 'Record Bids',
      title: widget.info.forfeited.srNumber,
      headerAccentColor: accent,
      icon: Icons.sell_rounded,
      width: 480,
      child: _loading
          ? Padding(
              padding: const EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(color: accent)))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Earlier rounds: read-only.
                for (int r = 0; r < lastIdx; r++)
                  _pastRoundCard(rounds[r], r + 1,
                      _past[rounds[r].id] ?? const <double>[]),
                // Current (latest) round. LOCKED once the Valuation Directorate
                // has priced it: the valuation is decided BY looking at these
                // bids, so changing them afterwards would invalidate it.
                StyledFormSection(
                  gap: 0,
                  title: _currentRoundLocked
                      ? '${_roundLabel(_current, rounds.length)} · Valued'
                      : '${_roundLabel(_current, rounds.length)} · Current',
                  icon: Icons.gavel_rounded,
                  children: [
                    // Valuation first (decided before/at tendering) …
                    _revalLine(_current.id, rounds.length),
                    const Gap(12),
                    // … then the bids for this round.
                    Row(children: [
                      Icon(Icons.sell_rounded, size: 15, color: accent),
                      const Gap(8),
                      Text('Bids',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ]),
                    const Gap(10),
                    if (_currentRoundLocked) ...[
                      // Read-only chips, same as a past round.
                      _lockedBidChips(),
                      const Gap(10),
                      _lockedNotice(),
                    ] else ...[
                      for (int i = 0; i < _controllers.length; i++)
                        _bidField(i, accent),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addRow,
                          icon:
                              Icon(Icons.add_rounded, size: 18, color: accent),
                          label: Text('Add bid',
                              style: TextStyle(
                                  color: accent, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ],
                ),
                // The Valuation Directorate's figure for the NEXT tender,
                // once one exists — sealed, like the committee block below.
                _nextTenderValuationSection(),
                // The Top Management Directorate committee's figure, once one exists.
                _committeeValueSection(),
              ],
            ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text(_currentRoundLocked ? 'Close' : 'Cancel')),
        if (!_currentRoundLocked)
          FilledButton(
            onPressed: (_loading || _saving) ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save Bids'),
          ),
      ],
    );
  }
}

// ── Destructions ──────────────────────────────────────────────

class _DestructionsTab extends ConsumerWidget {
  const _DestructionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final sales = ref.watch(destructionsProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Destruction Sales',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const DisposalSearch(
                tabKey: 'destructions', hint: 'Search sale no / SR…'),
            const Gap(12),
            YardAllFilter(
              value: ref.watch(disposalYardFilterProvider('destructions')),
              onChanged: (v) => ref
                  .read(disposalYardFilterProvider('destructions').notifier)
                  .state = v,
            ),
            const Gap(12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: green, foregroundColor: Colors.white),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Destruction Sale',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => const _DestructionFormDialog()),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(16),
          Expanded(
            child: sales.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.refresh(destructionsProvider)),
              data: (list) {
                final q = ref
                    .watch(disposalSearchProvider('destructions'))
                    .toLowerCase();
                final yf =
                    ref.watch(disposalYardFilterProvider('destructions'));
                // Hide sales with no actionable rows left: every item destroyed
                // (fully consumed), OR the destroy window has closed (the
                // un-destroyed items have dropped to the Undestroyed pool).
                var visible = list.where((s) {
                  final hasPending = s.items.any((i) => !i.destroyed);
                  if (!hasPending) return false;
                  final windowClosed = s.unsoldDeadline != null &&
                      DateTime.now().isAfter(s.unsoldDeadline!);
                  return !windowClosed;
                }).toList();
                if (yf != null) {
                  // Same reasoning as Tender Sales: match per item, not on the
                  // sale's own yard, since a multi-directorate yard's items
                  // can carry different SR-number prefixes within one sale.
                  visible = visible
                      .where((s) => s.items.any((i) => matchesYardFilter(
                          yf, i.yard, i.forfeited?.srNumber ?? '')))
                      .toList();
                }
                if (q.isNotEmpty) {
                  visible = visible
                      .where((s) =>
                          (s.saleNumber ?? '').toLowerCase().contains(q) ||
                          s.items.any((i) =>
                              (i.forfeited?.srNumber ?? '')
                                  .toLowerCase()
                                  .contains(q) ||
                              (i.forfeited?.consigneeName ?? '')
                                  .toLowerCase()
                                  .contains(q)))
                      .toList();
                }
                if (visible.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        icon: Icons.local_fire_department_outlined,
                        message: 'No active destruction sales',
                        subtitle:
                            'Create a destruction sale, or check the Undestroyed tab for items whose window has closed.'),
                  );
                }
                // Detect re-destructions against ALL sales (the earlier sale's
                // window may have closed and dropped out of `visible`).
                final retenderIds = retenderDestructionIds(list);
                return ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, i) => DestructionCard(
                      sale: visible[i],
                      isRetender: retenderIds.contains(visible[i].id)),
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Destruction Sale card (header + per-item detail table + Mark Destroyed) ─────────

class _DestRow {
  final DestructionItemModel saleItem;
  final PackageItem? item;
  final String warehouse;
  const _DestRow(this.saleItem, this.item, this.warehouse);
}

class DestructionCard extends ConsumerWidget {
  final DestructionModel sale;

  /// Yard view-only mode: hides the countdown timer, never drops rows when the
  /// window closes, and disables Mark Destroyed (those are the directorate's).
  final bool readOnly;

  /// True when this destruction re-schedules an item left undestroyed by an
  /// earlier destruction sale — shown as a "Re-tender" badge in the header.
  final bool isRetender;
  const DestructionCard(
      {required this.sale, this.readOnly = false, this.isRetender = false});

  String _warehouseFor(PackageModel? pkg, String itemId) {
    if (pkg == null) return '—';
    final entries = pkg.warehouseEntries
        .where((e) => e.packageItemId == itemId)
        .toList()
      ..sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
    if (entries.isEmpty) return '—';
    final w = entries.first;
    return w.zone != null && w.zone!.isNotEmpty
        ? '${w.warehouseName} · ${w.zone}'
        : w.warehouseName;
  }

  List<_DestRow> _rows() {
    final rows = <_DestRow>[];
    // Once the destroy window has CLOSED, items NOT yet destroyed have moved to
    // the Undestroyed pool — they must leave this page too (only destroyed ones
    // remain visible there, on the Destroyed Packages page). While the window is
    // open, un-destroyed items stay here so they can be marked. The yard's
    // read-only view keeps EVERY item (sold/unsold) so it can always be seen.
    final windowClosed = !readOnly &&
        sale.unsoldDeadline != null &&
        DateTime.now().isAfter(sale.unsoldDeadline!);
    // Destroyed items leave the Destruction Sales page (they move to Destroyed
    // Packages) — but stay on the yard's read-only view as the full outcome.
    final source =
        readOnly ? sale.items : sale.items.where((s) => !s.destroyed);
    for (final si in source) {
      if (windowClosed) continue; // dropped to Undestroyed
      final pkg = si.forfeited?.packageDetails;
      final pkgItems = pkg?.items ?? const [];
      final fpItemId = si.forfeited?.itemId;
      if (pkgItems.isEmpty) {
        rows.add(_DestRow(si, null, '—'));
      } else if (fpItemId != null) {
        // Per-item FP row — show only the specific item it refers to.
        final match = pkgItems.where((i) => i.id == fpItemId).firstOrNull;
        rows.add(_DestRow(
            si, match, match != null ? _warehouseFor(pkg, match.id) : '—'));
      } else {
        // Package-level FP row — show one row per package item (legacy data).
        for (final it in pkgItems) {
          rows.add(_DestRow(si, it, _warehouseFor(pkg, it.id)));
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final storageRate = ref.watch(storageRateProvider).valueOrNull ?? const {};
    final rows = _rows();
    // Central Disposal: no actionable rows left (all destroyed, or window closed
    // and items moved to Undestroyed) → drop the whole card. The yard read-only
    // view keeps the card to show the full outcome.
    if (!readOnly && rows.isEmpty) return const SizedBox.shrink();
    final total = sale.items.length;
    final destroyed = sale.destroyedCount;
    final allDestroyed = total > 0 && destroyed == total;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: allDestroyed
                ? green.withOpacity(0.4)
                : context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.receipt_long_rounded, color: green, size: 20),
              ),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                            sale.saleNumber?.isNotEmpty == true
                                ? sale.saleNumber!
                                : 'Destruction Sale',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                      ),
                      if (isRetender) ...[
                        const Gap(8),
                        _retenderBadge(context, label: 'Re-destruction'),
                      ],
                    ]),
                    const Gap(2),
                    Row(children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 12, color: context.colors.textMuted),
                      const Gap(4),
                      Text(
                          sale.saleDate != null
                              ? DateFormat('yyyy-MM-dd').format(sale.saleDate!)
                              : '—',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12)),
                      const Gap(12),
                      Flexible(
                        child: Text(sale.typeLabel,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textMuted, fontSize: 12)),
                      ),
                    ]),
                    // Live "Destroy within" countdown to the undestroyed deadline
                    // — once it closes, remaining items drop to Undestroyed.
                    // Central Disposal only — the yard read-only view hides it.
                    if (!readOnly &&
                        !allDestroyed &&
                        sale.unsoldDeadline != null) ...[
                      const Gap(6),
                      _DeadlineCountdown(
                          deadline: sale.unsoldDeadline,
                          label: 'Destroy within'),
                    ],
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (allDestroyed ? green : context.colors.warningAmber)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          (allDestroyed ? green : context.colors.warningAmber)
                              .withOpacity(0.4)),
                ),
                child: Text(
                  total == 0 ? 'No packages' : '$destroyed / $total destroyed',
                  style: TextStyle(
                      color: allDestroyed ? green : context.colors.warningAmber,
                      fontWeight: FontWeight.w700,
                      fontSize: 12),
                ),
              ),
            ]),
          ),
          Divider(height: 1, color: context.colors.borderColor),
          // Items table
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: (rows.length * 48.0 + 56).clamp(115, 380),
              decoration: BoxDecoration(
                border: Border.all(color: context.colors.borderColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: DataTable2(
                  columnSpacing: 10,
                  horizontalMargin: 12,
                  fixedTopRows: 1,
                  minWidth: 1280,
                  headingRowColor: _headingColor(context),
                  empty: const EmptyTableState(
                      message: 'No packages in this sale'),
                  columns: [
                    DataColumn2(label: Text('SR Number'), size: ColumnSize.S, fixedWidth: 135),
                    DataColumn2(label: Text('Case No'), size: ColumnSize.S, fixedWidth: 130),
                    DataColumn2(label: Text('Goods Name'), size: ColumnSize.L),
                    DataColumn2(
                        label: Center(child: Text('Source')),
                        size: ColumnSize.S,
                        fixedWidth: 65),
                    DataColumn2(
                        label: Center(child: Text('Qty')),
                        size: ColumnSize.S,
                        fixedWidth: 50),
                    DataColumn2(label: Text('Reason'), size: ColumnSize.M),
                    DataColumn2(label: Text('Location'), size: ColumnSize.M),
                    // Yard shows the SR item Value; Central shows the valuation.
                    DataColumn2(
                        label: Center(child: const Text('Latest Valuation')),
                        size: ColumnSize.S,
                        fixedWidth: 140),
                    DataColumn2(
                        label: Center(child: Text('Status')),
                        size: ColumnSize.M,
                        fixedWidth: 235),
                    DataColumn2(
                        label: Center(child: Text('Details')),
                        size: ColumnSize.S,
                        fixedWidth: 55),
                  ],
                  rows: rows.map((r) {
                    final f = r.saleItem.forfeited;
                    final pkg = f?.packageDetails;
                    return DataRow(cells: [
                      DataCell(TooltipText(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(TooltipText(pkg?.caseNumber ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(TooltipText(
                          r.item?.itemName ?? 'Multiple/Unspecified',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Center(child: _sourceChip(context, f?.source))),
                      DataCell(Center(
                          child: Text(
                              '${f?.entryQty ?? r.item?.quantity ?? '—'}'))),
                      DataCell(Builder(builder: (_) {
                        final reason = _forfeitReasonText(r.item, f);
                        return Tooltip(
                          message: reason,
                          child: Text(reason.isNotEmpty ? reason : '—',
                              overflow: TextOverflow.ellipsis),
                        );
                      })),
                      DataCell(TooltipText(
                          '${yardName(r.saleItem.yard)} / ${r.warehouse}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12))),
                      DataCell(Center(
                          child: _ValuationCell(
                        f: f,
                        useItemValue: readOnly,
                        // Hidden until the destruction sale has actually run —
                        // same rule as the tender sale card.
                        sealedUntilSale: !sale.saleEnded,
                        qty: f?.entryQty ?? r.item?.quantity,
                      ))),
                      DataCell(Center(
                        child: r.saleItem.destroyed
                            ? _statusChipWidget(context, 'Destroyed',
                                Icons.check_circle_rounded, green)
                            : (() {
                                final deadline = sale.unsoldDeadline;
                                final isUndestroyed = r.saleItem.undestroyed ||
                                    (deadline != null &&
                                        DateTime.now().isAfter(deadline));
                                if (isUndestroyed) {
                                  return _statusChipWidget(
                                      context,
                                      'Undestroyed',
                                      Icons.cancel_outlined,
                                      context.colors.dangerRed);
                                }
                                if (readOnly) {
                                  return _statusChipWidget(
                                      context,
                                      'Pending',
                                      Icons.schedule_rounded,
                                      context.colors.warningAmber);
                                }
                                final canDestroy = sale.saleTimePassed;
                                final btnRow = FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: green,
                                          backgroundColor:
                                              green.withOpacity(0.08),
                                          side: BorderSide(
                                              color: green.withOpacity(0.5)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 5),
                                          minimumSize: const Size(0, 31),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(7.5),
                                          ),
                                        ),
                                        icon: const Icon(Icons.sell_rounded,
                                            size: 13),
                                        label: const Text('Mark Destroyed',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                        onPressed: canDestroy
                                            ? () => _markDestroyed(
                                                context, ref, r.saleItem)
                                            : null,
                                      ),
                                      const Gap(6),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              context.colors.dangerRed,
                                          backgroundColor: context
                                              .colors.dangerRed
                                              .withOpacity(0.08),
                                          side: BorderSide(
                                              color: context.colors.dangerRed
                                                  .withOpacity(0.5)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 9, vertical: 5),
                                          minimumSize: const Size(0, 31),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(7.5),
                                          ),
                                        ),
                                        icon: const Icon(
                                            Icons.cancel_outlined,
                                            size: 13),
                                        label: const Text('Mark Undestroyed',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                        onPressed: canDestroy
                                            ? () => _markUndestroyed(context,
                                                ref, r.saleItem, f?.srNumber)
                                            : null,
                                      ),
                                    ],
                                  ),
                                );
                                return canDestroy
                                    ? btnRow
                                    : Tooltip(
                                        message: _destroyLockMessage(sale),
                                        child: btnRow);
                              }()),
                      )),
                      DataCell(Center(
                        child: pkg != null
                            ? IconButton(
                                icon: Icon(Icons.info_outline_rounded,
                                    color: context.colors.accentLightBlue,
                                    size: 18),
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => PackageDetailsDialog(
                                    package: pkg,
                                    storageRate: storageRate,
                                    // Yard (read-only) uses the default blue
                                    // header like Forfeited; Central keeps green.
                                    headerAccentColor: readOnly ? null : green,
                                    useLegacySummary: true,
                                    highlightItemId: f?.itemId,
                                    yardLabel: yardName(r.saleItem.yard),
                                    // Valuation price is a Central-Disposal-only
                                    // figure — never shown in the yard (readOnly)
                                    // view. Passing null hides the popup's
                                    // Valuation section for yards.
                                    valuationUnitCost:
                                        readOnly ? null : f?.valuationCost,
                                    valuationTotalCost:
                                        (!readOnly && f?.valuationCost != null)
                                            ? f!.valuationCost! *
                                                (f.entryQty ??
                                                    r.item?.quantity ??
                                                    1)
                                            : null,
                                    valuationQty: readOnly
                                        ? null
                                        : (f?.entryQty ?? r.item?.quantity),
                                    // Sealed until the destruction sale runs.
                                    valuationSealedUntilSale:
                                        !readOnly && !sale.saleEnded,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tooltip shown on a disabled Mark Destroyed button — tells the officer when
  /// the scheduled destruction moment unlocks the action.
  String _destroyLockMessage(DestructionModel sale) {
    final moment = sale.saleMoment;
    if (moment == null) return 'No destruction date set yet';
    final when = DateFormat('yyyy-MM-dd HH:mm').format(moment);
    return 'Available after the scheduled destruction time ($when)';
  }

  void _markDestroyed(
      BuildContext context, WidgetRef ref, DestructionItemModel item) {
    showDialog(
      context: context,
      builder: (ctx) => _MarkDestroyedDialog(item: item, ref: ref),
    );
  }

  Future<void> _markUndestroyed(BuildContext context, WidgetRef ref,
      DestructionItemModel item, String? srNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.colors.borderColor),
        ),
        title: Row(children: [
          Icon(Icons.cancel_outlined,
              color: context.colors.dangerRed, size: 20),
          const Gap(10),
          Text('Mark as Undestroyed',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Mark ${srNumber ?? 'this package'} as Undestroyed? It will be moved to the Undestroyed page.',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: context.colors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.dangerRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Undestroyed'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(disposalServiceProvider)
          .markDestructionItemUndestroyed(destructionItemId: item.id);
      ref.read(destructionsRefreshProvider.notifier).trigger();
      ref.invalidate(undestroyedDestructionsProvider);
      if (context.mounted) {
        DefaultTabController.of(context).animateTo(12);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${srNumber ?? 'Package'} marked as Undestroyed — moved to Undestroyed'),
          backgroundColor: context.colors.dangerRed,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: context.colors.dangerRed,
        ));
      }
    }
  }
}

class _MarkDestroyedDialog extends StatefulWidget {
  final DestructionItemModel item;
  final WidgetRef ref;
  const _MarkDestroyedDialog({required this.item, required this.ref});
  @override
  State<_MarkDestroyedDialog> createState() => _MarkDestroyedDialogState();
}

class _MarkDestroyedDialogState extends State<_MarkDestroyedDialog> {
  final _receiptC = TextEditingController();
  final _notesC = TextEditingController();
  final _priceC = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _receiptC.dispose();
    _notesC.dispose();
    _priceC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StyledFormDialog(
      label: 'Destruction',
      title: 'Mark Package Destroyed',
      headerAccentColor: context.colors.successGreen,
      icon: Icons.delete_forever_rounded,
      width: 460,
      child: StyledFormSection(
        title: 'Destruction Confirmation',
        icon: Icons.delete_forever_rounded,
        children: [
          Text(
            '${widget.item.forfeited?.srNumber ?? 'Package'} — ${yardName(widget.item.yard)}. '
            'This records the package as DESTROYED.',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          ),
          // Order: Receipt No → Price → Notes. Receipt No + Price required.
          TextField(
            controller: _receiptC,
            decoration: const InputDecoration(labelText: 'Receipt No *'),
          ),
          const Gap(16),
          // Destruction records a price only — no taxes (unlike a tender sale).
          TextField(
            controller: _priceC,
            decoration: const InputDecoration(
                labelText: 'Destruction Price *', prefixText: 'Rs '),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const Gap(16),
          TextField(
            controller: _notesC,
            maxLines: 3,
            minLines: 2,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (_error != null) ...[
            const Gap(12),
            Text(_error!,
                style:
                    TextStyle(color: context.colors.dangerRed, fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        StyledDialogPrimaryButton(
          labelText: 'Confirm Destroyed',
          icon: Icons.check_circle_rounded,
          loading: _loading,
          onPressed: () async {
            // Receipt No and Destruction Price are mandatory; Notes optional.
            // Parse the price fresh from the field (the build-time value is
            // stale — the field has no onChanged, so it never rebuilt).
            final receiptNo = _receiptC.text.trim();
            final notes = _notesC.text.trim();
            final enteredPrice = double.tryParse(_priceC.text.trim()) ?? 0.0;
            if (receiptNo.isEmpty) {
              setState(() => _error = 'Receipt No is required.');
              return;
            }
            if (_priceC.text.trim().isEmpty || enteredPrice <= 0) {
              setState(() => _error = 'Enter a valid Destruction Price.');
              return;
            }
            setState(() {
              _error = null;
              _loading = true;
            });
            try {
              await widget.ref
                  .read(disposalServiceProvider)
                  .markDestructionItemDestroyed(
                    destructionItemId: widget.item.id,
                    // Notes appended only when provided.
                    receipt: notes.isEmpty
                        ? 'Receipt No: $receiptNo'
                        : 'Receipt No: $receiptNo | Notes: $notes',
                    destroyedPrice: enteredPrice,
                  );
              widget.ref.read(destructionsRefreshProvider.notifier).trigger();
              widget.ref
                  .read(packagesRefreshTriggerProvider.notifier)
                  .trigger();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Package marked destroyed'),
                  backgroundColor: context.colors.successGreen,
                ));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(_appealHoldMessage(e)),
                  backgroundColor: context.colors.dangerRed,
                ));
              }
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
        ),
      ],
    );
  }
}

// ── New Destruction Sale form (details + Sale-only package picker) ─────────────

class _DestructionFormDialog extends ConsumerStatefulWidget {
  /// In [reDestruction] mode the package pool is the undestroyed destruction-sale packages
  /// (not fresh "Sale" requests) — used by the Undestroyed Destructions page.
  final bool reDestruction;
  const _DestructionFormDialog({this.reDestruction = false});
  @override
  ConsumerState<_DestructionFormDialog> createState() =>
      _DestructionFormDialogState();
}

class _DestructionFormDialogState
    extends ConsumerState<_DestructionFormDialog> {
  final _numberC = TextEditingController();
  final _serialC = TextEditingController();
  final _yearC = TextEditingController(text: DateTime.now().year.toString());
  DateTime? _saleDate;
  TimeOfDay? _saleTime;

  /// When bidding CLOSES. The valuation unseals only after this.
  TimeOfDay? _saleEndTime;
  String? _destructionType;
  bool _loading = false;
  String? _error;
  // forfeited_package_id → yard
  final Map<String, String> _selected = {};
  // The yard this destruction belongs to. The package pool is filtered to this
  // yard's forwarded requests, and the created destruction is assigned to it.
  late String _formYard;

  String? _validate() {
    if (_saleDate == null) return 'Destruction Sale Date is required.';
    if (_saleTime == null) return 'Sale Start Time is required.';
    // The end time is what unseals the valuation, so it has to be real: an
    // end at or before the start would unseal the reserve price immediately.
    if (_saleEndTime == null) return 'Sale End Time is required.';
    final startM = _saleTime!.hour * 60 + _saleTime!.minute;
    final endM = _saleEndTime!.hour * 60 + _saleEndTime!.minute;
    if (endM <= startM) return 'Sale End Time must be after the start time.';
    if (_destructionType == null || _destructionType!.isEmpty)
      return 'Destruction Sale Type is required.';
    if (_selected.isEmpty) return 'Select at least one package.';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _formYard = ref.read(disposalSelectedYardProvider);
    _yearC.addListener(_onYearChanged);
    _serialC.addListener(_updateSaleNumber);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSerialForYear();
    });
  }

  @override
  void dispose() {
    _yearC.removeListener(_onYearChanged);
    _serialC.removeListener(_updateSaleNumber);
    _numberC.dispose();
    _serialC.dispose();
    _yearC.dispose();
    super.dispose();
  }

  void _onYearChanged() {
    if (_yearC.text.length == 4) {
      _loadSerialForYear();
    }
  }

  Future<void> _loadSerialForYear() async {
    final year = int.tryParse(_yearC.text);
    if (year == null) return;
    try {
      // Serial runs per-yard: GL1's 6th destruction is serial 6 even if GL2 has 3.
      final nextSerial = await ref
          .read(disposalServiceProvider)
          .getNextDestructionSerial(year, yard: _formYard);
      if (mounted) {
        _serialC.text = nextSerial.toString();
        _updateSaleNumber();
      }
    } catch (e) {
      // ignore
    }
  }

  void _updateSaleNumber() {
    final year = _yearC.text;
    final serial = _serialC.text;
    if (year.isEmpty || serial.isEmpty) return;

    String saleNum = 'CDU/TS/$year/$serial';
    if (_destructionType == 'special') {
      saleNum += '(Special)';
    }
    _numberC.text = saleNum;
  }

  String _summary(DisposalRequestItemModel it) {
    final pkgItems = it.forfeited?.packageDetails?.items ?? const [];
    if (pkgItems.isEmpty) return 'Multiple/Unspecified';
    final itemId = it.forfeited?.itemId;
    if (itemId != null) {
      final match = pkgItems.where((i) => i.id == itemId).firstOrNull;
      if (match != null) return match.itemName;
    }
    if (pkgItems.length == 1) return pkgItems.first.itemName;
    return '${pkgItems.first.itemName} +${pkgItems.length - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final green = context.colors.successGreen;
    // Fresh destruction → "Destruction"-tagged requests. Re-destruction → only
    // the undestroyed packages shown on the Undestroyed Destructions page.
    // Either way, only the packages belonging to the yard selected in this form
    // are shown (and destroyed).
    final AsyncValue<List<DisposalRequestItemModel>> pool = (widget
                .reDestruction
            ? ref.watch(undestroyedDestructionsProvider).whenData((list) => list
                .map((info) => DisposalRequestItemModel(
                      id: info.forfeited.id,
                      requestId: '',
                      forfeitedPackageId: info.forfeited.id,
                      disposition: 'destruction',
                      forfeited: info.forfeited,
                    ))
                .toList())
            : ref.watch(destructionRequestItemsProvider))
        .whenData((list) =>
            list.where((it) => it.forfeited?.yard == _formYard).toList());
    return StyledFormDialog(
      label: 'Destruction Sale',
      title:
          widget.reDestruction ? 'Re-destruction Sale' : 'New Destruction Sale',
      headerAccentColor: context.colors.successGreen,
      icon: Icons.gavel_rounded,
      width: 720,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.dangerRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: context.colors.dangerRed.withOpacity(0.4)),
              ),
              child: Row(children: [
                Icon(Icons.error_outline,
                    color: context.colors.dangerRed, size: 18),
                const Gap(10),
                Expanded(
                    child: Text(_error!,
                        style: TextStyle(
                            color: context.colors.dangerRed, fontSize: 13))),
              ]),
            ),
            const Gap(12),
          ],
          StyledFormSection(
            title: 'Sale Details',
            icon: Icons.receipt_long_rounded,
            children: [
              _StyledYardPicker(
                value: _formYard,
                width: double.infinity,
                yards: ref.watch(yardsProvider).valueOrNull
                        ?.where((y) => y.isActive)
                        .toList() ??
                    [for (final y in kYards) YardModel(code: y.code, name: y.name, srPrefix: y.srPrefix)],
                onChanged: (v) {
                  if (v == null) return;
                  // Switching yards clears any selection from the previous yard
                  // and reloads the serial scoped to the newly selected yard.
                  setState(() {
                    _formYard = v;
                    _selected.clear();
                  });
                  _loadSerialForYear();
                },
              ),
              TextField(
                controller: _numberC,
                readOnly: true,
                decoration:
                    const InputDecoration(labelText: 'Destruction Sale Number'),
              ),
              Row(children: [
                Expanded(
                  child: _OneTapDateField(
                    label: 'Destruction Sale Date',
                    value: _saleDate,
                    onChanged: (d) => setState(() => _saleDate = d),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _OneTapTimeField(
                    label: 'Sale Start Time',
                    value: _saleTime,
                    onChanged: (t) => setState(() => _saleTime = t),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: _OneTapTimeField(
                    // Bidding CLOSES here. The valuation is the reserve price,
                    // so it stays sealed until this passes — not merely until
                    // the sale opens.
                    label: 'Sale End Time',
                    value: _saleEndTime,
                    onChanged: (t) => setState(() => _saleEndTime = t),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: TextField(
                    controller: _serialC,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Serial'),
                  ),
                ),
              ]),
              TextField(
                controller: _yearC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Year'),
              ),
              StyledDropdownFormField<String>(
                value: _destructionType,
                label: 'Destruction Sale Type',
                helperText: null,
                isDense: true,
                menuWidth: 400,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                options: [
                  for (final e in kDestructionTypes.entries)
                    StyledDropdownOption(e.key, e.value),
                ],
                onChanged: (v) {
                  setState(() => _destructionType = v);
                  _updateSaleNumber();
                },
              ),
            ],
          ),
          const Gap(16),
          StyledFormSection(
            title: 'Select Packages — for Sale (${_selected.length} selected)',
            icon: Icons.inventory_2_rounded,
            children: [
              pool.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.refresh(widget.reDestruction
                        ? undestroyedDestructionsProvider
                        : destructionRequestItemsProvider)),
                data: (items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'No "Destruction" packages awaiting a destruction sale.\n'
                          'Yards mark packages for Destruction in a Disposal Request.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.textSecondary),
                        ),
                      ),
                    );
                  }
                  // Items already covered by a dedicated per-item row (correct
                  // partial qty) — a package-level row must not re-expand them
                  // at the full registered qty.
                  final perItemKeys = <String>{};
                  for (final it in items) {
                    final iid = it.forfeited?.itemId;
                    final pid = it.forfeited?.packageId;
                    if (iid != null && pid != null) {
                      perItemKeys.add('$pid:$iid');
                    }
                  }
                  // Expand package-level DR items (itemId==null, multiple pkg
                  // items) so each item appears as its own selectable row.
                  final rows =
                      <({DisposalRequestItemModel it, PackageItem? pkgItem})>[];
                  for (final it in items) {
                    final fpItems =
                        it.forfeited?.packageDetails?.items ?? const [];
                    final pid = it.forfeited?.packageId;
                    if (it.forfeited?.itemId == null && fpItems.length > 1) {
                      for (final pkgItem in fpItems) {
                        if (pid != null &&
                            perItemKeys.contains('$pid:${pkgItem.id}')) {
                          continue;
                        }
                        rows.add((it: it, pkgItem: pkgItem));
                      }
                    } else {
                      rows.add((it: it, pkgItem: null));
                    }
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SelectAllBar(
                        selectedCount: _selected.length,
                        totalCount: rows.length,
                        onSelectAll: () => setState(() {
                          for (final r in rows) {
                            final rowKey = r.pkgItem != null
                                ? '${r.it.id}_${r.pkgItem!.id}'
                                : r.it.id;
                            _selected[rowKey] = r.it.forfeited?.yard ?? '';
                          }
                        }),
                        onClearAll: () => setState(_selected.clear),
                      ),
                      const Gap(8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color:
                                  context.colors.borderColor.withOpacity(0.5)),
                          itemBuilder: (context, i) {
                            final r = rows[i];
                            final it = r.it;
                            final pkgItem = r.pkgItem;
                            final rowKey = pkgItem != null
                                ? '${it.id}_${pkgItem.id}'
                                : it.id;
                            final yard = it.forfeited?.yard ?? '';
                            final selected = _selected.containsKey(rowKey);
                            final displayName =
                                pkgItem?.itemName ?? _summary(it);
                            // Show the forfeited quantity (e.g. 6 of 10).
                            final qty = _disposalForfeitedQty(it, pkgItem) ??
                                (pkgItem != null
                                    ? pkgItem.quantity
                                    : it.totalQuantity);
                            return InkWell(
                              onTap: () => setState(() {
                                if (selected) {
                                  _selected.remove(rowKey);
                                } else {
                                  _selected[rowKey] = yard;
                                }
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 6),
                                child: Row(children: [
                                  Checkbox(
                                    activeColor: green,
                                    value: selected,
                                    onChanged: (_) => setState(() {
                                      if (selected) {
                                        _selected.remove(rowKey);
                                      } else {
                                        _selected[rowKey] = yard;
                                      }
                                    }),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Flexible(
                                            child: Text(
                                                it.forfeited?.srNumber ?? '—',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: context.colors
                                                        .accentLightBlue)),
                                          ),
                                          const Gap(8),
                                          _SourceChip(
                                              source: it.forfeited?.source ??
                                                  'forfeit'),
                                        ]),
                                        Text(displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: context
                                                    .colors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                        it.forfeited?.consigneeName ?? '—',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: context.colors.textPrimary)),
                                  ),
                                  const Gap(10),
                                  Text('Qty $qty',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: context.colors.textMuted)),
                                  const Gap(8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: green.withOpacity(0.3)),
                                    ),
                                    child: Text(yardName(yard),
                                        style: TextStyle(
                                            color: green,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        StyledDialogPrimaryButton(
          labelText: 'Save Destruction Sale',
          icon: Icons.save_rounded,
          loading: _loading,
          onPressed: () async {
            final err = _validate();
            if (err != null) {
              setState(() => _error = err);
              return;
            }
            setState(() {
              _loading = true;
              _error = null;
            });
            // Build forfeitedPackageId→yard map from _selected keys.
            // Keys are either plain it.id or "${it.id}_${pkgItem.id}" for
            // expanded per-item rows — both cases point to the same
            // forfeitedPackageId on the DR item.
            // Re-destruction picks from the UNDESTROYED pool (mapped the same way
            // the form builds its rows); a fresh destruction from the request
            // pool. Wrong pool left packageYards empty so nothing moved sales.
            final allDrItems = widget.reDestruction
                ? (ref.read(undestroyedDestructionsProvider).valueOrNull ??
                        const [])
                    .map((info) => DisposalRequestItemModel(
                          id: info.forfeited.id,
                          requestId: '',
                          forfeitedPackageId: info.forfeited.id,
                          disposition: 'destruction',
                          forfeited: info.forfeited,
                        ))
                    .toList()
                : (ref.read(destructionRequestItemsProvider).valueOrNull ??
                    const []);
            final packageYards = <String, String>{};
            // forfeited_package_id → the specific package_item id it covers, so
            // the destruction row is item-scoped (Mark Destroyed destroys only
            // that item, not the whole package).
            final packageItems = <String, String?>{};
            for (final key in _selected.keys) {
              final drItemId = key.contains('_') ? key.split('_').first : key;
              final drItem =
                  allDrItems.where((it) => it.id == drItemId).firstOrNull;
              if (drItem != null) {
                packageYards[drItem.forfeitedPackageId] =
                    drItem.forfeited?.yard ?? _formYard;
                final pkgItemId = key.contains('_')
                    ? key.split('_').last
                    : drItem.forfeited?.itemId;
                packageItems[drItem.forfeitedPackageId] = pkgItemId;
              }
            }
            try {
              await ref.read(disposalServiceProvider).createDestruction(
                    saleNumber: _numberC.text.trim().isEmpty
                        ? null
                        : _numberC.text.trim(),
                    saleDate: _saleDate,
                    saleTime:
                        _saleTime == null ? null : _timeOfDayToHHmm(_saleTime!),
                    saleEndTime: _saleEndTime == null
                        ? null
                        : _timeOfDayToHHmm(_saleEndTime!),
                    serial: _serialC.text.trim().isEmpty
                        ? null
                        : _serialC.text.trim(),
                    year: int.tryParse(_yearC.text.trim()),
                    tenderType: _destructionType,
                    yard: _formYard,
                    packageYards: packageYards,
                    packageItems: packageItems,
                  );
              ref.read(destructionsRefreshProvider.notifier).trigger();
              if (mounted) Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Destruction sale recorded'),
                  backgroundColor: green,
                ));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: context.colors.dangerRed,
                ));
              }
            } finally {
              if (mounted) setState(() => _loading = false);
            }
          },
        ),
      ],
    );
  }
}

class _DestructionSaleHistoryDialog extends StatelessWidget {
  final ReDestructionInfo info;
  const _DestructionSaleHistoryDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final sales = info.destructions;
    return StyledFormDialog(
      label: 'Destruction Sale History',
      title: info.forfeited.srNumber,
      headerAccentColor: context.colors.successGreen,
      icon: Icons.history_rounded,
      width: 540,
      child: StyledFormSection(
        title: 'Attempted ${info.timesAttempted} time(s)',
        icon: Icons.gavel_rounded,
        children: [
          for (int i = 0; i < sales.length; i++)
            _saleCard(context, sales[i], i == 0),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }

  Widget _saleCard(BuildContext context, dynamic t, bool isLatest) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isLatest
                ? context.colors.primaryGold.withOpacity(0.5)
                : context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.gavel_rounded,
                size: 16, color: context.colors.primaryGold),
            const Gap(8),
            Text(t.saleNumber ?? 'No Number',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
            if (isLatest) ...[
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Latest',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const Gap(8),
          _kv(
              context,
              'Sale Date',
              t.saleDate != null
                  ? DateFormat('yyyy-MM-dd').format(t.saleDate!)
                  : '—'),
          _kv(context, 'Sale Start Time', t.saleTime ?? '—'),
          if (t.createdByName != null)
            _kv(context, 'Created By', t.createdByName!),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(
          width: 130,
          child: Text(k,
              style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _UndestroyedReDestructionTab extends ConsumerWidget {
  const _UndestroyedReDestructionTab();

  String _itemName(ForfeitedPackageModel f) {
    final items = f.packageDetails?.items ?? const [];
    if (items.isEmpty) return 'Multiple/Unspecified';
    // An item-scoped FP names its own item — show THAT, not "first +N".
    if (f.itemId != null) {
      final match = items.where((i) => i.id == f.itemId).firstOrNull;
      if (match != null) return match.itemName;
    }
    if (items.length == 1) return items.first.itemName;
    return '${items.first.itemName} +${items.length - 1}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final amber = context.colors.warningAmber;
    final storageRate = ref.watch(storageRateProvider).valueOrNull ?? const {};
    final async = ref.watch(undestroyedDestructionsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Undestroyed Packages — Re-destruction',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const DisposalSearch(
                tabKey: 'undestroyed', hint: 'Search SR / item / consignee…'),
            const Gap(12),
            YardAllFilter(
              value: ref.watch(disposalYardFilterProvider('undestroyed')),
              onChanged: (v) => ref
                  .read(disposalYardFilterProvider('undestroyed').notifier)
                  .state = v,
            ),
            const Gap(12),
            async.maybeWhen(
              data: (list) => ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: green, foregroundColor: Colors.white),
                icon: const Icon(Icons.auto_delete_rounded, size: 18),
                label: const Text('Re-destruction',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onPressed: list.isEmpty
                    ? null
                    : () => showDialog(
                          context: context,
                          builder: (_) =>
                              const _DestructionFormDialog(reDestruction: true),
                        ).then((_) {
                          ref.invalidate(undestroyedDestructionsProvider);
                          ref.invalidate(destructionsProvider);
                        }),
              ),
              orElse: () => const SizedBox(),
            ),
          ]).animate().fadeIn(duration: 300.ms),
          const Gap(14),
          async.maybeWhen(
            data: (list) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: StatChip(
                  label: 'Undestroyed — re-destructionable',
                  value: '${list.length}',
                  color: amber),
            ).animate().fadeIn(duration: 300.ms),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: green)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(undestroyedDestructionsProvider)),
              data: (list) {
                final q = ref
                    .watch(disposalSearchProvider('undestroyed'))
                    .toLowerCase();
                final yf = ref.watch(disposalYardFilterProvider('undestroyed'));
                if (yf != null) {
                  list = list
                      .where((info) => matchesYardFilter(
                          yf, info.forfeited.yard, info.forfeited.srNumber))
                      .toList();
                }
                if (q.isNotEmpty) {
                  list = list
                      .where((info) =>
                          info.forfeited.srNumber.toLowerCase().contains(q) ||
                          info.forfeited.consigneeName
                              .toLowerCase()
                              .contains(q) ||
                          _itemName(info.forfeited).toLowerCase().contains(q))
                      .toList();
                }
                if (list.isEmpty) {
                  return _listCard(
                    context,
                    const EmptyTableState(
                        message:
                            'No undestroyed packages — everything destructioned is destroyed or still in an active destruction window'),
                  );
                }
                return _listCard(
                  context,
                  DataTable2(
                    columnSpacing: 12,
                    horizontalMargin: 16,
                    fixedTopRows: 1,
                    minWidth: 880,
                    headingRowColor: _headingColor(context),
                    columns: const [
                      DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                      DataColumn2(label: Text('Case No'), size: ColumnSize.S),
                      DataColumn2(
                          label: Text('Goods Name'), size: ColumnSize.M),
                      DataColumn2(
                          label: Center(child: Text('Source')),
                          size: ColumnSize.S),
                      DataColumn2(
                          label: Text('Qty'),
                          size: ColumnSize.S,
                          fixedWidth: 56),
                      DataColumn2(label: Text('Reason'), size: ColumnSize.M),
                      DataColumn2(label: Text('Location'), size: ColumnSize.M),
                      DataColumn2(
                          // "Latest": the cell shows the newest valuation —
                          // sealed while the round it prices is still open.
                          label: Text('Latest Valuation'),
                          size: ColumnSize.S,
                          fixedWidth: 145),
                      DataColumn2(
                          label: Center(child: Text('Destructions')),
                          size: ColumnSize.S,
                          fixedWidth: 120),
                      DataColumn2(
                          label: Center(child: Text('Details')),
                          size: ColumnSize.S,
                          fixedWidth: 64),
                    ],
                    rows: list.map((info) {
                      final f = info.forfeited;
                      final pkg = f.packageDetails;
                      final item = f.itemId != null
                          ? (pkg?.items
                              .where((i) => i.id == f.itemId)
                              .firstOrNull)
                          : null;
                      return DataRow(cells: [
                        DataCell(TooltipText(f.srNumber,
                            style: TextStyle(
                                color: context.colors.accentLightBlue,
                                fontWeight: FontWeight.w600))),
                        DataCell(TooltipText(pkg?.caseNumber ?? '—',
                            overflow: TextOverflow.ellipsis)),
                        DataCell(TooltipText(_itemName(f),
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Center(child: _SourceChip(source: f.source))),
                        DataCell(TooltipText(
                            '${f.entryQty ?? item?.quantity ?? '—'}')),
                        DataCell(Builder(builder: (_) {
                          final reason = _forfeitReasonText(item, f);
                          return Tooltip(
                            message: reason,
                            child: Text(reason.isNotEmpty ? reason : '—',
                                overflow: TextOverflow.ellipsis),
                          );
                        })),
                        DataCell(TooltipText(_warehouseLocation(pkg, f.itemId),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12))),
                        DataCell(_LatestValuationCell(
                            f: f,
                            qty: f.entryQty ?? item?.quantity,
                            // Sealed while the newest destruction round is
                            // still pending.
                            sealedUntilSale:
                                info.latestDestruction?.saleEnded == false)),
                        DataCell(Center(
                          child: _AttemptsBadge(
                            count: info.timesAttempted,
                            color: amber,
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) =>
                                  _DestructionSaleHistoryDialog(info: info),
                            ),
                          ),
                        )),
                        DataCell(Center(
                          child: pkg != null
                              ? IconButton(
                                  icon: Icon(Icons.info_outline_rounded,
                                      color: context.colors.accentLightBlue,
                                      size: 18),
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => PackageDetailsDialog(
                                      package: pkg,
                                      storageRate: storageRate,
                                      headerAccentColor: green,
                                      useLegacySummary: true,
                                      highlightItemId: f.itemId,
                                      yardLabel: yardName(f.yard),
                                      valuationUnitCost: f.valuationCost,
                                      valuationTotalCost: f.valuationCost !=
                                              null
                                          ? f.valuationCost! * (f.entryQty ?? 1)
                                          : null,
                                      valuationQty: f.entryQty,
                                      // Sealed while the newest round is open.
                                      valuationSealedUntilSale:
                                          info.latestDestruction?.saleEnded ==
                                              false,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        )),
                      ]);
                    }).toList(),
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

// ── Select All / Clear All bar for the package picker lists ───────────────────

class _SelectAllBar extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;
  const _SelectAllBar({
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$selectedCount of $totalCount selected',
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton.icon(
          onPressed: onSelectAll,
          icon: Icon(Icons.done_all_rounded,
              size: 16, color: context.colors.primaryGold),
          label: Text('Select All',
              style: TextStyle(
                  color: context.colors.primaryGold,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
        TextButton.icon(
          onPressed: onClearAll,
          icon: Icon(Icons.clear_all_rounded,
              size: 16, color: context.colors.textMuted),
          label: Text('Clear All',
              style: TextStyle(
                  color: context.colors.textMuted,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
      ],
    );
  }
}

// ── Shared form fields (gold one-tap calendar / clock, no OK button) ──────────

/// A read-only field that opens the gold [OneTapDatePicker] on tap and reports
/// the picked date. Matches the SR-registration calendar look & flow.
class _OneTapDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  const _OneTapDateField(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDialog<DateTime>(
          context: context,
          // Tender / Disposal sale & destruction dates can be scheduled for the
          // future, so no lastDate cap here (same custom picker, look identical).
          builder: (_) =>
              OneTapDatePicker(initialDate: value ?? DateTime.now()),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_month_rounded),
        ),
        child: Text(
          value != null
              ? DateFormat('yyyy-MM-dd').format(value!)
              : 'Select sale date',
          style:
              value == null ? TextStyle(color: context.colors.textMuted) : null,
        ),
      ),
    );
  }
}

/// A read-only field that opens the gold [OneTapTimePicker] on tap. No OK
/// button — tapping a minute closes the picker immediately.
class _OneTapTimeField extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final ValueChanged<TimeOfDay> onChanged;
  const _OneTapTimeField(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDialog<TimeOfDay>(
          context: context,
          builder: (_) =>
              OneTapTimePicker(initialTime: value ?? TimeOfDay.now()),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.access_time_rounded),
        ),
        child: Text(
          value != null ? value!.format(context) : 'Select time',
          style:
              value == null ? TextStyle(color: context.colors.textMuted) : null,
        ),
      ),
    );
  }
}

// ── Valuation Cell shared by Tender Sales, Destructions, Unsold, Undestroyed ──

class _ValuationCell extends StatelessWidget {
  final ForfeitedPackageModel? f;
  // In the yard (read-only) views the Valuation Directorate price must NOT be
  // shown — instead this cell shows the SR-form package item's own declared
  // Value. The valuation price is Central-Disposal-only.
  final bool useItemValue;

  /// The quantity shown in the row's Qty column — the valuation must multiply
  /// by exactly this so "@ unit × qty" stays consistent with what the row shows.
  final int? qty;

  /// When set, this unit cost is shown instead of the package's original
  /// [ForfeitedPackageModel.valuationCost] — used to surface the LATEST tender
  /// re-valuation on the Unsold Tenders page.
  final double? overrideUnitCost;
  final bool isRevalued;

  /// True while the goods are in a tender/destruction sale that has NOT yet
  /// run. The valuation is the reserve price, so it stays hidden until then —
  /// see [valuationSealed]. Defaults to false: the many places that show a
  /// valuation with no live sale (unsold pools, re-valuation, committee work)
  /// have nothing to protect.
  final bool sealedUntilSale;
  const _ValuationCell(
      {required this.f,
      this.useItemValue = false,
      this.qty,
      this.overrideUnitCost,
      this.isRevalued = false,
      this.sealedUntilSale = false});

  @override
  Widget build(BuildContext context) {
    // Sealed while the sale is still open — for BOTH the directorate's
    // valuation and the yard's own declared-value view. Whichever figure is
    // shown here still tells a bidder what the reserve is worth, so it stays
    // hidden until the sale has ended, exactly like every other Valuation
    // column. Checked first so the figure is never even computed.
    if (sealedUntilSale) {
      return const SealedValuation(compact: true);
    }
    final fp = f;
    if (fp == null) {
      return Text('—', style: TextStyle(color: context.colors.textMuted));
    }
    final int effQty;
    if (qty != null && qty! > 0) {
      effQty = qty!;
    } else if (fp.entryQty != null) {
      effQty = fp.entryQty!;
    } else if (fp.itemId != null) {
      effQty = fp.packageDetails?.items
              .where((i) => i.id == fp.itemId)
              .firstOrNull
              ?.quantity ??
          1;
    } else {
      effQty =
          fp.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 1;
    }
    final fmt = NumberFormat('#,##0');

    // Yard view → the SR-form item's own declared Value (unit value × qty),
    // shown as a plain total (no "@ unit × qty" breakdown — that's the valuation
    // style, which is Central-Disposal-only).
    if (useItemValue) {
      final item = fp.itemId != null
          ? fp.packageDetails?.items.where((i) => i.id == fp.itemId).firstOrNull
          : fp.packageDetails?.items.firstOrNull;
      final unitValue = item?.unitValue ?? 0;
      final total = unitValue * effQty;
      // Same "@ unit × qty" breakdown Central Disposal's own column uses, so
      // a bare total here doesn't read as a different, less detailed figure.
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'LKR ${fmt.format(total)}',
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12),
          ),
          Text(
            '@ ${fmt.format(unitValue)} × $effQty',
            style: TextStyle(color: context.colors.textMuted, fontSize: 10),
          ),
        ],
      );
    }

    // Central Disposal view → the LATEST re-valuation if one exists, else the
    // Valuation Directorate's original cost.
    final unitCost = overrideUnitCost ?? fp.valuationCost;
    if (unitCost == null) {
      return Text('—', style: TextStyle(color: context.colors.textMuted));
    }
    final total = unitCost * effQty;
    final priceColor = isRevalued
        ? context.colors.accentLightBlue
        : context.colors.primaryGold;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'LKR ${fmt.format(total)}',
            style: TextStyle(
                color: priceColor, fontWeight: FontWeight.w700, fontSize: 12),
          ),
          if (isRevalued) ...[
            const Gap(5),
            Icon(Icons.price_change_rounded,
                size: 12, color: context.colors.accentLightBlue),
          ],
        ]),
        Text(
          '@ ${fmt.format(unitCost)} × $effQty${isRevalued ? ' · re-valued' : ''}',
          style: TextStyle(color: context.colors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}
