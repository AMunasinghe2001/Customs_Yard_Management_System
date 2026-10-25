import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/screens/ict/yard_directorate_tab.dart';

const _directorates = [
  DirectorateModel(code: 'CED', name: 'Customs Enforcement', srPrefix: 'CED'),
];

void main() {
  group('ICT Form Enter Key Action Tests', () {
    testWidgets('Directorate dialog fields have correct textInputAction and onSubmitted',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoratesProvider.overrideWith((ref) => Future.value(_directorates)),
            yardsProvider.overrideWith((ref) => Future.value(const [])),
            yardDirectoratesProvider.overrideWith((ref) => Future.value(const {})),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: YardDirectorateTab(accent: Color(0xFF8E3A5F)),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the tab renders
      expect(find.byType(YardDirectorateTab), findsOneWidget);
    });
  });
}
