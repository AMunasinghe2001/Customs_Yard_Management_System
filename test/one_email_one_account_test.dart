import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Signing up on a second portal must not TAKE OVER an existing account.
///
/// ⚠️ Observed on the live server. An ICT account was created with one
/// e-mail; a Central Disposal account was then created with the SAME e-mail
/// and it "worked" — because `sr_auth.sign_up` correctly refused the duplicate,
/// the app caught `user_already_exists`, signed in as the existing account,
/// and upserted the new role over it. One e-mail, one id: the ICT account
/// became a Disposal account and ICT ceased to exist entirely.
///
/// That is privilege escalation through a sign-up form. Anyone who knows an
/// officer's address and password could re-point their account at whichever
/// portal they chose — and the officer would simply find themselves locked
/// out of their own directorate.
void main() {
  final svc = File('lib/services/services.dart').readAsStringSync();

  group('one e-mail holds one account', () {
    test('the repair branch only runs when the role is unchanged', () {
      // ⚠️ The branch itself is legitimate: an account whose sr_auth.users row
      // was created but whose profile write then failed is repaired by
      // signing in and re-writing the profile. It is only valid when the
      // role being written is the role already there.
      expect(svc, contains("existingRole != role"),
          reason: 'the role is not compared, so any portal can take over');
      expect(svc, contains('in a '),
          reason: 'the refusal must say WHY, not just fail');
    });

    test('it reads the role BEFORE writing the profile', () {
      // Reading it afterwards would be reading back what was just
      // overwritten — the check has to happen while the old role is still
      // there to see.
      final branch = svc.indexOf('if (exists) {');
      expect(branch, greaterThan(-1));
      final read = svc.indexOf("select('role')", branch);
      final write = svc.indexOf("from('profiles').upsert(", branch);
      expect(read, greaterThan(-1), reason: 'the existing role is never read');
      expect(write, greaterThan(read),
          reason: 'the profile is written before the role is checked');
    });

    test('a refused takeover does not leave the session signed in', () {
      // The branch signs in to inspect the account. Refusing without signing
      // out again would leave the caller holding a live session for an
      // account they were just told they may not touch.
      final branch = svc.indexOf('if (exists) {');
      final refusal = svc.indexOf('An account already exists for this e-mail',
          branch);
      expect(refusal, greaterThan(-1));
      final before = svc.substring(branch, refusal);
      expect(before, contains('signOut()'),
          reason: 'a refused takeover keeps the session alive');
    });

    test('the other two creation paths already refuse outright', () {
      // ICT creating an officer, and ICT creating a directorate account,
      // both reject a duplicate e-mail rather than adopting the account.
      expect("throw Exception('This email is already registered.')"
              .allMatches(svc)
              .length,
          2,
          reason: 'an admin-driven creation must never adopt an account');
    });
  });
}
