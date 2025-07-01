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
    setState(() {
      _connectionStatus = 'Simulating Bluetooth for web...';
    });

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

    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _isConnecting = false;
      _isPaired = true;
      _connectionStatus = 'Paired with ${_getDeviceName(device)}';
    });

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
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: const Text(
          'Send Payment',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 22),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 24),
            onPressed: _isScanning || _isConnecting ? null : _startScan,
            tooltip: 'Rescan Devices',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Section
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    RotationTransition(
                      turns: _isScanning ? _animationController! : const AlwaysStoppedAnimation(0),
                      child: Icon(
                        Icons.bluetooth,
                        size: 28,
                        color: colorScheme.onPrimaryContainer,
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
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            'Secure Offline P2P Payment',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onPrimaryContainer.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Payment Details
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 16),
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
              // Connection Status
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      RotationTransition(
                        turns: _isScanning || _isConnecting ? _animationController! : const AlwaysStoppedAnimation(0),
                        child: Icon(
                          _isPaired ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                          size: 28,
                          color: _isPaired ? Colors.green : colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _connectionStatus,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface.withOpacity(0.8),
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
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                ScaleTransition(
                  scale: Tween(begin: 0.9, end: 1.0).animate(
                    CurvedAnimation(parent: _animationController!, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 40,
                      color: Colors.green,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Paired with ${_getDeviceName(_selectedDevice!)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Payment sent. Verify to confirm.',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        _buildActionButton(
          context,
          label: _isWaitingResponse ? 'Verifying...' : 'Verify',
          icon: _isWaitingResponse ? null : Icons.check,
          isLoading: _isWaitingResponse,
          onPressed: _isPaired && !_isWaitingResponse ? _verifyAndProceed : null,
        ),
      ],
    );
  }

  Widget _buildDeviceList() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildActionButton(
          context,
          label: _isScanning ? 'Scanning...' : 'Scan for Devices',
          icon: _isScanning ? null : Icons.search,
          isLoading: _isScanning,
          onPressed: _isScanning || _isConnecting ? null : _startScan,
        ),
        const SizedBox(height: 16),
        if (_discoveredDevices.any((device) => _getDeviceName(device) == _defaultDeviceName))
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Demo device available for testing',
                    style: TextStyle(
                      color: colorScheme.primary,
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
                        turns: _isScanning ? _animationController! : const AlwaysStoppedAnimation(0),
                        child: Icon(
                          Icons.bluetooth_searching,
                          size: 48,
                          color: colorScheme.onSurface.withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _isScanning ? 'Scanning for devices...' : 'No devices found',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      if (!_isScanning)
                        Text(
                          'Simulated devices available for web testing',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final device = _discoveredDevices[index];
                    final isConnecting = _isConnecting && _selectedDevice?.remoteId == device.remoteId;
                    final isDemoDevice = _getDeviceName(device) == _defaultDeviceName;

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: _selectedDevice?.remoteId == device.remoteId
                            ? BorderSide(color: colorScheme.primary, width: 1)
                            : BorderSide.none,
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDemoDevice ? colorScheme.primary.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isDemoDevice ? Icons.smartphone : Icons.bluetooth,
                            color: isDemoDevice ? colorScheme.primary : Colors.grey[600],
                            size: 24,
                          ),
                        ),
                        title: Text(
                          _getDeviceName(device),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _selectedDevice?.remoteId == device.remoteId
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          isDemoDevice ? 'Demo Device - Tap to pair' : 'Tap to pair and send payment',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDemoDevice ? colorScheme.primary : Colors.grey[600],
                          ),
                        ),
                        trailing: isConnecting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _selectedDevice?.remoteId == device.remoteId && _isPaired
                                    ? Icons.check_circle
                                    : Icons.arrow_forward_ios,
                                size: 16,
                                color: _selectedDevice?.remoteId == device.remoteId && _isPaired
                                    ? Colors.green
                                    : colorScheme.onSurface.withOpacity(0.6),
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

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    IconData? icon,
    required bool isLoading,
    required VoidCallback? onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else if (icon != null)
            Icon(icon, size: 20),
          if (isLoading || icon != null) const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}