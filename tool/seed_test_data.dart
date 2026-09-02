// Clears the transactional data and seeds a fresh, representative set.
//
// KEPT (the ICT Directorate's reference data, and the setup that hangs off it):
//   directorates, yards, yard_directorates, profiles, auth.users, storage_rates
//
// REBUILT: warehouses, zones, package categories, hold reasons, customs rules
//   -- so the categories match the goods actually seeded and every zone a
//   category points at exists.
//
// CLEARED: every goods/SR/tender/disposal row.
//
// Post-status activities are code constants (lib/core/post_status_activities),
// not a table, so there is nothing to keep or seed for them.
//
// Run:  dart run tool/seed_test_data.dart
import 'dart:math';

import 'package:postgres/postgres.dart';

/// Seeded so a re-run produces the same data -- a moving dataset makes any
/// screenshot or bug report impossible to compare against.
final _rng = Random(20260903);

const _yard = 'GL1';
const _directoratePrefix = 'CED';

/// Goods that spoil, and goods that do not. Kept apart because the two take
/// different paths through the whole system.
const _perishableGoods = <(String, String, String, int, int)>[
  ('Fresh Prawns (frozen)', 'Farmed prawns, 1kg vacuum packs', '0306.17.00', 8500, 40),
  ('Chilled Beef Cuts', 'Vacuum-packed beef, chilled', '0201.30.00', 12000, 25),
  ('Imported Apples', 'Red apples, 18kg cartons', '0808.10.00', 4200, 60),
  ('Butter Blocks 25kg', 'Unsalted dairy butter', '0405.10.00', 15500, 20),
  ('Fresh Cut Flowers', 'Mixed stems, cold chain', '0603.11.00', 3200, 150),
  ('Liquid Milk Cartons', 'UHT milk, 1L', '0401.20.00', 480, 500),
  ('Frozen Fish Fillets', 'Skinless fillets, 5kg', '0304.62.00', 6800, 35),
  ('Yoghurt Tubs', 'Set yoghurt, 100ml', '0403.20.00', 190, 800),
  ('Vaccine Vials (cold)', 'Temperature-controlled vials', '3002.20.00', 45000, 12),
  ('Live Ornamental Fish', 'Aquarium stock in bags', '0301.11.00', 2100, 90),
];

const _normalGoods = <(String, String, String, int, int)>[
  ('Steel Cooking Pots', 'Stainless steel, 5L', '7323.93.00', 3200, 110),
  ('Cutlery Sets', '24-piece stainless sets', '8215.10.00', 2400, 95),
  ('Ceramic Floor Tiles', '60x60cm, assorted', '6907.21.00', 1850, 240),
  ('PVC Electrical Conduit', '20mm rigid conduit', '3917.23.00', 420, 420),
  ('Rubber Conveyor Belt', 'Industrial belting, 800mm', '4010.12.00', 22000, 55),
  ('Printed Circuit Boards', 'Bare 4-layer PCBs', '8534.00.00', 5600, 160),
  ('Copper Wire Coils', 'Bare copper, 2.5mm', '7408.11.00', 18500, 130),
  ('Aluminium Foil Rolls', 'Household grade, 30cm', '7607.11.00', 950, 110),
  ('Wrist Watches', 'Quartz analogue', '9102.11.00', 7800, 58),
  ('Engine Cylinder Block', 'Used motorcycle blocks, 125cc', '8409.91.00', 7800, 55),
  ('Clutch Plate Set', 'Friction plates, 5-plate', '8708.93.00', 2400, 75),
  ('Laptop Chargers', '65W universal adapters', '8504.40.00', 2900, 200),
  ('Cotton Bed Sheets', 'Double, 200TC', '6302.21.00', 3400, 145),
  ('Leather Handbags', 'Assorted ladies bags', '4202.21.00', 9500, 70),
  ('Ceramic Sanitaryware', 'Wash basins, white', '6910.10.00', 5180, 85),
  ('Paint Thinner Cans', 'Solvent, 20L', '3814.00.00', 4800, 90),
  ('Galvanised Steel Sheets', '1.2mm, 8ft', '7210.49.00', 6200, 85),
  ('Industrial Bearings', 'Ball bearings, assorted', '8482.10.00', 1450, 200),
  ('Latex Gloves', 'Examination, box of 100', '4015.12.00', 780, 400),
  ('Power Tools', 'Corded drills, 700W', '8467.21.00', 8900, 72),
];

