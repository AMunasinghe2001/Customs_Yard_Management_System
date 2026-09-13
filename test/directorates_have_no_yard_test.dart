import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A directorate is not inside a yard.
///
/// ⚠️ `profiles.yard` defaulted to 'GL1', so every account created without an
/// explicit yard silently became a Grey Line 1 account — ICT, Valuation,
/// Appeal, Central Disposal and Top Management included. The Activity Log then
/// printed "Grey Line 1" beside an ICT sign-in, which is simply untrue: those
/// officers work in their directorate, and yard staff are separate people.
///
/// A directorate touches a yard only through the SR records it reads, and that
/// link is carried by the PACKAGE's yard — never by the officer's.
void main() {
  final sql =
      File('migrations/027_directorates_do_not_belong_to_a_yard.sql')
          .readAsStringSync();

  group('the database stops assigning one', () {
    test('the default is removed, not changed', () {
      // A yard account is always created with an explicit yard, so the
      // default only ever served to put a wrong answer on directorate rows.
      expect(sql, contains('alter column yard drop default'));
    });

    test('a check constraint keeps it that way', () {
      // ⚠️ A CHECK rather than a trigger: it states the rule where anyone
      // reading the table sees it, and a direct write cannot skip it.
      expect(sql, contains('profiles_directorate_has_no_yard'));
      expect(sql, contains('or yard is null'));
    });

    test('the migration proves the constraint bites', () {
      // Adding a constraint and asserting nothing would prove only that the
      // statement parsed.
      expect(sql, contains('check_violation'));
      expect(sql, contains('a directorate account can still be given a yard'));
    });

    test('yard staff keep theirs', () {
      // The column still has a job; this must not break it.
      expect(sql, contains('yard staff still do'));
    });
  });

  group('the app stops stamping one', () {
    final session = File('lib/core/app_session.dart').readAsStringSync();
    final services = File('lib/services/services.dart').readAsStringSync();

    test('there is a nullable yard for stamping', () {
      // ⚠️ currentYard falls back to the default code so SR numbers always
      // resolve — and that fallback was being written onto audit rows too.
      expect(session, contains('static String? get stampYard'));
      expect(session, contains('isYardBound ? currentYard : null'));
    });

    test('the audit log uses it', () {
      final at = services.indexOf("from('audit_logs').insert(");
      expect(at, greaterThan(-1));
      final insert = services.substring(at, at + 600);
      expect(insert, contains("'yard': AppSession.stampYard"),
          reason: 'a directorate sign-in is still logged against a yard');
    });
  });

  group('the existing trail is not rewritten', () {
    test('the column hides the yard for a directorate row instead', () {
      // ⚠️ audit_logs is append-only by trigger, and an audit trail that can
      // be edited afterwards is worth nothing — so the ~558 rows the old
      // default mislabelled STAY as they are. The column declines to repeat a
      // claim the role makes impossible rather than the history being
      // doctored to match.
      final logs =
          File('lib/screens/ict/activity_logs_tab.dart').readAsStringSync();
      expect(logs, contains('kDirectorateRoles'));
      expect(logs, contains('append-only'),
          reason: 'the reason the rows are left alone must be written down');
    });
  });

  group('a failed sign-in names the yard it targeted', () {
    final sql = File('migrations/028_failed_login_records_the_yard.sql')
        .readAsStringSync();

    test('the insert carries a yard', () {
      // ⚠️ record_failed_login inserted no yard at all, so every "Login
      // failed" row showed an em-dash — including attempts against yard
      // officers, who do belong to a yard. ICT could not tell which office an
      // attempt was aimed at.
      expect(sql, contains('insert into public.audit_logs (user_id, yard,'));
    });

    test("it is the TARGET account's yard, and only if it has one", () {
      // There is no session yet, so the attacker's yard is unknowable; the
      // useful fact is which account was being guessed at.
      expect(sql, contains("p.role in ('officer', 'admin')"));
    });

    test('a directorate attempt still records none', () {
      expect(sql, contains('it has none'));
    });

    test('the check matches rows by entity_id, not by time', () {
      // ⚠️ Both inserts land in one transaction with the same clock, so
      // "newest row" read the officer's row back for the directorate check
      // and reported a failure that was not real.
      expect(sql, contains('entity_id = v_dir_id::text'));
      expect(sql, contains('entity_id = v_officer_id::text'));
    });

    test('the self-check rows it leaves behind are marked', () {
      // audit_logs is append-only, so the check cannot tidy up after itself —
      // and a verification able to delete audit rows would be worse to own
      // than two labelled entries.
      expect(sql, contains('Migration 028 self-check'));
    });
  });

  group('the trail keeps what is worth auditing', () {
    test('session traffic is hidden by default, not dropped', () {
      // ⚠️ 690 of 1048 rows are sign-ins and sign-outs. What ICT opens this
      // page for is what somebody CHANGED — an SR edited, an appeal decided,
      // goods released, a privilege granted — and those 358 rows were buried
      // under the other 690.
      final services = File('lib/services/services.dart').readAsStringSync();
      expect(services, contains("query.not('entity_type', 'eq', 'auth')"));
      // ⚠️ Only when no Activity filter is chosen. "Who was in the system at
      // 3pm" is a real question an audit trail must answer — it is just not
      // the one the page opens with, so the rows stay reachable.
      expect(services, contains('if (entityType == null || entityType.isEmpty)'),
          reason: 'the filter could not bring the sign-in rows back');
    });

    test('the hidden rows are findable and the header does not lie', () {
      final tab =
          File('lib/screens/ict/activity_logs_tab.dart').readAsStringSync();
      // A bare "Auth" in the dropdown says nothing about what it holds.
      expect(tab, contains("return 'Sign-in / Sign-out'"));
      // ⚠️ A header promising "Every action" while hiding 690 rows would
      // leave an officer believing a quiet account really did nothing.
      expect(tab.contains("subtitle: 'Every action across all yards"), isFalse,
          reason: 'the header claims more than the page shows');
    });
  });
}
