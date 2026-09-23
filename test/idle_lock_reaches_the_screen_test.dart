import 'package:flutter/material.dart';
import 'package:cus_yard_management/screens/lock/idle_lock_screen.dart';
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

void _noop() {}

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

    // ⚠️ THE SCREEN IS MOUNTED ABOVE MaterialApp, as main.dart does it.
    //
    // Locking signs the session out, which replaces the ProviderScope
    // and the router -- rebuilding MaterialApp and everything under it.
    // Drawn inside IdleLockOverlay, the screen was destroyed and
    // recreated about two seconds after it appeared and visibly jumped
    // back to its first frame. The overlay now only WATCHES; this layer
    // is what draws, and it sits where the reset cannot reach it.
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: IdleActivityDetector(
              child: IdleLockOverlay(
                child:
                    const Scaffold(body: Center(child: Text('dashboard'))),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: idleLockedFlag,
          builder: (context, locked, _) => locked
              ? const Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: IdleLockScreen(onUnlock: _noop),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ]),
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
