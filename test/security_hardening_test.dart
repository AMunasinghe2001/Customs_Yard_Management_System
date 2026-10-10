import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/core/security_policy.dart';

void main() {
  group('LoginSecurityPolicy', () {
    test('locks an account after the threshold is reached', () {
      final now = DateTime(2026, 1, 10, 12, 0, 0);
      final lockUntil = LoginSecurityPolicy.lockedUntilForAttempts(
        failedAttempts: 5,
        now: now,
      );

      expect(lockUntil, equals(now.add(const Duration(minutes: 15))));
      expect(
        LoginSecurityPolicy.isLockedOut(
          lockedUntil: lockUntil,
          now: now.add(const Duration(minutes: 5)),
        ),
        isTrue,
      );
    });

    test('allows a lock to expire naturally', () {
      final now = DateTime(2026, 1, 10, 12, 0, 0);
      final lockUntil = now.add(const Duration(minutes: 15));

      expect(
        LoginSecurityPolicy.isLockedOut(
          lockedUntil: lockUntil,
          now: now.add(const Duration(minutes: 16)),
        ),
        isFalse,
      );
    });
  });

  group('SessionSecurityPolicy', () {
    test('marks inactive sessions as expired once the timeout is reached', () {
      final now = DateTime(2026, 1, 10, 12, 0, 0);
      final lastActivity = now.subtract(const Duration(minutes: 31));

      expect(
        SessionSecurityPolicy.isExpired(
          lastActivityAt: lastActivity,
          now: now,
        ),
        isTrue,
      );
    });

    test('keeps a fresh session active', () {
      final now = DateTime(2026, 1, 10, 12, 0, 0);
      final lastActivity = now.subtract(const Duration(minutes: 5));

      expect(
        SessionSecurityPolicy.isExpired(
          lastActivityAt: lastActivity,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
