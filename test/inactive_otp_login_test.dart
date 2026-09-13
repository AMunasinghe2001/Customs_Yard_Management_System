import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an inactive directorate account is rejected before it receives an OTP',
      () {
    final service = File('lib/services/services.dart').readAsStringSync();
    final start = service.indexOf('Future<String> startOtpLogin');
    final finish = service.indexOf('Future<ProfileModel?> finishOtpLogin');
    final body = service.substring(start, finish);

    expect(body, contains(".select('role, is_active')"));
    final inactive = body.indexOf("throw Exception('account_deactivated')");
    final send = body.indexOf('.sendCode(');
    expect(inactive, greaterThan(-1));
    expect(send, greaterThan(inactive));
  });
}
