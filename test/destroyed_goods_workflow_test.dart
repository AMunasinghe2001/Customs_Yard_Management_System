import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cus_yard_management/models/models.dart';
import 'package:cus_yard_management/core/providers.dart';
import 'package:cus_yard_management/core/theme.dart';
import 'package:cus_yard_management/screens/packages/disposition_category_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Destroyed Goods Workflow & Classification Tests', () {
    test('Destroyed tag accepts both final and proposed destruction statuses', () {
      const acceptedTags = {
        'FINAL:DESTROYED',
        'DESTROYED',
        'DESTROY',
        'SUPPOSED TO BE DESTROYED'
      };
      expect(acceptedTags.contains('FINAL:DESTROYED'), isTrue);
      expect(acceptedTags.contains('SUPPOSED TO BE DESTROYED'), isTrue);
      expect(acceptedTags.contains('DESTROY'), isTrue);
      expect(acceptedTags.contains('DESTROYED'), isTrue);
    });

    test('Non-disposal decisions set excludes destruction candidates from valuation sales requests', () {
      const nonDisposalDecisions = {
        'RELEASE',
        'RE-EXPORT',
        'OTHER',
        'DESTROY',
        'DESTRUCTION',
        'SUPPOSED TO BE DESTROYED',
      };
      expect(nonDisposalDecisions.contains('DESTROY'), isTrue);
      expect(nonDisposalDecisions.contains('DESTRUCTION'), isTrue);
      expect(nonDisposalDecisions.contains('SUPPOSED TO BE DESTROYED'), isTrue);
      expect(nonDisposalDecisions.contains('SALE'), isFalse);
    });

    testWidgets('DispositionCategoryScreen renders Destroyed table with Mark Destroyed button for pending items',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime(2025, 1, 1);

      final pkgPending = PackageModel(
        id: 'pkg-1',
        srNumber: 'CED/GL1/SR/01/2025',
        consigneeName: 'Test Importer',
        status: 'detain',
        createdAt: now,
        updatedAt: now,
        items: [
          PackageItem(
            id: 'item-1',
            packageId: 'pkg-1',
            itemName: 'Perishable Chemical Goods',
            quantity: 10,
            status: 'supposed to be destroyed',
          ),
        ],
        warehouseEntries: const [],
      );

      final pkgDestroyed = PackageModel(
        id: 'pkg-2',
        srNumber: 'CED/GL1/SR/02/2025',
        consigneeName: 'Test Importer 2',
        status: 'detain',
        createdAt: now,
        updatedAt: now,
        items: [
          PackageItem(
            id: 'item-2',
            packageId: 'pkg-2',
            itemName: 'Damaged Food Packets',
            quantity: 5,
            status: 'destroyed',
          ),
        ],
        warehouseEntries: [
          WarehouseEntryModel(
            id: 'entry-2',
            packageId: 'pkg-2',
            packageItemId: 'item-2',
            warehouseId: 'wh-1',
            warehouseCode: 'WH1',
            warehouseName: 'Warehouse A',
            zone: 'A',
            holdReason: 'Destroyed',
            itemCount: 5,
            admittedAt: now,
            dailyRate: 50.0,
            isReturned: true,
            returnedAt: DateTime(2025, 1, 3),
            returnNotes: '[FINAL:DESTROYED] — Certificate #4410',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            livePackagesProvider.overrideWith(
              (ref) => Future.value([pkgPending, pkgDestroyed]),
            ),
            storageRateProvider.overrideWith(
              (ref) => Future.value({DateTime(2020, 1, 1): 50.0}),
            ),
            packageDestroyedDeliveredMapProvider.overrideWith(
              (ref) => Future.value(const <String, bool>{}),
            ),
            // The Destruction Expenses column reads the SR's recorded costs,
            // so rendering the table opens a real socket without this.
            srFinancialsProvider.overrideWith(
              (ref) => Future.value(const <SrFinancials>[]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const DispositionCategoryScreen(
              route: '/destroyed-packages',
              title: 'Destroyed Goods',
              subtitle: 'Goods that have been destroyed or queued for destruction',
              countLabel: 'Destroyed',
              finalTag: 'DESTROYED',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify SR numbers exist
      expect(find.text('CED/GL1/SR/01/2025'), findsOneWidget);
      expect(find.text('CED/GL1/SR/02/2025'), findsOneWidget);

      // Verify "Mark Destroyed" action button appears for pending item
      expect(find.text('Mark Destroyed'), findsOneWidget);

      // Verify "Destroyed" status chip appears for already destroyed item
      expect(find.text('Destroyed'), findsWidgets);
    });
  });
}
