// The nav rail's grouping, and the two rails that used to be hand-copied.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  final shell = _read('lib/widgets/app_shell.dart');

  group('one definition feeds both rails', () {
    // ⚠️ The officer and DC/SDDC rails were two hand-maintained copies of the
    // same twenty-odd entries. Keeping them in step was manual, and they had
    // already drifted once. navSectionsFor() builds both from one list, so an
    // entry cannot be added to one rail and forgotten on the other.
    test('the rails are built, not duplicated', () {
      expect(shell, contains('List<NavSection> navSectionsFor('));
      expect(shell.contains('const _officerNav = ['), isFalse,
          reason: 'the duplicated lists must not come back');
      expect(shell.contains('const _adminNav = ['), isFalse);
    });

    test('the admin rail differs only where it should', () {
      // Its own Dashboard route, and the extra Admin Panel entry.
      expect(shell, contains("isAdmin ? '/admin' : '/dashboard'"));
      expect(shell, contains("if (isAdmin)"));
      expect(shell, contains("'/admin/panel'"));
    });
  });

  group('every page is still reachable', () {
    // A regrouping must not quietly drop a page. These are the routes the rail
    // is responsible for offering.
    const mustOffer = [
      '/dashboard', '/inspection', '/old-entries', '/packages',
      '/warehouses', '/zone-capacity',
      '/detained-packages', '/abandoned-packages', '/forfeited-packages',
      '/other-packages', '/perishable-goods',
      '/returned-packages', '/sold-packages', '/unsold-packages',
      '/destroyed-packages', '/reexported-packages',
      '/government-use-packages', '/auction-packages',
      '/converted-packages', '/removed-packages',
      '/tender-disposals', '/reports',
    ];

    for (final route in mustOffer) {
      test('$route is in the rail', () {
        expect(shell, contains("'$route'"));
      });
    }
  });

  group('the sections read in the order the work happens', () {
    // Goods arrive, are held, get a disposition, then reach an outcome.
    int at(String needle) => shell.indexOf(needle);

    test('register comes before storage, holding, disposal and outcomes', () {
      expect(at("NavSection('Register'"), lessThan(at("NavSection('Storage'")));
      expect(at("NavSection('Storage'"), lessThan(at("NavSection('Held Goods'")));
      expect(
          at("NavSection('Held Goods'"), lessThan(at("NavSection('Disposed'")));
      expect(at("NavSection('Disposed'"),
          lessThan(at("NavSection('Final Outcomes'")));
      expect(at("NavSection('Final Outcomes'"),
          lessThan(at("NavSection('Reporting'")));
    });

    test('a heading is rendered for a named section only', () {
      // The Dashboard sits in an unnamed section — it needs no caption.
      expect(shell, contains('if (section.title.isNotEmpty)'));
      expect(shell, contains('_NavSectionHeading'));
    });
  });

  group('the rail responds to the pointer', () {
    // ⚠️ An InkWell's own hover highlight all but vanishes against the dark
    // navy rail, so pointing at an item gave almost no feedback — on a rail
    // this long you could not tell which row you were about to click.
    test('hover is tracked explicitly', () {
      expect(shell, contains('MouseRegion'));
      expect(shell, contains('_hovered'));
      expect(shell, contains('SystemMouseCursors.click'));
    });

    test('the active row does not change under the pointer', () {
      // Active wins over hover: an already-open page should not restyle just
      // because the pointer crosses it. The tint is chosen active-FIRST, so
      // `_hovered` is only ever consulted in the not-active branch.
      final from = shell.indexOf('final tint = isActive');
      expect(from, greaterThan(-1), reason: 'the tint must be active-first');
      final expr = shell.substring(from, shell.indexOf(';', from));
      expect(expr.indexOf('isActive'), lessThan(expr.indexOf('_hovered')),
          reason: 'active must be tested before hover');
    });
  });
}
