// The Post Status Activity list the SR form offers depends on the Status.
//
// ⚠️ This filter was removed wholesale at one point, so every status offered
// every activity. The reason was real — a PERISHABLE has no status in either
// group, so a filtered list left it with nothing to choose — but the cure was
// applied to all goods rather than to the exception, and an officer could then
// record "Pending Licence" against goods that were already forfeited.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/post_status_activities.dart';

String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('which activities a status offers', () {
    test('Detain gets the pending list, and nothing from disposal', () {
      final detain = postStatusActivitiesFor('Detain');
      expect(detain, kDetainActivities);
      expect(detain, contains('Pending Licence'));
      expect(detain, isNot(contains('Supposed to be Sold / Auction')));
    });

    test('the disposal statuses get the disposal list', () {
      for (final status in ['Forfeit', 'Abandoned', 'Other']) {
        final list = postStatusActivitiesFor(status);
        expect(list, kDisposalActivities, reason: status);
        expect(list, isNot(contains('Pending Licence')), reason: status);
      }
    });

    test('a free-text status falls to the disposal list', () {
      // The form lets an officer type their own status; anything that is not
      // Detain is on its way to being disposed of.
      expect(postStatusActivitiesFor('Other: seized pending court'),
          kDisposalActivities);
    });

    test('the two lists share only Other', () {
      final shared =
          kDetainActivities.where(kDisposalActivities.contains).toList();
      expect(shared, ['Other']);
      // And the combined list keeps it once, or a dropdown would show two
      // identical entries.
      expect(kAllPostStatusActivities.where((a) => a == 'Other').length, 1);
    });
  });

  group('the SR form applies the rule', () {
    final form = _read('lib/screens/inspection/inspection_screen.dart');

    test('the list comes from the status, not from everything', () {
      expect(form, contains('postStatusActivitiesFor(widget.row.status)'));
    });

    // ⚠️ THE exception, and the reason the filter was dropped before. A
    // perishable's status is 'Perishable', which is in neither group, so a
    // filtered list would offer it nothing at all.
    test('a perishable is exempt and gets every activity', () {
      expect(form, contains('widget.row.nature == kNaturePerishable'));
      expect(form, contains('kAllPostStatusActivities'));
      // Both perishable pages filter against the same full list, so what the
      // form can save is exactly what the filters can match.
      final yard = _read('lib/screens/packages/perishable_goods_screen.dart');
      expect(yard, contains('kAllPostStatusActivities'));
    });

    // ⚠️ Without this the field renders EMPTY while the row still holds the
    // old value — and the old value is what gets saved.
    test('changing the status drops an activity the new one does not offer',
        () {
      expect(form, contains('final allowed = postStatusActivitiesFor(widget.row.status)'));
      expect(form, contains('widget.row.selectedReasons[i] = null'));
    });
  });
}
