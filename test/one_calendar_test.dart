// Two calendars in one product.
//
// ⚠️ Reported directly, from the hand-over dialog: the app has its own
// gold, one-tap calendar (OneTapDatePicker) and every date on the yard's
// pages opens it — except two, which opened Material's stock
// `showDatePicker`. That put a blue-and-white box with its own OK/Cancel
// in the middle of a yard-styled popup, and it reads as a different
// product rather than a different step.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the yard pages open the app\'s own calendar', () {
    // The hand-over form (Release to Owner / to Buyer) and the yard's
    // Mark as Destroyed dialog.
    const yardPages = [
      'lib/widgets/handover_form_dialog.dart',
      'lib/screens/packages/disposition_category_screen.dart',
    ];

    for (final p in yardPages) {
      test('${p.split('/').last} uses OneTapDatePicker', () {
        final src = File(p).readAsStringSync();
        expect(src, contains('OneTapDatePicker('),
            reason: 'this page no longer opens the app calendar');
      });

      test('${p.split('/').last} does not call showDatePicker', () {
        final src = File(p).readAsStringSync();
        // ⚠️ The CODE, not the comments: both files explain in prose why
        // the stock picker was replaced, and that sentence names it.
        final code = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains('showDatePicker('), isFalse,
            reason: 'the stock Material picker is back');
      });
    }

    test('a hand-over date still cannot be in the future', () {
      // ⚠️ Goods cannot have been collected on a day that has not happened.
      // Swapping the picker must not drop the bound it carried.
      final src =
          File('lib/widgets/handover_form_dialog.dart').readAsStringSync();
      final i = src.indexOf('OneTapDatePicker(');
      expect(src.substring(i, i + 400), contains('lastDate: DateTime.now()'));
    });

    test('a destruction date still cannot be in the future', () {
      final src = File('lib/screens/packages/disposition_category_screen.dart')
          .readAsStringSync();
      final i = src.indexOf('OneTapDatePicker(');
      expect(src.substring(i, i + 500), contains('lastDate: DateTime.now()'));
    });
  });
}
