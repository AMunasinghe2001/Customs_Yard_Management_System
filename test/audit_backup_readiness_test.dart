import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The audit trail's guarantees, checked against the migration that makes
/// them. The live-database probes live in `tool/audit_backup_readiness.py`;
/// these run on every `flutter test`, so a migration edited to relax one of
/// these fails in CI rather than waiting for someone to run the audit.
void main() {
  final sql = File('postgres/53_audit_append_only.sql').readAsStringSync();

  group('audit_logs is append-only', () {
    test('the FOR ALL policy that allowed edits is dropped', () {
      // ⚠️ audit_logs was in the generic yard-scoped table list, so it got
      // `create policy yard_all ... for all` — the same policy as `packages`.
      // FOR ALL includes UPDATE and DELETE, so an officer could rewrite the
      // rows recording what they had just done.
      expect(sql, contains('drop policy if exists yard_all'));
    });

    test('only INSERT and SELECT policies are created', () {
      expect(sql, contains('create policy audit_insert'));
      expect(sql, contains('create policy audit_select'));
      // With RLS on and no policy for a command, that command is denied — so
      // the absence of these is the enforcement, and it must stay absent.
      expect(sql, isNot(contains('create policy audit_update')));
      expect(sql, isNot(contains('create policy audit_delete')));
      expect(RegExp(r'create policy \w+ on public\.audit_logs\s+for all')
          .hasMatch(sql), isFalse);
    });

    test('UPDATE, DELETE and TRUNCATE each have a trigger', () {
      // Triggers, not policies, are what actually holds: the app connects as
      // a superuser, which bypasses RLS and grants entirely.
      expect(sql, contains('create trigger audit_logs_no_update'));
      expect(sql, contains('create trigger audit_logs_no_delete'));
      expect(sql, contains('create trigger audit_logs_no_truncate'));
    });

    test('TRUNCATE is guarded at STATEMENT level', () {
      // ⚠️ TRUNCATE fires no row triggers and is not a DELETE, so the two
      // above miss it — and it empties the whole table in one statement.
      // Verified before the fix: `truncate audit_logs` succeeded as superuser.
      final i = sql.indexOf('create trigger audit_logs_no_truncate');
      expect(i, greaterThan(-1));
      final decl = sql.substring(i, i + 200);
      expect(decl, contains('before truncate'));
      expect(decl, contains('for each statement'),
          reason: 'a row-level trigger never fires for TRUNCATE');
    });

    test('force row level security binds the table owner too', () {
      expect(sql, contains('force row level security'));
    });

    test('write privileges are revoked as well', () {
      expect(sql, contains('revoke update, delete, truncate'));
    });
  });

  group('retention is the one sanctioned deletion', () {
    test('the purge announces itself and the trigger recognises only that', () {
      expect(sql, contains("set_config('app.audit_purge', 'on'"));
      expect(sql, contains("current_setting('app.audit_purge', true) = 'on'"));
      // Only DELETE is let through, never UPDATE — retention removes old rows,
      // it never edits one.
      expect(sql, contains("and TG_OP = 'DELETE'"));
    });

    test('the purge records its own run', () {
      // ⚠️ Otherwise retention and tampering look identical when someone later
      // asks why a month is missing.
      final i = sql.indexOf('function public.purge_old_audit_logs');
      expect(i, greaterThan(-1));
      final body = sql.substring(i, sql.indexOf(r'$fn$;', i));
      expect(body, contains('Audit retention purge'));
      expect(body, contains('deleted_rows'));
    });

    test('the window is still 365 days', () {
      expect(sql, contains("interval '365 days'"));
    });
  });

  group('what every entry carries', () {
    test('client metadata columns are added', () {
      for (final col in ['client_addr', 'client_host', 'app_name', 'db_user']) {
        expect(sql, contains(col));
      }
    });

    test('metadata is stamped by a trigger, not by the caller', () {
      // A caller can neither forge these nor forget them.
      expect(sql, contains('create trigger audit_logs_stamp'));
      expect(sql, contains('inet_client_addr()'));
      expect(sql, contains('before insert on public.audit_logs'));
    });

    test('an entry cannot be attributed to another user', () {
      // ⚠️ The policy says this too, but a superuser ignores policies — and
      // the app is one. Verified: acting as an officer, an insert naming
      // another user's id was accepted until this went into the trigger.
      expect(sql,
          contains('cannot write an entry attributed to another user'));
      expect(sql, contains('new.user_id <> auth.uid()'));
    });
  });

  group('the events that were never logged', () {
    test('failed logins are recorded, including for unknown accounts', () {
      final i = sql.indexOf('function auth.record_failed_login');
      expect(i, greaterThan(-1));
      final body = sql.substring(i, sql.indexOf(r'$fn$;', i));
      expect(body, contains('insert into public.audit_logs'));
      expect(body, contains('Login failed'));
      expect(body, contains('account locked'));
      // Someone guessing addresses is exactly what a trail should show.
      expect(body, contains('account_exists'));
    });

    test('logging a failed login cannot break logging in', () {
      // ⚠️ audit_logs.user_id is an FK to PROFILES. An auth user with no
      // profile made the insert violate it, and because the insert runs
      // inside record_failed_login the violation propagated out and failed
      // the whole sign-in attempt.
      final i = sql.indexOf('function auth.record_failed_login');
      final body = sql.substring(i, sql.indexOf(r'$fn$;', i));
      expect(body, contains('v_has_profile'));
      expect(body, contains('from public.profiles p where p.id = v_user_id'));
    });

    test('privilege changes are caught by a trigger, not by call sites', () {
      // Role is changed by a plain UPDATE from several screens, so there is no
      // single call site — and a change made in pgAdmin must be caught too.
      expect(sql, contains('create trigger profiles_audit_privilege'));
      expect(sql, contains('after update on public.profiles'));
      for (final col in ['role', 'is_active', 'yard', 'directorate']) {
        expect(sql, contains("new.$col is distinct from old.$col"));
      }
    });

    test('a privilege change records who did it, not who it was done to', () {
      final i = sql.indexOf('function public.profiles_audit_privilege_change');
      final body = sql.substring(i, sql.indexOf(r'$fn$;', i));
      expect(body, contains('auth.uid()'));
      expect(body, contains('subject_id'));
    });

    test('an ordinary edit is not logged as a privilege change', () {
      final i = sql.indexOf('function public.profiles_audit_privilege_change');
      final body = sql.substring(i, sql.indexOf(r'$fn$;', i));
      expect(body, contains("if v_changes = '{}'::jsonb then"));
    });
  });

  group('backup readiness', () {
    test('the backup script verifies what it writes', () {
      final s = File('tool/backup_database.ps1').readAsStringSync();
      // ⚠️ A backup nobody has restored is a guess.
      expect(s, contains('pg_restore'));
      expect(s, contains('--list'));
      expect(s, contains('audit_logs'),
          reason: 'a dump missing the trail would look like a success');
    });

    test('old backups are retired only after the new one is verified', () {
      // Anchor on the SECTION banners, not the first mention of each word —
      // both appear earlier in the header comment, which put "Retention"
      // before "Verify" and made this compare the wrong two positions.
      final s = File('tool/backup_database.ps1').readAsStringSync();
      final verify = s.indexOf('# ── Verify');
      final retention = s.indexOf('# ── Retention');
      expect(verify, greaterThan(-1));
      expect(retention, greaterThan(verify),
          reason: 'a failed run must never leave you with nothing');
    });

    test('the script does not assume pg_dump is on PATH', () {
      // It is not, on this machine: PostgreSQL was unpacked, not installed.
      final s = File('tool/backup_database.ps1').readAsStringSync();
      expect(s, contains('Resolve-PgTool'));
    });

    test('backups, retention, PITR and a restore drill are documented', () {
      final d = File('postgres/SECURITY.md').readAsStringSync();
      expect(d, contains('Point-in-Time Recovery'));
      expect(d, contains('recovery_target_time'));
      expect(d, contains('archive_mode'));
      expect(d, contains('Retention schedule'));
      expect(d, contains('Restore drill'));
      expect(d, contains('pg_basebackup'));
    });
  });
}
