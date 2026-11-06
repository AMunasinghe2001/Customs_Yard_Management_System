import 'sealed_valuation.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart'
    show
        Wrap,
        RoundedRectangleBorder,
        Colors,
        Icons,
        Theme,
        FontWeight,
        BorderRadius,
        Radius,
        BoxConstraints,
        BoxShadow,
        Offset,
        Border,
        BorderSide,
        IconButton,
        ElevatedButton,
        CircularProgressIndicator,
        ScaffoldMessenger,
        SnackBar,
        showDialog,
        BuildContext,
        Widget,
        Row,
        Column,
        Expanded,
        Icon,
        Text,
        Padding,
        EdgeInsets,
        Center,
        SingleChildScrollView,
        Form,
        GlobalKey,
        FormState,
        TextFormField,
        InputDecoration,
        OutlineInputBorder,
        DropdownButtonFormField,
        DropdownMenuItem,
        SizedBox,
        Brightness,
        Color,
        IconData,
        Dialog,
        Tween,
        TweenAnimationBuilder,
        AnimationController,
        Animation,
        CurvedAnimation,
        AnimatedBuilder,
        SingleTickerProviderStateMixin,
        Transform,
        Opacity,
        Curves,
        MainAxisSize,
        CrossAxisAlignment,
        BoxDecoration,
        StatelessWidget,
        LinearGradient,
        Flexible,
        Navigator,
        MainAxisAlignment,
        TextButton,
        BoxShape,
        FontStyle,
        TextStyle,
        Container,
        OutlinedButton,
        TextEditingController,
        MediaQuery,
        TextInputType,
        VoidCallback,
        Spacer,
        TextOverflow,
        StatefulWidget,
        StatefulBuilder,
        ConstrainedBox,
        State,
        InkWell,
        AlwaysStoppedAnimation,
        Positioned,
        SnackBarBehavior,
        Stack;
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../core/theme.dart';
import 'dialog_close_button.dart';
import '../models/models.dart';
import '../core/providers.dart';
import '../core/post_status_activities.dart';
import 'styled_dropdown.dart';
import 'one_tap_date_picker.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/services.dart';
import 'error_view.dart';
import 'appeal_state_chip.dart';
import 'storage_charge_note.dart';
import '../widgets/app_dialog.dart';
import 'displaced_badge.dart';

/// The valuation row shown in the Sale / Destruction sections.
///
/// Shows the **LATEST** valuation: if the package was re-valued for a later
/// tender round that figure wins over the Valuation Directorate's first one,
/// and the row is marked "re-valued" — the same rule the Unsold tables use.
/// Formatted like those tables too: total first, then `@ unit x qty`.
class _ValuationDetailRow extends ConsumerWidget {
  final ForfeitedPackageModel fp;

  /// The quantity actually sold / destroyed, when the caller knows it.
  final int? soldQty;

  const _ValuationDetailRow({required this.fp, this.soldQty});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revals =
        ref.watch(tenderRevaluationsProvider(fp.id)).valueOrNull ?? const {};
    TenderRevaluationModel? latest;
    for (final r in revals.values) {
      if (latest == null || r.createdAt.isAfter(latest.createdAt)) latest = r;
    }
    final unit = latest?.valuationCost ?? fp.valuationCost;
    if (unit == null) return const SizedBox.shrink();

    final int qty;
    if (soldQty != null && soldQty! > 0) {
      qty = soldQty!;
    } else if (fp.entryQty != null) {
      qty = fp.entryQty!;
    } else if (fp.itemId != null) {
      qty = fp.packageDetails?.items
              .where((i) => i.id == fp.itemId)
              .firstOrNull
              ?.quantity ??
          1;
    } else {
      qty =
          fp.packageDetails?.items.fold<int>(0, (s, i) => s + i.quantity) ?? 1;
    }

    final money = NumberFormat('#,##0.##');
    final revalued = latest != null;
    return _DetailItem(
      icon: Icons.calculate_rounded,
      label: revalued ? 'Valuation (Rs) · re-valued' : 'Valuation (Rs)',
      value: '${money.format(unit * qty)}'
          '  (@ ${money.format(unit)} × $qty)',
      valueColor: revalued ? context.colors.accentLightBlue : null,
    );
  }
}

/// Per-round tender history for an unsold package: the valuation each round
/// was offered at, and the bids that came in against it.
///
/// Shown on the Unsold popup so the whole story is visible in one place —
/// the Valuation Tender, then Tender 1/2/3, then the committee-priced round,
/// each with its price and its bids. Rounds with neither a valuation nor a
/// bid are skipped, and the section hides itself entirely when there is
/// nothing to show.
class TenderHistorySection extends ConsumerWidget {
  final ForfeitedPackageModel forfeited;

  /// Quantity this row covers, so a per-item unit price can be totalled.
  final int? qty;

  /// The Valuation Directorate is reading its OWN figures.
  ///
  /// ⚠️ A reserve price is sealed until bidding closes so nobody can bid
  /// against it -- but the directorate that SET it cannot be kept from it.
  /// Sealing there hides a number from the only people whose job is to
  /// decide it, and they are setting the NEXT round's price from exactly
  /// these rounds.
  final bool valuerView;

  /// Whether to render the final outcome tile at the bottom.
  final bool showFinalOutcome;

  const TenderHistorySection({
    super.key,
    required this.forfeited,
    this.qty,
    this.showFinalOutcome = true,
    this.valuerView = false,
  });

  /// True when these goods are PERISHABLE.
  ///
  /// ⚠️ A perishable runs ONE special tender sale. If it fails the goods
  /// go straight to the Top Management Directorate through Unsold
  /// Perishables -- there is no re-valuation and no second round, because
  /// the goods are rotting. So this section must not offer the vocabulary
  /// of a package that gets four attempts: no bids, no "re-valued" badge,
  /// no "Tender 1", and no committee.
  bool get _isPerishable =>
      forfeited.source.trim().toLowerCase() == 'perishable';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revals = _isPerishable
        ? const <String, TenderRevaluationModel>{}
        : (ref.watch(tenderRevaluationsProvider(forfeited.id)).valueOrNull ??
            const <String, TenderRevaluationModel>{});
    // ⚠️ Not fetched at all for a perishable. Migration 62 deleted the 20
    // that existed and added a trigger, but a stale row must not be able to
    // put a bid chip under a round nobody can re-price.
    final bids = _isPerishable
        ? const <String, List<double>>{}
        : (ref.watch(tenderBidsProvider(forfeited.id)).valueOrNull ??
            const <String, List<double>>{});
    // The committee round is priced by the ADG's submission. The seed also
    // records that as a tender_revaluations row, but a package valued through
    // the UI may not have one yet — so fall back to the committee itself,
    // otherwise the round would vanish from this list.
    final committeeAsync = ref.watch(tenderCommitteesProvider);
    // A committee is appointed after four failed rounds; a perishable has
    // one, so it can never reach that door.
    final committee =
        _isPerishable ? null : committeeAsync.valueOrNull?[forfeited.id];
    // ⚠️ Whether this package's story has ENDED. Converted, auctioned, taken
    // into government use, removed -- after any of those there is no next
    // tender, so nothing below may announce one.
    final proposal =
        ref.watch(unsoldProposalsProvider).valueOrNull?[forfeited.id];
    final decided = proposal != null;
    // Members only exist once the DG/ADG appointed the committee. Held in a
    // local so every branch below reads the same list.
    final committeeMembers = committee?.members ?? const <CommitteeMember>[];
    // The rounds THIS package sat in, oldest first — that ordering is what
    // turns a sale id into "Valuation Tender" / "Tender 1" / ...
    //
    // Fetched per package. This used to filter tenderSalesProvider, which pulls
    // EVERY sale with its items, packages and warehouses; the Tender Sales tab
    // had already cached that on Central Disposal, but the yard's Sold Goods
    // page never loads it, so the popup paid a cold ~120ms fetch and this
    // section appeared visibly later than the rest of the dialog.
    final mine =
        ref.watch(tenderRoundsForPackageProvider(forfeited.id)).valueOrNull ??
            const <({
              String id,
              DateTime createdAt,
              bool hasRun,
              bool sold,
              double? soldPrice
            })>[];

    // Any round that has a valuation or bids but no matching sale row still
    // deserves a line, so collect those ids too.
    final ordered = <String>[for (final s in mine) s.id];
    // Whether each round has actually RUN. A round still to be tendered must
    // not show its price: that is the reserve price for live bidding.
    final ranById = <String, bool>{for (final s in mine) s.id: s.hasRun};
    // ⚠️ Which round SOLD, and for how much.
    //
    // Bids are only recorded when goods FAIL to sell — a round that sold has
    // none, and it has no re-valuation of its own either, because nothing
    // needed re-pricing afterwards. The skip rule below therefore threw away
    // the one round that mattered most: the package's history stopped at the
    // last failure and never said it had sold.
    final soldById = <String, double?>{
      for (final s in mine)
        if (s.sold) s.id: s.soldPrice
    };
    for (final id in {...revals.keys, ...bids.keys}) {
      if (id.isNotEmpty && !ordered.contains(id)) ordered.add(id);
    }
    if (ordered.isEmpty) return const SizedBox.shrink();

    final effQty = (qty != null && qty! > 0)
        ? qty!
        : (forfeited.entryQty ??
            (forfeited.itemId != null
                ? (forfeited.packageDetails?.items
                        .where((i) => i.id == forfeited.itemId)
                        .firstOrNull
                        ?.quantity ??
                    1)
                : (forfeited.packageDetails?.items
                        .fold<int>(0, (a, i) => a + i.quantity) ??
                    1)));

    final money = NumberFormat('#,##0.##');
    final rows = <Widget>[];
    for (var i = 0; i < ordered.length; i++) {
      final id = ordered[i];
      final roundBids = bids[id] ?? const <double>[];
      // Bids only exist to PRICE the next round, and the committee round is
      // the last one — its price comes from the committee, not from bidding,
      // so it shows its price and nothing about bids.
      //
      // Normally the round's POSITION says it: anything past Tender 3 is
      // committee-priced. But a package whose earlier rounds were never
      // recorded would shift that index, so the last round also counts as the
      // committee round once the ADG has submitted a committee price.
      final isLastRound = i == ordered.length - 1;
      final isCommitteeRound = (i + 1) > kMaxBidTenderRounds + 1 ||
          (isLastRound && committee?.submittedValue != null && i > 0);
      // A `tender_revaluations` row is the RESERVE PRICE OF THE ROUND IT IS
      // KEYED TO. Proven against live data (SR/37/2025, Pipe Tees x180):
      //   round 1  820 x180 = 147,600  vs best bid 110,700  -> unsold
      //   round 2  738 x180 = 132,840  vs best bid 103,320  -> unsold
      //   round 3  656 x180 = 118,080  vs best bid  95,940  -> unsold
      //   round 4  574 x180 = 103,320  vs best bid 174,168  -> SOLD
      // Every round's bids sit below its own figure, and the round whose bid
      // finally cleared it is the one that sold.
      //
      // Round 1 has no re-valuation of its own — it ran at the Valuation
      // Directorate's original figure. The committee round runs at the ADG's
      // submitted value.
      final reval = revals[id];
      final unit = reval?.valuationCost ??
          (i == 0
              ? forfeited.valuationCost
              : (isCommitteeRound ? committee?.submittedValue : null));
      // A committee round is ALWAYS worth showing: it is the last attempt, and
      // hiding it would end the history at Tender 3.
      // Sealed until THIS round has run. The committee round is the clearest
      // case: the ADG submits a price and the package is only tendered at it
      // afterwards, so showing it here leaked the reserve price of a tender
      // that had not opened yet.
      // ⚠️ Never sealed for the VALUER. The seal exists so nobody can
      // bid against a live reserve price -- and the directorate that SET
      // it is not "nobody". Sealing here hid a number from the only
      // people whose job is to decide it, on the page where they decide
      // the next one.
      final sealed = !valuerView && !(ranById[id] ?? false);
      final soldHere = soldById.containsKey(id);
      // A sealed round still renders — it is the one that says "not yet".
      // ⚠️ And a round that SOLD always renders, whatever else it lacks: it
      // has no bids (bidding only happens when goods do not sell) and no
      // re-valuation (nothing was re-priced after it), so every other test
      // here would drop it.
      if (unit == null &&
          roundBids.isEmpty &&
          !isCommitteeRound &&
          !sealed &&
          !soldHere) {
        continue;
      }
      rows.add(_TenderRoundTile(
        sealed: sealed,
        // ⚠️ A perishable's one round is a SPECIAL TENDER SALE, not
        // "Valuation Tender". That name only means something as the first
        // of a series -- it is the price the goods went to tender at, before
        // the re-valuations that follow. A perishable has no series, and
        // calling its single sale "Valuation Tender" implied a Tender 1 that
        // is never coming.
        label: _isPerishable ? 'Special Tender Sale' : tenderRoundLabel(i + 1),
        isCommitteeRound: isCommitteeRound,
        isPerishableRound: _isPerishable,
        // Who set this price. Only the committee round names its officers.
        committeeMembers: isCommitteeRound ? committeeMembers : const [],
        // Separates "still loading" from "nobody was appointed", so the tile
        // can say which instead of silently listing none.
        committeeLoading: isCommitteeRound && committeeAsync.isLoading,
        // The round that sold shows what it FETCHED. On a Sold Goods popup
        // that is the number the whole page is about, and it belongs at the
        // end of the story rather than only in the table behind it.
        soldLabel: soldHere && soldById[id] != null
            ? 'Sold for LKR ${money.format(soldById[id])}'
            : (soldHere ? 'Sold' : null),
        priceLabel: (unit == null || sealed)
            ? null
            : 'LKR ${money.format(unit * effQty)}'
                '  (@ ${money.format(unit)} \u00d7 $effQty)',
        // ⚠️ The FIRST round is never a re-valuation.
        //
        // "Valuation Tender" IS the first valuation — the price the package
        // went to tender at. Every round AFTER it runs at a fresh figure, and
        // those are the re-valuations. Badging round one "re-valued" said the
        // opening price had already been revised, and put the word on the one
        // row that cannot be a revision of anything.
        //
        // (A `tender_revaluations` row keyed to round one still sets its
        // PRICE — that is what the round ran at — it just is not a revision
        // of an earlier round, because there is no earlier round.)
        revalued: i > 0 && reval != null && !isCommitteeRound,
        bids: isCommitteeRound
            ? const []
            : [for (final b in roundBids) 'LKR ${money.format(b)}'],
      ));
    }
    // The NEXT tender's price, when one is already set. Mirrors the committee
    // block: it says a figure exists and is withheld, without carrying it.
    //
    // Detected here rather than passed in, so EVERY popup that shows tender
    // history gets it — a caller cannot forget. A PENDING row (no round yet,
    // key '') is a price for a tender that has not been placed; a figure keyed
    // to a round belongs to that round and is already listed above.
    //
    // ⚠️ TWO reasons a pending row is NOT a next tender:
    //
    //   * The package already has a final outcome. Converted, auctioned,
    //     taken into government use, removed — there is no next tender after
    //     any of those, so a sealed "coming next" tile on those pages was
    //     announcing a round that can never happen.
    //   * The figure IS the committee's. The committee price is written as a
    //     pending re-valuation as well as onto the committee itself, so the
    //     same number appeared twice: once as "Committee Tender 1" and again
    //     as a phantom "Committee Tender 2". There is only ever ONE committee
    //     round.
    final pending = revals[''];
    final isCommitteePrice = pending != null &&
        committee?.submittedValue != null &&
        (pending.valuationCost - committee!.submittedValue!).abs() < 0.01;
    if (pending != null && !decided && !isCommitteePrice) {
      // ⚠️ The NEXT round's price, and the last place the seal was still
      // hardcoded. `sealed: true` here is right for every reader except the
      // one who WROTE the figure: this tile is the Valuation Directorate's
      // own pending re-valuation, and its popup told it the number was
      // "shown once the tender closes" -- on the page where it had just
      // typed it.
      //
      // The seal is not decoration. It is why the price is withheld from
      // bidders, and it stays for everyone else.
      final nextQty = qty ??
          forfeited.entryQty ??
          (forfeited.itemId != null
              ? (forfeited.packageDetails?.items
                      .where((i) => i.id == forfeited.itemId)
                      .firstOrNull
                      ?.quantity ??
                  1)
              : (forfeited.packageDetails?.items
                      .fold<int>(0, (a, i) => a + i.quantity) ??
                  1));
      rows.add(_TenderRoundTile(
        sealed: !valuerView,
        upcoming: valuerView,
        label: tenderRoundLabel(ordered.length + 1),
        isCommitteeRound: false,
        committeeMembers: const [],
        committeeLoading: false,
        priceLabel: valuerView
            ? 'LKR ${money.format(pending.valuationCost * nextQty)}'
                '  (@ ${money.format(pending.valuationCost)} \u00d7 $nextQty)'
            : null,
        revalued: true,
        bids: const [],
      ));
    }

    // If the package is at or past Tender 3 and no committee round tile was
    // added yet, add the Committee Tender 1 tile with its current appointment /
    // valuation / submission state.
    final hasCommitteeTile =
        rows.any((r) => r is _TenderRoundTile && r.isCommitteeRound);
    if (!hasCommitteeTile && (ordered.length >= 4 || committee != null)) {
      final isAppointed = committeeMembers.isNotEmpty;
      final hasValue = committee?.committeeValue != null;
      final isSubmitted = committee?.submittedValue != null;

      final String? cPriceLabel;
      final String cSubtitle;

      if (!isAppointed) {
        cPriceLabel = null;
        cSubtitle = 'Awaiting committee appointment · no bidding';
      } else if (!hasValue) {
        cPriceLabel = null;
        cSubtitle =
            'Committee appointed (${committeeMembers.length} members) · Valuation pending';
      } else if (!isSubmitted) {
        final val = committee!.committeeValue!;
        cPriceLabel =
            'LKR ${money.format(val * effQty)}  (@ ${money.format(val)} × $effQty)';
        cSubtitle =
            'Valued by committee (${committeeMembers.length} members) · Awaiting ADG submission';
      } else {
        final val = committee!.submittedValue!;
        cPriceLabel =
            'LKR ${money.format(val * effQty)}  (@ ${money.format(val)} × $effQty)';
        cSubtitle =
            'Priced by the tender committee (${committeeMembers.length} members) · no bidding';
      }

      rows.add(_TenderRoundTile(
        sealed: false,
        label: 'Committee Tender 1',
        isCommitteeRound: true,
        committeeSubtitle: cSubtitle,
        committeeMembers: committeeMembers,
        committeeLoading: committeeAsync.isLoading,
        priceLabel: cPriceLabel,
        revalued: false,
        bids: const [],
      ));
    }

    // ⚠️ How the story ENDS, at the end of the story.
    //
    // ⚠️ Not for the VALUER. Its work is one step of a process with
    // several still to run -- the price it sets goes to Central Disposal,
    // which re-tenders, and only after that does anything reach Top
    // Management. Announcing an ending on the form where the next round is
    // priced describes a future nobody has decided.
    if (showFinalOutcome && !valuerView) {
      final soldPrice = mine.where((s) => s.sold).firstOrNull?.soldPrice;
      // ⚠️ A FOURTH state: the tender is still running.
      //
      // The tile knew sold, decided, and "awaiting Top Management" -- so a
      // package on its first round, with the sale open and bidding not yet
      // closed, was told every tender had been exhausted. 71 forfeited
      // packages in this yard have exactly one round; CED/GL1/SR/18/2025's
      // Engine Cylinder Block sat in a sale opened three days ago and read
      // as though the DG were already deciding its fate.
      //
      // Goods reach Top Management only when every round has RUN and none
      // sold. `hasRun` is the same clock the round tiles seal prices on, so
      // the outcome and the rounds above it cannot disagree.
      final everySaleHasRun = mine.isNotEmpty && mine.every((s) => s.hasRun);
      rows.add(_FinalOutcomeTile(
        proposal: proposal,
        soldPrice: soldPrice,
        isPerishable: _isPerishable,
        stillRunning: !everySaleHasRun,
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return _DetailSection(
      title: 'Tender History',
      icon: Icons.history_rounded,
      delay: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

/// What Top Management finally decided — or that they have not yet.
///
/// ⚠️ Both states are drawn, because "still waiting" is an answer. A package
/// that has run out of tenders sits with the DG until they rule, and a popup
/// that showed nothing there could not be told apart from one whose outcome
/// had simply failed to load.
/// An ending with a HAND-OVER the yard is still waiting on.
///
/// ⚠️ Re-export and Release only. Both are two events wearing one date:
/// the yard RULES it -- writing the tag or the receipt -- and the goods
/// LEAVE later, when a ship sails or an owner arrives. Only the first was
/// ever stored, so both pages reported every row as finished on the day it
/// was decided.
///
/// ⚠️ NOT Sold or Destroyed. Those already state their ending twice --
/// Sold has the tender history's Final Outcome panel and a Sold Price
/// column, Destroyed has a Destruction Status & Financials section -- and a
/// third panel there repeated what was directly above it.
enum HandoverKind {
  reexport(
    title: 'Re-export Outcome',
    icon: Icons.flight_takeoff_rounded,
    decidedLabel: 'Decision Recorded',
    doneLabel: 'Shipped On',
    pendingLabel: 'Shipping Status',
    doneValue: 'Shipped',
    pendingValue: 'Not yet shipped',
    pendingHint: 'Still held by the yard',
    noteLabel: 'Reason Recorded',
    pillDone: 'SHIPPED',
    pillPending: 'PENDING',
  ),
  released(
    title: 'Release Outcome',
    icon: Icons.keyboard_return_rounded,
    decidedLabel: 'Release Recorded',
    doneLabel: 'Collected On',
    pendingLabel: 'Collection Status',
    doneValue: 'Collected',
    pendingValue: 'Not yet collected',
    pendingHint: 'Still held by the yard',
    noteLabel: 'Release Note',
    pillDone: 'COLLECTED',
    pillPending: 'PENDING',
  );

  const HandoverKind({
    required this.title,
    required this.icon,
    required this.decidedLabel,
    required this.doneLabel,
    required this.pendingLabel,
    required this.doneValue,
    required this.pendingValue,
    required this.pendingHint,
    required this.noteLabel,
    required this.pillDone,
    required this.pillPending,
  });

  final String title;
  final IconData icon;
  final String decidedLabel;
  final String doneLabel;
  final String pendingLabel;
  final String doneValue;
  final String pendingValue;
  final String pendingHint;
  final String noteLabel;
  final String pillDone;
  final String pillPending;
}

class HandoverOutcome {
  final HandoverKind kind;

  /// The note the officer wrote when recording the disposition.
  final String? note;

  /// When the disposition was recorded.
  final DateTime? decidedAt;

  /// Whether the goods have physically gone.
  final bool delivered;

  /// The day they went, when one was recorded.
  ///
  /// ⚠️ Null even on a DELIVERED row: rows marked delivered before the
  /// date column existed carry no day. The heading alone is the whole of
  /// what is known about those, and inventing a date would be worse.
  final DateTime? deliveredAt;

  const HandoverOutcome({
    required this.kind,
    this.note,
    this.decidedAt,
    required this.delivered,
    this.deliveredAt,
  });
}

/// The hand-over, in the same frame as Warehouse Summary.
///
/// ⚠️ A [_DetailSection] of [_DetailItem]s, not a tinted banner. It sits
/// directly above Warehouse Summary and the two are read as a pair -- where
/// the goods are, and whether they have gone -- so a banner in a different
/// visual language between the dialog's other sections made the popup look
/// assembled from two designs.
class _HandoverSection extends StatelessWidget {
  const _HandoverSection({required this.outcome});

  final HandoverOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final k = outcome.kind;
    final d = DateFormat('dd MMM yyyy');
    final note = (outcome.note ?? '').trim();
    final gone = outcome.delivered;
    return _DetailSection(
      title: k.title,
      icon: k.icon,
      delay: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠️ The two events side by side, because they are the whole
          // point of this section: the yard RULED it, and the goods LEFT.
          // One had been stored since the beginning; the other had nowhere
          // to live at all until it was given a column, so every row read
          // as finished on the day it was decided.
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  icon: Icons.assignment_turned_in_rounded,
                  label: k.decidedLabel,
                  value: outcome.decidedAt == null
                      ? '—'
                      : d.format(outcome.decidedAt!),
                ),
              ),
              const Gap(12),
              Expanded(
                child: _DetailItem(
                  icon: gone
                      ? Icons.check_circle_rounded
                      : Icons.schedule_rounded,
                  label: gone ? k.doneLabel : k.pendingLabel,
                  value: gone
                      ? (outcome.deliveredAt == null
                          ? k.doneValue
                          : d.format(outcome.deliveredAt!))
                      : k.pendingValue,
                  // The one figure on this section a reader scans for.
                  valueColor: gone
                      ? context.colors.successGreen
                      : context.colors.warningAmber,
                  subValue: gone ? null : k.pendingHint,
                  // ⚠️ The same pill the TABLE shows, in the same two
                  // colours. A reader who marked a row Delivered and then
                  // opened it had to re-read a date to check it had taken --
                  // the state they had just changed was the one thing the
                  // section did not show at a glance.
                  trailing: _HandoverPill(delivered: gone, kind: k),
                ),
              ),
            ],
          ),
          if (note.isNotEmpty)
            _DetailItem(
              icon: Icons.notes_rounded,
              label: k.noteLabel,
              value: note,
            ),
        ],
      ),
    );
  }
}

class _FinalOutcomeTile extends StatelessWidget {
  const _FinalOutcomeTile(
      {required this.proposal,
      this.soldPrice,
      this.isPerishable = false,
      this.stillRunning = false});

  /// A round of this package's tender has not closed yet.
  ///
  /// ⚠️ Goods reach Top Management when every round has RUN and none
  /// sold. While one is still open the story has not ended, and saying it
  /// has puts a decision in the DG's hands that nobody has asked for.
  final bool stillRunning;

  /// True for goods that ran a single SPECIAL tender sale.
  ///
  /// ⚠️ Only changes the WAITING line. A perishable reaches Top
  /// Management after one failed sale, not after exhausting four rounds
  /// and a committee, and telling an officer otherwise misdescribes the
  /// only process these goods have.
  final bool isPerishable;

  final UnsoldProposalModel? proposal;

  /// What the goods fetched, when they SOLD instead of reaching Top
  /// Management.
  ///
  /// ⚠️ A sale is a third state, not a kind of proposal. A perishable that
  /// sells never goes to the DG at all -- selling IS the ending -- so reading
  /// the outcome from unsold_proposals alone left CED/GL1/SR/30/2026 sold for
  /// Rs 5,533,000 and still showing "Awaiting Top Management" on the page that
  /// exists to say what became of it.
  final double? soldPrice;

  IconData get _icon => switch (proposal?.proposal) {
        'destroy' => Icons.local_fire_department_rounded,
        'government_use' => Icons.account_balance_rounded,
        'auction' => Icons.gavel_rounded,
        're_export' => Icons.flight_takeoff_rounded,
        'convert' => Icons.autorenew_rounded,
        'remove_from_premises' => Icons.logout_rounded,
        _ => Icons.hourglass_top_rounded,
      };

  @override
  Widget build(BuildContext context) {
    // ⚠️ Checked FIRST. Selling ends the story, so nothing below may announce
    // a decision that is still to come.
    final sold = soldPrice;
    final decided = proposal != null;
    // ⚠️ A tender still running is not an outcome at all, so it is not
    // amber either -- amber is the colour of work waiting on somebody. It
    // reads as neutral information, because that is what it is.
    final running = stillRunning && sold == null && !decided;
    final tint = (sold != null || decided)
        ? context.colors.successGreen
        : (running
            ? context.colors.accentLightBlue
            : context.colors.warningAmber);

    return material.Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tint.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                running
                    ? Icons.storefront_rounded
                    : (sold != null ? Icons.sell_rounded : _icon),
                size: 16,
                color: tint),
            const Gap(8),
            Text('FINAL OUTCOME',
                style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(
                running
                    ? 'At tender'
                    : sold != null
                        ? 'Sold'
                        : decided
                            ? unsoldProposalLabel(proposal!.proposal)
                            : 'Awaiting Top Management',
                style: TextStyle(
                    color: tint, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ]),
          if (sold != null) ...[
            const Gap(6),
            Text(
                'Sold at tender for Rs ${sold.toStringAsFixed(2)}. These goods '
                'never went to the Top Management Directorate — selling is '
                'the outcome.',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 11.5)),
          ] else if (decided) ...[
            const Gap(6),
            Text(
                'Decided on '
                '${DateFormat('dd MMM yyyy').format(proposal!.decidedAt)}'
                '${(proposal!.note ?? '').trim().isEmpty ? '' : ' \u00b7 ${proposal!.note!.trim()}'}',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 11.5)),
            // ⚠️ A decision is not a hand-over. The goods sit in the yard
            // until someone comes for them, so the outcome on its own is
            // only half the answer.
            //
            // ⚠️ Its OWN banner, the same one the Sold popup carries. This
            // was a 11.5pt line squeezed under the decision note, on pages
            // (Government Use, Auction, Re-export, Converted, Removed)
            // whose whole job is to say whether the goods have gone yet.
            // One fact, one treatment, wherever it is read.
            const Gap(10),
            DeliveryStatusBanner(
              delivered: proposal!.delivered,
              deliveredAt: proposal!.deliveredAt,
              waitingFor: 'hand-over',
              doneLabel: 'Delivered',
            ),
          ] else if (running) ...[
            const Gap(6),
            // ⚠️ Nothing has ended. Say what is happening instead of
            // announcing a decision nobody has been asked for.
            Text(
                'This package is in a tender that has not closed yet. '
                'Its outcome is decided when bidding ends.',
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 11.5)),
          ] else ...[
            const Gap(6),
            // ⚠️ "Every tender has been exhausted" describes a package
            // that failed four rounds and a committee. A perishable never
            // has four: it runs ONE special sale, and if that fails the
            // goods come here immediately -- because they are rotting, not
            // because every avenue was tried.
            Text(
                isPerishable
                    ? 'The special tender sale did not sell these goods. '
                        'Perishables go straight to Top Management for a '
                        'final decision -- there is no re-tender.'
                    : 'Every tender has been exhausted. The package is with '
                        'Top Management for a final decision.',
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}

/// Whether the goods have actually left, as a banner.
///
/// ⚠️ This was a row in a list of fields reading "Pending" in RED. Red is
/// the colour of something wrong, and goods waiting to be collected are not
/// wrong -- they are the yard's outstanding work. It also sat between a
/// receipt number and a tax figure, where the one thing a reader opens this
/// popup to check was the least visible thing on it.
///
/// ⚠️ It says WHAT IS WAITING, not just "Pending". A sale waits for a
/// buyer to collect; a re-export waits for a ship; a release waits for its
/// owner. "Pending" is the same word for three different jobs.
class DeliveryStatusBanner extends StatelessWidget {
  const DeliveryStatusBanner({
    super.key,
    required this.delivered,
    this.deliveredAt,
    this.waitingFor = 'collection',
    this.doneLabel = 'Delivered',
    this.receiptNo,
    this.charge,
  });

  final bool delivered;
  final DateTime? deliveredAt;

  /// What the goods are waiting FOR, in a word: 'collection', 'shipment'.
  final String waitingFor;

  /// The past-tense word for this ending: 'Delivered', 'Shipped',
  /// 'Collected'.
  final String doneLabel;

  /// The receipt written for the storage charge, when one was taken.
  final String? receiptNo;

  /// What was collected, when it was.
  final double? charge;

  @override
  Widget build(BuildContext context) {
    // ⚠️ GREEN when gone, AMBER while waiting -- never red. Amber is the
    // colour this app uses for work outstanding, and the delivery pill on
    // every table beside this popup already uses exactly these two.
    final tint =
        delivered ? context.colors.successGreen : context.colors.warningAmber;
    final money = NumberFormat('#,##0.00');
    final d = DateFormat('dd MMM yyyy');

    return material.Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: material.Alignment.centerLeft,
          end: material.Alignment.centerRight,
          colors: [tint.withOpacity(0.14), tint.withOpacity(0.04)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          material.Container(
            width: 40,
            height: 40,
            alignment: material.Alignment.center,
            decoration: BoxDecoration(
              color: tint.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
                delivered
                    ? Icons.check_circle_rounded
                    : Icons.local_shipping_rounded,
                size: 21,
                color: tint),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    delivered
                        ? (deliveredAt == null
                            ? doneLabel
                            : '$doneLabel on ${d.format(deliveredAt!)}')
                        : 'Awaiting $waitingFor',
                    style: material.TextStyle(
                      color: tint,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    )),
                const Gap(2),
                Text(
                    delivered
                        ? 'The goods have left the yard.'
                        : 'The goods are still in the yard, and still take '
                            'up its space.',
                    style: material.TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11.5,
                        height: 1.3)),
                // The receipt is the RECORD of the money, so it belongs
                // with the hand-over rather than three fields away.
                if (delivered &&
                    ((receiptNo ?? '').isNotEmpty || (charge ?? 0) > 0)) ...[
                  const Gap(6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    if ((receiptNo ?? '').isNotEmpty)
                      _MiniTag(
                          icon: Icons.receipt_long_rounded,
                          label: 'Receipt ${receiptNo!}',
                          tint: tint),
                    if ((charge ?? 0) > 0)
                      _MiniTag(
                          icon: Icons.payments_rounded,
                          label: 'Storage LKR ${money.format(charge)}',
                          tint: tint),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small icon+text tag, for facts that ride along with a banner.
class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.icon, required this.label, required this.tint});

  final IconData icon;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) => material.Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: tint.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tint.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: tint),
          const Gap(4),
          Text(label,
              style: material.TextStyle(
                  color: tint, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// One appointed committee officer, shown under the committee round.
class _CommitteeMemberChip extends StatelessWidget {
  final int no;
  final CommitteeMember member;

  const _CommitteeMemberChip({required this.no, required this.member});

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accentLightBlue;
    final desig = member.designation?.trim() ?? '';
    final salary = member.salaryNo?.trim() ?? '';
    final sub = [
      if (desig.isNotEmpty) desig,
      if (salary.isNotEmpty) 'Salary No: $salary',
    ].join('  ·  ');

    return material.Tooltip(
      message: sub.isEmpty ? member.name : member.name + '\n' + sub,
      waitDuration: const Duration(milliseconds: 300),
      child: material.Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          material.Container(
            width: 17,
            height: 17,
            alignment: material.Alignment.center,
            decoration: BoxDecoration(
                color: accent.withOpacity(0.18), shape: BoxShape.circle),
            child: Text('$no',
                style: TextStyle(
                    color: accent, fontSize: 9.5, fontWeight: FontWeight.w800)),
          ),
          const Gap(6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(member.name,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
              if (desig.isNotEmpty)
                Text(desig,
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 10)),
            ],
          ),
        ]),
      ),
    );
  }
}

