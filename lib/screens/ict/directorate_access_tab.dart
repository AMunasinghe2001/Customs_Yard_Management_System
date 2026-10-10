import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/account_cells.dart';
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

  /// Turn a deactivated directorate account back on.
  ///
  /// ⚠️ Goes through toggleUserStatus, which routes a reactivation to the
  /// `reactivate_account` function — that resets the dormancy clock in the
  /// same statement. Writing `is_active = true` directly would wake the
  /// account with a 30-day-old last_sign_in_at still on it, and the very next
  /// sweep would switch it straight back off.
  Future<void> _confirmReactivate(
      BuildContext context, WidgetRef ref, ProfileModel account) async {
    final portal = kDirectorateRoleNames[account.role] ?? account.role;
    final dormant = account.deactivatedReason == 'dormant';

    final ok = await showIctDialog<bool>(
      context: context,
      builder: (ctx) => StyledFormDialog(
        label: 'REACTIVATE',
        title: 'Restore access for this account',
        icon: Icons.check_circle_outline_rounded,
        headerAccentColor: accent,
        erp: true,
        width: 520,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          const Gap(8),
          StyledDialogPrimaryButton(
            erp: true,
            accentColor: accent,
            labelText: 'Reactivate',
            icon: Icons.check_circle_outline_rounded,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Kv(label: 'Portal', value: portal),
            _Kv(label: 'Account', value: account.fullName),
            const Gap(14),
            Text(
              dormant
                  ? 'This account was switched off automatically after 30 days '
                      'without a sign-in. Reactivating restores access and '
                      'restarts that clock, so it will not be switched off '
                      'again straight away.'
                  : 'This account was deactivated by hand. Reactivating '
                      'restores access immediately.',
              style: TextStyle(
                  color: context.colors.textMuted, fontSize: 12, height: 1.5),
            ),
            const Gap(10),
            // ⚠️ Say what this does NOT do. The password is untouched, so an
            // account whose password has also expired still needs a reset —
            // two different problems that look the same from the table.
            Text(
              'The password is not changed. If it has also expired, use '
              'Reset access afterwards.',
              style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 12,
                  height: 1.5,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      await ref
          .read(ictServiceProvider)
          .toggleUserStatus(account.id, true, staffName: account.fullName);
      ref.invalidate(directorateAccountsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ ${account.fullName} reactivated'),
          backgroundColor: context.colors.successGreen,
        ));
      }
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _confirmReset(
      BuildContext context, WidgetRef ref, ProfileModel account) async {
    final portal = kDirectorateRoleNames[account.role] ?? account.role;

    final ok = await showIctDialog<bool>(
      context: context,
      builder: (ctx) => StyledFormDialog(
        label: 'RESET ACCESS',
        title: 'Reissue sign-in details',
        icon: Icons.key_rounded,
        headerAccentColor: accent,
        erp: true,
        width: 520,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          const Gap(8),
          // The same footer button every other ICT form ends with -- this one
          // was a raw ElevatedButton, so it was the only confirm button in
          // the console at a different height and radius.
          StyledDialogPrimaryButton(
            erp: true,
            accentColor: accent,
            labelText: 'Send new details',
            icon: Icons.send_rounded,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StyledFormSection(
              erp: true,
              accentColor: accent,
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
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              // ⚠️ Was absent, so the columns were squeezed to whatever width
              // the window gave and the Access column — now carrying
              // Reactivate as well as Reset access — was the one that lost
              // out. This table has only FIVE columns, so it needs far less
              // than the Staff register: 302 fixed (Status 112 + Access 170 +
              // margins 40) plus spacing, and ~140px each for the three
              // flexible ones. 834 covers it, and the table has ~858px even
              // at the 1180px minimum window — so no scrollbar at any size.
              minWidth: 834,
              headingRowHeight: kIctHeadingHeight,
              dataRowHeight: kIctRowHeight,
              isHorizontalScrollBarVisible: false,
              empty: const EmptyTableState(
                icon: Icons.vpn_key_outlined,
                message: 'No directorate accounts',
                subtitle: 'Directorate accounts appear here once they exist.',
              ),
              columns: [
                ictCol('Directorate', size: ColumnSize.M),
                ictCol('Account', size: ColumnSize.L),
                // ⚠️ NOT the username. It is half of a working credential
                // for an account a whole directorate signs in with, and this
                // table is read on an office monitor with people walking past
                // it. What ICT actually needs here is whether the password is
                // near its rotation — the reason someone gets locked out and
                // asks for a reset in the first place.
                ictCol('Password', size: ColumnSize.M),
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
                    DataCell(PasswordAgeCell(profile: a)),
                    // ⚠️ The shared status, not a hand-rolled Active/Inactive.
                    // This said only "Inactive" for an account the 30-day
                    // sweep had switched off, so ICT could not tell a
                    // deliberate deactivation from a dormant one — and the
                    // Staff table one tab away was already making that
                    // distinction.
                    DataCell(Center(
                      child: Builder(builder: (context) {
                        // ⚠️ accountStatusOf for the ANSWER, IctStatusPill for
                        // the CHROME — the same split the Staff table uses.
                        // AccountStatusChip draws its own container, so using
                        // it here would have given this one table a different
                        // pill from the rest of the console.
                        final st = accountStatusOf(context, a);
                        return IctStatusPill(
                          label: st.label,
                          color: st.color,
                          tooltip: st.tooltip,
                        );
                      }),
                    )),
                    DataCell(Center(
                      child: a.isActive
                          ? IctGhostButton(
                              label: 'Reset access',
                              icon: Icons.key_rounded,
                              accent: accent,
                              dense: true,
                              onPressed: () => _confirmReset(context, ref, a),
                            )
                          // ⚠️ A deactivated account had NOTHING here: "Reset
                          // access" was greyed out (correctly — the
                          // credentials would not work) and no other action
                          // was offered, so a directorate account switched off
                          // by the dormancy sweep was stranded with no way
                          // back. The Staff table has had a reactivate button
                          // all along; this table simply never grew one.
                          : IctGhostButton(
                              label: 'Reactivate',
                              icon: Icons.check_circle_outline_rounded,
                              accent: context.colors.successGreen,
                              dense: true,
                              onPressed: () =>
                                  _confirmReactivate(context, ref, a),
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

/// The key/value line inside the reset confirmation.
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
