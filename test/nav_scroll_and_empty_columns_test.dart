import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two independent complaints, both about state that should have survived and
/// did not:
///
///  * clicking a nav item near the BOTTOM of the yard's rail scrolled the rail
///    back to the top the instant the page opened, hiding the item that had
///    just been selected;
///  * Central Disposal's outcome tabs showed no column headers at all when
///    empty, so an empty Removed tab was indistinguishable from an empty
///    Converted one.
/// Reads a source file with line endings normalised to LF.
///
/// The working tree may be checked out CRLF, and the assertions below match
/// multi-line source — without this they fail on the line endings alone.
String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('the nav rail keeps its scroll position across a navigation', () {
    final shell = _read('lib/widgets/app_shell.dart');

    test('the rail has a controller at all', () {
      expect(shell, contains('controller: _navScrollCtrl'),
          reason: 'an uncontrolled ListView starts at offset 0 every build');
    });

    test('the offset lives OUTSIDE the widget, not in State', () {
      // Every screen wraps itself in its own AppShell, so navigating disposes
      // one shell and builds another. A controller whose offset is only held
      // in State is therefore born at 0 on every navigation — the bug.
      final offsetDecl = RegExp(r'^double _navScrollOffset = 0;', multiLine: true);
      expect(offsetDecl.hasMatch(shell), isTrue,
          reason: 'the remembered offset must outlive the State object');

      // It must be declared at the top level, not inside the State class.
      final classStart = shell.indexOf('class _AppShellState');
      expect(shell.indexOf('double _navScrollOffset = 0;'), lessThan(classStart),
          reason: 'the offset was moved back inside the widget/State');
    });

    test('the controller is seeded from it and writes back to it', () {
      expect(shell, contains('initialScrollOffset: _navScrollOffset'),
          reason: 'the new shell must resume where the old one stopped');
      expect(shell, contains('_navScrollOffset = _navScrollCtrl.offset'),
          reason: 'scrolling must update the remembered offset');
    });

    test('the controller is disposed with its listener', () {
      expect(shell, contains('_navScrollCtrl.removeListener(_rememberNavScroll)'));
      expect(shell, contains('_navScrollCtrl.dispose()'));
    });

    testWidgets('a ListView seeded with an offset really starts there',
        (tester) async {
      // Pins the mechanism the fix relies on: initialScrollOffset survives a
      // rebuild into a brand-new controller, which is what a navigation does.
      final controller = ScrollController(initialScrollOffset: 240);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView(
              controller: controller,
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 40, child: Text('item $i')),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(controller.offset, 240);
    });
  });

  group('an empty outcome tab still shows its columns', () {
    // Normalised: the working tree may be checked out CRLF, and these
    // assertions match multi-line source.
    final dash =
        _read('lib/screens/disposal/disposal_dashboard_screen.dart');

    test('the table is no longer swapped out for a bare empty state', () {
      // The bug: `rows.isEmpty ? _listCard(EmptyTableState) : Column(table)`
      // removed the DataTable2 entirely, taking the column headers with it.
      expect(
          dash,
          isNot(contains('child: rows.isEmpty\n'
              '                ? _listCard(')),
          reason: 'the outcome tab drops its table (and headers) when empty');
    });

    test('the outcome table renders its empty state INSIDE the table', () {
      final tab = dash.substring(dash.indexOf('class UnsoldProposalsTab'));
      final body = tab.substring(0, tab.indexOf('class '.padRight(6), 10) + 1);
      expect(body, contains('empty: EmptyTableState('),
          reason: 'DataTable2.empty is what keeps the headers visible');
    });

    test('each outcome tab says something specific when empty', () {
      // One widget serves all four outcome tabs, so without per-tab wording
      // each of Removed / Converted / Auction / Government Use read
      // "No unresolved unsold packages" — the Unsold tab's own message.
      for (final phrase in [
        'No goods assigned to government use',
        'No goods sent to auction',
        'No converted goods',
        'No goods removed from the premises',
      ]) {
        expect(dash, contains(phrase),
            reason: 'an outcome tab still borrows another tab\'s empty text');
      }
    });

    test('the pager is hidden when there is nothing to page', () {
      // ⚠️ Against the DATABASE's total, not the loaded rows. The tab pages on
      // the server now, so `rows` holds one page — a count taken from it would
      // be wrong on every page, and empty-looking on none.
      expect(dash, contains('if (total > 0)\n'
          '                        TablePager('));
    });
  });
}
