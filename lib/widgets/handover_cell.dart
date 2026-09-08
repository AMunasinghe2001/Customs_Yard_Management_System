import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'destruction_status_pill.dart';
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
}

class HandoverCell extends ConsumerStatefulWidget {
  final WarehouseEntryModel? entry;

  /// The view's answer, so the pill is right on first paint rather than
  /// after a second fetch this cell would otherwise have to make.
  final bool? delivered;
  final HandoverEntryKind kind;
  const HandoverCell(
      {required this.entry, required this.kind, this.delivered});

  @override
  ConsumerState<HandoverCell> createState() => HandoverCellState();
}

class HandoverCellState extends ConsumerState<HandoverCell> {
  bool _saving = false;
  bool? _optimistic;

  Future<void> _mark() async {
    final id = widget.entry?.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      final svc = ref.read(disposalServiceProvider);
      await switch (widget.kind) {
        HandoverEntryKind.reexport => svc.toggleReexportDelivery(id, true),
        HandoverEntryKind.released => svc.toggleReleasedDelivery(id, true),
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
