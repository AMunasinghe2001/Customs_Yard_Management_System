// Page headings were marked with emoji, and emoji were the wrong tool.
//
// They render from a colour font, so they cannot be tinted: 🏷️ stayed orange
// and ♻️ stayed green against a palette built from one gold accent, and none of
// them changed with the light/dark theme -- the only thing on the page that
// did not. They were also applied unevenly: Perishable, the one page reused
// from the yard side, had no mark at all.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/widgets/page_title.dart';

/// Everything a user actually reads on screen.
final _screens = Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Colour-emoji planes. Deliberately NOT including U+FE0F or the dingbats
/// block that ⚠️ lives in -- that one is all over the comments, on purpose.
final _emoji = RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true);

void main() {
  group('no emoji is left in anything the user reads', () {
    test('not in ANY string, however the call is wrapped', () {
      // ⚠️ This test used to require the emoji and the `Text(` on the SAME
      // line, and Taxes wrapped its call across two:
      //
      //     Text(
      //       '📊  Tax Configuration',
      //
      // So the one page that still had a colour emoji was the one page the
      // test could not see. Now it looks at every string literal, whatever
      // encloses it -- a formatting choice can no longer hide a finding.
      final offenders = <String>[];
      for (final f in _screens) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          // The ⚠️ marks in comments are wanted; only strings count.
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          if (!_emoji.hasMatch(line)) continue;
          // A quote anywhere on the line means the emoji is in a literal
          // rather than in a trailing comment.
          if (!line.contains("'") && !line.contains('"')) continue;
          // ⚠️ Two known emoji are NOT headings and stay: a 🔴 inside a
          // dropdown option string (a plain String, with no widget to hang an
          // Icon on) and a 🛑 in a Supabase error message that no longer runs.
          // Narrow exceptions, listed here so a THIRD one cannot slip in
          // quietly under the same excuse.
          if (line.contains('FULL 🔴') || line.contains('Email Limit')) {
            continue;
          }
          offenders.add('${f.path}:${i + 1}  ${trimmed.trim()}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'emoji cannot be tinted — use PageTitle/titleIcon instead');
    });
  });

  group('the mark is an icon, and it takes the theme', () {
    testWidgets('it is tinted with the same gold as the nav rail', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: PageTitle('Perishable Goods', Icons.eco_rounded),
        ),
      ));
      final icon = t.widget<Icon>(find.byIcon(Icons.eco_rounded));
      // Read from the theme, not from a constant: the point is that the mark
      // takes whatever gold the active theme carries.
      final gold =
          AppTheme.darkTheme.extension<AppColors>()!.primaryGold;
      expect(icon.color, gold);
    });

    testWidgets('and it follows the theme, which an emoji could not',
        (t) async {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
            body: PageTitle('Sold Goods', Icons.sell_rounded)),
      ));
      final darkText = t.widget<Text>(find.text('Sold Goods'));

      // ⚠️ A fresh key, or Flutter reuses the element and never rebuilds the
      // subtree -- the second pump would read back the FIRST theme's colour
      // and the test would pass whatever the widget did.
      await t.pumpWidget(MaterialApp(
        key: const ValueKey('light'),
        theme: AppTheme.lightTheme,
        home: const Scaffold(
            body: PageTitle('Sold Goods', Icons.sell_rounded)),
      ));
      final lightText = t.widget<Text>(find.text('Sold Goods'));

      // ⚠️ The whole point: the heading changes with the theme. An emoji
      // rendered the same bitmap in both.
      expect(darkText.style?.color, isNot(lightText.style?.color));
    });

    testWidgets('a long title ellipsises rather than overflowing', (t) async {
      // These headings sit beside a fixed 300px search box and a 220px yard
      // filter, so the title is the only part that can give.
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: SizedBox(
            width: 160,
            child: PageTitle(
                'Undestroyed Packages — Re-destruction', Icons.sell_rounded),
          ),
        ),
      ));
      expect(tester_noOverflow(t), isTrue);
      final text = t.widget<Text>(
          find.text('Undestroyed Packages — Re-destruction'));
      expect(text.overflow, TextOverflow.ellipsis);
    });
  });

  group('every Central Disposal page carries a mark', () {
    final dash = File('lib/screens/disposal/disposal_dashboard_screen.dart')
        .readAsStringSync();

    test('the shared Unsold tab takes one per instance', () {
      expect(dash, contains('final IconData titleIcon;'));
      // Government Use, Auction, Converted, Removed -- four reuses of one tab,
      // each needing its own mark.
      expect('titleIcon:'.allMatches(dash).length, greaterThanOrEqualTo(4));
    });

    test('Perishable is no longer the one page without a mark', () {
      // ⚠️ This is the page the bug report was about. It is a YARD screen
      // reused read-only in Central Disposal, so it missed the pass that gave
      // every other tab its emoji.
      final per = File('lib/screens/packages/perishable_goods_screen.dart')
          .readAsStringSync();
      // ⚠️ Only the READ-ONLY copy carries a mark. That one is Central
      // Disposal's; the yard's own copy has none, because the marks were only
      // ever meant for that portal's tab strip.
      expect(per, contains("PageTitle('Perishable Goods', Icons.eco_rounded"));
      final yardHeader = per.substring(per.indexOf('] else'));
      expect(yardHeader.contains('titleIcon:'), isFalse);
    });

    test('the heading reuses the icon its own tab shows', () {
      // The eye should carry one mark from the tab it clicked to the heading
      // that answers it.
      for (final pair in [
        ['Sold Goods', 'Icons.sell_rounded'],
        ['Destroyed Goods', 'Icons.delete_forever_rounded'],
        ['Disposal Requests', 'Icons.assignment_turned_in_rounded'],
        ['Tender Sales', 'Icons.storefront_rounded'],
        ['Tender Committees', 'Icons.groups_rounded'],
      ]) {
        // The call also passes the portal's accent now, so match up to the
        // icon rather than to the closing bracket.
        expect(dash, contains("PageTitle('${pair[0]}', ${pair[1]}"),
            reason: '${pair[0]} should use its tab strip icon');
      }
    });
  });

  group('the yard-side header gained the same option', () {
    final header =
        File('lib/widgets/disposal_page_header.dart').readAsStringSync();

    test('the icon is optional, so nothing is forced to carry one', () {
      expect(header, contains('final IconData? titleIcon;'));
      expect(header, contains('if (titleIcon != null)'));
    });

    test('it defaults to gold, and a portal may pass its own', () {
      // ⚠️ Gold is the nav rail's colour and right for the yard. A
      // directorate passes its own accent -- gold marks on Central Disposal's
      // green pages looked borrowed from somewhere else, because they were.
      expect(header, contains('titleIconColor ??'));
      expect(header, contains('context.colors.primaryGold'));
    });

    test('the held-goods pages carry no mark at all', () {
      // ⚠️ These are YARD pages. The heading marks were only ever meant for
      // Central Disposal, whose tab strip they echo -- on the yard, where the
      // nav rail already shows the icon beside the page name, a second copy
      // in the heading said nothing new.
      for (final path in [
        'lib/screens/packages/detained_packages_screen.dart',
        'lib/screens/packages/abandoned_packages_screen.dart',
        'lib/screens/forfeited_packages/forfeited_packages_screen.dart',
        'lib/screens/packages/other_packages_screen.dart',
      ]) {
        expect(File(path).readAsStringSync().contains('titleIcon:'), isFalse,
            reason: '$path has a heading icon again');
      }
    });

    test('the rail still names an icon for each of those pages', () {
      // ⚠️ Asserted against the rail itself, so the two cannot drift apart
      // silently after someone edits one of them.
      final rail = File('lib/widgets/app_shell.dart').readAsStringSync();
      for (final pair in [
        ["'Detained Goods', Icons.gpp_maybe_rounded"],
        ["'Abandoned Goods', Icons.inbox_rounded"],
        ["'Forfeited Goods', Icons.gavel_rounded"],
        ["'Other Goods', Icons.label_important_rounded"],
        ["'Perishable Goods', Icons.eco_rounded"],
      ]) {
        expect(rail, contains(pair[0]));
      }
    });
  });
}

/// True when nothing overflowed during the pump.
bool tester_noOverflow(WidgetTester t) {
  return t.takeException() == null;
}
