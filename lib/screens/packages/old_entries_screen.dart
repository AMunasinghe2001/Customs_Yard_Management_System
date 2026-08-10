import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../core/theme.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/package_details_dialog.dart';
import '../../widgets/table_pager.dart';
import '../../widgets/tooltip_text.dart';

final oldEntrySearchProvider = StateProvider<String>((ref) => '');

/// Old Entries — packages registered under "Old Entry" mode, i.e. migrated from
/// a previous/legacy register. Shows the old SR number next to the new one.
/// The goods still flow through the normal package process; this page is just a
/// dedicated view of the migrated entries.
class OldEntriesScreen extends ConsumerStatefulWidget {
  const OldEntriesScreen({super.key});

  @override
  ConsumerState<OldEntriesScreen> createState() => _OldEntriesScreenState();
}

class _OldEntriesScreenState extends ConsumerState<OldEntriesScreen> {
  final _searchCtrl = TextEditingController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchCtrl.text = ref.read(oldEntrySearchProvider);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(livePackagesProvider);
    final storageRate = ref.watch(storageRateProvider).valueOrNull ??
        const <DateTime, double>{};
    final search = ref.watch(oldEntrySearchProvider);
    ref.listen(oldEntrySearchProvider, (_, __) => setState(() => _page = 0));

    return AppShell(
      currentRoute: '/old-entries',
      child: Scaffold(
        backgroundColor: context.colors.scaffoldBg,
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Old Entries',
                      style: Theme.of(context).textTheme.headlineLarge),
                  Text(
                    'Packages migrated from a previous register (old SR → new SR)',
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                ],
              ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
              const Gap(20),

              // ── Search ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: context.colors.primaryGold.withOpacity(0.5)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: context.colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search by old SR, new SR or consignee...',
                    prefixIcon: Icon(Icons.search_rounded,
                        color: context.colors.textMuted),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded,
                                color: context.colors.textMuted),
                            onPressed: () {
                              _searchCtrl.clear();
                              ref.read(oldEntrySearchProvider.notifier).state =
                                  '';
                            },
                          )
                        : null,
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      ref.read(oldEntrySearchProvider.notifier).state = v,
                ),
              )
                  .animate()
                  .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                  .fadeIn(),
              const Gap(16),

              // ── Table ───────────────────────────────────────────
              Expanded(
                child: packagesAsync.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.refresh(livePackagesProvider)),
                  data: (packages) {
                    // Only packages that carry a legacy SR number.
                    var rows = packages
                        .where((p) =>
                            p.oldSrNumber != null &&
                            p.oldSrNumber!.trim().isNotEmpty)
                        .toList();

                    final q = search.trim().toLowerCase();
                    if (q.isNotEmpty) {
                      rows = rows
                          .where((p) =>
                              (p.oldSrNumber ?? '')
                                  .toLowerCase()
                                  .contains(q) ||
                              p.srNumber.toLowerCase().contains(q) ||
                              p.consigneeName.toLowerCase().contains(q))
                          .toList();
                    }
                    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    final pageRows = rows
                        .skip(_page * kClientPageSize)
                        .take(kClientPageSize)
                        .toList();

                    return Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                                color: context.colors.cardDark,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: context.colors.borderColor)),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: DataTable2(
                                columnSpacing: 12,
                                horizontalMargin: 12,
                                fixedTopRows: 1,
                                empty: const EmptyTableState(
                                    message: 'No old entries yet'),
                                isVerticalScrollBarVisible: true,
                                columns: const [
                                  DataColumn2(
                                      label: Text('Old SR Number'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('New SR Number'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Consignee'),
                                      size: ColumnSize.M),
                                  DataColumn2(
                                      label: Text('Entry Date'),
                                      size: ColumnSize.S,
                                      fixedWidth: 120),
                                  DataColumn2(
                                      label: Text('Items'),
                                      size: ColumnSize.S,
                                      fixedWidth: 70),
                                  DataColumn2(
                                      label: Center(child: Text('Details')),
                                      size: ColumnSize.S,
                                      fixedWidth: 60),
                                ],
                                rows: pageRows
                                    .map((p) => DataRow(cells: [
                                          DataCell(TooltipText(
                                              p.oldSrNumber ?? '—',
                                              style: TextStyle(
                                                  color: context
                                                      .colors.primaryGold,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                          DataCell(TooltipText(p.srNumber,
                                              style: TextStyle(
                                                  color: context.colors
                                                      .accentLightBlue,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                          DataCell(TooltipText(
                                              p.consigneeName,
                                              overflow:
                                                  TextOverflow.ellipsis)),
                                          DataCell(TooltipText(p.entryDate !=
                                                  null
                                              ? DateFormat('yyyy-MM-dd')
                                                  .format(p.entryDate!)
                                              : '—')),
                                          DataCell(Center(
                                              child: Text(
                                                  '${p.totalItemCount}'))),
                                          DataCell(Center(
                                              child: IconButton(
                                            icon: Icon(
                                                Icons.info_outline_rounded,
                                                color: context
                                                    .colors.accentLightBlue,
                                                size: 18),
                                            onPressed: () => showDialog(
                                              context: context,
                                              builder: (_) =>
                                                  PackageDetailsDialog(
                                                package: p,
                                                storageRate: storageRate,
                                                useLegacySummary: true,
                                              ),
                                            ),
                                          ))),
                                        ]))
                                    .toList(),
                              ),
                            ),
                          ),
                        ),
                        TablePager(
                          total: rows.length,
                          page: _page,
                          pageSize: kClientPageSize,
                          onPageChanged: (p) => setState(() => _page = p),
                        ),
                      ],
                    );
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
