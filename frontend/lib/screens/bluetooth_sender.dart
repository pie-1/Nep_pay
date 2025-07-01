import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';
import '../services/transactions_queue.dart';
import 'payment_confirmation_page.dart';

class BluetoothSenderScreen extends StatefulWidget {
  final String receiverName;
  final String receiverPhone;
  final double amount;
  final String? description;

  const BluetoothSenderScreen({
    super.key,
    required this.receiverName,
    required this.receiverPhone,
    required this.amount,
    this.description,
  });

  @override
  State<BluetoothSenderScreen> createState() => _BluetoothSenderScreenState();
}

class _BluetoothSenderScreenState extends State<BluetoothSenderScreen> with SingleTickerProviderStateMixin {
  final BLEService _bleService = BLEService();
  List<BluetoothDevice> _discoveredDevices = [];
  BluetoothDevice? _selectedDevice;
  String _connectionStatus = 'Initializing...';
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isWaitingResponse = false;
  bool _isPaired = false;
  AnimationController? _animationController;

  // Default demo device for hackathon
  final String _defaultDeviceName = 'OffPay Demo Device';
  final String _defaultDeviceId = '00:11:22:33:44:55';

  // Mock device names for web
  final Map<String, String> _mockDeviceNames = {
    '00:11:22:33:44:55': 'OffPay Demo Device',
    '11:22:33:44:55:66': 'Redmi Note 12',
    '22:33:44:55:66:77': 'AirBud Pro',
    '33:44:55:66:77:88': 'Samsung Galaxy S23',
  };

