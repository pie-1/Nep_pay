import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TransactionQueue {
  static const String _key = 'offline_transactions';

  static Future<void> queue(Map<String, dynamic> transaction) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? [];
    existing.add(jsonEncode(transaction));
    await prefs.setStringList(_key, existing);
  }

  static Future<List<Map<String, dynamic>>> getQueued() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_key) ?? [];
    return stored.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }

  static Future<void> update(int index, Map<String, dynamic> transaction) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? [];
    if (index >= 0 && index < existing.length) {
      existing[index] = jsonEncode(transaction);
      await prefs.setStringList(_key, existing);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}



