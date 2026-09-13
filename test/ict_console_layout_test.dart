// The ICT portal is laid out as an ERP console.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/screens/ict/ict_ui.dart';

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
      expect(yards, contains('c.toUpperCase()'));
      expect(yards, contains('height: kIctHeadingHeight'));
      expect(yards, contains('minHeight: kIctRowHeight'));
    });
  });

  group('one status pill for the whole console', () {
    // The request was explicit: every status box the same size and the same
    // design, on every page.
    test('the width is set once', () {
      expect(ui, contains('const double kIctPillWidth ='));
      expect(ui, contains('const double kIctPillHeight ='));
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
      // ⚠️ Whitespace-insensitive. This pinned the call as a single line and
      // broke when dart format wrapped it across two — a formatting accident
      // reported as a missing shared helper. What matters is that the ICT
      // console asks account_cells for the answer, not how it is wrapped.
      expect(ict.replaceAll(RegExp(r'\s+'), ''),
          contains('accountStatusOf(context,staff)'));
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

  group('one height, one button, everywhere', () {
    // ⚠️ The request was explicit: every button in ICT the same size and the
    // same design. These lock the two ways that drifts — a control that sets
    // its own height, and a second kind of icon button.
    test('the control height is named once and nothing overrides it', () {
      // The number itself is not the invariant -- that it is named ONCE
      // and that a real measurement holds the controls to it is. See
      // ict_control_heights_test, which pumps a toolbar and measures.
      expect(ui, contains('const double kIctControlHeight ='));
      // No ICT screen hard-codes a height for a control of its own.
      for (final src in [logs, access, yards]) {
        expect(src.contains('ElevatedButton.icon('), isFalse,
            reason: 'use IctPrimaryButton or StyledDialogPrimaryButton');
      }
    });

    test('row actions are the console icon button, not three sizes of one', () {
      expect(ui, contains('class IctIconButton'));
      expect(yards, contains('IctIconButton('));
      // The 34px IconButton holding a toggle glyph is what pushed the Yards
      // table's Actions column past the card's edge. Counted rather than
      // searched for: a bare "IconButton(" also matches inside
      // "IctIconButton(", so the two counts being equal is what says there
      // is no plain one left.
      expect('IconButton('.allMatches(yards).length,
          'IctIconButton('.allMatches(yards).length);
    });

    test('the dialogs take the console shape, and only ICT does', () {
      for (final src in [ict, access, yards]) {
        expect(src, contains('erp: true'));
      }
      // ⚠️ StyledFormDialog is every portal's form chrome. The flag must stay
      // opt-in, or redesigning ICT would silently redesign the yard's forms.
      final dialog = _read('lib/widgets/styled_form_dialog.dart');
      expect(dialog, contains('this.erp = false'));
      for (final p in [
        'lib/screens/admin/admin_screen.dart',
        'lib/screens/disposal/disposal_dashboard_screen.dart',
      ]) {
        expect(_read(p).contains('erp: true'), isFalse);
      }
    });
  });

  group('rows are told apart by a rule, not by banding', () {
    test('the table theme sets a light divider colour', () {
      // ⚠️ DataTable reads its row divider from ThemeData.dividerColor, not
      // from DataTableThemeData — there is no divider colour on the table
      // theme at all, so setting it here is the only way.
      expect(ui, contains('dividerColor: c.borderColor.withOpacity(0.5)'));
      // And no table cancels it back out.
      for (final src in [ict, logs, access]) {
        expect(src.contains('dividerThickness: 0'), isFalse);
      }
    });

    test('the hand-built rows draw the same rule', () {
      expect(yards, contains('borderColor.withOpacity(0.5)'));
    });
  });

  group('the console does not print a live credential', () {
    // ⚠️ A directorate username is half a working credential for an account a
    // whole office signs in with, and this page is read on an open monitor.
    test('Directorate Access shows the password rotation, not the username',
        () {
      expect(access.contains("ictCol('Username'"), isFalse);
      expect(access, contains("ictCol('Password'"));
      // ⚠️ The cell moved. It was `class _PasswordAge`, private to this tab;
      // the Staff Register needed the same answer about yard officers, so it
      // now lives in widgets/account_cells.dart as PasswordAgeCell and both
      // tables share it. What this test protects is unchanged — the column
      // shows the rotation rather than a live credential.
      expect(access, contains('PasswordAgeCell('));
    });
  });

  group('the console does not lurch or interrupt', () {
    // ⚠️ On a trackpad a two-finger sideways flick slid the console between
    // modules, so an officer scrolling a wide table found half of one page
    // beside half of another. A console is navigated from its rail.
    test('the modules cannot be dragged between', () {
      expect(ict, contains('physics: const NeverScrollableScrollPhysics()'));
      // The rail's animateTo still runs the transition, so choosing a module
      // is animated -- it is only the DRAG that is gone.
      expect(ict, contains('controller.animateTo(i)'));
      expect(ict, contains('class _IctModule'));
    });

    // ⚠️ The arrival animation reads the CONTROLLER, not a one-shot started
    // in initState: a module is built once and shown many times, so a
    // play-on-build animation would run only the first time it was opened.
    test('the arrival animation is driven by the controller', () {
      final module = ict.substring(ict.indexOf('class _IctModule'));
      expect(module, contains('controller.animation'));
      // The subtree is passed through AnimatedBuilder's `child`, so a page
      // with a data table is not rebuilt sixty times a second.
      expect(module, contains('child: child,'));
    });

    test('the profile is a dialog over a blurred console', () {
      // ⚠️ It was briefly a PAGE, and that broke the console: the rail stayed
      // visible and clickable but its taps only moved a tab controller that
      // nothing was showing, so choosing another module did nothing and one
      // back button was the only way out. A dialog cannot reach that state —
      // it owns the screen until dismissed, and dismissing it puts you back.
      expect(ict.contains('_IctProfilePage'), isFalse);
      expect(ict.contains('_onProfile'), isFalse);
      expect(ict, contains('showIctProfileDialog(context, accent)'));
      // The blur is what separates it from the console; a flat scrim leaves
      // sharp text behind the dialog and the eye keeps reading past it.
      expect(ui, contains('BackdropFilter('));
      expect(ui, contains('ImageFilter.blur(sigmaX: 6 * t, sigmaY: 6 * t)'));
      // ⚠️ And a real scrim with it. Blur alone still reads as the console,
      // slightly smudged — the dialog has to look like it is in FRONT of
      // something, and darkness is what does that.
      expect(ui, contains('barrierColor: Colors.black.withOpacity(0.45)'));
      // The dialog takes the console's flat shape, opt-in as ever.
      expect(ui, contains('DisposalProfileDialog(accent: accent, erp: true)'));
      final profile = _read('lib/widgets/disposal_profile_dialog.dart');
      expect(profile, contains('this.erp = false'),
          reason: 'every other portal keeps the gradient dialog');
      expect(profile.contains('embedded'), isFalse,
          reason: 'the reverted page left its flag behind');
    });
  });

  group('the audit trail is paged by the database', () {
    test('the pager keeps first, last and a window around the current page',
        () {
      // A short run is shown whole.
      expect(IctPager.windowFor(0, 5), [0, 1, 2, 3, 4]);
      // ⚠️ Long runs collapse to a fixed width, so the bar is the same size
      // at 10 pages and at 3,000. First and last are always reachable.
      final mid = IctPager.windowFor(10, 40);
      expect(mid.first, 0);
      expect(mid.last, 39);
      expect(mid, contains(10));
      expect(mid, contains(null), reason: 'the gaps collapse to an ellipsis');
      expect(mid.length, lessThan(10));
      // At either end the window does not run off the edge.
      expect(IctPager.windowFor(0, 40).first, 0);
      expect(IctPager.windowFor(39, 40).last, 39);
      expect(IctPager.windowFor(0, 0), isEmpty);
    });

    test('the screen holds one page, not the table', () {
      final providers = _read('lib/core/providers.dart');
      expect(providers, contains('FutureProvider<AuditLogPage>'));
      // Every narrowing is part of the provider's identity, so changing a
      // filter is a new QUERY rather than a re-filter of rows in hand.
      expect(providers, contains('class IctLogQuery'));
      expect(providers, contains('offset: q.page * q.pageSize'));
    });
  });

  group('the console has a colour', () {
    // "Too white": white cards on a white page, separated only by hairlines,
    // read as one flat sheet.
    test('the ground and the card headers carry the accent', () {
      expect(ict, contains('accent.withOpacity(0.035)'),
          reason: 'the page behind the cards');
      expect(ui, contains('IctAccent.of(context).withOpacity(0.07)'),
          reason: 'the section-card header strip');
      // The accent is published once rather than threaded through every
      // widget that wants to paint one line with it.
      expect(ui, contains('class IctAccent extends InheritedWidget'));
      expect(ict, contains('IctAccent('));
    });

    test('a metric tile is tinted, not a white box with a coloured square',
        () {
      expect(ui, contains('Color.alphaBlend(color.withOpacity(0.05)'));
    });
  });

  group('one cell shape across the toolbar', () {
    // ⚠️ Measured for real in ict_control_heights_test — every control is
    // kIctControlHeight and they share a baseline. What made the search box
    // look like the small one was that it had no CAPTION: three cells were a
    // label and a box, and it was a box on its own.
    test('the search box is labelled like the filters beside it', () {
      expect(ui, contains('class IctFieldLabel'));
      final search = ui.substring(ui.indexOf('class IctSearchField'),
          ui.indexOf('/// One ICT filter'));
      expect(search, contains('IctFieldLabel(label)'));
    });

    test('the header and the rail brand are built the same way', () {
      // ⚠️ Equal heights were not enough. The rail was a SizedBox followed by
      // a Divider — a rule in the pixel AFTER the box — while the header's
      // border sits in the last pixel OF it. One pixel apart, and that is
      // the step you can see where the two meet.
      expect('height: kIctTopBarHeight'.allMatches(ict).length, 2);
      expect(ict, contains('its own bottom rule INSIDE that height'));
    });
  });

  group('a module arrives the way a page of rows does', () {
    // ⚠️ Choosing a module from the rail and turning a page in the pager are
    // both "show me different rows", so they must not arrive differently.
    // The table card plays .slideY(begin: 0.05).fadeIn(); the rail used to
    // nudge the page in by a flat 12px, and only one of them looked meant.
    // ⚠️ And every module stages its own arrival the same way: the measures
    // or the first card, then the filters, then the rows. Staff Accounts and
    // Yards & Directorates had none of this, so switching to them from
    // Activity Logs looked like the animation had failed rather than like a
    // different page.
    test('all four modules play the same entrance', () {
      for (final entry in {
        'ict_dashboard_screen.dart': ict,
        'activity_logs_tab.dart': logs,
        'directorate_access_tab.dart': access,
        'yard_directorate_tab.dart': yards,
      }.entries) {
        expect(entry.value, contains('slideY(begin: 0.05, duration: 400.ms)'),
            reason: '${entry.key} does not bring its table card in');
      }
      // The two that also carry a toolbar fade it in first.
      for (final src in [ict, logs]) {
        expect(src, contains('fadeIn(duration: 300.ms, delay: 120.ms)'));
      }
    });

    test('the rail lifts a module by the same fraction the card does', () {
      final module = ict.substring(ict.indexOf('class _IctModule'));
      expect(module, contains('Curves.easeOutCubic'));
      expect(module, contains('(1 - eased) * 0.05'));
      expect(logs, contains('slideY(begin: 0.05'));
    });
  });

  group('the toolbar controls agree before anything forces them', () {
    // ⚠️ The bug this locks out was invisible to every layout assertion: both
    // controls measured kIctControlHeight because a SizedBox said so, while
    // the dropdown's INTRINSIC height was 48 (a Material prefix icon is a
    // 48x48 tap target) and its border painted outside the box it was given.
    test('the dropdown constrains its prefix icon, as the search box does',
        () {
      expect(ui, contains('prefixIconConstraints:'));
      expect('prefixIconConstraints:'.allMatches(ui).length, 2,
          reason: 'both the search box and the filter must constrain it');
      // The shared dropdown accepts it but does not default to it: every
      // other portal's dropdowns keep Material's 48px target.
      final dd = _read('lib/widgets/styled_dropdown.dart');
      expect(dd, contains('final BoxConstraints? prefixIconConstraints;'));
    });
  });
}
