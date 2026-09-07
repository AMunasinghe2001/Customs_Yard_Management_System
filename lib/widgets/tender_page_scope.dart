import 'package:flutter/widgets.dart';

import '../core/providers.dart';

/// The forfeited-package ids of the page a tender table is showing.
///
/// ⚠️ Four cells on the Unsold Tenders table each fetched their own row's
/// bids or re-valuations: `_UnsoldValuationCell`, `_LatestValuationCell`,
/// `_ReTenderStatusCell` and `_BidsCell` all read
/// `tenderRevaluationsProvider(fpId)` or `tenderBidsProvider(fpId)` from
/// inside their build. Twenty rows meant twenty round trips per cell.
/// Measured at page size: 74ms for the re-valuations and 57ms for the bids as
/// separate calls, against 14ms and 22ms as one query each.
///
/// This is the same shape as `DestructionExpenseScope`, and it exists for the
/// same reason: **paging a table does not page what its CELLS fetch.**
///
/// ⚠️ An InheritedWidget rather than a constructor argument. The cells are
/// built deep inside a `DataTable2` row builder, and threading the page's ids
/// through every one of them would put the page's shape into each cell.
class TenderPageScope extends InheritedWidget {
  /// The page's forfeited-package ids, joined — this is the provider's family
  /// key, so it must be stable for a given page or every rebuild opens a fresh
  /// query, trading one slow load for a permanent one.
  final String packageKey;

  const TenderPageScope({
    super.key,
    required this.packageKey,
    required super.child,
  });

  /// Builds the key from a page's rows.
  ///
  /// ⚠️ One definition, shared with the providers that consume it.
  /// Two copies of "sorted, de-duplicated, pipe-joined" is two chances for a
  /// key built here to miss the cache filled there -- and the symptom would be
  /// a page that fetches twice and looks merely slow.
  static String keyFor(Iterable<String> ids) => packageKeyOf(ids);

  /// The enclosing page's key, or '' when a cell is built outside one — a
  /// dialog, say. ⚠️ An empty key means the page-wide providers return
  /// nothing, so a caller that can be built either way must fall back to its
  /// own single-package fetch rather than showing a blank.
  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TenderPageScope>()?.packageKey ??
      '';

  @override
  bool updateShouldNotify(TenderPageScope old) => old.packageKey != packageKey;
}
