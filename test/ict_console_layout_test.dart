// The ICT portal is laid out as an ERP console.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  final ict = _read('lib/screens/ict/ict_dashboard_screen.dart');
  final ui = _read('lib/screens/ict/ict_ui.dart');
  final logs = _read('lib/screens/ict/activity_logs_tab.dart');
  final access = _read('lib/screens/ict/directorate_access_tab.dart');
  final yards = _read('lib/screens/ict/yard_directorate_tab.dart');
  final ictFiles = {
    'ict_dashboard_screen.dart': ict,
    'activity_logs_tab.dart': logs,
    'directorate_access_tab.dart': access,
    'yard_directorate_tab.dart': yards,
  };

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
  });

  group('the rail can only ever highlight one row', () {
    // ⚠️ The bug this replaced: with a bool inside each row, TWO rows could
    // light at once. The rail rebuilds as the tab controller animates, and a
    // MouseRegion rebuilt while the pointer is already inside it never gets
    // the exit that would have cleared the row the pointer left — so a quick
    // pass down the rail left a trail of stuck highlights.
    test('hover is one index on the rail, not a bool per row', () {
      expect(ict, contains('int? _hovered;'),
          reason: 'the rail holds the single hovered index');
      expect(ict, contains('hovered: _hovered == i'));
      // A stateless row cannot keep a highlight of its own to get stuck.
      expect(ict, contains('class _IctRailTile extends StatelessWidget'));
      expect(ict.contains('class _IctRailTileState'), isFalse);
    });

    test('the row does not paint a second highlight of its own', () {
      // The InkWell's hover overlay fades on its own schedule, so on a fast
      // pass it stayed lit underneath the painted one.
      expect(ict, contains('hoverColor: Colors.transparent'));
      // Selected still wins over hover: an open page must not restyle just
      // because the pointer crosses it.
      expect(ict, contains('final tint = selected'));
    });

    test('leaving the rail sideways clears the highlight', () {
      // The one exit no individual row is guaranteed to see.
      expect(ict, contains('onExit: (_) => setState(() => _hovered = null)'));
    });
  });

  group('ERP chrome, and only for ICT', () {
    // ⚠️ The look is carried by widgets in ict_ui.dart, never by edits to the
    // shared AppTheme — every other portal's tables must keep their gold,
    // title-case headings.
    test('the shared table theme is untouched', () {
      final theme = _read('lib/core/theme.dart');
      expect(theme, contains('headingTextStyle: const TextStyle(color: primaryGold'));
    });

    test('no other portal uses the ICT kit', () {
      for (final p in [
        'lib/screens/disposal/disposal_dashboard_screen.dart',
        'lib/screens/executive/executive_dashboard_screen.dart',
        'lib/screens/valuation/valuation_dashboard_screen.dart',
        'lib/screens/appeal/appeal_dashboard_screen.dart',
        'lib/screens/admin/admin_screen.dart',
      ]) {
        expect(_read(p).contains('ict_ui.dart'), isFalse);
        expect(_read(p).contains('_IctSideRail'), isFalse);
      }
    });

    test('the ICT login and signup are untouched by this work', () {
      for (final p in [
        'lib/screens/ict/ict_login_screen.dart',
        'lib/screens/ict/ict_signup_screen.dart',
      ]) {
        expect(_read(p).contains('_IctSideRail'), isFalse);
        expect(_read(p).contains('ict_ui.dart'), isFalse);
      }
    });
  });

  group('every ICT table is the same table', () {
    // ⚠️ IctTableTheme sets the heading style and colour. A call site that
    // passes either one WINS over it, and that table alone would keep the old
    // gold heading — which is exactly the drift this locks out.
    test('no ICT table styles its own heading row', () {
      ictFiles.forEach((name, src) {
        expect(src.contains('headingTextStyle:'), isFalse, reason: name);
        expect(src.contains('headingRowColor:'), isFalse, reason: name);
      });
    });

    test('every DataTable2 in ICT is wrapped in IctTableTheme', () {
      ictFiles.forEach((name, src) {
        expect('DataTable2('.allMatches(src).length,
            'IctTableTheme('.allMatches(src).length,
            reason: '$name has an unwrapped table');
      });
    });

    // Uppercasing happens in ictCol, so no one has to remember to type
    // capitals — and no table can quietly opt out.
    test('column headings go through ictCol', () {
      ictFiles.forEach((name, src) {
        expect(src.contains('DataColumn2('), isFalse,
            reason: '$name builds a column by hand instead of with ictCol');
      });
      expect(ui, contains('label.toUpperCase()'));
    });

    // The hand-built rows in Yards & Directorates are the console's only
    // table that is not a DataTable2, so it has to be held to the same rule.
    test('the hand-built table matches the real ones', () {
      expect(yards, contains('columns[i].toUpperCase()'));
      expect(yards, contains('height: kIctHeadingHeight'));
      expect(yards, contains('minHeight: kIctRowHeight'));
    });
  });

  group('one status pill for the whole console', () {
    // The request was explicit: every status box the same size and the same
    // design, on every page.
    test('the width is set once', () {
      expect(ui, contains('const double kIctPillWidth = 92'));
      expect(ui, contains('this.width = kIctPillWidth'));
    });

    test('no ICT screen draws a status box of its own', () {
      // Every status in ICT — account state, directorate state, the actor's
      // role — is an IctStatusPill.
      for (final src in [ict, logs, access, yards]) {
        expect(src, contains('IctStatusPill('));
      }
      // The one decision about what an account's state IS still lives in
      // account_cells.dart, shared with the Admin Panel; only the chrome
      // differs.
      expect(ict, contains('accountStatusOf(context, staff)'));
      expect(_read('lib/widgets/account_cells.dart'),
          contains('AccountStatus accountStatusOf('));
    });
  });

  group('a module does not repeat the console header', () {
    // ⚠️ The console header already names the section and says what it holds.
    // A page that prints its own title again twenty pixels below is the
    // surest sign of a screen designed on its own rather than as one module.
    test('no tab reprints its own section name as a page heading', () {
      expect(logs.contains("Text('Activity Logs'"), isFalse);
      expect(access.contains("Text('Directorate Access'"), isFalse);
    });

    test('the section name and count sit on the card instead', () {
      expect(logs, contains('IctSectionCard('));
      expect(access, contains('IctSectionCard('));
      expect(yards, contains('IctSectionCard('));
      expect(ict, contains('IctSectionCard('));
      // The count moved from a floating chip into the card's header.
      expect(logs.contains('_CountChip'), isFalse);
    });
  });
}
