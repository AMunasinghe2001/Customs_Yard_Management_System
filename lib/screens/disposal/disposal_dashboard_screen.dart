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
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import 'taxes_tab.dart';
import '../../widgets/styled_dropdown.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/one_tap_date_picker.dart';
import '../../widgets/disposal_profile_dialog.dart';
import '../../widgets/table_pager.dart';

class DisposalDashboardScreen extends ConsumerWidget {
  const DisposalDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final profile = ref.watch(currentProfileProvider);
    return DefaultTabController(
      length: 8,
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
                    Text('Sold & forfeited items across all yards · tender sales',
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
                  splashFactory: NoSplash.splashFactory,
                  overlayColor:
                      WidgetStateProperty.all(Colors.transparent),
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
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.sell_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Sold Packages', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.delete_forever_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Destroyed Packages', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.assignment_turned_in_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Disposal Requests', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.storefront_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Tender Sales', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.replay_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Unsold Tenders', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.gavel_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Destructions', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.auto_delete_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Undestroyed', overflow: TextOverflow.ellipsis)),
                        ])),
                    Tab(
                        height: 44,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.receipt_long_rounded, size: 18),
                          Gap(8),
                          Flexible(child: Text('Taxes', overflow: TextOverflow.ellipsis)),
                        ])),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 350.ms, delay: 80.ms),
            const Expanded(
              child: TabBarView(children: [
                _SoldPackagesTab(),
                _DestroyedPackagesTab(),
                _DisposalRequestsTab(),
                _TenderSalesTab(),
                _UnsoldReTenderTab(),
                _DestructionsTab(),
                _UndestroyedReDestructionTab(),
                TaxesTab(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────

// Per-tab search query (keyed by tab name).
final _disposalSearchProvider =
    StateProvider.family<String, String>((ref, key) => '');

// Per-tab yard filter (null = All Yards) for the cross-yard list tabs.
final _disposalYardFilterProvider =
    StateProvider.family<String?, String>((ref, key) => null);

/// Styled search box shared by every Central Disposal tab.
class _DisposalSearch extends ConsumerStatefulWidget {
  final String tabKey;
  final String hint;
  final double width;
  const _DisposalSearch(
      {required this.tabKey, this.hint = 'Search…', this.width = 300});
  @override
  ConsumerState<_DisposalSearch> createState() => _DisposalSearchState();
}

class _DisposalSearchState extends ConsumerState<_DisposalSearch> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(
        text: ref.read(_disposalSearchProvider(widget.tabKey)));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w));
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _c,
        style: TextStyle(color: context.colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
        onChanged: (v) {
          ref.read(_disposalSearchProvider(widget.tabKey).notifier).state = v;
          setState(() {});
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintStyle: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: context.colors.primaryGold),
          suffixIcon: _c.text.isEmpty
              ? null
              : IconButton(
                  splashRadius: 16,
                  icon: Icon(Icons.close_rounded,
                      size: 16, color: context.colors.textMuted),
                  onPressed: () {
                    _c.clear();
                    ref
                        .read(_disposalSearchProvider(widget.tabKey).notifier)
                        .state = '';
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: context.colors.primaryGold.withOpacity(0.06),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: border(context.colors.primaryGold.withOpacity(0.4)),
          enabledBorder: border(context.colors.primaryGold.withOpacity(0.4)),
          focusedBorder: border(context.colors.primaryGold, 1.5),
        ),
      ),
    );
  }
}

/// Yard dropdown with an "All Yards" option, bound to a provided value/onChanged.
/// Used by tabs that filter their own (cross-yard) list locally.
class _YardAllFilter extends StatelessWidget {
  final String? value; // null = all
  final ValueChanged<String?> onChanged;
  const _YardAllFilter({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
            filled: true,
            fillColor: context.colors.primaryGold.withOpacity(0.06),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.colors.primaryGold.withOpacity(0.4))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.colors.primaryGold.withOpacity(0.4))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.colors.primaryGold, width: 1.5)),
          ),
        ),
        child: StyledDropdownFormField<String>(
          value: value ?? '_all',
          label: 'Yard',
          helperText: null,
          isDense: true,
          menuWidth: 220,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon:
              Icon(Icons.warehouse_rounded, color: context.colors.primaryGold, size: 20),
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

class _YardFilter extends ConsumerWidget {
  const _YardFilter();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedYard = ref.watch(disposalSelectedYardProvider);
    return _StyledYardPicker(
      value: selectedYard,
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
  const _StyledYardPicker({
    required this.value,
    required this.onChanged,
    this.width = 240,
  });

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
                borderSide: BorderSide(color: context.colors.primaryGold.withOpacity(0.4))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.colors.primaryGold.withOpacity(0.4))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.colors.primaryGold, width: 1.5)),
          ),
        ),
        child: StyledDropdownFormField<String>(
          value: value,
          label: 'Yard',
          helperText: null,
          isDense: true,
          menuWidth: width,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          prefixIcon:
              Icon(Icons.warehouse_rounded, color: context.colors.primaryGold, size: 20),
          options: [
            for (final y in kYards) StyledDropdownOption(y.code, y.name),
          ],
          onChanged: onChanged,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        const Gap(8),
        Text(label,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]),
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

/// The reason shown in the disposal tables' "Forfeit Reason" column. Prefers
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