/// The dispositions a normal item can carry, and how often each appears.
/// Weighted so the busier pages have enough rows to page through.
const _dispositions = <String>[
  'Detain', 'Detain', 'Detain', 'Detain',
  'Forfeit', 'Forfeit', 'Forfeit',
  'Abandoned', 'Abandoned',
  'Other',
];

const _detainReasons = [
  'Pending Inquiry',
  'Pending Licence',
  'Valuation Dispute',
  'Document Verification',
];

const _consignees = [
  ('Nova Impex Lanka', 'Lanka Clearing Services'),
  ('Summit Auto Lanka', 'Trans Freight (Pvt) Ltd'),
  ('Orient Traders (Pvt) Ltd', 'Orient Clearing'),
  ('Palm Grove Enterprises', 'Palm Logistics'),
  ('Kandy Electricals', 'Hill Country Clearing'),
  ('Colombo Tile Centre', 'Metro Freight'),
  ('Lanka Paper Mills', 'Paper Trail Logistics'),
  ('Tropical Foods Lanka', 'Cold Chain Movers'),
  ('Metro Distributors', 'Metro Freight'),
  ('Eastern Traders Lanka', 'Eastern Clearing Co'),
  ('Ceylon Marine Supplies', 'Harbour Agents'),
  ('Rathnayake Motors', 'Auto Freight Lanka'),
];

