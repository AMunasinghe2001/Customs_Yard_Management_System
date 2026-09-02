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

/// How much each zone holds.
///
/// ⚠️ Used BOTH when the zone row is written and when the seeder books space
/// against it. If the two ever disagreed the seeder would fill zones to a
/// number the Zone Capacity page does not share -- so there is one definition.
///
/// Sized to fit the whole seed with a little headroom: a couple of zones
/// finishing at or near 100% is wanted, items left unplaced is not.
int _zoneCapacity(String warehouseCode) =>
    warehouseCode == 'OA1' ? 5200 : 3400;
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

/// The goods an OA number carries: vehicle parts, metals and building
/// material -- bulky, weather-tolerant cargo that belongs on open hardstanding
/// rather than under a roof. That is what the Open Area is for, and it is why
/// the OA register exists as its own book.
const _openAreaGoods = <(String, String, String, int, int)>[
  ('Engine Cylinder Block', 'Used motorcycle blocks, 125cc', '8409.91.00', 7800, 55),
  ('Clutch Plate Set', 'Friction plates, 5-plate', '8708.93.00', 2400, 75),
  ('Rubber Conveyor Belt', 'Industrial belting, 800mm', '4010.12.00', 22000, 55),
  ('Vehicle Leaf Springs', 'Heavy vehicle suspension', '7320.10.00', 5400, 60),
  ('Truck Tyres', 'Radial, 11R22.5', '4011.20.00', 34000, 40),
  ('Scrap Steel Bundles', 'Mixed ferrous scrap', '7204.49.00', 1200, 300),
  ('Galvanised Steel Sheets', '1.2mm, 8ft', '7210.49.00', 6200, 85),
  ('Cast Iron Pipes', 'Ductile iron, 150mm', '7303.00.00', 8800, 70),
  ('Ceramic Floor Tiles', '60x60cm, assorted', '6907.21.00', 1850, 240),
  ('PVC Electrical Conduit', '20mm rigid conduit', '3917.23.00', 420, 420),
  ('Steel Reinforcement Bars', 'Deformed bar, 12mm', '7214.20.00', 2100, 350),
  ('Used Engine Blocks', 'Assorted vehicle engines', '8409.99.00', 15000, 30),
];

