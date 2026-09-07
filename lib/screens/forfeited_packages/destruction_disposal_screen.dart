import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/app_session.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/error_view.dart';
import '../../widgets/date_range_picker_dialog.dart' as custom;
import '../../widgets/year_filter.dart';
import '../../widgets/table_pager.dart';
import '../disposal/disposal_dashboard_screen.dart';

// ── Local providers ────────────────────────────────────────────

final destructionSearchProvider = StateProvider<String>((ref) => '');

// ── Screen ─────────────────────────────────────────────────────
// Yard view-only Destruction Sales — mirrors the Tender Sale screen. Shows the
// destruction sales that include packages from this yard. Read-only: the cards
// never drop rows when the destroy window closes and the timer is hidden, so the
// yard can always see the full outcome (Mark Destroyed is the directorate's).

class DestructionDisposalScreen extends ConsumerStatefulWidget {
  const DestructionDisposalScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DestructionDisposalScreen> createState() =>
      _DestructionDisposalScreenState();
}

class _DestructionDisposalScreenState
    extends ConsumerState<DestructionDisposalScreen> {
  final _searchCtrl = TextEditingController();
  DateTimeRange? _dateRange;
  String? _yearFilter;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchCtrl.text = ref.read(destructionSearchProvider);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(destructionSearchProvider);
    final myYard = AppSession.currentYard;

    // ⚠️ One page from SQL. This screen loaded EVERY destruction with
    // its items, their forfeited rows, packages, package items and warehouse
    // entries, then filtered by yard, search, date range and year here and
    // paged the result with `pageSlice` -- which still loads everything and
    // only renders less.
    final query = DestructionQuery(
      page: _page,
      search: search.trim().isEmpty ? null : search.trim(),
      // The yard is the FILTER: this page is "destructions that include
      // packages from this yard", matched on the yards the ITEMS carry.
      yardFilter: myYard,
      dateStart: _dateRange?.start,
      dateEnd: _dateRange?.end,
      year: _yearFilter,
    );
    final salesAsync = ref.watch(destructionsPageProvider(query));
    // ⚠️ Over ALL destructions, not this page: derived from twenty rows
    // a destruction would be called new because its predecessor sat on the
    // page before.
    final redestructionIds =
        ref.watch(redestructionIdsProvider).valueOrNull ?? const <String>{};

    return AppShell(
      currentRoute: '/destruction-disposals',
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
                  Text('Destruction Sale',
                      style: Theme.of(context).textTheme.headlineLarge),
                  Text(
                    'Destruction sales that include packages from this yard',
                    style: TextStyle(color: context.colors.textSecondary),
                  ),
                ],
              ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
              const Gap(20),

              // ── Search Bar ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: context.colors.primaryGold.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      style: TextStyle(color: context.colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search by sale number or SR number...',
                        prefixIcon: Icon(Icons.search_rounded,
                            color: context.colors.textMuted),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear_rounded,
                                    color: context.colors.textMuted),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  ref
                                      .read(destructionSearchProvider.notifier)
                                      .state = '';
                                },
                              )
                            : null,
                        isDense: true,
                      ),
                      onChanged: (v) {
                        ref.read(destructionSearchProvider.notifier).state = v;
                        setState(() => _page = 0);
                      },
                    ),
                    const Gap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDialog<dynamic>(
                              context: context,
                              builder: (context) =>
                                  custom.DateRangePickerDialog(
                                      initialRange: _dateRange),
                            );
                            if (picked is DateTimeRange) {
                              setState(() {
                                _dateRange = picked;
                                _page = 0;
                              });
                            } else if (picked == false) {
                              setState(() {
                                _dateRange = null;
                                _page = 0;
                              });
                            }
                          },
                          icon: Icon(Icons.date_range_rounded,
                              size: 16,
                              color: _dateRange != null
                                  ? context.colors.primaryGold
                                  : context.colors.textSecondary),
                          label: Text(
                            _dateRange != null
                                ? '${DateFormat('MMM d').format(_dateRange!.start)} - ${DateFormat('MMM d').format(_dateRange!.end)}'
                                : 'Date Range',
                            style: TextStyle(
                                color: _dateRange != null
                                    ? context.colors.primaryGold
                                    : context.colors.textSecondary,
                                fontSize: 12,
                                fontWeight: _dateRange != null
                                    ? FontWeight.bold
                                    : FontWeight.normal),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: _dateRange != null
                                    ? context.colors.primaryGold
                                    : context.colors.borderColor),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        if (_dateRange != null)
                          IconButton(
                            icon: Icon(Icons.clear_rounded,
                                size: 16, color: context.colors.dangerRed),
                            onPressed: () => setState(() {
                              _dateRange = null;
                              _page = 0;
                            }),
                            tooltip: 'Clear Date Filter',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        const SizedBox(width: 8),
                        YearFilterButton(
                          value: _yearFilter,
                          // ⚠️ From ALL destructions, not the page.
                          years: ref
                                  .watch(destructionYearsProvider)
                                  .valueOrNull ??
                              const <String>[],
                          onChanged: (v) => setState(() {
                            _yearFilter = v;
                            _page = 0;
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              )
                  .animate()
                  .slideY(begin: 0.1, duration: 400.ms, delay: 200.ms)
                  .fadeIn(),

              const Gap(16),

              // ── Destruction sales list (view-only, this yard's packages) ──
              Expanded(
                child: salesAsync.when(
                  loading: () => Center(
                      child: CircularProgressIndicator(
                          color: context.colors.primaryGold)),
                  error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () =>
                          ref.refresh(destructionsPageProvider(query))),
                  data: (data) {
                    // ⚠️ Nothing is filtered here any more. The yard, the
                    // search, the date range and the year are all SQL
                    // predicates -- filtering a page would narrow the twenty
                    // rows on screen while the pager went on counting the
                    // destructions it had just removed.
                    final visible = data.rows;

                    if (visible.isEmpty) {
                      return Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.colors.cardDark,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: context.colors.borderColor),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.local_fire_department_rounded,
                                color: context.colors.textMuted, size: 48),
                            const Gap(12),
                            Text('No destruction sales for this yard yet',
                                style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 16)),
                            const Gap(6),
                            Text(
                                'Sales are created centrally by the Disposal Directorate',
                                style: TextStyle(
                                    color: context.colors.textMuted,
                                    fontSize: 13)),
                          ],
                        ),
                      );
                    }

                    final pageItems = visible;
                    final retenderIds = redestructionIds;
                    return Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            itemCount: pageItems.length,
                            separatorBuilder: (_, __) => const Gap(16),
                            itemBuilder: (context, i) => DestructionCard(
                                sale: pageItems[i],
                                readOnly: true,
                                isRetender:
                                    retenderIds.contains(pageItems[i].id)),
                          )
                              .animate()
                              .slideY(
                                  begin: 0.1,
                                  duration: 400.ms,
                                  delay: 300.ms)
                              .fadeIn(),
                        ),
                        TablePager(
                          // ⚠️ The SERVER's count: `visible.length` is
                          // the page size now.
                          total: data.total,
                          page: _page,
                          pageSize: kDispositionPageSize,
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
