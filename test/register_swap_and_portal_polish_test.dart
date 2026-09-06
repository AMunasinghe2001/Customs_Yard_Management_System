import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/directorates.dart';
import 'package:cus_yard_management/models/models.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

TenderSaleModel _sale({DateTime? date, String? start, String? end}) =>
    TenderSaleModel(
      id: 's1',
      saleNumber: 'CDU/TS/2026/8',
      saleDate: date,
      saleTime: start,
      saleEndTime: end,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('switching the register keeps the serial', () {
    // Switching SR to OA on the form is a CORRECTION to a number already on
    // screen. Re-minting from the other register's count moved the serial out
    // from under the officer, so a number they had just read changed.
    test('only the register segment changes', () {
      expect(withSrDocType('CED/GL1/SR/87/2026', 'OA'), 'CED/GL1/OA/87/2026');
      expect(withSrDocType('CED/GL1/OA/87/2026', 'SR'), 'CED/GL1/SR/87/2026');
    });

    test('the directorate prefix survives', () {
      expect(withSrDocType('B/A/KAT/SR/07/2026', 'OA'), 'B/A/KAT/OA/07/2026');
    });

    test('an unprefixed number stays unprefixed', () {
      expect(withSrDocType('GL1/SR/07/2026', 'OA'), 'GL1/OA/07/2026');
    });

    test('the serial keeps its padding and the year is untouched', () {
      expect(withSrDocType('GL1/SR/01/2025', 'OA'), 'GL1/OA/01/2025');
    });

    test('switching to the register it already has is a no-op', () {
      expect(withSrDocType('GL1/SR/87/2026', 'SR'), 'GL1/SR/87/2026');
    });

    test('a shape it cannot rewrite returns null, so the caller can mint', () {
      expect(withSrDocType('', 'OA'), isNull);
      expect(withSrDocType('nonsense', 'OA'), isNull);
      expect(withSrDocType('GL1/MISC/187/2025', 'OA'), isNull,
          reason: 'MISC is not a register this build knows');
      expect(withSrDocType('GL1/SR/87/2026', 'ZZ'), isNull,
          reason: 'ZZ is not a register either');
    });

    test('the form swaps in place rather than re-minting', () {
      final form = _read('lib/screens/inspection/inspection_screen.dart');
      expect(form, contains('withSrDocType(\n                                              _srNumberCtrl.text, v)'));
      // Minting stays as the fallback for a field with nothing to rewrite.
      expect(form, contains('} else {\n                                            _generateNextSr();'));
    });

    test('minting a NEW number still counts within one register', () {
      // The two rules coexist: a fresh number is scoped, a swap is not.
      final services = _read('lib/services/services.dart');
      expect(services, contains("parts[1].trim().toUpperCase() != type"));
    });
  });

  group('DC and SDDC are shown apart', () {
    test('the short titles name each post on its own', () {
      expect(kPostShortTitles['dc'], 'DC');
      expect(kPostShortTitles['sddc'], 'SDDC');
      expect(kPostShortTitles['officer'], 'Officer');
    });

    test('a profile reports its own post, not the shared pair', () {
      ProfileModel p(String post) => ProfileModel(
          id: 'p',
          fullName: 'A',
          role: kPostRoles[post]!,
          isActive: true,
          createdAt: DateTime.now(),
          jobRole: post);
      expect(p('dc').postShortTitle, 'DC');
      expect(p('sddc').postShortTitle, 'SDDC');
      expect(p('officer').postShortTitle, 'Officer');
    });

    test('an account with no post recorded still cannot be told apart', () {
      // Honest: without a post, DC and SDDC are genuinely indistinguishable.
      final p = ProfileModel(
          id: 'p',
          fullName: 'A',
          role: 'admin',
          isActive: true,
          createdAt: DateTime.now());
      expect(p.postShortTitle, 'DC / SDDC');
    });

    test('the ICT table and filter both work off the post', () {
      final ict = _read('lib/screens/ict/ict_dashboard_screen.dart');
      // The POST, not the permission role. Uppercasing moved into
      // IctStatusPill when the console got one pill for every status, so
      // the cell now just hands it the post.
      expect(ict, contains('label: staff.postShortTitle'));
      expect(ict, isNot(contains("staff.isAdmin ? 'DC / SDDC' : 'OFFICER'")));
      // The filter lists posts, and narrows to the exact one client-side
      // because the query only speaks in permission roles.
      expect(ict, contains('for (final e in kPostTitles.entries)'));
      expect(ict, contains('kPostRoles[_selectedRole]'));
      expect(ict, contains('return post == _selectedRole;'));
    });
  });

  group('a tender sale reports which stage it has reached', () {
    // "Pending" said nothing about which of four situations this was.
    final now = DateTime.now();

    test('announced but not started', () {
      final s = _sale(
          date: now.add(const Duration(days: 2)), start: '10:00', end: '12:00');
      expect(s.stage, TenderStage.open);
      expect(s.stage.label, 'Tender Open');
    });

    test('bidding under way', () {
      final s = _sale(date: now, start: '00:01', end: '23:59');
      expect(s.stage, TenderStage.running);
      expect(s.stage.label, 'Tender Started');
    });

    test('bidding closed, Central Disposal still deciding', () {
      // Closed earlier today; the deadline is a later working day.
      final s = _sale(date: now, start: '00:01', end: '00:02');
      expect(s.stage, TenderStage.awaitingDecision);
      expect(s.stage.label, 'Awaiting Decision');
    });

    test('a month-old sale is STILL awaiting a decision, not lapsed', () {
      // ⚠️ There is no longer a fourth stage. An item used to fall to
      // Unsold on its own once a working-day window closed, so a CLOCK decided
      // the outcome -- and a public holiday moved the deadline, which moved
      // which packages reached the DG. Central Disposal marks every item by
      // hand now, and a sale nobody has marked stays here however old it is.
      final s = _sale(
          date: now.subtract(const Duration(days: 30)),
          start: '10:00',
          end: '11:00');
      expect(s.stage, TenderStage.awaitingDecision);
      expect(s.stage.label, 'Awaiting Decision');
    });

    test('the sale says how long the decision has been outstanding', () {
      // What replaced the deadline: not a cut-off, but a note in the header.
      final s = _sale(
          date: now.subtract(const Duration(days: 3)),
          start: '10:00',
          end: '11:00');
      expect(s.sinceSaleStarted, isNotNull);
      expect(s.sinceSaleStarted!.inDays, greaterThanOrEqualTo(2));
    });

    test('a sale that has not started yet reports no elapsed time', () {
      final s = _sale(
          date: now.add(const Duration(days: 2)), start: '10:00', end: '11:00');
      expect(s.sinceSaleStarted, isNull);
    });

    test('an undated sale reads as open, never as decided', () {
      expect(_sale().stage, TenderStage.open);
    });

    test('every stage carries a description for its tooltip', () {
      for (final st in TenderStage.values) {
        expect(st.label, isNotEmpty);
        expect(st.description, isNotEmpty);
      }
    });

    test('the watched card shows the stage instead of a bare Pending', () {
      final disposal =
          _read('lib/screens/disposal/disposal_dashboard_screen.dart');
      final ro = disposal.substring(disposal.indexOf('if (widget.readOnly) {'));
      final block = ro.substring(0, 1400);
      expect(block, contains('widget.sale.stage'));
      expect(block, contains('stage.description'));
      expect(block, isNot(contains("'Pending'")));
    });
  });

  group('every portal opens and confirms the same way', () {
    const portals = {
      'appeal': 'lib/screens/appeal/appeal_login_screen.dart',
      'disposal': 'lib/screens/disposal/disposal_login_screen.dart',
      'valuation': 'lib/screens/valuation/valuation_login_screen.dart',
      'executive': 'lib/screens/executive/executive_login_screen.dart',
    };

    for (final p in portals.entries) {
      test('${p.key} confirms the OTP in green, not its own accent', () {
        // A sent code is a confirmation; tinting it with the portal colour
        // made it read as chrome.
        final src = _read(p.value);
        // Read to the END of the success branch rather than a fixed number of
        // characters: a fixed window broke the moment the comment above the
        // banner grew, which says nothing about the colour being right.
        final start = src.indexOf('if (_success != null');
        final banner = src.substring(start, src.indexOf('if (_error', start));
        expect(banner, contains('context.colors.successGreen'));
      });

      test('${p.key} animates its heading in, like the ICT portal', () {
        final src = _read(p.value);
        // Asserts the two animations exist, not the punctuation in front of
        // them. The heading used to sit in a Row (with the back arrow beside
        // it), so this read `]).animate()`; the arrow has since moved to the
        // page corner and the heading is a bare Text, which is a layout change
        // rather than a change to how it animates in.
        expect(src, contains('.animate()'));
        expect(src, contains('.fadeIn(duration: 400.ms)'));
        expect(src, contains('.fadeIn(delay: 100.ms)'));
      });
    }

    test('the ICT portal was already green, and still is', () {
      final ict = _read('lib/screens/ict/ict_login_screen.dart');
      expect(ict, contains('context.colors.successGreen'));
    });
  });

  group('the Top Management portal is named after its directorate', () {
    test('its sign-in reads like every other portal', () {
      // Appeal / Disposal / Valuation all name the directorate; this one said
      // "Executive", which nothing else calls it.
      final src = _read('lib/screens/executive/executive_login_screen.dart');
      expect(src, contains("Text('Top Management Sign In'"));
      expect(src, isNot(contains("Text('Executive Sign In'")));
    });
  });
}
