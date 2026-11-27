import 'dart:convert';

import 'package:crypto/crypto.dart';

class AuthService {
  const AuthService();

  static const _account = 'tospino';
  static const _salt = 'tospino-hr:v1:9e0c88b2c5';
  static const _passwordDigest =
      '6422e94b6b2b957463dee53446bff1faacf2125c51e02b4e1fa0d599e4b2762e';

  bool authenticate({required String account, required String password}) {
    final normalizedAccount = account.trim().toLowerCase();
    if (normalizedAccount != _account || password.isEmpty) {
      return false;
    }
    final candidate = sha256
        .convert(utf8.encode('$_salt:$password'))
        .toString();
    return _constantTimeEquals(candidate, _passwordDigest);
  }

  bool _constantTimeEquals(String left, String right) {
    final leftUnits = left.codeUnits;
    final rightUnits = right.codeUnits;
    var difference = leftUnits.length ^ rightUnits.length;
    final length = leftUnits.length > rightUnits.length
        ? leftUnits.length
        : rightUnits.length;
    for (var index = 0; index < length; index++) {
      final a = index < leftUnits.length ? leftUnits[index] : 0;
      final b = index < rightUnits.length ? rightUnits[index] : 0;
      difference |= a ^ b;
    }
    return difference == 0;
  }
}
