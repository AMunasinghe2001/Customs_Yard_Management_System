import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

/// Destruction is NOT a disposal request.
///
/// A yard destroying goods records it as a Final Disposition, which writes the
/// item's destruction tag directly and puts it on the Destroyed Goods pages.
/// It never reaches the Valuation Directorate or Central Disposal's Disposal
/// Requests, and there is no route by which it could — so offering it as a
/// disposition only produced request rows that sat in both queues with nothing
/// anyone could do to them.
void main() {
  group('a request can only be for sale', () {
    test('destruction is not on offer', () {
      expect(kDispositions.containsKey('destruction'), isFalse,
          reason: 'destruction would create an unactionable request row');
      expect(kDispositions.keys, ['sale']);
    });

    test('the default a new item is created with is sale', () {
      expect(kDefaultDisposition, 'sale');
      expect(kDispositions.containsKey(kDefaultDisposition), isTrue);
    });

    test('a row missing its disposition reads back as sale, not destruction',
        () {
      final item = DisposalRequestItemModel.fromJson({
        'id': 'i1',
        'request_id': 'r1',
        'forfeited_package_id': 'f1',
      });
      expect(item.disposition, 'sale');
    });

    test('a legacy destruction row still reads back as itself', () {
      // Removing the option must not silently relabel historical data as a
      // sale — a row that says destruction still says so when read.
      final item = DisposalRequestItemModel.fromJson({
        'id': 'i1',
        'request_id': 'r1',
        'forfeited_package_id': 'f1',
        'disposition': 'destruction',
      });
      expect(item.disposition, 'destruction');
      expect(dispositionLabel('destruction'), 'destruction',
          reason: 'no label is offered for a disposition that cannot be made');
    });

    test('counting still distinguishes the two', () {
      final req = DisposalRequestModel(
        id: 'r1',
        yard: 'GL1',
        requestDate: DateTime(2026, 1, 1),
        status: 'pending',
        createdAt: DateTime(2026, 1, 1),
        items: const [
          DisposalRequestItemModel(
              id: 'a', requestId: 'r1', forfeitedPackageId: 'f1',
              disposition: 'sale'),
          DisposalRequestItemModel(
              id: 'b', requestId: 'r1', forfeitedPackageId: 'f2',
              disposition: 'sale'),
        ],
      );
      expect(req.saleCount, 2);
      expect(req.destructionCount, 0);
    });
  });

  group('the yard is never offered the choice', () {
    final dialog = File(
            'lib/screens/forfeited_packages/disposal_request_dialog.dart')
        .readAsStringSync();

    test('the disposition toggle is gone from the request dialog', () {
      expect(dialog, isNot(contains('_DispositionToggle')),
          reason: 'the yard could still tag a request for destruction');
      expect(dialog, isNot(contains("seg('destruction'")));
    });

    test('every package a request selects is tagged sale', () {
      // The only assignment into the selection map.
      expect(dialog, contains("map[pkg.id] = 'sale'"));
      expect(dialog, isNot(contains("= 'destruction'")));
    });
  });
}
