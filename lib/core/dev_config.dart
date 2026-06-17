/// ⚠️ DEVELOPMENT / TESTING TOGGLES — flip back before shipping.
///
/// When [kDevSkipOtp] is true, the OTP-gated portals (Central Disposal,
/// Valuation, Appeal) sign in with the password ONLY — the emailed one-time
/// code step is skipped. The password is still verified against Supabase, so
/// this is a convenience for the testing period, not an auth removal.
///
/// ➜ To re-enable OTP once testing is over: set this to `false` (one line).
const bool kDevSkipOtp = true;
