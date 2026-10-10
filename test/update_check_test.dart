// Telling a branch office that a newer version exists.
//
// The app is installed at several offices against one cloud database, and
// updates get published from time to time. Nobody visits the branches, so the
// app has to notice for itself — and the comparison that decides whether to
// interrupt an officer has to be right in both directions: a false positive
// nags forever, a false negative means a yard never updates at all.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/update_check.dart';

void main() {
  group('versions compare as NUMBERS, never as text', () {
    test('a later patch is newer', () {
      expect(compareVersions('1.1.0', '1.1.1'), lessThan(0));
      expect(compareVersions('1.1.1', '1.1.0'), greaterThan(0));
    });

    test('the same release compares equal', () {
      expect(compareVersions('1.2.3', '1.2.3'), 0);
    });

    test('1.10.0 is newer than 1.9.0', () {
      // ⚠️ THE bug a string compare produces: '1' sorts before '9', so
      // '1.10.0' would read as OLDER and every update from 1.9 onward would
      // be invisible. This is why the parts are parsed as ints.
      expect(compareVersions('1.9.0', '1.10.0'), lessThan(0));
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    });

    test('a leading v is tolerated, because GitHub tags carry one', () {
      expect(compareVersions('1.1.0', 'v1.2.0'), lessThan(0));
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
    });

    test('a build suffix names the same release', () {
      // pubspec carries 1.1.0+2; the tag is 1.1.0. They are one release.
      expect(compareVersions('1.1.0+2', '1.1.0'), 0);
      expect(compareVersions('1.1.0+9', '1.1.1'), lessThan(0));
    });

    test('a missing segment counts as zero', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2', '1.2.1'), lessThan(0));
    });

    test('rubbish sorts as zero rather than throwing', () {
      // A malformed tag must not crash a startup check.
      expect(compareVersions('', '1.0.0'), lessThan(0));
      expect(compareVersions('not-a-version', '0.0.0'), 0);
    });
  });

  group('the installer is picked out of the release', () {
    test('the .exe is chosen', () {
      final a = pickWindowsInstaller([
        {'name': 'checksums.txt', 'browser_download_url': 'x'},
        {'name': 'SLCustoms-SR-Setup-1.2.0.exe', 'browser_download_url': 'y'},
      ]);
      expect(a?['browser_download_url'], 'y');
    });

    test('a release with no installer yields nothing', () {
      // ⚠️ Rather than handing the officer a source zip to "install".
      expect(pickWindowsInstaller([
        {'name': 'Source code.zip', 'browser_download_url': 'x'},
      ]), isNull);
      expect(pickWindowsInstaller(const []), isNull);
    });
  });

  group('a database behind the app is named, not stumbled over', () {
    test('an equal or newer database is fine', () {
      // ⚠️ The MINIMUM, not an exact match: the server is migrated first and
      // the branches follow over days. Every older copy must keep working.
      expect(schemaMismatchMessage(43, required: 43), isNull);
      expect(schemaMismatchMessage(44, required: 43), isNull);
    });

    test('an older database is reported in plain words', () {
      final m = schemaMismatchMessage(42, required: 43);
      expect(m, isNotNull);
      expect(m, contains('version 42'));
      expect(m, contains('system administrator'));
    });

    test('an UNKNOWN version is not treated as old', () {
      // A database that predates schema_version() answers with an error.
      // Reading that as 0 would refuse to start against every yard not yet
      // migrated — the opposite of helpful.
      expect(schemaMismatchMessage(null, required: 43), isNull);
    });
  });

  group('the three version numbers cannot drift', () {
    // ⚠️ pubspec, the installer and the app's own constant must agree, or the
    // notice misbehaves in the worst way: behind, and every branch is told
    // forever to install what they already have; ahead, and nobody is ever
    // told anything.
    String versionIn(String path, RegExp re) {
      final m = re.firstMatch(File(path).readAsStringSync());
      expect(m, isNotNull, reason: 'no version found in $path');
      return m!.group(1)!;
    }

    test('pubspec, setup.iss and kAppVersion say the same thing', () {
      final pub = versionIn('pubspec.yaml', RegExp(r'^version:\s*([\d.]+)\+', multiLine: true));
      final iss = versionIn('installer/setup.iss', RegExp(r'#define AppVersion\s+"([^"]+)"'));
      final dart = versionIn('lib/core/update_check.dart',
          RegExp(r"APP_VERSION', defaultValue: '([^']+)'"));
      expect(iss, pub, reason: 'installer/setup.iss is out of step with pubspec');
      expect(dart, pub, reason: 'kAppVersion is out of step with pubspec');
    });

    test('one script writes all three', () {
      final rel = File('tool/release.ps1').readAsStringSync();
      expect(rel, contains('pubspec.yaml'));
      expect(rel, contains('installer/setup.iss'));
      expect(rel, contains('lib/core/update_check.dart'));
    });
  });

  group('the download is opened, never executed', () {
    test('the app does not fetch and run the installer itself', () {
      // ⚠️ Downloading and silently running an .exe is the shape of an
      // attack, and it bypasses SmartScreen and antivirus prompts. The
      // browser is where "should I run this?" already has an answer.
      final src = File('lib/core/update_check.dart').readAsStringSync();
      expect(src, contains("Process.run('cmd', ['/c', 'start', '', url])"));
      expect(src.contains('Process.run(url'), isFalse);
    });

    test('a non-https URL is refused', () {
      final src = File('lib/core/update_check.dart').readAsStringSync();
      expect(src, contains("uri.scheme != 'https'"));
    });

    test('drafts and pre-releases are skipped', () {
      final src = File('lib/core/update_check.dart').readAsStringSync();
      expect(src, contains("json['draft'] == true || json['prerelease'] == true"));
    });
  });
}