/// One round of [TenderHistorySection]: its price and the bids against it.
class _TenderRoundTile extends StatelessWidget {
  final String label;
  final String? priceLabel;

  /// This round has not been tendered yet, so its price is withheld and the
  /// tile says so instead of showing a figure.
  final bool sealed;

  /// This round has not RUN yet, but its price is shown anyway.
  ///
  /// ⚠️ The Valuation Directorate's own view. "Not yet tendered" is
  /// still worth saying there -- it is the difference between a price that
  /// fetched nothing and one nobody has bid on -- but the reason changes:
  /// not "withheld until the tender closes", which is what the seal says,
  /// simply that the round is still to come.
  final bool upcoming;
  final bool revalued;

  /// What this round FETCHED, when it is the one that sold. Null on every
  /// other round.
  final String? soldLabel;
  final List<String> bids;

  /// The committee-priced round. It takes no bids, so the bid line is replaced
  /// by a note saying where its price came from.
  final bool isCommitteeRound;

  /// The officers the ADG appointed to value these goods. Listed under the
  /// committee round so the price and the people who set it read together.
  final List<CommitteeMember> committeeMembers;

  /// The committee list has not arrived yet. Distinguishes it from a package
  /// no committee was ever appointed for.
  final bool committeeLoading;

  /// Custom subtitle for committee round (e.g. pending / valued / submitted).
  final String? committeeSubtitle;

  /// True when this is a PERISHABLE's single special sale.
  ///
  /// ⚠️ Changes what an empty bid list MEANS. Everywhere else it is an
  /// omission -- somebody has not entered them yet. Here it is the rule:
  /// perishable goods take no bids at all.
  final bool isPerishableRound;