Future<void> main() async {
  final conn = await Connection.open(
    Endpoint(
        host: 'localhost',
        port: 5432,
        database: 'Customs_SR_DB',
        username: 'postgres',
        password: 'postgres'),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  print('── Clearing transactional data ' + '─' * 40);
  // Order matters: children before parents. Everything here is goods data;
  // nothing ICT maintains is touched.
  for (final t in const [
    'tender_bids',
    'tender_revaluations',
    'tender_committees',
    'unsold_proposals',
    'tender_sale_items',
    'tender_sales',
    'tender_disposals',
    'tenders',
    'destruction_items',
    'destructions',
    'disposal_request_items',
    'disposal_requests',
    'disposal_taxes',
    'financial_expenses',
    'forfeited_packages',
    'warehouse_entries',
    'package_items',
    'packages',
    'audit_logs',
    'sr_number_migration_log',
  ]) {
    final r = await conn.execute('delete from public."$t"');
    print('  cleared ${t.padRight(28)} ${r.affectedRows}');
  }

  // Rebuilt so categories, zones and the goods actually agree.
  for (final t in const [
    'package_categories',
    'warehouse_zones',
    'warehouses',
    'hold_reasons',
    'customs_rules',
  ]) {
    await conn.execute('delete from public."$t"');
    print('  cleared ${t.padRight(28)} (rebuilt below)');
  }

  print('\n── Warehouses & zones ' + '─' * 47);
  // An OPEN AREA is a warehouse like any other -- it holds goods, accrues the
  // same storage charge and takes the same entries. It is only "open" in the
  // sense that what it holds does not need a roof.
  final warehouses = <String, String>{};
  for (final (code, name, desc, location, capacity) in const [
    ('W01', 'Warehouse 01', 'Covered general cargo store', 'Main yard, north', 5000),
    ('W02', 'Warehouse 02', 'Covered store, secured section', 'Main yard, east', 5000),
    ('W03', 'Warehouse 03', 'Covered store, bulk goods', 'Main yard, south', 5000),
    ('OA1', 'Open Area 01', 'Uncovered hardstanding for weather-tolerant cargo',
        'Rear compound', 8000),
  ]) {
    final r = await conn.execute(
      r'insert into public.warehouses (name, code, description, location, capacity) '
      r'values ($1, $2, $3, $4, $5) returning id',
      parameters: [name, code, desc, location, capacity],
    );
    warehouses[code] = r.first.first as String;
    print('  $code  $name');
  }

  // Every zone a category points at has to exist, or admitting goods fails.
  final zones = <String, List<String>>{
    'W01': ['A', 'B'],
    'W02': ['A', 'B', 'C'],
    'W03': ['A', 'B'],
    'OA1': ['Y1', 'Y2'],
  };
  for (final e in zones.entries) {
    for (final z in e.value) {
      await conn.execute(
        r'insert into public.warehouse_zones (warehouse_id, name, code, capacity, description) '
        r'values ($1, $2, $3, $4, $5)',
        parameters: [
          warehouses[e.key],
          z,
          '${e.key}-$z',
          e.key == 'OA1' ? 4000 : 2500,
          e.key == 'OA1' ? 'Open hardstanding bay' : 'Covered bay',
        ],
      );
    }
    print('  ${e.key} zones: ${e.value.join(', ')}');
  }

  print('\n── Categories, hold reasons, rules ' + '─' * 35);
  // Each category routes to a real warehouse+zone, chosen to suit the goods:
  // heavy and weather-tolerant cargo to the open area, the rest under cover.
  const categories = <(String, String, String, String)>[
    ('Foodstuffs & Perishables', 'W02', 'C', 'Chilled and short-life goods'),
    ('Household & Kitchenware', 'W01', 'A', 'Pots, cutlery, homeware'),
    ('Building Materials', 'OA1', 'Y1', 'Tiles, sheets, conduit — weather tolerant'),
    ('Vehicle Parts and Tyres', 'OA1', 'Y2', 'Bulky automotive parts'),
    ('Electrical & Electronics', 'W02', 'A', 'Boards, chargers, cabling'),
    ('Textiles and Apparel', 'W01', 'B', 'Fabric, bedding, garments'),
    ('Metals & Hardware', 'W03', 'A', 'Wire, bearings, fittings'),
    ('Chemicals & Solvents', 'W03', 'B', 'Paints, thinners, solvents'),
    ('Medical Supplies', 'W02', 'B', 'Gloves, vials, consumables'),
    ('General Cargo', 'W01', 'A', 'Anything not otherwise categorised'),
  ];
  for (final (name, wh, zone, desc) in categories) {
    await conn.execute(
      r'insert into public.package_categories (name, target_warehouse_id, target_zone, description) '
      r'values ($1, $2, $3, $4)',
      parameters: [name, warehouses[wh], zone, desc],
    );
  }
  print('  ${categories.length} categories, each routed to a real zone');

  for (final (name, desc) in const [
    ('Pending Inquiry', 'Held while an inquiry is open'),
    ('Pending Licence', 'Awaiting an import licence or permit'),
    ('Valuation Dispute', 'Declared value under review'),
    ('Document Verification', 'Supporting documents being checked'),
    ('Perishable — Immediate Disposal', 'Goods that cannot be stored'),
  ]) {
    await conn.execute(
      r'insert into public.hold_reasons (name, reason_text, description, is_active) '
      r'values ($1, $1, $2, true)',
      parameters: [name, desc],
    );
  }
  print('  5 hold reasons');

  for (final (n, t, v, d) in const [
    ('Maximum Declared Value', 'max_value', 75000.0,
        'Packages over LKR 75,000 must be held'),
    ('Maximum Weight', 'max_weight', 1000.0, 'Packages over 1000kg must be held'),
    ('Maximum Item Count', 'max_items', 500.0, 'Packages over 500 items must be held'),
  ]) {
    await conn.execute(
      r'insert into public.customs_rules (rule_name, rule_type, threshold_value, description, is_active) '
      r'values ($1, $2, $3, $4, true)',
      parameters: [n, t, v, d],
    );
  }
  print('  3 customs rules');

  print('\n── Packages ' + '─' * 57);
  await _seedPackages(conn, warehouses);

  print('\n── Final counts ' + '─' * 53);
  for (final t in const [
    'packages',
    'package_items',
    'warehouse_entries',
    'forfeited_packages',
    'warehouses',
    'warehouse_zones',
    'package_categories',
    'profiles',
    'directorates',
    'yards',
  ]) {
    final c = await conn.execute('select count(*) from public."$t"');
    print('  ${t.padRight(22)} ${c.first.first}');
  }

  await conn.close();
  print('\nDone.');
}

/// The dates the data spans: 2024, 2025, and 2026 up to the end of March.
///
/// Nothing is dated after 31 March 2026 -- the request was for everything to
/// predate April, so a report run "this year" has a clear before/after.
final _periods = <(int, DateTime, DateTime)>[
  (2024, DateTime(2024, 1, 8), DateTime(2024, 12, 20)),
  (2025, DateTime(2025, 1, 6), DateTime(2025, 12, 19)),
  (2026, DateTime(2026, 1, 5), DateTime(2026, 3, 31)),
];

Future<void> _seedPackages(
    Connection conn, Map<String, String> warehouses) async {
  // Serials run per register per year, exactly as getNextSrNumber mints them.
  final serials = <String, int>{};
  var made = 0;
  var perishableCount = 0;
  final statusTally = <String, int>{};

  for (final (year, from, to) in _periods) {
    // Weighted to the current year, the way a real register fills up.
    final count = year == 2026 ? 60 : (year == 2025 ? 50 : 40);
    final span = to.difference(from).inDays;

    for (var i = 0; i < count; i++) {
      final entry = from.add(Duration(
          days: _rng.nextInt(span),
          hours: 8 + _rng.nextInt(9),
          minutes: _rng.nextInt(60)));

      // One in six is an OA number, so both registers have real history and
      // their serials can be seen running independently.
      final register = _rng.nextInt(6) == 0 ? 'OA' : 'SR';
      final key = '$register-$year';
      final serial = (serials[key] ?? 0) + 1;
      serials[key] = serial;
      final srNumber = '$_directoratePrefix/$_yard/$register/'
          '${serial.toString().padLeft(2, '0')}/$year';

      final (consignee, declarant) =
          _consignees[_rng.nextInt(_consignees.length)];

      // One in five packages is perishable. They never reach a warehouse, so
      // they are kept whole rather than mixed with normal goods -- a package
      // is either a perishable consignment or a normal one.
      final isPerishable = _rng.nextInt(5) == 0;

      final pkgRes = await conn.execute(
        r'insert into public.packages '
        r'(sr_number, case_number, consignee_name, consignee_nic, consignee_address, '
        r' consignee_phone, declarant_name, cusdec_no, cusdec_date, entry_date, '
        r' origin_country, declared_value, weight_kg, container_number, description, '
        r' status, yard, destroying_deposit, created_at, updated_at) '
        r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$19) '
        r'returning id',
        parameters: [
          srNumber,
          '$_yard/CASE/$year/${(1000 + made).toString()}',
          consignee,
          '${197000000000 + _rng.nextInt(29000000)}V',
          '${10 + _rng.nextInt(400)}, Main Street, Colombo ${1 + _rng.nextInt(15)}',
          '07${1 + _rng.nextInt(8)}${(1000000 + _rng.nextInt(8999999))}',
          declarant,
          'CUSDEC/$year/${1500 + made}',
          _iso(entry.subtract(const Duration(days: 1))),
          entry,
          const ['India', 'China', 'Singapore', 'Malaysia', 'UAE',
              'Thailand'][_rng.nextInt(6)],
          (50000 + _rng.nextInt(900000)).toDouble(),
          (100 + _rng.nextInt(2400)).toDouble(),
          'CONT${4000000 + _rng.nextInt(900000)}',
          isPerishable
              ? 'Perishable consignment — immediate disposal'
              : 'General consignment held under SR',
          isPerishable ? 'detained' : 'pending',
          _yard,
          // Only goods that may end up destroyed lodge a destroying deposit.
          isPerishable || _rng.nextInt(3) == 0
              ? (5000 + _rng.nextInt(70000)).toDouble()
              : null,
          entry,
        ],
      );
      final pkgId = pkgRes.first.first as String;

      final itemCount = isPerishable ? 1 + _rng.nextInt(2) : 1 + _rng.nextInt(3);
      for (var k = 0; k < itemCount; k++) {
        final pool = isPerishable ? _perishableGoods : _normalGoods;
        final (name, desc, hs, value, qty) = pool[_rng.nextInt(pool.length)];

        final status = isPerishable
            ? 'Perishable'
            : _dispositions[_rng.nextInt(_dispositions.length)];
        statusTally[status] = (statusTally[status] ?? 0) + 1;
        if (isPerishable) perishableCount++;

        final itemRes = await conn.execute(
          r'insert into public.package_items '
          r'(package_id, item_name, goods_description, quantity, unit_of_measure, '
          r' unit_value, hs_code, category, status, reasons, nature, yard, created_at) '
          r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) returning id',
          parameters: [
            pkgId,
            name,
            desc,
            qty + _rng.nextInt(30) - 15,
            'Pieces',
            value.toDouble(),
            hs,
            _categoryFor(name, isPerishable),
            status,
            status == 'Detain'
                ? _detainReasons[_rng.nextInt(_detainReasons.length)]
                : (isPerishable
                    ? 'Perishable — immediate disposal'
                    : 'Supposed to be Sold / Auction'),
            isPerishable ? 'perishable' : 'normal',
            _yard,
            entry,
          ],
        );
        final itemId = itemRes.first.first as String;

        // ⚠️ Perishable goods never reach a warehouse -- that is the whole
        // point of the nature. Only normal goods get an entry.
        if (!isPerishable) {
          final wh = _warehouseFor(name, warehouses);
          await conn.execute(
            r'insert into public.warehouse_entries '
            r'(package_id, package_item_id, warehouse_id, hold_reason, item_count, '
            r' zone, yard, daily_rate, admitted_at, created_at, updated_at) '
            r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9,$9)',
            parameters: [
              pkgId,
              itemId,
              wh.$1,
              status == 'Detain'
                  ? _detainReasons[_rng.nextInt(_detainReasons.length)]
                  : 'Pending Inquiry',
              qty,
              wh.$2,
              _yard,
              50.0,
              entry.add(const Duration(hours: 3)),
            ],
          );
        }

        // Forfeited and abandoned goods carry a forfeited_packages row, which
        // is what the appeal window and the disposal request both read.
        if (status == 'Forfeit' || status == 'Abandoned' || status == 'Other') {
          final forfeitedAt = entry.add(Duration(days: 5 + _rng.nextInt(25)));
          await conn.execute(
            r'insert into public.forfeited_packages '
            r'(package_id, item_id, sr_number, consignee_name, forfeited_at, '
            r' appeal_deadline, reason, source, yard, entry_qty, created_at, updated_at) '
            r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$5,$5)',
            parameters: [
              pkgId,
              itemId,
              srNumber,
              consignee,
              forfeitedAt,
              forfeitedAt.add(const Duration(days: 30)),
              status == 'Forfeit'
                  ? 'Forfeited under Customs Ordinance'
                  : (status == 'Abandoned'
                      ? 'Abandoned by the consignee'
                      : 'Routed via Other disposition'),
              status.toLowerCase(),
              _yard,
              qty,
              ],
          );
        }
      }
      made++;
    }
  }

  print('  $made packages');
  print('  perishable items: $perishableCount');
  final tally = statusTally.entries.map((e) => '${e.key}=${e.value}').join(', ');
  print('  item statuses: $tally');
  print('  registers: ' +
      serials.entries.map((e) => '${e.key}:${e.value}').join(', '));
}

