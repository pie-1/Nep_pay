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
  StreamSubscription? _connectionStateSubscription;

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
      if (!isSupported) {
        _connectionStatusController.add('Bluetooth not supported on this device');
        return false;
      }
      
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _connectionStatusController.add('Please enable Bluetooth in device settings');
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('Error checking Bluetooth availability: $e');
      _connectionStatusController.add('Error checking Bluetooth: $e');
      return false;
    }
  }

  // Start scanning for nearby devices
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    try {
      // Check if Bluetooth is available first
      final isAvailable = await isBluetoothAvailable();
      if (!isAvailable) return;

      _discoveredDevices.clear();
      _devicesController.add(_discoveredDevices);

      // Stop any existing scan
      await FlutterBluePlus.stopScan();

      _connectionStatusController.add('Scanning for Bluetooth devices...');

      // Start scanning for all devices with extended timeout
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );

      // Listen for scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          final device = result.device;
          
          // Only add devices that aren't already in the list
          if (!_discoveredDevices.any((d) => d.remoteId == device.remoteId)) {
            _discoveredDevices.add(device);
            _devicesController.add(List.from(_discoveredDevices));
            
            final deviceName = getDeviceName(device);
            debugPrint('Found device: $deviceName (${device.remoteId})');
          }
        }
      });

      // Wait for scan to complete
      await Future.delayed(timeout);
      await stopScan();
      
      if (_discoveredDevices.isEmpty) {
        _connectionStatusController.add('No devices found. Make sure nearby devices are discoverable and Bluetooth is enabled.');
      } else {
        _connectionStatusController.add('Found ${_discoveredDevices.length} device(s). Tap on a device to connect.');
      }
    } catch (e) {
      debugPrint('Error starting scan: $e');
      _connectionStatusController.add('Error scanning: $e');
    }
  }

  // Stop scanning
  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }
  }

  // Connect to a specific device
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      final deviceName = getDeviceName(device);
      _connectionStatusController.add('Connecting to $deviceName...');
      
      // Disconnect from any existing device
      await disconnect();

      // Connect to the new device with extended timeout
      await device.connect(
        timeout: const Duration(seconds: 20),
        autoConnect: false,
      );
      
      _connectedDevice = device;

      // Listen for connection state changes
      _connectionStateSubscription = device.connectionState.listen((state) {
        debugPrint('Connection state changed: $state');
        if (state == BluetoothConnectionState.disconnected) {
          _connectionStatusController.add('Disconnected from $deviceName');
          _connectedDevice = null;
          _characteristic = null;
        }
      });

      // Discover services
      _connectionStatusController.add('Discovering services on $deviceName...');
      final services = await device.discoverServices();
      
      debugPrint('Found ${services.length} services on device');

      // Try to find our custom service first, otherwise use any available service
      BluetoothService? targetService;
      BluetoothCharacteristic? targetCharacteristic;

      // Look for our custom service
      for (var service in services) {
        debugPrint('Service: ${service.uuid}');
        if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
          targetService = service;
          debugPrint('Found custom payment service');
          break;
        }
      }

      // If custom service not found, use the first available service with writable characteristics
      if (targetService == null) {
        for (var service in services) {
          for (var characteristic in service.characteristics) {
            if (characteristic.properties.write || 
                characteristic.properties.writeWithoutResponse) {
              targetService = service;
              debugPrint('Using service: ${service.uuid} for communication');
              break;
            }
          }
          if (targetService != null) break;
        }
      }

      if (targetService != null) {
        // Look for our custom characteristic first
        for (var characteristic in targetService.characteristics) {
          debugPrint('Characteristic: ${characteristic.uuid}, Properties: ${characteristic.properties}');
          if (characteristic.uuid.toString().toLowerCase() == characteristicUuid.toLowerCase()) {
            targetCharacteristic = characteristic;
            debugPrint('Found custom payment characteristic');
            break;
          }
        }

        // If custom characteristic not found, use first available writable characteristic
        if (targetCharacteristic == null) {
          for (var characteristic in targetService.characteristics) {
            if (characteristic.properties.write || 
                characteristic.properties.writeWithoutResponse ||
                characteristic.properties.notify ||
                characteristic.properties.read) {
              targetCharacteristic = characteristic;
              debugPrint('Using characteristic: ${characteristic.uuid} for communication');
              break;
            }
          }
        }
      }

      if (targetCharacteristic != null) {
        _characteristic = targetCharacteristic;
        
        // Enable notifications if supported
        if (targetCharacteristic.properties.notify) {
          try {
            await targetCharacteristic.setNotifyValue(true);
            _characteristicSubscription = targetCharacteristic.lastValueStream.listen(_onDataReceived);
            debugPrint('Notifications enabled for characteristic: ${targetCharacteristic.uuid}');
          } catch (e) {
            debugPrint('Could not enable notifications: $e');
          }
        }

        _connectionStatusController.add('Successfully connected to $deviceName');
        return true;
      } else {
        _connectionStatusController.add('No suitable characteristics found on $deviceName');
        await device.disconnect();
        return false;
      }
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      _connectionStatusController.add('Failed to connect: ${e.toString()}');
      return false;
    }
  }

  // Disconnect from current device
  Future<void> disconnect() async {
    try {
      await _characteristicSubscription?.cancel();
      await _connectionStateSubscription?.cancel();
      
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
      }
      
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
    if (_characteristic == null || _connectedDevice == null) {
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
      
      debugPrint('Sending payment request: $jsonData');
      
      // Send data in chunks if needed
      await _sendDataInChunks(bytes);
      
      _connectionStatusController.add('Payment request sent successfully');
      
      // Simulate automatic acceptance for demo purposes since we're connecting to regular devices
      // In a real BinaNet Pay implementation, both devices would have the app installed
      await Future.delayed(const Duration(seconds: 3));
      _messageController.add({
        'type': 'payment_response',
        'transaction_id': paymentData['transaction_id'],
        'accepted': true,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      return true;
    } catch (e) {
      debugPrint('Error sending payment request: $e');
      _connectionStatusController.add('Error: Failed to send payment request - $e');
      return false;
    }
  }

  // Send payment response (accept/reject)
  Future<bool> sendPaymentResponse({
    required String transactionId,
    required bool accepted,
    String? reason,
  }) async {
    if (_characteristic == null || _connectedDevice == null) {
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
      _connectionStatusController.add('Error: Failed to send payment response - $e');
      return false;
    }
  }

  // Send data in chunks to handle MTU limitations
  Future<void> _sendDataInChunks(List<int> data) async {
    if (_characteristic == null) return;

    try {
      // Get MTU size, default to 20 if not available
      int mtu = 20;
      try {
        if (_connectedDevice != null) {
          mtu = await _connectedDevice!.mtu.first;
          mtu = mtu - 3; // Account for ATT overhead
          debugPrint('Device MTU: $mtu');
        }
      } catch (e) {
        debugPrint('Could not get MTU, using default: $e');
      }

      final chunkSize = mtu.clamp(20, 512);
      debugPrint('Sending ${data.length} bytes in chunks of $chunkSize');
      
      for (int i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
        final chunk = data.sublist(i, end);
        
        if (_characteristic!.properties.writeWithoutResponse) {
          await _characteristic!.write(Uint8List.fromList(chunk), withoutResponse: true);
        } else if (_characteristic!.properties.write) {
          await _characteristic!.write(Uint8List.fromList(chunk), withoutResponse: false);
        } else {
          throw Exception('Characteristic does not support writing');
        }
        
        // Small delay between chunks
        if (i + chunkSize < data.length) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }
      
      debugPrint('Data sent successfully');
    } catch (e) {
      debugPrint('Error sending data chunks: $e');
      rethrow;
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
      debugPrint('Received message: $parsedMessage');
    } catch (e) {
      debugPrint('Error parsing received data: $e');
      // Try to handle partial data or non-JSON data
      final messageString = String.fromCharCodes(data);
      debugPrint('Raw received data: $messageString');
    }
  }

  // Generate unique transaction ID
  String _generateTransactionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'BT_${timestamp}_$random';
  }

  // Get connection status
  bool get isConnected => _connectedDevice != null;
  
  String get connectedDeviceName {
    if (_connectedDevice == null) return 'Not Connected';
    return getDeviceName(_connectedDevice!);
  }

  // Get device name helper
  String getDeviceName(BluetoothDevice device) {
    // Try platform name first
    final platformName = device.platformName;
    if (platformName.isNotEmpty) return platformName;
    
    // Try advertisement name
    final advName = device.advName;
    if (advName.isNotEmpty) return advName;
    
    // Use MAC address as fallback
    final macAddress = device.remoteId.toString();
    return 'Device ${macAddress.substring(macAddress.length - 8)}';
  }

  // Check if device supports our payment service (for filtering)
  Future<bool> supportsPaymentService(BluetoothDevice device) async {
    try {
      // For now, we'll assume all connectable devices can potentially support payments
      // In a real implementation, you might check for specific service UUIDs in advertisement data
      return true;
    } catch (e) {
      return false;
    }
  }

  // Dispose resources
  void dispose() {
    _scanSubscription?.cancel();
    _characteristicSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _devicesController.close();
    _messageController.close();
    _connectionStatusController.close();
  }
}