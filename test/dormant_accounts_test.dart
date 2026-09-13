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
      // auth.users.last_sign_in_at is written by auth.sign_in and nothing
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
      final fn = sql.substring(sql.lastIndexOf('function auth.sign_in'));
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
    });
  });
}
