import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static final _storage = FlutterSecureStorage();

  static Future<void> saveUser({
    required String name,
    required String phone,
    required String passwordHash,
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: 'name', value: name);
    await _storage.write(key: 'phone', value: phone);
    await _storage.write(key: 'password_hash', value: passwordHash);
    await _storage.write(key: 'jwt', value: accessToken);
    await _storage.write(key: 'refresh', value: refreshToken);
  }

  static Future<Map<String, String>> getUser() async {
    return await _storage.readAll();
  }

  static Future<void> clear() async {
    await _storage.deleteAll();
  }
}
