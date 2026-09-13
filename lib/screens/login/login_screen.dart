import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/secure_credentials.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import '../../core/theme.dart';
import '../../widgets/brand_panel.dart';
import '../../widgets/forgot_password_panel.dart';
import '../../core/db_client.dart';
import '../../core/abandon_sign_in.dart';
import '../../core/providers.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import '../../widgets/auth_back_button.dart';
import '../../widgets/password_expired_stage.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  /// The profile waiting behind an expired password, and the stage that
  /// collects the new one.
  ///
  /// ⚠️ A STAGE in this panel, not a modal. The four directorate portals
  /// already did it this way; a dialog made the same moment in the same flow
  /// look like a different product, and read as an interruption to something
  /// else when it IS the sign-in.
  ProfileModel? _expiredProfile;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final creds = await SecureCredentialStore.load('saved');
    setState(() {
      _emailCtrl.text = creds['email'] as String? ?? '';
      _passwordCtrl.text = creds['password'] as String? ?? '';
      _rememberMe = creds['remember_me'] as bool? ?? false;
    });
  }

  Future<void> _saveCredentials() async {
    await SecureCredentialStore.save(
      'saved',
      emailOrId: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      rememberMe: _rememberMe,
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    ref.read(loginLoadingProvider.notifier).state = true;
    ref.read(loginErrorProvider.notifier).state = null;
    try {
      final profile = await ref.read(authServiceProvider).signInWithIdentifier(
            _emailCtrl.text.trim(),
            _passwordCtrl.text,
          );
      if (profile == null) {
        ref.read(loginErrorProvider.notifier).state =
            'Login failed. Check credentials.';
        return;
      }
      if (!profile.isActive) {
        await supabase.auth.signOut();
        ref.read(loginErrorProvider.notifier).state =
            'Account is disabled. Contact admin.';
        return;
      }
      if (profile.isAdmin) {
        await supabase.auth.signOut();
        ref.read(loginErrorProvider.notifier).state =
            'Admin accounts must use the Admin Sign In.';
        return;
      }
      // ⚠️ An expired password is a dead session at the DATABASE now
      // (migration 018): auth.uid() is null and auth.role() is 'anon', so
      // every page would come back empty. This portal had no password stage
      // at all, and three yard officers are already past 90 days — without
      // this they would sign in to an empty app with no way to fix it.
      // ⚠️ EXPIRING SOON enters the same stage, with Skip offered. The four
      // directorate portals have warned for the last 7 days all along; the
      // yard portals had only the hard stop, so yard staff learned of the
      // rotation on the morning it locked them out.
      if (profile.isPasswordExpired || profile.isPasswordExpiringSoon) {
        ref.read(currentProfileProvider.notifier).state = profile;
        if (!mounted) return;
        setState(() => _expiredProfile = profile);
        ref.read(loginErrorProvider.notifier).state = null;
        return;
      }
      await _saveCredentials();
      ref.read(currentProfileProvider.notifier).state = profile;
      if (mounted) {
        context.showSuccess('Logged in successfully as ${profile.fullName}');
        context.go('/dashboard');
      }
    } catch (e) {
      ref.read(loginErrorProvider.notifier).state =
          _friendlyError(e.toString());
    } finally {
      ref.read(loginLoadingProvider.notifier).state = false;
    }
  }

  String _friendlyError(String raw) {
    final low = raw.toLowerCase();
    if (low.contains('socketexception') ||
        low.contains('retryablefetch') ||
        low.contains('semaphore') ||
        low.contains('failed host lookup') ||
        low.contains('clientexception') ||
        low.contains('failedtoopensocket') ||
        low.contains('timed out')) {
      return 'Network problem — couldn\'t reach the server. Check your internet connection and try again.';
    }
    if (raw.contains('email_not_confirmed')) {
      return 'Email not confirmed. Please check your inbox and confirm your email address first.';
    }
    if (raw.contains('login_locked')) {
      return 'This account is temporarily locked after repeated failed logins. Please try again later.';
    }
    if (raw.contains('Invalid login credentials') ||
        raw.contains('invalid_credentials')) {
      return 'Incorrect username/email or password. Please try again.';
    }
    if (raw.contains('too many requests') ||
        raw.contains('over_email_send_rate_limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (raw.contains('account_deactivated')) {
      return 'Your account has been deactivated. Please contact an administrator.';
    }
    if (raw.contains('account_expired')) {
      return 'Your account has expired (accounts auto-deactivate 8 months after creation). Please contact an administrator.';
    }
    if (raw.contains('session_expired')) {
      return 'Your session has timed out due to inactivity. Please sign in again.';
    }
    // A database fault is not the officer's fault. Telling someone with a
    // correct password to "check your credentials" sends them round the same
    // failing loop; naming the server sends them to whoever can fix it.
    if (low.contains('postgresqlexception') ||
        low.contains('postgresexception') ||
        low.contains('severity.error') ||
        low.contains('infinite recursion detected') ||
        low.contains('policy for relation') ||
        low.contains('connection refused') ||
        low.contains('connection closed')) {
      return 'The server rejected the sign-in because of a database fault, '
          'not your password. Please report this to the ICT Directorate.';
    }
    return 'Sign in failed. Please check your credentials.';
  }

  /// Whether the right-hand panel is showing the reset flow instead of the
  /// sign-in form.
  ///
  /// ⚠️ Not a dialog. Resetting a password is the same act as signing in --
  /// the officer is getting into their account -- so it happens in the same
  /// panel, as the next page of one flow.
  bool _resetting = false;

  /// Shows the reset flow, pre-filled with whatever was already typed.
  void _openForgotPassword() => setState(() => _resetting = true);

  /// Back from the reset flow. On success the officer is left on the sign-in
  /// form with a note to sign in again -- which is exactly where they need
  /// to be.
  void _closeForgotPassword(bool changed) {
    if (!mounted) return;
    setState(() => _resetting = false);
    if (changed) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            const Text('Password changed. Sign in with your new password.'),
        backgroundColor: context.colors.successGreen,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(loginLoadingProvider);
    final error = ref.watch(loginErrorProvider);

    return Scaffold(
      backgroundColor: context.colors.scaffoldBg,
      body: Stack(children: [
        Positioned(
          top: 24,
          right: 24,
          child: IconButton(
            icon: Icon(
              ref.watch(themeModeProvider) == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              color: context.colors.textPrimary,
            ),
            onPressed: () {
              final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
        ),
        Row(children: [
          // Left – branding
          Expanded(
            flex: 5,
            child: BrandPanel(
              accent: context.colors.accentLightBlue,
              deepColor: const Color(0xFF050411),
              badgeLabel: 'SC / DSC / ASC Portal',
              badgeIcon: Icons.person_outline_rounded,
            ),
          ),
          Expanded(
              flex: 4,
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    padding: const EdgeInsets.all(52),
                    child: _resetting
                        ? ForgotPasswordPanel(
                            accent: context.colors.accentLightBlue,
                            initialIdentifier: _emailCtrl.text.trim(),
                            onClose: _closeForgotPassword,
                          )
                        : Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('SC / DSC / ASC Sign In',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium)
                                    .animate()
                                    .fadeIn(duration: 400.ms),
                                const Gap(8),
                                Text(
                                        _expiredProfile != null
                                            ? 'Your password has expired'
                                            : 'Enter your credentials to access the system',
                                        style: TextStyle(
                                            color: context.colors.textSecondary,
                                            fontSize: 14))
                                    .animate()
                                    .fadeIn(delay: 100.ms),
                                const Gap(40),
                                // The expiry step REPLACES the credentials
                                // form: they have already been accepted, and
                                // leaving them on screen would invite the
                                // officer to try them again.
                                if (_expiredProfile != null) ...[
                                  PasswordExpiredStage(
                                    accent: context.colors.primaryGold,
                                    signInRoute: '/login',
                                    expired: _expiredProfile!.isPasswordExpired,
                                    daysLeft: _expiredProfile!
                                        .daysUntilPasswordExpiry,
                                    // Deferring finishes the sign-in exactly
                                    // as a normal one does — the password is
                                    // still valid today, so nothing else
                                    // about the session differs.
                                    onSkip: () async {
                                      await _saveCredentials();
                                      if (!mounted) return;
                                      final p = _expiredProfile!;
                                      setState(() => _expiredProfile = null);
                                      ref
                                          .read(currentProfileProvider.notifier)
                                          .state = p;
                                      if (!mounted) return;
                                      context.showSuccess(
                                          'Logged in successfully as ${p.fullName}');
                                      context.go('/dashboard');
                                    },
                                    // ⚠️ Back to THIS form, not into the app.
                                    // The stage has signed the session out,
                                    // so the officer signs in with the new
                                    // password the ordinary way — which is
                                    // what a password change should feel
                                    // like, and proves the new password
                                    // works while the form is still in front
                                    // of them.
                                    onDone: () {
                                      setState(() {
                                        _expiredProfile = null;
                                        _passwordCtrl.text = '';
                                      });
                                      context.showSuccess(
                                          'Password updated. Sign in with your new password.');
                                    },
                                    onSignOut: () {
                                      // ⚠️ Read BEFORE the setState below
                                      // clears the profile this depends on.
                                      final wasExpired =
                                          _expiredProfile!.isPasswordExpired;
                                      setState(() {
                                        _expiredProfile = null;
                                        _passwordCtrl.text = '';
                                      });
                                      ref
                                              .read(loginErrorProvider.notifier)
                                              .state =
                                          wasExpired
                                              ? 'Your password has expired. Set a new one to sign in.'
                                              : 'Sign in again when you are ready to set a new password.';
                                    },
                                  ),
                                ] else ...[
                                  if (error != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: context.colors.dangerRed
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: context.colors.dangerRed
                                                .withOpacity(0.4)),
                                      ),
                                      child: Row(children: [
                                        Icon(Icons.error_outline,
                                            color: context.colors.dangerRed,
                                            size: 18),
                                        const Gap(10),
                                        Expanded(
                                            child: Text(error,
                                                style: TextStyle(
                                                    color: context
                                                        .colors.dangerRed,
                                                    fontSize: 13))),
                                      ]),
                                    ),
                                    const Gap(20),
                                  ],
                                  TextFormField(
                                    controller: _emailCtrl,
                                    // Enter submits, so the form can be completed from the
                                    // keyboard without reaching for the mouse.
                                    onFieldSubmitted: (_) => _signIn(),
                                    decoration: InputDecoration(
                                      labelText: 'Username or Email',
                                      prefixIcon: Icon(Icons.person_outline,
                                          color: context.colors.textMuted),
                                    ),
                                    keyboardType: TextInputType.text,
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Username or email required'
                                        : null,
                                  )
                                      .animate()
                                      .slideX(
                                          begin: 0.1,
                                          duration: 400.ms,
                                          delay: 200.ms)
                                      .fadeIn(),
                                  const Gap(16),
                                  TextFormField(
                                    controller: _passwordCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: Icon(Icons.lock_outline,
                                          color: context.colors.textMuted),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_off
                                                : Icons.visibility,
                                            color: context.colors.textMuted),
                                        onPressed: () => setState(() =>
                                            _obscurePassword =
                                                !_obscurePassword),
                                      ),
                                    ),
                                    obscureText: _obscurePassword,
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Password required'
                                        : null,
                                    onFieldSubmitted: (_) => _signIn(),
                                  )
                                      .animate()
                                      .slideX(
                                          begin: 0.1,
                                          duration: 400.ms,
                                          delay: 300.ms)
                                      .fadeIn(),
                                  const Gap(12),
                                  Row(children: [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: Checkbox(
                                        value: _rememberMe,
                                        activeColor:
                                            context.colors.accentLightBlue,
                                        onChanged: (v) => setState(
                                            () => _rememberMe = v ?? false),
                                      ),
                                    ),
                                    const Gap(8),
                                    Text('Remember me',
                                        style: TextStyle(
                                            color: context.colors.textSecondary,
                                            fontSize: 13)),
                                    const Spacer(),
                                    // Beside Remember-me: both are things an officer
                                    // reaches for at a sign-in that will not go through.
                                    TextButton(
                                      onPressed: _openForgotPassword,
                                      style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap),
                                      child: Text('Forgot password?',
                                          style: TextStyle(
                                              color: context
                                                  .colors.accentLightBlue,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ]).animate().fadeIn(delay: 350.ms),
                                  const Gap(24),
                                  SizedBox(
                                          height: 54,
                                          child: ElevatedButton(
                                            onPressed:
                                                isLoading ? null : _signIn,
                                            child: isLoading
                                                ? SizedBox(
                                                    width: 22,
                                                    height: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: context
                                                                .colors
                                                                .primaryNavy))
                                                : const Text('Sign In',
                                                    style: TextStyle(
                                                        fontSize: 16)),
                                          ))
                                      .animate()
                                      .slideY(
                                          begin: 0.3,
                                          duration: 400.ms,
                                          delay: 400.ms)
                                      .fadeIn(),
                                  const Gap(24),
                                  Divider(
                                      color: context.colors.borderColor
                                          .withOpacity(0.5)),
                                  const Gap(16),
                                  Center(
                                      child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                        Icon(Icons.info_outline_rounded,
                                            size: 15,
                                            color: context.colors.textMuted),
                                        const Gap(6),
                                        Flexible(
                                          child: Text(
                                              'Yard staff accounts are provisioned by the ICT Directorate.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color:
                                                      context.colors.textMuted,
                                                  fontSize: 13)),
                                        ),
                                      ])).animate().fadeIn(delay: 600.ms),
                                ],
                              ],
                            )),
                  ),
                ),
              )),
        ]),
        Positioned(
          top: 24,
          right: 24,
          child: IconButton(
            icon: Icon(
                ref.watch(themeModeProvider) == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: context.colors.textPrimary),
            onPressed: () {
              final isDark = ref.read(themeModeProvider) == ThemeMode.dark;
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
        ),
        AuthBackButton(
          tooltip: _expiredProfile != null
              ? 'Back to sign in'
              : 'Back to yard access',
          // ⚠️ Step back a STAGE before leaving. The expiry step is a
          // setState stage of this one route, not a route of its own, so
          // there was nothing for the arrow to pop and it fell through to
          // the chooser.
          //
          // Leaving also ENDS the session: that stage runs inside a live one,
          // and walking away used to land on the dashboard with no password
          // entered. See core/abandon_sign_in.dart.
          onPressed: () async {
            await abandonSignIn(ref);
            if (!mounted) return;
            if (_expiredProfile != null) {
              setState(() {
                _expiredProfile = null;
                _passwordCtrl.text = '';
              });
              return;
            }
            if (context.mounted) context.go('/yard-access');
          },
        ),
      ]),
    );
  }
}