  const _TenderRoundTile({
    required this.label,
    required this.priceLabel,
    this.sealed = false,
    required this.revalued,
    this.soldLabel,
    required this.bids,
    this.isCommitteeRound = false,
    this.isPerishableRound = false,
    this.upcoming = false,
    this.committeeSubtitle,
    this.committeeMembers = const [],
    this.committeeLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent =
        revalued ? context.colors.accentLightBlue : context.colors.primaryGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: accent.withOpacity(0.4)),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800)),
            ),
            // ⚠️ Three kinds of round, three markings, and they must not be
            // confusable: the FIRST carries no badge (it is the valuation
            // itself), the middle rounds are re-valuations, and the last is
            // priced by the committee — which is a different act by different
            // people, not another re-valuation.
            if (revalued) ...[
              const Gap(8),
              Icon(Icons.price_change_rounded,
                  size: 14, color: context.colors.accentLightBlue),
              const Gap(4),
              Text('re-valued',
                  style: TextStyle(
                      color: context.colors.accentLightBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ] else if (isCommitteeRound) ...[
              const Gap(8),
              Icon(Icons.groups_2_rounded,
                  size: 14, color: context.colors.primaryGold),
              const Gap(4),
              Text('committee value',
                  style: TextStyle(
                      color: context.colors.primaryGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
            if (soldLabel != null) ...[
              const Gap(8),
              Icon(Icons.check_circle_rounded,
                  size: 14, color: context.colors.successGreen),
              const Gap(4),
              Text(soldLabel!,
                  style: TextStyle(
                      color: context.colors.successGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
            const Spacer(),
            // A sealed round says WHY the figure is missing, in place of it.
            if (sealed)
              const Flexible(child: SealedValuation(compact: true))
            else if (priceLabel != null)
              Flexible(
                child: Text(priceLabel!,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          const Gap(8),
          // Say WHY the price is missing, the same way the committee block
          // does. A bare "Sealed" chip reads as a glitch; this says the figure
          // is deliberately withheld and when it will appear.
          if (sealed || upcoming) ...[
            Text(
                sealed
                    ? 'This round has not been tendered yet. Its valuation '
                        'is the reserve price, so it is shown once the '
                        'tender closes.'
                    // ⚠️ Same fact, different reason. The valuer is not
                    // being kept from the figure -- it set it -- so the
                    // line says what is still to happen instead of what is
                    // being withheld.
                    : 'Set for the next round. Central Disposal re-tenders '
                        'at this price.',
                style:
                    TextStyle(fontSize: 11, color: context.colors.textMuted)),
            const Gap(8),
          ],
          if (isCommitteeRound) ...[
            Text(
                committeeLoading
                    ? 'Priced by the tender committee · loading members…'
                    : (committeeSubtitle ??
                        (committeeMembers.isEmpty
                            ? 'Priced by the tender committee · no bidding'
                            : 'Priced by the tender committee '
                                '(${committeeMembers.length} '
                                '${committeeMembers.length == 1 ? 'member' : 'members'})'
                                ' · no bidding')),
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 11.5)),
            if (committeeMembers.isNotEmpty) ...[
              const Gap(8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < committeeMembers.length; i++)
                    _CommitteeMemberChip(
                        no: i + 1, member: committeeMembers[i]),
                ],
              ),
            ],
          ] else if (bids.isEmpty)
            // ⚠️ "No bids recorded" reads as an omission -- somebody
            // forgot to enter them. For a perishable it is the RULE:
            // the goods run one special sale and take no bids at all,
            // so the line says which of the two this is.
            Text(
                isPerishableRound
                    ? 'Perishable goods take no bids'
                    : 'No bids recorded',
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 11.5))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Text('Bids:',
                    style: TextStyle(
                        color: context.colors.textMuted, fontSize: 11.5)),
                for (final b in bids)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.colors.successGreen.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: context.colors.successGreen.withOpacity(0.35)),
                    ),
                    child: Text(b,
                        style: TextStyle(
                            color: context.colors.successGreen,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class PackageDetailsDialog extends ConsumerStatefulWidget {
  final PackageModel package;
  final Map<DateTime, double> storageRate;
  final WarehouseEntryModel? highlightEntry; // Added highlightEntry
  // Fallback item to highlight when there is no warehouse entry ([highlightEntry]
  // is null) — e.g. an abandoned/"Other" item registered on the SR form that was
  // never admitted to a warehouse. Ensures such items still get the item-detail
  // view and the Final Disposition footer button.
  final String? highlightItemId;
  final bool useLegacySummary;

  /// The forfeited row whose tender history (per-round valuation + bids)
  /// should be shown. Set by the Unsold pages; null hides the section.
  final ForfeitedPackageModel? tenderHistoryFor;
  final bool showFinalOutcome;
  final bool useWarehouseSummary;

  // Optional yard label (e.g. 'Grey Line 1') shown in the Warehouse Summary so
  // the cross-yard directorate views (Central Disposal / Valuation) can see
  // which yard holds the package. Null hides the row.
  final String? yardLabel;

  // Optional valuation cost set by the Valuation Directorate, shown in the Item
  // Details alongside the package's own declared value. [valuationUnitCost] is
  // per item; [valuationTotalCost] = unit × qty. Null hides the rows.
  final double? valuationUnitCost;
  final double? valuationTotalCost;
  final int? valuationQty;

  /// True while the goods are still in a tender/destruction sale that has not
  /// yet run. The valuation is the reserve price, so the whole Valuation
  /// section AND the per-round tender history are replaced by a "sealed"
  /// notice — see [valuationSealed].
  final bool valuationSealedUntilSale;

  /// The VALUATION DIRECTORATE is reading its own figures.
  ///
  /// ⚠️ Passed by that portal alone. A reserve price is sealed until
  /// bidding closes so nobody can bid against it -- and the directorate
  /// that SET it is not "nobody". Sealing there hid a number from the
  /// only people whose job is to decide it, on the very page where they
  /// decide the next round's.
  final bool valuerView;

  // Optional generic footer action (e.g. the Appeal Directorate's "Hold Appeal"
  // / "Release"). When [footerActionLabel] is set, a button is shown in the
  // dialog footer — styled like the Final Disposition footer — that calls
  // [onFooterAction] (the dialog closes first).
  final String? footerActionLabel;
  final IconData? footerActionIcon;
  final Color? footerActionColor;
  final String? footerActionHint;
  final VoidCallback? onFooterAction;
  final Color? headerAccentColor;
  final bool appealHold;
  final String? appealHoldNote;
  final DateTime? appealHeldAt;

  // Appeal Directorate decision banner. When [appealDecisionLabel] is set, a
  // prominent banner is shown at the top of the body telling the owning yard
  // what to do with the package (e.g. "Release to owner", "Destroy").
  final String? appealDecisionLabel;
  // The raw decision CODE ('RELEASE' | 'SALE' | 'DESTROY' | 'RE-EXPORT' |
  // 'OTHER'). When set, the Final Disposition dialog enables ONLY the matching
  // action — the yard must proceed exactly as the Appeal Directorate decided.
  final String? appealDecisionCode;
  final String? appealDecisionNote;
  final DateTime? appealDecidedAt;

  // Final-disposition gating (Forfeited screen). The footer "Final Disposition"
  // button is shown ONLY when [allowFinalDisposition] is true — i.e. the appeal
  // window has passed. While an appeal is still open it is hidden entirely.
  final bool allowFinalDisposition;

  // Sale / Destroy are NOT offered in this dialog — `_isActionEnabled` always
  // disables them. Those two outcomes belong to the Central Disposal
  // Directorate and are started from the "Send Disposal Request" button on the
  // status page, so that one deliberate request covers every selected item.
  //
  // The hook is kept for callers that want to route a Sale / Destroy pick
  // somewhere of their own, but with the current gating it is never invoked.
  final void Function(String disposition)? onSaleOrDestroyRequest;

  // When true, the Final Disposition footer is shown unconditionally (skips the
  // [_hasFinalDisposition] heuristic). Callers that already guarantee the item
  // is actionable — e.g. the Abandoned / Other tables, which exclude finalised
  // items when building their rows — pass this so EVERY listed package gets the
  // button in its details popup.
  final bool forceFinalDisposition;

  // When true, the dialog is opened from the Sold Packages page, so the
  // Sale & Financial Information section is always shown. When false
  // (default), the section only shows if the highlighted entry is sold.
  final bool isSoldPage;

  // When true, show the admin-only "Update" (edit) footer even when this
  // isn't the warehouse-summary layout — e.g. opened from the Packages page.
  // The Update action itself remains admin-only regardless of this flag.
  final bool allowEdit;

  // When true, the Final Disposition dialog is for a Detained item and must
  // apply different gating: Release / Re-export / Other are always available;
  // Sale and Destroy require the 30-day window to pass or an appeal decision.
  final bool isDetained;
  // True while the goods are still within the 30-day appeal window and no
  // Appeal Directorate decision has been issued. Passed to _FinalDispositionDialog
  // so it can disable Destroy (and Sale is already disabled via _requestActions).
  final bool inAppealWindow;

  const PackageDetailsDialog({
    super.key,
    required this.package,
    required this.storageRate,
    this.highlightEntry, // Added highlightEntry
    this.highlightItemId,
    this.useLegacySummary = false,
    this.tenderHistoryFor,
    this.showFinalOutcome = true,
    this.useWarehouseSummary = false,
    this.yardLabel,
    this.valuationUnitCost,
    this.valuationTotalCost,
    this.valuationQty,
    this.valuationSealedUntilSale = false,
    this.valuerView = false,
    this.footerActionLabel,
    this.footerActionIcon,
    this.footerActionColor,
    this.footerActionHint,
    this.onFooterAction,
    this.headerAccentColor,
    this.appealHold = false,
    this.appealHoldNote,
    this.appealHeldAt,
    this.appealDecisionLabel,
    this.appealDecisionCode,
    this.appealDecisionNote,
    this.appealDecidedAt,
    this.allowFinalDisposition = true,
    this.onSaleOrDestroyRequest,
    this.forceFinalDisposition = false,
    this.isSoldPage = false,
    this.allowEdit = false,
    this.isDetained = false,
    this.inAppealWindow = false,
    this.srFinancials,
    this.handover,
  });

  final SrFinancials? srFinancials;

  /// An ending the yard is still waiting to hand over — see [HandoverKind].
  ///
  /// ⚠️ Re-export and Release only. Both were recorded once and reported
  /// finished from that moment; neither popup said whether the goods had
  /// actually gone. Sold and Destroyed already state their ending twice and
  /// pass null here.
  final HandoverOutcome? handover;

  @override
  ConsumerState<PackageDetailsDialog> createState() =>
      _PackageDetailsDialogState();
}

/// Shown where the entering officer is genuinely absent from the record.
///
/// Packages carried over when the register was migrated have no `inspected_by`
/// and no creation audit row, so no name exists to show. This is a statement
/// about the RECORD, not a failed lookup -- see [_SystemEntrySection].
const String _kNoEntrantRecorded = 'Not recorded';

class _PackageDetailsDialogState extends ConsumerState<PackageDetailsDialog>
    with SingleTickerProviderStateMixin {
  String? _creatorFallback;
  bool _isLoadingCreator = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _animCtrl.forward();
    if (widget.package.inspectedBy == null) {
      _lookupCreator();
    }
  }

  Future<void> _lookupCreator() async {
    setState(() => _isLoadingCreator = true);
    try {
      final creator =
          await AuditLogService().getPackageCreator(widget.package.id);
      if (mounted) setState(() => _creatorFallback = creator);
    } catch (_) {}
    if (mounted) setState(() => _isLoadingCreator = false);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<bool> _showReleaseConfirmation(
      BuildContext context, WarehouseEntryModel entry,
      {int? preselectedQty, List<int>? packageNumbers}) async {
    final notesCtrl = TextEditingController();
    final receiptCtrl = TextEditingController();
    final dateCtrl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    // Release date drives the warehouse-charge calculation (entry date → this
    // date). Defaults to today; editable (a back-date is allowed).
    DateTime releaseDate = DateTime.now();
    final releaseDateCtrl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(releaseDate));

    // Find the specific item this entry refers to
    final specificItem = widget.package.items.firstWhere(
      (i) => i.id == entry.packageItemId,
      orElse: () => widget.package.items.first,
    );

    // Auto-repair display logic for old entries that saved 1 as itemCount
    int displayCount = entry.itemCount;
    if (displayCount == 1 && specificItem.quantity > 1 && !entry.isReturned) {
      final returnedSum = widget.package.warehouseEntries
          .where((e) => e.packageItemId == specificItem.id && e.isReturned)
          .fold(0, (sum, e) => sum + e.itemCount);
      displayCount = specificItem.quantity - returnedSum;
      if (displayCount < 1) displayCount = 1; // Fallback
    }

    final qtyCtrl = TextEditingController(
        text: (preselectedQty ?? displayCount).toString());
    final formKey = GlobalKey<FormState>();

    // Charge counts from the SR-form Entry Date (falling back to the warehouse
    // admit date if the package has none), NOT the warehouse admit timestamp —
    // that's what the officer sets on the SR form and expects to be billed from.
    final chargeStart = widget.package.entryDate ?? entry.admittedAt;

    double getCharge(int count) {
      // Temp entry with the release date as the exit date, so the charge covers
      // SR entry date → release date (inclusive) at the historical daily rates.
      final tempEntry = WarehouseEntryModel(
        id: entry.id,
        packageId: entry.packageId,
        packageItemId: entry.packageItemId,
        warehouseId: entry.warehouseId,
        warehouseName: entry.warehouseName,
        warehouseCode: entry.warehouseCode,
        holdReason: entry.holdReason,
        itemCount: count,
        admittedAt: chargeStart,
        dailyRate: entry.dailyRate,
        returnedAt: releaseDate,
      );
      return tempEntry
          .calculatePackageCharge([specificItem], widget.storageRate);
    }

    final result = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => material.AlertDialog(
          title: const Text('Release Package Item'),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SR: ${widget.package.srNumber}',
                      style: const material.TextStyle(
                          fontWeight: FontWeight.bold)),
                  Text('Goods: ${specificItem.itemName}',
                      style: material.TextStyle(
                          color: context.colors.primaryGold)),
                  Text('Warehouse: ${entry.warehouseName}',
                      style: const material.TextStyle(fontSize: 12)),
                  const Gap(16),
                  material.Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total in Warehouse:'),
                            Text('$displayCount',
                                style: const material.TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Gap(12),
                        // Quantity is fixed to the packages selected in the
                        // previous step — read-only so it can't diverge.
                        TextFormField(
                          controller: qtyCtrl,
                          readOnly: true,
                          enabled: false,
                          decoration: const material.InputDecoration(
                            labelText: 'Quantity to Release',
                            isDense: true,
                          ),
                        ),
                        const Gap(12),
                        // Release date — drives the charge below.
                        TextFormField(
                          controller: releaseDateCtrl,
                          readOnly: true,
                          decoration: material.InputDecoration(
                            labelText: 'Release Date *',
                            isDense: true,
                            suffixIcon: Icon(Icons.calendar_month,
                                size: 18, color: context.colors.primaryGold),
                          ),
                          onTap: () async {
                            final picked = await showAppDialog<DateTime>(
                              context: ctx,
                              builder: (_) => OneTapDatePicker(
                                initialDate: releaseDate,
                                // Release can't be before the SR entry date.
                                firstDate: chargeStart,
                                lastDate: DateTime.now(),
                              ),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                releaseDate = picked;
                                releaseDateCtrl.text =
                                    DateFormat('yyyy-MM-dd').format(picked);
                              });
                            }
                          },
                        ),
                        const Gap(8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Warehouse Charge:'),
                            Text(
                                'LKR ${NumberFormat('#,##0.00').format(getCharge(int.tryParse(qtyCtrl.text) ?? 0))}',
                                style: material.TextStyle(
                                    color: context.colors.primaryGold,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Gap(4),
                        material.Builder(builder: (_) {
                          final startDay = DateTime(chargeStart.year,
                              chargeStart.month, chargeStart.day);
                          final endDay = DateTime(releaseDate.year,
                              releaseDate.month, releaseDate.day);
                          final days = endDay.difference(startDay).inDays + 1;
                          final beforeEntry = endDay.isBefore(startDay);
                          return material.Align(
                            alignment: material.Alignment.centerLeft,
                            child: Text(
                              beforeEntry
                                  ? 'Release date is before the entry date (${DateFormat('yyyy-MM-dd').format(chargeStart)}) — no charge.'
                                  : 'Entry ${DateFormat('yyyy-MM-dd').format(chargeStart)} → Release · $days day(s)',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: beforeEntry
                                      ? context.colors.dangerRed
                                      : context.colors.textMuted),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const Gap(16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: receiptCtrl,
                          decoration: const material.InputDecoration(
                            labelText: 'Receipt No. *',
                            hintText: 'Enter receipt #',
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: dateCtrl,
                          readOnly: true,
                          decoration: const material.InputDecoration(
                            labelText: 'Receipt Date *',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          onTap: () async {
                            // Same custom picker as the SR form (consistent look).
                            final existing =
                                DateTime.tryParse(dateCtrl.text.trim());
                            final date = await showAppDialog<DateTime>(
                              context: context,
                              builder: (_) => OneTapDatePicker(
                                initialDate: existing ?? DateTime.now(),
                                lastDate: DateTime.now(),
                              ),
                            );
                            if (date != null) {
                              dateCtrl.text =
                                  DateFormat('yyyy-MM-dd').format(date);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const Gap(16),
                  material.TextField(
                    controller: notesCtrl,
                    maxLines: 3,
                    minLines: 2,
                    keyboardType: TextInputType.multiline,
                    decoration: const material.InputDecoration(
                      labelText: 'Release Notes (Optional)',
                      hintText: 'Enter any additional details',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            material.TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.successGreen,
                  foregroundColor: Colors.white),
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final releaseQty = int.tryParse(qtyCtrl.text) ?? 0;
                if (releaseQty <= 0 || releaseQty > entry.itemCount) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Invalid quantity to release'),
                      backgroundColor: Colors.red));
                  return;
                }

                try {
                  String finalNotes =
                      "Receipt No: ${receiptCtrl.text.trim()} | Date: ${dateCtrl.text}";
                  if (notesCtrl.text.trim().isNotEmpty) {
                    finalNotes += " | Notes: ${notesCtrl.text.trim()}";
                  }

                  await ref.read(warehouseServiceProvider).markAsReturned(
                        entry.id,
                        returnNotes: finalNotes,
                        returnQty: releaseQty,
                        packageNumbers: packageNumbers,
                        returnDate: releaseDate,
                      );
                  ref.read(packagesRefreshTriggerProvider.notifier).trigger();
                  ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
                  ref.invalidate(
                      liveWarehouseEntriesProvider(entry.warehouseId));
                  ref.invalidate(livePackagesProvider);
                  ref.invalidate(allWarehouseEntriesProvider);
                  ref.invalidate(packageDataProvider(entry.packageId));
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ctx.mounted) {
                    showErrorSnack(ctx, e);
                  }
                }
              },
              child: const Text('Confirm Release'),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<bool> _showDispositionDialog(
      BuildContext context, WarehouseEntryModel entry, String dispositionType,
      {int? preselectedQty, List<int>? packageNumbers}) async {
    final notesCtrl = TextEditingController();
    // Every disposition captures the date the action took place — defaults to
    // today, back-dating allowed, future dates blocked. For Forfeit this date
    // also anchors the 30-day appeal deadline; for others it's the record date
    // (Re-export date, Abandon date, Destroy date, …).
    final isForfeit = _isForfeitStatusLocal(dispositionType);
    DateTime dispositionDate = DateTime.now();
    final dispositionDateCtrl = TextEditingController(
        text:
            '${dispositionDate.year}-${dispositionDate.month.toString().padLeft(2, '0')}-${dispositionDate.day.toString().padLeft(2, '0')}');
    // The date field's label follows the action, e.g. "Re-export Date".
    final dateLabel = isForfeit ? 'Forfeit Date' : '$dispositionType Date';

    final Map<String, _DispositionMeta> meta = {
      'Forfeit': _DispositionMeta(
        icon: Icons.gavel_rounded,
        color: const Color(0xFFE53935),
        label: 'Forfeit',
        description:
            'Package is forfeited to the state. No further charges apply.',
      ),
      'Abandoned': _DispositionMeta(
        icon: Icons.inbox_rounded,
        color: const Color(0xFF9E9E9E),
        label: 'Abandoned',
        description: 'Package is declared abandoned. No further charges apply.',
      ),
      'Re-export': _DispositionMeta(
        icon: Icons.flight_takeoff_rounded,
        color: const Color(0xFF00ACC1),
        label: 'Re-export',
        description: 'Package is sent back to the country of origin.',
      ),
      'Destroy': _DispositionMeta(
        icon: Icons.delete_forever_rounded,
        color: const Color(0xFFE64A19),
        label: 'Destroy',
        description: 'Package is destroyed. No further charges apply.',
      ),
    };
    final m = meta[dispositionType] ??
        _DispositionMeta(
          icon: Icons.help_outline_rounded,
          color: const Color(0xFF7E57C2),
          label: dispositionType,
          description: 'Custom disposition: $dispositionType',
        );

    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => material.AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(m.icon, color: m.color, size: 22),
          const Gap(10),
          Text('${m.label} Package Item'),
        ]),
        content: StatefulBuilder(
            builder: (ctx, setLocalState) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: m.color.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: m.color.withOpacity(0.3)),
                        ),
                        child: Text(m.description,
                            style: TextStyle(color: m.color, fontSize: 13)),
                      ),
                      // Forfeit date picker (Forfeit only). Defaults to today; a back-date is
                      // allowed. The 30-day appeal deadline is counted from this date.
                      // Date picker for EVERY disposition — defaults to today, future dates
                      // blocked (lastDate = now), same one-tap calendar as the SR form.
                      const Gap(16),
                      TextFormField(
                        controller: dispositionDateCtrl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: dateLabel,
                          isDense: true,
                          suffixIcon:
                              Icon(Icons.calendar_month, color: m.color),
                        ),
                        onTap: () async {
                          final picked = await showAppDialog<DateTime>(
                            context: ctx,
                            builder: (_) => OneTapDatePicker(
                              initialDate: dispositionDate,
                              lastDate: DateTime.now(),
                            ),
                          );
                          if (picked != null) {
                            setLocalState(() {
                              dispositionDate = picked;
                              dispositionDateCtrl.text =
                                  '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                            });
                          }
                        },
                      ),
                      if (preselectedQty != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: m.color.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Packages selected:',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: m.color.withOpacity(0.7))),
                                Text('$preselectedQty',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: m.color)),
                              ],
                            ),
                          ),
                        ),
                      const Gap(16),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes / Remarks (optional)',
                          isDense: true,
                        ),
                        maxLines: 3,
                        minLines: 2,
                        keyboardType: TextInputType.multiline,
                      ),
                    ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: Icon(m.icon, size: 16),
            label: Text('Confirm ${m.label}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: m.color,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    await ref.read(warehouseServiceProvider).disposeWarehouseItem(
          entry.id,
          dispositionStatus: dispositionType,
          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
          qty: preselectedQty,
          packageNumbers: packageNumbers,
          // Every disposition now carries its chosen date (stored as returned_at;
          // for Forfeit it also anchors the appeal deadline).
          forfeitDate: dispositionDate,
        );
    // Refresh so the (still open) actions dialog recomputes processed slots.
    ref.read(packagesRefreshTriggerProvider.notifier).trigger();
    ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
    ref.invalidate(packageDataProvider(entry.packageId));
    ref.invalidate(liveWarehouseEntriesProvider(entry.warehouseId));
    ref.invalidate(livePackagesProvider);
    // When forfeited: refresh the Forfeited Packages page too so the new row appears.
    if (_isForfeitStatusLocal(dispositionType)) {
      ref.invalidate(forfeitedPackagesProvider);
      ref.invalidate(requestableForfeitedPackagesProvider);
    }
    return true;
  }

  void _showActionsDialog(
    BuildContext ctx,
    WarehouseEntryModel entry, {
    PackageItem? highlightedItem,
  }) {
    final specificItem = highlightedItem ??
        widget.package.items.firstWhere(
          (i) => i.id == entry.packageItemId,
          orElse: () => widget.package.items.first,
        );

    showAppDialog(
      context: ctx,
      builder: (dialogCtx) => _PackageActionsDialog(
        packageId: entry.packageId,
        itemId: specificItem.id,
        fallbackEntry: entry,
        entryDate: widget.package.entryDate ?? widget.package.createdAt,
        onRelease: (held, slots) async {
          return await _showReleaseConfirmation(ctx, held,
              preselectedQty: slots.length, packageNumbers: slots);
        },
        onDispose: (held, type, slots) async {
          return await _showDispositionDialog(ctx, held, type,
              preselectedQty: slots.length, packageNumbers: slots);
        },
        // On a successful action: instead of closing the details dialog (which
        // dumped the user back to the warehouse page, resetting it to the first
        // tab), re-open the SAME package's details with fresh data so the
        // action's result is reflected and the user stays in context.
        onCompleted: () => _reopenWithFreshData(ctx, entry),
      ),
    );
  }

  /// Refresh providers after an in-dialog action so the warehouse list
  /// (behind the dialog) stays in sync. The dialog itself stays open and alive —
  /// no pop/re-open so the entry animation does not replay.
  void _reopenWithFreshData(BuildContext ctx, WarehouseEntryModel oldEntry) {
    ref.read(packagesRefreshTriggerProvider.notifier).trigger();
    ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
    ref.invalidate(packageDataProvider(oldEntry.packageId));
    ref.invalidate(liveWarehouseEntriesProvider(oldEntry.warehouseId));
    ref.invalidate(livePackagesProvider);
    ref.invalidate(allWarehouseEntriesProvider);
  }

  /// Opens the final-disposition picker for an abandoned/forfeit item.
  /// Release / Re-export / Other are admin-only (hidden for officers).
  void _showFinalDispositionDialog(
    BuildContext ctx, {
    required PackageItem item,
    required WarehouseEntryModel? entry,
    required bool isOfficer,
  }) {
    final qty = entry?.itemCount ?? item.effectiveQuantity;
    showAppDialog(
      context: ctx,
      builder: (dialogCtx) => _FinalDispositionDialog(
        item: item,
        qty: qty,
        isOfficer: isOfficer,
        // Restrict the enabled action to the Appeal Directorate's decision.
        decisionCode: widget.appealDecisionCode,
        isDetained: widget.isDetained,
        inAppealWindow: widget.inAppealWindow,
        // When a Sale/Destroy request handler is supplied (Forfeited screen),
        // those two route to the Central Disposal request flow instead of
        // writing a [FINAL:…] entry directly.
        onRequestDisposal: widget.onSaleOrDestroyRequest == null
            ? null
            : (String disposition) {
                Navigator.pop(dialogCtx); // close the picker
                Navigator.pop(ctx); // close the details dialog
                widget.onSaleOrDestroyRequest!(disposition);
              },
        onConfirm: (String type, String? notes, DateTime date) async {
          Navigator.pop(dialogCtx);

          // Capture everything that reads from a BuildContext BEFORE popping —
          // this State's own context is torn down with the dialog, so looking
          // any of it up afterwards would fail.
          final messenger = material.ScaffoldMessenger.maybeOf(ctx);
          final successColour = context.colors.successGreen;
          // No failure colour captured: showErrorSnack picks it by kind.

          // Close the details dialog BEFORE the write, not after it.
          //
          // Popping last meant the popup stayed on screen through the round
          // trip AND the invalidations that follow it, so the goods had
          // already vanished from the table behind it while the dialog sat
          // there. The write does not need this dialog, and the page it
          // returns to refreshes itself.
          Navigator.pop(ctx);

          try {
            await ref.read(warehouseServiceProvider).recordFinalDisposition(
                  packageItemId: item.id,
                  dispositionType: type,
                  qty: qty,
                  notes: notes,
                  dispositionDate: date,
                );
            // Refresh every affected view so the item leaves the Forfeited /
            // Other-manageable list and appears on its outcome page — the item's
            // status just changed but no realtime fires on package_items alone.
            ref.read(packagesRefreshTriggerProvider.notifier).trigger();
            ref.invalidate(livePackagesProvider);
            ref.invalidate(packageDataProvider(widget.package.id));
            ref.invalidate(forfeitedPackagesProvider);
            ref.invalidate(requestableForfeitedPackagesProvider);
            ref.invalidate(allItemAppealOutcomesProvider);
            messenger?.showSnackBar(
              material.SnackBar(
                content: Text('Final disposition recorded: $type'),
                backgroundColor: successColour,
              ),
            );
          } catch (e) {
            // Worded by kind, like everywhere else -- a timeout here is not a
            // failure the officer caused, and should not read like one.
            if (ctx.mounted) showErrorSnack(ctx, e);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.package;
    final hasAppealDecision =
        widget.appealDecisionLabel?.trim().isNotEmpty ?? false;
    final showAppealStatus = widget.appealHold || hasAppealDecision;
    final appealIsHold = widget.appealHold;
    final appealAccent = appealIsHold
        ? context.colors.warningAmber
        : context.colors.accentLightBlue;
    final appealDate =
        appealIsHold ? widget.appealHeldAt : widget.appealDecidedAt;
    final appealNote =
        (appealIsHold ? widget.appealHoldNote : widget.appealDecisionNote)
            ?.trim();
    // ⚠️ NOT "Unknown Officer". Most of these entries were bulk-loaded when
    // the register was migrated, so no officer was ever recorded against them
    // -- there is nobody to name, and nothing has gone wrong. "Unknown"
    // read as a lookup that had FAILED and sent people hunting for a bug.
    // `_recordedEntrant` below marks the difference so the section can say
    // which of the two it is.
    String officerDisplay = _kNoEntrantRecorded;
    String? salaryNumber;

    if (p.inspectedByName != null) {
      // Extract salary number if it's in the name format "(Salary No: XXXXX)"
      final match =
          RegExp(r'\(Salary No:\s*(\d+)\)').firstMatch(p.inspectedByName!);
      if (match != null) {
        salaryNumber = match.group(1);
      }
      // Clean up officer name - remove salary number if included
      officerDisplay =
          p.inspectedByName!.replaceAll(RegExp(r'\s*\(Salary No:.*?\)'), '');
    } else if (p.inspectedBy != null) {
      officerDisplay = 'ID: ${p.inspectedBy}';
    } else if (_isLoadingCreator) {
      officerDisplay = 'Loading...';
    } else if (_creatorFallback != null) {
      officerDisplay = _creatorFallback!;
    }

    // Use badge number if available, otherwise use extracted salary number
    final displayBadgeNumber =
        (p.inspectedByBadge != null && p.inspectedByBadge!.isNotEmpty)
            ? p.inspectedByBadge
            : salaryNumber;

    // Get current user's role to conditionally disable update button
    final currentProfile = ref.watch(currentProfileProvider);
    final isOfficer = currentProfile?.role == 'officer';
    // Editing a package is strictly admin-only.
    final canUpdatePackage = currentProfile?.isAdmin ?? false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOld = p.oldSrNumber != null && p.oldSrNumber!.trim().isNotEmpty;

    // Resolve which package item this popup is about. [highlightItemId] is the
    // caller's explicit choice (e.g. the Abandoned/Other table row's own item)
    // and takes priority — it's authoritative even when a [highlightEntry] is
    // also supplied, because an entry may be package-level (packageItemId null)
    // or reference a sibling item, which would otherwise resolve to the WRONG
    // item via the orElse fallback and break the Final Disposition gating.
    final highlightedItem = (widget.highlightItemId != null &&
            p.items.any((i) => i.id == widget.highlightItemId))
        ? p.items.firstWhere((i) => i.id == widget.highlightItemId)
        : (widget.highlightEntry != null
            ? p.items.firstWhere(
                (i) => i.id == widget.highlightEntry!.packageItemId,
                orElse: () => p.items.first)
            : null);

    // The forfeited row the Appeal section reads, for whichever item this
    // popup is about.
    //
    // ⚠️ THIS item's row, and no other. An SR can hold several items, each
    // with its OWN forfeited row and its own appeal — CED/GL1/SR/24/2025 has
    // four, and only Paint Thinner Cans was ruled on. Falling back to
    // "whichever row came first" showed that ruling on the popup for Laptop
    // Chargers, which had never been appealed at all: the table said Enabled
    // and the popup said Decided · Other about the same goods.
    //
    // ⚠️ `forfeitedByItemProvider` keys STRICTLY by item and drops any
    // package-level row (`if (itemId == null) continue`), so there is no
    // package-wide entry to fall back to here. An item with no row of its
    // own simply has no appeal to show, and showing nothing is right: the
    // table says Enabled for exactly those goods.
    final appealFor = widget.tenderHistoryFor ??
        (highlightedItem == null
            ? null
            : ref
                .watch(forfeitedByItemProvider(p.id))
                .valueOrNull?[highlightedItem.id]);

    // Perishables never enter a warehouse -- no storage, no appeal window,
    // straight to disposal. So an EMPTY warehouse summary is the correct
    // answer for them, and the section has to say so rather than showing the
    // same "No warehouse details" blank that a failed load would produce.
    final isPerishable = highlightedItem != null
        ? highlightedItem.nature == kNaturePerishable
        : p.items.isNotEmpty &&
            p.items.every((i) => i.nature == kNaturePerishable);

    // Show ONLY the item this popup is about whenever it's known (via
    // highlightItemId OR a highlightEntry) — a decided/forfeited item may have
    // no warehouse entry, so relying on highlightEntry alone would fall back to
    // listing every sibling item. If no specific item is known, show all.
    final legacyItems = highlightedItem != null ? [highlightedItem] : p.items;
    final legacyEntries =
        (widget.useLegacySummary && widget.highlightEntry != null)
            ? [widget.highlightEntry!]
            // When an item is known (via entry OR highlightItemId), show only
            // that item's warehouse entries (the Central Disposal / Valuation
            // request popup goes through here). Package-level entries with no
            // packageItemId are kept too so legacy data still surfaces. If that
            // leaves nothing, fall back to all entries. Otherwise show all.
            : (highlightedItem != null)
                ? (() {
                    final matched = p.warehouseEntries
                        .where((e) =>
                            e.packageItemId == highlightedItem.id ||
                            e.packageItemId == null)
                        .toList();
                    return matched.isEmpty ? p.warehouseEntries : matched;
                  })()
                : p.warehouseEntries;

    int? displayQty;
    if (highlightedItem != null && widget.highlightEntry != null) {
      displayQty = widget.highlightEntry!.itemCount;
      if (displayQty == 1 &&
          highlightedItem.quantity > 1 &&
          !widget.highlightEntry!.isReturned) {
        final returnedSum = widget.package.warehouseEntries
            .where((e) => e.packageItemId == highlightedItem.id && e.isReturned)
            .fold(0, (sum, e) => sum + e.itemCount);
        displayQty = highlightedItem.quantity - returnedSum;
        if (displayQty! < 1) displayQty = 1;
      }
    }

    String? returnedReceiptNo;
    String? returnedReceiptDate;
    String? releaseNotesText;
    final returnNotes = widget.highlightEntry?.returnNotes;
    if (returnNotes != null && returnNotes.trim().isNotEmpty) {
      for (final part in returnNotes.split('|')) {
        final text = part.trim();
        if (text.toLowerCase().startsWith('receipt no:')) {
          final idx = text.indexOf(':');
          if (idx != -1) returnedReceiptNo = text.substring(idx + 1).trim();
        } else if (text.toLowerCase().startsWith('date:')) {
          final idx = text.indexOf(':');
          if (idx != -1) returnedReceiptDate = text.substring(idx + 1).trim();
        } else if (text.toLowerCase().startsWith('notes:')) {
          final idx = text.indexOf(':');
          if (idx != -1) releaseNotesText = text.substring(idx + 1).trim();
        }
      }
    }
    // The actual disposition date is stored on the entry as returnedAt.
    final String? releaseDateText = widget.highlightEntry?.returnedAt != null
        ? DateFormat('yyyy-MM-dd').format(widget.highlightEntry!.returnedAt!)
        : null;
    // Label that date by the disposition it records — the return_notes carry a
    // "[FINAL:RE-EXPORTED]" / "[FINAL:DESTROYED]" / "[RELEASED]" … tag, so the
    // popup reads "Re-export Date" / "Destroyed Date" instead of always
    // "Release Date".
    final String dispoDateLabel = (() {
      final n = widget.highlightEntry?.returnNotes?.toUpperCase() ?? '';
      if (n.contains('RE-EXPORT')) return 'Re-export Date';
      if (n.contains('DESTROY')) return 'Destroyed Date';
      if (n.contains('SOLD') || n.contains('SALE')) return 'Sold Date';
      if (n.contains('FORFEIT')) return 'Forfeit Date';
      if (n.contains('ABANDON')) return 'Abandoned Date';
      if (n.contains('OTHER')) return 'Disposition Date';
      return 'Release Date';
    })();
    // Warehouse charge counts from the SR-form Entry Date (not the warehouse
    // admit timestamp) → the release date, so the popup matches the release
    // dialog's figure. Falls back to admittedAt if the package has no entry date.
    double? releasedCharge;
    if (widget.highlightEntry != null && highlightedItem != null) {
      final e = widget.highlightEntry!;
      final chargeStart = p.entryDate ?? e.admittedAt;
      final tempEntry = WarehouseEntryModel(
        id: e.id,
        packageId: e.packageId,
        packageItemId: e.packageItemId,
        warehouseId: e.warehouseId,
        warehouseName: e.warehouseName,
        warehouseCode: e.warehouseCode,
        holdReason: e.holdReason,
        itemCount: e.itemCount,
        admittedAt: chargeStart,
        dailyRate: e.dailyRate,
        returnedAt: e.returnedAt,
      );
      releasedCharge = tempEntry
          .calculatePackageCharge([highlightedItem], widget.storageRate);
    }

    final highlightReturnedById = widget.highlightEntry?.returnedBy;
    final returnedOfficerDisplay = widget.highlightEntry?.returnedByName ??
        (highlightReturnedById != null &&
                highlightReturnedById == currentProfile?.id
            ? currentProfile?.fullName
            : null) ??
        _kNoEntrantRecorded;
    final returnedOfficerBadge = widget.highlightEntry?.returnedByBadge ??
        (highlightReturnedById != null &&
                highlightReturnedById == currentProfile?.id
            ? currentProfile?.badgeNumber
            : null);

    final _hs = highlightedItem?.status?.toLowerCase() ?? '';
    final isConfiscated = _hs == 'confiscated' ||
        _hs == 'forfeit' ||
        _hs == 'forfiet' ||
        _hs == 'abandoned' ||
        widget.highlightEntry?.isPackageConfiscated == true;

    // No-charge context: abandoned / forfeit / destroy. These items carry no
    // storage fee and no release receipt — so we show registration-form item
    // details instead of charge/receipt fields. A [FINAL:DESTROYED] disposition
    // entry is also no-charge even if the item status didn't update.
    final _entryNotesUpper =
        (widget.highlightEntry?.returnNotes ?? '').trim().toUpperCase();
    final isDestroyedEntry = _entryNotesUpper.startsWith('[FINAL:DESTROYED') ||
        _entryNotesUpper.startsWith('[DESTROY');
    final isReExportEntry = _entryNotesUpper.startsWith('[FINAL:RE-EXPORTED') ||
        _entryNotesUpper.startsWith('[RE-EXPORT');
    final isOtherEntry = _entryNotesUpper.startsWith('[FINAL:OTHER') ||
        _entryNotesUpper.startsWith('[OTHER');

    // No-charge context: abandoned / forfeit / destroy / re-export / other. These items carry no
    // storage fee and no release receipt — so we show registration-form item
    // details instead of charge/receipt fields.
    final isNoChargeContext = WarehouseEntryModel.isNoChargeStatus(_hs) ||
        _isAbandonOrForfeitEntry(widget.highlightEntry) ||
        isDestroyedEntry ||
        isReExportEntry ||
        isOtherEntry;

    // SOLD-via-tender context: declutter — no release receipt / warehouse
    // charges / packages-released fields (the Sale & Financial section covers it).
    final isSoldContext = _hs == 'sold' ||
        p.status?.toLowerCase() == 'sold' ||
        (widget.highlightEntry?.returnNotes?.toUpperCase().contains('SOLD') ??
            false);

    // ── "(This Action)" count label ──
    // For released items the second count reads "Released (This Receipt)".
    // For every other disposition (Forfeit / Abandoned / Re-export / Destroy /
    // Other-custom) we show the SAME pattern — Total Packages + the count of
    // packages handled by THIS specific action — using a label matching the
    // disposition type. The disposition key is read from the entry's returnNotes
    // tag (e.g. "[FORFEIT]"), falling back to the item status.
    String? _actionCountLabel;
    if (widget.highlightEntry != null && !isSoldContext) {
      final notes = (widget.highlightEntry!.returnNotes ?? '').trim();
      final m = RegExp(r'^\[([^\]]+)\](.*)').firstMatch(notes);
      if (m != null) {
        final raw = m.group(1)!.trim();
        final rawUpper = raw.toUpperCase();
        if (rawUpper.startsWith('OTHER:')) {
          // New "[OTHER: <text>]" tag — the custom text is inside the bracket.
          final customText = raw.substring(6).trim();
          _actionCountLabel =
              '${customText.isEmpty ? 'Other' : customText} (This Action)';
        } else if (raw == 'OTHER' || raw == 'FINAL:OTHER') {
          final dashIndex = notes.indexOf('—');
          if (dashIndex != -1) {
            final customText = notes.substring(dashIndex + 1).trim();
            _actionCountLabel = '$customText (This Action)';
          } else {
            _actionCountLabel = 'Other (This Action)';
          }
        } else {
          _actionCountLabel =
              '${_dispoLabel(raw.toUpperCase(), raw)} (This Action)';
        }
      } else if (isNoChargeContext) {
        // No disposition tag but a no-charge status (form-level forfeit/abandoned/
        // destroy) — label by the item status.
        String key = _hs.toUpperCase();
        if (key == 'FORFEIT' || key == 'FORFIET' || key == 'CONFISCATED') {
          key = 'FORFEIT';
        }
        _actionCountLabel = '${_dispoLabel(key, _hs)} (This Action)';
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final v = _anim.value;
          return Transform.scale(
            scale: v,
            child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
          );
        },
        child: material.Container(
          width: 900,
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              material.Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: widget.headerAccentColor != null
                      ? LinearGradient(colors: [
                          widget.headerAccentColor!.withOpacity(0.15),
                          context.colors.cardDark,
                        ])
                      : LinearGradient(
                          colors: isDark
                              ? [
                                  context.colors.surfaceDark,
                                  context.colors.cardDark
                                ]
                              : [
                                  context.colors.customsBlue,
                                  context.colors.customsBlueDark
                                ],
                        ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(23)),
                ),
                child: Row(
                  children: [
                    material.Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.inventory_2_rounded,
                          color: widget.headerAccentColor ??
                              context.colors.primaryGold,
                          size: 24),
                    )
                        .animate()
                        .scale(duration: 400.ms, curve: Curves.easeOutBack),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                isOld
                                    ? 'OLD ENTRY (MIGRATED)'
                                    : 'SR REGISTER ENTRY',
                                style: material.TextStyle(
                                  color: widget.headerAccentColor ??
                                      (isOld
                                          ? context.colors.primaryGold
                                          : context.colors.primaryGold),
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Gap(8),
                              material.Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOld
                                      ? context.colors.primaryGold
                                          .withOpacity(0.18)
                                      : context.colors.accentLightBlue
                                          .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isOld
                                        ? context.colors.primaryGold
                                            .withOpacity(0.5)
                                        : context.colors.accentLightBlue
                                            .withOpacity(0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isOld
                                      ? 'Old SR: ${p.oldSrNumber}'
                                      : 'NEW ENTRY',
                                  style: material.TextStyle(
                                    color: isOld
                                        ? context.colors.primaryGold
                                        : context.colors.accentLightBlue,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                          const Gap(2),
                          Text(
                            p.srNumber,
                            style: const material.TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                              .animate()
                              .fadeIn(duration: 400.ms, delay: 150.ms)
                              .slideX(begin: -0.1),
                        ],
                      ),
                    ),
                    const Gap(12),
                    DialogCloseButton(
                        prominent: widget.headerAccentColor != null),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // ── Appeal decision banner ──
                      // Shown to the owning yard once the Appeal Directorate has
                      // released a hold with a decision.
                      if (widget.appealDecisionLabel != null &&
                          widget.appealDecisionLabel!.trim().isNotEmpty)
                        material.Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.colors.accentLightBlue
                                .withOpacity(0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: context.colors.accentLightBlue
                                    .withOpacity(0.4)),
                          ),
                          child: Row(children: [
                            Icon(Icons.gavel_rounded,
                                color: context.colors.accentLightBlue,
                                size: 22),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('APPEAL DIRECTORATE DECISION',
                                      style: material.TextStyle(
                                          color: context.colors.accentLightBlue,
                                          fontSize: 10,
                                          letterSpacing: 1.0,
                                          fontWeight: FontWeight.w800)),
                                  const Gap(2),
                                  Text(
                                    'Proceed with: ${widget.appealDecisionLabel}',
                                    style: material.TextStyle(
                                        color: context.colors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                      // SR Register Information Section
                      _DetailSection(
                        title: 'SR Register Information',
                        icon: Icons.assignment_rounded,
                        delay: 100,
                        child: Column(
                          children: [
                            if (isOld) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.numbers_rounded,
                                      label: 'New SR Number',
                                      value: p.srNumber,
                                      valueColor:
                                          context.colors.accentLightBlue,
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.history_edu_rounded,
                                      label: 'Old SR Number (Migrated)',
                                      value: p.oldSrNumber!,
                                      valueColor: context.colors.primaryGold,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.history_rounded,
                                      label: 'Entry Type',
                                      value: 'Old Entry (Migrated)',
                                      valueColor: context.colors.primaryGold,
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.calendar_today_rounded,
                                      label: 'Entry Date',
                                      value: p.entryDate != null
                                          ? DateFormat('yyyy-MM-dd')
                                              .format(p.entryDate!)
                                          : 'N/A',
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.receipt_long_rounded,
                                      label: 'Cusdec No',
                                      value: p.cusdecNo ?? 'N/A',
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.calendar_month_rounded,
                                      label: 'Cusdec Date',
                                      value: p.cusdecDate ?? 'N/A',
                                    ),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.numbers_rounded,
                                      label: 'SR Number',
                                      value: p.srNumber,
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.fiber_new_rounded,
                                      label: 'Entry Type',
                                      value: 'New Entry (Standard)',
                                      valueColor:
                                          context.colors.accentLightBlue,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.calendar_today_rounded,
                                      label: 'Entry Date',
                                      value: p.entryDate != null
                                          ? DateFormat('yyyy-MM-dd')
                                              .format(p.entryDate!)
                                          : 'N/A',
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.receipt_long_rounded,
                                      label: 'Cusdec No',
                                      value: p.cusdecNo ?? 'N/A',
                                    ),
                                  ),
                                ],
                              ),
                              _DetailItem(
                                icon: Icons.calendar_month_rounded,
                                label: 'Cusdec Date',
                                value: p.cusdecDate ?? 'N/A',
                              ),
                            ],
                            _DetailItem(
                              icon: Icons.gavel_rounded,
                              label: 'Case Number',
                              value: p.caseNumber ?? 'N/A',
                            ),
                            _DetailItem(
                              icon: Icons.local_shipping_rounded,
                              label: 'Container Number',
                              value: p.containerNumber ?? 'N/A',
                            ),
                            // Package-level: one deposit per SR, taken at
                            // registration against the cost of destruction.
                            _DetailItem(
                              icon: Icons.savings_rounded,
                              label: 'Destroying Deposit',
                              value: p.destroyingDeposit == null
                                  ? 'N/A'
                                  : 'LKR ${NumberFormat('#,##0.##').format(p.destroyingDeposit)}',
                            ),
                            _DetailItem(
                              icon: Icons.description_rounded,
                              label: 'Package Description',
                              value: p.description ?? 'No description provided',
                            ),
                          ],
                        ),
                      ),

                      // Consignee Information Section
                      _DetailSection(
                        title: 'Consignee Information',
                        icon: Icons.person_pin_rounded,
                        delay: 200,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.person_rounded,
                                    label: 'Consignee Name',
                                    value: p.consigneeName,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.badge_rounded,
                                    label: 'Declarant Name',
                                    value: p.declarantName ?? 'N/A',
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.home_rounded,
                                    label: 'Declarant Address',
                                    value: p.consigneeAddress ?? 'N/A',
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.phone_rounded,
                                    label: 'Declarant Phone Number',
                                    value: p.consigneePhone ?? 'N/A',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      if (widget.useLegacySummary ||
                          widget.useWarehouseSummary) ...[
                        _DetailSection(
                          title: 'Goods Details',
                          icon: Icons.shopping_bag_rounded,
                          delay: 300,
                          child: (widget.highlightEntry == null &&
                                  highlightedItem != null)
                              // No warehouse entry (form-level abandoned/"Other"
                              // item) — show a compact item card from the SR
                              // registration data.
                              ? _NoEntryItemCard(item: highlightedItem)
                              : (widget.highlightEntry == null ||
                                      highlightedItem == null)
                                  // No specific item/entry highlighted (e.g. the
                                  // Central Disposal request view) — fall back to
                                  // listing every package item so the popup still
                                  // shows full details, like the Forfeited screen.
                                  ? (legacyItems.isEmpty
                                      ? const _EmptyState(
                                          message: 'No released item details')
                                      : Column(
                                          children: [
                                            for (var i = 0;
                                                i < legacyItems.length;
                                                i++) ...[
                                              if (i > 0) const Gap(12),
                                              _NoEntryItemCard(
                                                  item: legacyItems[i]),
                                            ],
                                          ],
                                        ))
                                  : material.Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.colors.surfaceDark,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: context.colors.borderColor),
                                      ),
                                      child: isNoChargeContext
                                          ? Column(
                                              children: [
                                                _DetailItem(
                                                  icon: Icons
                                                      .label_important_rounded,
                                                  label: 'Goods Name',
                                                  value:
                                                      highlightedItem.itemName,
                                                ),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .view_in_ar_rounded,
                                                        label: 'Total Packages',
                                                        value:
                                                            '${highlightedItem.effectiveQuantity}',
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .inventory_2_rounded,
                                                        label:
                                                            _actionCountLabel ??
                                                                'Quantity',
                                                        value:
                                                            '${widget.highlightEntry!.itemCount}',
                                                        valueColor: context
                                                            .colors.primaryGold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .straighten_rounded,
                                                        label: 'Unit',
                                                        value: highlightedItem
                                                                    .unitOfMeasure ==
                                                                'Other'
                                                            ? (highlightedItem
                                                                    .unitOther ??
                                                                'Other')
                                                            : (highlightedItem
                                                                        .packagingLabel !=
                                                                    null
                                                                ? '${highlightedItem.effectiveQuantity} ${highlightedItem.effectiveUnit} (in ${highlightedItem.packagingLabel})'
                                                                : highlightedItem
                                                                    .effectiveUnit),
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .category_rounded,
                                                        label: 'Category',
                                                        value: (highlightedItem
                                                                    .category
                                                                    ?.isNotEmpty ==
                                                                true)
                                                            ? highlightedItem
                                                                .category!
                                                            : '—',
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons.tag_rounded,
                                                        label: 'HS Code',
                                                        value: (highlightedItem
                                                                    .hsCode
                                                                    ?.isNotEmpty ==
                                                                true)
                                                            ? highlightedItem
                                                                .hsCode!
                                                            : '—',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                _DetailItem(
                                                  icon: Icons.payments_rounded,
                                                  // The TOTAL, with the unit price beneath it — the same shape
                                                  // the Valuation column uses. This showed the bare unitValue
                                                  // under a label reading just "Value", while every table showed
                                                  // unitValue x quantity under that same word.
                                                  label: 'Value (total)',
                                                  value:
                                                      'LKR ${NumberFormat('#,##0.00').format(highlightedItem.unitValue * highlightedItem.quantity)}'
                                                      '  ·  @ ${NumberFormat('#,##0.00').format(highlightedItem.unitValue)} × ${highlightedItem.quantity}',
                                                ),
                                                if (highlightedItem
                                                        .goodsDescription
                                                        ?.isNotEmpty ==
                                                    true)
                                                  _DetailItem(
                                                    icon: Icons
                                                        .description_rounded,
                                                    label: 'Goods Description',
                                                    value: highlightedItem
                                                        .goodsDescription!,
                                                  ),
                                                if (highlightedItem
                                                        .reasons?.isNotEmpty ==
                                                    true)
                                                  _DetailItem(
                                                    icon: Icons
                                                        .warning_amber_rounded,
                                                    label:
                                                        'Post Status Activity',
                                                    value: highlightedItem
                                                        .reasons!,
                                                  ),
                                              ],
                                            )
                                          : Column(
                                              children: [
                                                _DetailItem(
                                                  icon: Icons
                                                      .label_important_rounded,
                                                  label: 'Goods Name',
                                                  value:
                                                      highlightedItem.itemName,
                                                ),
                                                // Total Packages + Unit — always
                                                // shown (incl. Sold context) so the
                                                // popup lists the full item detail.
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .view_in_ar_rounded,
                                                        label: 'Total Packages',
                                                        value:
                                                            '${highlightedItem.effectiveQuantity}',
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .straighten_rounded,
                                                        label: 'Unit',
                                                        value: highlightedItem
                                                                    .unitOfMeasure ==
                                                                'Other'
                                                            ? (highlightedItem
                                                                    .unitOther ??
                                                                'Other')
                                                            : (highlightedItem
                                                                        .packagingLabel !=
                                                                    null
                                                                ? '${highlightedItem.effectiveQuantity} ${highlightedItem.effectiveUnit} (in ${highlightedItem.packagingLabel})'
                                                                : highlightedItem
                                                                    .effectiveUnit),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                // Valuation / disposal context: how
                                                // many of the total were actually
                                                // sent for disposal (e.g. 6 of 10).
                                                if (widget.valuationQty !=
                                                        null &&
                                                    widget.valuationQty !=
                                                        highlightedItem
                                                            .effectiveQuantity)
                                                  _DetailItem(
                                                    icon:
                                                        Icons.outbound_rounded,
                                                    label: 'Sent for Disposal',
                                                    value:
                                                        '${widget.valuationQty} of ${highlightedItem.effectiveQuantity}',
                                                    valueColor: context
                                                        .colors.primaryGold,
                                                  ),
                                                // Warehouse-entry count (Remaining /
                                                // Released) only when an entry exists
                                                // (never in the Sold context).
                                                if (!isSoldContext &&
                                                    widget.highlightEntry !=
                                                        null)
                                                  _DetailItem(
                                                    icon: widget
                                                            .useWarehouseSummary
                                                        ? Icons
                                                            .inventory_2_rounded
                                                        : Icons
                                                            .keyboard_return_rounded,
                                                    label: widget
                                                            .useWarehouseSummary
                                                        ? 'Remaining (Current)'
                                                        : (_actionCountLabel ??
                                                            'Released (This Receipt)'),
                                                    value:
                                                        '${widget.highlightEntry!.itemCount}',
                                                    valueColor: widget
                                                            .useWarehouseSummary
                                                        ? context
                                                            .colors.primaryGold
                                                        : context.colors
                                                            .successGreen,
                                                  ),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons.tag_rounded,
                                                        label: 'HS Code',
                                                        value: (highlightedItem
                                                                    .hsCode
                                                                    ?.isNotEmpty ==
                                                                true)
                                                            ? highlightedItem
                                                                .hsCode!
                                                            : '—',
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: _DetailItem(
                                                        icon: Icons
                                                            .payments_rounded,
                                                        // Total, with the unit
                                                        // price beneath —
                                                        // matching the tables.
                                                        label: 'Value (total)',
                                                        value:
                                                            'LKR ${NumberFormat('#,##0.00').format(highlightedItem.unitValue * highlightedItem.quantity)}'
                                                            '  ·  @ ${NumberFormat('#,##0.00').format(highlightedItem.unitValue)} × ${highlightedItem.quantity}',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (highlightedItem
                                                        .goodsDescription
                                                        ?.isNotEmpty ==
                                                    true)
                                                  _DetailItem(
                                                    icon: Icons
                                                        .description_rounded,
                                                    label: 'Goods Description',
                                                    value: highlightedItem
                                                        .goodsDescription!,
                                                  ),
                                                if (highlightedItem
                                                        .reasons?.isNotEmpty ==
                                                    true)
                                                  _DetailItem(
                                                    icon: Icons
                                                        .warning_amber_rounded,
                                                    label:
                                                        'Post Status Activity',
                                                    value: highlightedItem
                                                        .reasons!,
                                                  ),
                                              ],
                                            ),
                                    ),
                        ),
                        // Valuation Directorate cost (Central Disposal /
                        // Valuation request popups) — shown next to the package's
                        // own declared value.
                        // Sealed while the sale is still open: show that the
                        // figure is deliberately withheld, not simply missing.
                        // ⚠️ Not for the valuer. They set this figure; a
                        // lock panel where their own number should be is a
                        // page telling them they may not see their own work.
                        if (widget.valuationSealedUntilSale &&
                            !widget.valuerView)
                          _DetailSection(
                            title: 'Valuation',
                            icon: Icons.lock_outline_rounded,
                            delay: 320,
                            child: material.Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.surfaceDark,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: context.colors.borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SealedValuation(),
                                  const Gap(6),
                                  Text(SealedValuation.tooltip,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: context.colors.textMuted)),
                                ],
                              ),
                            ),
                          )
                        // ⚠️ Only when there is NO tender history below.
                        //
                        // Tender History opens with the Valuation Tender —
                        // the first round and the figure it ran at — so this
                        // card was the same fact stated twice. Worse, the two
                        // did not agree: this shows the ORIGINAL valuation,
                        // while the first round shows the re-valuation keyed
                        // to it, and a reader had no way to tell which was
                        // which. One place, and it is the one that also shows
                        // every round after it.
                        //
                        // A package that never went to tender has no history
                        // section at all, and still needs its valuation, so
                        // this stays for exactly that case.
                        else if (widget.valuationUnitCost != null &&
                            !(widget.tenderHistoryFor != null &&
                                !widget.valuationSealedUntilSale))
                          _DetailSection(
                            title: 'Valuation',
                            icon: Icons.calculate_rounded,
                            delay: 320,
                            child: material.Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.surfaceDark,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: context.colors.borderColor),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.sell_rounded,
                                      label: 'Valuation Cost / item',
                                      value:
                                          'LKR ${NumberFormat('#,##0').format(widget.valuationUnitCost)}',
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: _DetailItem(
                                      icon: Icons.functions_rounded,
                                      label: widget.valuationQty != null
                                          ? 'Total (× ${widget.valuationQty})'
                                          : 'Total Valuation',
                                      value:
                                          'LKR ${NumberFormat('#,##0').format(widget.valuationTotalCost ?? widget.valuationUnitCost)}',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // ⚠️ The appeal's OWN story, for the Appeal
                        // Directorate's popup. Its two tables say a package
                        // is "On Appeal Hold" or "Decided · Sell", and the
                        // popup then said nothing at all about the appeal —
                        // not when it was lodged, not when the deadline
                        // falls, not what was ruled or when.
                        //
                        // ⚠️ Resolved HERE when the caller did not pass one,
                        // rather than at each call site. Eight screens open
                        // this popup (Abandoned, Detained, Other, Goods
                        // History, Old Entries, Released, Forfeited,
                        // Warehouses) and none of them passed
                        // `tenderHistoryFor`, so an officer asking "was this
                        // appealed?" got no answer on any of them — while the
                        // table they had just clicked from showed an Appeal
                        // column. The popup has the package and a ref, so it
                        // can answer for itself.
                        if (appealFor != null)
                          _AppealHistorySection(
                            forfeited: appealFor,
                            itemId: highlightedItem?.id,
                          ),
                        // Per-round valuation + bids, for unsold packages.
                        // Also sealed: each round carries its own valuation.
                        if (widget.tenderHistoryFor != null &&
                            !widget.valuationSealedUntilSale)
                          TenderHistorySection(
                            forfeited: widget.tenderHistoryFor!,
                            qty: widget.valuationQty,
                            showFinalOutcome: widget.showFinalOutcome,
                            valuerView: widget.valuerView,
                          ),
                        // ⚠️ Directly ABOVE Warehouse Summary, and in the
                        // same frame. The two are read as a pair -- where
                        // the goods are, and where they went.
                        if (widget.handover != null)
                          _HandoverSection(outcome: widget.handover!),
                        if (!widget.useWarehouseSummary)
                          _DetailSection(
                            title: 'Warehouse Summary',
                            icon: Icons.warehouse_rounded,
                            delay: 350,
                            child: legacyEntries.isEmpty
                                // Even with no warehouse entry, surface the yard
                                // so the cross-yard directorate views still show
                                // where the package belongs.
                                ? (widget.yardLabel != null
                                    ? material.Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: context.colors.surfaceDark,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color:
                                                  context.colors.borderColor),
                                        ),
                                        child: _DetailItem(
                                          icon: Icons.maps_home_work_rounded,
                                          label: 'Yard',
                                          value: widget.yardLabel!,
                                        ),
                                      )
                                    : _EmptyState(
                                        icon: isPerishable
                                            ? Icons.ac_unit_rounded
                                            : Icons.inbox_rounded,
                                        message: isPerishable
                                            ? 'Not stored in a warehouse'
                                            : 'No warehouse details',
                                        reason: isPerishable
                                            ? 'Perishable goods go straight '
                                                'to disposal — they are stored '
                                                'in the yard without warehouse '
                                                'admission.'
                                            : null,
                                      ))
                                : material.Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: context.colors.surfaceDark,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: context.colors.borderColor),
                                    ),
                                    child: Column(
                                      children: [
                                        if (widget.yardLabel != null)
                                          _DetailItem(
                                            icon: Icons.maps_home_work_rounded,
                                            label: 'Yard',
                                            value: widget.yardLabel!,
                                          ),
                                        _DetailItem(
                                          icon: Icons.warehouse_rounded,
                                          label: 'Warehouse',
                                          value: legacyEntries
                                              .map(
                                                  (e) => e.warehouseName.trim())
                                              .where((w) => w.isNotEmpty)
                                              .toSet()
                                              .join(', '),
                                        ),
                                        _DetailItem(
                                          icon: Icons.location_on_rounded,
                                          label: 'Zone',
                                          value: () {
                                            final zones = legacyEntries
                                                .map((e) {
                                                  final zn = e.zone?.trim();
                                                  if (zn != null &&
                                                      zn.isNotEmpty) {
                                                    return zn
                                                            .toLowerCase()
                                                            .startsWith('zone')
                                                        ? zn
                                                        : 'Zone $zn';
                                                  }
                                                  return e.warehouseCode
                                                          .trim()
                                                          .isNotEmpty
                                                      ? e.warehouseCode.trim()
                                                      : null;
                                                })
                                                .where((z) => z != null)
                                                .cast<String>()
                                                .toSet();
                                            return zones.isEmpty
                                                ? '—'
                                                : zones.join(', ');
                                          }(),
                                        ),
                                        _DetailItem(
                                          icon: Icons.calendar_month_rounded,
                                          label: 'Entry Date',
                                          value: (p.entryDate ??
                                                      legacyEntries
                                                          .first.admittedAt) !=
                                                  null
                                              ? DateFormat('yyyy-MM-dd').format(
                                                  p.entryDate ??
                                                      legacyEntries
                                                          .first.admittedAt)
                                              : '—',
                                        ),
                                        if (releaseDateText != null)
                                          _DetailItem(
                                            icon: Icons.event_available_rounded,
                                            label: dispoDateLabel,
                                            value: releaseDateText,
                                          ),
                                        if (!isNoChargeContext &&
                                            !isSoldContext) ...[
                                          if (releasedCharge != null)
                                            _DetailItem(
                                              icon: Icons.payments_rounded,
                                              label: 'Warehouse Charge',
                                              value:
                                                  'LKR ${NumberFormat('#,##0.00').format(releasedCharge)}',
                                              valueColor:
                                                  context.colors.successGreen,
                                            ),
                                          _DetailItem(
                                            icon: Icons.receipt_long_rounded,
                                            label: 'Receipt No',
                                            value: returnedReceiptNo ?? '—',
                                          ),
                                          _DetailItem(
                                            icon: Icons.event_rounded,
                                            label: 'Receipt Date',
                                            value: returnedReceiptDate ?? '—',
                                          ),
                                        ],
                                        if (releaseNotesText != null &&
                                            releaseNotesText.isNotEmpty)
                                          _DetailItem(
                                            icon: Icons.notes_rounded,
                                            label: 'Release Notes',
                                            value: releaseNotesText,
                                          ),
                                      ],
                                    ),
                                  ),
                          ),
                      ] else
                        _DetailSection(
                          title: 'Package Item Summary',
                          icon: Icons.inventory_2_rounded,
                          delay: 300,
                          child: p.items.isEmpty
                              ? const _EmptyState(message: 'No package items')
                              : Column(
                                  children: p.items.map((item) {
                                    final relatedEntries = p.warehouseEntries
                                        .where(
                                            (e) => e.packageItemId == item.id)
                                        .toList();
                                    final heldQty = relatedEntries
                                        .where((e) => !e.isReturned)
                                        .fold<int>(
                                            0, (sum, e) => sum + e.itemCount);

                                    // ⚠️ An item that has LEFT has no current
                                    // warehouse, whatever its entries say.
                                    //
                                    // The test was `!e.isReturned` alone, so a
                                    // straggling entry — one the sale never
                                    // closed out — kept printing "Current
                                    // Warehouse: Open Area 01" for goods that
                                    // had already been sold and delivered. The
                                    // item's own STATUS is the authority here:
                                    // sold, destroyed, re-exported or released
                                    // all mean the goods are gone, and a
                                    // warehouse row that disagrees is a
                                    // bookkeeping leftover, not a location.
                                    // ── Categorize returned entries by disposition ──
                                    // Releases carry no [STATUS] prefix in returnNotes;
                                    // dispositions are tagged e.g. [FORFEIT], [RE-EXPORT].
                                    final _returnedEntries = relatedEntries
                                        .where((e) => e.isReturned)
                                        .toList();
                                    int _releasedQty = 0;
                                    String? _releasedOfficer;
                                    double _releasedChargesPaid = 0;
                                    final Map<String, int> _dispoCounts = {};
                                    final Map<String, String?> _dispoOfficers =
                                        {};
                                    final Map<String, String> _dispoRawLabel =
                                        {};
                                    for (final e in _returnedEntries) {
                                      final notes =
                                          (e.returnNotes ?? '').trim();
                                      final m = RegExp(r'^\[([^\]]+)\]')
                                          .firstMatch(notes);
                                      final officer =
                                          e.returnedByName ?? e.returnedByBadge;
                                      if (m == null) {
                                        _releasedQty += e.itemCount;
                                        _releasedOfficer ??= officer;
                                        _releasedChargesPaid += e
                                            .calculatePackageCharge(
                                                [item], widget.storageRate);
                                      } else {
                                        final raw = m.group(1)!.trim();
                                        final key = raw.toUpperCase();
                                        _dispoCounts[key] =
                                            (_dispoCounts[key] ?? 0) +
                                                e.itemCount;
                                        _dispoOfficers[key] ??= officer;
                                        _dispoRawLabel[key] = raw;
                                      }
                                    }

                                    final _itemStatus =
                                        item.status?.toLowerCase() ?? '';
                                    final isItemForfeited =
                                        _itemStatus == 'confiscated' ||
                                            _itemStatus == 'forfeit' ||
                                            _itemStatus == 'forfeited' ||
                                            _itemStatus == 'forfiet';
                                    final isItemAbandoned =
                                        _itemStatus == 'abandoned';
                                    final isItemDetained =
                                        _itemStatus == 'detained' ||
                                            _itemStatus == 'detain';
                                    final isItemReexport =
                                        _itemStatus == 're-export';
                                    final isItemDestroy =
                                        _itemStatus == 'destroy';
                                    final isItemDisposed =
                                        isItemReexport || isItemDestroy;
                                    final isItemConfiscated = isItemForfeited;
                                    // ⚠️ The FINAL OUTCOMES, as distinct from
                                    // the decisions above them: 'destroy' is
                                    // the ruling, 'destroyed' is what
                                    // happened. Both deserve the badge, and
                                    // the outcome more than the decision --
                                    // it is the end of the story.
                                    //
                                    // These sat in `_neutralStatuses`, so an
                                    // item that had actually been SOLD or
                                    // DESTROYED got no badge and no tint at
                                    // all, while a released one did (through
                                    // a separate quantity test). One outcome
                                    // was visible and the rest were not.
                                    final isItemSold = _itemStatus == 'sold';
                                    final isItemDestroyedDone =
                                        _itemStatus == 'destroyed';
                                    final isItemReexportedDone =
                                        _itemStatus == 're-exported';
                                    final isItemReleasedDone =
                                        _itemStatus == 'released' ||
                                            _itemStatus == 'returned';
                                    final isItemFinalOutcome = isItemSold ||
                                        isItemDestroyedDone ||
                                        isItemReexportedDone ||
                                        isItemReleasedDone;
                                    final isItemTerminal = isItemForfeited ||
                                        isItemAbandoned ||
                                        isItemDetained ||
                                        isItemDisposed ||
                                        isItemFinalOutcome;
                                    // A custom ("Other") status — anything that
                                    // is not a known disposition and not a
                                    // neutral working/left-yard state — should
                                    // still get a status badge in this card.
                                    const _neutralStatuses = {
                                      '',
                                      'pending',
                                      'held',
                                      'inspecting',
                                      'returned',
                                      'released',
                                      'sold',
                                      're-exported',
                                      'destroyed',
                                    };
                                    final isItemOther = !isItemTerminal &&
                                        !_neutralStatuses.contains(_itemStatus);
                                    // A fully-released item (all qty released, none
                                    // held, no other disposition) shows a RELEASED
                                    // badge instead of falling back to a neutral
                                    // 'returned' status with no badge.
                                    // A fully-released item whose STATUS was
                                    // never updated: the quantities say it
                                    // left even though the column still reads
                                    // 'returned' or blank.
                                    final isItemReleased = isItemReleasedDone ||
                                        (_releasedQty > 0 &&
                                            heldQty == 0 &&
                                            _dispoCounts.isEmpty);
                                    final showStatusBadge = isItemTerminal ||
                                        isItemOther ||
                                        isItemReleased;

                                    // Status-specific color
                                    Color _statusColor() {
                                      if (isItemForfeited)
                                        return const Color(0xFFE53935);
                                      if (isItemAbandoned)
                                        return const Color(0xFF9E9E9E);
                                      if (isItemDetained)
                                        return const Color(0xFFFF8F00);
                                      if (isItemReexport)
                                        return const Color(0xFF00ACC1);
                                      if (isItemDestroy)
                                        return const Color(0xFFE64A19);
                                      if (isItemSold)
                                        return context.colors.successGreen;
                                      if (isItemDestroyedDone)
                                        return const Color(0xFFE64A19);
                                      if (isItemReexportedDone)
                                        return const Color(0xFF00ACC1);
                                      if (isItemReleased)
                                        return context.colors.successGreen;
                                      if (isItemOther)
                                        return context.colors.accentLightBlue;
                                      return context.colors.borderColor;
                                    }

                                    final itemStatusColor = _statusColor();

                                    // Status label for badge
                                    String _statusLabel() {
                                      if (isItemForfeited) return 'FORFEITED';
                                      if (isItemAbandoned) return 'ABANDONED';
                                      if (isItemDetained) return 'DETAINED';
                                      if (isItemReexport) return 'RE-EXPORT';
                                      if (isItemDestroy) return 'DESTROYED';
                                      if (isItemSold) return 'SOLD';
                                      if (isItemDestroyedDone) {
                                        return 'DESTROYED';
                                      }
                                      if (isItemReexportedDone) {
                                        return 'RE-EXPORTED';
                                      }
                                      if (isItemReleased) return 'RELEASED';
                                      if (isItemOther) {
                                        return (item.status ?? '')
                                            .toUpperCase();
                                      }
                                      return '';
                                    }

                                    return material.Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isItemTerminal
                                            ? itemStatusColor.withOpacity(0.05)
                                            : context.colors.surfaceDark,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: isItemTerminal
                                                ? itemStatusColor
                                                    .withOpacity(0.35)
                                                : context.colors.borderColor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              top: 2),
                                                      child: Icon(
                                                          Icons
                                                              .label_important_rounded,
                                                          size: 16,
                                                          color: isItemTerminal
                                                              ? itemStatusColor
                                                              : context.colors
                                                                  .primaryGold),
                                                    ),
                                                    const Gap(12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            item.itemName,
                                                            style: material
                                                                .TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 14,
                                                              color: isItemTerminal
                                                                  ? context
                                                                      .colors
                                                                      .textMuted
                                                                  : null,
                                                            ),
                                                          ),
                                                          if (item.category !=
                                                              null)
                                                            Text(item.category!,
                                                                style: material.TextStyle(
                                                                    color: context
                                                                        .colors
                                                                        .textMuted,
                                                                    fontSize:
                                                                        11)),
                                                          if (item.goodsDescription !=
                                                                  null &&
                                                              item.goodsDescription!
                                                                  .trim()
                                                                  .isNotEmpty)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      top: 3),
                                                              child: Text(
                                                                item.goodsDescription!,
                                                                style: material
                                                                    .TextStyle(
                                                                  color: context
                                                                      .colors
                                                                      .textSecondary,
                                                                  fontSize: 12,
                                                                ),
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (showStatusBadge) ...[
                                                        material.Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      10,
                                                                  vertical: 4),
                                                          decoration:
                                                              BoxDecoration(
                                                            color:
                                                                itemStatusColor
                                                                    .withOpacity(
                                                                        0.15),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        20),
                                                            border: Border.all(
                                                                color: itemStatusColor
                                                                    .withOpacity(
                                                                        0.4)),
                                                          ),
                                                          child: Text(
                                                            _statusLabel(),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: material
                                                                .TextStyle(
                                                              color:
                                                                  itemStatusColor,
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w900,
                                                              letterSpacing:
                                                                  0.5,
                                                            ),
                                                          ),
                                                        ),
                                                        const Gap(8),
                                                      ],
                                                      Text(
                                                        'x${item.effectiveQuantity}',
                                                        style:
                                                            material.TextStyle(
                                                          color: isItemTerminal
                                                              ? context.colors
                                                                  .textMuted
                                                              : context.colors
                                                                  .primaryGold,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const Gap(12),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _DetailItem(
                                                  icon:
                                                      Icons.straighten_rounded,
                                                  label: 'Unit',
                                                  value: item.packagingLabel !=
                                                          null
                                                      ? '${item.effectiveQuantity} ${item.effectiveUnit} (in ${item.packagingLabel})'
                                                      : item.effectiveUnit,
                                                ),
                                              ),
                                              // Detain → show storage charges paid for
                                              // released portion. Forfeit/Abandoned →
                                              // hide value box (no charge). Else → Unit Value.
                                              if (isItemDetained) ...[
                                                const Gap(12),
                                                Expanded(
                                                  child: _DetailItem(
                                                    icon: Icons
                                                        .price_check_rounded,
                                                    label: 'Charges Paid',
                                                    value:
                                                        'LKR ${NumberFormat('#,##0.00').format(_releasedChargesPaid)}',
                                                    valueColor: context
                                                        .colors.successGreen,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.tag_rounded,
                                                  label: 'HS Code',
                                                  value: (item.hsCode
                                                              ?.isNotEmpty ==
                                                          true)
                                                      ? item.hsCode!
                                                      : '—',
                                                ),
                                              ),
                                              const Gap(12),
                                              Expanded(
                                                child: _DetailItem(
                                                  icon: Icons.payments_rounded,
                                                  // The TOTAL, with the unit price beneath it — the same shape
                                                  // the Valuation column uses. This showed the bare unitValue
                                                  // under a label reading just "Value", while every table showed
                                                  // unitValue x quantity under that same word.
                                                  label: 'Value (total)',
                                                  value:
                                                      'LKR ${NumberFormat('#,##0.00').format(item.unitValue * item.quantity)}'
                                                      '  ·  @ ${NumberFormat('#,##0.00').format(item.unitValue)} × ${item.quantity}',
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (item.reasons != null &&
                                              item.reasons!.isNotEmpty)
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    material.Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              8),
                                                      decoration: BoxDecoration(
                                                        color: context
                                                            .colors.dangerRed
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
                                                      ),
                                                      child: Icon(
                                                        Icons
                                                            .warning_amber_rounded,
                                                        size: 16,
                                                        color: context
                                                            .colors.dangerRed,
                                                      ),
                                                    ),
                                                    const Gap(12),
                                                    // ⚠️ Named for what the
                                                    // FORM calls it. The
                                                    // officer picks a "Post
                                                    // Status Activity"
                                                    // (stored in
                                                    // `hold_reason`) and
                                                    // every list filters on
                                                    // that name — calling it
                                                    // "Reason" only here
                                                    // made the popup look
                                                    // like it was showing
                                                    // some other field.
                                                    Text(
                                                      'Post Status Activity',
                                                      style: material.TextStyle(
                                                        color: context
                                                            .colors.textMuted,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const Gap(8),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 12),
                                                  child: Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children: item.reasons!
                                                        .split(',')
                                                        .map((reason) =>
                                                            material.Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          8),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: context
                                                                    .colors
                                                                    .dangerRed
                                                                    .withOpacity(
                                                                        0.05),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            10),
                                                                border:
                                                                    Border.all(
                                                                  color: context
                                                                      .colors
                                                                      .dangerRed
                                                                      .withOpacity(
                                                                          0.2),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                reason.trim(),
                                                                style: material
                                                                    .TextStyle(
                                                                  color: context
                                                                      .colors
                                                                      .dangerRed,
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ))
                                                        .toList(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          // ⚠️ "Current Warehouse" and the
                                          // "Disposition Breakdown" block
                                          // used to sit here and have been
                                          // REMOVED, not lost: both are now
                                          // answered once, per admission, by
                                          // _ItemStorageSection below.
                                          //
                                          // They said the same thing three
                                          // times over. A released item read
                                          // "Left the warehouse — released to
                                          // the owner", then "Currently Held
                                          // x0 / Released x40", then
                                          // "Delivered out … Quantity 40" —
                                          // and the breakdown's counts could
                                          // drift from the entries they were
                                          // summarising. The storage section
                                          // lists each admission with its own
                                          // warehouse, zone, quantity and
                                          // state, which covers the split
                                          // cases the breakdown existed for
                                          // without restating them.
                                          // ⚠️ Every avenue this ITEM went
                                          // down, under the item itself.
                                          //
                                          // The popup could already show a
                                          // tender history, but only when a
                                          // caller passed ONE forfeited
                                          // package in -- so from Goods
                                          // History, where an SR holds several
                                          // items that each met a different
                                          // end, it showed nothing at all. The
                                          // valuation, the bids, the
                                          // committee, the appeal and the
                                          // final outcome all belong to the
                                          // item, so they are rendered per
                                          // item.
                                          // Where these goods have been and
                                          // what that has cost. Before the
                                          // lifecycle, because storage is
                                          // what happens FIRST and is still
                                          // happening while everything below
                                          // is being decided.
                                          if (widget.tenderHistoryFor == null)
                                            _ItemStorageSection(
                                              package: p,
                                              item: item,
                                              highlightEntry:
                                                  widget.highlightEntry,
                                            ),
                                          if (widget.tenderHistoryFor == null)
                                            _ItemLifecycleSection(
                                              packageId: p.id,
                                              item: item,
                                            ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      const Gap(16),

                      // Officer Notice Section
                      if (p.notes != null && p.notes!.isNotEmpty) ...[
                        _DetailSection(
                          title: 'Officer Notice',
                          icon: Icons.notification_important_rounded,
                          delay: 400,
                          child: _NoteDisplay(
                            text: p.notes!,
                            isWarning: true,
                            icon: Icons.warning_amber_rounded,
                          ),
                        ),
                        const Gap(16),
                      ],

                      // ⚠️ BEFORE the entry sections. Storage is a fact about
                      // the GOODS; "System Entry By" and "Released By" name
                      // the officers who signed for them. Reading the people
                      // last is how every paper form in this office is laid
                      // out -- the signature goes at the bottom.
                      //
                      // ⚠️ And ask FIRST, then build the frame. The note
                      // returns an empty box for a package with no warehouse
                      // entries -- goods that never reached a zone -- while a
                      // section wrapping it still drew its heading and its
                      // border, so the popup carried an empty panel titled
                      // STORAGE.
                      if ((widget.useLegacySummary ||
                              isNoChargeContext ||
                              isSoldContext) &&
                          (ref.watch(storageChargeVisibleProvider(p.id)) ??
                              false))
                        _DetailSection(
                          title: 'Storage',
                          icon: Icons.warehouse_rounded,
                          delay: 480,
                          child: StorageChargeNote(
                            packageId: p.id,
                            packageItemId:
                                widget.highlightEntry?.packageItemId ??
                                    widget.highlightItemId,
                          ),
                        ),

                      // Entry Person Section
                      _SystemEntrySection(
                        officerDisplay: officerDisplay,
                        badgeNumber: displayBadgeNumber,
                        delay: 500,
                      ),
                      const Gap(16),

                      // Released By Section
                      // For dispositions like Destroy/Re-export/Other, we change the label and icon.
                      if (!widget.useWarehouseSummary &&
                          widget.highlightEntry?.isReturned == true &&
                          !isSoldContext &&
                          (!isNoChargeContext ||
                              isDestroyedEntry ||
                              isReExportEntry ||
                              isOtherEntry)) ...[
                        material.Builder(builder: (context) {
                          String returnedOfficerTitle = 'Released By';
                          IconData returnedOfficerIcon =
                              Icons.keyboard_return_rounded;

                          if (isDestroyedEntry) {
                            returnedOfficerTitle = 'Destroyed By';
                            returnedOfficerIcon = Icons.delete_forever_rounded;
                          } else if (isReExportEntry) {
                            returnedOfficerTitle = 'Re-exported By';
                            returnedOfficerIcon = Icons.flight_takeoff_rounded;
                          } else if (isOtherEntry) {
                            String customText = 'Actioned';
                            final notes =
                                (widget.highlightEntry?.returnNotes ?? '')
                                    .trim();
                            // New "[OTHER: <text>]" tag — the disposition label
                            // lives inside the bracket.
                            final bracket = RegExp(r'^\[OTHER:\s*([^\]]*)\]',
                                    caseSensitive: false)
                                .firstMatch(notes);
                            if (bracket != null &&
                                bracket.group(1)!.trim().isNotEmpty) {
                              customText = bracket.group(1)!.trim();
                            } else {
                              // Legacy "[…] — <text>" form.
                              final m = RegExp(r'^\[([^\]]+)\](.*)')
                                  .firstMatch(notes);
                              if (m != null) {
                                final dashIndex = notes.indexOf('—');
                                if (dashIndex != -1) {
                                  customText =
                                      notes.substring(dashIndex + 1).trim();
                                } else {
                                  customText = 'Other';
                                }
                              }
                            }
                            returnedOfficerTitle = '$customText By';
                            returnedOfficerIcon = Icons.more_horiz_rounded;
                          }

                          return _SystemEntrySection(
                            officerDisplay: returnedOfficerDisplay,
                            badgeNumber: returnedOfficerBadge,
                            delay: 550,
                            customTitle: returnedOfficerTitle,
                            customIcon: returnedOfficerIcon,
                          );
                        }),
                        const Gap(16),
                      ],

                      // Skip on legacy summary — Receipt No/Date already shown in
                      // the Package Item Summary section above (avoids a duplicate).
                      if (!widget.useLegacySummary &&
                          !widget.useWarehouseSummary &&
                          widget.highlightEntry?.isReturned == true &&
                          (returnedReceiptNo != null ||
                              returnedReceiptDate != null)) ...[
                        _DetailSection(
                          title: 'Receipt Details',
                          icon: Icons.receipt_long_rounded,
                          delay: 560,
                          child: Row(
                            children: [
                              if (returnedReceiptNo != null)
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.receipt_rounded,
                                    label: 'Receipt No',
                                    value: returnedReceiptNo!,
                                  ),
                                ),
                              if (returnedReceiptNo != null &&
                                  returnedReceiptDate != null)
                                const Gap(12),
                              if (returnedReceiptDate != null)
                                Expanded(
                                  child: _DetailItem(
                                    icon: Icons.event_rounded,
                                    label: 'Receipt Date',
                                    value: returnedReceiptDate!,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Gap(16),
                      ],

                      // Warehouse Charges Section — hidden for no-charge
                      // (abandoned / forfeit / destroy) items and sold items.
                      // Skipped on legacy summary (charge shown in the summary
                      // above, entry-date based).
                      if (!widget.useLegacySummary &&
                          widget.highlightEntry != null &&
                          !isNoChargeContext &&
                          !isSoldContext)
                        _DetailSection(
                          title: 'Warehouse Charges',
                          icon: Icons.payments_rounded,
                          delay: 600,
                          child: Column(
                            children: [
                              _DetailItem(
                                icon: Icons.calculate_rounded,
                                label: 'Storage Fee (LKR)',
                                value:
                                    'LKR ${NumberFormat('#,##0.00').format(widget.highlightEntry!.calculatePackageCharge([
                                      highlightedItem!
                                    ], widget.storageRate))}',
                                valueColor: context.colors.successGreen,
                              ),
                            ],
                          ),
                        ),
                      // ⚠️ What the SPACE has cost, on every popup that does
                      // not already carry the section above.
                      //
                      // That section is skipped in three cases and each
                      // leaves a real gap: `useLegacySummary` (which is
                      // nearly every popup in the app), a no-charge status,
                      // and a sale. The first shows an entry-date charge in
                      // its summary but only on the pages that have one; the
                      // second and third are goods the state has taken or
                      // sold, where nobody is billed -- but the days in a
                      // zone still happened, and every valuation, committee
                      // and sale decision is made against them.
                      //
                      // The note says which of the two figures it is: an
                      // accrued CHARGE payable on collection, or the COST of
                      // space nobody will be billed for.
                      if (() {
                        // Sold Packages page: always show Sale & Financial.
                        if (widget.isSoldPage) return true;

                        // All other pages: only show if entry is SOLD.
                        final entryNotes =
                            widget.highlightEntry?.returnNotes ?? '';
                        return entryNotes.toUpperCase().contains('SOLD');
                      }())
                        _SaleFinancialsSection(
                          package: p,
                          packageItemId: widget.highlightEntry?.packageItemId ??
                              widget.highlightItemId,
                          // Parse "[FINAL:SOLD] — Receipt: <no>" so the correct
                          // TSI row (price/taxes) is shown when an item was sold
                          // across several partial tenders.
                          receipt: (() {
                            final m = RegExp(r'Receipt:\s*([^\|—]+)',
                                    caseSensitive: false)
                                .firstMatch(
                                    widget.highlightEntry?.returnNotes ?? '');
                            return m?.group(1)?.trim();
                          }()),
                          // Who recorded the sale — shown here instead of in the
                          // Sold table.
                          soldBy: widget.highlightEntry?.returnedByName ??
                              widget.highlightEntry?.returnedByBadge,
                          // Prefer the caller's figure; fall back to the
                          // highlighted entry's own count so the popup still
                          // agrees with the row when no qty was passed.
                          valuationQty: widget.valuationQty ??
                              widget.highlightEntry?.itemCount,
                        ),
                      // ⚠️ Scoped to the item this popup is ABOUT, not to the
                      // package. `p.items.any(...)` asked whether ANY item was
                      // being destroyed, so opening a SOLD item showed it the
                      // Destruction Status panel because a sibling under the
                      // same SR number was pending destruction. One number
                      // covers several goods, and they meet different ends.
                      //
                      // ⚠️ And an APPEAL RULING overrides the item's status.
                      // CED/GL1/SR/03/2025 held Latex Gloves whose status
                      // still read `destroyed` while the Directorate had
                      // ruled SALE — so a package the Decided Goods table
                      // labels "Decided · Sell" opened showing DESTRUCTION
                      // STATUS. Seven rows carry that contradiction. The
                      // ruling is the later word and the authoritative one:
                      // the status is what the yard recorded before the
                      // appeal was heard.
                      if (!_appealRuledAwayFromDestruction(
                              widget.tenderHistoryFor, highlightedItem?.id) &&
                          (isDestroyedEntry ||
                              (highlightedItem != null
                                  ? _statusIsDestruction(highlightedItem.status)
                                  : p.items.any(
                                      (i) => _statusIsDestruction(i.status)))))
                        _DestructionFinancialsSection(
                          package: p,
                          // ⚠️ The ITEM this popup is about, not just the
                          // package. A package can hold one item already
                          // destroyed and another still pending, and the
                          // section used to ask "does ANY item say
                          // destroyed?" — so opening a PENDING row showed
                          // DESTROYED because a sibling was.
                          item: highlightedItem,
                          srFinancials: widget.srFinancials,
                        ),
                      // ⚠️ The OTHER expenses — auction, advertising,
                      // transport, labour — shown wherever they exist.
                      //
                      // The panel above is destruction-only and correctly so.
                      // But the Disposal Expenses tab lists SRs whose costs
                      // are an auction fee or a transport charge with no
                      // destruction at all, and opening Details on one of
                      // those showed the goods and the storage and then
                      // simply stopped: the very figures the row was listing
                      // appeared nowhere in the popup it opened.
                      if (widget.srFinancials != null &&
                          _hasNonDestructionExpense(widget.srFinancials!))
                        _DisposalExpenseBreakdown(sr: widget.srFinancials!),
                      // ⚠️ Disposal expenses belong to DESTRUCTION, and the
                      // `else` that used to be here gave them to everything
                      // that was NOT being destroyed. So a SOLD item showed
                      // "Disposal Expenses & Financials" — a destroying
                      // deposit, a cost breakdown, a shortfall — for goods
                      // that were never destroyed: every figure in it either
                      // zero, or an auction cost re-labelled as a disposal
                      // shortfall, which is worse than blank.
                      //
                      // Sold goods have their own money section, Sale &
                      // Financial Information, and that one is true. This
                      // panel now appears only where its numbers mean
                      // something — inside the destruction section above.
                    ],
                  ),
                ),
              ),
              if (widget.useWarehouseSummary || widget.allowEdit)
                material.Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade50,
                    border: Border(
                        top: BorderSide(color: context.colors.borderColor)),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(23)),
                  ),
                  child: Row(
                    children: [
                      material.Tooltip(
                        message: !canUpdatePackage
                            ? 'Package updates are restricted to SDDC / DDC officers only'
                            : '',
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canUpdatePackage
                                ? context.colors.primaryGold
                                : Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Update'),
                          onPressed: !canUpdatePackage
                              ? null
                              : () {
                                  showAppDialog(
                                    context: context,
                                    builder: (_) => PackageUpdateDialog(
                                      package: p,
                                      highlightedItem: highlightedItem,
                                      highlightEntry: widget.highlightEntry,
                                      storageRate: widget.storageRate,
                                    ),
                                  );
                                },
                        ),
                      ),
                      const Gap(12),
                      // NOT offered on the WAREHOUSE dialog. Every status now
                      // has its own page (Detained / Abandoned / Forfeited /
                      // Other) where the goods are actioned, so the warehouse
                      // is a view of what it holds: look, and Update. The
                      // Appeal column in its table still shows where each item
                      // stands.
                      if (!widget.useWarehouseSummary &&
                          widget.highlightEntry != null &&
                          !widget.highlightEntry!.isReturned)
                        material.Tooltip(
                          message: isOfficer
                              ? 'Actions are restricted to SDDC / DDC officers only'
                              : (isConfiscated
                                  ? 'Confiscated / Forfeited / Abandoned packages cannot be actioned'
                                  : ''),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (isConfiscated || isOfficer)
                                  ? Colors.grey
                                  : const Color(0xFF5C6BC0),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                            ),
                            icon: const Icon(Icons.bolt_rounded, size: 18),
                            label: const Text('Actions'),
                            // Officers can view but not action (same as Update).
                            onPressed: (isConfiscated || isOfficer)
                                ? null
                                : () => _showActionsDialog(
                                    context, widget.highlightEntry!,
                                    highlightedItem: highlightedItem),
                          ),
                        ),
                    ],
                  ),
                ),
              // ── Final Disposition footer ──
              // Shown for every appeal-expired item (allowFinalDisposition),
              // regardless of how it reached the Other/Abandoned table. Every
              // such item MUST still be actionable — Release / Re-export / Other
              // (recorded directly) or Sale / Destroy (Central Disposal request)
              // — so it can move on to its final-outcome table. Hidden only while
              // an appeal is still open, or once a FINAL disposition is recorded.
              // Footer action shows ONLY when the caller actually wires up the
              // disposition callback (Forfeited screen). Read-only viewers like
              // Central Disposal / Valuation pass no callback → no button.
              // NOT shown to the WAREHOUSE dialog, which is view + Update
              // only: goods are actioned on their own status page. The status
              // pages (Detained / Abandoned / Other / Forfeited) have no
              // Actions button, so this footer is their only route.
              if (widget.allowFinalDisposition &&
                  widget.onSaleOrDestroyRequest != null &&
                  !widget.useWarehouseSummary &&
                  (widget.useLegacySummary || widget.highlightItemId != null) &&
                  highlightedItem != null &&
                  (widget.forceFinalDisposition ||
                      !_hasFinalDisposition(p, highlightedItem.id)))
                material.Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade50,
                    border: Border(
                        top: BorderSide(color: context.colors.borderColor)),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(23)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Record the final outcome for these goods',
                          style: material.TextStyle(
                              color: context.colors.textMuted, fontSize: 12),
                        ),
                      ),
                      material.Tooltip(
                        message: isOfficer
                            ? 'Only SDDC / DDC can record the final disposition'
                            : '',
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5C6BC0),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                context.colors.textMuted.withOpacity(0.25),
                            disabledForegroundColor: context.colors.textMuted,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          icon: const Icon(Icons.outbound_rounded, size: 18),
                          label: const Text('Final Disposition'),
                          // Officers may view but never record the final
                          // disposition — the action is SDDC / DDC only.
                          onPressed: isOfficer
                              ? null
                              : () => _showFinalDispositionDialog(
                                    context,
                                    item: highlightedItem,
                                    entry: widget.highlightEntry,
                                    isOfficer: isOfficer,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Generic footer action (e.g. Appeal Directorate Hold/Release) ──
              if (widget.footerActionLabel != null)
                material.Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade50,
                    border: Border(
                        top: BorderSide(color: context.colors.borderColor)),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(23)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.footerActionHint ?? '',
                          style: material.TextStyle(
                              color: context.colors.textMuted, fontSize: 12),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.footerActionColor ??
                              context.colors.primaryGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        icon: Icon(
                            widget.footerActionIcon ?? Icons.check_rounded,
                            size: 18),
                        label: Text(widget.footerActionLabel!),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onFooterAction?.call();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _statusIsDestruction(String? status) {
  final st = (status ?? '').toLowerCase();
  return st == 'destroyed' ||
      st == 'supposed to be destroyed' ||
      st == 'destroy';
}

/// Whether this SR carries any expense the Destruction panel does not show.
///
/// ⚠️ Destruction is deliberately excluded: it has its own panel with the
/// deposit, the shortfall and the refund beside it, and repeating the figure
/// in two places invites the reader to add it twice.
bool _hasNonDestructionExpense(SrFinancials sr) =>
    sr.advertisingExpense > 0 ||
    sr.labourExpense > 0 ||
    sr.transportExpense > 0 ||
    sr.auctionExpense > 0;

/// The expense breakdown for an SR whose costs are not a destruction.
/// What happened to this package's APPEAL: when it was forfeited, when the
/// window closes, whether a hold is on it, and what was finally ruled.
///
/// ⚠️ The Appeal Directorate's two tables label a package "On Appeal Hold" or
/// "Decided · Sell", and its Details popup said nothing about the appeal at
/// all — not the date it was lodged, not the deadline, not the ruling or when
/// it was made. An officer opening the row could not check the very thing the
/// page exists for.
///
/// A ruling is per ITEM (item_appeal_decisions), so when the popup is about
/// one item this shows THAT item's ruling. The package-level fields are the
/// fallback for rows decided before per-item rulings existed.
/// True when the Appeal Directorate ruled this item to something OTHER than
/// destruction.
///
/// ⚠️ A ruling outranks the item's status. The status is what the yard
/// recorded when it seized the goods; the ruling is what the Directorate
/// decided afterwards, and it is the later word. Seven seeded rows carry an
/// item marked `destroyed` whose ruling is SALE or RELEASE — without this the
/// popup showed a Destruction Status panel for goods the Decided Goods table
/// had just labelled "Decided · Sell".
///
/// DESTROY and a missing ruling both return false: the first agrees with the
/// destruction panel, the second leaves the status to decide as before.
bool _appealRuledAwayFromDestruction(
    ForfeitedPackageModel? forfeited, String? itemId) {
  if (forfeited == null || itemId == null) return false;
  final raw = forfeited.itemAppealDecisions[itemId] as Map<String, dynamic>?;
  final decision =
      ((raw?['decision'] as String?) ?? forfeited.appealDecision ?? '')
          .trim()
          .toUpperCase();
  if (decision.isEmpty) return false;
  return decision != 'DESTROY';
}

/// What the appeal window's start date is called, for this kind of goods.
///
/// ⚠️ `forfeited_packages` holds every route into the appeal window, not
/// just forfeits: abandoned, "Other", detained and perishable goods all get a
/// row, and `forfeited_at` is simply the day that window opened. Calling it
/// "Forfeited on" for all of them says the State has taken goods that are
/// still under inquiry -- which is both wrong and the kind of wrong an
/// officer would act on.
///
/// The wording follows [SourceChip], so one row reads the same in the table
/// and in the popup.
String _appealStartLabel(String source) =>
    switch (source.trim().toLowerCase()) {
      'abandoned' => 'Abandoned on',
      'detain' || 'detained' => 'Detained on',
      'perishable' => 'Recorded on',
      // "Other" is a status, not an event with a verb of its own.
      'other' => 'Recorded on',
      _ => 'Forfeited on',
    };

class _AppealHistorySection extends StatelessWidget {
  final ForfeitedPackageModel forfeited;

  /// The item this popup is about, when it is about one.
  final String? itemId;

  const _AppealHistorySection({required this.forfeited, this.itemId});

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('yyyy-MM-dd');
    final f = forfeited;

    // The ruling for THIS item, falling back to the package's own.
    final raw = itemId == null
        ? null
        : f.itemAppealDecisions[itemId] as Map<String, dynamic>?;
    final decision = (raw?['decision'] as String?) ?? f.appealDecision;
    final note = (raw?['note'] as String?) ?? f.appealDecisionNote;
    final decidedAt = raw?['decided_at'] != null
        ? DateTime.tryParse(raw!['decided_at'].toString())
        : f.appealDecidedAt;

    final outcome = ItemAppealOutcome(decision: decision, onHold: f.appealHold);
    final decided = outcome.isDecided;

    // The state line, in the same words the tables use.
    final (String state, Color colour, IconData icon) = f.appealHold
        ? (
            'On Appeal Hold',
            context.colors.warningAmber,
            Icons.pan_tool_rounded
          )
        : decided
            ? (
                'Decided · ${outcome.label ?? decision!}',
                context.colors.successGreen,
                Icons.gavel_rounded
              )
            : DateTime.now().isBefore(f.appealDeadline)
                ? (
                    'In appeal window',
                    context.colors.accentLightBlue,
                    Icons.schedule_rounded
                  )
                : (
                    'Window closed, no appeal',
                    context.colors.textMuted,
                    Icons.event_busy_rounded
                  );

    return _DetailSection(
      title: 'Appeal',
      icon: Icons.balance_rounded,
      delay: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          material.Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colour.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colour.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: colour),
                const Gap(10),
                Expanded(
                  child: Text(state,
                      style: material.TextStyle(
                          color: colour,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const Gap(12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DetailItem(
                  icon: Icons.gavel_rounded,
                  // ⚠️ Named for what this row ACTUALLY is. The appeal window
                  // opens for abandoned, "Other", detained and perishable
                  // goods too -- 250 of the 318 rows in this database are one
                  // of those -- and every one of them read "Forfeited on",
                  // which is a statement that the State has taken goods still
                  // under inquiry. The same mistake SourceChip already
                  // corrects for Detained.
                  label: _appealStartLabel(f.source),
                  value: date.format(f.forfeitedAt),
                ),
              ),
              const Gap(12),
              Expanded(
                child: _DetailItem(
                  icon: Icons.event_rounded,
                  label: 'Appeal deadline',
                  value: date.format(f.appealDeadline),
                  // Red only while it still MEANS something: once a ruling is
                  // in, a passed deadline is history, not a warning.
                  valueColor: !decided &&
                          !f.appealHold &&
                          DateTime.now().isAfter(f.appealDeadline)
                      ? context.colors.dangerRed
                      : null,
                ),
              ),
            ],
          ),
          if (f.appealHold) ...[
            const Gap(12),
            _DetailItem(
              icon: Icons.pan_tool_rounded,
              label: 'Hold placed on',
              value:
                  f.appealHeldAt != null ? date.format(f.appealHeldAt!) : '—',
            ),
            if ((f.appealHoldNote ?? '').trim().isNotEmpty) ...[
              const Gap(12),
              _DetailItem(
                icon: Icons.sticky_note_2_rounded,
                label: 'Reason for the hold',
                value: f.appealHoldNote!.trim(),
              ),
            ],
          ],
          if (decided) ...[
            const Gap(12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DetailItem(
                    icon: Icons.check_circle_rounded,
                    label: 'Ruling',
                    value: outcome.label ?? decision!,
                    valueColor: context.colors.successGreen,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _DetailItem(
                    icon: Icons.event_available_rounded,
                    label: 'Decided on',
                    value: decidedAt != null ? date.format(decidedAt) : '—',
                  ),
                ),
              ],
            ),
            if ((note ?? '').trim().isNotEmpty) ...[
              const Gap(12),
              _DetailItem(
                icon: Icons.sticky_note_2_rounded,
                label: 'Directorate’s note',
                value: note!.trim(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DisposalExpenseBreakdown extends StatelessWidget {
  final SrFinancials sr;
  const _DisposalExpenseBreakdown({required this.sr});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final rows = <(String, double, IconData)>[
      ('Advertising', sr.advertisingExpense, Icons.campaign_rounded),
      ('Labour', sr.labourExpense, Icons.groups_rounded),
      ('Transport', sr.transportExpense, Icons.local_shipping_rounded),
      ('Auction', sr.auctionExpense, Icons.gavel_rounded),
      // Shown only when there IS one, so a non-destruction SR does not carry
      // an empty destruction line.
      if (sr.destructionExpense > 0)
        (
          'Destruction',
          sr.destructionExpense,
          Icons.local_fire_department_rounded
        ),
    ].where((r) => r.$2 > 0).toList();

    return _DetailSection(
      title: 'Disposal Expenses',
      icon: Icons.receipt_long_rounded,
      delay: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ⚠️ _DetailItem, the same card every other figure in this popup
          // uses — a bespoke tile here would make one section look like a
          // different app. Two to a row, matching the destruction panel.
          for (var i = 0; i < rows.length; i += 2) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DetailItem(
                    icon: rows[i].$3,
                    label: rows[i].$1,
                    value: 'LKR ${money.format(rows[i].$2)}',
                    valueColor: context.colors.textPrimary,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: i + 1 < rows.length
                      ? _DetailItem(
                          icon: rows[i + 1].$3,
                          label: rows[i + 1].$1,
                          value: 'LKR ${money.format(rows[i + 1].$2)}',
                          valueColor: context.colors.textPrimary,
                        )
                      : const SizedBox(),
                ),
              ],
            ),
            const Gap(12),
          ],
          const Gap(12),
          material.Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.surfaceDark,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.colors.borderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.summarize_rounded,
                    size: 16, color: context.colors.textMuted),
                const Gap(10),
                Text('Total spent',
                    style: material.TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('LKR ${money.format(sr.depositSpent)}',
                    style: material.TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DestructionFinancialsSection extends StatelessWidget {
  final PackageModel package;

  /// The item the popup was opened for, when it was opened for one.
  ///
  /// ⚠️ Null only for a whole-package view. Where it is set it DECIDES the
  /// status: a package with one destroyed item and one pending item is not
  /// "destroyed", and the row the officer clicked says which they meant.
  final PackageItem? item;
  final SrFinancials? srFinancials;

  const _DestructionFinancialsSection({
    required this.package,
    this.item,
    this.srFinancials,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final green = context.colors.successGreen;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ⚠️ THIS item's status when the popup is about one, and only then the
    // package's. Asking `package.items.any(destroyed)` reported DESTROYED on
    // a row the table itself was showing as Pending, because a DIFFERENT
    // item in the same SR had been destroyed.
    final bool isDestroyed;
    if (item != null) {
      final st = (item!.status ?? '').toLowerCase();
      isDestroyed = st == 'destroyed' ||
          package.warehouseEntries.any((e) =>
              e.packageItemId == item!.id &&
              (e.returnNotes ?? '')
                  .trim()
                  .toUpperCase()
                  .startsWith('[FINAL:DESTROYED'));
    } else {
      isDestroyed = package.status?.toLowerCase() == 'destroyed' ||
          package.items.any((i) {
            final st = (i.status ?? '').toLowerCase();
            return st == 'destroyed';
          }) ||
          package.warehouseEntries.any((e) {
            final n = (e.returnNotes ?? '').trim().toUpperCase();
            return n.startsWith('[FINAL:DESTROYED');
          });
    }

    return _DetailSection(
      title: 'Destruction Status & Financials',
      icon: Icons.local_fire_department_rounded,
      delay: 350,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Status Badge ──
          Row(
            children: [
              material.Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isDestroyed ? green : context.colors.warningAmber)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isDestroyed ? green : context.colors.warningAmber)
                        .withOpacity(0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    material.Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color:
                            isDestroyed ? green : context.colors.warningAmber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Gap(8),
                    Text(
                      isDestroyed ? 'DESTROYED' : 'PENDING DESTRUCTION',
                      style: material.TextStyle(
                        color:
                            isDestroyed ? green : context.colors.warningAmber,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(14),

          if (srFinancials != null) ...[
            // ── Deposit & Total Expenses ──
            Row(
              children: [
                Expanded(
                  child: _DetailItem(
                    icon: Icons.savings_rounded,
                    label: 'Destruction Deposit',
                    value:
                        'LKR ${money.format(srFinancials!.destroyingDeposit)}',
                    valueColor: green,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _DetailItem(
                    icon: Icons.payments_rounded,
                    label: 'Total Expenses',
                    value: 'LKR ${money.format(srFinancials!.depositSpent)}',
                    valueColor: srFinancials!.depositSpent > 0
                        ? context.colors.dangerRed
                        : null,
                  ),
                ),
              ],
            ),

            // ── Refund / Shortfall ──
            Row(
              children: [
                Expanded(
                  child: _DetailItem(
                    icon: Icons.undo_rounded,
                    label: srFinancials!.deficit > 0
                        ? 'Shortfall'
                        : 'Refund Amount',
                    value: srFinancials!.deficit > 0
                        ? '− LKR ${money.format(srFinancials!.deficit)}'
                        : 'LKR ${money.format(srFinancials!.refund)}',
                    valueColor: srFinancials!.deficit > 0
                        ? context.colors.dangerRed
                        : green,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _DetailItem(
                    icon: Icons.info_outline_rounded,
                    label: 'Expense Status',
                    value: srFinancials!.depositSpent == 0
                        ? 'Pending'
                        : (srFinancials!.deficit > 0
                            ? 'Shortfall'
                            : 'Refundable'),
                    valueColor: srFinancials!.depositSpent == 0
                        ? context.colors.warningAmber
                        : (srFinancials!.deficit > 0
                            ? context.colors.dangerRed
                            : green),
                  ),
                ),
              ],
            ),
            const Gap(12),

            // ── Cost Breakdown ──
            material.Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isDark ? context.colors.surfaceDark : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cost Breakdown',
                    style: material.TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(8),
                  Row(
                    children: [
                      Expanded(
                        child: _ExpenseCostBox(
                          label: 'Destruction',
                          amount: srFinancials!.destructionExpense,
                          color: context.colors.dangerRed,
                        ),
                      ),
                      const Gap(8),
                      Expanded(
                        child: _ExpenseCostBox(
                          label: 'Labour',
                          amount: srFinancials!.labourExpense,
                          color: context.colors.accentLightBlue,
                        ),
                      ),
                    ],
                  ),
                  const Gap(8),
                  Row(
                    children: [
                      Expanded(
                        child: _ExpenseCostBox(
                          label: 'Transport',
                          amount: srFinancials!.transportExpense,
                          color: context.colors.customsBlue,
                        ),
                      ),
                      // ⚠️ ADVERTISING IS ALWAYS SHOWN, like Destruction,
                      // Labour and Transport beside it.
                      //
                      // It used to appear only when non-zero, on the same
                      // wrong premise the entry form carried: that a
                      // destruction is never advertised. It is, and the cost
                      // comes out of the destroying deposit -- so a blank
                      // here means "nothing spent yet", which is information,
                      // not an empty box to hide.
                      const Gap(8),
                      Expanded(
                        child: _ExpenseCostBox(
                          label: 'Advertising',
                          amount: srFinancials!.advertisingExpense,
                          color: context.colors.warningAmber,
                        ),
                      ),
                      // Auction stays conditional: a destroyed item is never
                      // sold, so a figure here is legacy data rather than a
                      // field anyone fills.

                      if (srFinancials!.auctionExpense > 0) ...[
                        const Gap(8),
                        Expanded(
                          child: _ExpenseCostBox(
                            label: 'Auction',
                            amount: srFinancials!.auctionExpense,
                            color: context.colors.primaryGold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ] else
            // No financial data available yet
            material.Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    isDark ? context.colors.surfaceDark : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: context.colors.textMuted),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      'Financial data will be available once destruction expenses are recorded by the Central Disposal Directorate.',
                      style: material.TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExpenseCostBox extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _ExpenseCostBox({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return material.Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: material.TextStyle(
              color: context.colors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(2),
          Text(
            amount == 0 ? '—' : 'LKR ${money.format(amount)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: material.TextStyle(
              color: amount == 0 ? context.colors.textMuted : color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final isPending = s.contains('pending');
    final isInspected = s.contains('inspected');
    final color = isPending
        ? context.colors.primaryGold
        : (isInspected ? context.colors.successGreen : Colors.blue);
    return material.Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          material.Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const Gap(6),
          Text(status.toUpperCase(),
              style: material.TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

/// Everything that happened to ONE item, under that item.
///
/// ⚠️ The popup could already show a tender history, but only when a caller
/// handed it a single forfeited package. Opened from Goods History -- where an
/// SR holds several items that each met a different end -- it showed nothing,
/// so an officer reading one SR could not tell that the Truck Tyres sold while
/// the Steel Sheets were still sitting in Open Area 01.
///
/// Everything here is per item because forfeiture is per item: the appeal, the
/// tender rounds with their valuations and bids, the committee, the final
/// outcome and the hand-over all belong to the item, not to the SR number.
///
/// Renders NOTHING for an item that never left the ordinary path -- no
/// forfeiture, no appeal. A section reading "no tender history" on goods that
/// were never meant to go to tender is noise.
/// Where THESE goods have physically been, and what that has cost — one
/// block per item, from the day they were admitted to the day they leave.
///
/// ⚠️ Per ITEM, not per SR. An SR's items are admitted separately, can sit in
/// different warehouses and zones, are held under different reasons and leave
/// on different days — so a single package-level "Current Warehouse" line
/// answered the question for one item and quietly misled about every other.
///
/// Renders nothing for an item that has never been in a warehouse: an empty
/// storage block on goods that were never admitted is noise.
class _ItemStorageSection extends ConsumerWidget {
  final PackageModel package;
  final PackageItem item;
  final WarehouseEntryModel? highlightEntry;

  const _ItemStorageSection({
    required this.package,
    required this.item,
    this.highlightEntry,
  });

  static String fmtDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Entries belonging to THIS item. Watch live packageDataProvider so
    // warehouse entries and displacements update dynamically.
    final freshPkg = ref.watch(packageDataProvider(package.id)).valueOrNull ??
        ref.watch(packageByIdProvider(package.id)).valueOrNull ??
        package;
    final allEntries = freshPkg.warehouseEntries.isNotEmpty
        ? freshPkg.warehouseEntries
        : package.warehouseEntries;

    final entries = allEntries.where((e) {
      if (e.packageItemId == item.id || e.packageItemId == null) return true;
      if (freshPkg.items.length == 1 || package.items.length == 1) return true;
      return false;
    }).toList();

    if (highlightEntry != null &&
        (highlightEntry!.packageId == package.id ||
            highlightEntry!.packageId == freshPkg.id)) {
      if (highlightEntry!.packageItemId == null ||
          highlightEntry!.packageItemId == item.id ||
          freshPkg.items.length <= 1 ||
          package.items.length <= 1) {
        final existingIdx =
            entries.indexWhere((e) => e.id == highlightEntry!.id);
        if (existingIdx != -1) {
          entries[existingIdx] = highlightEntry!;
        } else {
          entries.add(highlightEntry!);
        }
      }
    }
    entries.sort((a, b) => a.admittedAt.compareTo(b.admittedAt));

    // Put the entry that opened the popup first in the reader's view. The
    // movement note is important enough to see without opening each history
    // row, especially when an SR has more than one warehouse admission.
    WarehouseEntryModel? displacedEntry;
    if (highlightEntry?.movedForSpace == true) {
      displacedEntry =
          entries.where((e) => e.id == highlightEntry!.id).firstOrNull;
    }
    displacedEntry ??= entries.where((e) => e.movedForSpace).firstOrNull;

    final isPerishable = item.nature == kNaturePerishable;
    if (entries.isEmpty && !isPerishable) return const SizedBox.shrink();

    final rates = ref.watch(storageRateProvider).valueOrNull ??
        const <DateTime, double>{};
    final live = entries.where((e) => !e.isReturned).toList();
    final money = NumberFormat('#,##0.00');

    // ⚠️ Unsold goods carry NO figure at all — see storage_charge_note.dart.
    // Top Management has ruled on them after every sale route failed, so
    // nobody is billed and nobody is pricing them against the days any
    // more. The same package reappears under each Final Outcome page, so
    // the rule travels with the figure rather than with a page.
    final proposals = ref.watch(unsoldProposalsProvider).valueOrNull;
    final byItem = ref.watch(forfeitedByItemProvider(package.id)).valueOrNull;
    final hasProposal = proposals != null &&
        proposals.isNotEmpty &&
        byItem != null &&
        byItem.values.any((f) => proposals.containsKey(f.id));

    final TenderSaleItemModel? saleItem = ref
        .watch(saleItemForPackageItemProvider('${package.id}|${item.id}'))
        .valueOrNull;

    final unsoldDisposal = hasProposal || saleItem?.unsold == true;

    final isDelivered = saleItem?.isDelivered == true;
    final DateTime perishableStart = package.entryDate ?? package.createdAt;
    final DateTime? perishableEnd = isDelivered
        ? (saleItem?.deliveredAt ?? saleItem?.soldAt ?? DateTime.now())
        : null;
    final int perishableUnits = item.quantity > 0 ? item.quantity : 1;
    final double perishableSpaceCost = isPerishable && entries.isEmpty
        ? spaceCostFor(
            from: perishableStart,
            units: perishableUnits,
            rates: rates,
            until: perishableEnd,
          )
        : 0.0;

    // Charges accrue per entry and stop when the goods leave, so the total is
    // the sum over entries — live ones still climbing, closed ones fixed.
    final charge = entries.isNotEmpty
        ? entries.fold<double>(
            0, (a, e) => a + e.calculatePackageCharge(package.items, rates))
        : (saleItem?.sold == true ? perishableSpaceCost : 0.0);

    // ⚠️ And what the SPACE cost, which is a different question. Forfeited,
    // confiscated, abandoned and destroyed goods are never billed — that is
    // a billing rule, not a statement that they were free to keep. They
    // occupied a zone for the same days as anything else, and every
    // valuation, committee figure and sale decision is taken against that
    // cost. Showing "No charge" and nothing else hid it entirely.
    final spaceCost = entries.isNotEmpty
        ? entries.fold<double>(
            0,
            (a, e) =>
                a +
                spaceCostFor(
                  from: e.admittedAt,
                  units: e.itemCount,
                  rates: rates,
                  until: e.returnedAt,
                ))
        : perishableSpaceCost;

    final billed = charge > 0;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.inventory_2_outlined,
                  size: 15, color: context.colors.accentLightBlue),
              const Gap(8),
              material.Text('Storage & Movement',
                  style: material.TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary)),
              const Spacer(),
              if (!unsoldDisposal && (billed || spaceCost > 0))
                material.Text(
                    'LKR ' + money.format(billed ? charge : spaceCost),
                    style: material.TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        // Not gold when nobody pays it: the figure is real
                        // but it is a cost to the yard, not a bill to anyone.
                        color: billed
                            ? context.colors.primaryGold
                            : context.colors.textSecondary)),
            ]),
            const Gap(4),
            material.Text(
              unsoldDisposal
                  ? 'No warehouse charge — storage is not billed on unsold '
                      'goods.'
                  : !billed && spaceCost > 0
                      ? (isPerishable && entries.isEmpty
                          ? 'Perishable goods held in yard — space cost accrued so far.'
                          : 'Not billed — these goods were taken by the State. '
                              'This is what the space they occupied has cost.')
                      : (entries.isEmpty && isPerishable)
                          ? (isDelivered
                              ? 'Perishable goods delivered — storage charges billed for yard stay.'
                              : saleItem?.sold == true
                                  ? 'Perishable goods sold — storage charges accrue until delivery.'
                                  : 'Charges accrue until the goods are sold or delivered out.')
                          : live.isEmpty
                              ? 'These goods have left the warehouse.'
                              : 'Charges accrue until the goods are delivered '
                                  'out.',
              style: material.TextStyle(
                  fontSize: 10.5, color: context.colors.textMuted),
            ),
            if (displacedEntry != null)
              DisplacedNotice(
                entry: displacedEntry,
                warehouses: ref.watch(warehousesProvider).valueOrNull,
              ),
            const Gap(10),
            if (entries.isEmpty && isPerishable) ...[
              material.Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.colors.surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: Row(children: [
                  Icon(Icons.yard_outlined,
                      size: 16, color: context.colors.warningAmber),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        material.Text(
                          'Stored in Yard',
                          style: material.TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const Gap(2),
                        material.Text(
                          'Admitted: ${fmtDate(perishableStart)}'
                          '${isDelivered ? ' · Delivered: ${fmtDate(perishableEnd!)}' : saleItem?.sold == true ? ' · Sold: ${fmtDate(saleItem!.soldAt!)} (accruing to delivery)' : ' · Active in Yard'}'
                          ' · Units: $perishableUnits',
                          style: material.TextStyle(
                            fontSize: 11,
                            color: context.colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!unsoldDisposal && perishableSpaceCost > 0)
                    material.Text(
                      'LKR ${money.format(perishableSpaceCost)}',
                      style: material.TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: billed
                            ? context.colors.primaryGold
                            : context.colors.textSecondary,
                      ),
                    ),
                ]),
              ),
            ],
            for (final e in entries) ...[
              _ItemStorageEntryRow(
                entry: e,
                charge: e.calculatePackageCharge(package.items, rates),
                hideCharge: unsoldDisposal,
                spaceCost: spaceCostFor(
                  from: e.admittedAt,
                  units: e.itemCount,
                  rates: rates,
                  until: e.returnedAt,
                ),
                // Shown above the card already. An admission usually
                // inherits the item's activity, so repeating it on every
                // entry is noise — it earns its place only when this
                // admission was made under a DIFFERENT one.
                itemActivity: (item.reasons ?? '').trim(),
                warehouses: ref.watch(warehousesProvider).valueOrNull,
                showDisplacementNotice: e.id != displacedEntry?.id,
              ),
              if (e != entries.last) const Gap(8),
            ],
          ],
        ),
      ),
    );
  }
}

/// One admission of one item into one warehouse.
class _ItemStorageEntryRow extends StatelessWidget {
  final WarehouseEntryModel entry;
  final double charge;

  /// What the space cost regardless of who is billed — see the section above.
  final double spaceCost;

  /// The item's own Post Status Activity, already shown above the card.
  final String itemActivity;

  /// Unsold goods carry no money figure at all.
  final bool hideCharge;

  /// Every warehouse in the yard, so a displaced entry can name where it was
  /// MEANT to go. See DisplacedBadge for why this is not embedded in the
  /// query.
  final List<WarehouseModel>? warehouses;

  /// The selected moved entry is shown once under the section heading. Other
  /// moved admissions keep their own notice inside their history row.
  final bool showDisplacementNotice;

  const _ItemStorageEntryRow(
      {required this.entry,
      required this.charge,
      this.spaceCost = 0,
      this.itemActivity = '',
      this.hideCharge = false,
      this.warehouses,
      this.showDisplacementNotice = true});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    final out = entry.isReturned;
    // Still in the warehouse is the live case and reads as such; a closed
    // entry is history, and is deliberately quieter.
    final tone = out ? context.colors.textMuted : context.colors.successGreen;

    // WHERE: the warehouse and the zone within it. A zone is how goods are
    // actually found on the ground, so a warehouse alone is half an answer.
    final zone = (entry.zone ?? '').trim();
    final place = zone.isEmpty || zone.toLowerCase() == 'n/a'
        ? entry.warehouseName
        : entry.warehouseName + ' · Zone ' + zone;

    return material.Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderColor.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(out ? Icons.logout_rounded : Icons.warehouse_rounded,
                size: 13, color: tone),
            const Gap(6),
            Expanded(
              child: material.Text(place,
                  style: material.TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary)),
            ),
            _MiniTag(
                icon: out
                    ? Icons.check_circle_outline_rounded
                    : Icons.inventory_2_outlined,
                label: out ? 'Delivered out' : 'In warehouse',
                tint: tone),
          ]),
          const Gap(8),
          Wrap(spacing: 14, runSpacing: 6, children: [
            // Under WHICH status this admission was made. Skipped when it
            // simply repeats the activity printed above the card.
            if (entry.holdReason.trim().isNotEmpty &&
                entry.holdReason.trim().toLowerCase() !=
                    itemActivity.toLowerCase())
              _StorageFact(label: 'Held under', value: entry.holdReason.trim()),
            _StorageFact(label: 'Quantity', value: entry.itemCount.toString()),
            _StorageFact(
                label: 'Admitted',
                value: _ItemStorageSection.fmtDate(entry.admittedAt)),
            if (entry.admittedByName != null)
              _StorageFact(label: 'Admitted by', value: entry.admittedByName!),
            _StorageFact(
                label: out ? 'Days stored' : 'Days so far',
                value: entry.storageDays.toString()),
            if (out && entry.returnedAt != null)
              _StorageFact(
                  label: 'Left on',
                  value: _ItemStorageSection.fmtDate(entry.returnedAt!)),
            if (out && entry.returnedByName != null)
              _StorageFact(label: 'Released by', value: entry.returnedByName!),
            // Two different questions, so two different labels. "No charge"
            // alone answered neither: it said who pays without saying what
            // the space cost.
            if (hideCharge)
              const _StorageFact(label: 'Storage charge', value: 'Not charged')
            else
              _StorageFact(
                  label:
                      charge > 0 ? 'Storage charge' : 'Space cost (not billed)',
                  value: charge > 0
                      ? 'LKR ' + money.format(charge)
                      : spaceCost > 0
                          ? 'LKR ' + money.format(spaceCost)
                          : 'No charge',
                  strong: charge > 0),
          ]),
          // ⚠️ Below the figures, not among them: this is not another fact
          // about the storage, it is the reason the location above is not the
          // one the reader expected.
          if (showDisplacementNotice)
            DisplacedNotice(entry: entry, warehouses: warehouses),
        ],
      ),
    );
  }
}

/// A label over its value, for the storage grid.
class _StorageFact extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _StorageFact(
      {required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        material.Text(label,
            style: material.TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: context.colors.textMuted)),
        const Gap(2),
        material.Text(value,
            style: material.TextStyle(
                fontSize: 11.5,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: strong
                    ? context.colors.primaryGold
                    : context.colors.textSecondary)),
      ],
    );
  }
}

class _ItemLifecycleSection extends ConsumerWidget {
  final String packageId;
  final PackageItem item;

  const _ItemLifecycleSection({
    required this.packageId,
    required this.item,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forfeited =
        ref.watch(forfeitedByItemProvider(packageId)).valueOrNull?[item.id];
    final appeal =
        ref.watch(itemAppealOutcomesProvider(packageId)).valueOrNull?[item.id];
    // An appeal HOLD or a ruling is worth showing even with no forfeiture --
    // it is why the goods are not moving.
    final hasAppeal = appeal != null && (appeal.isDecided || appeal.onHold);
    if (forfeited == null && !hasAppeal) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.timeline_rounded,
                  size: 15, color: context.colors.accentLightBlue),
              const Gap(8),
              material.Text(
                'Goods Lifecycle',
                style: material.TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
            ]),
            const Gap(12),
            // ── Appeal ──────────────────────────────────────────────────
            // Shown FIRST: while an appeal is held nothing below it can
            // proceed, so it is the answer to "why has nothing happened".
            if (hasAppeal) ...[
              Row(children: [
                Expanded(
                  child: material.Text(
                    appeal.onHold ? 'Appeal' : 'Appeal decision',
                    style: material.TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textMuted),
                  ),
                ),
                AppealStateChip(
                  entryDate: forfeited?.forfeitedAt,
                  deadline: forfeited?.appealDeadline,
                  outcome: appeal,
                ),
              ]),
              if ((forfeited?.appealDecisionNote ?? '').trim().isNotEmpty) ...[
                const Gap(6),
                material.Text(
                  forfeited!.appealDecisionNote!.trim(),
                  style: material.TextStyle(
                      fontSize: 11, color: context.colors.textSecondary),
                ),
              ],
              const Gap(12),
            ],
            // ── Tender rounds, valuations, bids, committee, outcome ─────
            // The SAME section the disposal pages use, so a round reads
            // identically wherever it is opened -- one definition, and no
            // second story to keep in step with the first.
            if (forfeited != null)
              TenderHistorySection(
                forfeited: forfeited,
                qty: forfeited.entryQty ?? item.quantity,
              )
            else
              material.Text(
                'No tender rounds recorded for these goods.',
                style: material.TextStyle(
                    fontSize: 11, color: context.colors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final int delay;

  const _DetailSection({
    required this.title,
    required this.icon,
    required this.child,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return material.Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? context.colors.surfaceDark.withOpacity(0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          material.Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withOpacity(0.03),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              border:
                  Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: context.colors.primaryGold),
                const Gap(10),
                Text(
                  title.toUpperCase(),
                  style: material.TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ).animate().slideX(
              delay: Duration(milliseconds: delay),
              duration: 300.ms,
              begin: -0.2),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ).animate().fadeIn(
              delay: Duration(milliseconds: delay + 100), duration: 400.ms),
        ],
      ),
    );
  }
}

/// The Delivered / Pending pill the hand-over section carries.
///
/// ⚠️ Deliberately the same two colours as the table's own pill -- green
/// for gone, amber for still here -- because it answers the same question
/// about the same row. A third colour scheme for the same fact would make
/// the popup and the table look like two systems.
class _HandoverPill extends StatelessWidget {
  const _HandoverPill({required this.delivered, required this.kind});

  final bool delivered;
  final HandoverKind kind;

  @override
  Widget build(BuildContext context) {
    final tint =
        delivered ? context.colors.successGreen : context.colors.warningAmber;
    return material.Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(delivered ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 12, color: tint),
        const Gap(5),
        Text(delivered ? kind.pillDone : kind.pillPending,
            style: material.TextStyle(
                color: tint, fontSize: 10.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subValue;
  final Color? valueColor;

  /// A widget pinned to the RIGHT of the row -- a status pill, typically.
  final Widget? trailing;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    this.subValue,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: context.colors.borderColor.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            material.Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.colors.primaryGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: context.colors.primaryGold),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: material.TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    value,
                    style: material.TextStyle(
                      color: valueColor ?? context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subValue != null) ...[
                    const Gap(2),
                    Text(
                      subValue!,
                      style: material.TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const Gap(8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _CargoItemTile extends StatelessWidget {
  final PackageItem item;
  final int index;

  const _CargoItemTile({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.primaryGold.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: context.colors.primaryGold.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            material.Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.colors.primaryGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: material.TextStyle(
                    color: context.colors.primaryGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName,
                    style: material.TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (item.category != null)
                    Text(item.category!,
                        style: material.TextStyle(
                            color: context.colors.textMuted, fontSize: 11)),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      // "Value/unit", not "Value": the tables under the same
                      // word show unitValue × quantity.
                      'HS: ${(item.hsCode?.isNotEmpty == true) ? item.hsCode! : '—'}  ·  Value/unit: LKR ${NumberFormat('#,##0.00').format(item.unitValue)}',
                      style: material.TextStyle(
                          color: context.colors.textMuted, fontSize: 11),
                    ),
                  ),
                  if (item.reasons != null && item.reasons!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 10, color: context.colors.heldOrange),
                          const Gap(4),
                          Expanded(
                            child: Text(
                              item.reasons!,
                              style: material.TextStyle(
                                color: context.colors.heldOrange,
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Text(
              'x${item.quantity}',
              style: material.TextStyle(
                color: context.colors.primaryGold,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseHistoryTile extends StatelessWidget {
  final PackageModel package;
  final WarehouseEntryModel entry;
  final int index;
  final Map<DateTime, double> rate;
  final bool isHighlighted;
  final material.VoidCallback onRelease;

  const _WarehouseHistoryTile({
    required this.package,
    required this.entry,
    required this.index,
    required this.rate,
    required this.isHighlighted,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: material.Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isHighlighted
              ? context.colors.primaryGold.withOpacity(0.08)
              : context.colors.textPrimary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isHighlighted
                ? context.colors.primaryGold.withOpacity(0.5)
                : context.colors.borderColor.withOpacity(0.5),
            width: isHighlighted ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                material.Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.colors.primaryGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.warehouse_rounded,
                      size: 14, color: context.colors.primaryGold),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.warehouseName,
                        style: material.TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      ...entry.holdReason.split(',').map((reason) => Text(
                            reason.trim(),
                            style: material.TextStyle(
                                color: context.colors.textMuted, fontSize: 10),
                          )),
                    ],
                  ),
                ),
                if (entry.isReturned)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      material.Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.colors.successGreen.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('RELEASED',
                            style: material.TextStyle(
                                color: context.colors.successGreen,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                      if (entry.returnedByName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'By: ${entry.returnedByName}',
                            style: material.TextStyle(
                                color: context.colors.textMuted, fontSize: 9),
                          ),
                        ),
                    ],
                  )
                else
                  material.InkWell(
                    onTap: () {
                      final item = package.items
                          .where((i) => i.id == entry.packageItemId)
                          .firstOrNull;
                      final isConfiscated = item?.status == 'confiscated' ||
                          entry.isPackageConfiscated;
                      if (isConfiscated) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Confiscated items cannot be released'),
                                backgroundColor: Colors.red));
                        return;
                      }
                      onRelease();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: material.Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (package.items
                                        .where(
                                            (i) => i.id == entry.packageItemId)
                                        .firstOrNull
                                        ?.status ==
                                    'confiscated' ||
                                entry.isPackageConfiscated)
                            ? Colors.grey.withOpacity(0.15)
                            : context.colors.successGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: (package.items
                                            .where((i) =>
                                                i.id == entry.packageItemId)
                                            .firstOrNull
                                            ?.status ==
                                        'confiscated' ||
                                    entry.isPackageConfiscated)
                                ? Colors.grey.withOpacity(0.4)
                                : context.colors.successGreen.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_fill_rounded,
                              size: 12,
                              color: (package.items
                                              .where((i) =>
                                                  i.id == entry.packageItemId)
                                              .firstOrNull
                                              ?.status ==
                                          'confiscated' ||
                                      entry.isPackageConfiscated)
                                  ? Colors.grey
                                  : context.colors.successGreen),
                          const Gap(6),
                          Text('RELEASE',
                              style: material.TextStyle(
                                  color: (package.items
                                                  .where((i) =>
                                                      i.id ==
                                                      entry.packageItemId)
                                                  .firstOrNull
                                                  ?.status ==
                                              'confiscated' ||
                                          entry.isPackageConfiscated)
                                      ? Colors.grey
                                      : context.colors.successGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const Gap(6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'In: ${DateFormat('dd MMM yyyy').format(entry.admittedAt)}${entry.returnedAt != null ? "  Out: ${DateFormat('dd MMM yyyy').format(entry.returnedAt!)}" : ""}',
                  style: material.TextStyle(
                      color: context.colors.textMuted, fontSize: 10),
                ),
                if (entry.admittedByName != null)
                  Text(
                    'Entry by: ${entry.admittedByName}',
                    style: material.TextStyle(
                        color: context.colors.textMuted, fontSize: 10),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemEntrySection extends StatelessWidget {
  final String officerDisplay;
  final String? badgeNumber;
  final int delay;
  final String? customTitle;
  final IconData? customIcon;

  const _SystemEntrySection({
    required this.officerDisplay,
    this.badgeNumber,
    required this.delay,
    this.customTitle,
    this.customIcon,
  });

  /// True when there is no officer to name, rather than one we failed to load.
  bool get _unrecorded => officerDisplay == _kNoEntrantRecorded;

  /// The officer's initials, for the avatar.
  ///
  /// ⚠️ Two letters at most, and only from words that start with one.
  /// A name like "D. M. Perera" would otherwise read "DM" from the
  /// initials somebody already wrote out.
  String get _initials {
    if (_unrecorded) return '?';
    final words = officerDisplay
        .split(RegExp(r'[\s.]+'))
        .where((w) => w.isNotEmpty && RegExp(r'^[A-Za-z]').hasMatch(w))
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return (words.first[0] + words.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.colors.primaryGold;
    // ⚠️ An unrecorded entry is drawn in MUTED grey, not gold. Gold and
    // bold announces a person; using it for "Not recorded" made a blank
    // field look like a finding.
    final tint = _unrecorded ? context.colors.textMuted : gold;

    return material.Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? context.colors.surfaceDark.withOpacity(0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠️ The SAME header bar every other section has -- the tinted
          // strip, the gold icon, the spaced capitals. This panel used a
          // gradient card of its own, so the last thing on every popup
          // looked like it came from a different screen.
          material.Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withOpacity(0.03),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
              border:
                  Border(bottom: BorderSide(color: context.colors.borderColor)),
            ),
            child: Row(
              children: [
                Icon(customIcon ?? Icons.verified_user_rounded,
                    size: 18, color: gold),
                const Gap(10),
                Text(
                  (customTitle ?? 'System Entry By').toUpperCase(),
                  style: material.TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // ⚠️ An AVATAR, not another icon. The header already
                // carries one, and repeating it says nothing; initials say
                // a person signed this.
                material.Container(
                  width: 44,
                  height: 44,
                  alignment: material.Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: tint.withOpacity(0.35)),
                  ),
                  child: Text(
                    _initials,
                    style: material.TextStyle(
                      color: tint,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const Gap(14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        officerDisplay,
                        style: material.TextStyle(
                          color: _unrecorded
                              ? context.colors.textMuted
                              : context.colors.textPrimary,
                          fontSize: 14.5,
                          fontWeight:
                              _unrecorded ? FontWeight.w500 : FontWeight.w700,
                          fontStyle:
                              _unrecorded ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                      // Says WHY it is blank, so nobody goes looking for a
                      // broken lookup.
                      if (_unrecorded) ...[
                        const Gap(3),
                        Text(
                          'This entry predates officer tracking \u2014 no '
                          'officer was saved against it.',
                          style: material.TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 11,
                              height: 1.3),
                        ),
                      ] else if (badgeNumber != null &&
                          badgeNumber!.isNotEmpty) ...[
                        const Gap(3),
                        Text(
                          'Salary No: ${badgeNumber!}',
                          style: material.TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: delay)).slideY(begin: 0.1);
  }
}

class _SaleFinancialsSection extends ConsumerStatefulWidget {
  final PackageModel package;
  final String? packageItemId;

  /// Receipt number of THIS sale — pins the exact TSI row when one item was
  /// sold across several partial tenders (same package_item_id, distinct prices).
  final String? receipt;

  /// Officer who recorded the sale (shown here, not in the Sold table).
  final String? soldBy;

  /// Quantity this sale covers, as the table shows it. Without it the
  /// valuation row falls back to 1, because the sale query does not join
  /// package_items so `forfeited.packageDetails` is null here.
  final int? valuationQty;
  const _SaleFinancialsSection(
      {required this.package,
      this.packageItemId,
      this.receipt,
      this.soldBy,
      this.valuationQty});
  @override
  ConsumerState<_SaleFinancialsSection> createState() =>
      _SaleFinancialsSectionState();
}

class _SaleFinancialsSectionState
    extends ConsumerState<_SaleFinancialsSection> {
  String get _saleItemKey =>
      '${widget.package.id}|${widget.packageItemId ?? ''}|${widget.receipt ?? ''}';

  // Marking delivery lives in the Sold Goods table now -- see
  // _DeliveryStatusCell. This section only reports the status.

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(saleItemForPackageItemProvider(_saleItemKey));
    return async.when(
      loading: () => const material.Center(
        child: material.Padding(
            padding: EdgeInsets.all(16),
            child: material.CircularProgressIndicator()),
      ),
      error: (_, __) => const material.SizedBox.shrink(),
      data: (saleItem) {
        if (saleItem == null) return const material.SizedBox.shrink();

        double taxSum = 0;
        for (final t in saleItem.appliedTaxes) {
          taxSum += parseDbNum(t['amount']) ?? 0;
        }

        final delivered = saleItem.isDelivered;

        return _DetailSection(
          title: 'Sale & Financial Information',
          icon: Icons.sell_rounded,
          delay: 650,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surfaceDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.colors.borderColor),
            ),
            child: Column(
              children: [
                // ⚠️ FIRST, and as a banner. It was a row reading
                // "Pending" in RED, sitting between a receipt number and
                // a tax figure -- the one thing a reader opens this
                // popup to check was the least visible thing on it, and
                // red is the colour of something wrong. Goods waiting to
                // be collected are not wrong; they are the yard's
                // outstanding work, which is what amber means here and
                // on every delivery pill in the tables beside it.
                DeliveryStatusBanner(
                  delivered: delivered,
                  deliveredAt: saleItem.deliveredAt,
                  waitingFor: 'collection by the buyer',
                  doneLabel: 'Delivered',
                  receiptNo: saleItem.handoverReceiptNo,
                  charge: saleItem.handoverCharge,
                ),
                if (saleItem.receiptNumber?.trim().isNotEmpty == true)
                  _DetailItem(
                    icon: Icons.receipt_long_rounded,
                    label: 'Receipt No',
                    value: saleItem.receiptNumber!.trim(),
                  ),
                if (widget.soldBy?.trim().isNotEmpty == true)
                  _DetailItem(
                    icon: Icons.person_rounded,
                    label: 'Sold By',
                    value: widget.soldBy!.trim(),
                  ),
                // Valuation Directorate's valuation, for comparison with the
                // actual sold price below.
                if (() {
                  final fp = saleItem.forfeited;
                  return fp?.valuationCost != null;
                }())
                  _ValuationDetailRow(
                      fp: saleItem.forfeited!,
                      // The table's Qty column is the source of truth:
                      // the sale query does not join package_items, so
                      // fp.packageDetails is null here and the internal
                      // fallback would land on 1.
                      soldQty: widget.valuationQty),
                _DetailItem(
                  icon: Icons.payments_rounded,
                  label: 'Sold Price (Rs)',
                  value: saleItem.soldPrice.toStringAsFixed(2),
                ),
                // ⚠️ The taxes STORED on this item -- the ones that were
                // enabled at the moment it sold -- never today's tax table.
                // Enabling a tax later must not change what a past sale was
                // charged, and disabling one must not make the charge vanish.
                // That is why each sold item carries its own list.
                if (saleItem.appliedTaxes.isNotEmpty) ...[
                  ...saleItem.appliedTaxes.map((t) => _DetailItem(
                        icon: Icons.receipt_rounded,
                        label: '${t['name']} (${t['percentage']}%)',
                        value: ((t['amount'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(2),
                      )),
                  _DetailItem(
                    icon: Icons.functions_rounded,
                    label: 'Total Tax',
                    value: taxSum.toStringAsFixed(2),
                  ),
                ],
                _DetailItem(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Total Sale Value (Inc. Taxes)',
                  value: (saleItem.soldPrice + taxSum).toStringAsFixed(2),
                  valueColor: context.colors.primaryGold,
                ),
                // ⚠️ No Mark Delivered button here. Confirming delivery is
                // the yard's ONE routine action on a sold row, and doing it
                // from a popup meant open, scroll, press, watch it close. It
                // now lives in the Sold Goods table beside the status it
                // changes; this popup only REPORTS that status.
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoteDisplay extends StatelessWidget {
  final String text;
  final bool isWarning;
  final IconData? icon;

  const _NoteDisplay({required this.text, this.isWarning = false, this.icon});

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning
            ? context.colors.primaryGold.withOpacity(0.05)
            : context.colors.textPrimary.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isWarning
                  ? context.colors.primaryGold
                  : context.colors.borderColor)
              .withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            material.Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: (isWarning
                        ? context.colors.primaryGold
                        : context.colors.textMuted)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 14,
                color: isWarning
                    ? context.colors.primaryGold
                    : context.colors.textMuted,
              ),
            ),
            const Gap(12),
          ],
          Expanded(
            child: Text(
              text,
              style: material.TextStyle(
                color: context.colors.textPrimary,
                fontSize: 12,
                height: 1.5,
                fontWeight: isWarning ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  /// Why the section is empty, when "nothing here" is the CORRECT answer
  /// rather than missing data. Without it an intentional blank reads as a
  /// failure to load -- which is exactly how the perishables' (correctly)
  /// empty warehouse summary read.
  final String? reason;

  final IconData icon;

  const _EmptyState({
    required this.message,
    this.reason,
    this.icon = Icons.inbox_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 32, color: context.colors.textMuted.withOpacity(0.4)),
            const Gap(2),
            Text(
              message,
              style: material.TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic),
            ),
            if (reason != null) ...[
              const Gap(6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  reason!,
                  textAlign: material.TextAlign.center,
                  style: material.TextStyle(
                      color: context.colors.textMuted.withOpacity(0.8),
                      fontSize: 11,
                      height: 1.45),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact item-detail card shown when an abandoned / "Other" item has no
/// warehouse entry (registered on the SR form but never admitted). Uses the
/// item's registration data — no charges/receipts apply.
class _NoEntryItemCard extends StatelessWidget {
  final PackageItem item;
  const _NoEntryItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        children: [
          _DetailItem(
            icon: Icons.label_important_rounded,
            label: 'Goods Name',
            value: item.itemName,
          ),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  icon: Icons.view_in_ar_rounded,
                  label: 'Total Packages',
                  value: '${item.effectiveQuantity}',
                ),
              ),
              const Gap(12),
              Expanded(
                child: _DetailItem(
                  icon: Icons.straighten_rounded,
                  label: 'Unit',
                  value: item.unitOfMeasure == 'Other'
                      ? (item.unitOther ?? 'Other')
                      : (item.packagingLabel != null
                          ? '${item.effectiveQuantity} ${item.effectiveUnit} (in ${item.packagingLabel})'
                          : item.effectiveUnit),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _DetailItem(
                  icon: Icons.tag_rounded,
                  label: 'HS Code',
                  value: (item.hsCode?.isNotEmpty == true) ? item.hsCode! : '—',
                ),
              ),
              const Gap(12),
              Expanded(
                child: _DetailItem(
                  icon: Icons.payments_rounded,
                  // The TOTAL, with the unit price beneath it — the same shape
                  // the Valuation column uses. This showed the bare unitValue
                  // under a label reading just "Value", while every table showed
                  // unitValue x quantity under that same word.
                  label: 'Value (total)',
                  value:
                      'LKR ${NumberFormat('#,##0.00').format(item.unitValue * item.quantity)}'
                      '  ·  @ ${NumberFormat('#,##0.00').format(item.unitValue)} × ${item.quantity}',
                ),
              ),
            ],
          ),
          if (item.goodsDescription?.isNotEmpty == true)
            _DetailItem(
              icon: Icons.description_rounded,
              label: 'Goods Description',
              value: item.goodsDescription!,
            ),
          if (item.reasons?.isNotEmpty == true)
            _DetailItem(
              icon: Icons.warning_amber_rounded,
              label: 'Post Status Activity',
              value: item.reasons!,
            ),
        ],
      ),
    );
  }
}

class _DetailColumn extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailColumn(this.label, this.value, {required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: context.colors.textMuted),
            const Gap(6),
            Text(label,
                style:
                    TextStyle(color: context.colors.textMuted, fontSize: 12)),
          ],
        ),
        Text(value,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14)),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String label;
  final String value;
  final BuildContext ctx;

  const _HistoryRow(this.label, this.value, this.ctx);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: TextStyle(color: ctx.colors.textMuted, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: ctx.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

Widget _InfoChip(
    String label, String value, IconData icon, BuildContext context) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: context.colors.surfaceDark,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: context.colors.borderColor),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: context.colors.textMuted),
        const Gap(6),
        Text('$label: ',
            style: TextStyle(color: context.colors.textMuted, fontSize: 12)),
        Text(value,
            style: TextStyle(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
      ],
    ),
  );
}

// ============ PACKAGE UPDATE DIALOG ============
class PackageUpdateDialog extends ConsumerStatefulWidget {
  final PackageModel package;
  final PackageItem? highlightedItem;
  final WarehouseEntryModel? highlightEntry; // Added this
  final Map<DateTime, double> storageRate;

  const PackageUpdateDialog({
    super.key,
    required this.package,
    this.highlightedItem,
    this.highlightEntry, // Added this
    required this.storageRate,
  });

  @override
  ConsumerState<PackageUpdateDialog> createState() =>
      _PackageUpdateDialogState();
}

class _ItemRow {
  String id = '';
  final nameCtrl = TextEditingController();
  final goodsDescriptionCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final unitOfMeasureCtrl = TextEditingController(text: 'Pieces');
  final unitOtherCtrl = TextEditingController();
  // Cartons only: inner unit type + inner quantity per carton.
  final innerUnitCtrl = TextEditingController(text: 'Pieces');
  final innerQtyCtrl = TextEditingController(text: '1');
  final valueCtrl = TextEditingController(text: '0');
  final hsCodeCtrl = TextEditingController();
  final categoryCtrl = TextEditingController();
  String status = 'Detain';
  final otherStatusCtrl = TextEditingController();
  final List<String?> selectedReasons = [null];
}

class _PackageUpdateDialogState extends ConsumerState<PackageUpdateDialog>
    with SingleTickerProviderStateMixin {
  late final _formKey = GlobalKey<FormState>();
  late final AnimationController _animCtrl;
  late final Animation<double> _anim;
  late final TextEditingController _consigneeCtrl;
  late final TextEditingController _consigneeNicCtrl;
  late final TextEditingController _consigneePhoneCtrl;
  late final TextEditingController _declarantCtrl;
  late final TextEditingController _cusdecCtrl;
  late final TextEditingController _cusdecDateCtrl;
  late final TextEditingController _entryDateCtrl;
  late final TextEditingController _caseNumberCtrl;
  late final TextEditingController _containerNumberCtrl;

  /// Package-level deposit against the cost of destruction.
  late final TextEditingController _destroyingDepositCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _reasonCtrl;
  late final TextEditingController _valueCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _originCtrl;

  late String _statusValue;
  late List<_ItemRow> _items;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _anim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _animCtrl.forward();
    _consigneeCtrl = TextEditingController(text: widget.package.consigneeName);
    _consigneeNicCtrl =
        TextEditingController(text: widget.package.consigneeNic ?? '');
    _consigneePhoneCtrl =
        TextEditingController(text: widget.package.consigneePhone ?? '');
    _declarantCtrl =
        TextEditingController(text: widget.package.declarantName ?? '');
    _cusdecCtrl = TextEditingController(text: widget.package.cusdecNo ?? '');
    _cusdecDateCtrl =
        TextEditingController(text: widget.package.cusdecDate ?? '');
    _entryDateCtrl = TextEditingController(
        text: widget.package.entryDate != null
            ? '${widget.package.entryDate!.year}-${widget.package.entryDate!.month.toString().padLeft(2, '0')}-${widget.package.entryDate!.day.toString().padLeft(2, '0')}'
            : '');
    _caseNumberCtrl =
        TextEditingController(text: widget.package.caseNumber ?? '');
    _containerNumberCtrl =
        TextEditingController(text: widget.package.containerNumber ?? '');
    _destroyingDepositCtrl = TextEditingController(
        text: widget.package.destroyingDeposit?.toString() ?? '');
    _descCtrl = TextEditingController(text: widget.package.description ?? '');
    _notesCtrl = TextEditingController(text: widget.package.notes ?? '');
    _reasonCtrl = TextEditingController(text: widget.package.reason ?? '');
    _valueCtrl = TextEditingController(
        text: widget.package.declaredValue?.toString() ?? '');
    _weightCtrl =
        TextEditingController(text: widget.package.weightKg?.toString() ?? '');
    _originCtrl =
        TextEditingController(text: widget.package.originCountry ?? '');

    _statusValue = (widget.package.status == 'detained' ||
            widget.package.status == 'forfeited')
        ? 'held'
        : widget.package.status;

    // Initialize items
    _items = [];
    if (widget.highlightedItem != null) {
      // Show only the specific highlighted item if provided
      final row = _ItemRow();
      row.id = widget.highlightedItem!.id;
      row.nameCtrl.text = widget.highlightedItem!.itemName;
      row.goodsDescriptionCtrl.text =
          widget.highlightedItem!.goodsDescription ?? '';
      final hi = widget.highlightedItem!;
      if (hi.innerUnit == 'Cartons' && hi.innerQuantity != null) {
        row.unitOfMeasureCtrl.text = 'Cartons';
        row.qtyCtrl.text = (hi.innerQuantity ?? 1).toString();
        row.innerUnitCtrl.text = hi.unitOfMeasure;
        // ⚠️ Back OUT of the total. `quantity` holds cartons x per-carton,
        // and this box asks for ONE carton's contents -- showing the total
        // here made "5 Cartons of 5 Pieces each" out of 5 pieces in 5
        // cartons, and the next save stored that reading as fact.
        final hiCartons = hi.innerQuantity ?? 1;
        row.innerQtyCtrl.text =
            (hiCartons > 0 ? (hi.quantity ~/ hiCartons) : hi.quantity)
                .toString();
      } else {
        row.qtyCtrl.text = hi.quantity.toString();
        row.unitOfMeasureCtrl.text = hi.unitOfMeasure;
        if (![
          'Pieces',
          'Cartons',
          'Boxes',
          'Bags',
          'Pallets',
          'Rolls',
          'Packages',
          'No of',
          'Bottles',
          'KG',
          'Meters',
          'Other'
        ].contains(row.unitOfMeasureCtrl.text)) {
          row.unitOtherCtrl.text = row.unitOfMeasureCtrl.text;
          row.unitOfMeasureCtrl.text = 'Other';
        }
      }

      row.valueCtrl.text = widget.highlightedItem!.unitValue.toString();
      row.hsCodeCtrl.text = widget.highlightedItem!.hsCode ?? '';
      row.categoryCtrl.text = widget.highlightedItem!.category ?? '';
      _applyStatusToRow(row, widget.highlightedItem!.status);

      // If the entry is returned, override item status to 'returned'
      if (widget.highlightEntry?.isReturned == true) {
        row.status = 'Other';
        row.otherStatusCtrl.text = 'returned';
      }

      if (widget.highlightedItem!.reasons != null &&
          widget.highlightedItem!.reasons!.isNotEmpty) {
        final rList = widget.highlightedItem!.reasons!
            .split(', ')
            .map((s) => s.trim())
            .toList();
        row.selectedReasons.clear();
        for (int i = 0; i < rList.length && i < 4; i++) {
          row.selectedReasons.add(rList[i]);
        }
        if (row.selectedReasons.isEmpty) row.selectedReasons.add(null);
      }
      _items.add(row);
    } else if (widget.package.items.isNotEmpty) {
      for (final item in widget.package.items) {
        final row = _ItemRow();
        row.id = item.id;
        row.nameCtrl.text = item.itemName;
        row.goodsDescriptionCtrl.text = item.goodsDescription ?? '';
        // Reconstruct the inverted Cartons storage: a packaged item keeps
        // 'Cartons' + carton count in innerUnit/innerQuantity and the inner
        // contents in quantity/unitOfMeasure.
        if (item.innerUnit == 'Cartons' && item.innerQuantity != null) {
          row.unitOfMeasureCtrl.text = 'Cartons';
          row.qtyCtrl.text = (item.innerQuantity ?? 1).toString();
          row.innerUnitCtrl.text = item.unitOfMeasure;
          // ⚠️ Back OUT of the total -- see the highlighted-item branch above.
          final cartons = item.innerQuantity ?? 1;
          row.innerQtyCtrl.text =
              (cartons > 0 ? (item.quantity ~/ cartons) : item.quantity)
                  .toString();
        } else {
          row.qtyCtrl.text = item.quantity.toString();
          row.unitOfMeasureCtrl.text = item.unitOfMeasure;
          if (![
            'Pieces',
            'Cartons',
            'Boxes',
            'Bags',
            'Pallets',
            'Rolls',
            'Packages',
            'No of',
            'Bottles',
            'KG',
            'Meters',
            'Other'
          ].contains(row.unitOfMeasureCtrl.text)) {
            row.unitOtherCtrl.text = row.unitOfMeasureCtrl.text;
            row.unitOfMeasureCtrl.text = 'Other';
          }
        }

        row.valueCtrl.text = item.unitValue.toString();
        row.hsCodeCtrl.text = item.hsCode ?? '';
        row.categoryCtrl.text = item.category ?? '';
        _applyStatusToRow(row, item.status);
        if (item.reasons != null && item.reasons!.isNotEmpty) {
          final rList = item.reasons!.split(', ').map((s) => s.trim()).toList();
          row.selectedReasons.clear();
          for (int i = 0; i < rList.length && i < 4; i++) {
            row.selectedReasons.add(rList[i]);
          }
          if (row.selectedReasons.isEmpty) row.selectedReasons.add(null);
        }
        _items.add(row);
      }
    } else {
      _items.add(_ItemRow());
    }
  }

  @override
  void dispose() {
    _consigneeCtrl.dispose();
    _consigneeNicCtrl.dispose();
    _consigneePhoneCtrl.dispose();
    _declarantCtrl.dispose();
    _cusdecCtrl.dispose();
    _cusdecDateCtrl.dispose();
    _entryDateCtrl.dispose();
    _caseNumberCtrl.dispose();
    _containerNumberCtrl.dispose();
    _destroyingDepositCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    _valueCtrl.dispose();
    _weightCtrl.dispose();
    _originCtrl.dispose();
    for (final item in _items) {
      item.nameCtrl.dispose();
      item.goodsDescriptionCtrl.dispose();
      item.qtyCtrl.dispose();
      item.unitOfMeasureCtrl.dispose();
      item.unitOtherCtrl.dispose();
      item.valueCtrl.dispose();
      item.hsCodeCtrl.dispose();
      item.categoryCtrl.dispose();
      item.otherStatusCtrl.dispose();
    }
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate(TextEditingController controller) async {
    // Use the same custom picker as the SR form so the calendar looks identical
    // (same look/size) and dates read as YYYY-MM-DD — not the Material picker's
    // MM/DD/YYYY manual-entry box.
    final existing = DateTime.tryParse(controller.text.trim());
    final DateTime? picked = await showAppDialog<DateTime>(
      context: context,
      builder: (_) => OneTapDatePicker(
        initialDate: existing ?? DateTime.now(),
        lastDate: DateTime.now(),
      ),
    );
    if (picked != null) {
      setState(() {
        controller.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _applyStatusToRow(_ItemRow row, String status) {
    const statuses = ['Detain', 'Forfeit', 'Abandoned', 'Other'];
    if (statuses.contains(status)) {
      row.status = status;
      row.otherStatusCtrl.clear();
    } else {
      row.status = 'Other';
      row.otherStatusCtrl.text = status.isEmpty ? 'Detain' : status;
    }
  }

  String _rowStatus(_ItemRow row) {
    return row.status == 'Other' ? row.otherStatusCtrl.text.trim() : row.status;
  }

  Future<void> _updatePackage() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);
    try {
      final List<PackageItem> itemsToUpsert;

      if (widget.highlightedItem != null) {
        // If we were editing a specific item, update just that one in the list
        itemsToUpsert = widget.package.items.map<PackageItem>((item) {
          if (item.id == widget.highlightedItem!.id) {
            final row = _items.first;
            return item.copyWith(
              itemName: row.nameCtrl.text,
              goodsDescription: row.goodsDescriptionCtrl.text.trim().isEmpty
                  ? null
                  : row.goodsDescriptionCtrl.text.trim(),
              // Cartons stored inverted: quantity/unit hold the inner contents;
              // packaging (Cartons + count) goes to innerUnit/innerQuantity.
              // ⚠️ CARTONS x PER-CARTON. `innerQtyCtrl` is one carton's
              // contents, so storing it raw recorded 5 cartons of 5 pieces
              // as 5 pieces -- and every charge, capacity and Qty column
              // downstream reads this number.
              quantity: row.unitOfMeasureCtrl.text == 'Cartons'
                  ? ((int.tryParse(row.qtyCtrl.text) ?? 1) *
                      (int.tryParse(row.innerQtyCtrl.text) ?? 1))
                  : (int.tryParse(row.qtyCtrl.text) ?? 1),
              unitValue: double.tryParse(row.valueCtrl.text) ?? 0,
              hsCode: row.hsCodeCtrl.text.trim().isEmpty
                  ? null
                  : row.hsCodeCtrl.text.trim(),
              category: row.categoryCtrl.text,
              unitOfMeasure: row.unitOfMeasureCtrl.text == 'Cartons'
                  ? row.innerUnitCtrl.text
                  : (row.unitOfMeasureCtrl.text == 'Other'
                      ? row.unitOtherCtrl.text
                      : row.unitOfMeasureCtrl.text),
              innerUnit:
                  row.unitOfMeasureCtrl.text == 'Cartons' ? 'Cartons' : null,
              innerQuantity: row.unitOfMeasureCtrl.text == 'Cartons'
                  ? (int.tryParse(row.qtyCtrl.text) ?? 1)
                  : null,
              status: _rowStatus(row),
              reasons:
                  row.selectedReasons.where((res) => res != null).join(', '),
            );
          }
          return item;
        }).toList();
      } else {
        // Otherwise use the bulk items list from the form
        itemsToUpsert = _items
            .where((r) => r.nameCtrl.text.isNotEmpty)
            .map((r) => PackageItem(
                  id: r.id,
                  packageId: '',
                  itemName: r.nameCtrl.text,
                  goodsDescription: r.goodsDescriptionCtrl.text.trim().isEmpty
                      ? null
                      : r.goodsDescriptionCtrl.text.trim(),
                  // ⚠️ CARTONS x PER-CARTON -- see the sibling save above.
                  quantity: r.unitOfMeasureCtrl.text == 'Cartons'
                      ? ((int.tryParse(r.qtyCtrl.text) ?? 1) *
                          (int.tryParse(r.innerQtyCtrl.text) ?? 1))
                      : (int.tryParse(r.qtyCtrl.text) ?? 1),
                  unitValue: double.tryParse(r.valueCtrl.text) ?? 0,
                  hsCode: r.hsCodeCtrl.text.trim().isEmpty
                      ? null
                      : r.hsCodeCtrl.text.trim(),
                  category: r.categoryCtrl.text,
                  unitOfMeasure: r.unitOfMeasureCtrl.text == 'Cartons'
                      ? r.innerUnitCtrl.text
                      : (r.unitOfMeasureCtrl.text == 'Other'
                          ? r.unitOtherCtrl.text
                          : r.unitOfMeasureCtrl.text),
                  innerUnit:
                      r.unitOfMeasureCtrl.text == 'Cartons' ? 'Cartons' : null,
                  innerQuantity: r.unitOfMeasureCtrl.text == 'Cartons'
                      ? (int.tryParse(r.qtyCtrl.text) ?? 1)
                      : null,
                  status: _rowStatus(r),
                  reasons:
                      r.selectedReasons.where((res) => res != null).join(', '),
                ))
            .toList();
      }

      final updatedPackage = widget.package.copyWith(
        consigneeName: _consigneeCtrl.text.trim(),
        consigneeNic: _consigneeNicCtrl.text.trim(),
        consigneePhone: _consigneePhoneCtrl.text.trim(),
        declarantName: _declarantCtrl.text.trim(),
        cusdecNo: _cusdecCtrl.text.trim(),
        cusdecDate: _cusdecDateCtrl.text.trim(),
        caseNumber: _caseNumberCtrl.text.trim().isEmpty
            ? null
            : _caseNumberCtrl.text.trim(),
        containerNumber: _containerNumberCtrl.text.trim().isEmpty
            ? null
            : _containerNumberCtrl.text.trim(),
        destroyingDeposit: double.tryParse(_destroyingDepositCtrl.text.trim()),
        entryDate: _entryDateCtrl.text.isNotEmpty
            ? DateTime.tryParse(_entryDateCtrl.text)
            : null,
        description: _descCtrl.text.trim(),
        reason: _reasonCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        declaredValue: double.tryParse(_valueCtrl.text.trim()) ?? 0,
        weightKg: double.tryParse(_weightCtrl.text.trim()) ?? 0,
        originCountry: _originCtrl.text.trim(),
        status: _statusValue,
      );

      await ref
          .read(packageServiceProvider)
          .upsertPackage(updatedPackage, itemsToUpsert);

      // Trigger refreshes for all related dashboard and list providers
      ref.read(packagesRefreshTriggerProvider.notifier).trigger();
      ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
      ref.invalidate(livePackagesProvider);
      ref.invalidate(forfeitedPackagesProvider);
      ref.invalidate(forfeitCountsProvider);
      ref.invalidate(dashboardStatsProvider); // Dashboard stats refresh
      ref.invalidate(recentPackagesProvider); // Recent inspections refresh
      ref.invalidate(allWarehouseEntriesProvider);
      ref.invalidate(categoryZoneSummaryProvider); // Inventory table refresh

      if (mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Package "${widget.package.srNumber}" updated successfully!'),
            backgroundColor: context.colors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e);
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final value = _anim.value;
          return Transform.scale(
            scale: value,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: material.Container(
          width: 1000,
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9),
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              material.Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [context.colors.surfaceDark, context.colors.cardDark]
                        : [
                            context.colors.customsBlue,
                            context.colors.customsBlueDark
                          ],
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(23)),
                ),
                child: Row(
                  children: [
                    material.Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.edit_document,
                          color: context.colors.primaryGold, size: 24),
                    ),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'UPDATE SR REGISTER ENTRY',
                            style: material.TextStyle(
                              color: context.colors.primaryGold,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.package.srNumber,
                            style: material.TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    DialogCloseButton(prominent: false),
                  ],
                ),
              ),
              // Form Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // SR Information Section
                        _UpdateSectionCard(
                          title: 'SR Register Information',
                          icon: Icons.inventory_2_rounded,
                          children: [
                            TextFormField(
                              enabled: false,
                              initialValue: widget.package.srNumber,
                              decoration: const InputDecoration(
                                  labelText: 'SR Number *'),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _cusdecCtrl,
                                    decoration: const InputDecoration(
                                        labelText: 'Cusdec No *'),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _entryDateCtrl,
                                    inputFormatters: [
                                      MaskTextInputFormatter(
                                        mask: '####-##-##',
                                        filter: {"#": RegExp(r'[0-9]')},
                                        type: MaskAutoCompletionType.lazy,
                                      )
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Entry Date *',
                                      hintText: 'YYYY-MM-DD',
                                      suffixIcon: IconButton(
                                        icon: Icon(Icons.calendar_month,
                                            color: context.colors.primaryGold),
                                        onPressed: () =>
                                            _selectDate(_entryDateCtrl),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty)
                                        return 'Required';
                                      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                          .hasMatch(v)) return 'Use YYYY-MM-DD';
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _caseNumberCtrl,
                                    decoration: const InputDecoration(
                                        labelText: 'Case Number'),
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _cusdecDateCtrl,
                                    inputFormatters: [
                                      MaskTextInputFormatter(
                                        mask: '####-##-##',
                                        filter: {"#": RegExp(r'[0-9]')},
                                        type: MaskAutoCompletionType.lazy,
                                      )
                                    ],
                                    decoration: InputDecoration(
                                      labelText: 'Cusdec Date *',
                                      hintText: 'YYYY-MM-DD',
                                      suffixIcon: IconButton(
                                        icon: Icon(Icons.calendar_month,
                                            color: context.colors.primaryGold),
                                        onPressed: () =>
                                            _selectDate(_cusdecDateCtrl),
                                      ),
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty)
                                        return 'Required';
                                      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                          .hasMatch(v)) return 'Use YYYY-MM-DD';
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            TextFormField(
                              controller: _containerNumberCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Container Number'),
                              textCapitalization: TextCapitalization.characters,
                            ),
                            TextFormField(
                              controller: _destroyingDepositCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Destroying Deposit (LKR)'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]')),
                              ],
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null; // optional
                                final d = double.tryParse(t);
                                if (d == null) return 'Enter a number';
                                if (d < 0) return 'Cannot be negative';
                                return null;
                              },
                            ),
                            TextFormField(
                              controller: _descCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Package Description'),
                              maxLines: 2,
                            ),
                          ],
                        ),
                        const Gap(16),
                        // Consignee Information Section
                        _UpdateSectionCard(
                          title: 'Consignee Information',
                          icon: Icons.person_rounded,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _consigneeCtrl,
                                    decoration: const InputDecoration(
                                        labelText: 'Consignee Name *'),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _declarantCtrl,
                                    decoration: const InputDecoration(
                                        labelText: 'Declarant Name *'),
                                    validator: (v) =>
                                        v!.isEmpty ? 'Required' : null,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller:
                                        _descCtrl, // Reusing controller for address if needed, or stick to required fields
                                    decoration: const InputDecoration(
                                        labelText: 'Declarant Address'),
                                  ),
                                ),
                                const Gap(12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _consigneePhoneCtrl,
                                    decoration: const InputDecoration(
                                        labelText:
                                            'Declarant Phone Number (10 digits) *'),
                                    keyboardType: TextInputType.phone,
                                    validator: (v) {
                                      if (v == null || v.isEmpty)
                                        return 'Required';
                                      if (!RegExp(r'^\d{10}$').hasMatch(v)) {
                                        return 'Must be exactly 10 digits';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ).animate().slideY(
                            begin: 0.1, duration: 400.ms, delay: 200.ms),
                        const Gap(16),
                        // Package Goods Section
                        _UpdateSectionCard(
                          title: widget.highlightedItem != null
                              ? 'ITEM DETAILS'
                              : 'Package Goods',
                          icon: Icons.shopping_bag_rounded,
                          children: [
                            Column(
                              children: List.generate(
                                  _items.length,
                                  (i) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: _UpdateItemRowWidget(
                                          row: _items[i],
                                          index: widget.highlightedItem != null
                                              ? -1
                                              : i +
                                                  1, // -1 means don't show index
                                          onRemove: widget.highlightedItem !=
                                                  null
                                              ? null
                                              : (_items.length > 1
                                                  ? () => setState(
                                                      () => _items.removeAt(i))
                                                  : null),
                                          onChanged: () => setState(() {}),
                                        ),
                                      )),
                            ),
                            // Add Item below the list (not in the header) so a
                            // new item needs no scroll back to the top. Hidden
                            // in single-item edit mode.
                            if (widget.highlightedItem == null) ...[
                              const Gap(4),
                              material.Align(
                                alignment: material.Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Add Goods'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: context.colors.primaryGold,
                                    side: BorderSide(
                                        color: context.colors.primaryGold
                                            .withOpacity(0.5)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 14),
                                  ),
                                  onPressed: () =>
                                      setState(() => _items.add(_ItemRow())),
                                ),
                              ),
                            ],
                          ],
                        ).animate().slideY(
                            begin: 0.1, duration: 400.ms, delay: 300.ms),
                        const Gap(16),
                        // Notes Section
                        _UpdateSectionCard(
                          title: 'OFFICER NOTES',
                          icon: Icons.note_rounded,
                          children: [
                            TextFormField(
                              controller: _notesCtrl,
                              decoration: const InputDecoration(
                                  hintText: 'Additional inspection notes...'),
                              maxLines: 3,
                            ),
                          ],
                        ).animate().slideY(
                            begin: 0.1, duration: 400.ms, delay: 500.ms),
                      ],
                    ),
                  ),
                ),
              ),
              // Footer Buttons
              material.Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade50,
                  border: Border(
                      top: BorderSide(color: context.colors.borderColor)),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(23)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const Gap(12),
                    ElevatedButton.icon(
                      icon: _isUpdating
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.colors.primaryNavy))
                          : const Icon(Icons.save_rounded),
                      label: Text(_isUpdating ? 'Updating...' : 'Update Entry'),
                      onPressed: _isUpdating ? null : _updatePackage,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper widget for update form sections
class _UpdateItemRowWidget extends ConsumerStatefulWidget {
  final _ItemRow row;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _UpdateItemRowWidget({
    required this.row,
    required this.index,
    this.onRemove,
    required this.onChanged,
  });

  @override
  ConsumerState<_UpdateItemRowWidget> createState() =>
      _UpdateItemRowWidgetState();
}

class _UpdateItemRowWidgetState extends ConsumerState<_UpdateItemRowWidget> {
  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(packageCategoriesProvider);
    return material.Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderColor),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              material.Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.colors.primaryGold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Goods ${widget.index == -1 ? "1" : widget.index}',
                    style: TextStyle(
                        color: context.colors.primaryGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ),
              const Spacer(),
              if (widget.onRemove != null)
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 20, color: context.colors.dangerRed),
                  onPressed: widget.onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Remove item',
                ),
            ],
          ),
          const Gap(12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: widget.row.nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Goods Name *', isDense: true),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              const Gap(10),
              Expanded(
                flex: 2,
                child: StyledDropdownFormField<String>(
                  label: 'Unit Type *',
                  menuWidth: 220,
                  columns: 2,
                  value: const [
                    'Pieces',
                    'Cartons',
                    'Boxes',
                    'Bags',
                    'Pallets',
                    'Rolls',
                    'Packages',
                    'No of',
                    'Bottles',
                    'KG',
                    'Meters',
                    'Other'
                  ].contains(widget.row.unitOfMeasureCtrl.text)
                      ? widget.row.unitOfMeasureCtrl.text
                      : 'Pieces',
                  options: const [
                    'Pieces',
                    'Cartons',
                    'Boxes',
                    'Bags',
                    'Pallets',
                    'Rolls',
                    'Packages',
                    'No of',
                    'Bottles',
                    'KG',
                    'Meters',
                    'Other'
                  ].map((u) => StyledDropdownOption(u, u)).toList(),
                  onChanged: (v) {
                    setState(() {
                      widget.row.unitOfMeasureCtrl.text = v ?? 'Pieces';
                    });
                    widget.onChanged();
                  },
                ),
              ),
              if (widget.row.unitOfMeasureCtrl.text == 'Other') ...[
                const Gap(8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: widget.row.unitOtherCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Name *', isDense: true),
                    validator: (v) =>
                        widget.row.unitOfMeasureCtrl.text == 'Other' &&
                                (v == null || v.trim().isEmpty)
                            ? 'Req'
                            : null,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ],
              const Gap(10),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: widget.row.qtyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Quantity *', isDense: true),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Req';
                    if (int.tryParse(v) == null || int.tryParse(v)! <= 0)
                      return 'Err';
                    return null;
                  },
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              if (widget.row.unitOfMeasureCtrl.text == 'Cartons') ...[
                const Gap(10),
                Expanded(
                  flex: 2,
                  child: StyledDropdownFormField<String>(
                    label: 'Inner Unit *',
                    menuWidth: 220,
                    columns: 2,
                    value: const [
                      'Pieces',
                      'Boxes',
                      'Bags',
                      'Pallets',
                      'Rolls',
                      'Packages',
                      'No of',
                      'Bottles',
                      'KG',
                      'Meters',
                    ].contains(widget.row.innerUnitCtrl.text)
                        ? widget.row.innerUnitCtrl.text
                        : 'Pieces',
                    options: const [
                      'Pieces',
                      'Boxes',
                      'Bags',
                      'Pallets',
                      'Rolls',
                      'Packages',
                      'No of',
                      'Bottles',
                      'KG',
                      'Meters',
                    ].map((u) => StyledDropdownOption(u, u)).toList(),
                    onChanged: (v) {
                      setState(
                          () => widget.row.innerUnitCtrl.text = v ?? 'Pieces');
                      widget.onChanged();
                    },
                  ),
                ),
                const Gap(8),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: widget.row.innerQtyCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Inner Qty *', isDense: true),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) =>
                        widget.row.unitOfMeasureCtrl.text == 'Cartons' &&
                                (v == null || v.trim().isEmpty)
                            ? 'Req'
                            : null,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ],
              const Gap(10),
              Expanded(
                flex: 2,
                child: StyledDropdownFormField<String>(
                  label: 'Status *',
                  menuWidth: 200,
                  value: const ['Detain', 'Forfeit', 'Abandoned', 'Other']
                          .contains(widget.row.status)
                      ? widget.row.status
                      : 'Other',
                  options: const ['Detain', 'Forfeit', 'Abandoned', 'Other']
                      .map((s) => StyledDropdownOption(s, s))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      final previous = widget.row.status;
                      widget.row.status = v!;
                      // Detain and the disposal statuses offer different
                      // activities — drop selections that no longer apply.
                      if (postStatusActivitiesFor(previous) !=
                          postStatusActivitiesFor(widget.row.status)) {
                        widget.row.selectedReasons
                          ..clear()
                          ..add(null);
                      }
                    });
                    widget.onChanged();
                  },
                ),
              ),
              if (widget.row.status == 'Other') ...[
                const Gap(10),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: widget.row.otherStatusCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Other Status *', isDense: true),
                    validator: (v) => widget.row.status == 'Other' &&
                            (v == null || v.trim().isEmpty)
                        ? 'Required'
                        : null,
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ],
              const Gap(10),
              Expanded(
                flex: 2,
                child: categories.when(
                  loading: () => const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (e, _) => IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 16, color: Colors.orange),
                    onPressed: () => ref.refresh(packageCategoriesProvider),
                    tooltip: 'Error loading categories',
                  ),
                  data: (list) {
                    final selectedCategory = list
                        .where((c) => c.name == widget.row.categoryCtrl.text)
                        .firstOrNull;
                    return StyledDropdownFormField<String>(
                      label: 'Category',
                      menuWidth: 240,
                      value: selectedCategory?.name,
                      options: list
                          .map((c) => StyledDropdownOption(c.name, c.name))
                          .toList(),
                      onChanged: (v) {
                        widget.row.categoryCtrl.text = v ?? '';
                        setState(() {});
                        widget.onChanged();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          const Gap(12),
          // ── HS Code & Value (per item) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: widget.row.hsCodeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'HS Code', isDense: true),
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              const Gap(12),
              Expanded(
                child: TextFormField(
                  controller: widget.row.valueCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Value', isDense: true, prefixText: 'LKR '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
            ],
          ),
          const Gap(16),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: context.colors.heldOrange),
              const Gap(8),
              Text('Post Status Activity',
                  style: material.TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: context.colors.textPrimary)),
              const Spacer(),
              if (widget.row.selectedReasons.length < 4)
                TextButton.icon(
                  onPressed: () {
                    setState(() => widget.row.selectedReasons.add(null));
                    widget.onChanged();
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Add Activity',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.primaryGold,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    backgroundColor:
                        context.colors.primaryGold.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
          const Gap(12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: List.generate(widget.row.selectedReasons.length, (rIdx) {
              // ⚠️ The same rule the SR form applies, not the same LIST.
              //
              // The two must agree, or editing an item would offer something
              // the form would not — or drop something it allowed. The rule
              // is: the status decides, except a perishable, whose status is
              // in neither group and which therefore gets everything.
              //
              // This row has no `nature` field, but it does not need one: a
              // perishable's STATUS is 'Perishable', which is what identifies
              // it here and is exactly why a filtered list would leave it
              // with nothing to choose.
              final activities = widget.row.status == 'Perishable'
                  ? kAllPostStatusActivities
                  : postStatusActivitiesFor(widget.row.status);
              return SizedBox(
                width: 380,
                child: Row(
                  children: [
                    Expanded(
                      child: StyledDropdownFormField<String>(
                        label: 'Activity ${rIdx + 1} *',
                        menuWidth: 300,
                        fillColor: context.colors.fieldFill,
                        value: activities
                                .contains(widget.row.selectedReasons[rIdx])
                            ? widget.row.selectedReasons[rIdx]
                            : null,
                        validator: (v) => v == null ? 'Required' : null,
                        options: activities
                            .map((a) => StyledDropdownOption(a, a))
                            .toList(),
                        onChanged: (v) {
                          setState(() => widget.row.selectedReasons[rIdx] = v);
                          widget.onChanged();
                        },
                      ),
                    ),
                    if (widget.row.selectedReasons.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 20, color: Colors.grey),
                          onPressed: () {
                            setState(() =>
                                widget.row.selectedReasons.removeAt(rIdx));
                            widget.onChanged();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Remove activity',
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const Gap(12),
          TextFormField(
            controller: widget.row.goodsDescriptionCtrl,
            decoration: const InputDecoration(
                labelText: 'Goods Description', isDense: true, helperText: ' '),
            maxLines: 2,
            onChanged: (_) => widget.onChanged(),
          ),
        ],
      ),
    );
  }
}

class _UpdateSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? headerTrailing;

  _UpdateSectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return material.Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? context.colors.surfaceDark.withOpacity(0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.colors.primaryGold),
              const Gap(10),
              Text(
                title.toUpperCase(),
                style: material.TextStyle(
                  color: context.colors.primaryGold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              if (headerTrailing != null) ...[
                const Spacer(),
                headerTrailing!,
              ],
            ],
          ),
          const Gap(16),
          Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const Gap(10),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Package Actions Dialog ────────────────────────────────────────────────────

class _PackageActionsDialog extends ConsumerStatefulWidget {
  final String packageId;
  final String itemId;
  final WarehouseEntryModel fallbackEntry;

  /// When the goods entered the yard. Every status carries a 30-day appeal
  /// window from this date, and NO action may be taken while it is open.
  final DateTime? entryDate;
  // Return true when the action was applied.
  final Future<bool> Function(WarehouseEntryModel held, List<int> slots)
      onRelease;
  final Future<bool> Function(
      WarehouseEntryModel held, String type, List<int> slots) onDispose;
  // Invoked after a successful action so the caller can close the parent
  // details dialog too (this dialog pops itself first). When null, only this
  // dialog closes.
  final VoidCallback? onCompleted;

  const _PackageActionsDialog({
    required this.packageId,
    required this.itemId,
    required this.fallbackEntry,
    required this.entryDate,
    required this.onRelease,
    required this.onDispose,
    this.onCompleted,
  });

  @override
  ConsumerState<_PackageActionsDialog> createState() =>
      _PackageActionsDialogState();
}

class _PackageActionsDialogState extends ConsumerState<_PackageActionsDialog> {
  bool _otherExpanded = false;
  bool _isLoading = false;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  void _showSuccess(BuildContext ctx, String message) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          const Gap(12),
          Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showError(BuildContext ctx, String message) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_rounded, color: Colors.white, size: 20),
          const Gap(12),
          Expanded(
              child: Text(message,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        backgroundColor: const Color(0xFFC62828),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _runAction(BuildContext ctx, Future<bool> Function() action,
      String successMsg) async {
    setState(() => _isLoading = true);
    try {
      final ok = await action();
      if (!mounted) return;
      if (ok) {
        _showSuccess(ctx, successMsg);
        // Auto-close on success: pop this actions dialog, then ask the caller
        // to close the parent details dialog so we land back on the list.
        setState(() => _isLoading = false);
        Navigator.of(context).pop();
        widget.onCompleted?.call();
        return;
      } else {
        _showError(ctx, 'Action could not be completed. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      _showError(ctx, 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _actions = [
    _ActionDef(
      key: 'Release',
      icon: Icons.assignment_return_rounded,
      label: 'Release Package',
      description: 'Package returned to the owner. Storage charge applies.',
      color: Color(0xFF43A047),
    ),
    _ActionDef(
      key: 'Forfeit',
      icon: Icons.gavel_rounded,
      label: 'Forfeit',
      description: 'Package forfeited to the state. No further charges.',
      color: Color(0xFFE53935),
    ),
    _ActionDef(
      key: 'Abandoned',
      icon: Icons.inbox_rounded,
      label: 'Abandoned',
      description: 'Package declared abandoned. No further charges.',
      color: Color(0xFF9E9E9E),
    ),
    _ActionDef(
      key: 'Re-export',
      icon: Icons.flight_takeoff_rounded,
      label: 'Re-export',
      description: 'Package sent back to country of origin. Charge applies.',
      color: Color(0xFF00ACC1),
    ),
    _ActionDef(
      key: 'Destroy',
      icon: Icons.delete_forever_rounded,
      label: 'Destroy',
      description: 'Package destroyed. No further charges.',
      color: Color(0xFFE64A19),
    ),
    _ActionDef(
      key: 'Other',
      icon: Icons.more_horiz_rounded,
      label: 'Other',
      description: 'Enter a custom disposition type.',
      color: Color(0xFF7E57C2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Live data: recompute held / processed slots whenever package data changes,
    // so the dialog stays correct after an action without closing.
    final pkg = ref.watch(packageDataProvider(widget.packageId)).valueOrNull;
    final entries = pkg?.warehouseEntries ?? [widget.fallbackEntry];
    final item = pkg?.items.where((i) => i.id == widget.itemId).firstOrNull;
    final total = item?.quantity ?? widget.fallbackEntry.itemCount;
    final processed = _computeProcessedSlots(widget.itemId, total, entries);
    final heldEntry = entries
            .where((e) => e.packageItemId == widget.itemId && !e.isReturned)
            .firstOrNull ??
        widget.fallbackEntry;
    final heldCount = (total - processed.length).clamp(0, total);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Role-based action permissions.
    // - Officers: no disposition actions enabled at all.
    // - Admins (DC/SDDC): every action is enabled, Destroy included — it goes
    //   through the same [FINAL:DESTROYED] warehouse-entry write as Release /
    //   Forfeit / Abandoned / Re-export / Other, just like the Final
    //   Disposition sheet below already allows. This dialog used to disable
    //   it unconditionally, so even an Appeal Directorate decision of DESTROY
    //   could never actually be carried out from here.
    final isOfficer = ref.watch(currentProfileProvider)?.role == 'officer';
    const _disabledForAll = <String>{};
    // The 30-day appeal window freezes EVERY action, whatever the status:
    // the owner may still appeal, so the goods cannot be released, forfeited,
    // abandoned, re-exported or destroyed until it closes.
    //
    // …UNLESS the Appeal Directorate has already ruled. A decision ends the
    // wait: there is nothing left to appeal, so the goods become actionable
    // immediately rather than sitting out the remaining days. A HOLD does the
    // opposite and keeps them frozen, because that appeal is still open.
    final outcome =
        ref.watch(itemAppealOutcomesProvider(widget.packageId)).valueOrNull;
    final itemOutcome =
        outcome?[widget.itemId] ?? outcome?[''] ?? const ItemAppealOutcome();
    final decidedEarly = itemOutcome.unblocksAction;

    final inAppealWindow =
        isWithinAppealWindow(widget.entryDate) && !decidedEarly;
    final appealDaysRemaining = appealDaysLeft(widget.entryDate);
    // An open appeal blocks action even after the window closes.
    final blockedByHold = itemOutcome.onHold;
    // The action key matching an Appeal Directorate decision code. SALE and
    // DESTROY map to nothing here: those two are carried out by sending a
    // disposal request to Central Disposal, never from this sheet.
    String? actionKeyForDecision(String code) {
      switch (code.trim().toUpperCase()) {
        case 'RELEASE':
          return 'Release';
        case 'RE-EXPORT':
          return 'Re-export';
        case 'OTHER':
          return 'Other';
        default:
          return null;
      }
    }

    bool isActionEnabled(String key) {
      if (isOfficer) return false;
      if (_disabledForAll.contains(key)) return false;
      if (inAppealWindow || blockedByHold) return false;
      // Once the directorate has ruled, ONLY the decided action is open — the
      // yard carries out what was decided rather than choosing afresh. This
      // mirrors the Final Disposition sheet's own gating.
      if (itemOutcome.isDecided) {
        return key == actionKeyForDecision(itemOutcome.decision!);
      }
      return true;
    }

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          children: [
            material.Container(
              width: 580,
              constraints: const BoxConstraints(maxHeight: 750),
              decoration: BoxDecoration(
                color: context.colors.scaffoldBg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 40,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Dialog Header ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [
                                context.colors.surfaceDark,
                                context.colors.cardDark
                              ]
                            : [
                                context.colors.customsBlue,
                                context.colors.customsBlueDark
                              ],
                      ),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.inventory_2_rounded,
                              color: context.colors.primaryGold, size: 24),
                        )
                            .animate()
                            .slideY(begin: 0.1, duration: 400.ms)
                            .fadeIn(),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SR REGISTER ENTRY',
                                style: TextStyle(
                                  color: context.colors.primaryGold,
                                  fontSize: 11,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                                  .animate()
                                  .slideY(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 100.ms)
                                  .fadeIn(),
                              Text(
                                heldEntry.srNumber ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                                  .animate()
                                  .slideY(
                                      begin: 0.1,
                                      duration: 400.ms,
                                      delay: 150.ms)
                                  .fadeIn(),
                            ],
                          ),
                        ),
                        const Gap(12),
                        DialogCloseButton(prominent: false),
                      ],
                    ),
                  ),

                  // ── Dialog Body ──
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.bolt_rounded,
                                  color: context.colors.primaryGold, size: 24),
                              const Gap(10),
                              Text(
                                'Goods Actions',
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ).animate().fadeIn(delay: 200.ms),
                          const Gap(16),
                          // The directorate has ruled, so the wait is over even
                          // though the window has days left. Says which way.
                          if (decidedEarly)
                            material.Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.successGreen
                                    .withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: context.colors.successGreen
                                        .withOpacity(0.4)),
                              ),
                              child: Row(children: [
                                Icon(Icons.gavel_rounded,
                                    color: context.colors.successGreen,
                                    size: 18),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                      'Appeal decided \u00b7 '
                                      '${itemOutcome.decision}. '
                                      'These goods can be actioned now \u2014 the '
                                      '30-day window no longer applies.',
                                      style: TextStyle(
                                          color: context.colors.successGreen,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ).animate().fadeIn(delay: 220.ms),
                          // An appeal is lodged and still open: frozen regardless
                          // of the deadline.
                          if (blockedByHold)
                            material.Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.warningAmber
                                    .withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: context.colors.warningAmber
                                        .withOpacity(0.4)),
                              ),
                              child: Row(children: [
                                Icon(Icons.pan_tool_rounded,
                                    color: context.colors.warningAmber,
                                    size: 18),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                      'On appeal hold. The Appeal Directorate is '
                                      'reviewing these goods \u2014 no action can '
                                      'be taken until it rules.',
                                      style: TextStyle(
                                          color: context.colors.warningAmber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ).animate().fadeIn(delay: 220.ms),
                          // Why everything is greyed out.
                          if (inAppealWindow && !blockedByHold)
                            material.Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.warningAmber
                                    .withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: context.colors.warningAmber
                                        .withOpacity(0.4)),
                              ),
                              child: Row(children: [
                                Icon(Icons.gavel_rounded,
                                    color: context.colors.warningAmber,
                                    size: 18),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                      'Appealing · $appealDaysRemaining day'
                                      '${appealDaysRemaining == 1 ? '' : 's'} left. '
                                      'No action can be taken until the 30-day '
                                      'appeal window closes.',
                                      style: TextStyle(
                                          color: context.colors.warningAmber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ).animate().fadeIn(delay: 220.ms),
                          if (heldCount <= 0)
                            material.Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.successGreen
                                    .withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: context.colors.successGreen
                                        .withOpacity(0.3)),
                              ),
                              child: Row(children: [
                                Icon(Icons.check_circle_rounded,
                                    color: context.colors.successGreen,
                                    size: 18),
                                const Gap(10),
                                Expanded(
                                  child: Text(
                                      'All $total packages have been processed.',
                                      style: TextStyle(
                                          color: context.colors.textSecondary,
                                          fontSize: 12)),
                                ),
                              ]),
                            ).animate().fadeIn(delay: 250.ms)
                          else
                            material.Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: material.Align(
                                alignment: material.Alignment.centerLeft,
                                child: Text(
                                    '$heldCount of $total packages remaining',
                                    style: TextStyle(
                                        color: context.colors.textMuted,
                                        fontSize: 13)),
                              ),
                            ).animate().fadeIn(delay: 250.ms),

                          // Show all actions
                          ..._actions.map((a) {
                            final isOther = a.key == 'Other';
                            // Disabled either by role-permission or because there
                            // are no packages left to act on.
                            final permitted = isActionEnabled(a.key);
                            final isDisabled = !permitted || heldCount <= 0;
                            // Greyed colour for disabled cards/labels.
                            final cardColor =
                                isDisabled ? context.colors.textMuted : a.color;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                material.Opacity(
                                  opacity: isDisabled ? 0.45 : 1.0,
                                  child: material.Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: (isOther && _otherExpanded)
                                            ? cardColor.withOpacity(0.6)
                                            : cardColor.withOpacity(0.2),
                                        width: (isOther && _otherExpanded)
                                            ? 1.5
                                            : 1,
                                      ),
                                    ),
                                    color: cardColor.withOpacity(0.04),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: isDisabled
                                          ? null
                                          : () async {
                                              if (isOther) {
                                                setState(() => _otherExpanded =
                                                    !_otherExpanded);
                                              } else {
                                                // Show selection dialog with live processed slots
                                                final slots =
                                                    await showAppDialog<
                                                        Set<int>>(
                                                  context: context,
                                                  builder: (ctx) =>
                                                      _PackageSelectionDialog(
                                                    actionColor: a.color,
                                                    actionName:
                                                        a.key == 'Release'
                                                            ? 'Release'
                                                            : a.key,
                                                    totalQty: total,
                                                    processedSlots: processed,
                                                  ),
                                                );
                                                if (slots != null &&
                                                    slots.isNotEmpty) {
                                                  final list = slots.toList()
                                                    ..sort();
                                                  final ctx = context;
                                                  if (a.key == 'Release') {
                                                    await _runAction(
                                                      ctx,
                                                      () => widget.onRelease(
                                                          heldEntry, list),
                                                      '${list.length} package(s) released successfully.',
                                                    );
                                                  } else {
                                                    await _runAction(
                                                      ctx,
                                                      () => widget.onDispose(
                                                          heldEntry,
                                                          a.key,
                                                          list),
                                                      '${list.length} package(s) marked as ${a.label} successfully.',
                                                    );
                                                  }
                                                }
                                              }
                                            },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        child: Row(children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color:
                                                  cardColor.withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(a.icon,
                                                color: cardColor, size: 20),
                                          ),
                                          const Gap(16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(a.label,
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 15,
                                                        color: cardColor)),
                                                const Gap(4),
                                                Text(a.description,
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        color: context
                                                            .colors.textMuted)),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            isOther
                                                ? (_otherExpanded
                                                    ? Icons.expand_less_rounded
                                                    : Icons.expand_more_rounded)
                                                : Icons.chevron_right_rounded,
                                            color: cardColor.withOpacity(0.6),
                                            size: 22,
                                          ),
                                        ]),
                                      ),
                                    ),
                                  )
                                      .animate()
                                      .fadeIn(delay: 300.ms)
                                      .slideY(begin: 0.05),
                                ),
                                // Inline "Other" text field
                                if (isOther && _otherExpanded)
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(4, 0, 4, 16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        TextFormField(
                                          controller: _otherCtrl,
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            labelText: 'Disposition Type *',
                                            hintText:
                                                'e.g. Transferred, Seized for Analysis...',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context
                                                      .colors.borderColor),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: context
                                                      .colors.borderColor),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color:
                                                      const Color(0xFF7E57C2),
                                                  width: 2),
                                            ),
                                            filled: true,
                                            fillColor: context
                                                .colors.textPrimary
                                                .withOpacity(0.02),
                                          ),
                                        ).animate().fadeIn(),
                                        const Gap(12),
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.check_rounded,
                                              size: 18),
                                          label: const Text(
                                              'Confirm Other Disposition',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF7E57C2),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                          ),
                                          onPressed: () async {
                                            final t = _otherCtrl.text.trim();
                                            if (t.isEmpty) return;

                                            final slots =
                                                await showAppDialog<Set<int>>(
                                              context: context,
                                              builder: (ctx) =>
                                                  _PackageSelectionDialog(
                                                actionColor:
                                                    const Color(0xFF7E57C2),
                                                actionName: t,
                                                totalQty: total,
                                                processedSlots: processed,
                                              ),
                                            );
                                            if (slots != null &&
                                                slots.isNotEmpty) {
                                              final list = slots.toList()
                                                ..sort();
                                              final ctx = context;
                                              // Prefix the custom text with the "Other:"
                                              // marker so the disposition is unambiguously
                                              // an "Other" outcome — tagged "[OTHER: <text>]"
                                              // in returnNotes (partial) and stored as item
                                              // status "Other: <text>" (full). This is what
                                              // the Other Packages table detects.
                                              await _runAction(
                                                ctx,
                                                () => widget.onDispose(
                                                    heldEntry,
                                                    'Other: $t',
                                                    list),
                                                '${list.length} package(s) marked as "$t" successfully.',
                                              );
                                            }
                                          },
                                        ).animate().fadeIn(),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                  // ── Dialog Footer ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceDark,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(20)),
                      border: Border(
                          top: BorderSide(color: context.colors.borderColor)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.textSecondary,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 14),
                          ),
                          child: const Text('Cancel',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Loading overlay ──
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFFB300)),
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionDef {
  final String key;
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  const _ActionDef({
    required this.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
  });
}

