import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/idle_lock.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/widgets/idle_lock_overlay.dart';

ProfileModel _profile() => ProfileModel(
      id: 'u1',
      fullName: 'Officer',
      role: 'officer',
      isActive: true,
      createdAt: DateTime.now(),
      passwordUpdatedAt: DateTime.now(),
    );

void main() {
  setUp(() => idleLockedFlag.value = false);
  tearDown(() => idleLockedFlag.value = false);

  testWidgets('the REAL overlay locks 5 minutes after a profile appears',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentProfileProvider.notifier).state = _profile();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: IdleActivityDetector(
          child: IdleLockOverlay(
            child: const Scaffold(body: Center(child: Text('dashboard'))),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(container.read(idleLockedProvider), isFalse,
        reason: 'not locked immediately');

    // Just short of five minutes.
    // Just short of five minutes.
    await tester.pump(const Duration(minutes: 4, seconds: 50));
    expect(container.read(idleLockedProvider), isFalse);

    // Past five minutes with no input at all.
    await tester.pump(const Duration(seconds: 20));
    expect(container.read(idleLockedProvider), isTrue,
        reason: 'the app must lock five minutes after the desk goes quiet');
  });

  testWidgets('the lock screen itself is shown, not just the flag',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentProfileProvider.notifier).state = _profile();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: IdleActivityDetector(
          child: IdleLockOverlay(
            child: const Scaffold(body: Center(child: Text('dashboard'))),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5, seconds: 20));
    await tester.pump(const Duration(milliseconds: 200));

    // ⚠️ The whole point: an officer must SEE the lock, not be silently
    // signed out and dropped somewhere else.
    expect(find.text('Sri Lanka Customs'), findsOneWidget,
        reason: 'the lock screen must actually be on screen');
    expect(find.textContaining('Locked after'), findsOneWidget);
  });

}
