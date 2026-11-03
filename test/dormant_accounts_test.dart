import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// An account nobody signs into is the one worth stealing.
///
/// Migration 021 disables any account unused for 90 days — the same period as
/// the password rotation, since an officer away that long would have been
/// stopped at the password gate anyway. These assert the parts of the rule
/// that are easy to undo by accident.
void main() {
  final sql = File('migrations/021_dormant_accounts_are_disabled.sql')
      .readAsStringSync();
  // ⚠️ 022 corrects the COLUMN 021 read. Assertions about which clock the
  // rule consults belong against the current definition, not the first one.
  final fixed = File('migrations/022_dormancy_reads_the_right_clock.sql')
      .readAsStringSync();
  final svc = File('lib/services/services.dart').readAsStringSync();

  group('the dormancy rule', () {
    test('reuses is_active rather than inventing a second disabled flag', () {
      // Every sign-in path already refuses an inactive profile, and ICT
      // already has the button. A separate flag would mean two answers to
      // "can this account sign in" that can disagree.
      expect(sql, contains('set is_active = false'));
    });

    test('reads the sign-in clock, not the presence heartbeat', () {
      // ⚠️ The bug 022 fixes, and it disabled live accounts.
      //
      // `profiles.last_seen_at` is a PRESENCE heartbeat: signOut() and
      // setUserOffline() both null it ON PURPOSE, so the online list drops
      // somebody the moment they leave instead of ~90s later. 021 read it
      // as "when was this account last used", so ANY account whose holder
      // signed out tidily had a null there, fell back to created_at, and
      // was disabled as soon as the account was over 90 days old. An SDDC
      // account signed into minutes earlier read as dormant.
      //
      // sr_auth.users.last_sign_in_at is written by sr_auth.sign_in and nothing
      // clears it, which is exactly the question the rule asks.
      expect(fixed, contains('u.last_sign_in_at'),
          reason: 'dormancy is not reading the sign-in clock');
      expect(fixed.contains('coalesce(p.last_seen_at, p.created_at)'), isFalse,
          reason: 'the presence heartbeat is back in the dormancy test; an '
              'account that signed out cleanly will be disabled');
    });

    test('reactivation resets the clock the rule actually reads', () {
      // 021 reset last_seen_at — which 022 no longer consults, so waking an
      // account would not have stopped the next sweep disabling it again.
      final fn =
          fixed.substring(fixed.indexOf('function public.reactivate_account'));
      expect(fn, contains('set last_sign_in_at = now()'),
          reason: 'a reactivated account is dormant again immediately');
    });

    test('counts an account that has NEVER been used', () {
      // ⚠️ last_seen_at is null for a provisioned-but-unused account.
      // Treating null as "not dormant" would exempt exactly the accounts
      // this rule exists for.
      // A null clock means "never signed in", which is dormancy too — the
      // provisioned-but-unused account the rule most exists for.
      expect(fixed, contains('coalesce(u.last_sign_in_at, p.created_at)'),
          reason: 'a never-used account escapes the sweep');
    });

    test('records WHY the account was switched off', () {
      // Otherwise a dormancy switch-off is indistinguishable from ICT
      // deactivating someone deliberately.
      expect(sql, contains("deactivated_reason = 'dormant'"));
    });

    test('only ICT can reactivate', () {
      // The point of the rule: if the holder could wake it by signing in,
      // it would protect nothing — they are who we are unsure about.
      final fn =
          sql.substring(sql.indexOf('function public.reactivate_account'));
      expect(fn, contains('auth_user_is_ict()'));
      expect(fn, contains('insufficient_privilege'));
    });

    test('reactivation resets the clock', () {
      // ⚠️ Without this the woken account is still 90 days stale, and the
      // very next sweep turns it straight back off.
      final fn =
          fixed.substring(fixed.indexOf('function public.reactivate_account'));
      final body = fn.substring(0, fn.indexOf(r'$fn$;'));
      expect(body, contains('last_sign_in_at = now()'),
          reason: 'a reactivated account is dormant again immediately');
    });

    test('the sweep runs before the password is checked', () {
      // Running it after would let the first sign-in through.
      final fn = sql.substring(sql.lastIndexOf('function sr_auth.sign_in'));
      final sweep = fn.indexOf('disable_dormant_accounts()');
      final check = fn.indexOf('crypt(p_password');
      expect(sweep, greaterThan(-1), reason: 'sign_in never sweeps');
      expect(sweep, lessThan(check),
          reason: 'a dormant account gets one more sign-in');
    });

    test('the app wakes accounts through the function, not a flag write', () {
      // A plain is_active write leaves last_seen_at stale — see above.
      final fn = svc.indexOf('Future<void> toggleUserStatus');
      expect(fn, greaterThan(-1));
      final body = svc.substring(fn, fn + 1200);
      expect(body, contains("rpc('reactivate_account'"),
          reason: 'waking an account by flag alone re-disables it next sweep');

      // ⚠️ Both services must agree. IctService powers the Staff Register table
      // in the ICT Console where administrators reactivate yard officers.
      final fn2 = svc.indexOf('Future<void> toggleUserStatus', fn + 1);
      expect(fn2, greaterThan(-1), reason: 'IctService.toggleUserStatus must exist');
      final body2 = svc.substring(fn2, fn2 + 1200);
      expect(body2, contains("rpc('reactivate_account'"),
          reason: 'IctService must route reactivation to reactivate_account');
    });
  });

  group('the window is 30 days, not 90', () {
    final sql =
        File('migrations/026_dormancy_after_30_days.sql').readAsStringSync();

    test('the constant changed', () {
      expect(sql, contains('select 30'));
    });

    test('it is decoupled from the password rotation', () {
      // ⚠️ The two used to share the number 90, and the old comment said so —
      // but they answer different questions. A stale password is asked to
      // change; an unused account is switched off. Tying them together meant
      // one could not move without the other.
      expect(sql, contains('Deliberately shorter'));
    });

    test('the migration proves the boundary moved', () {
      // 31 days must be dormant and 29 must not — a migration that only
      // rewrites the constant proves nothing about what the rule now does.
      expect(sql, contains("interval '31 days'"));
      expect(sql, contains("interval '29 days'"));
    });

    test('what the officer reads says 30', () {
      final cells = File('lib/widgets/account_cells.dart').readAsStringSync();
      expect(cells, contains('not signed into for 30 days'));
      // ⚠️ And the PASSWORD tooltip beside it still says 90, because that
      // rule did not change.
      expect(cells, contains('90 days from the last change'));
    });
  });

  group('ICT can turn a dormant account back on', () {
    test('the button says what reactivating a dormant account does', () {
      // An unlabelled "Activate Account" gave no hint that the sweep — not a
      // person — switched it off, or that turning it on restarts that clock
      // rather than leaving it to switch itself off again.
      final ict =
          File('lib/screens/ict/ict_dashboard_screen.dart').readAsStringSync();
      // Whitespace-insensitive: dart format wraps this expression.
      final flat = ict.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, contains("deactivatedReason == 'dormant'"));
      expect(ict, contains('restarts'));
    });
  });

  group('a directorate account can be brought back too', () {
    final tab = File('lib/screens/ict/directorate_access_tab.dart')
        .readAsStringSync();

    test('there is a Reactivate action', () {
      // ⚠️ A deactivated directorate account had NOTHING to click: "Reset
      // access" was correctly greyed out (the credentials would not work) and
      // nothing else was offered, so an account the dormancy sweep switched
      // off was stranded. The Staff table one tab away had a reactivate
      // button all along.
      expect(tab, contains("label: 'Reactivate'"));
      expect(tab, contains('_confirmReactivate('));
    });

    test('it goes through the clock-resetting path', () {
      // Writing is_active = true directly would wake the account with a
      // 30-day-old last_sign_in_at and the next sweep would switch it off
      // again. toggleUserStatus routes a reactivation to reactivate_account.
      expect(tab, contains('toggleUserStatus(account.id, true'));
    });

    test('it shows DORMANT apart from a deliberate deactivation', () {
      // The hand-rolled Active/Inactive pill could not tell them apart.
      // accountStatusOf gives the ANSWER; IctStatusPill gives the chrome the
      // rest of the console uses. AccountStatusChip would have drawn its own
      // container and made this table the odd one out.
      expect(tab, contains('accountStatusOf(context, a)'));
      expect(tab, contains('IctStatusPill('));
      expect(tab.contains("label: a.isActive ? 'Active' : 'Inactive'"), isFalse,
          reason: 'the hand-rolled pill hides why the account is off');
    });

    test('the dialog says the password is untouched', () {
      // An expired password and a dormant account look identical in the
      // table; reactivating fixes only one of them.
      expect(tab, contains('The password is not changed'));
    });
  });

  group('the last column stays reachable on a small window', () {
    test('both ICT tables declare a minWidth wide enough to scroll', () {
      // ⚠️ data_table_2 SQUEEZES flexible columns to fit rather than
      // scrolling, so the rightmost column — Actions on Staff, Access on
      // Directorate, each holding the only reactivate button — was crushed
      // out of sight on a smaller screen instead of being scrolled to.
      // ⚠️ And not so wide that a MAXIMISED window scrolls either. 1400 was
      // my own overcorrection: it kept the last column reachable by forcing a
      // scrollbar at every size, including full screen. The balance is a
      // minimum that fits the columns tightly — text ellipsises, which is
      // fine — rather than one that reserves room they do not need.
      //
      // ⚠️ 760, not 1040. The sidebar takes ~200px, so at the app's
      // minimum window (~1024px) the table area is only ~800px — a 1040
      // minimum put the Actions column BEYOND it, which is the fault this
      // test exists to catch rather than a stricter version of the fix.
      final ict =
          File('lib/screens/ict/ict_dashboard_screen.dart').readAsStringSync();
      expect(ict, contains('minWidth: 760'));

      final tab = File('lib/screens/ict/directorate_access_tab.dart')
          .readAsStringSync();
      expect(tab, contains('minWidth: 834'),
          reason: 'this table had no minWidth at all');
    });
  });
}