// ── Final-disposition helpers ─────────────────────────────────────────────────

bool _hasFinalDisposition(PackageModel pkg, String itemId) {
  return pkg.warehouseEntries.any((e) {
    if (e.packageItemId != itemId) return false;
    final notes = (e.returnNotes ?? '').trim().toUpperCase();
    // NOTE: a bare "[OTHER…]" tag is a warehouse-Actions custom disposition
    // (like "[ABANDONED]"/"[FORFEIT]") — NOT a final-table move, so it does
    // NOT count here. The item must remain actionable via Final Disposition
    // until it is genuinely finalised ("[FINAL:OTHER]" etc.). Only the real
    // final markers below hide the button.
    return notes.contains('[FINAL:') ||
        notes.startsWith('[RE-EXPORT') ||
        notes.startsWith('[DESTROY') ||
        notes.startsWith('[SOLD');
  });
}

bool _isForfeitStatusLocal(String? s) {
  final v = (s ?? '').trim().toLowerCase();
  return v == 'forfeit' ||
      v == 'forfeited' ||
      v == 'forfiet' ||
      v == 'confiscated';
}

/// Receipt/Notes are stored combined as "Receipt No: <no> | Notes: <notes>".
/// [_receiptNoOf] returns just the number; [_notesOf] returns just the notes.
/// Both handle a plain string (no prefix) gracefully.
String? _receiptNoOf(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final m =
      RegExp(r'Receipt No:\s*([^|]+)', caseSensitive: false).firstMatch(s);
  if (m != null) {
    final v = m.group(1)!.trim();
    return v.isEmpty ? null : v;
  }
  // No "Receipt No:" prefix — treat the part before any "| Notes:" as the no.
  final v = s.split(RegExp(r'\|?\s*Notes:', caseSensitive: false)).first.trim();
  return v.isEmpty ? null : v;
}

