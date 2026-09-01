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
