import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two separate dialogs both let a DC/SDDC record a final disposition, and
/// both had their own copy of the Release/Forfeit/Abandoned/Re-export/
/// Destroy/Other list. The Final Disposition sheet correctly enabled Destroy
/// for anyone but an officer; the "Actions" dialog (_PackageActionsDialog,
/// opened from the Abandoned / Detained / Forfeited / Other status pages) had
/// a SEPARATE, unconditional `_disabledForAll = {'Destroy'}` that grey-faded
/// the tile and blocked the tap regardless of role or an Appeal Directorate
/// decision -- so even a DC/SDDC carrying out a DESTROY ruling could never
/// actually press it from here.
void main() {
  test('the Actions dialog no longer hard-disables Destroy', () {
    final src =
        File('lib/widgets/package_details_dialog.dart').readAsStringSync();
    final i = src.indexOf('_disabledForAll');
    expect(i, greaterThan(-1));
    final decl = src.substring(i, i + 60);
    expect(decl, isNot(contains("{'Destroy'}")),
        reason: 'Destroy must be enabled the same as every other action.');
    expect(decl, contains('<String>{}'),
        reason: 'No action should be unconditionally disabled here.');
  });

  test('Destroy still routes through onDispose like every other action', () {
    // Not special-cased -- it shares the same tap handler, the same
    // _PackageSelectionDialog, and the same disposeWarehouseItem write as
    // Release / Forfeit / Abandoned / Re-export / Other.
    final src =
        File('lib/widgets/package_details_dialog.dart').readAsStringSync();
    final flat = src.replaceAll(RegExp(r'\s+'), ' ');
    expect(flat, contains("'Destroy': _DispositionMeta("),
        reason: 'The confirmation dialog needs its own icon/colour/label.');
  });
}