String? _notesOf(String? raw) {
  final s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  final m = RegExp(r'Notes:\s*(.+)$', caseSensitive: false).firstMatch(s);
  final v = m?.group(1)?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// True if the highlighted entry is itself an abandon/forfeit disposition —
/// used so partial abandon/forfeit rows (item status still 'detain') can
/// still receive a final disposition.
bool _isAbandonOrForfeitEntry(WarehouseEntryModel? e) {
  if (e == null || !e.isReturned) return false;
  final notes = (e.returnNotes ?? '').trim().toUpperCase();
  return notes.startsWith('[ABANDONED') ||
      notes.startsWith('[FORFEIT') ||
      notes.startsWith('[CONFISCATED');
}

// ── Per-package-number slot tracking ──────────────────────────────────────────

/// Parses the explicit package numbers encoded in a returnNotes string
/// ("... pkgs:2,5,17 ...").
Set<int> _parsePkgNums(String? notes) {
  if (notes == null) return {};
  final m = RegExp(r'pkgs:([\d,]+)').firstMatch(notes);
  if (m == null) return {};
  return m
      .group(1)!
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toSet();
}

/// The set of package slot numbers (1..totalQty) that have already been
/// processed (released / disposed) for an item. Entries that recorded explicit
/// numbers are honoured exactly; legacy count-only entries fall back to the
/// lowest still-available slots.
Set<int> _computeProcessedSlots(
    String itemId, int totalQty, List<WarehouseEntryModel> entries) {
  final explicit = <int>{};
  int legacy = 0;
  for (final e in entries) {
    if (e.packageItemId != itemId || !e.isReturned) continue;
    final nums = _parsePkgNums(e.returnNotes);
    if (nums.isNotEmpty) {
      explicit.addAll(nums);
    } else {
      legacy += e.itemCount;
    }
  }
  final result = <int>{...explicit};
  for (int n = 1; n <= totalQty && legacy > 0; n++) {
    if (!result.contains(n)) {
      result.add(n);
      legacy--;
    }
  }
  return result;
}

// ── Final Disposition Dialog ──────────────────────────────────────────────────

/// Result of the per-action final-disposition confirm dialog.
class _FinalActionConfirmResult {
  final DateTime date;
  final String notes;
  const _FinalActionConfirmResult(this.date, this.notes);
}

/// Per-action confirmation for a Release / Re-export / Other final disposition —
/// mirrors the warehouse action final step: a date picker (defaults to today,
/// future blocked, same one-tap calendar as the SR form) plus optional notes.
class _FinalActionConfirmDialog extends StatefulWidget {
  final String label; // 'Release' / 'Re-export' / 'Other: nnn'
  final IconData icon;
  final Color color;
  final String description;
  final int qty;
  const _FinalActionConfirmDialog({
    required this.label,
    required this.icon,
    required this.color,
    required this.description,
    required this.qty,
  });

  @override
  State<_FinalActionConfirmDialog> createState() =>
      _FinalActionConfirmDialogState();
}

class _FinalActionConfirmDialogState extends State<_FinalActionConfirmDialog> {
  DateTime _date = DateTime.now();
  late final TextEditingController _dateCtrl;
  final _notesCtrl = TextEditingController();

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _dateCtrl = TextEditingController(text: _fmt(_date));
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return material.AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Icon(widget.icon, color: widget.color, size: 22),
        const Gap(10),
        Flexible(child: Text('${widget.label} Package Item')),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.color.withOpacity(0.3)),
            ),
            child: Text(widget.description,
                style: TextStyle(color: widget.color, fontSize: 13)),
          ),
          const Gap(16),
          // Date — defaults to today, future blocked, one-tap calendar.
          TextFormField(
            controller: _dateCtrl,
            readOnly: true,
            decoration: InputDecoration(
              labelText: '${widget.label} Date',
              isDense: true,
              suffixIcon: Icon(Icons.calendar_month, color: widget.color),
            ),
            onTap: () async {
              final picked = await showAppDialog<DateTime>(
                context: context,
                builder: (_) => OneTapDatePicker(
                  initialDate: _date,
                  lastDate: DateTime.now(),
                ),
              );
              if (picked != null) {
                setState(() {
                  _date = picked;
                  _dateCtrl.text = _fmt(picked);
                });
              }
            },
          ),
          const Gap(12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.color.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Packages selected:',
                    style: TextStyle(
                        fontSize: 12, color: widget.color.withOpacity(0.7))),
                Text('${widget.qty}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: widget.color)),
              ],
            ),
          ),
          const Gap(12),
          TextFormField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notes / Remarks (optional)',
              isDense: true,
            ),
            maxLines: 3,
            minLines: 2,
            keyboardType: TextInputType.multiline,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton.icon(
          icon: Icon(widget.icon, size: 16),
          label: Text('Confirm ${widget.label}'),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.color,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(
            context,
            _FinalActionConfirmResult(_date, _notesCtrl.text.trim()),
          ),
        ),
      ],
    );
  }
}

