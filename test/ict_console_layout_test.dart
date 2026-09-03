// The ICT portal is laid out as an ERP console.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  final ict = _read('lib/screens/ict/ict_dashboard_screen.dart');

  group('a left rail, not a top tab strip', () {
    // ⚠️ ICT alone gets this shape. The other portals are single-purpose — an
    // officer opens one to do one job — so a tab strip suits them. ICT is an
    // ADMIN console: four unrelated areas a system admin moves between all
    // day, and a rail keeps all four in view and named at once.
    test('the rail exists and the tab strip is gone', () {
      expect(ict, contains('_IctSideRail'));
      expect(ict.contains('child: TabBar('), isFalse,
          reason: 'the top tab strip was replaced by the rail');
    });

    // ⚠️ Driven by the SAME controller the body uses. A rail holding its own
    // copy of the selection falls out of step the moment someone swipes the
    // body — it would still point at the old page.
    test('the rail reads the tab controller, not its own index', () {
      expect(ict, contains('_IctSideRail(controller: _tabs'));
      expect(ict, contains('controller.index == i'));
      expect(ict, contains('controller.animateTo(i)'));
      // Repaints as the controller animates, so a swipe moves the rail with
      // the page instead of snapping at the end.
      expect(ict, contains('animation: controller.animation ?? controller'));
    });

    test('the four areas are all named', () {
      for (final label in [
        'Staff Accounts',
        'Yards & Directorates',
        'Directorate Access',
        'Activity Logs',
      ]) {
        expect(ict, contains("'$label'"));
      }
    });

    // The rail carries the brand, so the header names the SECTION instead —
    // repeating the emblem would waste the width the header needs.
    test('the emblem appears once, on the rail', () {
      expect('SvgPicture.asset'.allMatches(ict).length, 1);
      expect(ict, contains('_IctSideRail.itemAt(_tabs.index)'));
    });

    test('the rail responds to the pointer', () {
      expect(ict, contains('MouseRegion'));
      expect(ict, contains('_hovered'));
      // Selected wins over hover, like the yard rail.
      expect(ict, contains('final tint = selected'));
    });
  });

  group('only this portal changed', () {
    // The request was explicit: redesign ICT, leave the rest alone.
    test('the ICT login and signup are untouched by this work', () {
      final login = _read('lib/screens/ict/ict_login_screen.dart');
      expect(login.contains('_IctSideRail'), isFalse);
      final signup = _read('lib/screens/ict/ict_signup_screen.dart');
      expect(signup.contains('_IctSideRail'), isFalse);
    });

    test('no other portal grew a rail', () {
      for (final p in [
        'lib/screens/disposal/disposal_dashboard_screen.dart',
        'lib/screens/executive/executive_dashboard_screen.dart',
        'lib/screens/valuation/valuation_dashboard_screen.dart',
        'lib/screens/appeal/appeal_dashboard_screen.dart',
      ]) {
        expect(_read(p).contains('_IctSideRail'), isFalse);
      }
    });
  });
}
