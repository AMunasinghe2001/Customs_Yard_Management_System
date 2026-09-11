class LoginSecurityPolicy {
  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);

  static DateTime lockedUntilForAttempts({
    required int failedAttempts,
    required DateTime now,
  }) {
    if (failedAttempts < maxFailedAttempts) {
      return now;
    }
    return now.add(lockoutDuration);
  }

  static bool isLockedOut({
    required DateTime? lockedUntil,
    required DateTime now,
  }) {
    if (lockedUntil == null) return false;
    return lockedUntil.isAfter(now);
  }
}

class SessionSecurityPolicy {
  static const Duration sessionTimeout = Duration(minutes: 30);

  static bool isExpired({
    required DateTime? lastActivityAt,
    required DateTime now,
  }) {
    if (lastActivityAt == null) return true;
    return now.difference(lastActivityAt) > sessionTimeout;
  }
}

/// Password strength, mirrored from `public.password_policy_violation` in
/// postgres/52_user_security_policies.sql.
///
/// ⚠️ This copy exists so the person typing sees the rule immediately. It is
/// NOT the control: the database refuses a weak password whatever the client
/// believes, because `auth.sign_up` and `auth.change_password` are reachable
/// without going through any screen. When the two disagree, the SQL wins —
/// so if you change a rule here, change it there in the same commit.
///
/// Before this, 14 screens each carried their own `length < 8` check and one
/// still allowed 6, while the server accepted anything over 5. The weakest
/// rule anywhere is the one that actually applied.
/// One password requirement: what to show, and how to test it.
class PasswordRule {
  final String label;
  final bool Function(String) isMet;
  const PasswordRule({required this.label, required this.isMet});
}

class PasswordPolicy {
  PasswordPolicy._();

  static const int minLength = 12;

  /// The longest password a person will actually type at a shared desk.
  ///
  /// ⚠️ 24, not bcrypt's 72-byte limit and not the 128 this used to be.
  /// Those are ceilings on what the ALGORITHM can hash, which is a different
  /// question from what an officer can be asked to enter correctly twice on
  /// every sign-in. A limit nobody reaches is not a limit; it just made the
  /// rule read as noise.
  ///
  /// Kept at 24 rather than 20 so a three-word passphrase still fits —
  /// passphrases are the easiest strong passwords to remember, and a 20-char
  /// cap quietly rules them out.
  ///
  /// ⚠️ `password_policy_violation` in PostgreSQL enforces the same number.
  /// Changing one without the other is how the form comes to promise what
  /// the server refuses.
  static const int maxLength = 24;

  /// Words a dictionary attack tries first. Not a breach list — just the ones
  /// that cost nothing to exclude.
  static const List<String> commonWords = [
    'password', 'passw0rd', 'welcome', 'customs',
    'qwerty', 'admin123', 'letmein', '12345678',
  ];

  /// Why [password] is unacceptable, or null when it passes.
  ///
  /// Returns the FIRST failure only, so the message names one fixable thing
  /// rather than a wall of rules.
  static String? violation(String? password) {
    final p = password ?? '';
    if (p.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    if (p.length > maxLength) {
      return 'Password must be at most $maxLength characters.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(p)) {
      return 'Password must contain an uppercase letter.';
    }
    if (!RegExp(r'[a-z]').hasMatch(p)) {
      return 'Password must contain a lowercase letter.';
    }
    if (!RegExp(r'[0-9]').hasMatch(p)) {
      return 'Password must contain a number.';
    }
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(p)) {
      return 'Password must contain a special character.';
    }
    final lower = p.toLowerCase();
    if (commonWords.any(lower.contains)) {
      return 'Password contains a commonly used word.';
    }
    return null;
  }

  static bool isAcceptable(String? password) => violation(password) == null;

  /// Every rule, each with a label and a test.
  ///
  /// ⚠️ ONE source for the checklist a user reads, the bar under the field
  /// and the message on failure. The hint under four login screens said
  /// "Minimum 8 characters" while [violation] rejected anything under 12,
  /// so the form told the officer to do something it would then refuse —
  /// which is what a second, hand-written copy of a rule always ends up
  /// doing.
  static List<PasswordRule> get rules => [
        PasswordRule(
          // ⚠️ Both ends in ONE rule, so going past the ceiling turns the
          // same line (and the bar) back to red instead of silently staying
          // green while the form quietly rejects the password.
          //
          // 128 is not a design choice — `password_policy_violation` in the
          // database enforces exactly 12..128, and the two numbers must
          // match or the form promises what the server refuses.
          label: 'Between $minLength and $maxLength characters',
          isMet: (p) => p.length >= minLength && p.length <= maxLength,
        ),
        PasswordRule(
          label: 'An uppercase letter (A-Z)',
          isMet: (p) => RegExp(r'[A-Z]').hasMatch(p),
        ),
        PasswordRule(
          label: 'A lowercase letter (a-z)',
          isMet: (p) => RegExp(r'[a-z]').hasMatch(p),
        ),
        PasswordRule(
          label: 'A number (0-9)',
          isMet: (p) => RegExp(r'[0-9]').hasMatch(p),
        ),
        PasswordRule(
          label: r'A symbol (@ # % ! & ...)',
          isMet: (p) => RegExp(r'[^A-Za-z0-9]').hasMatch(p),
        ),
        PasswordRule(
          label: 'No common word (password, qwerty, ...)',
          isMet: (p) {
            if (p.isEmpty) return false;
            final lower = p.toLowerCase();
            return !commonWords.any(lower.contains);
          },
        ),
      ];

  /// How many of [rules] this password satisfies, 0..rules.length.
  static int metCount(String password) =>
      rules.where((r) => r.isMet(password)).length;

  /// True once every rule passes — the same answer as [isAcceptable], but
  /// derived from the list the user can see, so the bar filling completely
  /// and the form accepting can never disagree.
  static bool allRulesMet(String password) =>
      metCount(password) == rules.length;

  /// A form-field validator: `validator: PasswordPolicy.validate`.
  static String? validate(String? value) => violation(value);

  /// 0–4, for a strength meter. Deliberately not the pass/fail rule —
  /// [violation] is.
  static int strength(String password) {
    var score = 0;
    if (password.length >= minLength) score++;
    if (password.length >= 16) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      score++;
    }
    return score;
  }
}

/// The 90-day rotation rule, kept beside the strength rule.
///
/// The per-profile answers live on [ProfileModel] (isPasswordExpired,
/// isPasswordExpiringSoon); these are the numbers both it and
/// `public.password_age_status` are built from.
class PasswordRotationPolicy {
  PasswordRotationPolicy._();

  static const int maxAgeDays = 90;

  /// Warn during the last week. ⚠️ Must match the `83 days` in
  /// password_age_status, or the app and the server warn on different days.
  static const int warnWithinDays = 7;
}
