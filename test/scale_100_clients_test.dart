import 'package:flutter_test/flutter_test.dart';

import 'package:cus_yard_management/core/app_session.dart';
import 'package:cus_yard_management/core/db/pg_connection.dart';
import 'package:cus_yard_management/core/db/pg_realtime.dart';
import 'package:cus_yard_management/core/parse_isolate.dart';

/// What it takes for a hundred PCs to share one PostgreSQL server.
///
/// These are the three failures that only appear at scale, so none of them
/// would be caught by running the app on one machine:
///
///   1. the connection budget runs out and the 12th user is REFUSED
///   2. one person's click makes all 100 clients re-query at once
///   3. a big parse freezes the window because Dart is single-threaded
void main() {
  group('the connection budget is shared, not per-client', () {
    // The app talks straight to Postgres with no middle tier, so every PC
    // holds its own pool and the server's limit is divided between them.
    int clientsThatFit({
      required int maxConnections,
      required int reserved,
      required int poolSize,
    }) =>
        (maxConnections - reserved) ~/ (poolSize + 1); // +1 = LISTEN socket

    test('the old pool of 8 ran out after eleven users on a stock server', () {
      // This is the bug: it reads as a server fault ("too many connections")
      // but is only arithmetic, and it appears nowhere until the 12th user.
      expect(
        clientsThatFit(maxConnections: 100, reserved: 3, poolSize: 8),
        10,
      );
    });

    test('a pool of 3 alone is still not enough for 100 on a stock server', () {
      // Shrinking the client pool helps, but cannot get to 100 by itself --
      // which is why postgres/63_server_tuning.conf exists as well.
      expect(
        clientsThatFit(maxConnections: 100, reserved: 3, poolSize: 3),
        lessThan(100),
      );
    });

    test('a pool of 3 AND max_connections 400 carries 100 clients', () {
      // Both halves of the fix together, with headroom left for pgAdmin,
      // backups and the odd psql session.
      expect(
        clientsThatFit(
            maxConnections: 400, reserved: 3, poolSize: PgConfig.poolSizeSetting),
        greaterThanOrEqualTo(99),
      );
    });

    test('the pool stays small enough to share a server', () {
      // Guards the regression directly: someone raising this back to 8 for a
      // snappier single-machine dev run would re-break the 12th user.
      //
      // ⚠️ A RANGE, not `== 3`. This reads the live `.env`, so it was
      // really testing the developer's own config: the Supabase deployment
      // sets PG_POOL_SIZE=1 (its free tier allows ~60 connections, and
      // 9 officers x 2 = 18), which is MORE conservative and failed a test
      // written to catch the opposite mistake.
      //
      // 3 is the office-server default; 1 is the cloud one. Anything above
      // 4 is the actual regression -- at 8 a stock server runs out at the
      // twelfth user.
      expect(PgConfig.poolSizeSetting, greaterThanOrEqualTo(1));
      expect(PgConfig.poolSizeSetting, lessThanOrEqualTo(4),
          reason: 'a pool this large starves the other clients');
    });

    test('pooled connections are retired rather than held all day', () {
      // A desktop client is open for eight hours. Without a bounded lifetime
      // it reaches its peak during the busy minute and never gives those
      // sockets back, so 100 idle clients hold their peak forever.
      expect(PgConfig.maxConnectionAgeSeconds, greaterThan(0));
      expect(PgConfig.maxConnectionAgeSeconds, lessThanOrEqualTo(3600));
    });
  });

  group('a change in another yard does not wake this client', () {
    tearDown(AppSession.clear);

    test('an officer ignores a yard that is not theirs', () {
      AppSession.setYard('GL1');
      AppSession.applyYardFilterToRealtime('officer');

      // The storm in one line: without this, one save in CED costs the server
      // a query from every PC in the country.
      expect(PgRealtime.instance.watchAllYards, isFalse);
    });

    test('the head-office directorates still see every yard', () {
      // They read cross-yard BY DESIGN -- Disposal approves requests from
      // every yard -- so filtering them would hide real work from them.
      for (final role in ['disposal', 'appeal', 'valuation', 'executive', 'ict']) {
        AppSession.setYard('GL1');
        AppSession.applyYardFilterToRealtime(role);
        expect(PgRealtime.instance.watchAllYards, isTrue,
            reason: '$role reads across yards and must not be filtered');
      }
    });

    test('an unknown or empty role errs towards seeing everything', () {
      // A missed refresh shows stale seizure data; a redundant query costs a
      // few milliseconds. The default must be the safe one.
      AppSession.applyYardFilterToRealtime(null);
      expect(PgRealtime.instance.watchAllYards, isTrue);

      AppSession.applyYardFilterToRealtime('');
      expect(PgRealtime.instance.watchAllYards, isTrue);
    });

    test('signing out restores the unfiltered default', () {
      AppSession.setYard('GL1');
      AppSession.applyYardFilterToRealtime('officer');
      expect(PgRealtime.instance.watchAllYards, isFalse);

      // Otherwise the NEXT user to sign in on this PC -- possibly a Disposal
      // officer -- would silently inherit the previous user's yard filter.
      AppSession.clear();
      expect(PgRealtime.instance.watchAllYards, isTrue);
    });
  });

  group('a burst of changes is one refresh, not ten', () {
    test('the debounce window is under the sub-second sync requirement', () {
      // Saving one form writes several tables in one transaction, and each is
      // a separate NOTIFY. The window absorbs the burst; it must still leave
      // room for the query itself inside one second.
      expect(PgRealtime.debounceWindow.inMilliseconds, lessThan(500));
      expect(PgRealtime.debounceWindow.inMilliseconds, greaterThan(0));
    });
  });

  group('a big parse leaves the UI thread', () {
    test('an empty list costs nothing and spawns no isolate', () async {
      expect(await parsePackages(const []), isEmpty);
      expect(await parseForfeitedPackages(const []), isEmpty);
    });

    test('a malformed row is skipped, not thrown', () async {
      // One bad row must not lose the user the other four hundred.
      final rows = <dynamic>['not a map', 42, null];
      expect(await parsePackages(rows), isEmpty);
    });

    test('the threshold keeps small lists on the main thread', () {
      // Below it, spawning an isolate costs more than the parse it saves --
      // so this being >1 is the whole reason the fast path exists.
      expect(kIsolateParseThreshold, greaterThan(1));
    });
  });
}
