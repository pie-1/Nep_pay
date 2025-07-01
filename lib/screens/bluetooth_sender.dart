import 'dart:async';
import 'package:flutter/material.dart';
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

class _BluetoothSenderScreenState extends State<BluetoothSenderScreen> 
    with SingleTickerProviderStateMixin {
  final BLEService _bleService = BLEService();
  List<BluetoothDevice> _discoveredDevices = [];
  BluetoothDevice? _selectedDevice;
  String _connectionStatus = 'Ready to scan';
  bool _isWaitingResponse = false;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  StreamSubscription? _devicesSubscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _initializeBluetooth();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _devicesSubscription?.cancel();
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _bleService.stopScan();
    _bleService.disconnect();
    super.dispose();
  }

  Future<void> _initializeBluetooth() async {
    final isAvailable = await _bleService.isBluetoothAvailable();
    if (!isAvailable) {
      setState(() {
        _connectionStatus = 'Bluetooth not available. Please enable Bluetooth.';
      });
      return;
    }

    _statusSubscription = _bleService.connectionStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _connectionStatus = status;
        });
      }
    });

    _devicesSubscription = _bleService.devicesStream.listen((devices) {
      if (mounted) {
        setState(() {
          _discoveredDevices = devices;
        });
      }
    });

    _messageSubscription = _bleService.messageStream.listen((message) {
      _handleIncomingMessage(message);
    });

    setState(() {
      _connectionStatus = 'Ready to scan for devices';
    });
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
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('Payment of ₹${widget.amount.toStringAsFixed(2)} sent successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pushReplacement(
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

  void _onPaymentRejected(Map<String, dynamic> response) {
    if (mounted) {
      final reason = response['reason'] ?? 'Payment was rejected by the receiver';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(reason)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _startScan() async {
    _animationController.repeat();
    await _bleService.startScan();
    _animationController.stop();
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final success = await _bleService.connectToDevice(device);
    if (success && mounted) {
      setState(() {
        _selectedDevice = device;
      });
    }
  }

  Future<void> _sendPayment() async {
    if (_selectedDevice == null) return;

    setState(() {
      _isWaitingResponse = true;
    });

    final success = await _bleService.sendPaymentRequest(
      senderName: 'Current User',
      senderPhone: '+1234567890',
      receiverName: widget.receiverName,
      receiverPhone: widget.receiverPhone,
      amount: widget.amount,
      description: widget.description,
    );

    if (!success && mounted) {
      setState(() {
        _isWaitingResponse = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Send Payment'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (!_bleService.isScanning && !_bleService.isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
              tooltip: 'Scan for devices',
            ),
        ],
      ),
      body: Column(
        children: [
          // Payment Details Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.primary.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.payment,
                      color: colorScheme.onPrimary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Payment Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDetailRow('To:', widget.receiverName, colorScheme.onPrimary),
                _buildDetailRow('Phone:', widget.receiverPhone, colorScheme.onPrimary),
                _buildDetailRow('Amount:', '₹${widget.amount.toStringAsFixed(2)}', colorScheme.onPrimary),
                if (widget.description?.isNotEmpty == true)
                  _buildDetailRow('Description:', widget.description!, colorScheme.onPrimary),
              ],
            ),
          ),

          // Connection Status
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _bleService.isScanning ? _pulseAnimation.value : 1.0,
                      child: Icon(
                        _getStatusIcon(),
                        color: _getStatusColor(),
                        size: 24,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _connectionStatus,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_bleService.isConnected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'CONNECTED',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Device List or Connected View
          Expanded(
            child: _bleService.isConnected && _selectedDevice != null
                ? _buildConnectedView()
                : _buildDeviceList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: textColor.withOpacity(0.8),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon() {
    if (_bleService.isConnected) return Icons.bluetooth_connected;
    if (_bleService.isScanning) return Icons.bluetooth_searching;
    return Icons.bluetooth;
  }

  Color _getStatusColor() {
    if (_bleService.isConnected) return Colors.green;
    if (_bleService.isScanning) return Colors.blue;
    return Colors.grey;
  }

  Widget _buildConnectedView() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.green.withOpacity(0.1),
                    Colors.green.withOpacity(0.05),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Container(
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
                  const SizedBox(height: 16),
                  Text(
                    'Connected to',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedDevice!.displayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _selectedDevice!.signalIcon,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _selectedDevice!.signalStrength,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
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
              onPressed: _isWaitingResponse ? null : _sendPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          'Sending Payment...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'Send Payment',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Column(
      children: [
        // Scan Button
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _bleService.isScanning ? null : _startScan,
            icon: _bleService.isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(
              _bleService.isScanning ? 'Scanning...' : 'Scan for Devices',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Device List
        Expanded(
          child: _discoveredDevices.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final device = _discoveredDevices[index];
                    final isDemo = device.name.contains('OffPay');
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDemo
                                ? Colors.blue.withOpacity(0.1)
                                : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isDemo ? Icons.smartphone : Icons.bluetooth,
                            color: isDemo
                                ? Colors.blue
                                : Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          device.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  device.signalIcon,
                                  size: 14,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  device.signalStrength,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const Spacer(),
                                if (isDemo)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'DEMO',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              device.isConnectable ? 'Tap to connect' : 'Not available',
                              style: TextStyle(
                                fontSize: 12,
                                color: device.isConnectable ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: device.isConnectable 
                              ? Theme.of(context).colorScheme.primary 
                              : Colors.grey,
                        ),
                        onTap: device.isConnectable ? () => _connectToDevice(device) : null,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _bleService.isScanning ? _pulseAnimation.value : 1.0,
                child: Icon(
                  Icons.bluetooth_searching,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            _bleService.isScanning ? 'Scanning for devices...' : 'No devices found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _bleService.isScanning 
                ? 'Please wait while we search for nearby devices'
                : 'Tap "Scan for Devices" to find nearby payment-enabled devices',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}