/// Everything an SR number carries: goods that go under cover.
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
  'Abandoned', 'Abandoned', 'Abandoned', 'Abandoned',
  'Other', 'Other',
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
  //
  // Enough zones that the goods fit: the seed fills a zone only up to its
  // capacity and moves to the next, the way the SR form lets an officer pick
  // another zone when the first is full. Too few zones and there would be
  // nowhere left to put the tail of the data.
  final zones = <String, List<String>>{
    'W01': ['A', 'B', 'C', 'D'],
    'W02': ['A', 'B', 'C', 'D'],
    'W03': ['A', 'B', 'C', 'D'],
    // Six bays: OA goods never spill into a covered warehouse, so the open
    // area has to hold the whole OA register on its own.
    'OA1': ['Y1', 'Y2', 'Y3', 'Y4', 'Y5', 'Y6'],
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
          _zoneCapacity(e.key),
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
  // Room left in each zone, spent as goods are placed. Without this the seed
  // routed purely by category and buried every zone at 150-240% -- capacity
  // meant nothing, and the Zone Capacity page was a wall of red.
  final space = <String, int>{
    for (final e in zones.entries)
      for (final z in e.value) '${e.key}|$z': _zoneCapacity(e.key),
  };
  await _seedPackages(conn, warehouses, space);
  // ⚠️ Order matters. Releases run FIRST: a released item's status becomes
  // 'returned', which takes it out of the detained pool -- so the appeal pass
  // below cannot lodge an appeal against goods that have already gone home.
  await _seedReleases(conn);
  await _seedOldEntries(conn);
  // The detain rows must exist BEFORE outcomes are seeded, or the ruling pass
  // has nothing to rule on for detained goods.
  await _seedDetainAppeals(conn);
  await _seedAppealOutcomes(conn);
  // ⚠️ LAST: it reads whether an appeal was decided, so it has to run after
  // the rulings exist -- otherwise every completed row looks like one the
  // yard finished directly.
  await _seedFinalOtherOutcomes(conn);
  // ⚠️ LAST of all: it selects only goods that are still disposable, so every
  // pass that RETIRES goods (released, finished as Other) must already have
  // run -- otherwise it would tender goods that have left the yard.
  await _seedTenderPipeline(conn);
  // ⚠️ AFTER the tender pipeline, and it excludes anything already tendered or
  // already on a disposal request. The same goods cannot be both sold and
  // destroyed, and whichever pass runs second has to say so.
  await _seedDestructions(conn);

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

/// A recent cohort, entered inside the last few weeks.
///
/// The appeal window runs 30 days from the ENTRY DATE, so goods entered before
/// April have all long since become actionable -- every Forfeit, Abandoned and
/// Other row above is past its window and its status is enabled. Without a
/// recent batch there is nothing to test the *blocked* half against: no row
/// showing days remaining, and no disabled status to click at.
///
/// Dated relative to now rather than fixed, so the cohort stays inside the
/// window however long after the seed it is looked at.
final _appealWindowFrom = DateTime.now().subtract(const Duration(days: 24));
final _appealWindowTo = DateTime.now().subtract(const Duration(days: 2));

Future<void> _seedPackages(Connection conn, Map<String, String> warehouses,
    Map<String, int> space) async {
  // Serials run per register per year, exactly as getNextSrNumber mints them.
  final serials = <String, int>{};
  var made = 0;
  var perishableCount = 0;
  var unplaced = 0;
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

      // ⚠️ One SR/OA number covers ONE package, and a package can hold several
      // distinct goods. So the same number appearing on several rows of a
      // status table is correct, not a duplicate -- each row is a different
      // item under the one number. Seeded up to 4 so that shows up plainly.
      final itemCount = isPerishable ? 1 + _rng.nextInt(2) : 1 + _rng.nextInt(4);
      for (var k = 0; k < itemCount; k++) {
        // The register decides what the goods are: an OA number is opened for
        // the bulky, weather-tolerant cargo the Open Area holds, so its items
        // come from that list and land there.
        final pool = isPerishable
            ? _perishableGoods
            : (register == 'OA' ? _openAreaGoods : _normalGoods);
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
          final qtyHeld = qty;
          final wh = _placeIn(name, qtyHeld, warehouses, space,
              openArea: register == 'OA');
          if (wh == null) {
            // Every zone full. Rather than overfill one -- which is what made
            // the capacity page meaningless -- the goods are left unplaced and
            // reported, so the shortfall is visible instead of hidden.
            unplaced++;
            continue;
          }
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

  // ── The still-appealable cohort ──────────────────────────────────────────
  // The 30-day window runs from the ENTRY DATE and applies to every status
  // alike -- a Detain is frozen for its first 30 days exactly as a Forfeit is.
  // Detain therefore belongs here too; only a perishable is exempt, since it
  // never waits a window out.
  const appealable = ['Forfeit', 'Abandoned', 'Other', 'Detain'];
  final recentSpan = _appealWindowTo.difference(_appealWindowFrom).inDays;
  var recent = 0;
  var recentItems = 0;
  for (var i = 0; i < 26; i++) {
    final entry = _appealWindowFrom.add(Duration(
        days: _rng.nextInt(recentSpan + 1),
        hours: 8 + _rng.nextInt(9),
        minutes: _rng.nextInt(60)));
    final year = entry.year;
    final register = _rng.nextInt(4) == 0 ? 'OA' : 'SR';
    final key = '$register-$year';
    final serial = (serials[key] ?? 0) + 1;
    serials[key] = serial;
    final srNumber = '$_directoratePrefix/$_yard/$register/'
        '${serial.toString().padLeft(2, '0')}/$year';
    final (consignee, declarant) =
        _consignees[_rng.nextInt(_consignees.length)];

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
        '$_yard/CASE/$year/${(2000 + i).toString()}',
        consignee,
        '${197000000000 + _rng.nextInt(29000000)}V',
        '${10 + _rng.nextInt(400)}, Main Street, Colombo ${1 + _rng.nextInt(15)}',
        '07${1 + _rng.nextInt(8)}${(1000000 + _rng.nextInt(8999999))}',
        declarant,
        'CUSDEC/$year/${3000 + i}',
        _iso(entry.subtract(const Duration(days: 1))),
        entry,
        const ['India', 'China', 'Singapore', 'Malaysia', 'UAE',
            'Thailand'][_rng.nextInt(6)],
        (50000 + _rng.nextInt(900000)).toDouble(),
        (100 + _rng.nextInt(2400)).toDouble(),
        'CONT${4000000 + _rng.nextInt(900000)}',
        'Recent consignment — appeal window still open',
        'pending',
        _yard,
        _rng.nextInt(3) == 0 ? (5000 + _rng.nextInt(70000)).toDouble() : null,
        entry,
      ],
    );
    final pkgId = pkgRes.first.first as String;

    final pool = register == 'OA' ? _openAreaGoods : _normalGoods;
    // Several goods under the one recent number, so the multi-item case is
    // visible inside the appeal window too and not only in the history.
    final itemCount = 1 + _rng.nextInt(3);
    for (var k = 0; k < itemCount; k++) {
      final (name, desc, hs, value, qty) = pool[_rng.nextInt(pool.length)];
      final status = appealable[_rng.nextInt(appealable.length)];
      statusTally[status] = (statusTally[status] ?? 0) + 1;

      final itemRes = await conn.execute(
        r'insert into public.package_items '
        r'(package_id, item_name, goods_description, quantity, unit_of_measure, '
        r' unit_value, hs_code, category, status, reasons, nature, yard, created_at) '
        r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) returning id',
        parameters: [
          pkgId, name, desc, qty + _rng.nextInt(30) - 15, 'Pieces',
          value.toDouble(), hs, _categoryFor(name, false), status,
          status == 'Detain'
              ? _detainReasons[_rng.nextInt(_detainReasons.length)]
              : 'Supposed to be Sold / Auction',
          'normal', _yard, entry,
        ],
      );
      final itemId = itemRes.first.first as String;

      final wh =
          _placeIn(name, qty, warehouses, space, openArea: register == 'OA');
      if (wh != null) {
        await conn.execute(
          r'insert into public.warehouse_entries '
          r'(package_id, package_item_id, warehouse_id, hold_reason, item_count, '
          r' zone, yard, daily_rate, admitted_at, created_at, updated_at) '
          r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9,$9)',
          parameters: [
            pkgId, itemId, wh.$1,
            status == 'Detain'
                ? _detainReasons[_rng.nextInt(_detainReasons.length)]
                : 'Pending Inquiry',
            qty, wh.$2, _yard, 50.0, entry.add(const Duration(hours: 3)),
          ],
        );
      } else {
        unplaced++;
      }

      // A Detain is held on its own footing -- it has no forfeited_packages
      // row, and its window is read straight off the entry date.
      if (status != 'Detain') {
        // Forfeited AT the entry date, so the 30-day window from that date is
        // genuinely still running -- which is what leaves the status disabled.
        await conn.execute(
          r'insert into public.forfeited_packages '
          r'(package_id, item_id, sr_number, consignee_name, forfeited_at, '
          r' appeal_deadline, reason, source, yard, entry_qty, created_at, updated_at) '
          r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$5,$5)',
          parameters: [
            pkgId, itemId, srNumber, consignee, entry,
            entry.add(const Duration(days: 30)),
            status == 'Forfeit'
                ? 'Forfeited under Customs Ordinance'
                : (status == 'Abandoned'
                    ? 'Abandoned by the consignee'
                    : 'Routed via Other disposition'),
            status.toLowerCase(), _yard, qty,
          ],
        );
      }
      recentItems++;
    }
    made++;
    recent++;
  }

  print('  $made packages');
  print('  $recent of them entered in the last 24 days ($recentItems items) '
      '-- appeal window OPEN, status disabled');
  print('  perishable items: $perishableCount (no warehouse, by design)');
  if (unplaced > 0) {
    print('  ⚠ $unplaced items could not be placed -- every zone was full');
  }
  final tally = statusTally.entries.map((e) => '${e.key}=${e.value}').join(', ');
  print('  item statuses: $tally');
  print('  registers: ' +
      serials.entries.map((e) => '${e.key}:${e.value}').join(', '));
}

