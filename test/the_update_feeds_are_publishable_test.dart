// The release pipeline has to produce something an officer's PC can actually
// read, and the three version strings have to agree before it does.
//
// ⚠️ A drift between them is invisible until it misbehaves in the worst way:
// an app whose kAppVersion trails the published one offers the same update
// forever; one that leads it never offers anything at all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `version: 1.2.0+3` -> `1.2.0`
String _pubspecVersion() {
  final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync());
  return m!.group(1)!;
}

void main() {
  group('the three version strings agree', () {
    test('pubspec, the installer and the app all say the same version', () {
      final pubspec = _pubspecVersion();

      final iss = RegExp(r'^#define\s+AppVersion\s+"([^"]+)"', multiLine: true)
          .firstMatch(File('installer/setup.iss').readAsStringSync());
      expect(iss, isNotNull, reason: 'no AppVersion in installer/setup.iss');

      final dart = RegExp(r"defaultValue:\s*'(\d+\.\d+\.\d+)'")
          .firstMatch(File('lib/core/update_check.dart').readAsStringSync());
      expect(dart, isNotNull, reason: 'no kAppVersion default');

      expect(iss!.group(1), pubspec,
          reason: 'installer/setup.iss disagrees with pubspec.yaml — '
              'run tool/release.ps1 -Version <x.y.z>');
      expect(dart!.group(1), pubspec,
          reason: 'kAppVersion disagrees with pubspec.yaml — '
              'run tool/release.ps1 -Version <x.y.z>');
    });
  });

  group('the appcast generator', () {
    final src = File('tools/generate_appcast.py').readAsStringSync();

    test('it refuses to write a feed when the versions disagree', () {
      // ⚠️ The guard is the point of the script. Without it the feed can
      // quote a version the .exe does not carry.
      expect(src, contains('version mismatch'));
      expect(src, contains('read_installer_version'));
    });

    test('the enclosure points at the public Supabase object URL', () {
      // Not the dashboard, not a signed URL: the app fetches this before
      // anybody has signed in, so it must need no token.
      expect(src, contains('/storage/v1/object/public/updates'));
    });

    test('it writes BOTH feeds', () {
      // ⚠️ Two independent update paths read two different formats.
      // Publishing one without the other leaves half the officers on a
      // version the other half is not offered.
      expect(src, contains('appcast.xml'));
      expect(src, contains('latest.json'));
    });

    test('latest.json keeps the shape update_check.dart already parses', () {
      // update_check.dart was written against the GitHub Releases API.
      // Matching that shape is what lets the banner work from Supabase
      // with no change to the Dart or to update_check_test.dart.
      for (final key in const [
        'tag_name',
        'draft',
        'prerelease',
        'assets',
        'browser_download_url',
      ]) {
        expect(src, contains(key), reason: '$key missing from latest.json');
      }
    });
  });

  group('the feed stops offering a version already installed', () {
    final src = File('tools/generate_appcast.py').readAsStringSync();

    test('sparkle:version is the FULL version the exe carries', () {
      // ⚠️ Windows reads `1.3.0+4` off the binary (Flutter stamps
      // pubspec's whole version string, build number included). Writing
      // only the build number here compared
      //
      //     "4"  vs  "1.3.0+4"
      //
      // which is never equal -- so an officer who installed the update was
      // offered the SAME version again after every restart, for ever.
      expect(src, contains("exe_version = '%s+%s' % (version, build)"));
      expect(src, contains('sparkle:version="%(exe_version)s"'));
    });

    test('it is NOT the bare build number any more', () {
      expect(src, isNot(contains('sparkle:version="%(build)s"')),
          reason: 'that is the bug that re-offered an installed version');
    });
  });

  group('the shipping build is obfuscated', () {
    final pub = File('tool/publish_release.ps1').readAsStringSync();

    test('publish_release.ps1 passes --obfuscate', () {
      // ⚠️ This is the script that builds every release. An earlier
      // tool/build_release.ps1 obfuscated, but nothing shipped through
      // it -- so releases were going out unobfuscated while a script
      // that did the right thing sat unused beside it.
      expect(pub, contains("'--obfuscate'"));
    });

    test('and keeps the symbols, per version', () {
      // ⚠️ --obfuscate WITHOUT --split-debug-info throws the symbol
      // map away. A crash from that build can never be turned back
      // into a readable stack trace.
      expect(pub, contains('--split-debug-info='));
      const bs = '\\';
      expect(pub, contains('build' + bs + 'symbols' + bs + r'$version+$build'));
    });

    test('the folder is created before the build', () {
      expect(pub, contains('New-Item -ItemType Directory -Force -Path \$symbolDir'));
    });

    test('a build that wrote no symbols is a failure', () {
      // Better to fail now than to discover it months later, holding a
      // crash report and no way to read it.
      expect(pub, contains('wrote no debug symbols'));
    });

    test('symbols are not committed', () {
      final ignore = File('.gitignore').readAsStringSync();
      expect(ignore, contains('/build/symbols/'));
    });

    test('the comment does not overclaim what obfuscation does', () {
      // ⚠️ It renames SYMBOLS. A compiled-in password is still
      // recoverable with `strings`. Saying otherwise in a comment is
      // how a reader ends up trusting it for something it cannot do.
      expect(pub, contains('IT DOES NOT HIDE THOSE PASSWORDS'));
    });
  });

  group('bumping the version is a separate step', () {
    final rel = File('tool/release.ps1').readAsStringSync();
    final pub = File('tool/publish_release.ps1').readAsStringSync();

    test('publish_release does NOT bump anything', () {
      // ⚠️ It builds what the version files already say. Running it
      // twice therefore publishes the SAME version twice, and an officer
      // on that version is never offered the second one -- which is
      // exactly what happened: two 1.3.0 installers, no update.
      expect(pub, isNot(contains("-replace '(?m)^version:")));
      expect(pub, contains('VERSION MISMATCH'),
          reason: 'it should verify the three strings, not write them');
    });

    test('release.ps1 writes all three from one argument', () {
      for (final f in const [
        'pubspec.yaml',
        'installer/setup.iss',
        'lib/core/update_check.dart',
      ]) {
        expect(rel, contains(f));
      }
    });

    test('it also raises the BUILD number', () {
      // ⚠️ sparkle:version is `1.4.0+5`, build number included. Two
      // releases sharing a build number are indistinguishable to
      // WinSparkle even when the dotted version differs.
      expect(rel, contains(r'[int]$Matches[2] + 1'));
    });

    test('one part at a time: -Patch, -Minor, -Major', () {
      // 4.2.1 -> 4.2.2 (a small fix), 4.2.2 -> 4.3.0 (a feature),
      // 4.3.0 -> 5.0.0 (a big release).
      for (final f in const [r'$Patch', r'$Minor', r'$Major']) {
        expect(rel, contains('[switch]' + f));
      }
    });

    test('a minor bump RESETS the patch, a major resets both', () {
      // ⚠️ Otherwise 4.2.2 + -Minor would be 4.3.2, the numbers stop
      // meaning anything, and an officer cannot tell which release is
      // newer.
      expect(rel, contains(r'if     ($Major) { $ma++; $mi = 0; $pa = 0 }'));
      expect(rel, contains(r'elseif ($Minor) { $mi++; $pa = 0 }'));
    });

    test('it refuses -Version together with a bump flag', () {
      // ⚠️ A contradiction. Silently preferring one would ship a
      // release numbered differently from what was typed.
      expect(rel, contains('not both.'));
    });

    test('the version stays THREE parts', () {
      // ⚠️ Not style: pubspec takes `x.y.z+n`, and Flutter writes that
      // into Windows' four-number FILEVERSION with the build number in
      // the fourth slot. 4.2.2.1 would leave nowhere for it.
      expect(rel, contains(r"[ValidatePattern('^\d+\.\d+\.\d+$')]"));
    });

    test('-BumpOnly stops before a build with no defines', () {
      // ⚠️ release.ps1's own `flutter build` passes no --dart-define,
      // so it makes a binary with NO credentials and NO update feed.
      // publish_release.ps1 passes both; -BumpOnly is what hands over.
      expect(rel, contains(r'[switch]$BumpOnly'));
      expect(rel, contains(r'if ($BumpOnly) {'));
      expect(rel, contains('publish_release.ps1'));
    });
  });

  group('the release notes are readable', () {
    final src = File('tools/generate_appcast.py').readAsStringSync();

    test('the notes are wrapped in a styled HTML document', () {
      // ⚠️ WinSparkle renders this in an embedded browser. Bare text
      // inherits no styling at all and came out white-on-black with the
      // whole line selected.
      expect(src, contains('<html>'));
      expect(src, contains('background:#ffffff'));
      expect(src, contains('color:#1a1a1a'));
    });

    test('selected text stays dark', () {
      // The pane opens with the first line highlighted; without this the
      // selection is what made it unreadable.
      expect(src, contains('::selection'));
    });

    test('the note is escaped before it becomes HTML', () {
      // It is typed on the command line. An unescaped & or < would break
      // the rest of the pane.
      expect(src, contains('_notes_to_html'));
      expect(src, contains('escape(s)'));
    });
  });

  group('the manual check reports what it could not do', () {
    final src = File('lib/core/app_updater.dart').readAsStringSync();

    test('checkForUpdatesNow returns an outcome rather than void', () {
      // ⚠️ WinSparkle shows its own window when the check RUNS, but shows
      // nothing at all when there is no feed. Without a return value the
      // button looks dead in exactly that case.
      expect(src, contains('Future<UpdateCheckOutcome> checkForUpdatesNow()'));
    });

    test('every case a button has to explain is named', () {
      for (final v in const [
        'started',
        'notConfigured',
        'feedRefused',
        'unsupportedPlatform',
        'failed',
      ]) {
        expect(src, contains(v));
      }
    });

    test('an http feed is still refused unless it is private and opted in',
        () {
      // Unchanged by this work, and worth keeping pinned: the feed decides
      // which .exe the app downloads and runs.
      expect(src, contains('allowInsecureUpdateFeed'));
      expect(src, contains('_isPrivateHost'));
    });
  });

  group('the app shows its OWN update notice, not WinSparkle''s', () {
    final au = File('lib/core/app_updater.dart').readAsStringSync();
    final banner = File('lib/widgets/update_banner.dart').readAsStringSync();

    test('no unattended native check is started', () {
      // ⚠️ WinSparkle draws a native Win32 window -- its own grey
      // chrome, its own sun icon, its own fonts. Nothing in the package
      // exposes its colours, because it belongs to a C library rather
      // than to Flutter. Left running, it appeared ON TOP of the app's
      // own themed notice.
      expect(au, isNot(contains('setScheduledCheckInterval')));
      expect(au, isNot(contains('checkForUpdates(inBackground: true)')));
    });

    test('but the feed is still registered', () {
      // That is what makes the manual "Check for Updates" button work --
      // and a native window is reasonable when somebody ASKED for it.
      expect(au, contains('setFeedURL(updateFeedUrl)'));
      expect(au, contains('autoUpdater.checkForUpdates()'));
    });

    test('the themed strip is what appears by itself', () {
      expect(banner, contains('primaryGold'));
      expect(banner, contains('showUpdateDialog'));
    });

    test('and it says the app must be closed to install', () {
      // ⚠️ Windows refuses to overwrite a running .exe. An officer who
      // leaves the app open sees the setup fail for a reason it never
      // explains.
      expect(banner, contains('CLOSED'));
    });
  });

  group('Update means update, not download', () {
    final banner = File('lib/widgets/update_banner.dart').readAsStringSync();

    test('the button starts WinSparkle, not a browser', () {
      // ⚠️ Opening the URL handed the officer a file in Downloads to
      // find and run -- and on a PC with a download manager installed,
      // that manager grabbed the link and the app never heard of it
      // again. WinSparkle fetches and launches the installer itself.
      expect(banner, contains('startUpdate('));
      expect(banner, contains('checkForUpdatesNow()'));
      expect(banner, isNot(contains('onPressed: () => openUpdateDownload(')),
          reason: 'the strip button must not open a browser');
    });

    test('the browser stays as a fallback', () {
      // A build with no UPDATE_FEED_URL has no WinSparkle feed to use.
      // ⚠️ The app still never downloads and executes an .exe itself;
      // that is what makes the browser acceptable here.
      expect(banner, contains('openUpdateDownload(update.downloadUrl)'));
      expect(banner, contains('UpdateCheckOutcome.started'));
    });

    test('a dead button always says something', () {
      expect(banner, contains('Could not start the update'));
    });
  });

  group('a fresh install can actually sign in', () {
    final iss = File('installer/setup.iss').readAsStringSync();

    test('the installer writes the Gmail keys too', () {
      // ⚠️ Sign-in sends a one-time code. Without these the app
      // reaches the database and then stops at "E-mail is not
      // configured" -- a fresh install is not half-configured, it is
      // locked.
      expect(iss, contains('GMAIL_USER='));
      expect(iss, contains('GMAIL_APP_PASSWORD='));
      expect(iss, contains('GMAIL_FROM_NAME='));
    });

    test('the App Password is quoted', () {
      // ⚠️ Google shows it as four space-separated groups, and an
      // unquoted value with spaces is a different string once dotenv
      // has read it.
      expect(iss, contains(r"""'GMAIL_APP_PASSWORD="' + GmailPw + '"'"""));
    });

    test('it comes from a compile-time define, not the source', () {
      expect(iss, contains('#ifndef GmailPassword'));
      expect(iss, contains("GmailPw := '{#GmailPassword}';"));
    });
  });

  group('the update button appears only when there IS an update', () {
    final btn = File('lib/widgets/update_available_button.dart')
        .readAsStringSync();

    test('it renders nothing when there is no update', () {
      // ⚠️ This replaced a permanent "Check for Updates" button --
      // a question almost nobody wants to ask, since nearly every
      // press answered "nothing new". The app already knows from the
      // start-up check, so it offers the ACTION instead.
      expect(btn, contains('if (update == null) return const SizedBox.shrink();'));
    });

    test('it reads the same value the gold strip does', () {
      // One source of truth: fetchAvailableUpdate() publishes to
      // availableUpdate at start-up and both read it.
      expect(btn, contains('valueListenable: availableUpdate'));
    });

    test('pressing it UPDATES rather than checking', () {
      // startUpdate hands the work to WinSparkle, which downloads and
      // launches the installer. Nothing lands in Downloads.
      expect(btn, contains('startUpdate(context, update)'));
    });

    test('the label names the version', () {
      // ⚠️ "Update" alone says nothing about what is being installed.
      expect(btn, contains("'Update to "));
    });
  });

  group('every portal offers it', () {
    // ⚠️ Four separate headers. AppShell covers the yard, executive
    // and valuation portals; ICT, Appeal and Disposal each build their
    // own and inherit nothing from it -- which is how the ICT console
    // missed the button when it was added to the shell alone.
    const headers = {
      'the yard shell': 'lib/widgets/app_shell.dart',
      'the ICT console': 'lib/screens/ict/ict_dashboard_screen.dart',
      'Appeal': 'lib/screens/appeal/appeal_dashboard_screen.dart',
      'Disposal': 'lib/screens/disposal/disposal_dashboard_screen.dart',
    };

    headers.forEach((name, path) {
      test('$name shows the shared button', () {
        final src = File(path).readAsStringSync();
        expect(src, contains('UpdateAvailableButton('),
            reason: '$path has its own header and needs the button');
        expect(src, contains('updateButtonLabel(update)'));
      });
    });

    test('none of them rolls its own copy', () {
      // A second implementation would drift the first time one was
      // corrected.
      for (final path in headers.values) {
        final src = File(path).readAsStringSync();
        // ⚠️ The LABEL, not the bare words. Both files carry a
        // comment explaining why the always-on button went, and
        // matching the phrase would fail on the explanation itself.
        expect(src, isNot(contains("Text('Check for Updates'")),
            reason: '$path still has the old always-on button');
      }
    });
  });

  group('the ICT tables have room at the right edge', () {
    final ui = File('lib/screens/ict/ict_ui.dart').readAsStringSync();
    final tab =
        File('lib/screens/ict/yard_directorate_tab.dart').readAsStringSync();

    test('the Actions column carries a trailing inset', () {
      // ⚠️ Without it the toggle ends exactly where the card's padding
      // begins, so the control looks pinned to the border while every
      // other column has air around it.
      expect(ui, contains('kIctTableEndInset'));
      expect(ui, contains('kIctIconButtonSize * 2 + 8 + 16 + kIctTableEndInset'));
    });

    test('the inset widens the COLUMN, not the row padding', () {
      // ⚠️ The header and the rows share one width list. Row padding
      // would move the cells and leave the heading behind.
      expect(ui, contains('const double kIctTableEndInset'));
    });

    test('the directorate name gets the share that varies', () {
      // SR Prefix is a fixed-width chip and Code is three or four
      // characters; the NAME is the only column whose content varies.
      expect(tab, contains('const widths = [2, 2, 9];'));
    });

    test('Status and Actions stay FIXED, never flex', () {
      // Given a flex share they become the narrowest columns in a wide
      // row -- which is how the toggle once spilled past the card.
      expect(tab, contains('const fixed = [kIctStatusColumnWidth, kIctActionsColumnWidth];'));
    });
  });

}