class _SoldRow {
  final PackageModel package;
  final WarehouseEntryModel entry;
  final String itemName;
  final String officer;
  const _SoldRow(this.package, this.entry, this.itemName, this.officer);

  /// Key for saleItemForPackageItemProvider: "packageId|packageItemId".
  String get saleItemKey => '${package.id}|${entry.packageItemId ?? ''}';
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
        final item =
            p.items.where((i) => i.id == e.packageItemId).firstOrNull;
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
            Text('Sold Packages',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const _DisposalSearch(
                tabKey: 'sold', hint: 'Search SR / item / sold by…'),
            const Gap(12),
            _YardAllFilter(
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
                    ref.watch(_disposalSearchProvider('sold')).toLowerCase();
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
                      child: _StatChip(
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
                            DataColumn2(label: Text('Item'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 60),
                            DataColumn2(
                                label: Text('Sold Date'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Sold By'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Receipt No'), size: ColumnSize.S),
                            DataColumn2(
                                label: Text('Financials'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Delivery'), fixedWidth: 120),
                            DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                          ],
                          rows: pageRows
                              .map((r) => DataRow(cells: [
                                    DataCell(Text(r.package.srNumber,
                                        style: TextStyle(
                                            color:
                                                context.colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(Text(r.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Text('${r.entry.itemCount}')),
                                    DataCell(Text(r.entry.returnedAt != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(r.entry.returnedAt!)
                                        : '—')),
                                    DataCell(Text(r.officer,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(
                                        _SaleReceiptCell(saleItemKey: r.saleItemKey)),
                                    DataCell(
                                        _SaleFinancialsCell(saleItemKey: r.saleItemKey)),
                                    DataCell(
                                        _DeliveryStatusCell(package: r.package, saleItemKey: r.saleItemKey)),
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
  const _DeliverySegmentedFilter(
      {required this.value, required this.onChanged});

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
      seg('Delivered', true, Icons.check_circle_rounded),
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
  return tag == 'FINAL:DESTROYED' || tag == 'DESTROYED' || tag == 'DESTROY';
}

class _DestroyedPackagesTab extends ConsumerStatefulWidget {
  const _DestroyedPackagesTab();
  @override
  ConsumerState<_DestroyedPackagesTab> createState() =>
      _DestroyedPackagesTabState();
}

class _DestroyedPackagesTabState extends ConsumerState<_DestroyedPackagesTab> {
  static const int _pageSize = 20;
  int _page = 0;

  List<_SoldRow> _rows(List<PackageModel> packages) {
    final rows = <_SoldRow>[];
    for (final p in packages) {
      for (final e in p.warehouseEntries) {
        if (!_isDestroyedEntry(e)) continue;
        final item =
            p.items.where((i) => i.id == e.packageItemId).firstOrNull;
        // Never mislabel an un-linked entry as items.first in a multi-item
        // package (see the Sold tab note).
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
    // Central Disposal's accent is green — keep the Destroyed tab on-brand
    // (loading spinner, stat chip, popup header) rather than danger-red.
    final green = context.colors.successGreen;
    final yardFilter = ref.watch(disposalDestroyedYardFilterProvider);
    final destroyed = ref.watch(disposalDestroyedPackagesProvider);
    final deliveryFilter = ref.watch(_destroyedDeliveryFilterProvider);
    final deliveredMap =
        ref.watch(packageDestroyedDeliveredMapProvider).valueOrNull ?? const {};
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        {DateTime(2020, 1, 1): 50.0};
    final yardLabel = yardFilter == null ? 'all yards' : yardName(yardFilter);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Destroyed Packages',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const _DisposalSearch(
                tabKey: 'destroyed', hint: 'Search SR / item / by…'),
            const Gap(12),
            _YardAllFilter(
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
                    .watch(_disposalSearchProvider('destroyed'))
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
                      .where((r) =>
                          (deliveredMap[r.package.id] ?? false) ==
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
                      child: _StatChip(
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
                            DataColumn2(label: Text('Item'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Qty'),
                                size: ColumnSize.S,
                                fixedWidth: 60),
                            DataColumn2(
                                label: Text('Destroyed Date'),
                                size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Destroyed By'), size: ColumnSize.M),
                            DataColumn2(
                                label: Text('Delivery'), fixedWidth: 130),
                            DataColumn2(
                                label: Center(child: Text('Details')),
                                size: ColumnSize.S,
                                fixedWidth: 70),
                          ],
                          rows: pageRows
                              .map((r) => DataRow(cells: [
                                    DataCell(Text(r.package.srNumber,
                                        style: TextStyle(
                                            color:
                                                context.colors.accentLightBlue,
                                            fontWeight: FontWeight.w600))),
                                    DataCell(Text(r.itemName,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(Text('${r.entry.itemCount}')),
                                    DataCell(Text(r.entry.returnedAt != null
                                        ? DateFormat('yyyy-MM-dd')
                                            .format(r.entry.returnedAt!)
                                        : '—')),
                                    DataCell(Text(r.officer,
                                        overflow: TextOverflow.ellipsis)),
                                    DataCell(_DestroyedDeliveryCell(
                                        package: r.package)),
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

/// Read-only Delivered/Pending chip for a destroyed package (watches the
/// per-package destruction-item provider so it stays live across sessions).
class _DestroyedDeliveryCell extends ConsumerWidget {
  final PackageModel package;
  const _DestroyedDeliveryCell({required this.package});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(destructionItemForPackageProvider(package.id));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) =>
          DeliveryStatusChip(delivered: item?.delivered ?? false),
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
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
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

class _SaleFinancialsCell extends ConsumerWidget {
  final String saleItemKey;
  const _SaleFinancialsCell({required this.saleItemKey});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saleItemForPackageItemProvider(saleItemKey));
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('—'),
      data: (item) {
        if (item == null) return const Text('—');
        double taxSum = 0;
        for (final t in item.appliedTaxes) {
          taxSum += (t['amount'] as num?)?.toDouble() ?? 0;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Rs ${item.soldPrice.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Tax: Rs ${taxSum.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: context.colors.textMuted)),
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
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
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
            style:
                TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
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
            const _DisposalSearch(
                tabKey: 'requests', hint: 'Search SR / consignee…'),
            const Gap(12),
            _YardAllFilter(
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
                final q = ref
                    .watch(_disposalSearchProvider('requests'))
                    .toLowerCase();
                var filtered = yardFilter == null
                    ? list
                    : list.where((r) => r.yard == yardFilter).toList();
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
    final expandedRows = <({DisposalRequestItemModel it, PackageItem? pkgItem})>[];
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
                      Text(
                          DateFormat('yyyy-MM-dd').format(request.requestDate),
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
                    Text('${expandedRows.length} package${expandedRows.length == 1 ? '' : 's'} requested',
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
                    DataColumn2(label: Text('Item'), size: ColumnSize.M),
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
                        label: Text('Source'),
                        size: ColumnSize.S,
                        fixedWidth: 110),
                    DataColumn2(
                        label: Text('Disposition'),
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
                    final displayQty = pkgItem != null ? pkgItem.quantity : it.totalQuantity;
                    final highlightId = pkgItem?.id ?? f?.itemId ??
                        (f?.packageDetails?.items.isNotEmpty == true
                            ? f!.packageDetails!.items.first.id
                            : null);
                    return DataRow(cells: [
                      DataCell(Text(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(Text(displayName,
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text(f?.consigneeName ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text(displayHs ?? '—',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12))),
                      DataCell(Text('$displayQty',
                          style: TextStyle(
                              color: context.colors.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12))),
                      DataCell(_SourceChip(source: f?.source ?? 'forfeit')),
                      DataCell(_DispositionChip(disposition: it.disposition)),
                      DataCell(it.valuationCost != null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                    'LKR ${NumberFormat('#,##0').format((it.unitCost ?? 0) * displayQty)}',
                                    style: TextStyle(
                                        color: context.colors.primaryGold,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12)),
                                Text(
                                    '@ ${NumberFormat('#,##0').format(it.unitCost)} × $displayQty',
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 10)),
                              ],
                            )
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
                                      headerAccentColor: context.colors.successGreen,
                                      useLegacySummary: true,
                                      highlightItemId: highlightId,
                                      yardLabel: yardName(
                                          f.yard ?? request.yard),
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
    final icon =
        isSale ? Icons.sell_rounded : Icons.delete_forever_rounded;
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Unsold Packages — Re-tender',
                style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            const _DisposalSearch(
                tabKey: 'unsold', hint: 'Search SR / item / consignee…'),
            const Gap(12),
            _YardAllFilter(
              value: ref.watch(_disposalYardFilterProvider('unsold')),
              onChanged: (v) => ref
                  .read(_disposalYardFilterProvider('unsold').notifier)
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
              child: _StatChip(
                  label: 'Unsold — re-tenderable',
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
                  onRetry: () => ref.refresh(unsoldTenderSalesProvider)),
              data: (list) {
                final q =
                    ref.watch(_disposalSearchProvider('unsold')).toLowerCase();
                final yf = ref.watch(_disposalYardFilterProvider('unsold'));
                if (yf != null) {
                  list =
                      list.where((info) => info.forfeited.yard == yf).toList();
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
                      DataColumn2(label: Text('Item'), size: ColumnSize.L),
                      DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                      DataColumn2(
                          label: Text('Source'),
                          size: ColumnSize.S,
                          fixedWidth: 110),
                      DataColumn2(label: Text('Valuation'), size: ColumnSize.M),
                      DataColumn2(
                          label: Center(child: Text('Times Tendered')),
                          size: ColumnSize.S,
                          fixedWidth: 130),
                      DataColumn2(
                          label: Center(child: Text('Tenders')),
                          size: ColumnSize.S,
                          fixedWidth: 90),
                      DataColumn2(
                          label: Center(child: Text('Details')),
                          size: ColumnSize.S,
                          fixedWidth: 64),
                    ],
                    rows: list.map((info) {
                      final f = info.forfeited;
                      final pkg = f.packageDetails;
                      return DataRow(cells: [
                        DataCell(Text(f.srNumber,
                            style: TextStyle(
                                color: context.colors.accentLightBlue,
                                fontWeight: FontWeight.w600))),
                        DataCell(Text(_itemName(f),
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text(f.consigneeName,
                            overflow: TextOverflow.ellipsis)),
                        DataCell(_SourceChip(source: f.source)),
                        DataCell(_ValuationCell(f: f)),
                        DataCell(Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: amber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: amber.withOpacity(0.4)),
                            ),
                            child: Text('${info.tenderCount}×',
                                style: TextStyle(
                                    color: amber, fontWeight: FontWeight.w800)),
                          ),
                        )),
                        DataCell(Center(
                          child: IconButton(
                            icon: const Icon(Icons.history_rounded, size: 18),
                            color: context.colors.accentLightBlue,
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => _TenderSaleHistoryDialog(info: info),
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
                                      valuationTotalCost: f.valuationCost != null
                                          ? f.valuationCost! * (f.entryQty ?? 1)
                                          : null,
                                      valuationQty: f.entryQty,
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
            const _DisposalSearch(
                tabKey: 'tendersales', hint: 'Search sale no / SR…'),
            const Gap(12),
            _YardAllFilter(
              value: ref.watch(_disposalYardFilterProvider('tendersales')),
              onChanged: (v) => ref
                  .read(_disposalYardFilterProvider('tendersales').notifier)
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
                    .watch(_disposalSearchProvider('tendersales'))
                    .toLowerCase();
                // Hide sales whose packages are all sold (fully consumed).
                var visible =
                    list.where((s) => s.items.any((i) => !i.sold)).toList();
                final yf =
                    ref.watch(_disposalYardFilterProvider('tendersales'));
                if (yf != null) {
                  visible = visible.where((s) => s.yard == yf).toList();
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
                        message: 'No tender sales yet',
                        subtitle:
                            'Create a tender sale to start selling forfeited packages.'),
                  );
                }
                return ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, i) => TenderSaleCard(sale: visible[i]),
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

class TenderSaleCard extends ConsumerWidget {
  final TenderSaleModel sale;
  /// Yard-side, view-only mode: shows every item (sold included) with a
  /// read-only Sold/Pending status chip instead of the Mark-Sold action.
  final bool readOnly;
  const TenderSaleCard({required this.sale, this.readOnly = false});

  String _warehouseFor(PackageModel? pkg, String itemId) {
    if (pkg == null) return '—';
    final entries =
        pkg.warehouseEntries.where((e) => e.packageItemId == itemId).toList()
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
    final source =
        readOnly ? sale.items : sale.items.where((s) => !s.sold);

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
        rows.add(_TsRow(si, match, match != null ? _warehouseFor(pkg!, match.id) : '—'));
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
  Widget build(BuildContext context, WidgetRef ref) {
    final green = context.colors.successGreen;
    final storageRate = ref.watch(storageRateProvider).valueOrNull ?? const {};
    final rows = _rows();
    final total = sale.totalCount;
    final sold = sale.soldCount;
    final allSold = total > 0 && sold == total;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: allSold
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
                    Text(
                        sale.saleNumber?.isNotEmpty == true
                            ? sale.saleNumber!
                            : 'Tender Sale',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
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
                                color: context.colors.textMuted,
                                fontSize: 12)),
                      ),
                    ]),
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
              height: (rows.length * 46.0 + 56).clamp(110, 360),
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
                  minWidth: 1080,
                  headingRowColor: _headingColor(context),
                  empty:
                      const EmptyTableState(message: 'No packages in this sale'),
                  columns: const [
                    DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                    DataColumn2(label: Text('Case No'), size: ColumnSize.S),
                    DataColumn2(label: Text('Item'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Qty'), size: ColumnSize.S, fixedWidth: 56),
                    DataColumn2(label: Text('Forfeit Reason'), size: ColumnSize.M),
                    DataColumn2(label: Text('Location'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Goods Description'), size: ColumnSize.L),
                    DataColumn2(label: Text('Valuation'), size: ColumnSize.M),
                    DataColumn2(
                        label: Center(child: Text('Status')),
                        size: ColumnSize.M,
                        fixedWidth: 140),
                    DataColumn2(
                        label: Center(child: Text('Details')),
                        size: ColumnSize.S,
                        fixedWidth: 64),
                  ],
                  rows: rows.map((r) {
                    final f = r.saleItem.forfeited;
                    final pkg = f?.packageDetails;
                    return DataRow(cells: [
                      DataCell(Text(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(Text(pkg?.caseNumber ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text(r.item?.itemName ?? 'Multiple/Unspecified',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text('${f?.entryQty ?? r.item?.quantity ?? '—'}')),
                      DataCell(Builder(builder: (_) {
                        final reason = _forfeitReasonText(r.item, f);
                        return Tooltip(
                          message: reason,
                          child: Text(reason.isNotEmpty ? reason : '—',
                              overflow: TextOverflow.ellipsis),
                        );
                      })),
                      DataCell(Text(
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
                      DataCell(_ValuationCell(f: f)),
                      DataCell(Center(
                        child: r.saleItem.sold
                            ? _statusChip(context, 'Sold',
                                Icons.check_circle_rounded, green)
                            : readOnly
                                ? (() {
                                    final saleDate = sale.saleDate;
                                    final isUnsold = saleDate != null &&
                                        DateTime.now().isAfter(
                                            saleDate.add(const Duration(days: 1)));
                                    return isUnsold
                                        ? _statusChip(
                                            context,
                                            'Unsold',
                                            Icons.cancel_outlined,
                                            context.colors.dangerRed)
                                        : _statusChip(
                                            context,
                                            'Pending',
                                            Icons.schedule_rounded,
                                            context.colors.warningAmber);
                                  }())
                                : (() {
                                    // Mark Sold only unlocks once the scheduled
                                    // sale moment (date + time) has passed.
                                    final canSell = sale.saleTimePassed;
                                    final btn = OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: green,
                                        side: BorderSide(
                                            color: green.withOpacity(0.5)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        minimumSize: const Size(0, 32),
                                      ),
                                      icon: const Icon(Icons.sell_rounded,
                                          size: 14),
                                      label: const Text('Mark Sold',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700)),
                                      onPressed: canSell
                                          ? () => _markSold(
                                              context, ref, r.saleItem)
                                          : null,
                                    );
                                    return canSell
                                        ? btn
                                        : Tooltip(
                                            message: _saleLockMessage(sale),
                                            child: btn);
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
                                    headerAccentColor: green,
                                    useLegacySummary: true,
                                    highlightItemId: f?.itemId,
                                    yardLabel: yardName(r.saleItem.yard),
                                    valuationUnitCost: f?.valuationCost,
                                    valuationTotalCost: f?.valuationCost != null
                                        ? f!.valuationCost! *
                                            (f.entryQty ?? r.item?.quantity ?? 1)
                                        : null,
                                    valuationQty:
                                        f?.entryQty ?? r.item?.quantity,
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

  /// Tooltip shown on a disabled Mark Sold button — tells the officer when the
  /// scheduled sale moment unlocks the action.
  String _saleLockMessage(TenderSaleModel sale) {
    final moment = sale.saleMoment;
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
            style: TextStyle(
              color: context.colors.textSecondary, fontSize: 13)
          ),
          TextField(
            controller: _receiptC,
            decoration: const InputDecoration(labelText: 'Receipt Number (optional)'),
          ),
          const Gap(16),
          TextField(
            controller: _soldPriceC,
            decoration: const InputDecoration(labelText: 'Sold Price', prefixText: 'Rs '),
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
                  Text('Rs ${(price * (t.percentage / 100)).toStringAsFixed(2)}'),
                ],
              ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Grand Total:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Rs ${grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')
        ),
        StyledDialogPrimaryButton(
          labelText: 'Confirm Sold',
          icon: Icons.check_circle_rounded,
          loading: _loading,
          onPressed: () async {
            setState(() => _loading = true);
            try {
              await widget.ref.read(disposalServiceProvider).markTenderSaleItemSold(
                tenderSaleItemId: widget.item.id,
                receipt: _receiptC.text,
                soldPrice: price,
                appliedTaxes: appliedTaxesList,
              );
              // Fire every related trigger so this session's views update
              // instantly (the realtime round-trip handles other sessions).
              widget.ref.read(tenderSalesRefreshProvider.notifier).trigger();
              widget.ref.read(tenderSaleItemsRefreshProvider.notifier).trigger();
              widget.ref.read(packagesRefreshTriggerProvider.notifier).trigger();
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
  DateTime? _saleDate;
  TimeOfDay? _saleTime;
  String? _tenderType;
  bool _loading = false;
  String? _error;
  // forfeited_package_id → yard
  final Map<String, String> _selected = {};
  // The yard this tender sale belongs to. The package pool is filtered to this
  // yard's forwarded requests, and the created sale is assigned to it.
  late String _formYard;

  String? _validate() {
    if (_saleDate == null) return 'Tender Sale Date is required.';
    if (_saleTime == null) return 'Sale Start Time is required.';
    if (_tenderType == null || _tenderType!.isEmpty) return 'Tender Sale Type is required.';
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
    // shown on the Unsold Tenders page. Either way, only the packages belonging
    // to the yard selected in this form are shown (and tendered).
    final AsyncValue<List<DisposalRequestItemModel>> pool = (widget.reTender
            ? ref.watch(unsoldTenderSalesProvider).whenData((list) => list
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
                border: Border.all(color: context.colors.dangerRed.withOpacity(0.4)),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, color: context.colors.dangerRed, size: 18),
                const Gap(10),
                Expanded(child: Text(_error!, style: TextStyle(color: context.colors.dangerRed, fontSize: 13))),
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
                    label: 'Tender Sale Date',
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
                          'No "Sale" packages awaiting a tender sale.\n'
                          'Yards mark packages for Sale in a Disposal Request.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: context.colors.textSecondary),
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
                  final rows = <({DisposalRequestItemModel it, PackageItem? pkgItem})>[];
                  for (final it in items) {
                    final fpItems = it.forfeited?.packageDetails?.items ?? const [];
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
                          color: context.colors.borderColor.withOpacity(0.5)),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final it = r.it;
                        final pkgItem = r.pkgItem;
                        final rowKey = pkgItem != null
                            ? '${it.id}_${pkgItem.id}'
                            : it.id;
                        final yard = it.forfeited?.yard ?? '';
                        final selected = _selected.containsKey(rowKey);
                        final displayName = pkgItem?.itemName ?? _summary(it);
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
                                                color: context
                                                    .colors.accentLightBlue)),
                                      ),
                                      const Gap(8),
                                      _SourceChip(
                                          source:
                                              it.forfeited?.source ?? 'forfeit'),
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
                              const Gap(8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: green.withOpacity(0.3)),
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
            setState(() { _loading = true; _error = null; });
            // Build forfeitedPackageId→yard from composite _selected keys.
            final allDrItems = ref
                .read(saleRequestItemsProvider)
                .valueOrNull ?? const [];
            final packageYards = <String, String>{};
            // forfeited_package_id → the specific package_item id it covers, so
            // the TSI row is item-scoped (Mark Sold sells only that item).
            final packageItems = <String, String?>{};
            for (final key in _selected.keys) {
              final drItemId = key.contains('_') ? key.split('_').first : key;
              final drItem = allDrItems
                  .where((it) => it.id == drItemId)
                  .firstOrNull;
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
                    saleNumber: _numberC.text.trim().isEmpty ? null : _numberC.text.trim(),
                    saleDate: _saleDate,
                    saleTime:
                        _saleTime == null ? null : _timeOfDayToHHmm(_saleTime!),
                    serial:
                        _serialC.text.trim().isEmpty ? null : _serialC.text.trim(),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              style: TextStyle(
                  color: context.colors.textMuted, fontSize: 12)),
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
            const _DisposalSearch(
                tabKey: 'destructions', hint: 'Search sale no / SR…'),
            const Gap(12),
            _YardAllFilter(
              value: ref.watch(_disposalYardFilterProvider('destructions')),
              onChanged: (v) => ref
                  .read(_disposalYardFilterProvider('destructions').notifier)
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
                    .watch(_disposalSearchProvider('destructions'))
                    .toLowerCase();
                final yf =
                    ref.watch(_disposalYardFilterProvider('destructions'));
                // Hide sales whose packages are all destroyed (fully consumed).
                var visible =
                    list.where((s) => s.items.any((i) => !i.destroyed)).toList();
                if (yf != null) {
                  visible = visible.where((s) => s.yard == yf).toList();
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
                        message: 'No destruction sales with undestroyed packages'),
                  );
                }
                return ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, i) => _DestructionCard(sale: visible[i]),
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

class _DestructionCard extends ConsumerWidget {
  final DestructionModel sale;
  const _DestructionCard({required this.sale});

  String _warehouseFor(PackageModel? pkg, String itemId) {
    if (pkg == null) return '—';
    final entries =
        pkg.warehouseEntries.where((e) => e.packageItemId == itemId).toList()
          ..sort((a, b) => b.admittedAt.compareTo(a.admittedAt));
    if (entries.isEmpty) return '—';
    final w = entries.first;
    return w.zone != null && w.zone!.isNotEmpty
        ? '${w.warehouseName} · ${w.zone}'
        : w.warehouseName;
  }

  List<_DestRow> _rows() {
    final rows = <_DestRow>[];
    // Destroyed items leave the Destruction Sales page (they move to Destroyed Packages).
    for (final si in sale.items.where((s) => !s.destroyed)) {
      final pkg = si.forfeited?.packageDetails;
      final pkgItems = pkg?.items ?? const [];
      final fpItemId = si.forfeited?.itemId;
      if (pkgItems.isEmpty) {
        rows.add(_DestRow(si, null, '—'));
      } else if (fpItemId != null) {
        // Per-item FP row — show only the specific item it refers to.
        final match = pkgItems.where((i) => i.id == fpItemId).firstOrNull;
        rows.add(_DestRow(si, match, match != null ? _warehouseFor(pkg, match.id) : '—'));
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
                    Text(
                        sale.saleNumber?.isNotEmpty == true
                            ? sale.saleNumber!
                            : 'Destruction Sale',
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
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
                                color: context.colors.textMuted,
                                fontSize: 12)),
                      ),
                    ]),
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
                      color: (allDestroyed ? green : context.colors.warningAmber)
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
              height: (rows.length * 46.0 + 56).clamp(110, 360),
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
                  minWidth: 1080,
                  headingRowColor: _headingColor(context),
                  empty:
                      const EmptyTableState(message: 'No packages in this sale'),
                  columns: const [
                    DataColumn2(label: Text('SR Number'), size: ColumnSize.M),
                    DataColumn2(label: Text('Case No'), size: ColumnSize.S),
                    DataColumn2(label: Text('Item'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Qty'), size: ColumnSize.S, fixedWidth: 56),
                    DataColumn2(label: Text('Forfeit Reason'), size: ColumnSize.M),
                    DataColumn2(label: Text('Location'), size: ColumnSize.M),
                    DataColumn2(
                        label: Text('Goods Description'), size: ColumnSize.L),
                    DataColumn2(label: Text('Valuation'), size: ColumnSize.M),
                    DataColumn2(
                        label: Center(child: Text('Status')),
                        size: ColumnSize.M,
                        fixedWidth: 140),
                    DataColumn2(
                        label: Center(child: Text('Details')),
                        size: ColumnSize.S,
                        fixedWidth: 64),
                  ],
                  rows: rows.map((r) {
                    final f = r.saleItem.forfeited;
                    final pkg = f?.packageDetails;
                    return DataRow(cells: [
                      DataCell(Text(f?.srNumber ?? '—',
                          style: TextStyle(
                              color: context.colors.accentLightBlue,
                              fontWeight: FontWeight.w600))),
                      DataCell(Text(pkg?.caseNumber ?? '—',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text(r.item?.itemName ?? 'Multiple/Unspecified',
                          overflow: TextOverflow.ellipsis)),
                      DataCell(Text('${f?.entryQty ?? r.item?.quantity ?? '—'}')),
                      DataCell(Builder(builder: (_) {
                        final reason = _forfeitReasonText(r.item, f);
                        return Tooltip(
                          message: reason,
                          child: Text(reason.isNotEmpty ? reason : '—',
                              overflow: TextOverflow.ellipsis),
                        );
                      })),
                      DataCell(Text(
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
                      DataCell(_ValuationCell(f: f)),
                      DataCell(Center(
                        child: r.saleItem.destroyed
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: green.withOpacity(0.4)),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_rounded,
                                          size: 13, color: green),
                                      const Gap(5),
                                      Text('Destroyed',
                                          style: TextStyle(
                                              color: green,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700)),
                                    ]),
                              )
                            : (() {
                                // Mark Destroyed only unlocks once the scheduled
                                // destruction moment (date + time) has passed.
                                final canDestroy = sale.saleTimePassed;
                                final btn = OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: green,
                                    side: BorderSide(
                                        color: green.withOpacity(0.5)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  icon:
                                      const Icon(Icons.sell_rounded, size: 14),
                                  label: const Text('Mark Destroyed',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                  onPressed: canDestroy
                                      ? () => _markDestroyed(
                                          context, ref, r.saleItem)
                                      : null,
                                );
                                return canDestroy
                                    ? btn
                                    : Tooltip(
                                        message: _destroyLockMessage(sale),
                                        child: btn);
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
                                    headerAccentColor: green,
                                    useLegacySummary: true,
                                    highlightItemId: f?.itemId,
                                    yardLabel: yardName(r.saleItem.yard),
                                    valuationUnitCost: f?.valuationCost,
                                    valuationTotalCost: f?.valuationCost != null
                                        ? f!.valuationCost! *
                                            (f.entryQty ?? r.item?.quantity ?? 1)
                                        : null,
                                    valuationQty:
                                        f?.entryQty ?? r.item?.quantity,
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
}

class _MarkDestroyedDialog extends StatefulWidget {
  final DestructionItemModel item;
  final WidgetRef ref;
  const _MarkDestroyedDialog({required this.item, required this.ref});
  @override
  State<_MarkDestroyedDialog> createState() => _MarkDestroyedDialogState();
}

class _MarkDestroyedDialogState extends State<_MarkDestroyedDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    // Destruction is not a sale — no price, taxes or receipt. Confirmation only.
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
            style: TextStyle(
              color: context.colors.textSecondary, fontSize: 13)
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel')
        ),
        StyledDialogPrimaryButton(
          labelText: 'Confirm Destroyed',
          icon: Icons.check_circle_rounded,
          loading: _loading,
          onPressed: () async {
            setState(() => _loading = true);
            try {
              await widget.ref.read(disposalServiceProvider).markDestructionItemDestroyed(
                destructionItemId: widget.item.id,
                receipt: '',
              );
              widget.ref.read(destructionsRefreshProvider.notifier).trigger();
              widget.ref.read(packagesRefreshTriggerProvider.notifier).trigger();
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

class _DestructionFormDialogState extends ConsumerState<_DestructionFormDialog> {
  final _numberC = TextEditingController();
  final _serialC = TextEditingController();
  final _yearC = TextEditingController(text: DateTime.now().year.toString());
  DateTime? _saleDate;
  TimeOfDay? _saleTime;
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
    if (_destructionType == null || _destructionType!.isEmpty) return 'Destruction Sale Type is required.';
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
    final AsyncValue<List<DisposalRequestItemModel>> pool = (widget.reDestruction
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
      title: widget.reDestruction ? 'Re-destruction Sale' : 'New Destruction Sale',
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
                border: Border.all(color: context.colors.dangerRed.withOpacity(0.4)),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, color: context.colors.dangerRed, size: 18),
                const Gap(10),
                Expanded(child: Text(_error!, style: TextStyle(color: context.colors.dangerRed, fontSize: 13))),
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
                          style:
                              TextStyle(color: context.colors.textSecondary),
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
                  final rows = <({DisposalRequestItemModel it, PackageItem? pkgItem})>[];
                  for (final it in items) {
                    final fpItems = it.forfeited?.packageDetails?.items ?? const [];
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
                          color: context.colors.borderColor.withOpacity(0.5)),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final it = r.it;
                        final pkgItem = r.pkgItem;
                        final rowKey = pkgItem != null
                            ? '${it.id}_${pkgItem.id}'
                            : it.id;
                        final yard = it.forfeited?.yard ?? '';
                        final selected = _selected.containsKey(rowKey);
                        final displayName = pkgItem?.itemName ?? _summary(it);
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
                                                color: context
                                                    .colors.accentLightBlue)),
                                      ),
                                      const Gap(8),
                                      _SourceChip(
                                          source:
                                              it.forfeited?.source ?? 'forfeit'),
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
                              const Gap(8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: green.withOpacity(0.3)),
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
            setState(() { _loading = true; _error = null; });
            // Build forfeitedPackageId→yard map from _selected keys.
            // Keys are either plain it.id or "${it.id}_${pkgItem.id}" for
            // expanded per-item rows — both cases point to the same
            // forfeitedPackageId on the DR item.
            final allDrItems = ref
                .read(destructionRequestItemsProvider)
                .valueOrNull ?? const [];
            final packageYards = <String, String>{};
            // forfeited_package_id → the specific package_item id it covers, so
            // the destruction row is item-scoped (Mark Destroyed destroys only
            // that item, not the whole package).
            final packageItems = <String, String?>{};
            for (final key in _selected.keys) {
              final drItemId = key.contains('_') ? key.split('_').first : key;
              final drItem = allDrItems
                  .where((it) => it.id == drItemId)
                  .firstOrNull;
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
                    saleNumber: _numberC.text.trim().isEmpty ? null : _numberC.text.trim(),
                    saleDate: _saleDate,
                    saleTime:
                        _saleTime == null ? null : _timeOfDayToHHmm(_saleTime!),
                    serial:
                        _serialC.text.trim().isEmpty ? null : _serialC.text.trim(),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              style: TextStyle(
                  color: context.colors.textMuted, fontSize: 12)),
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
            const _DisposalSearch(
                tabKey: 'undestroyed', hint: 'Search SR / item / consignee…'),
            const Gap(12),
            _YardAllFilter(
              value: ref.watch(_disposalYardFilterProvider('undestroyed')),
              onChanged: (v) => ref
                  .read(_disposalYardFilterProvider('undestroyed').notifier)
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
              child: _StatChip(
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
                    .watch(_disposalSearchProvider('undestroyed'))
                    .toLowerCase();
                final yf =
                    ref.watch(_disposalYardFilterProvider('undestroyed'));
                if (yf != null) {
                  list =
                      list.where((info) => info.forfeited.yard == yf).toList();
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
                      DataColumn2(label: Text('Item'), size: ColumnSize.L),
                      DataColumn2(label: Text('Consignee'), size: ColumnSize.M),
                      DataColumn2(
                          label: Text('Source'),
                          size: ColumnSize.S,
                          fixedWidth: 110),
                      DataColumn2(label: Text('Valuation'), size: ColumnSize.M),
                      DataColumn2(
                          label: Center(child: Text('Times Attempted')),
                          size: ColumnSize.S,
                          fixedWidth: 130),
                      DataColumn2(
                          label: Center(child: Text('Destructions')),
                          size: ColumnSize.S,
                          fixedWidth: 100),
                      DataColumn2(
                          label: Center(child: Text('Details')),
                          size: ColumnSize.S,
                          fixedWidth: 64),
                    ],
                    rows: list.map((info) {
                      final f = info.forfeited;
                      final pkg = f.packageDetails;
                      return DataRow(cells: [
                        DataCell(Text(f.srNumber,
                            style: TextStyle(
                                color: context.colors.accentLightBlue,
                                fontWeight: FontWeight.w600))),
                        DataCell(Text(_itemName(f),
                            overflow: TextOverflow.ellipsis)),
                        DataCell(Text(f.consigneeName,
                            overflow: TextOverflow.ellipsis)),
                        DataCell(_SourceChip(source: f.source)),
                        DataCell(_ValuationCell(f: f)),
                        DataCell(Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: amber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: amber.withOpacity(0.4)),
                            ),
                            child: Text('${info.timesAttempted}×',
                                style: TextStyle(
                                    color: amber, fontWeight: FontWeight.w800)),
                          ),
                        )),
                        DataCell(Center(
                          child: IconButton(
                            icon: const Icon(Icons.history_rounded, size: 18),
                            color: context.colors.accentLightBlue,
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => _DestructionSaleHistoryDialog(info: info),
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
                                      valuationTotalCost: f.valuationCost != null
                                          ? f.valuationCost! * (f.entryQty ?? 1)
                                          : null,
                                      valuationQty: f.entryQty,
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
          builder: (_) => OneTapDatePicker(initialDate: value ?? DateTime.now()),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_month_rounded),
        ),
        child: Text(
          value != null ? DateFormat('yyyy-MM-dd').format(value!) : 'Select sale date',
          style: value == null
              ? TextStyle(color: context.colors.textMuted)
              : null,
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
          builder: (_) => OneTapTimePicker(initialTime: value ?? TimeOfDay.now()),
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
          style: value == null
              ? TextStyle(color: context.colors.textMuted)
              : null,
        ),
      ),
    );
  }
}

// ── Valuation Cell shared by Tender Sales, Destructions, Unsold, Undestroyed ──

class _ValuationCell extends StatelessWidget {
  final ForfeitedPackageModel? f;
  const _ValuationCell({required this.f});

  @override
  Widget build(BuildContext context) {
    final fp = f;
    final unitCost = fp?.valuationCost;
    if (unitCost == null || fp == null) {
      return Text('—', style: TextStyle(color: context.colors.textMuted));
    }
    final int qty;
    if (fp.entryQty != null) {
      qty = fp.entryQty!;
    } else if (fp.itemId != null) {
      qty = fp.packageDetails?.items
              .where((i) => i.id == fp.itemId)
              .firstOrNull
              ?.quantity ??
          1;
    } else {
      qty = fp.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 1;
    }
    final total = unitCost * qty;
    final fmt = NumberFormat('#,##0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'LKR ${fmt.format(total)}',
          style: TextStyle(
              color: context.colors.primaryGold,
              fontWeight: FontWeight.w700,
              fontSize: 12),
        ),
        Text(
          '@ ${fmt.format(unitCost)} × $qty',
          style: TextStyle(color: context.colors.textMuted, fontSize: 10),
        ),
      ],
    );
  }
}
