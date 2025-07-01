import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/secure_storage.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  String? _error;
  bool _loading = false;

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _loading = true);

      final stored = await SecureStorage.getUser();
      final enteredPhone = phoneController.text.trim();
      final enteredPassword = passwordController.text.trim();
      final enteredHash = sha256.convert(utf8.encode(enteredPassword)).toString();

      final storedPhone = stored['phone'];
      final storedHash = stored['password_hash'];

      if (storedPhone == null || storedHash == null) {
        print("⚠️ SecureStorage missing offline login data.");
        print("Stored data: $stored");
      }

      if (storedPhone != null && storedHash != null &&
          storedPhone == enteredPhone && storedHash == enteredHash) {
        Navigator.of(context).pushReplacementNamed('/home');
        setState(() => _loading = false);
        return;
      }

      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        setState(() {
          _error = 'No internet connection and no local account found.';
          _loading = false;
        });
        return;
      }

      final onlineLoginSuccess = await AuthService.login(
        phone: enteredPhone,
        password: enteredPassword,
      );

      if (onlineLoginSuccess) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        setState(() => _error = 'Login failed. Wrong phone, password, or network error.');
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                validator: (v) => v!.isEmpty ? 'Enter phone' : null,
              ),
              TextFormField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => v!.isEmpty ? 'Enter password' : null,
              ),
              const SizedBox(height: 20),
              _loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text('Login'),
                    ),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/signup'),
                child: const Text("Don't have an account? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}