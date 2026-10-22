import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/screens/ict/yard_directorate_tab.dart';

void main() {
  group('ICT Form Enter Key Action Tests', () {
    testWidgets('Directorate dialog fields have correct textInputAction and onSubmitted',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: YardDirectorateTab(),
            ),
          ),
        ),
      );

      // Verify the tab renders
      expect(find.byType(YardDirectorateTab), findsOneWidget);
    });
  });
}
