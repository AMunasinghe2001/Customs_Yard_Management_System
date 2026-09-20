import 'package:flutter/material.dart';

import 'app_dialog.dart';
import '../core/theme.dart';
import '../core/update_check.dart';
import 'styled_form_dialog.dart';

/// The update the app found at startup, or null while there is none.
///
/// ⚠️ A plain [ValueNotifier], not a provider. Signing out rebuilds the whole
/// ProviderScope (core/session_reset.dart), and a notice about the INSTALLED
/// SOFTWARE has nothing to do with who is signed in — it must survive a sign
/// out, a lock, and a portal switch, because the update is still there
/// afterwards. Kept outside the container, it does.
final ValueNotifier<AvailableUpdate?> availableUpdate =
    ValueNotifier<AvailableUpdate?>(null);

/// Set when the officer chooses "Later", so the strip stops nagging for the
/// rest of this run.
///
/// ⚠️ Deliberately NOT remembered across restarts. A skipped update comes
/// back next time the app opens, which is the point: a branch that keeps
/// dismissing it should keep being asked, or the yards drift apart on
/// versions and the database ends up older than half of them.
final ValueNotifier<bool> updateDismissed = ValueNotifier<bool>(false);

/// A strip across the top of the app when a newer release is published.
///
/// ⚠️ A STRIP, not a dialog, and never a forced install. An officer in the
/// middle of registering a consignment must not be stopped by a software
/// notice — the app still works, it is simply not the newest build. They
/// update when the desk is clear, which for a customs yard is the only time
/// it can safely happen.
///
/// Shaped like [OfflineBanner] on purpose: the two never show together in
/// practice, and one strip design is one thing for an officer to learn.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: ValueListenableBuilder<AvailableUpdate?>(
          valueListenable: availableUpdate,
          builder: (context, update, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: updateDismissed,
              builder: (context, dismissed, __) {
                final show = update != null && !dismissed;
                return AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  offset: show ? Offset.zero : const Offset(0, -1),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: show ? 1 : 0,
                    child: show
                        ? _Bar(update: update)
                        : const SizedBox(width: double.infinity),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.update});

  final AvailableUpdate update;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Gold, not red: nothing is wrong, there is simply something newer.
    final accent = colors.primaryGold;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: accent,
          child: Row(children: [
            Icon(Icons.system_update_alt_rounded,
                size: 18, color: colors.primaryNavy),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Version ${update.version} is available'
                '${update.sizeLabel.isEmpty ? '' : ' · ${update.sizeLabel}'}',
                style: TextStyle(
                    color: colors.primaryNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () => showUpdateDialog(context, update),
              style: TextButton.styleFrom(
                  foregroundColor: colors.primaryNavy,
                  padding: const EdgeInsets.symmetric(horizontal: 14)),
              child: const Text('What\'s new',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
            const SizedBox(width: 6),
            ElevatedButton.icon(
              onPressed: () => openUpdateDownload(update.downloadUrl),
              icon: const Icon(Icons.download_rounded, size: 16),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primaryNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              label: const Text('Update',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
            IconButton(
              tooltip: 'Not now',
              onPressed: () => updateDismissed.value = true,
              icon: Icon(Icons.close_rounded,
                  size: 18, color: colors.primaryNavy),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The release notes, and what installing actually involves.
///
/// ⚠️ It says the app must be CLOSED. The installer replaces
/// cus_yard_management.exe, and Windows refuses to overwrite a running
/// binary — an officer who leaves the app open sees the setup fail for a
/// reason it will not explain.
Future<void> showUpdateDialog(
    BuildContext context, AvailableUpdate update) async {
  await showAppDialog<void>(
    context: context,
    builder: (ctx) => StyledFormDialog(
      label: 'SOFTWARE UPDATE',
      title: 'Version ${update.version}',
      icon: Icons.system_update_alt_rounded,
      width: 520,
      actions: [
        TextButton(
          onPressed: () {
            updateDismissed.value = true;
            Navigator.pop(ctx);
          },
          child: const Text('Not now'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: ctx.colors.primaryGold,
            foregroundColor: ctx.colors.primaryNavy,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download update',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          onPressed: () {
            openUpdateDownload(update.downloadUrl);
            Navigator.pop(ctx);
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (update.notes.isNotEmpty) ...[
            Text('What changed',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: ctx.colors.textMuted)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(update.notes,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: ctx.colors.textSecondary)),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: ctx.colors.warningAmber.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: ctx.colors.warningAmber.withOpacity(0.4)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded,
                  size: 15, color: ctx.colors.warningAmber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The download opens in your browser. CLOSE this app before '
                  'running the setup — Windows cannot replace the program '
                  'while it is open. Your settings and the .env file are kept.',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: ctx.colors.textSecondary),
                ),
              ),
            ]),
          ),
        ],
      ),
    ),
  );
}