/// Rules on a share of the appeals, so the Appeal Directorate has a history.
///
/// Without this every forfeited row sits in one of only two states -- counting
/// down, or expired -- and the two states that need a HUMAN decision never
/// appear at all: "Decided Goods" is permanently empty, and no row ever shows
/// "On Appeal Hold". Both are reachable only by someone ruling, so the seed
/// has to rule.
///
/// ⚠️ Decisions are stored PER ITEM in `item_appeal_decisions`, keyed by item
/// id -- never in the package-level `appeal_decision` column. On a multi-item
/// package the package-level column is deliberately ignored (deciding one item
/// must not mark its siblings decided), so writing there would produce rows the
/// app refuses to treat as decided.
/// Sends goods for destruction, and destroys some of them.
///
/// Destroyed Goods has TWO states and the page filters on them, so seeding
/// only one leaves half the page empty:
///
///   * PENDING  -- item status 'supposed to be destroyed'. The goods are
///     listed for destruction but it has not happened yet.
///   * DESTROYED -- item status 'destroyed' AND the destruction_items row
///     marked destroyed, which is what carries the date and the receipt.
///
/// Both routes in are seeded, because a yard reaches destruction two ways:
///   * through the VALUATION directorate (a disposal request costed and
///     forwarded, disposition 'destruction'), and
///   * DIRECTLY, when the yard records Destroy as a final disposition with no
///     request at all -- perishables especially, which cannot wait.
///
/// ⚠️ The "Destruction Expenses" column does NOT come from the destruction
/// row. It is read from `financial_expenses` (kind 'destruction_expense')
/// against the SR NUMBER, so a destroyed row with no expense row shows a
/// blank spend however complete the destruction looks.
Future<void> _seedDestructions(Connection conn) async {
  final rows = await conn.execute(
    'select fp.id, fp.item_id, fp.sr_number, pi.quantity, pi.unit_value, '
    '       pi.nature '
    'from public.forfeited_packages fp '
    'join public.package_items pi on pi.id = fp.item_id '
    'where fp.appeal_deadline < now() '
    '  and coalesce(fp.appeal_hold, false) = false '
    "  and pi.status not in ('returned', 'other', 'sold', 'destroyed', "
    "                        'supposed to be destroyed') "
    '  and not exists (select 1 from public.tender_sale_items t '
    '                   where t.forfeited_package_id = fp.id) '
    '  and not exists (select 1 from public.disposal_request_items d '
    '                   where d.forfeited_package_id = fp.id) '
    'order by fp.forfeited_at asc',
  );

  var viaValuation = 0;
  var direct = 0;
  var destroyed = 0;
  var pending = 0;
  var serial = 0;

  String? batchReqId;
  DateTime? batchAt;
  var batchLeft = 0;

  for (final r in rows) {
    if (_rng.nextInt(100) >= 60) continue;

    final fpId = r[0] as String;
    final itemId = r[1] as String?;
    final srNumber = r[2] as String;
    final qty = (r[3] as int?) ?? 1;
    final unitValue = double.tryParse('${r[4]}') ?? 5000;

    final sentAt =
        DateTime.now().subtract(Duration(days: 25 + _rng.nextInt(420)));

    // Two in three go through Valuation; the rest the yard destroys directly.
    final throughValuation = _rng.nextInt(3) != 0;
    if (throughValuation) {
      if (batchLeft == 0 || batchReqId == null) {
        batchAt = sentAt;
        batchReqId = await _newDisposalRequest(conn, batchAt!, 'forwarded');
        batchLeft = 2 + _rng.nextInt(4);
      }
      batchLeft--;
      await conn.execute(
        r'insert into public.disposal_request_items '
        r'(request_id, forfeited_package_id, disposition, valuation_cost, forwarded) '
        r"values ($1,$2,'destruction',$3,true)",
        parameters: [
          batchReqId,
          fpId,
          (unitValue * qty * (0.4 + _rng.nextDouble() * 0.3)).roundToDouble(),
        ],
      );
      viaValuation++;
    } else {
      direct++;
    }

    // Has the destruction actually been carried out yet? The page has its own
    // Pending filter, so the waiting half needs a real population too.
    final isDone = _rng.nextInt(100) < 58;
    final destroyedAt = isDone
        ? sentAt.add(Duration(days: 5 + _rng.nextInt(30)))
        : null;

    serial++;
    final destructionId = await _newDestruction(conn, sentAt, serial);

    await conn.execute(
      r'insert into public.destruction_items '
      r'(destruction_id, forfeited_package_id, package_item_id, yard, '
      r' destroyed, destroyed_at, destroyed_price, receipt_number, notes, '
      r' delivered, delivered_at, created_at) '
      r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)',
      parameters: [
        destructionId, fpId, itemId, _yard,
        isDone,
        destroyedAt,
        // NOT NULL, default 0 -- a destruction that has not happened yet has
        // cost nothing, so 0 is the honest value, not null.
        isDone
            ? (unitValue * qty * (0.05 + _rng.nextDouble() * 0.12))
                .roundToDouble()
            : 0.0,
        isDone ? 'DR/$_yard/${sentAt.year}/${3000 + serial}' : null,
        _destructionNotes[_rng.nextInt(_destructionNotes.length)],
        isDone && _rng.nextBool(),
        isDone && _rng.nextBool()
            ? destroyedAt!.add(const Duration(days: 2))
            : null,
        sentAt,
      ],
    );

    if (itemId != null) {
      await conn.execute(
        r'update public.package_items set status = $2 where id = $1',
        parameters: [
          itemId,
          isDone ? 'destroyed' : 'supposed to be destroyed',
        ],
      );
    }

    if (isDone) {
      destroyed++;
      // ⚠️ What the destruction COST is a financial_expenses row keyed on the
      // SR number -- not a column on the destruction. Without it the
      // "Destruction Expenses" column is blank on an otherwise finished row.
      await conn.execute(
        r'insert into public.financial_expenses '
        r'(kind, amount, description, yard, sr_number, package_item_id, '
        r' incurred_on, created_at) '
        r"values ('destruction_expense',$1,$2,$3,$4,$5,$6,$7)",
        parameters: [
          (3000 + _rng.nextInt(48000)).toDouble(),
          _destructionExpenseNotes[
              _rng.nextInt(_destructionExpenseNotes.length)],
          _yard, srNumber, itemId, _iso(destroyedAt!), destroyedAt,
        ],
      );
      // The goods are gone: the held entry goes with them, so they stop
      // occupying a zone.
      if (itemId != null) {
        await conn.execute(
          r'delete from public.warehouse_entries '
          r'where package_item_id = $1 and coalesce(is_returned,false) = false',
          parameters: [itemId],
        );
      }
    } else {
      pending++;
    }
  }

  print('  destruction:');
  print('    $viaValuation via Valuation · $direct recorded directly');
  print('    $destroyed destroyed · $pending still pending');
}

const _destructionNotes = [
  'Unfit for human consumption',
  'Prohibited goods — court ordered destruction',
  'Damaged beyond recovery',
  'Expired stock',
  'Counterfeit goods',
];

const _destructionExpenseNotes = [
  'Incinerator hire and fuel',
  'Transport to the destruction site',
  'Labour and supervision',
  'Landfill and handling charges',
];

/// One destruction batch. Mirrors the tender-sale shape, which it shares.
Future<String> _newDestruction(
    Connection conn, DateTime at, int serial) async {
  final res = await conn.execute(
    r'insert into public.destructions '
    r'(sale_number, sale_date, serial, year, tender_type, yard, sale_time, '
    r' sale_end_time, created_at) '
    r"values ($1,$2,$3,$4,'destruction',$5,'09:00','15:00',$6) returning id",
    parameters: [
      'DS/$_yard/${at.year}/${serial.toString().padLeft(3, '0')}',
      _iso(at),
      serial,
      at.year,
      _yard,
      at,
    ],
  );
  return res.first.first as String;
}

