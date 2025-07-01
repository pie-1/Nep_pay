import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

class BluetoothDevice {
  final String id;
  final String name;
  final int rssi;
  final bool isConnectable;
  final DateTime lastSeen;

  BluetoothDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.isConnectable = true,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get displayName => name.isNotEmpty ? name : 'Unknown Device';
  
  String get signalStrength {
    if (rssi > -50) return 'Excellent';
    if (rssi > -70) return 'Good';
    if (rssi > -85) return 'Fair';
    return 'Poor';
  }

  IconData get signalIcon {
    if (rssi > -50) return Icons.signal_cellular_4_bar;
    if (rssi > -70) return Icons.signal_cellular_alt;
    if (rssi > -85) return Icons.signal_cellular_alt;
    return Icons.signal_cellular_off;
  }
}

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  BluetoothDevice? _connectedDevice;
  bool _isScanning = false;
  bool _isConnected = false;

  final StreamController<List<BluetoothDevice>> _devicesController = 
      StreamController<List<BluetoothDevice>>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _connectionStatusController = 
      StreamController<String>.broadcast();

  List<BluetoothDevice> _discoveredDevices = [];

  // Mock device database for realistic simulation
  final List<Map<String, String>> _mockDevices = [
    {'id': '00:11:22:33:44:55', 'name': 'OffPay Demo Device'},
    {'id': '11:22:33:44:55:66', 'name': 'Redmi Note 12'},
    {'id': '22:33:44:55:66:77', 'name': 'iPhone 14 Pro'},
    {'id': '33:44:55:66:77:88', 'name': 'Samsung Galaxy S23'},
    {'id': '44:55:66:77:88:99', 'name': 'OnePlus 11'},
    {'id': '55:66:77:88:99:AA', 'name': 'Pixel 7 Pro'},
    {'id': '66:77:88:99:AA:BB', 'name': 'Xiaomi 13'},
    {'id': '77:88:99:AA:BB:CC', 'name': 'Vivo V27'},
    {'id': '88:99:AA:BB:CC:DD', 'name': 'Oppo Find X5'},
    {'id': '99:AA:BB:CC:DD:EE', 'name': 'Realme GT 3'},
  ];

  // Getters for streams
  Stream<List<BluetoothDevice>> get devicesStream => _devicesController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<String> get connectionStatusStream => _connectionStatusController.stream;

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  // Check if Bluetooth is available and enabled
  Future<bool> isBluetoothAvailable() async {
    try {
      // Simulate Bluetooth availability check
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      debugPrint('Error checking Bluetooth availability: $e');
      return false;
    }
  }

  // Start scanning for nearby devices
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_isScanning) return;

    try {
      _isScanning = true;
      _discoveredDevices.clear();
      _devicesController.add(_discoveredDevices);
      _connectionStatusController.add('Scanning for devices...');

      // Simulate progressive device discovery
      final random = Random();
      final shuffledDevices = List.from(_mockDevices)..shuffle();
      
      for (int i = 0; i < shuffledDevices.length; i++) {
        if (!_isScanning) break;
        
        await Future.delayed(Duration(milliseconds: 300 + random.nextInt(700)));
        
        final deviceData = shuffledDevices[i];
        final device = BluetoothDevice(
          id: deviceData['id']!,
          name: deviceData['name']!,
          rssi: -30 - random.nextInt(60), // Random signal strength
          isConnectable: random.nextBool() || deviceData['name']!.contains('OffPay'),
        );

        _discoveredDevices.add(device);
        _devicesController.add(List.from(_discoveredDevices));

        // Stop after finding 5-7 devices for realistic experience
        if (i >= 4 + random.nextInt(3)) break;
      }

      await Future.delayed(const Duration(milliseconds: 500));
      _isScanning = false;
      _connectionStatusController.add(
        _discoveredDevices.isEmpty 
          ? 'No devices found' 
          : 'Found ${_discoveredDevices.length} device(s)'
      );
    } catch (e) {
      _isScanning = false;
      debugPrint('Error starting scan: $e');
      _connectionStatusController.add('Error: Failed to start scanning');
    }
  }

  // Stop scanning
  Future<void> stopScan() async {
    _isScanning = false;
    _connectionStatusController.add('Scan stopped');
  }

  // Connect to a specific device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _connectionStatusController.add('Connecting to ${device.displayName}...');
      
      // Simulate connection process
      await Future.delayed(const Duration(seconds: 2));
      
      // Simulate occasional connection failures for realism
      final random = Random();
      if (random.nextInt(10) < 2 && !device.name.contains('OffPay')) {
        _connectionStatusController.add('Failed to connect to ${device.displayName}');
        return false;
      }

      _connectedDevice = device;
      _isConnected = true;
      _connectionStatusController.add('Connected to ${device.displayName}');
      return true;
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      _connectionStatusController.add('Failed to connect to ${device.displayName}');
      return false;
    }
  }

  // Disconnect from current device
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        _connectionStatusController.add('Disconnecting from ${_connectedDevice!.displayName}...');
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      _connectedDevice = null;
      _isConnected = false;
      _connectionStatusController.add('Disconnected');
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    }
  }

  // Send payment request
  Future<bool> sendPaymentRequest({
    required String senderName,
    required String senderPhone,
    required String receiverName,
    required String receiverPhone,
    required double amount,
    String? description,
  }) async {
    if (!_isConnected || _connectedDevice == null) {
      _connectionStatusController.add('Error: Not connected to any device');
      return false;
    }

    try {
      final paymentData = {
        'type': 'payment_request',
        'sender_name': senderName,
        'sender_phone': senderPhone,
        'receiver_name': receiverName,
        'receiver_phone': receiverPhone,
        'amount': amount,
        'description': description ?? '',
        'timestamp': DateTime.now().toIso8601String(),
        'transaction_id': _generateTransactionId(),
      };

      _connectionStatusController.add('Sending payment request...');
      
      // Simulate sending data
      await Future.delayed(const Duration(seconds: 1));
      
      // Simulate automatic acceptance for demo
      await Future.delayed(const Duration(milliseconds: 500));
      _messageController.add({
        'type': 'payment_response',
        'transaction_id': paymentData['transaction_id'],
        'accepted': true,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      _connectionStatusController.add('Payment request sent successfully');
      return true;
    } catch (e) {
      debugPrint('Error sending payment request: $e');
      _connectionStatusController.add('Error: Failed to send payment request');
      return false;
    }
  }

  // Send payment response (accept/reject)
  Future<bool> sendPaymentResponse({
    required String transactionId,
    required bool accepted,
    String? reason,
  }) async {
    if (!_isConnected || _connectedDevice == null) {
      _connectionStatusController.add('Error: Not connected to any device');
      return false;
    }

    try {
      final responseData = {
        'type': 'payment_response',
        'transaction_id': transactionId,
        'accepted': accepted,
        'reason': reason ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      };

      await Future.delayed(const Duration(milliseconds: 500));
      
      _connectionStatusController.add('Payment response sent');
      return true;
    } catch (e) {
      debugPrint('Error sending payment response: $e');
      _connectionStatusController.add('Error: Failed to send payment response');
      return false;
    }
  }

  // Generate unique transaction ID
  String _generateTransactionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000).toString().padLeft(4, '0');
    return 'TXN_${timestamp}_$random';
  }

  // Simulate receiving a payment request (for receiver mode)
  void simulateIncomingPaymentRequest({
    required String senderName,
    required String senderPhone,
    required double amount,
    String? description,
  }) {
    final paymentData = {
      'type': 'payment_request',
      'sender_name': senderName,
      'sender_phone': senderPhone,
      'amount': amount,
      'description': description ?? '',
      'timestamp': DateTime.now().toIso8601String(),
      'transaction_id': _generateTransactionId(),
    };

    _messageController.add(paymentData);
  }

  // Dispose resources
  void dispose() {
    _devicesController.close();
    _messageController.close();
    _connectionStatusController.close();
  }
}