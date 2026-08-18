/// Post Status Activities — the follow-up action recorded against each package
/// item after its status is decided on the SR registration form.
///
/// The list shown to the officer depends on the item's Status:
///   * `Detain`  → pending-type activities (licence, classification, inquiry …)
///   * `Forfeit` / `Abandoned` / `Other` → disposal-type activities
///     (sale/auction, destruction, conversion, donation …)
///
/// This is the single source of truth: the SR form, the warehouse/abandoned/
/// returned-package filters and the reports all read from here, so adding or
/// renaming an activity only needs an edit in this file — no database change.
library;

/// Activities offered when the item status is `Detain`.
const List<String> kDetainActivities = [
  'Pending Licence',
  'Pending Classification / Valuation',
  'Pending Inquiry',
  'Other',
];

/// Activities offered when the item status is `Forfeit`, `Abandoned` or
/// `Other`.
const List<String> kDisposalActivities = [
  'Supposed to be Sold / Auction',
  'Supposed to be Destroyed',
  'Supposed to be Converted',
  'Supposed to be Donated',
  'Other',
];

/// Every activity that can be stored, used by the read-only filter dropdowns
/// that must match values already saved against existing packages.
List<String> get kAllPostStatusActivities => [
      ...kDetainActivities,
      // `Other` appears in both groups — keep it once.
      ...kDisposalActivities.where((a) => !kDetainActivities.contains(a)),
    ];

/// Activities valid for [status]. Any status other than `Detain` (including
/// free-text `Other: …` values) uses the disposal list.
List<String> postStatusActivitiesFor(String status) =>
    status == 'Detain' ? kDetainActivities : kDisposalActivities;
