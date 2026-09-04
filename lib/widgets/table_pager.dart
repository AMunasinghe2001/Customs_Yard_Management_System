import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import '../core/theme.dart';

/// Default rows shown per page on the client-paged disposition tables.
const int kClientPageSize = 20;

/// The pager bar under every table in the app.
///
/// ⚠️ **Numbered**, not just ‹ Page 3 ›. The arrows-only bar could not answer
/// "how far through am I" or "how much is there", and reaching page 12 meant
/// eleven clicks. The numbers, the window of them around the current page and
/// the ellipses are the ICT console's design, brought here so every table in
/// the app pages the same way — an officer should not have to learn a second
/// one.
///
/// The whole app goes through this one widget, so a change here reaches all
/// twenty-odd tables at once.
class TablePager extends StatelessWidget {
  final int total;

  /// Zero-based.
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  /// The colour of the selected page. Defaults to the yard's gold; the
  /// directorate portals pass their own so the pager belongs to the page it
  /// sits under rather than importing the yard's palette.
  final Color? accent;

  const TablePager({
    super.key,
    required this.total,
    required this.page,
    required this.onPageChanged,
    this.pageSize = kClientPageSize,
    this.accent,
  });

  /// The page numbers to draw, with nulls where an ellipsis goes.
  ///
  /// Always shows the first and last page — those are the two people actually
  /// aim for — plus a window around wherever they are now. Seven or fewer
  /// pages fit whole, so no ellipsis is drawn at all.
  static List<int?> windowFor(int page, int pageCount) {
    if (pageCount <= 7) return [for (var i = 0; i < pageCount; i++) i];
    final out = <int?>[0];
    var from = page - 1, to = page + 1;
    if (page <= 2) {
      from = 1;
      to = 3;
    }
    if (page >= pageCount - 3) {
      from = pageCount - 4;
      to = pageCount - 2;
    }
    if (from > 1) out.add(null);
    for (var i = from; i <= to; i++) {
      if (i > 0 && i < pageCount - 1) out.add(i);
    }
    if (to < pageCount - 2) out.add(null);
    out.add(pageCount - 1);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = accent ?? c.primaryGold;
    final pageCount = total == 0 ? 0 : ((total - 1) ~/ pageSize) + 1;
    final from = total == 0 ? 0 : page * pageSize + 1;
    final to = ((page + 1) * pageSize).clamp(0, total);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: [
        Text(total == 0 ? 'No records' : 'Showing $from–$to of $total',
            style: TextStyle(color: c.textSecondary, fontSize: 13)),
        const Spacer(),
        _PagerStep(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous page',
          onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
        ),
        const Gap(6),
        for (final p in windowFor(page, pageCount)) ...[
          if (p == null)
            SizedBox(
              width: 22,
              child: Text('…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textMuted, fontSize: 13)),
            )
          else
            _PagerNumber(
              number: p + 1,
              selected: p == page,
              accent: tint,
              onPressed: () => onPageChanged(p),
            ),
          const Gap(4),
        ],
        const Gap(2),
        _PagerStep(
          icon: Icons.chevron_right_rounded,
          tooltip: 'Next page',
          onPressed: to < total ? () => onPageChanged(page + 1) : null,
        ),
      ]),
    );
  }
}

class _PagerNumber extends StatelessWidget {
  const _PagerNumber({
    required this.number,
    required this.selected,
    required this.accent,
    required this.onPressed,
  });

  final int number;
  final bool selected;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selected ? null : onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 28),
          height: 28,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? accent : c.borderColor),
          ),
          child: Text('$number',
              style: TextStyle(
                  color: selected ? Colors.white : c.textSecondary,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
        ),
      ),
    );
  }
}

class _PagerStep extends StatelessWidget {
  const _PagerStep({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;

  /// Null at the end of the run, which greys the arrow out.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final on = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: on ? c.borderColor : c.borderColor.withOpacity(0.4)),
            ),
            child:
                Icon(icon, size: 17, color: on ? c.textSecondary : c.textMuted),
          ),
        ),
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
