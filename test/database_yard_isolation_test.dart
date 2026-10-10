import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration =
      File('migrations/003_database_yard_isolation.sql').readAsStringSync();
  final roleSetup = File('postgres/66_yard_app_role.sql').readAsStringSync();
  final boundary = File('migrations/005_restrict_yard_staff_at_database.sql')
      .readAsStringSync();
  final profileFix = File('migrations/006_profiles_policy_recursion_fix.sql')
      .readAsStringSync();
  final adminPolicyFix =
      File('migrations/007_drop_admin_profiles_policy.sql').readAsStringSync();
  final router = File('lib/core/router.dart').readAsStringSync();

  test('reporting views run as the caller, not postgres', () {
    expect(migration, contains('security_invoker = true'));
    expect(migration, contains("'warehouse_rows'"));
    expect(migration, contains("'forfeit_rows'"));
    expect(migration, contains("'disposition_rows'"));
    expect(migration, contains("'sr_financials'"));
  });

  test('operational tables force their existing yard RLS policies', () {
    expect(migration, contains('force row level security'));
    expect(migration, contains("'packages'"));
    expect(migration, contains("'tender_sales'"));
    expect(migration, contains("'financial_expenses'"));
  });

  test('yard isolation is dynamic, not a GL1/GL2-only condition', () {
    expect(migration, contains('row.yard = auth_user_yard()'));
    expect(migration, contains('ICT-created code'));
    expect(migration, isNot(contains("yard = 'GL1'")));
    expect(migration, isNot(contains("yard = 'GL2'")));
  });

  test('a restrictive database policy defeats legacy broad policies', () {
    expect(boundary, contains('as restrictive'));
    expect(boundary, contains('auth_user_is_yard_staff'));
    expect(boundary, contains('yard = public.auth_user_yard()'));
    expect(boundary, isNot(contains("yard = 'GL1'")));
    expect(boundary, isNot(contains("yard = 'GL2'")));
  });

  test('the profiles lookup cannot recursively call its own yard policy', () {
    expect(boundary, contains("c.table_name <> 'profiles'"));
    expect(profileFix, contains('drop policy if exists yard_staff_boundary'));
  });

  test('the application role is explicitly non-superuser and non-bypass', () {
    expect(roleSetup, contains('nosuperuser'));
    expect(roleSetup, contains('nobypassrls'));
    expect(roleSetup, contains('grant authenticated to yard_app'));
  });

  test('the base schema admin policy is dropped, not rewritten', () {
    // 002 removed cross-yard admin access and dropped auth_user_is_admin();
    // reviving the helper to break the recursion would re-open that hole.
    expect(adminPolicyFix,
        contains('drop policy if exists "Admins can manage all profiles"'));
    expect(adminPolicyFix,
        contains('drop function if exists public.auth_user_is_admin()'));
    expect(adminPolicyFix,
        isNot(contains('create policy "Admins can manage all profiles"')));
    expect(
        adminPolicyFix,
        isNot(
            contains('create or replace function public.auth_user_is_admin')));
  });

  test('no profiles policy may read profiles inline', () {
    // An inline read re-enters the policy being evaluated: error 42P17,
    // which fails every sign-in. Role checks go through SECURITY DEFINER.
    // 02_schema.sql is a stitched history, so the base schema still CREATEs
    // the recursive policy. What matters is that the drop comes after it, so
    // replaying the file end to end leaves the policy gone.
    final schema = File('postgres/02_schema.sql').readAsStringSync();
    final lastCreate =
        schema.lastIndexOf('CREATE POLICY "Admins can manage all profiles"');
    final lastDrop = schema
        .lastIndexOf('drop policy if exists "Admins can manage all profiles"');
    expect(lastCreate, isNot(-1));
    expect(lastDrop, isNot(-1));
    expect(lastDrop, greaterThan(lastCreate));
    expect(adminPolicyFix, contains('42P17'));
  });

  test('a failed session check ends the session instead of looping', () {
    // Bouncing to '/' while the check still fails on '/' is an infinite
    // redirect: no page is ever built and the window freezes.
    expect(router, contains('signOut()'));
    expect(router, contains("isPublicPage ? null : '/'"));
  });
}