/// Runs goods through the whole disposal-and-tender pipeline.
///
/// Nothing seeded any of it, so every screen downstream of "Send Disposal
/// Request" was empty: Pending Valuation, Unsold Tenders, Tender Sales, Sold
/// Goods and Unsold Goods. The chain is:
///
///   disposal_requests
///     -> disposal_request_items   (valuation_cost, then forwarded)
///       -> tender_sales           (a sale, with a close time)
///         -> tender_sale_items    (sold / not sold, per item)
///           -> tender_bids + tender_revaluations  (for a round that failed)
///
/// ⚠️ A request stays in the Pending Valuation feed while ANY of its items is
/// NOT forwarded. So a request whose items are all forwarded has moved on to
/// Central Disposal and must not be counted as pending -- and one left
/// unforwarded is what makes that page show anything at all.
///
/// ⚠️ Re-tendering does NOT reuse the item's row. Each round INSERTS a new
/// tender_sale_items row against a new sale, leaving the previous round's row
/// untouched and still marked unsold -- that is what "times tendered" counts.
/// Overwriting the old row would erase the history the Valuation portal reads.
Future<void> _seedTenderPipeline(Connection conn) async {
  // Goods that are genuinely disposable: past the appeal window, not held, not
  // already finished. These are what a yard would actually send.
  final rows = await conn.execute(
    'select fp.id, fp.yard, fp.item_id, pi.unit_value, pi.quantity '
    'from public.forfeited_packages fp '
    'join public.package_items pi on pi.id = fp.item_id '
    'where fp.appeal_deadline < now() '
    '  and coalesce(fp.appeal_hold, false) = false '
    "  and pi.status not in ('returned', 'other', 'sold', 'destroyed') "
    'order by fp.forfeited_at asc',
  );

  if (rows.isEmpty) {
    print('  no disposable packages -- tender pipeline skipped');
    return;
  }

  // Split the pool across the outcomes that need to exist.
  final pool = rows.toList();
  var pendingValuation = 0;
  var soldFirstRound = 0;
  final soldOnRound = <int, int>{};
  var stillUnsold = 0;
  var saleSerial = 0;

  // ── 1. Requests still awaiting valuation ─────────────────────────────────
  // Left with valuation_cost null and forwarded false, which is the only
  // state the Valuation portal's first tab shows.
  // ⚠️ Several SEPARATE requests, not one big one. A yard sends a batch and
  // then sends another; the directorate sees a queue of arrivals, each with
  // its own date. Putting all 14 on one request made the page read "1
  // request(s)" -- a queue of one, which is not what a queue looks like.
  //
  // Some of them are PART-VALUED: a cost entered against a few items while the
  // rest wait. That is the ordinary half-finished state, and the request stays
  // pending because at least one item is still unforwarded.
  final awaiting = pool.take(26).toList();
  pool.removeRange(0, awaiting.length);
  var idx = 0;
  var reqNo = 0;
  while (idx < awaiting.length) {
    final size = 3 + _rng.nextInt(4);
    final slice = awaiting.skip(idx).take(size).toList();
    idx += slice.length;
    reqNo++;

    final reqId = await _newDisposalRequest(
        conn,
        DateTime.now().subtract(Duration(days: 1 + _rng.nextInt(20))),
        'pending_valuation');

    // Every second request arrives with some of its items already costed.
    final partValued = reqNo.isEven;
    for (var i = 0; i < slice.length; i++) {
      final r = slice[i];
      // Never value them all -- a fully valued request would be forwarded.
      final valued = partValued && i < slice.length - 1 && _rng.nextBool();
      final unitValue = double.tryParse('${r[3]}') ?? 5000;
      final qty = (r[4] as int?) ?? 1;
      await conn.execute(
        r'insert into public.disposal_request_items '
        r'(request_id, forfeited_package_id, disposition, valuation_cost, forwarded) '
        r"values ($1,$2,'sale',$3,false)",
        parameters: [
          reqId,
          r[0] as String,
          valued
              ? (unitValue * qty * (0.55 + _rng.nextDouble() * 0.35))
                  .roundToDouble()
              : null,
        ],
      );
      pendingValuation++;
    }
  }

  // ── 2. Everything else was valued, forwarded and tendered ────────────────
  // Each package gets a number of ROUNDS. A round that fails leaves bids and a
  // re-valuation behind and the goods go round again -- which is exactly what
  // the Unsold Tenders tab is for.
  // The request currently being filled, and how many more packages go on it.
  String? batchReqId;
  DateTime? batchAt;
  var batchLeft = 0;

  // Sales already opened, so several packages can share one -- keyed by the
  // month and round they fall in, with the sale's own date and how full it is.
  final saleByKey = <String, String>{};
  final saleFill = <String, int>{};
  final saleDateByKey = <String, DateTime>{};

  for (final r in pool) {
    if (_rng.nextInt(100) >= 55) continue;

    final fpId = r[0] as String;
    final itemId = r[2] as String?;
    // ⚠️ A postgres `numeric` comes back as a STRING, not a num -- casting it
    // straight to num? throws. Parse it instead.
    final unitValue = double.tryParse('${r[3]}') ?? 5000;
    final qty = (r[4] as int?) ?? 1;

    // A valuation is the reserve the goods are offered at.
    var valuation = (unitValue * qty * (0.55 + _rng.nextDouble() * 0.35))
        .roundToDouble();

    // A yard sends a BATCH, not one package at a time -- so several packages
    // share a request, the way the Central Disposal list actually reads.
    if (batchLeft == 0 || batchReqId == null) {
      batchAt = DateTime.now().subtract(Duration(days: 60 + _rng.nextInt(500)));
      batchReqId = await _newDisposalRequest(conn, batchAt!, 'forwarded');
      batchLeft = 2 + _rng.nextInt(5);
    }
    batchLeft--;
    final requestedAt = batchAt!;
    final reqId = batchReqId!;
    await conn.execute(
      r'insert into public.disposal_request_items '
      r'(request_id, forfeited_package_id, disposition, valuation_cost, forwarded) '
      r"values ($1,$2,'sale',$3,true)",
      parameters: [reqId, fpId, valuation],
    );

    // How many times it goes to tender before it sells -- or never does.
    // 1 is much the commonest: most goods sell first time.
    final roll = _rng.nextInt(100);
    final int rounds;
    final bool everSells;
    if (roll < 45) {
      rounds = 1;
      everSells = true;
    } else if (roll < 62) {
      rounds = 2;
      everSells = true;
    } else if (roll < 74) {
      rounds = 3;
      everSells = true;
    } else if (roll < 82) {
      rounds = 4;
      everSells = true;
    } else {
      // Still going round: every round so far failed, and the last one is
      // still sitting in the unsold pool waiting to be re-valued.
      //
      // ⚠️ Up to FOUR, not three. A package that sells on its fourth attempt
      // leaves the unsold pool the moment it sells, so if unsold packages
      // stopped at three rounds the Unsold Tenders list could never show a
      // "4x" -- the count only ever appeared on goods that had already gone.
      rounds = 1 + _rng.nextInt(4);
      everSells = false;
    }

    var saleAt = requestedAt.add(Duration(days: 10 + _rng.nextInt(25)));

    for (var round = 1; round <= rounds; round++) {
      // The last round sells only when the goods ever sell.
      final isLast = round == rounds;
      final sold = isLast && everSells;

      // Every sale must already have closed, or the goods are still on offer
      // and cannot be counted sold or unsold yet.
      if (saleAt.isAfter(DateTime.now().subtract(const Duration(days: 2)))) {
        saleAt = DateTime.now().subtract(Duration(days: 3 + _rng.nextInt(40)));
      }

      // ⚠️ A tender sale is a SALE, not a lot: several packages go under the
      // one sale number. Minting a fresh sale per package made every sale a
      // single-item auction, which is not how a tender reads. Packages whose
      // round falls near the same date share the sale.
      final saleKey = '${saleAt.year}-${saleAt.month}-${round}';
      var saleId = saleByKey[saleKey];
      if (saleId == null || (saleFill[saleKey] ?? 0) >= 4) {
        saleSerial++;
        saleId = await _newTenderSale(conn, saleAt, saleSerial);
        saleByKey[saleKey] = saleId;
        saleFill[saleKey] = 0;
        saleDateByKey[saleKey] = saleAt;
      }
      saleFill[saleKey] = (saleFill[saleKey] ?? 0) + 1;
      // Every package in one sale is sold or unsold on that sale's own date.
      saleAt = saleDateByKey[saleKey]!;

      final soldPrice = sold
          ? (valuation * (1.0 + _rng.nextDouble() * 0.45)).roundToDouble()
          : null;

      await conn.execute(
        r'insert into public.tender_sale_items '
        r'(tender_sale_id, forfeited_package_id, package_item_id, yard, sold, '
        r' sold_at, sold_price, receipt_number, is_delivered, delivered_at, created_at) '
        r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)',
        parameters: [
          saleId, fpId, itemId, _yard, sold,
          sold ? saleAt : null,
          soldPrice,
          sold ? 'TR/$_yard/${saleAt.year}/${2000 + saleSerial}' : null,
          sold && _rng.nextBool(),
          sold && _rng.nextBool() ? saleAt.add(const Duration(days: 3)) : null,
          saleAt,
        ],
      );

      if (sold) {
        // The goods have left the yard.
        if (itemId != null) {
          await conn.execute(
            r"update public.package_items set status = 'sold' where id = $1",
            parameters: [itemId],
          );
        }
        if (round == 1) {
          soldFirstRound++;
        } else {
          soldOnRound[round] = (soldOnRound[round] ?? 0) + 1;
        }
      } else {
        // A failed round: the bids that came in, all under the reserve, and
        // the re-valuation that follows from them.
        final bidCount = _rng.nextInt(4);
        for (var b = 0; b < bidCount; b++) {
          await conn.execute(
            r'insert into public.tender_bids '
            r'(forfeited_package_id, tender_sale_id, amount, yard, created_at) '
            r'values ($1,$2,$3,$4,$5)',
            parameters: [
              fpId, saleId,
              (valuation * (0.35 + _rng.nextDouble() * 0.45)).roundToDouble(),
              _yard, saleAt.add(Duration(hours: 1 + b)),
            ],
          );
        }

        // The re-valuation is only recorded when the goods go round AGAIN --
        // the last failed round is left PENDING re-valuation on purpose, so
        // the Valuation portal has something waiting in its second tab.
        if (!isLast) {
          // Goods that did not sell are worth less than the reserve said.
          valuation = (valuation * (0.72 + _rng.nextDouble() * 0.15))
              .roundToDouble();
          await conn.execute(
            r'insert into public.tender_revaluations '
            r'(forfeited_package_id, tender_sale_id, valuation_cost, note, yard, created_at) '
            r'values ($1,$2,$3,$4,$5,$6)',
            parameters: [
              fpId, saleId, valuation,
              bidCount == 0
                  ? 'No bids received — reserve lowered for re-tender'
                  : 'Bids below reserve — reserve lowered for re-tender',
              _yard, saleAt.add(const Duration(days: 1)),
            ],
          );
        } else {
          stillUnsold++;
        }
      }

      saleAt = saleAt.add(Duration(days: 25 + _rng.nextInt(40)));
    }
  }

  final laterRounds =
      soldOnRound.entries.map((e) => 'round ${e.key}: ${e.value}').join(', ');
  print('  tender pipeline:');
  print('    $pendingValuation awaiting valuation across $reqNo requests');
  print('    $soldFirstRound sold first time'
      '${laterRounds.isEmpty ? '' : ' · $laterRounds'}');
  print('    $stillUnsold still unsold (awaiting re-valuation)');
}

