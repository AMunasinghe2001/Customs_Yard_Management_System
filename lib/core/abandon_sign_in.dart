import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'supabase_client.dart';

/// Ends a sign-in that was started but never finished.
///
/// ⚠️ The password-expiry stage runs INSIDE a live session. `signInWithPassword`
/// has already succeeded by the time the officer is asked to set a new
/// password — that is what makes the change possible at all (see migration
/// 018: an expired session may do nothing else, but `auth.change_password`
/// takes the user id as an argument and never asks `auth.uid()`).
///
/// So walking away from that stage — the back arrow, or landing back on the
/// portal chooser — left `supabase.auth.currentUser` set and
/// `currentProfileProvider` populated. The router's redirect then saw a
/// signed-in user on a public route and sent them **straight to the
/// dashboard**, with no password ever entered and the 90-day rule bypassed.
///
/// Any exit from a half-finished sign-in has to end the session. Signing out
/// also drops the ProviderScope (core/session_reset.dart), so nothing of the
/// abandoned attempt is left in memory either.
///
/// Safe to call when nobody is signed in: it checks first, so an ordinary back
/// press from an untouched login form costs nothing.
Future<void> abandonSignIn(WidgetRef ref) async {
  if (supabase.auth.currentUser == null &&
      ref.read(currentProfileProvider) == null) {
    return;
  }
  try {
    await ref.read(authServiceProvider).signOut();
  } catch (_) {
    // A failed sign-out must NOT leave the session usable. The local profile
    // is cleared below either way, and the server expires it on its own.
  }
  ref.read(currentProfileProvider.notifier).state = null;
}
