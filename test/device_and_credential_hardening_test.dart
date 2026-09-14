import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final creds = _read('lib/core/secure_credentials.dart');
  final deviceDart = _read('lib/core/device_id.dart');
  final deviceSql =
      _read('migrations/032_only_approved_machines_may_sign_in.sql');
  final rlsSql = _read('migrations/033_rls_on_the_last_five_tables.sql');

  group('a saved password goes to Windows Credential Manager', () {
    test('DPAPI holds it, not SharedPreferences', () {
      // ⚠️ What this replaced: the password was XOR-ed against a SHA-256
      // digest and written to SharedPreferences — a plain JSON file in the
      // roaming profile. XOR with a repeating key is not encryption, and the
      // key derived from an APP_SECRET whose fallback was a string literal in
      // that same file. Every unbuilt-with-dart-define copy shipped the same
      // secret, and the file could be carried to another machine and read.
      // ⚠️ Not flutter_secure_storage: its Windows plugin needs the Visual
      // Studio ATL component, absent from the default C++ workload, and the
      // build failed with "Cannot open include file: 'atlstr.h'". The same
      // DPAPI is called directly instead, with no native dependency.
      expect(creds, contains('WindowsCredentialStore.write'));
      expect(creds, contains('WindowsCredentialStore.read'));
      final store = _read('lib/core/windows_credential_store.dart');
      expect(store, contains('ProtectedData]::Protect'));
      expect(store, contains('DataProtectionScope]::CurrentUser'));
    });

    test('the XOR scheme is gone entirely', () {
      // ⚠️ Comment lines stripped: the note explaining WHY it was removed
      // names the old symbols, and a plain search matched its own
      // documentation.
      final code = creds
          .split(RegExp(r'\r?\n'))
          .where((l) =>
              !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('*'))
          .join(' ');
      for (final trace in const [
        '_encrypt(',
        '_decrypt(',
        '_deriveKey(',
        'APP_SECRET',
        'DO-NOT-USE-IN-PROD',
      ]) {
        expect(code.contains(trace), isFalse,
            reason: '"$trace" is still in the credential store');
      }
    });

    test('an old weak blob is deleted, never migrated', () {
      // ⚠️ Migrating it would mean decrypting the weak value to re-encrypt
      // it. The officer types the password once instead, and the blob goes.
      expect(creds, contains("prefs.remove('\${keyPrefix}_password_enc')"));
    });

    test('the e-mail stays in SharedPreferences', () {
      // It is not a secret, and the form needs it before any credential
      // prompt.
      expect(creds, contains("prefs.setString('\${keyPrefix}_email'"));
    });
  });

  group('only an approved machine may sign in', () {
    test('the check is inside auth.sign_in, not the client', () {
      // ⚠️ A check in Dart is a check the attacker controls — they are not
      // obliged to run our client.
      expect(deviceSql, contains('create or replace function auth.sign_in('));
      expect(deviceSql, contains('public.device_is_approved(v_device)'));
    });

    test('it wraps the original rather than editing it', () {
      // postgres/04_auth.sql re-creates auth.sign_in, so the rule must not
      // live there or a schema rebuild silently drops it.
      expect(deviceSql, contains('rename to sign_in_any_device'));
      expect(deviceSql, contains('auth.sign_in_any_device(p_identifier'));
    });

    test('an empty register allows every machine', () {
      // ⚠️ Applying this must not lock out a working system. Enforcement
      // starts when ICT approves the first PC.
      expect(deviceSql,
          contains('when not public.device_enforcement_active() then true'));
      expect(deviceSql, contains('DEVICE ENFORCEMENT IS OFF'));
    });

    test('a refusal is logged over a SEPARATE connection', () {
      // ⚠️ A plain INSERT before the RAISE is rolled back with it — measured:
      // the first version wrote the row, raised, and left zero rows. dblink
      // commits on its own connection and survives the caller's rollback.
      expect(deviceSql, contains('dblink_exec('));
      expect(deviceSql, contains('user=%s'),
          reason: 'without an explicit user libpq falls back to the OS '
              'account — on Windows that is SYSTEM, which is not a role');
    });

    test('the device id is derived, cached and never a credential', () {
      expect(deviceDart, contains('MachineGuid'));
      expect(deviceDart, contains('sha256'));
      // It identifies the PC; the password and OTP still authenticate.
      expect(deviceDart, contains('not a secret'));
    });

    test('an unidentifiable machine does not break the app', () {
      // Empty is what an unreadable GUID sends; an empty register allows it.
      expect(deviceDart, contains("_cached = '';"));
    });
  });

  group('every table carries Row-Level Security', () {
    test('the last five were closed', () {
      for (final t in const [
        'hold_reasons',
        'package_categories',
        'storage_rates',
        'app_migration_flags',
        'sr_number_migration_log',
      ]) {
        expect(rlsSql, contains(t), reason: '$t is not covered');
      }
    });

    test('reading reference data stays open to every officer', () {
      // ⚠️ An officer who cannot read hold_reasons cannot fill in the form,
      // and a locked rate table breaks the storage charge on every screen.
      expect(rlsSql, contains('for select using (true)'));
    });

    test('writing the storage rate is ICT only', () {
      // It sets the daily charge for every yard, and yard_app could INSERT.
      expect(rlsSql, contains('_ict_insert'));
      expect(rlsSql, contains('public.auth_user_is_ict()'));
    });

    test('separate policies per command, not one FOR ALL', () {
      // ⚠️ A single `for all` policy also governs SELECT, and its USING
      // clause would hide these rows from everyone who is not ICT.
      expect(rlsSql, contains('for insert'));
      expect(rlsSql, contains('for update'));
      expect(rlsSql, contains('for delete'));
    });

    test('the migration proves the boundary both ways', () {
      expect(rlsSql,
          contains('a yard officer can still set the storage rate'));
      expect(rlsSql, contains('these tables still have no RLS'));
    });
  });
}