/// One disposal request, dated and with the valuation state given.
Future<String> _newDisposalRequest(
    Connection conn, DateTime at, String valuationStatus) async {
  final res = await conn.execute(
    r'insert into public.disposal_requests '
    r'(yard, request_date, status, valuation_status, valued_at, created_at) '
    r'values ($1,$2,$3,$4,$5,$6) returning id',
    parameters: [
      _yard,
      _iso(at),
      valuationStatus == 'pending_valuation' ? 'pending' : 'forwarded',
      valuationStatus,
      valuationStatus == 'pending_valuation' ? null : at,
      at,
    ],
  );
  return res.first.first as String;
}

/// One tender sale. The close time is in the PAST for every seeded sale, so
/// the valuation is unsealed and the items can be counted sold or unsold.
Future<String> _newTenderSale(
    Connection conn, DateTime saleAt, int serial) async {
  final res = await conn.execute(
    r'insert into public.tender_sales '
    r'(sale_number, sale_date, serial, year, tender_type, yard, sale_time, '
    r' sale_end_time, created_at) '
    r"values ($1,$2,$3,$4,'general',$5,'09:00','15:00',$6) returning id",
    parameters: [
      'TS/$_yard/${saleAt.year}/${serial.toString().padLeft(3, '0')}',
      _iso(saleAt),
      serial.toString(),
      saleAt.year,
      _yard,
      saleAt,
    ],
  );
  return res.first.first as String;
}

