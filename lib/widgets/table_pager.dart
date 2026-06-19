import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Default rows shown per page on the client-paged disposition tables.
const int kClientPageSize = 20;

/// A compact "Showing X–Y of N · ‹ Page n ›" pager bar shown under a table.
/// Used by the client-paged lists (Released / Sold / Destroyed / Re-exported)
/// to page through already-loaded+filtered rows, matching the Package History
/// pager. Returns nothing when there's a single page (kept hidden by the caller
/// if preferred).
class TablePager extends StatelessWidget {
  final int total;
  final int page; // zero-based
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  const TablePager({
    super.key,
    required this.total,
    required this.page,
    required this.onPageChanged,
    this.pageSize = kClientPageSize,
  });

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : page * pageSize + 1;
    final to = ((page + 1) * pageSize).clamp(0, total);
    final hasPrev = page > 0;
    final hasNext = to < total;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Text(
              total == 0 ? 'No records' : 'Showing $from–$to of $total',
              style:
                  TextStyle(color: context.colors.textSecondary, fontSize: 13)),
          const Spacer(),
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left_rounded),
            color: context.colors.primaryGold,
            onPressed: hasPrev ? () => onPageChanged(page - 1) : null,
          ),
          Text('Page ${page + 1}',
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right_rounded),
            color: context.colors.primaryGold,
            onPressed: hasNext ? () => onPageChanged(page + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Returns the slice of [all] for [page] (zero-based), [pageSize] per page.
List<T> pageSlice<T>(List<T> all, int page, [int pageSize = kClientPageSize]) {
  final start = page * pageSize;
  if (start >= all.length) return const [];
  return all.skip(start).take(pageSize).toList();
}
