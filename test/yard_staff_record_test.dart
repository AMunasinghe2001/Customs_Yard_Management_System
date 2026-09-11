import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final admin = File('lib/screens/admin/admin_screen.dart').readAsStringSync();
  final services = File('lib/services/services.dart').readAsStringSync();

  test('the panel does not claim to manage officers', () {
    // Officer accounts are provisioned, posted and disabled by ICT — a yard
    // cannot create or edit one, so the old caption promised something the
    // page does not do.
    expect(admin, isNot(contains('Manage officers and system configuration')));
    expect(admin, contains('Yard staff record, warehouses, items and activity'));
  });

  test('the tab and the heading agree', () {
    expect(admin, contains("text: 'Yard Staff'"));
    expect(admin, contains("Text('Yard Staff',"));
    expect(admin, isNot(contains("Text('Officers & Admins',")));
  });

  test('the column shows the POST, not the permission level', () {
    // role has only 'admin' and 'officer', so a DC and an SDDC both rendered
    // as ADMIN — two different posts collapsed into one word.
    expect(admin, contains("Text('Job Role',"));
    expect(admin, contains('_JobRoleChip('));
    expect(admin, contains('profile.postShortTitle'));
    // The old chip read profiles.role and is gone, not merely unused.
    expect(admin, isNot(contains('class _RoleChip')));
  });

  test('"Disables In" is replaced by the service span', () {
    // It counted down to an automatic expiry — ICT's clock — and read
    // "Never" on every row in a yard.
    expect(admin, isNot(contains("Text('Disables In',")));
    expect(admin, contains("Text('Served in This Yard',"));
    expect(admin, contains('_ServedInYardCell('));
  });

  group('the service span is read per yard', () {
    test('it comes from the audit log, not from profiles', () {
      // profiles carries only is_active (where someone stands today) and
      // created_at (when the ACCOUNT was made) — neither answers "what
      // period did this member work in this yard".
      expect(services, contains('getYardServicePeriods('));
      expect(services, contains(".eq('entity_type', 'profile')"));
      expect(services, contains(".eq('yard', yard)"));
    });

    test('a transfer in or out bounds the stint', () {
      // GL1 → GL2 → GL1 is two separate stints here, and GL2's spell in
      // between is not this yard's business.
      expect(services, contains('transferred officer from'));
      expect(services, contains('joined'));
      expect(services, contains('left'));
    });

    test('the first activation and the last departure win', () {
      expect(services, contains('cur?.activatedAt ?? at'));
    });
  });

  test('members who have left are still listed', () {
    // The whole point: a yard needs to see who served here and when.
    expect(admin, contains('aHere != bHere'));
    expect(admin, contains('deactivatedAt'));
  });

  test('no dates is an em dash, never a guess', () {
    // Accounts provisioned before the log recorded these events have none,
    // and created_at is not the same as "started here".
    // An em dash for someone still here with no logged start; a transferred
    // member says so instead, because their stint demonstrably ended.
    expect(admin, contains("stillHere ? '—' : 'Transferred out'"));
  });

  group('a member who transferred away stays in this yard history', () {
    final providers = File('lib/core/providers.dart').readAsStringSync();

    test('the list is not limited to people posted here today', () {
      // profiles.yard holds ONE value — where someone is now — so an
      // officer moved GL1 → GL2 vanished from GL1's list, taking the record
      // of their service with them.
      expect(providers, contains('served.contains(p.id)'));
      expect(providers, contains('myYardServedIdsProvider'));
    });

    test('they do not read as ACTIVE in a yard they left', () {
      // The account is live — in another yard. Saying ACTIVE here would
      // claim they still work here.
      expect(admin, contains('class _YardStatusChip'));
      expect(admin, contains("Text('TRANSFERRED'"));
      expect(admin, contains('profile.yard != myYard'));
    });

    test('the Active/Inactive filter means "serving HERE"', () {
      expect(admin, contains('p.yard == myYard && p.isActive && !p.isExpired'));
    });
  });

  test('the staff columns share the slack', () {
    // Pinning the short columns pushed every spare pixel into one gap at
    // the end of the row, so only Status stays fixed.
    expect('fixedWidth'.allMatches(admin).length, greaterThan(0));
    expect(admin, contains("Text('Job Role',"));
    expect(admin, isNot(contains('fixedWidth: 120')));
  });

  group('a printed report says which yard it came from', () {
    final report = File('lib/services/report_service.dart').readAsStringSync();

    test('the yard is written the way an SR number writes it', () {
      // A yard code alone is ambiguous — NNR belongs to both CED and PSD —
      // and CED/GL2 is the form officers read off every SR number.
      expect(report, contains('static String? _yardLabel()'));
      expect(report, contains("'\$dir/\$yard'"));
    });

    test('it appears in the title, not only the small print', () {
      // A page separated from its stack has to say whose stock it lists.
      expect(report, contains("yard == null ? title : '\$title  —  \$yard'"));
    });

    test('a cross-yard portal prints no yard rather than a wrong one', () {
      expect(report, contains('if (yard.isEmpty) return null;'));
    });
  });

  group('the yard can actually READ its past staff', () {
    final mig =
        File('migrations/014_past_yard_staff_visible.sql').readAsStringSync();

    test('RLS admitted only the current yard, so the row was invisible', () {
      // The service dates come from audit_logs, which is already readable
      // per yard — but the NAME beside them lives in profiles, and that
      // row left GL1's result set the moment the officer transferred.
      expect(mig, contains('profile_served_in_my_yard'));
      expect(mig, contains('drop policy if exists yard_profiles_select'));
    });

    test('it opens only rows this yard has a history with', () {
      // Not "profiles across yards": the function matches the caller's OWN
      // yard against its OWN log.
      expect(mig, contains("l.yard = public.auth_user_yard()"));
      expect(mig, contains("l.entity_type = 'profile'"));
    });

    test('the lookup cannot recurse into profiles policies', () {
      // It is consulted BY a profiles policy — the 42P17 trap migrations
      // 006 and 007 removed.
      expect(mig, contains('security definer'));
    });
  });

  test('the yard page is not called the Admin Panel', () {
    // The ICT portal is THE Admin Panel — it provisions accounts for every
    // yard. This page configures one yard.
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    expect(shell, contains("'Yard Administration'"));
    expect(admin, contains("Text('Yard Administration',"));
    expect(admin, isNot(contains("Text('Admin Panel',")));
  });

  test('every report page carries the font that has an em dash', () {
    // Thirteen documents were bare, so those reports fell back to
    // Helvetica and printed a hollow box wherever the text said "—".
    final report = File('lib/services/report_service.dart').readAsStringSync();
    expect(report, isNot(contains('pw.Document();')));
    expect('pw.Document('.allMatches(report).length,
        equals('ThemeData.withFont('.allMatches(report).length));
  });
}