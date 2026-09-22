// An office PC gets the app from the setup file and nothing else.
//
// ⚠️ cus_yard_management.exe LINKS AGAINST the Visual C++ runtime --
// msvcp140.dll, vcruntime140.dll, vcruntime140_1.dll. Those are not part of
// Windows; they arrive with the VC++ Redistributable, which a development
// machine has and a freshly-imaged office PC may not.
//
// Missing, the app does not show our "Cannot reach the database" screen --
// Windows refuses to start the process at all:
//
//     The code execution cannot proceed because VCRUNTIME140.dll was not
//     found.
//
// No Dart code has run at that point, so nothing in the app can explain it.
// The installer therefore carries them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final iss = File('installer/setup.iss').readAsStringSync();

  group('the installer needs nothing pre-installed', () {
    test('it ships the Visual C++ runtime', () {
      for (final dll in const [
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
      ]) {
        expect(iss, contains(dll),
            reason: '$dll is imported by the exe but not installed');
      }
    });

    test('the redistributable copies are actually in the tree', () {
      // ⚠️ The .iss naming them is not enough -- Inno Setup fails the
      // compile on a missing Source, but only when someone rebuilds.
      for (final dll in const [
        'msvcp140.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
      ]) {
        expect(File('installer/vcredist/$dll').existsSync(), isTrue,
            reason: 'installer/vcredist/$dll is missing');
      }
    });

    test('they are copied only if the PC does not already have them', () {
      // ⚠️ `onlyifdoesntexist`, never `ignoreversion`: overwriting a
      // newer system runtime with ours could break other programs.
      final lines = iss
          .split('\n')
          .where((l) => l.contains('vcredist') && l.startsWith('Source:'));
      expect(lines, isNotEmpty);
      for (final l in lines) {
        expect(l, contains('onlyifdoesntexist'), reason: l.trim());
      }
    });

    test('the deployment note says no other software is needed', () {
      final dep = File('installer/DEPLOYMENT.txt').readAsStringSync();
      expect(dep, contains('WHAT THIS PC NEEDS'));
      expect(dep, contains('No'));
      // The three things an officer might otherwise be told to install.
      for (final w in const ['Flutter', 'Visual Studio', 'PostgreSQL']) {
        expect(dep, contains(w));
      }
    });

    test('the .env is still NOT shipped', () {
      // ⚠️ Unchanged and important: it carries a live password and
      // differs per office. Only the templates ship.
      expect(iss, contains('env-templates'));
      expect(iss, isNot(contains(r'Source: ".env"')));
    });
  });
}
