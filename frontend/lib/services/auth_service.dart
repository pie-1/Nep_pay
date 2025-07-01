import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'secure_storage.dart';

class AuthService {
  static const String baseUrl = 'http://10.200.10.199:8000/api/user/';

  /// Sign up a new user and store credentials securely.
  static Future<bool> signup({
    required String name,
    required String phone,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'phone': phone, 'password': password}),
    );

    if (response.statusCode == 201) {
      // Auto-login after signup to get tokens
      final loginResponse = await http.post(
        Uri.parse('${baseUrl}login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'password': password}),
      );

      if (loginResponse.statusCode == 200) {
        final tokens = jsonDecode(loginResponse.body);
        final passwordHash = sha256.convert(utf8.encode(password)).toString();

        await SecureStorage.saveUser(
          name: name,
          phone: phone,
          passwordHash: passwordHash,
          accessToken: tokens['access'],
          refreshToken: tokens['refresh'],
        );
        print(await SecureStorage.getUser()); // <-- Add this line for debugging
        return true;
      }
    }
    return false;
  }

  /// Login user online and store credentials securely.
  static Future<bool> login({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${baseUrl}login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'password': password}),
      ).timeout(const Duration(seconds: 7)); // <-- Add timeout here

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final passwordHash = sha256.convert(utf8.encode(password)).toString();

        await SecureStorage.saveUser(
          name: data['name'] ?? 'Anonymous',
          phone: phone,
          passwordHash: passwordHash,
          accessToken: data['access'],
          refreshToken: data['refresh'],
        );
        return true;
      }
      return false;
    } catch (e) {
      // Timeout or network error
      return false;
    }
  }
}