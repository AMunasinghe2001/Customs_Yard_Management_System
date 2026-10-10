import 'package:flutter_test/flutter_test.dart';
import 'package:cus_yard_management/models/models.dart';

ProfileModel _p(Duration sincePasswordChange) => ProfileModel(
      id: 'u1',
      fullName: 'Disposal Directorate (DC)',
      username: 'dc',
      badgeNumber: null,
      role: 'disposal',
      yard: null,
      isActive: true,
      createdAt: DateTime.now().subtract(sincePasswordChange),
      passwordUpdatedAt: DateTime.now().subtract(sincePasswordChange),
    );

void main() {
  test('16 hours PAST 90 days is expired', () {
    final p = _p(const Duration(days: 90, hours: 16));
    expect(p.isPasswordExpired, isTrue,
        reason: 'this is the live Disposal DC account: -0.676 days');
    expect(p.daysUntilPasswordExpiry, lessThan(0));
  });

  test('16 hours BEFORE 90 days is not expired', () {
    final p = _p(const Duration(days: 89, hours: 8));
    expect(p.isPasswordExpired, isFalse);
    expect(p.isPasswordExpiringSoon, isTrue);
  });

  test('the two states are distinguishable', () {
    final past = _p(const Duration(days: 90, hours: 16));
    final before = _p(const Duration(days: 89, hours: 8));
    expect(past.isPasswordExpired == before.isPasswordExpired, isFalse,
        reason: 'inDays truncation made both report 0 days and not-expired');
  });

  test('exactly at the boundary counts as expired', () {
    final p = _p(const Duration(days: 90));
    expect(p.isPasswordExpired, isTrue);
  });
}
