import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A log row must say what was true WHEN the action happened.
///
/// ⚠️ `audit_logs` stored only user_id, and the Activity Log read the role by
/// joining profiles — so it always showed the role the person holds TODAY.
/// Promote an officer to SDDC and every action they ever took retroactively
/// became an SDDC action: the trail claimed a yard administrator did work an
/// officer did, and the promotion date vanished from the history.
void main() {
  final sql =
      File('migrations/029_audit_rows_keep_the_role_of_the_day.sql')
          .readAsStringSync();

  group('the row carries its own role', () {
    test('there is a column for it', () {
      expect(sql, contains('add column if not exists actor_role text'));
    });

    test('a TRIGGER fills it, not the call sites', () {
      // ⚠️ recordLog is one of several writers — the failed-login function,
      // the privilege trigger and assorted services all insert here. A column
      // filled by the caller is a column that is sometimes empty.
      expect(sql, contains('audit_logs_stamp_actor_role'));
      expect(sql, contains('before insert on public.audit_logs'));
    });

    test('the backfill reads the ruling out of the right place', () {
      // ⚠️ `from` is nested inside `role`:
      // {"role": {"to": "admin", "from": "officer"}}. Reading details->>'from'
      // found nothing, so the first run marked all 1010 rows as guesses while
      // the evidence was sitting right there. 80 rows came back once the path
      // was right.
      expect(sql, contains("pc.details->'role'->>'from'"));
    });

    test('a guessed role is marked as one', () {
      // Past roles can only be recovered where a Privilege change entry
      // exists. Presenting the rest as equally certain would be a worse lie
      // than the one being fixed.
      expect(sql, contains('actor_role_inferred'));
    });

    test('only the UPDATE guard is stood down, and always restored', () {
      // ⚠️ Three separate guards protect this table. Adding a missing column
      // is the one legitimate reason to touch history — the action, actor and
      // timestamp are not altered — and the guard goes back on even if the
      // backfill throws.
      expect(sql, contains('disable trigger audit_logs_no_update'));
      expect(sql, contains('exception when others then'));
      expect(sql.split('enable trigger audit_logs_no_update').length - 1, 2,
          reason: 'the guard must be restored on the error path too');
    });

    test('the migration proves a promotion cannot rewrite history', () {
      // It stamps a row, changes the role, and re-reads the row.
      expect(sql, contains('the promotion rewrote history'));
    });
  });

  group('the app reads the stamped role', () {
    test('the model prefers actor_role over the joined profile', () {
      final models = File('lib/models/models.dart').readAsStringSync();
      expect(models, contains("(json['actor_role'] as String?) ??"));
    });

    test('the filter matches what the column shows', () {
      // ⚠️ Filtering on profiles.role while displaying actor_role would make
      // the two disagree: picking "Officer" would hide the very rows labelled
      // OFFICER, because that person is an SDDC today.
      final services = File('lib/services/services.dart').readAsStringSync();
      expect(services, contains("query.eq('actor_role', role)"));
      expect(services.contains("query.eq('profiles.role', role)"), isFalse,
          reason: 'the filter and the display would disagree');
    });
  });
}
