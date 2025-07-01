import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEService {
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  // Service and Characteristic UUIDs for payment transactions
  static const String serviceUuid = "12345678-1234-1234-1234-123456789abc";
  static const String characteristicUuid = "87654321-4321-4321-4321-cba987654321";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _characteristicSubscription;

  final StreamController<List<BluetoothDevice>> _devicesController = 
      StreamController<List<BluetoothDevice>>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _connectionStatusController = 
      StreamController<String>.broadcast();

  List<BluetoothDevice> _discoveredDevices = [];

  // Getters for streams
  Stream<List<BluetoothDevice>> get devicesStream => _devicesController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<String> get connectionStatusStream => _connectionStatusController.stream;

  // Check if Bluetooth is available and enabled
  Future<bool> isBluetoothAvailable() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return false;
      
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('Error checking Bluetooth availability: $e');
      return false;
    }
  }

  // Start scanning for nearby devices
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      _discoveredDevices.clear();
      _devicesController.add(_discoveredDevices);

      // Stop any existing scan
      await FlutterBluePlus.stopScan();

      // Start scanning
      await FlutterBluePlus.startScan(timeout: timeout);

      // Listen for scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (!_discoveredDevices.any((device) => device.id == result.device.id)) {
            _discoveredDevices.add(result.device);
            _devicesController.add(List.from(_discoveredDevices));
          }
        }
      });

      _connectionStatusController.add('Scanning for devices...');
    } catch (e) {
      debugPrint('Error starting scan: $e');
      _connectionStatusController.add('Error: Failed to start scanning');
    }
  }

  // Stop scanning
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _connectionStatusController.add('Scan stopped');
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }
  }

  // Connect to a specific device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _connectionStatusController.add('Connecting to ${device.name}...');
      
      await device.connect(timeout: const Duration(seconds: 15));
      _connectedDevice = device;

      // Discover services
      final services = await device.discoverServices();
      
      // Find our payment service and characteristic
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write || characteristic.properties.read) {
            _characteristic = characteristic;
            
            // Enable notifications if supported
            if (characteristic.properties.notify) {
              await characteristic.setNotifyValue(true);
              _characteristicSubscription = characteristic.value.listen(_onDataReceived);
            }
            break;
          }
        }
        if (_characteristic != null) break;
      }

      _connectionStatusController.add('Connected to ${device.name}');
      return true;
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      _connectionStatusController.add('Failed to connect to ${device.name}');
      return false;
    }
  }

  // Disconnect from current device
  Future<void> disconnect() async {
    try {
      await _characteristicSubscription?.cancel();
      await _connectedDevice?.disconnect();
      _connectedDevice = null;
      _characteristic = null;
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
    if (_characteristic == null) {
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

      final jsonData = jsonEncode(paymentData);
      final bytes = utf8.encode(jsonData);
      
      // Split data into chunks if too large (BLE has MTU limitations)
      await _sendDataInChunks(bytes);
      
      _connectionStatusController.add('Payment request sent');
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
    if (_characteristic == null) {
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

      final jsonData = jsonEncode(responseData);
      final bytes = utf8.encode(jsonData);
      
      await _sendDataInChunks(bytes);
      
      _connectionStatusController.add('Payment response sent');
      return true;
    } catch (e) {
      debugPrint('Error sending payment response: $e');
      _connectionStatusController.add('Error: Failed to send payment response');
      return false;
    }
  }

  // Send data in chunks to handle MTU limitations
  Future<void> _sendDataInChunks(List<int> data) async {
    const int chunkSize = 20; // Conservative chunk size for BLE
    
    for (int i = 0; i < data.length; i += chunkSize) {
      final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
      final chunk = data.sublist(i, end);
      
      await _characteristic!.write(Uint8List.fromList(chunk), withoutResponse: false);
      
      // Small delay between chunks
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  // Handle received data
  void _onDataReceived(List<int> data) {
    try {
      final message = utf8.decode(data);
      final Map<String, dynamic> parsedMessage = jsonDecode(message);
      
      _messageController.add(parsedMessage);
      
      // Log received message type
      final messageType = parsedMessage['type'] ?? 'unknown';
      _connectionStatusController.add('Received: $messageType');
    } catch (e) {
      debugPrint('Error parsing received data: $e');
    }
  }

  // Generate unique transaction ID
  String _generateTransactionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'TXN_${timestamp}_$random';
  }

  // Get connection status
  bool get isConnected => _connectedDevice != null;
  
  String get connectedDeviceName => _connectedDevice?.name ?? 'Unknown Device';

  // Simulate connection for demo purposes
  void simulateConnection(String deviceName) {
    _connectedDevice = BluetoothDevice(
      remoteId: DeviceIdentifier('00:11:22:33:44:55'),
    );
    _connectionStatusController.add('Connected to $deviceName (Demo)');
  }

  // Dispose resources
  void dispose() {
    _scanSubscription?.cancel();
    _characteristicSubscription?.cancel();
    _devicesController.close();
    _messageController.close();
    _connectionStatusController.close();
  }
}