/// Finishes off a share of the "Other" goods.
///
/// An "Other" item that is still being worked reads as Enabled / On Appeal
/// Hold / Decided. But once the yard records the outcome the process is OVER,
/// and the row becomes a completed, read-only record -- the page shows a
/// `_CompletedChip` instead of an appeal state, and offers no actions. Nothing
/// seeded that, so the finished half of the page never appeared.
///
/// Mirrors `recordFinalDisposition`, which is the only thing that produces it:
///
///   * inserts a RETURNED entry tagged "[FINAL:OTHER] — <outcome>",
///   * sets the item's status to 'other',
///   * and DELETES the remaining held entry, because the goods have left the
///     yard and must stop occupying (and being charged for) a zone.
///
/// ⚠️ The tag format is exact: `[FINAL:OTHER] — <text>` with an EM DASH.
/// `_finalOtherLabel` matches on it, and the outcome text shown on the chip is
/// whatever follows it -- a hyphen there leaves every row labelled a bare
/// "Other".
///
/// Both routes into it are seeded, because the yard reaches this state two
/// ways and they look identical afterwards:
///   * goods that went to appeal and came back with a ruling, and
///   * goods the yard finished directly, no appeal ever lodged.
Future<void> _seedFinalOtherOutcomes(Connection conn) async {
  // Only items whose window has closed: goods still inside their 30 days
  // cannot have been disposed of yet.
  final rows = await conn.execute(
    'select we.id, we.package_item_id, we.item_count, we.admitted_at, '
    '       we.package_id, we.warehouse_id, we.zone, we.hold_reason, '
    '       we.daily_rate, '
    '       (fp.id is not null and fp.item_appeal_decisions <> ' r"'{}'" '::jsonb) '
    '         as was_appealed '
    'from public.warehouse_entries we '
    'join public.package_items pi on pi.id = we.package_item_id '
    'join public.packages p on p.id = we.package_id '
    'left join public.forfeited_packages fp on fp.item_id = pi.id '
    'where pi.status = ' r"'Other'" ' '
    '  and coalesce(we.is_returned, false) = false '
    '  and coalesce(p.entry_date, p.created_at) < now() - interval ' r"'30 days'" ' '
    'order by we.admitted_at asc',
  );

  var afterAppeal = 0;
  var direct = 0;

  for (final r in rows) {
    final appealed = (r[9] as bool?) ?? false;
    // ⚠️ Goods that came BACK from an appeal are the scarce case -- only a
    // fraction of "Other" items were ever ruled on, so sampling them at the
    // same rate as the rest left barely any. A ruling is an instruction to
    // act, so every ruled item is carried out; the unappealed ones, which are
    // plentiful, are sampled.
    if (!appealed && _rng.nextInt(100) >= 30) continue;

    final entryId = r[0] as String;
    final itemId = r[1] as String;
    final qty = r[2] as int? ?? 0;
    final admittedAt = r[3] as DateTime;
    final pkgId = r[4] as String;
    final warehouseId = r[5] as String?;
    final zone = r[6] as String?;
    final holdReason = r[7] as String?;
    final dailyRate = r[8];
    final wasAppealed = appealed;

    // Finished some time after admission, but never in the future.
    var finishedAt = admittedAt.add(Duration(days: 35 + _rng.nextInt(150)));
    final now = DateTime.now();
    if (finishedAt.isAfter(now)) {
      finishedAt = now.subtract(Duration(days: 1 + _rng.nextInt(30)));
    }

    final outcome = wasAppealed
        ? _finalOtherAfterAppeal[_rng.nextInt(_finalOtherAfterAppeal.length)]
        : _finalOtherDirect[_rng.nextInt(_finalOtherDirect.length)];

    await conn.execute(
      r'insert into public.warehouse_entries '
      r'(package_id, package_item_id, warehouse_id, hold_reason, item_count, '
      r' zone, yard, daily_rate, admitted_at, is_returned, returned_at, '
      r' return_notes, created_at, updated_at) '
      r'values ($1,$2,$3,$4,$5,$6,$7,$8,$9,true,$10,$11,$10,$10)',
      parameters: [
        pkgId, itemId, warehouseId, holdReason, qty, zone, _yard,
        dailyRate, admittedAt, finishedAt,
        '[FINAL:OTHER] — $outcome',
      ],
    );

    await conn.execute(
      r"update public.package_items set status = 'other' where id = $1",
      parameters: [itemId],
    );

    // The goods have left the yard: the held entry goes, exactly as
    // recordFinalDisposition deletes it, so the zone is freed.
    await conn.execute(
      r'delete from public.warehouse_entries where id = $1',
      parameters: [entryId],
    );

    if (wasAppealed) {
      afterAppeal++;
    } else {
      direct++;
    }
  }
  print('  ${afterAppeal + direct} "Other" processes completed '
      '($afterAppeal after an appeal, $direct directly)');
}

/// Outcomes recorded once an appeal came back and the yard acted on it.
const _finalOtherAfterAppeal = [
  'Released on appeal ruling',
  'Re-exported per appeal ruling',
  'Handed to the owner after appeal',
  'Auctioned per appeal ruling',
];

/// Outcomes the yard recorded directly, with no appeal ever lodged.
const _finalOtherDirect = [
  'Transferred to Government Use',
  'Handed over to the Police',
  'Donated to a charity',
  'Returned to the shipping line',
  'Disposed of by public auction',
];

/// Releases a share of the detained goods back to their owners.
///
/// Mirrors what `markAsReturned` does for a FULL release, because the Released
/// Goods page reads the result rather than any release record of its own:
///
///   * the held warehouse_entries row is REPLACED by a returned one
///     (`is_returned`, `returned_at`, `return_notes`) -- the held row is
///     deleted, so the goods stop occupying the zone,
///   * and the item's status becomes 'returned'.
///
/// ⚠️ The receipt number lives INSIDE `return_notes`, formatted
/// "Receipt No: <no> | Date: <date>" -- there is no receipt column. The page
/// parses it back out of that string, so the format is load-bearing: a note
/// that does not match shows an empty Receipt No.
///
/// ⚠️ A note starting with "[" is read as a DISPOSITION tag, not a release
/// ([FINAL:RELEASED] aside), so a released row must never begin with one --
/// `_isReleaseEntry` would filter it straight off the page.
Future<void> _seedReleases(Connection conn) async {
  // Only goods still held, and only Detain -- releasing forfeited or abandoned
  // goods would contradict the disposition they already carry.
  final rows = await conn.execute(
    'select we.id, we.package_item_id, we.item_count, we.admitted_at, p.entry_date '
    'from public.warehouse_entries we '
    'join public.package_items pi on pi.id = we.package_item_id '
    'join public.packages p on p.id = we.package_id '
    'where pi.status = ' r"'Detain'" ' '
    '  and coalesce(we.is_returned, false) = false '
    'order by we.admitted_at asc',
  );

  var released = 0;
  for (final r in rows) {
    // One in three detained items is released back to its owner.
    if (_rng.nextInt(3) != 0) continue;

    final entryId = r[0] as String;
    final itemId = r[1] as String;
    final admittedAt = r[3] as DateTime;

    // Released some time after admission, but never in the future.
    var releasedAt = admittedAt.add(Duration(days: 12 + _rng.nextInt(120)));
    final now = DateTime.now();
    if (releasedAt.isAfter(now)) {
      releasedAt = now.subtract(Duration(days: 1 + _rng.nextInt(20)));
    }

    final receiptNo = 'RCP/$_yard/${releasedAt.year}/'
        '${(1000 + _rng.nextInt(8999))}';
    final notes = 'Receipt No: $receiptNo | Date: ${_iso(releasedAt)}';

    // The held row BECOMES the returned row. markAsReturned inserts a new one
    // and deletes the held one; the outcome is identical and this keeps the
    // warehouse_entries id stable for anything already pointing at it.
    await conn.execute(
      r'update public.warehouse_entries '
      r'set is_returned = true, returned_at = $2, return_notes = $3, '
      r'    updated_at = $2 '
      r'where id = $1',
      parameters: [entryId, releasedAt, notes],
    );

    await conn.execute(
      r"update public.package_items set status = 'returned' where id = $1",
      parameters: [itemId],
    );
    released++;
  }
  print('  $released detained items released back to their owners');
}

