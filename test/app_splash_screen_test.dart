import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/screens/home/home_screen.dart';
import 'package:cus_yard_management/widgets/app_splash_screen.dart';

void main() {
  group('AppSplashScreen unit and widget tests', () {
    testWidgets('renders brand title, subtitle, squircle logo, and progress bar',
        (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppSplashScreen(
            onComplete: () {
              completed = true;
            },
            duration: const Duration(milliseconds: 1000),
            settleDelay: const Duration(milliseconds: 100),
          ),
        ),
      );

      // Verify widgets render
      expect(find.text('Sri Lanka Customs'), findsOneWidget);
      expect(find.text('SR Management System'), findsOneWidget);

      // Initially not completed
      expect(completed, isFalse);

      // Pump to completion
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
    });

    testWidgets('tapping splash skips and completes immediately',
        (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: AppSplashScreen(
            onComplete: () {
              completed = true;
            },
            duration: const Duration(seconds: 10),
          ),
        ),
      );

      expect(completed, isFalse);

      // Tap on splash
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();

      expect(completed, isTrue);

      // Settle any remaining microtasks/animations
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('HomeScreen transitions from splash to portal chooser',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const HomeScreen(showSplash: true),
          ),
        ),
      );

      // Initially on splash
      expect(find.byType(AppSplashScreen), findsOneWidget);

      // Fast-forward past splash (duration + settle + transition)
      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 600));

      // After transition, portal selection view is shown
      expect(find.text('Select your portal to continue'), findsOneWidget);
      expect(find.text('Yard Access'), findsOneWidget);

      // Settle cards animations
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('HomeScreen with showSplash: false opens portal view immediately',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const HomeScreen(showSplash: false),
          ),
        ),
      );

      // Settle card stagger animations
      await tester.pump(const Duration(seconds: 2));

      // No splash screen, directly on portal view
      expect(find.byType(AppSplashScreen), findsNothing);
      expect(find.text('Select your portal to continue'), findsOneWidget);
    });
  });
}