  StreamSubscription? _devicesSubscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _initializeBluetooth();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _devicesSubscription?.cancel();
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _bleService.stopScan();
    _bleService.disconnect();
    super.dispose();
  }

  Future<void> _initializeBluetooth() async {
    // Web doesn't support full Bluetooth, so simulate device discovery
    setState(() {
      _connectionStatus = 'Simulating Bluetooth for web...';
    });

    // Simulate discovered devices for web
    _devicesSubscription = Stream.value([
      BluetoothDevice(remoteId: DeviceIdentifier('00:11:22:33:44:55')),
      BluetoothDevice(remoteId: DeviceIdentifier('11:22:33:44:55:66')),
      BluetoothDevice(remoteId: DeviceIdentifier('22:33:44:55:66:77')),
      BluetoothDevice(remoteId: DeviceIdentifier('33:44:55:66:77:88')),
    ]).listen((devices) {
      setState(() {
        _discoveredDevices = devices;
      });
    });

    _statusSubscription = Stream.value('Ready to pair').listen((status) {
      setState(() {
        _connectionStatus = status;
      });
    });

    _messageSubscription = _bleService.messageStream.listen((message) {
      _handleIncomingMessage(message);
    });

    _startScan();
  }

  void _handleIncomingMessage(Map<String, dynamic> message) {
    if (message['type'] == 'payment_response') {
      setState(() {
        _isWaitingResponse = false;
      });

      final accepted = message['accepted'] ?? false;
      if (accepted) {
        _onPaymentAccepted(message);
      } else {
        _onPaymentRejected(message);
      }
    }
  }

  Future<void> _onPaymentAccepted(Map<String, dynamic> response) async {
    await TransactionQueue.queue({
      'method': 'P2P-BT',
      'name': widget.receiverName,
      'phone': widget.receiverPhone,
      'amount': widget.amount,
      'description': widget.description ?? '',
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'completed',
      'transaction_id': response['transaction_id'],
      'type': 'sent',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment sent successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _onPaymentRejected(Map<String, dynamic> response) {
    if (mounted) {
      final reason = response['reason'] ?? 'Payment was rejected by the receiver';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
      _selectedDevice = null;
      _isPaired = false;
      _connectionStatus = 'Scanning for devices...';
    });

    // Simulate scan for web
    await Future.delayed(const Duration(seconds: 2));
    setState(() {
      _isScanning = false;
      _connectionStatus = _discoveredDevices.isEmpty ? 'No devices found' : 'Select a device to pair';
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _selectedDevice = device;
      _isPaired = false;
      _connectionStatus = 'Pairing with ${_getDeviceName(device)}...';
    });

    // Simulate pairing for web
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _isConnecting = false;
      _isPaired = true;
      _connectionStatus = 'Paired with ${_getDeviceName(device)}';
    });

    // Simulate payment transfer
    _bleService.simulateConnection(_getDeviceName(device));
    await _bleService.sendPaymentRequest(
      senderName: 'Current User',
      senderPhone: '+1234567890',
      receiverName: widget.receiverName,
      receiverPhone: widget.receiverPhone,
      amount: widget.amount,
      description: widget.description,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment of ₹${widget.amount.toStringAsFixed(2)} sent to ${_getDeviceName(device)}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _getDeviceName(BluetoothDevice device) {
    return _mockDeviceNames[device.remoteId.toString()] ?? 'Unknown Device';
  }

  Future<void> _verifyAndProceed() async {
    if (!_isPaired || _selectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No device paired. Please pair a device first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isWaitingResponse = true;
      _connectionStatus = 'Verifying payment...';
    });

    // Simulate verification for web
    await Future.delayed(const Duration(seconds: 1));
    await _onPaymentAccepted({
      'transaction_id': 'WEB_${DateTime.now().millisecondsSinceEpoch}',
      'accepted': true,
    });

    if (mounted) {
      setState(() {
        _isWaitingResponse = false;
      });
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PaymentConfirmationPage(
            receiverName: widget.receiverName,
            receiverPhone: widget.receiverPhone,
            amount: widget.amount,
            description: widget.description,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Offline Payment'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning || _isConnecting ? null : _startScan,
            tooltip: 'Rescan Devices',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withOpacity(0.8),
                  ],
                ),
              ),
              child: Row(
                children: [
                  RotationTransition(
                    turns: _isScanning ? _animationController! : const AlwaysStoppedAnimation(0),
                    child: Icon(
                      Icons.bluetooth,
                      size: 32,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'OffPay',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                        Text(
                          'Secure Offline P2P Payment',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onPrimary.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.payment, color: colorScheme.primary, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'Payment Details',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildDetailRow('To:', widget.receiverName),
                    _buildDetailRow('Phone:', widget.receiverPhone),
                    _buildDetailRow('Amount:', '₹${widget.amount.toStringAsFixed(2)}'),
                    if (widget.description?.isNotEmpty == true)
                      _buildDetailRow('Description:', widget.description!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    RotationTransition(
                      turns: _isScanning || _isConnecting ? _animationController! : const AlwaysStoppedAnimation(0),
                      child: Icon(
                        _isPaired ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                        size: 36,
                        color: _isPaired ? Colors.green : colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _connectionStatus,
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurface.withOpacity(0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_isPaired)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'PAIRED',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _isPaired ? _buildConnectedView() : _buildDeviceList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedView() {
    return Column(
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                ScaleTransition(
                  scale: Tween(begin: 0.8, end: 1.0).animate(
                    CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 48,
                      color: Colors.green,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Paired with ${_getDeviceName(_selectedDevice!)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Payment sent. Verify to confirm.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isPaired && !_isWaitingResponse ? _verifyAndProceed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
            child: _isWaitingResponse
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Verifying...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'Verify',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceList() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isScanning || _isConnecting ? null : _startScan,
            icon: _isScanning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(
              _isScanning ? 'Scanning...' : 'Scan for Devices',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_discoveredDevices.any((device) => _getDeviceName(device) == _defaultDeviceName))
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Demo device available for testing',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Expanded(
          child: _discoveredDevices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      RotationTransition(
                        turns: _isScanning
                            ? _animationController!
                            : const AlwaysStoppedAnimation(0),
                        child: Icon(
                          Icons.bluetooth_searching,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isScanning ? 'Scanning for devices...' : 'No devices found',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      if (!_isScanning) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Simulated devices available for web testing',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final device = _discoveredDevices[index];
                    final isConnecting = _isConnecting && _selectedDevice?.id == device.id;
                    final isDemoDevice = _getDeviceName(device) == _defaultDeviceName;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: _selectedDevice?.id == device.id ? 4 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: _selectedDevice?.id == device.id
                            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 1)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDemoDevice
                                ? Colors.blue.withOpacity(0.1)
                                : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isDemoDevice ? Icons.smartphone : Icons.bluetooth,
                            color: isDemoDevice
                                ? Colors.blue
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          _getDeviceName(device),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _selectedDevice?.id == device.id
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          isDemoDevice ? 'Demo Device - Tap to pair' : 'Tap to pair and send payment',
                          style: TextStyle(
                            color: isDemoDevice ? Colors.blue.shade600 : Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        trailing: isConnecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _selectedDevice?.id == device.id && _isPaired
                                    ? Icons.check_circle
                                    : Icons.arrow_forward_ios,
                                size: 16,
                                color: _selectedDevice?.id == device.id && _isPaired
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                              ),
                        onTap: (isConnecting || _isPaired) ? null : () => _connectToDevice(device),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}