/// Marks a share of the packages as migrated from a previous register.
///
/// The Old Entries page lists packages whose `old_sr_number` is set -- goods
/// that were already in the yard under the PREVIOUS register when this system
/// took over, and were carried across keeping both numbers. Nothing else marks
/// a package as migrated, so with the column empty everywhere the page has
/// nothing to show.
Future<void> _seedOldEntries(Connection conn) async {
  // Only the earliest packages: a migration happened once, at changeover, so
  // goods registered later cannot have come from the old book.
  final rows = await conn.execute(
    'select id, sr_number from public.packages '
    'where old_sr_number is null '
    'order by coalesce(entry_date, created_at) asc limit 60',
  );

  var migrated = 0;
  for (final r in rows) {
    if (_rng.nextInt(3) != 0) continue;

    final id = r[0] as String;
    // The old register was kept by hand in a different shape entirely --
    // no directorate prefix, no yard, just a book and a page.
    final oldNumber = 'SR/${1200 + _rng.nextInt(2600)}/'
        '${2021 + _rng.nextInt(3)}';

    await conn.execute(
      r'update public.packages set old_sr_number = $2 where id = $1',
      parameters: [id, oldNumber],
    );
    migrated++;
  }
  print('  $migrated packages carried over from the previous register');
}

/// Lodges appeals against DETAINED goods.
///
/// ⚠️ A detained item has no `forfeited_packages` row of its own -- the Appeal
/// portal synthesises one (`source: 'detain'`) so the item can be seen. But a
/// synthesised row is rebuilt on every read, so it can hold NOTHING: no hold,
/// no decision, no stable id. The moment an appeal is actually lodged against
/// detained goods, a real row has to exist to carry it -- which is exactly what
/// `getAppealablePackages` looks for when it prefers the STORED row.
///
/// Without this, detained goods could only ever show "Appealing" or "Enabled":
/// the two ruled states were unreachable for them, whatever the yard did.
Future<void> _seedDetainAppeals(Connection conn) async {
  // Only items still held in a warehouse -- a returned item is not detained
  // any more, and the portal skips it.
  final rows = await conn.execute(
    'select pi.id, pi.package_id, p.sr_number, p.consignee_name, pi.quantity, '
    '       coalesce(p.entry_date, p.created_at) as entered '
    'from public.package_items pi '
    'join public.packages p on p.id = pi.package_id '
    'where pi.status = ' r"'Detain'" ' '
    '  and exists (select 1 from public.warehouse_entries we '
    '               where we.package_item_id = pi.id '
    '                 and coalesce(we.is_returned, false) = false) '
    'order by coalesce(p.entry_date, p.created_at) asc',
  );

  var made = 0;
  for (final r in rows) {
    // Half of the detained goods are appealed. It has to be a decent share:
    // the coverage pass below claims the first row of each kind for a HOLD, so
    // a thin pool leaves almost nothing over to be decided or left counting
    // down, and detained goods show only one of the four states.
    if (_rng.nextInt(2) != 0) continue;

    final itemId = r[0] as String;
    final pkgId = r[1] as String;
    final srNumber = r[2] as String;
    final consignee = r[3] as String? ?? '';
    final qty = r[4] as int? ?? 0;
    final entered = r[5] as DateTime;

    await conn.execute(
      r'insert into public.forfeited_packages '
      r'(package_id, item_id, sr_number, consignee_name, forfeited_at, '
      r' appeal_deadline, reason, source, yard, entry_qty, created_at, updated_at) '
      r'values ($1,$2,$3,$4,$5,$6,$7,' r"'detain'" r',$8,$9,$5,$5)',
      parameters: [
        pkgId, itemId, srNumber, consignee, entered,
        entered.add(const Duration(days: 30)),
        'Detained pending inquiry', _yard, qty,
      ],
    );
    made++;
  }
  print('  $made detained items now carry an appeal row');
}

