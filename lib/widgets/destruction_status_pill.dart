import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'tooltip_text.dart';

/// Every metric the destruction status control uses, in one place.
///
/// The yard's table and Central Disposal's table show the SAME states, so they
/// must render at the SAME size — otherwise "Pending" comes out narrower than
/// "Destroyed", and the yard's clickable "Mark Destroyed" dwarfs both. A fixed
/// box is what keeps the three states interchangeable across the two screens.
/// ⚠️ Wide enough for the LONGEST label any of these pills carries --
/// "Remove from the Premises" and "Awaiting Top Management" are the two that
/// set it. At 132 they were clipped to "Remove from the P..." and "Awaiting
/// Top Mana...", which is worse than a ragged column: the officer could not
/// read what had been decided at all.
const double kDestructionPillWidth = 196;
const double kDestructionPillHeight = 28;
const double _kPillFontSize = 11;
const double _kPillIconSize = 13;

/// The column width that fits [kDestructionPillWidth] with the table's own
/// cell padding. Both Destroyed Goods tables use it, so their status columns
/// line up.
const double kDestructionStatusColumnWidth = 214;

/// The one control both Destroyed Goods tables use for a package's destruction
/// state.
///
/// Destruction is two states — marked for destruction, then confirmed
/// destroyed. Only the yard confirms one, so [onMark] is supplied there and
/// left null on Central Disposal, which reads the same state but cannot act on
/// it. All three renderings share one box so the two tables match.
class DestructionStatusPill extends StatelessWidget {
  /// True once the destruction is confirmed.
  final bool destroyed;

  /// Supplied only where the destruction can be confirmed (the yard). When
  /// null an unconfirmed row shows a read-only "Pending" pill instead.
  final VoidCallback? onMark;

  const DestructionStatusPill({super.key, required this.destroyed, this.onMark});

  @override
  Widget build(BuildContext context) {
    if (destroyed) {
      return _pill(
        context,
        color: context.colors.successGreen,
        icon: Icons.check_circle_rounded,
        label: 'Destroyed',
      );
    }
    if (onMark == null) {
      return _pill(
        context,
        color: context.colors.warningAmber,
        icon: Icons.schedule_rounded,
        label: 'Pending',
      );
    }
    return _pill(
      context,
      color: context.colors.dangerRed,
      icon: Icons.local_fire_department_rounded,
      label: 'Mark Destroyed',
      onTap: onMark,
    );
  }

  // Renders through the SHARED box, so the Destroyed and Delivered columns
  // cannot drift apart.
  Widget _pill(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) =>
      _statusPill(context,
          color: color, icon: icon, label: label, onTap: onTap);
}

/// The one control both Sold Goods tables use for a package's delivery state.
///
/// Delivery mirrors destruction exactly: two states, and only the yard
/// confirms one. So it renders through the SAME fixed box -- a "Mark
/// Delivered" that is a different size and shape from "Delivered" makes the
/// column jump as rows change state, and makes the two tables disagree with
/// the Destroyed Goods column right beside them.
///
/// ⚠️ There is no revert. Once delivered the pill is a plain label: goods that
/// left with their buyer cannot un-leave, so [onMark] is ignored then.
class DeliveryStatusPill extends StatelessWidget {
  /// True once delivery is confirmed.
  final bool delivered;

  /// Supplied only where delivery can be confirmed (the yard). When null an
  /// undelivered row shows a read-only "Pending" pill instead.
  final VoidCallback? onMark;

  /// Shows a spinner in place of the icon while the write is in flight.
  final bool busy;

  const DeliveryStatusPill(
      {super.key, required this.delivered, this.onMark, this.busy = false});

  @override
  Widget build(BuildContext context) {
    if (delivered) {
      return _statusPill(
        context,
        color: context.colors.successGreen,
        icon: Icons.check_circle_rounded,
        label: 'Delivered',
      );
    }
    if (onMark == null) {
      return _statusPill(
        context,
        color: context.colors.warningAmber,
        icon: Icons.schedule_rounded,
        label: 'Pending',
      );
    }
    return _statusPill(
      context,
      color: context.colors.successGreen,
      icon: Icons.local_shipping_rounded,
      label: 'Mark Delivered',
      onTap: busy ? null : onMark,
      busy: busy,
    );
  }
}

/// The width every status pill in a table column takes.
///
/// ⚠️ A pill that sizes to its own text makes a column of them ragged --
/// "Convert" ends up half the width of "Remove from the Premises", and the
/// eye cannot scan down the column. One box, whatever the label.
const double kStatusPillWidth = kDestructionPillWidth;

/// The shared box every status pill renders through, so the Destroyed,
/// Delivered and Final Outcome columns all match each other exactly.
Widget statusPill(
  BuildContext context, {
  required Color color,
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  bool busy = false,
  String? tooltip,
}) {
  final pill = _statusPill(context,
      color: color, icon: icon, label: label, onTap: onTap, busy: busy);
  if (tooltip == null || tooltip.isEmpty) return pill;
  return Tooltip(message: tooltip, child: pill);
}

Widget _statusPill(
  BuildContext context, {
  required Color color,
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  bool busy = false,
}) {
  final box = Container(
    width: kDestructionPillWidth,
    height: kDestructionPillHeight,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
              width: _kPillIconSize,
              height: _kPillIconSize,
              child: CircularProgressIndicator(strokeWidth: 2, color: color))
        else
          Icon(icon, size: _kPillIconSize, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: color,
                fontSize: _kPillFontSize,
                fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  if (onTap == null) return box;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: box,
    ),
  );
}

/// What an SR's destruction actually cost, shown identically on both Destroyed
/// Goods tables.
///
/// This is the WHOLE spend charged against the destroying deposit, not the
/// destruction line alone — the two tables previously disagreed because one
/// read `destructionExpense` and the other `depositSpent`, so the same SR
/// showed two different figures. Blank until something is recorded: a real
/// zero, never an invented placeholder.
class DestructionExpenseCell extends ConsumerWidget {
  final String srNumber;
  const DestructionExpenseCell({super.key, required this.srNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = NumberFormat('#,##0.00');
    final async = ref.watch(srFinancialsProvider);
    return async.when(
      loading: () => const SizedBox(
          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) =>
          Text('—', style: TextStyle(color: context.colors.textMuted)),
      data: (all) {
        final SrFinancials? sr =
            all.where((f) => f.srNumber.trim() == srNumber.trim()).firstOrNull;
        final spent = sr?.depositSpent ?? 0;
        if (spent <= 0) {
          return Text('—', style: TextStyle(color: context.colors.textMuted));
        }
        return TooltipText(
          'LKR ${fmt.format(spent)}',
          style: TextStyle(
              color: context.colors.dangerRed,
              fontWeight: FontWeight.w700,
              fontSize: 12),
        );
      },
    );
  }
}
