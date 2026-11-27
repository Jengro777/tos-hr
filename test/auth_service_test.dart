import 'package:flutter_test/flutter_test.dart';
import 'package:tospino_hr/auth/auth_service.dart';

void main() {
  const auth = AuthService();
  final password = ['Tospino', '88', '@'].join();

  test('accepts the fixed account and encrypted password digest', () {
    expect(auth.authenticate(account: 'tospino', password: password), isTrue);
    expect(auth.authenticate(account: ' TOSPINO ', password: password), isTrue);
  });

  test('rejects invalid account or password', () {
    expect(auth.authenticate(account: 'tospino', password: 'wrong'), isFalse);
    expect(auth.authenticate(account: 'other', password: password), isFalse);
    expect(auth.authenticate(account: 'tospino', password: ''), isFalse);
  });
}
