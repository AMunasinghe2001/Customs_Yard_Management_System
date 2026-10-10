import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme.dart';
import 'app_dialog.dart';
import '../screens/forfeited_packages/disposal_request_dialog.dart';

/// The "Send Disposal Request" button, shared by all five held-goods pages —
/// Detained, Abandoned, Forfeited, Other and Perishable.
///
/// ⚠️ SENDING A DISPOSAL REQUEST IS A YARD ADMINISTRATION ACT. It asks Central
/// Disposal to sell or destroy goods the State is holding, and only the SDDC /
/// DDC who runs the yard may ask for it. The five pages each built their own
/// button gated on `actionable > 0` alone, so any yard OFFICER could send one
/// — the same authority the Final Disposition button already refuses them, on
/// the very same rows.
///
/// The rule lives here, once, rather than in five copies that can drift: the
/// pages differ in how they count actionable rows, not in who may act.
class SendDisposalRequestButton extends ConsumerWidget {
  const SendDisposalRequestButton({
    super.key,
    required this.actionable,
    this.onSubmitted,
  });

  /// How many rows are ready to be sent. Zero disables the button for
  /// everyone, admin included — there is nothing to ask for.
  final int actionable;

  /// Refresh whatever the page shows once a request has gone.
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    // ⚠️ Asked POSITIVELY. Testing "is not an officer" instead would let a
    // null profile — still loading, or signed out under us — count as
    // permission; the button stays disabled until an admin is identified.
    final isAdmin = profile?.isAdmin ?? false;
    final enabled = isAdmin && actionable > 0;

    final button = ElevatedButton.icon(
      icon: const Icon(Icons.local_shipping_rounded, size: 16),
      label: const Text('Send Disposal Request'),
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled
            ? context.colors.primaryGold
            : context.colors.textMuted.withOpacity(0.2),
        foregroundColor: enabled ? Colors.white : context.colors.textMuted,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: enabled ? 2 : 0,
      ),
      onPressed: enabled
          ? () => showAppDialog(
                context: context,
                builder: (ctx) =>
                    DisposalRequestDialog(onSubmitted: onSubmitted),
              )
          : null,
    );

    // Say WHY it is off. A disabled button with no explanation reads as a
    // fault in the app; the officer needs to know this is their post, not a
    // bug — the same wording the Final Disposition button uses.
    return Tooltip(
      message: !isAdmin
          ? 'Only SDDC / DDC can send a disposal request'
          : (actionable == 0
              ? 'No goods are ready to be sent yet'
              : 'Send these goods to Central Disposal'),
      child: button,
    );
  }
}