class _FinalActionDef {
  final String type; // RELEASED, SOLD, DESTROYED, RE-EXPORTED, OTHER
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final bool adminOnly;
  const _FinalActionDef({
    required this.type,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.adminOnly,
  });
}

class _FinalDispositionDialog extends StatefulWidget {
  final PackageItem item;
  final int qty;
  final bool isOfficer;
  final Future<void> Function(String type, String? notes, DateTime date)
      onConfirm;
  // When supplied (Forfeited screen), Sale → 'sale' and Destroy → 'destruction'
  // route here to open the Central Disposal request flow instead of writing a
  // [FINAL:…] entry. When null, Sale / Destroy stay disabled.
  final void Function(String disposition)? onRequestDisposal;
  // Appeal Directorate decision code — when set, ONLY the matching action is
  // enabled (the yard must proceed exactly as decided).
  final String? decisionCode;
  // Detained goods within the 30-day window: Release/Re-export/Other are
  // allowed immediately; Destroy is blocked until 30 days pass or a decision.
  final bool isDetained;
  final bool inAppealWindow;

  const _FinalDispositionDialog({
    required this.item,
    required this.qty,
    required this.isOfficer,
    required this.onConfirm,
    this.onRequestDisposal,
    this.decisionCode,
    this.isDetained = false,
    this.inAppealWindow = false,
  });

