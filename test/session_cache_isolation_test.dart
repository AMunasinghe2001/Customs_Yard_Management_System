import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/app_session.dart';
import 'package:cus_yard_management/core/session_reset.dart';

void main() {
  test('an ended session belongs to no yard, not to GL1', () {
    // kDefaultYardCode is 'GL1'. Clearing to it meant a signed-out session
    // silently claimed to BE GL1, so any yard filter or yard stamp that ran
    // before the next profile loaded said GL1 — the exact yard whose rows
    // were showing up under other yards' officers.
    AppSession.setYard('GL2');
    AppSession.setRole('officer');
    expect(AppSession.currentYard, 'GL2');

    AppSession.clear();
    expect(AppSession.currentYard, isNot('GL1'));
    expect(AppSession.currentYard, isEmpty);
    expect(AppSession.currentDirectorate, isNull);
    expect(AppSession.currentRole, isNull);
  });

  testWidgets('ending a session bumps the epoch that keys the ProviderScope',
      (tester) async {
    final before = sessionEpoch.value;
    clearCachedSessionData();
    // Deferred by one frame on purpose: the caller still has statements that
    // read the live container.
    expect(sessionEpoch.value, before,
        reason: 'must not dispose the container underneath its caller');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(sessionEpoch.value, before + 1);
  });

  test('the ProviderScope is keyed by the session epoch', () {
    // Riverpod caches every provider for the life of its container, and none
    // of the data providers are autoDispose — so the container itself has to
    // go when a session ends.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('valueListenable: sessionEpoch'));
    expect(main, contains("ValueKey('session-\$epoch')"));
  });

  test('signing out clears the cache', () {
    final services = File('lib/services/services.dart').readAsStringSync();
    expect(services, contains('clearCachedSessionData();'));
    // Only from a real sign-out. A rejected sign-in never established a
    // session, and resetting under it would discard the error the user needs.
    final login = File('lib/screens/login/login_screen.dart').readAsStringSync();
    expect(login, isNot(contains('clearCachedSessionData')));
  });
}
