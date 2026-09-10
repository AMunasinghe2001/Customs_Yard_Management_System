import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Bumped when a session ends, to throw away every cached provider with it.
///
/// ⚠️ This exists because signing out does NOT empty Riverpod's cache.
/// A `FutureProvider` holds its value for the life of its container, and none
/// of the ~100 data providers in `providers.dart` are `autoDispose`. So the
/// rows fetched for one officer stayed in memory after they left, and the
/// next person to sign in rendered them: a GL1 officer's packages, warehouses
/// and disposition rows appeared under a GL2 officer's name, on every page
/// that had already been visited. The database was scoping correctly the
/// whole time — the stale data never came from a query, it came from memory,
/// which is why a psql session and a database-level test both reported the
/// boundary as sound.
///
/// Invalidating providers one by one is not a fix: there are around a hundred,
/// and the day someone adds the hundred-and-first without touching the list,
/// the leak is silently back. Rebuilding the `ProviderScope` drops the whole
/// container at once, so a new session starts with nothing carried over — by
/// construction, not by bookkeeping.
final ValueNotifier<int> sessionEpoch = ValueNotifier<int>(0);

/// Ends the current session's cache. Call from sign-out, never from a failed
/// sign-in attempt (those never established a session, and resetting under
/// them would discard the error message the user needs to read).
void clearCachedSessionData() {
  // ⚠️ Next frame, not now. Callers typically have a couple of statements
  // left that still touch the live container — clearing the profile,
  // navigating away — and disposing it underneath them would throw.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    sessionEpoch.value++;
  });
}