Future<void> _seedAppealOutcomes(Connection conn) async {
  // ⚠️ OLDEST first, and it matters. Ruling on a row ends its countdown, so
  // working newest-first spent every still-open appeal on a hold or a decision
  // and left "Appealing - Nd" with nothing in it at all. The expired rows are
  // ruled on first; the live ones are reached last, and are protected below.
  final rows = await conn.execute(
    'select fp.id, fp.item_id, fp.source, pi.item_name, '
    '       (fp.appeal_deadline > now()) as in_window '
    'from public.forfeited_packages fp '
    'join public.package_items pi on pi.id = fp.item_id '
    'where fp.item_id is not null order by fp.forfeited_at asc',
  );

  var decided = 0;
  var held = 0;

  // ⚠️ A random roll leaves whole kinds of goods untouched -- the rarer ones
  // never come up, and those goods can never be seen in that state at all. So
  // coverage is taken FIRST, and it is keyed on the GOODS NAME.
  //
  // Not on (source, goods): that made 94 pairs out of 26 kinds of goods and so
  // 94 separate holds, which is what buried the Appeal Directorate under more
  // open appeals than decided ones. Every kind of goods needs to be SEEN on
  // hold; it does not need to be on hold once per disposition.
  final pairs = <String>{
    for (final r in rows) r[3] as String,
  };
  final needHold = {...pairs};
  final needDecision = {...pairs};

  // Most of the still-open appeals are left strictly alone, so the plain
  // countdown state survives -- it is the state the yard sees most often, and
  // ruling on all of them erases it.
  var liveSeen = 0;

  for (final r in rows) {
    final id = r[0] as String;
    final itemId = r[1] as String;
    final pair = r[3] as String;
    final inWindow = r[4] as bool;

    // A HOLD is an appeal still waiting to be heard, so only a few should be
    // outstanding at once -- an Appeal Directorate with 84 open appeals and 22
    // ruled has the balance backwards. Holds are therefore spent ONLY on
    // coverage: one per kind of goods, so every kind can be seen in that
    // state, and no more. Everything else is ruled on.
    final coverHold = needHold.contains(pair);

    // Every third live appeal is left counting down, so "In Appeal Window"
    // keeps a real population. Coverage overrides this -- some kinds of goods
    // (other|Used Engine Blocks) exist ONLY as a live appeal, and skipping
    // those left them with no hold at all, which the check below then caught.
    if (inWindow && !coverHold && (liveSeen++ % 3 != 0)) continue;

    // ⚠️ Most EXPIRED rows are left alone. Ruling on every one of them wiped
    // out "Enabled" entirely -- the ordinary state of goods whose window ran
    // out with no appeal ever lodged, and the one the yard sees most. An
    // appeal is the exception, not the rule: most goods are never appealed.
    if (!inWindow && !coverHold && _rng.nextInt(100) >= 30) continue;

    if (coverHold) {
      needHold.remove(pair);
    } else {
      needDecision.remove(pair);
    }

    if (!coverHold) {
      final decision = _appealDecisions[_rng.nextInt(_appealDecisions.length)];
      await conn.execute(
        r'update public.forfeited_packages '
        r'set item_appeal_decisions = coalesce(item_appeal_decisions, ' r"'{}'" r'::jsonb) '
        r'      || jsonb_build_object($2::text, jsonb_build_object('
        r'           ' r"'decision'" r', $3::text, '
        r'           ' r"'note'" r', $4::text, '
        r'           ' r"'decided_at'" r', $5::timestamptz)), '
        r'    appeal_hold = false, '
        r'    held_item_ids = ' r"'{}'" r'::uuid[], '
        r'    appeal_decided_at = $5 '
        r'where id = $1',
        parameters: [
          id,
          itemId,
          decision.$1,
          decision.$2,
          DateTime.now().subtract(Duration(days: 1 + _rng.nextInt(45))),
        ],
      );
      decided++;
    } else {
      // An appeal lodged and NOT yet ruled on. A hold outlasts the deadline:
      // these stay blocked even once the 30 days have run out, which is the
      // one state the calendar alone can never produce.
      await conn.execute(
        r'update public.forfeited_packages '
        r'set appeal_hold = true, '
        r'    held_item_ids = array[$2::uuid], '
        r'    appeal_hold_note = $3, '
        r'    appeal_held_at = $4 '
        r'where id = $1',
        parameters: [
          id,
          itemId,
          _appealHoldNotes[_rng.nextInt(_appealHoldNotes.length)],
          DateTime.now().subtract(Duration(days: 1 + _rng.nextInt(20))),
        ],
      );
      held++;
    }
  }

  print('\n── Appeal outcomes ' + '─' * 50);
  print('  decided        $decided');
  print('  on appeal hold $held');
  print('  untouched      ${rows.length - decided - held}');
  // A hold is guaranteed for every kind of goods -- that was the requirement,
  // and it is checked hard.
  if (needHold.isNotEmpty) {
    throw StateError('no appeal hold seeded for: ${needHold.join(', ')}');
  }
  // A decision cannot be guaranteed the same way: a kind with only ONE
  // forfeited row spends it on the hold, since a single row cannot be both
  // held and decided. Those are reported, not treated as a failure.
  if (needDecision.isNotEmpty) {
    print('  ${needDecision.length} kinds have a hold but no decision '
        '(only one row each)');
  }
}

/// The rulings the Appeal Directorate can return, with the note it files.
///
/// ⚠️ These five codes are exactly the five actions the yard can carry out in
/// Final Disposition (Release / Sale / Destroy / Re-export / Other). A ruling
/// is an instruction to take ONE of them, so a code outside that set would name
/// an action the yard has no way to perform -- and [ItemAppealOutcome.label]
/// returns null for anything it does not know, which renders as no decision at
/// all.
///
/// ⚠️ The note for 'OTHER' becomes the chip's LABEL, and it is FREE TEXT the
/// officer types -- the app supplies no wording of its own for it. So it must
/// read as one of the outcomes the yard can actually record, never as an
/// invented decision of its own ("Referred back to yard" was such an
/// invention: it looked like a sixth decision the app does not have). The
/// other four have fixed labels and their note is free to explain itself.
const _appealDecisions = <(String, String)>[
  ('RELEASE', 'Appeal allowed — goods released to the owner'),
  ('SALE', 'Appeal dismissed — goods to be sold at auction'),
  ('DESTROY', 'Appeal dismissed — goods unfit, to be destroyed'),
  ('RE-EXPORT', 'Appeal allowed in part — re-export permitted'),
  ('OTHER', 'Disposal by public auction'),
];

const _appealHoldNotes = [
  'Appeal lodged by the consignee — under review',
  'Written objection received, awaiting hearing',
  'Documents called for from the declarant',
  'Hearing scheduled — decision reserved',
];

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
    // Open-area goods.
    'Vehicle Leaf Springs': 'Vehicle Parts and Tyres',
    'Truck Tyres': 'Vehicle Parts and Tyres',
    'Used Engine Blocks': 'Vehicle Parts and Tyres',
    'Scrap Steel Bundles': 'Metals & Hardware',
    'Cast Iron Pipes': 'Metals & Hardware',
    'Steel Reinforcement Bars': 'Building Materials',
  };
  return map[itemName] ?? 'General Cargo';
}

/// The warehouse each category prefers. Bulky, weather-tolerant cargo goes to
/// the open area; everything else under cover.
/// ⚠️ No entry here is 'OA1'. The open area belongs to the OA register alone,
/// and _placeIn sends those there directly -- an SR item must stay under
/// cover even when its category is the bulky kind, or the two registers stop
/// meaning anything.
const _preferredWarehouse = {
  'Household & Kitchenware': 'W01',
  'Textiles and Apparel': 'W01',
  'General Cargo': 'W01',
  'Electrical & Electronics': 'W02',
  'Medical Supplies': 'W02',
  'Foodstuffs & Perishables': 'W02',
  'Metals & Hardware': 'W03',
  'Chemicals & Solvents': 'W03',
  'Building Materials': 'W03',
  'Vehicle Parts and Tyres': 'W01',
};

/// Finds a zone with room for [qty] and books the space.
///
/// Tries the category's own warehouse first, then any other -- which is what
/// the SR form lets an officer do when the zone they wanted is full. A zone is
/// never taken past its capacity, so the Zone Capacity page reports something
/// true; returns null only when nothing anywhere can take the goods.
(String, String)? _placeIn(String itemName, int qty,
    Map<String, String> whs, Map<String, int> space,
    {bool openArea = false}) {
  final cat = _categoryFor(itemName, false);
  final preferred = openArea ? 'OA1' : (_preferredWarehouse[cat] ?? 'W01');

  // ⚠️ An OA number's goods belong in the Open Area, and an SR number's under
  // cover. The two registers exist to keep them apart, so the fallback never
  // crosses between them -- it only tries other zones of the same kind.
  final order = openArea
      ? ['OA1']
      : [preferred, ...whs.keys.where((c) => c != preferred && c != 'OA1')];

  for (final code in order) {
    final keys = space.keys.where((k) => k.startsWith('$code|')).toList()
      ..sort();
    for (final k in keys) {
      if ((space[k] ?? 0) >= qty) {
        space[k] = space[k]! - qty;
        return (whs[code]!, k.split('|')[1]);
      }
    }
  }
  return null;
}

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
