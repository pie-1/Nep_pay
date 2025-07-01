import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/transactions_queue.dart';

class ReceiverBluetoothServerScreen extends StatefulWidget {
  const ReceiverBluetoothServerScreen({super.key});

  @override
  State<ReceiverBluetoothServerScreen> createState() => _ReceiverBluetoothServerScreenState();
}

class _ReceiverBluetoothServerScreenState extends State<ReceiverBluetoothServerScreen>
    with SingleTickerProviderStateMixin {
  final BLEService _bleService = BLEService();
  String _connectionStatus = 'Initializing...';
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isListening = false;
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

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
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
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

    _messageSubscription = _bleService.messageStream.listen((message) {
      _handleIncomingMessage(message);
    });

    _startListening();
  }

  void _startListening() {
    setState(() {
      _isListening = true;
      _connectionStatus = 'Ready to receive payments. Device is discoverable.';
    });
    _animationController.repeat();

    // Simulate incoming payment request after a delay for demo
    Timer(const Duration(seconds: 3), () {
      if (mounted && _pendingRequests.isEmpty) {
        _simulateIncomingRequest();
      }
    });
  }

  void _simulateIncomingRequest() {
    _bleService.simulateIncomingPaymentRequest(
      senderName: 'John Doe',
      senderPhone: '+91 98765 43210',
      amount: 250.0,
      description: 'Coffee payment',
    );
  }

  void _handleIncomingMessage(Map<String, dynamic> message) {
    if (message['type'] == 'payment_request') {
      setState(() {
        _pendingRequests.add(message);
      });
      _showPaymentRequestDialog(message);
    }
  }

  Future<void> _showPaymentRequestDialog(Map<String, dynamic> request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.payment,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Payment Request',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRequestDetailRow('From:', request['sender_name']),
                    _buildRequestDetailRow('Phone:', request['sender_phone']),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '₹${request['amount']}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    if (request['description']?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      _buildRequestDetailRow('For:', request['description']),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Do you want to accept this payment?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    final transactionId = request['transaction_id'];
    await _bleService.sendPaymentResponse(
      transactionId: transactionId,
      accepted: confirmed ?? false,
      reason: confirmed == false ? 'Payment rejected by receiver' : null,
    );

    if (confirmed == true) {
      await TransactionQueue.queue({
        'method': 'P2P-BT',
        'name': request['sender_name'],
        'phone': request['sender_phone'],
        'amount': request['amount'],
        'description': request['description'] ?? '',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'completed',
        'transaction_id': transactionId,
        'type': 'received',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('Payment of ₹${request['amount']} accepted and recorded'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    }

    setState(() {
      _pendingRequests.removeWhere((req) => req['transaction_id'] == transactionId);
    });
  }

  Widget _buildRequestDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Receive Payment'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(_isListening ? Icons.stop : Icons.play_arrow),
            onPressed: () {
              if (_isListening) {
                _animationController.stop();
                setState(() {
                  _isListening = false;
                  _connectionStatus = 'Stopped listening for payments';
                });
              } else {
                _startListening();
              }
            },
            tooltip: _isListening ? 'Stop listening' : 'Start listening',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status Card
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primary.withOpacity(0.1),
                      colorScheme.primary.withOpacity(0.05),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _isListening ? _pulseAnimation.value : 1.0,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _isListening 
                                  ? colorScheme.primary.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Icon(
                              _isListening ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                              size: 48,
                              color: _isListening ? colorScheme.primary : Colors.grey,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Bluetooth Payment Receiver',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _connectionStatus,
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
            
            const SizedBox(height: 24),
            
            // Instructions Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'How to receive payments:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInstructionStep('1', 'Keep this screen open and active'),
                    _buildInstructionStep('2', 'Ensure Bluetooth is enabled on your device'),
                    _buildInstructionStep('3', 'Your device is now discoverable to senders'),
                    _buildInstructionStep('4', 'Accept or reject incoming payment requests'),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            // Pending requests indicator
            if (_pendingRequests.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pending_actions, color: colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      '${_pendingRequests.length} pending request(s)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),

            // Demo button for testing
            if (_isListening && _pendingRequests.isEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 16),
                child: OutlinedButton.icon(
                  onPressed: _simulateIncomingRequest,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Simulate Payment Request (Demo)'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}