import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// The account table cells shared by the yard Admin Panel and the ICT portal.
///
/// These lived privately inside `admin_screen.dart`, so the ICT staff table
/// grew its own plainer versions and the two drifted: ICT showed a grey
/// "ACTIVE" pill with no expiry information at all, while the Admin Panel
/// showed a green one that also warned when an account was about to
/// auto-deactivate. Both screens now render the same widgets.

/// How long until the account auto-deactivates (its 8-month lifetime).
///
/// "Never" for directorate accounts, "Expired" once past, and a red countdown
/// in the last 2 weeks so admins can renew in time.
class ExpiresInCell extends StatelessWidget {
  final ProfileModel profile;
  const ExpiresInCell({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final days = profile.daysUntilExpiry;
    if (days == null) {
      return Text('Never',
          style: TextStyle(color: context.colors.textMuted, fontSize: 12));
    }
    if (days < 0) {
      return Text('Expired',
          style: TextStyle(
              color: context.colors.dangerRed,
              fontWeight: FontWeight.w700,
              fontSize: 12));
    }
    final soon = days <= 14;
    final label = days == 0 ? 'Today' : '$days day${days == 1 ? '' : 's'}';
    return Text(label,
        style: TextStyle(
            color: soon ? context.colors.dangerRed : context.colors.textPrimary,
            fontWeight: soon ? FontWeight.w700 : FontWeight.w600,
            fontSize: 12));
  }
}

/// Read-only account status: ACTIVE (green), EXPIRED or INACTIVE (red).
///
/// An account is ACTIVE until 8 months after its creation date; the tooltip
/// gives the exact date either way.
class AccountStatusChip extends StatelessWidget {
  final ProfileModel profile;
  const AccountStatusChip({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    if (!profile.isActive) {
      label = 'INACTIVE';
      color = context.colors.dangerRed;
    } else if (profile.isExpired) {
      label = 'EXPIRED';
      color = context.colors.dangerRed;
    } else {
      label = 'ACTIVE';
      color = context.colors.successGreen;
    }
    final expiresStr = DateFormat('dd MMM yyyy').format(profile.expiresAt);
    return Tooltip(
      message: profile.isExpired
          ? 'Auto-deactivated on $expiresStr (8 months after creation)'
          : 'Auto-deactivates on $expiresStr (8 months after creation)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// The Edit / Delete pair used in every admin-style table's Actions column.
///
/// Kept as one widget so the two buttons cannot drift apart between screens —
/// the ICT tables had tinted square buttons while the Admin Panel had bare
/// icons, and only one of them had tooltips.
class RowActionButtons extends StatelessWidget {
  const RowActionButtons({
    super.key,
    required this.onEdit,
    this.onDelete,
    this.editTooltip = 'Edit',
    this.deleteTooltip = 'Delete',
    this.deleteIcon = Icons.delete_outline_rounded,
    this.accent,
  });

  final VoidCallback onEdit;

  /// Null hides the second button, for tables that only support editing.
  final VoidCallback? onDelete;
  final String editTooltip;
  final String deleteTooltip;
  final IconData deleteIcon;

  /// Tint for the edit button; defaults to the app's blue.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final edit = accent ?? context.colors.accentLightBlue;
    // Matches the Admin Panel's `_tableActionButton` exactly — 6px padding,
    // 15px icon, a 0.1 fill with a 0.25 border at radius 6 — so every table in
    // the app renders the same pair.
    Widget button(
            IconData icon, Color color, String tooltip, VoidCallback onTap) =>
        Tooltip(
          message: tooltip,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: color.withOpacity(0.25), width: 0.8),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
            ),
          ),
        );

    return Row(mainAxisSize: MainAxisSize.min, children: [
      button(Icons.edit_rounded, edit, editTooltip, onEdit),
      if (onDelete != null) ...[
        const SizedBox(width: 6),
        button(deleteIcon, context.colors.dangerRed, deleteTooltip, onDelete!),
      ],
    ]);
  }
}
