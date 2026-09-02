import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final reports = _read('lib/screens/reports/reports_screen.dart');
  final reportSvc = _read('lib/services/report_service.dart');
  final exec = _read('lib/screens/executive/executive_dashboard_screen.dart');
  final tenderTab =
      _read('lib/screens/executive/tender_sales_view_tab.dart');

  group('the destroyed report reports costs, not a sale', () {
    // The destroyed case is the block between its own label and the next.
    final block = reports.substring(
        reports.indexOf("case 'destroyed':"),
        reports.indexOf("case 'reconciliation':"));

    test('valuation and destroyed price are gone', () {
      // Destruction has no buyer: no valuation is realised, and there is no
      // price. Reporting them invited the reader to reconcile figures that
      // describe nothing.
      expect(block, isNot(contains('Destroyed Price')));
      expect(block, isNot(contains("'Valuation (LKR)'")));
      expect(block, isNot(contains('destroyedPrice')));
    });

    test('the deposit, the costs and the refund take their place', () {
      expect(block, contains("'Destroying Deposit (LKR)'"));
      expect(block, contains("'Total Costs (LKR)'"));
      expect(block, contains("'Refund (LKR)'"));
    });

    test('it reads the same provider the Destroyed Goods pages read', () {
      // Same source as the expense form and both tables, so the three cannot
      // disagree about one SR's money.
      expect(block, contains('srFinancialsProvider.future'));
      expect(block, contains('depositSpent'));
      expect(block, contains('destroyingDeposit'));
    });

    test('it no longer reads the old destruction-tender tables', () {
      expect(block, isNot(contains('getDestructions()')),
          reason: 'destruction is not a tender any more');
    });

    test('a shortfall is shown, not hidden', () {
      // Costs CAN exceed the deposit; clamping at zero would misreport it.
      expect(block, contains('final refund = deposit - spent;'));
    });
  });

  group('the report emblem', () {
    test('a failed load is not cached as permanently missing', () {
      // The guard only re-runs while _logoSvg is null, so caching "missing"
      // would downgrade every later report in the session to the monogram.
      final fn = reportSvc.substring(
          reportSvc.indexOf('static Future<void> _loadLogo()'));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains('_logoSvg = null;'));
      expect(body, contains('for (final asset in const ['));
    });

    test('an empty asset falls through to the next one', () {
      final fn = reportSvc.substring(
          reportSvc.indexOf('static Future<void> _loadLogo()'));
      expect(fn.substring(0, fn.indexOf('\n  }')),
          contains('if (raw.trim().isEmpty) continue;'));
    });

    test('currentColor is resolved before the SVG reaches the PDF', () {
      // A PDF has no notion of currentColor; unresolved, the emblem paints
      // as nothing.
      expect(reportSvc, contains("replaceAll('currentColor', '#0D47A1')"));
    });

    test('a font failure can no longer take the emblem down with it', () {
      // PdfGoogleFonts throws when the asset manifest is unreadable, which
      // used to abort _ensureFontsLoaded before/around the logo load.
      final fn = reportSvc
          .substring(reportSvc.indexOf('Future<void> _ensureFontsLoaded()'));
      final body = fn.substring(0, fn.indexOf('\n  }'));
      expect(body, contains('try {'));
      expect(body, contains('await _loadLogo();'));
      expect(body, contains('catch (e)'));
    });
  });

  group('Top Management can watch the tender sales', () {
    test('the tab is wired in with room for it', () {
      expect(exec, contains('static const int _kTabCount = 5;'),
          reason: 'a fifth tab needs a fifth slot, or the view throws');
      expect(exec, contains("Text('Tender Sales')"));
      expect(exec, contains('TenderSalesViewTab(),'));
    });

    test('the strip and the view stay the same length', () {
      final strip = exec.substring(
          exec.indexOf('tabs: const ['), exec.indexOf('// ── Tab views'));
      expect('Tab('.allMatches(strip).length, 5);
      final views = exec.substring(exec.indexOf('// ── Tab views'));
      final children = views.substring(
          views.indexOf('children: const ['), views.indexOf('],'));
      expect(children.split(',').where((c) => c.trim().isNotEmpty).length, 5);
    });

    test('it is read-only: Top Management observes, Disposal acts', () {
      expect(tenderTab, contains('readOnly: true'));
    });

    test('it shows only what is live, the same rule Disposal applies', () {
      // So a sale leaves this page the moment Central Disposal finishes it.
      expect(tenderTab, contains('s.items.any((i) => !i.sold)'));
      expect(tenderTab, contains('DateTime.now().isAfter(s.unsoldDeadline!)'));
    });

    test('the caption says the page drops rows on its own', () {
      // A page that silently empties is alarming; this one explains itself.
      expect(tenderTab, contains('a sale leaves this '));
      expect(tenderTab, contains('page once every item is decided'));
    });

    test('it has a yard dropdown, matched per item not per sale', () {
      // A sale can mix items from a multi-directorate yard, so the
      // sale-level yard code cannot tell them apart.
      expect(tenderTab, contains('_YardPicker('));
      expect(tenderTab, contains("StyledDropdownOption('__all__', 'All Yards')"));
      expect(tenderTab,
          contains("matchesYardFilter(\n                          _yard, i.yard, i.forfeited?.srNumber ?? '')"));
    });

    test('re-tenders are detected against every sale, not just visible ones', () {
      // The earlier tender's window may have closed and dropped out.
      expect(tenderTab, contains('retenderTenderSaleIds(list)'));
    });
  });
}