  @override
  State<_FinalDispositionDialog> createState() =>
      _FinalDispositionDialogState();
}

class _FinalDispositionDialogState extends State<_FinalDispositionDialog> {
  bool _otherExpanded = false;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  static const _actions = [
    _FinalActionDef(
      type: 'RELEASED',
      icon: Icons.assignment_return_rounded,
      label: 'Release',
      description:
          'Return the goods to the owner. SDDC / DDC approval required.',
      color: Color(0xFF43A047),
      adminOnly: true,
    ),
    _FinalActionDef(
      type: 'SOLD',
      icon: Icons.sell_rounded,
      label: 'Sale',
      description:
          'Send a disposal request to the Central Disposal Directorate.',
      color: Color(0xFFE8A826),
      adminOnly: false,
    ),
    _FinalActionDef(
      type: 'DESTROYED',
      icon: Icons.delete_forever_rounded,
      label: 'Destroy',
      description: 'Mark goods for destruction. SDDC / DDC approval required.',
      color: Color(0xFFE64A19),
      adminOnly: true,
    ),
    _FinalActionDef(
      type: 'RE-EXPORTED',
      icon: Icons.flight_takeoff_rounded,
      label: 'Re-export',
      description: 'Goods sent back to origin. SDDC / DDC approval required.',
      color: Color(0xFF00ACC1),
      adminOnly: true,
    ),
    _FinalActionDef(
      type: 'OTHER',
      icon: Icons.more_horiz_rounded,
      label: 'Other',
      description: 'Custom outcome. SDDC / DDC approval required.',
      color: Color(0xFF7E57C2),
      adminOnly: true,
    ),
  ];

