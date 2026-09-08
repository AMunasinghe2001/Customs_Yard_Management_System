import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'destruction_status_pill.dart';
import 'handover_form_dialog.dart';
import 'error_view.dart';

/// The two hand-overs an ENTRY carries: a re-export shipping, a release
/// being collected.
///
/// ⚠️ One cell, two kinds. They are the same interaction down to the
/// column width -- a pill, one irreversible action, no revert -- and differ
/// only in which column the answer lives in and what the goods are waiting
/// FOR. Two near-identical widgets would drift, and the drift would show as
/// two pages behaving slightly differently for no reason a reader could see.
enum HandoverEntryKind {
  reexport(
    done: 'The goods have left for their country of origin',
    prompt: 'Confirm the goods have left the yard',
    waiting: 'Awaiting the yard to confirm departure',
  ),
  released(
    done: 'The owner has collected the goods',
    prompt: 'Confirm the owner has collected the goods',
    waiting: 'Awaiting the yard to confirm collection',
  );

  const HandoverEntryKind(
      {required this.done, required this.prompt, required this.waiting});

  final String done;
  final String prompt;
  final String waiting;

  /// What the hand-over form says. The two differ in what the owner is
  /// paying for and what happens next -- a ship, or a collection.
  String get formTitle => switch (this) {
        HandoverEntryKind.reexport => 'Ship Re-exported Goods',
        HandoverEntryKind.released => 'Release Goods to Owner',
      };

  String get formAction => switch (this) {
        HandoverEntryKind.reexport => 'Confirm Shipped',
        HandoverEntryKind.released => 'Confirm Collected',
      };

  IconData get formIcon => switch (this) {
        HandoverEntryKind.reexport => Icons.flight_takeoff_rounded,
        HandoverEntryKind.released => Icons.keyboard_return_rounded,
      };

  String get chargeCaption => switch (this) {
        HandoverEntryKind.reexport =>
          'Storage from the SR entry date to the re-export',
        HandoverEntryKind.released =>
          'Storage from the SR entry date to the release',
      };
}

class HandoverCell extends ConsumerStatefulWidget {
  final WarehouseEntryModel? entry;

  /// The package, for the storage charge the hand-over collects.
  ///
  /// ⚠️ Without it the button cannot open the form, so it falls back to
  /// the old flag-only write. That is the wrong default for goods the yard
  /// is owed money on, so every caller passes it.
  final PackageModel? package;

  /// The rate history the charge is computed against.
  final Map<DateTime, double>? rates;

  /// The view's answer, so the pill is right on first paint rather than
  /// after a second fetch this cell would otherwise have to make.
  final bool? delivered;
  final HandoverEntryKind kind;
  const HandoverCell({
    required this.entry,
    required this.kind,
    this.delivered,
    this.package,
    this.rates,
  });

  @override
  ConsumerState<HandoverCell> createState() => HandoverCellState();
}

class HandoverCellState extends ConsumerState<HandoverCell> {
  bool _saving = false;
  bool? _optimistic;

  Future<void> _mark() async {
    final entry = widget.entry;
    final id = entry?.id;
    if (id == null || entry == null) return;

    // ⚠️ The FORM first. A hand-over is not a click: storage has been
    // accruing since the goods arrived, the owner pays it, the officer
    // writes a receipt, and only then do the goods leave. The button used
    // to skip all of it and set a flag, so the charge on the row beside it
    // was a figure nobody had a record of collecting.
    HandoverResult? result;
    final pkg = widget.package;
    final rates = widget.rates;
    if (pkg != null && rates != null) {
      final charge = handoverCharge(entry, pkg, rates);
      final item = pkg.items
          .where((i) => i.id == entry.packageItemId)
          .firstOrNull;
      result = await showHandoverForm(
        context,
        title: widget.kind.formTitle,
        actionLabel: widget.kind.formAction,
        icon: widget.kind.formIcon,
        srNumber: pkg.srNumber,
        itemName: item?.itemName ?? '—',
        quantity: entry.itemCount,
        charge: charge,
        chargeCaption: widget.kind.chargeCaption,
      );
      // Cancelled: nothing is written and the goods stay where they are.
      if (result == null) return;
    }

    setState(() => _saving = true);
    try {
      final svc = ref.read(disposalServiceProvider);
      await switch (widget.kind) {
        HandoverEntryKind.reexport => svc.toggleReexportDelivery(id, true,
            receiptNo: result?.receiptNo,
            charge: result?.charge,
            handedAt: result?.handedOverAt),
        HandoverEntryKind.released => svc.toggleReleasedDelivery(id, true,
            receiptNo: result?.receiptNo,
            charge: result?.charge,
            handedAt: result?.handedOverAt),
      };
      // ⚠️ Hold the answer locally as well as refreshing. The table
      // rebuilds from `disposition_rows`, and until that round-trip lands
      // the pill would snap back to Pending under the reader's eyes.
      if (mounted) setState(() => _optimistic = true);
      ref.read(warehouseRefreshTriggerProvider.notifier).trigger();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Marked as Delivered'),
          backgroundColor: context.colors.successGreen,
        ));
      }
    } catch (e) {
      if (mounted) showErrorSnack(context, e, action: 'Confirming delivery');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivered = _optimistic ?? widget.delivered ?? false;
    // Only a yard confirms a hand-over; Central Disposal watches.
    final profile = ref.watch(currentProfileProvider);
    final canEdit =
        profile != null && !profile.isDisposal && widget.entry != null;
    return Tooltip(
      message: delivered
          ? widget.kind.done
          : (canEdit ? widget.kind.prompt : widget.kind.waiting),
      child: DeliveryStatusPill(
        delivered: delivered,
        busy: _saving,
        onMark: (canEdit && !delivered) ? _mark : null,
      ),
    );
  }
}

// Read-only delivery STATUS chip for a DESTROYED package (mirrors
// _DeliveryStatusCell but reads the destruction item).
/// The Valuation Directorate's valuation (unit cost × qty) for a SOLD item —
/// shown alongside the actual sold price so both figures can be compared.
