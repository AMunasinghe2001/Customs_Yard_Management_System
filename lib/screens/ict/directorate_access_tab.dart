import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/empty_table_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/styled_form_dialog.dart';
import '../../widgets/tooltip_text.dart';
import 'ict_ui.dart';

/// Every directorate account is listed here, so ICT can reissue its sign-in
/// details when the holder cannot get in.
final directorateAccountsProvider =
    FutureProvider<List<ProfileModel>>((ref) async {
  ref.watch(staffRefreshProvider);
  return ref.read(ictServiceProvider).getDirectorateAccounts();
});

/// Bumped after a reset, so the list re-reads the new username.
final staffRefreshProvider = StateProvider<int>((ref) => 0);

/// Reissues the sign-in details for a directorate account.
///
/// A directorate account belongs to a POST, not a person: whoever holds it
/// next may never have signed in, and there is no personal mailbox to send a
/// self-service reset link to. So ICT generates a fresh username and password
/// and emails both to the address the account is registered to; the holder
/// signs in with them and changes both from their own profile.
///
/// Yard staff are deliberately absent — they reset their own password from the
/// login page.
class DirectorateAccessTab extends ConsumerWidget {
  final Color accent;
  const DirectorateAccessTab({super.key, required this.accent});

  Future<void> _confirmReset(
      BuildContext context, WidgetRef ref, ProfileModel account) async {
    final portal = kDirectorateRoleNames[account.role] ?? account.role;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StyledFormDialog(
        label: 'RESET ACCESS',
        title: 'Reissue sign-in details',
        icon: Icons.key_rounded,
        headerAccentColor: accent,
        width: 520,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          const Gap(8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: accent, foregroundColor: Colors.white),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send new details'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StyledFormSection(
              title: 'Account',
              icon: Icons.account_balance_rounded,
              children: [
                _Kv(label: 'Directorate', value: portal),
                _Kv(label: 'Account', value: account.fullName),
                _Kv(
                    label: 'Current username',
                    value: account.username?.isNotEmpty == true
                        ? account.username!
                        : '—'),
              ],
            ),
            const Gap(14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.warningAmber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: context.colors.warningAmber.withOpacity(0.35)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: context.colors.warningAmber),
                const Gap(10),
                Expanded(
                  child: Text(
                    'A new username and password will be generated and emailed '
                    'to this account. The current ones stop working at once, '
                    'so anyone signed in with them will have to sign in again.',
                    style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12.5,
                        height: 1.4),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    // Held before the await: the dialog's own context is gone by then.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final username = await ref
          .read(ictServiceProvider)
          .resetDirectorateCredentials(account.id);
      ref.read(staffRefreshProvider.notifier).state++;
      messenger.showSnackBar(SnackBar(
        // The username, never the password: that belongs in the mailbox, not
        // on an office monitor someone may be standing behind.
        content: Text('Sent. The new username is "$username".'),
        backgroundColor: context.colors.successGreen,
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: context.colors.dangerRed,
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(directorateAccountsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      // ⚠️ No page heading. The console's own header already names this
      // section and says what it is for, and a screen that repeats its title
      // twenty pixels below the first one is the surest sign of a page that
      // was designed on its own rather than as part of a console.
      child: async.when(
        loading: () => Center(child: CircularProgressIndicator(color: accent)),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.refresh(directorateAccountsProvider)),
        data: (accounts) => IctSectionCard(
          icon: Icons.vpn_key_rounded,
          title: 'Directorate Accounts',
          subtitle:
              'These belong to a post rather than a person, so ICT issues the '
              'credentials; yard staff reset their own from the login page.',
          badge: '${accounts.length} '
              '${accounts.length == 1 ? 'account' : 'accounts'}',
          fill: true,
          child: IctTableTheme(
            child: DataTable2(
              columnSpacing: 16,
              horizontalMargin: 20,
              fixedTopRows: 1,
              headingRowHeight: kIctHeadingHeight,
              dataRowHeight: kIctRowHeight,
              dividerThickness: 0,
              isHorizontalScrollBarVisible: false,
              empty: const EmptyTableState(
                icon: Icons.vpn_key_outlined,
                message: 'No directorate accounts',
                subtitle: 'Directorate accounts appear here once they exist.',
              ),
              columns: [
                ictCol('Directorate', size: ColumnSize.M),
                ictCol('Account', size: ColumnSize.L),
                ictCol('Username', size: ColumnSize.M),
                ictCol('Status',
                    size: ColumnSize.S,
                    fixedWidth: kIctPillWidth + 24,
                    center: true),
                ictCol('Access',
                    size: ColumnSize.S, fixedWidth: 170, center: true),
              ],
              rows: accounts.asMap().entries.map((entry) {
                final a = entry.value;
                return DataRow2(
                  color: ictRowColor(context, entry.key),
                  cells: [
                    DataCell(TooltipText(
                        kDirectorateRoleNames[a.role] ?? a.role,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.colors.textPrimary,
                            fontWeight: FontWeight.w700))),
                    DataCell(TooltipText(a.fullName,
                        overflow: TextOverflow.ellipsis)),
                    DataCell(TooltipText(
                        a.username?.isNotEmpty == true ? a.username! : '—',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.colors.accentLightBlue,
                            fontWeight: FontWeight.w600))),
                    DataCell(Center(
                      child: IctStatusPill(
                        label: a.isActive ? 'Active' : 'Inactive',
                        color: a.isActive
                            ? context.colors.successGreen
                            : context.colors.dangerRed,
                      ),
                    )),
                    DataCell(Center(
                      child: IctGhostButton(
                        label: 'Reset access',
                        icon: Icons.key_rounded,
                        accent: accent,
                        dense: true,
                        // A deactivated account cannot sign in at all, so
                        // reissuing its details would only send credentials
                        // that do not work.
                        onPressed: a.isActive
                            ? () => _confirmReset(context, ref, a)
                            : null,
                      ),
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ).animate().slideY(begin: 0.05, duration: 400.ms).fadeIn(),
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  final String label;
  final String value;
  const _Kv({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