  // Sale is written via disposal request to Central Disposal Directorate.
  // Release / Destroy / Re-export / Other are recorded directly.
  static const _requestActions = {'SOLD'};

  // The final-action type that matches an Appeal Directorate decision code.
  static String? _typeForDecision(String code) {
    switch (code.trim().toUpperCase()) {
      case 'RELEASE':
        return 'RELEASED';
      case 'SALE':
        return 'SOLD';
      case 'DESTROY':
      case 'DESTRUCTION':
      case 'SUPPOSED TO BE DESTROYED':
        return 'DESTROYED';
      case 'RE-EXPORT':
        return 'RE-EXPORTED';
      case 'OTHER':
        return 'OTHER';
      default:
        return null;
    }
  }

  // Whether THIS user may trigger the given action.
  // - Officers: nothing is enabled.
  // - Sale: ALWAYS disabled here (must use "Send Disposal Request").
  // - When Appeal Directorate has DECIDED: only matching action is enabled.
  // - Otherwise: Release / Destroy / Re-export / Other are enabled for DC/SDDC.
  bool _isActionEnabled(_FinalActionDef a) {
    if (widget.isOfficer) return false;
    if (_requestActions.contains(a.type)) return false;
    final code = widget.decisionCode;
    if (code != null && code.trim().isNotEmpty) {
      return a.type == _typeForDecision(code);
    }
    // Detained goods within the 30-day appeal window: Destroy is also blocked
    // (Sale is already blocked above via _requestActions). Release / Re-export
    // / Other are always available immediately for detained goods.
    if (widget.isDetained && widget.inAppealWindow) {
      if (a.type == 'DESTROYED') return false;
    }
    return true;
  }

  /// Opens the per-action confirmation dialog (date + notes) — mirroring the
  /// warehouse action final step — then records the disposition on that date.
  /// [otherDetail] carries the custom outcome text for the OTHER action.
  Future<void> _confirmFinalAction(_FinalActionDef a,
      {String? otherDetail}) async {
    final label = otherDetail != null ? 'Other: $otherDetail' : a.label;
    final result = await showAppDialog<_FinalActionConfirmResult>(
      context: context,
      builder: (_) => _FinalActionConfirmDialog(
        label: label,
        icon: a.icon,
        color: a.color,
        description: a.description,
        qty: widget.qty,
      ),
    );
    if (result == null) return;
    // For OTHER the outcome detail is the note; append any extra remarks.
    final String? notes;
    if (otherDetail != null) {
      notes =
          result.notes.isEmpty ? otherDetail : '$otherDetail — ${result.notes}';
    } else {
      notes = result.notes.isEmpty ? null : result.notes;
    }
    await widget.onConfirm(a.type, notes, result.date);
  }

  @override
  Widget build(BuildContext context) {
    // All actions are shown; disabled ones are greyed out and non-tappable.
    final visible = _actions;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 520,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: context.colors.scaffoldBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [context.colors.surfaceDark, context.colors.cardDark]
                        : [
                            context.colors.customsBlue,
                            context.colors.customsBlueDark
                          ],
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    material.Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.outbound_rounded,
                          color: context.colors.primaryGold, size: 24),
                    ).animate().slideY(begin: 0.1, duration: 400.ms).fadeIn(),
                    const Gap(16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('FINAL DISPOSITION',
                                  style: material.TextStyle(
                                      color: context.colors.primaryGold,
                                      fontSize: 11,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w800))
                              .animate()
                              .slideY(
                                  begin: 0.1, duration: 400.ms, delay: 100.ms)
                              .fadeIn(),
                          Text(
                            '${widget.item.itemName} · ${widget.qty} unit(s)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const material.TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          )
                              .animate()
                              .slideY(
                                  begin: 0.1, duration: 400.ms, delay: 150.ms)
                              .fadeIn(),
                        ],
                      ),
                    ),
                    const Gap(12),
                    DialogCloseButton(prominent: false),
                  ],
                ),
              ),

              // ── Body ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.assignment_ind_rounded,
                            size: 16, color: context.colors.primaryGold),
                        const Gap(8),
                        Text('Disposal Method',
                            style: material.TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3)),
                      ]).animate().fadeIn(delay: 200.ms),
                      if (widget.isOfficer) ...[
                        const Gap(6),
                        Text(
                          'Final disposition is restricted to SDDC / DDC officers.',
                          style: material.TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 11,
                              fontStyle: FontStyle.italic),
                        ),
                      ] else if (widget.isDetained && widget.inAppealWindow) ...[
                        const Gap(6),
                        Text(
                          'Goods are within the 30-day appeal window. Release, Re-export and Other may be recorded now. Sale and Destroy require the window to pass or an Appeal Directorate decision.',
                          style: material.TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 11,
                              fontStyle: FontStyle.italic),
                        ),
                      ] else ...[
                        const Gap(6),
                        Text(
                          'Sale goes to Central Disposal as a request; Release / Destroy / Re-export / Other are recorded directly.',
                          style: material.TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 11,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                      const Gap(16),
                      ...visible.map((a) {
                        final isOther = a.type == 'OTHER';
                        final isEnabled = _isActionEnabled(a);
                        final cardColor =
                            isEnabled ? a.color : context.colors.textMuted;
                        return Opacity(
                          opacity: isEnabled ? 1.0 : 0.45,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              material.Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: (isOther && _otherExpanded)
                                        ? cardColor.withOpacity(0.6)
                                        : cardColor.withOpacity(0.2),
                                    width:
                                        (isOther && _otherExpanded) ? 1.5 : 1,
                                  ),
                                ),
                                color: cardColor.withOpacity(0.04),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: !isEnabled
                                      ? null
                                      : () {
                                          if (isOther) {
                                            setState(() => _otherExpanded =
                                                !_otherExpanded);
                                          } else if (_requestActions
                                              .contains(a.type)) {
                                            // Sale → disposal request
                                            widget.onRequestDisposal!('sale');
                                          } else {
                                            // Release / Destroy / Re-export → per-action confirm dialog
                                            _confirmFinalAction(a);
                                          }
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    child: Row(children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: cardColor.withOpacity(0.12),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(a.icon,
                                            color: cardColor, size: 20),
                                      ),
                                      const Gap(14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(children: [
                                              Text(a.label,
                                                  style: material.TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 14,
                                                      color: cardColor)),
                                              if (_requestActions
                                                  .contains(a.type)) ...[
                                                const Gap(6),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: cardColor
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                      'CENTRAL DISPOSAL',
                                                      style: material.TextStyle(
                                                          fontSize: 8,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: cardColor,
                                                          letterSpacing: 0.5)),
                                                ),
                                              ] else if (a.adminOnly) ...[
                                                const Gap(6),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: cardColor
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text('SDDC / DDC',
                                                      style: material.TextStyle(
                                                          fontSize: 8,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: cardColor,
                                                          letterSpacing: 0.5)),
                                                ),
                                              ],
                                            ]),
                                            const Gap(2),
                                            Text(a.description,
                                                style: material.TextStyle(
                                                    fontSize: 12,
                                                    color: context
                                                        .colors.textMuted)),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        isOther
                                            ? (_otherExpanded
                                                ? Icons.expand_less_rounded
                                                : Icons.expand_more_rounded)
                                            : Icons.chevron_right_rounded,
                                        color: cardColor.withOpacity(0.6),
                                        size: 20,
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                              if (isOther && _otherExpanded)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(4, 0, 4, 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TextFormField(
                                        controller: _otherCtrl,
                                        autofocus: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Outcome detail *',
                                          hintText:
                                              'e.g. Donated, Transferred...',
                                          isDense: true,
                                        ),
                                      ),
                                      const Gap(10),
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.check_rounded,
                                            size: 16),
                                        label: const Text('Confirm Other'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF7E57C2),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () {
                                          final t = _otherCtrl.text.trim();
                                          if (t.isEmpty) return;
                                          _confirmFinalAction(a,
                                              otherDetail: t);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.05),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              // ── Footer ──
              material.Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: context.colors.surfaceDark,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(
                      top: BorderSide(color: context.colors.borderColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.textSecondary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Disposition meta resolvers (by normalized returnNotes key) ────────────────

String _dispoLabel(String key, String raw) {
  switch (key) {
    case 'FORFEIT':
    case 'FORFEITED':
    case 'FORFIET':
    case 'CONFISCATED':
      return 'Forfeited';
    case 'RE-EXPORT':
    case 'REEXPORT':
      return 'Re-export';
    case 'ABANDONED':
      return 'Abandoned';
    case 'DESTROY':
    case 'DESTROYED':
      return 'Destroy';
    default:
      // Title-case the custom "Other" type
      return raw
          .split(' ')
          .map((w) => w.isEmpty
              ? w
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
          .join(' ');
  }
}

// ── Disposition Row (shows status breakdown) ──────────────────────────────────

class _DispositionMeta {
  final IconData icon;
  final Color color;
  final String label;
  final String description;
  const _DispositionMeta({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
  });
}

class _DispositionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _DispositionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 14, color: color),
      label: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: color.withOpacity(0.05),
      ),
      onPressed: onPressed,
    );
  }
}

class _PackageSelectionDialog extends StatefulWidget {
  final Color actionColor;
  final String actionName;
  final int totalQty;
  final Set<int> processedSlots;

  const _PackageSelectionDialog({
    required this.actionColor,
    required this.actionName,
    required this.totalQty,
    required this.processedSlots,
  });

  @override
  State<_PackageSelectionDialog> createState() =>
      _PackageSelectionDialogState();
}

class _PackageSelectionDialogState extends State<_PackageSelectionDialog> {
  late Set<int> _selectedSlots;
  late final List<int> _heldSlots;
  // For large item counts (e.g. 1176 pieces) a tile-per-unit grid is unusable,
  // so we switch to a plain "how many to release" number field instead.
  late final bool _useQtyInput;
  final _qtyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _heldSlots = [
      for (int n = 1; n <= widget.totalQty; n++)
        if (!widget.processedSlots.contains(n)) n
    ];
    // By default, select all available (held) slots.
    _selectedSlots = _heldSlots.toSet();
    _useQtyInput = widget.totalQty > 50;
    _qtyCtrl.text = '${_heldSlots.length}';
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _toggleSlot(int slot) {
    setState(() {
      if (_selectedSlots.contains(slot)) {
        _selectedSlots.remove(slot);
      } else {
        _selectedSlots.add(slot);
      }
    });
  }

  // Quantity-input mode: select the first [n] available (held) slots.
  void _setQty(int n) {
    final clamped = n.clamp(0, _heldSlots.length);
    setState(() => _selectedSlots = _heldSlots.take(clamped).toSet());
  }

  void _selectAll() => setState(() {
        _selectedSlots = _heldSlots.toSet();
        _qtyCtrl.text = '${_heldSlots.length}';
      });
  void _clearAll() => setState(() {
        _selectedSlots.clear();
        _qtyCtrl.text = '0';
      });

  @override
  Widget build(BuildContext context) {
    final bool canProceed = _selectedSlots.isNotEmpty;

    return material.AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.all(24),
      title: Text('Select Packages to ${widget.actionName}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select which specific packages you want to apply this action to.',
                style: TextStyle(color: context.colors.textMuted, fontSize: 13),
              ),
              const Gap(16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedSlots.length} of ${_heldSlots.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _selectAll,
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          tapTargetSize:
                              material.MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Select All',
                            style: TextStyle(fontSize: 12)),
                      ),
                      const Gap(8),
                      TextButton(
                        onPressed: _clearAll,
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          tapTargetSize:
                              material.MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: context.colors.textMuted,
                        ),
                        child: const Text('Clear All',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
              const Gap(12),
              if (_useQtyInput)
                // Large counts → a single quantity field ("release N of M").
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: material.TextField(
                        controller: _qtyCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          isDense: true,
                        ),
                        onChanged: (v) => _setQty(int.tryParse(v) ?? 0),
                      ),
                    ),
                    const Gap(12),
                    Text('of ${_heldSlots.length} available',
                        style: TextStyle(color: context.colors.textSecondary)),
                  ],
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(widget.totalQty, (index) {
                    final slotNumber = index + 1;
                    final isProcessed =
                        widget.processedSlots.contains(slotNumber);
                    final isSelected = _selectedSlots.contains(slotNumber);

                    return _PackageSlotChip(
                      slotNumber: slotNumber,
                      totalQty: widget.totalQty,
                      isProcessed: isProcessed,
                      isSelected: isSelected,
                      activeColor: widget.actionColor,
                      onTap: isProcessed ? null : () => _toggleSlot(slotNumber),
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text('Cancel', style: TextStyle(color: context.colors.textMuted)),
        ),
        ElevatedButton(
          onPressed:
              canProceed ? () => Navigator.pop(context, _selectedSlots) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.actionColor,
            foregroundColor: Colors.white,
            disabledBackgroundColor: widget.actionColor.withOpacity(0.3),
            disabledForegroundColor: Colors.white.withOpacity(0.5),
          ),
          child: Text('${widget.actionName} (${_selectedSlots.length})'),
        ),
      ],
    );
  }
}

class _PackageSlotChip extends StatelessWidget {
  final int slotNumber;
  final int totalQty;
  final bool isProcessed;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback? onTap;

  const _PackageSlotChip({
    required this.slotNumber,
    required this.totalQty,
    required this.isProcessed,
    required this.isSelected,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color bgColor;
    Color borderColor;
    Color textColor;

    if (isProcessed) {
      bgColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;
      borderColor = Colors.transparent;
      textColor = isDark ? Colors.grey[500]! : Colors.grey[500]!;
    } else if (isSelected) {
      bgColor = activeColor.withOpacity(0.1);
      borderColor = activeColor;
      textColor = activeColor;
    } else {
      bgColor = Colors.transparent;
      borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
      textColor = isDark ? Colors.grey[300]! : Colors.grey[700]!;
    }

    return material.InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: material.AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Icon(Icons.check_circle_rounded, size: 14, color: activeColor),
              const Gap(4),
            ],
            Text(
              '$slotNumber / $totalQty',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: textColor,
                decoration:
                    isProcessed ? material.TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