/// Routes goods to the category that suits them, so the category, the
/// warehouse and the zone all agree with what the item actually is.
String _categoryFor(String itemName, bool perishable) {
  if (perishable) {
    return itemName.contains('Vaccine')
        ? 'Medical Supplies'
        : 'Foodstuffs & Perishables';
  }
  const map = {
    'Steel Cooking Pots': 'Household & Kitchenware',
    'Cutlery Sets': 'Household & Kitchenware',
    'Ceramic Sanitaryware': 'Household & Kitchenware',
    'Ceramic Floor Tiles': 'Building Materials',
    'PVC Electrical Conduit': 'Building Materials',
    'Galvanised Steel Sheets': 'Building Materials',
    'Rubber Conveyor Belt': 'Vehicle Parts and Tyres',
    'Engine Cylinder Block': 'Vehicle Parts and Tyres',
    'Clutch Plate Set': 'Vehicle Parts and Tyres',
    'Printed Circuit Boards': 'Electrical & Electronics',
    'Laptop Chargers': 'Electrical & Electronics',
    'Copper Wire Coils': 'Electrical & Electronics',
    'Cotton Bed Sheets': 'Textiles and Apparel',
    'Leather Handbags': 'Textiles and Apparel',
    'Aluminium Foil Rolls': 'Metals & Hardware',
    'Industrial Bearings': 'Metals & Hardware',
    'Power Tools': 'Metals & Hardware',
    'Wrist Watches': 'Metals & Hardware',
    'Paint Thinner Cans': 'Chemicals & Solvents',
    'Latex Gloves': 'Medical Supplies',
  };
  return map[itemName] ?? 'General Cargo';
}

/// The warehouse and zone a category routes to. Bulky, weather-tolerant cargo
/// goes to the open area; everything else under cover.
(String, String) _warehouseFor(String itemName, Map<String, String> whs) {
  final cat = _categoryFor(itemName, false);
  const routing = {
    'Household & Kitchenware': ('W01', 'A'),
    'Textiles and Apparel': ('W01', 'B'),
    'General Cargo': ('W01', 'A'),
    'Electrical & Electronics': ('W02', 'A'),
    'Medical Supplies': ('W02', 'B'),
    'Foodstuffs & Perishables': ('W02', 'C'),
    'Metals & Hardware': ('W03', 'A'),
    'Chemicals & Solvents': ('W03', 'B'),
    'Building Materials': ('OA1', 'Y1'),
    'Vehicle Parts and Tyres': ('OA1', 'Y2'),
  };
  final (code, zone) = routing[cat] ?? ('W01', 'A');
  return (whs[code]!, zone);
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
