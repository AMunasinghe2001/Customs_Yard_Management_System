import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../widgets/page_title.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/table_pager.dart';
import '../disposal/disposal_dashboard_screen.dart'
    show TenderSaleCard;
import 'executive_header.dart';

/// Tender sales as the Top Management Directorate sees them: read-only, and
/// showing exactly what Central Disposal is currently working on.
///
/// Deliberately NOT the yard's view, which keeps every sale ever run. This one
/// applies the same visibility rule Central Disposal's own tab does — a sale
/// stays only while it has unsold items AND its window is still open — so the
/// moment Central Disposal marks the last item, or the window closes, the sale
/// leaves this page too. That is the whole point: this page answers "what is
/// live right now", and the caption says so, because a page that silently
/// drops rows is otherwise alarming.
class TenderSalesViewTab extends ConsumerStatefulWidget {
  const TenderSalesViewTab({super.key});

  @override
  ConsumerState<TenderSalesViewTab> createState() => _TenderSalesViewTabState();
}

class _TenderSalesViewTabState extends ConsumerState<TenderSalesViewTab> {
  String _search = '';
  String? _yard; // null = all yards
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    // The portal's own accent, so the yard dropdown and the count chip match
    // the tab strip above them. This was customsBlue, which is a different
    // blue from the teal every other Top Management control uses.
    final accent = AppTheme.executiveTeal;
    // ⚠️ ONE PAGE, and the SAME worklist rule Central Disposal applies.
    //
    // `tenderSalesProvider` is the heaviest query in the app -- every sale
    // with its items, their forfeited rows, packages, package items and
    // warehouse entries -- and this tab watched all twenty-eight yards'
    // worth. It then showed every sale, including the seventy-odd whose items
    // were all decided: Top Management was reading a list of finished work.
    //
    // `onlyPending` is the view's has_pending (postgres/35): a sale where
    // something is still UNDECIDED. The two portals now agree on what is
    // live.
    final query = TenderSaleQuery(
      page: _page,
      search: _search,
      yardFilter: _yard,
      onlyPending: true,
    );
    final async = ref.watch(tenderSalesPageProvider(query));

    return Padding(
      // ⚠️ 16, not 24. These pages are TABLES, and vertical chrome is rows
      // the officer cannot see. Central Disposal tightened to this for the
      // same reason; matching it also keeps the two portals looking alike.
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: PageTitle(
                  'Tender Sales',
                  Icons.storefront_rounded,
                  subtitle: 'Live sales at Central Disposal — a sale leaves this page once every item is decided or its window closes',
                  accent: accent,
                ),
              ),
              const Gap(16),
              ExecutiveSearchField(
                hint: 'Search sale no / SR…',
                onChanged: (v) => setState(() {
                  _search = v;
                  _page = 0;
                }),
              ),
              const Gap(12),
              SizedBox(
                width: 220,
                child: ExecutiveYardFilter(
                  value: _yard,
                  onChanged: (v) => setState(() {
                    _yard = v;
                    _page = 0;
                  }),
                ),
              ),
            ],
          ).animate().fadeIn(duration: 300.ms),
          const Gap(12),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () =>
                  Center(child: CircularProgressIndicator(color: accent)),
              error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.refresh(tenderSalesPageProvider(query))),
              data: (result) {
                // ⚠️ Filtered and paged by the database. The yard filter and
                // the "something is still undecided" rule both reached SQL,
                // so `pageItems` IS the page.
                final pageItems = result.rows;
                final total = result.total;
                final maxPage =
                    total == 0 ? 0 : (total - 1) ~/ kDispositionPageSize;
                final page = _page.clamp(0, maxPage);
                if (page != _page) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _page = page);
                  });
                }

                if (pageItems.isEmpty) {
                  return const EmptyTableState(
                    icon: Icons.storefront_outlined,
                    message: 'No tender sales running',
                    subtitle:
                        'Sales appear here while Central Disposal is running '
                        'them, and leave once every item is decided.',
                  );
                }

                // ⚠️ Over ALL sales, not this page: a sale would otherwise
                // be marked new simply because its predecessor sat on the
                // page before. Its own provider, as on Central Disposal.
                final retenderIds =
                    ref.watch(retenderSaleIdsProvider).valueOrNull ??
                        const <String>{};

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _LiveChip(count: total, accent: accent),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: pageItems.length,
                        separatorBuilder: (_, __) => const Gap(16),
                        // readOnly: Top Management observes; Central Disposal
                        // is what actually marks an item sold or unsold.
                        itemBuilder: (context, i) => TenderSaleCard(
                          sale: pageItems[i],
                          // Top Management observes; Central Disposal is what
                          // actually marks an item sold or unsold.
                          readOnly: true,
                          // ⚠️ But this is a WORKLIST, not a record. An item
                          // already marked has left Central Disposal's hands
                          // -- it is on Sold Goods or in the Unsold Tenders
                          // pool -- and showing it here presents finished work
                          // as though a decision were still pending. The
                          // YARD's copy of this card is the record and keeps
                          // every item.
                          showDecidedItems: false,
                          isRetender: retenderIds.contains(pageItems[i].id),
                        ),
                      ),
                    ),
                    TablePager(
                      // The DATABASE's count for this filter.
                      total: total,
                      page: page,
                      accent: accent,
                      onPageChanged: (p) => setState(() => _page = p),
                    ),
                  ],
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// How many sales are live, and a reminder that the number moves on its own.
class _LiveChip extends StatelessWidget {
  final int count;
  final Color accent;
  const _LiveChip({required this.count, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.storefront_rounded, size: 15, color: accent),
        const Gap(8),
        Text('$count sale${count == 1 ? '' : 's'} running now',
            style: TextStyle(
                color: accent, fontSize: 12.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
