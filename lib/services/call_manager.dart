import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../screens/modern_call_screen.dart';
import 'webrtc_service.dart';

class CallManager {
  IO.Socket? _socket;
  BuildContext? _context;
  WebRTCService? _webrtcService;
  Map<String, dynamic>? _pendingIncomingCall;
  String? _currentUserId;

  void initialize(IO.Socket socket, BuildContext context, String currentUserId) {
print('[CallManager] Initializing with socket ID: ${socket.id}');
  print('[CallManager] Socket connected: ${socket.connected}');
  print('[CallManager] Current user ID: $currentUserId');
  socket.on('test_incoming_call', (data) {
  print('[CallManager] TEST INCOMING CALL RECEIVED: $data');
});
      if (_currentUserId == currentUserId && _socket != null) {
      print('[CallManager] Already initialized for user: $currentUserId, skipping');
      return;
    }
    
    print('[CallManager] Initializing for user: $currentUserId');
    _socket = socket;
    _context = context;
    _currentUserId = currentUserId;
    _webrtcService = WebRTCService();
    _setupSocketListeners();
    print('[CallManager] Initialization complete');
  }

  void _setupSocketListeners() {
    if (_socket == null) {
      print('[CallManager] Cannot setup listeners: Socket is null');
      return;
    }

    print('[CallManager] Setting up socket listeners for socket ID: ${_socket!.id}');
    print('[CallManager] Current user ID: $_currentUserId');
    
    // Remove existing listeners to avoid duplicates
    print('[CallManager] Removing existing listeners');
    _socket!.off('incoming_call');
    _socket!.off('call_offer');
    _socket!.off('call_answer');
    _socket!.off('ice_candidate');
    _socket!.off('call_end');
    _socket!.off('test_incoming_call');
    
    // Test event listener
    _socket!.on('test_incoming_call', (data) {
      print('[CallManager] ***********************');
      print('[CallManager] TEST INCOMING CALL RECEIVED: $data');
      print('[CallManager] Current socket ID: ${_socket?.id}');
      print('[CallManager] Current user ID: $_currentUserId');
      print('[CallManager] ***********************');
    });
    
    // Incoming call listener
    _socket!.on('incoming_call', (data) {
      print('[CallManager] ***********************');
      print('[CallManager] INCOMING CALL RECEIVED: $data');
      print('[CallManager] Current socket ID: ${_socket?.id}');
      print('[CallManager] Current user ID: $_currentUserId');
      print('[CallManager] ***********************');
      
      if (_pendingIncomingCall != null) {
        print('[CallManager] Already have a pending call, ignoring new one');
        return;
      }
      _handleIncomingCall(data);
    });
    _socket!.off('call_decline');
    _socket!.off('call_answered');

    // Listen for test events to verify socket connection
    _socket!.on('test_event', (data) {
      print('[CallManager] TEST: Received test_event: $data');
    });
    // In call_manager.dart, in _setupSocketListeners
_socket!.onDisconnect((_) {
  print('[CallManager] ⚠️ Socket disconnected!');
});
    // Add a catch-all listener to see ALL events
    _socket!.onAny((event, data) {
      print('[CallManager] RECEIVED EVENT: $event with data: $data');
    });
    
    // Listen for incoming calls with detailed debugging
    _socket!.on('incoming_call', (data) {
      print('[CallManager] *** INCOMING_CALL EVENT RECEIVED ***');
      print('[CallManager] Raw data: $data');
      print('[CallManager] Data type: ${data.runtimeType}');
      _handleIncomingCall(data as Map<String, dynamic>);
    });
    
    // Listen for call offers
    _socket!.on('call_offer', (data) => _handleCallOffer(data as Map<String, dynamic>));
    
    // Listen for call answers
    _socket!.on('call_answer', (data) => _handleCallAnswer(data as Map<String, dynamic>));
    
    // Listen for ICE candidates
    _socket!.on('ice_candidate', (data) => _handleIceCandidate(data as Map<String, dynamic>));
    
    // Listen for call decline
    _socket!.on('call_decline', (data) => _handleCallDecline(data as Map<String, dynamic>));
    
    // Listen for call end
    _socket!.on('call_end', (data) => _handleCallEnd(data as Map<String, dynamic>));
    
    // Call answered (notification)
    _socket!.on('call_answered', (data) {
      print('[CallManager] Call was answered by ${data['from']}');
    });
  }

  // Start outgoing call
  Future<void> startCall({
    required String partnerId,
    required String partnerName,
    required bool isVideo,
    required String currentUserId,
  }) async {
    if (_context == null || _socket == null) return;

    final callId = '${DateTime.now().millisecondsSinceEpoch}_${_socket!.id}_$partnerId';
    
    // First, emit call_initiate event to notify the receiver
    _socket!.emit('call_initiate', {
      'to': partnerId,
      'from': currentUserId,
      'callerName': partnerName,
      'callId': callId,
      'isVideo': isVideo,
    });
    
    print('[CallManager] Emitted call_initiate to $partnerId (ID: $partnerId) with callId: $callId');
    print('[CallManager] Current socket ID: ${_socket!.id}');
    
    // Navigate to call screen for outgoing calls
    Navigator.of(_context!).push(
      MaterialPageRoute(
        builder: (context) => ModernCallScreen(
          partnerId: partnerId,
          partnerName: partnerName,
          callId: callId,
          isVideo: isVideo,
          isIncoming: false,
          socket: _socket!,
          currentUserId: currentUserId,
          onCallEnded: () {
            print('[CallManager] Outgoing call ended');
          },
        ),
      ),
    );
  }

  void _handleIncomingCall(Map<String, dynamic> data) {
    print('[CallManager] _handleIncomingCall called with data: $data');
    print('[CallManager] Context is null: ${_context == null}');
    
    if (_context == null) {
      print('[CallManager] ERROR: Context is null, cannot show incoming call dialog');
      return;
    }
    
    final String callerId = data['from'];
    final String callerName = data['callerName'] ?? 'Unknown';
    final String callId = data['callId'];
    final bool isVideo = data['isVideo'] ?? false;

    print('[CallManager] Received incoming call from $callerId (name: $callerName)');
    print('[CallManager] Call ID: $callId, Video: $isVideo');
    print('[CallManager] Context available: ${_context != null}');

    showDialog(
      context: _context!,
      barrierDismissible: false,
      builder: (context) => _buildIncomingCallDialog(
        callerId: callerId,
        callerName: callerName,
        callId: callId,
        isVideo: isVideo,
      ),
    );
  }

  Widget _buildIncomingCallDialog({
    required String callerId,
    required String callerName,
    required String callId,
    required bool isVideo,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Caller info
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey[300],
              child: Icon(Icons.person, size: 40, color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            Text(
              callerName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              isVideo ? 'Incoming video call' : 'Incoming voice call',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 30),
            
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline button
                GestureDetector(
                  onTap: () {
                    Navigator.of(_context!).pop();
                    _declineCall(callerId, callId);
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                    child: Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                
                // Accept button
                GestureDetector(
                  onTap: () {
                    Navigator.of(_context!).pop();
                    _acceptCall(callerId, callerName, callId, isVideo);
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.green,
                    ),
                    child: Icon(
                      Icons.call,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _acceptCall(String callerId, String callerName, String callId, bool isVideo) {
    if (_context == null) return;

    _pendingIncomingCall = {
      'callerId': callerId,
      'callerName': callerName,
      'callId': callId,
      'isVideo': isVideo,
      'currentUserId': _getCurrentUserId(), // Add current user ID
    };

    // Notify backend/caller that call is accepted
    _socket?.emit('call_answered', {
      'to': callerId,
      'from': _getCurrentUserId(),
      'callId': callId,
    });

    print('[CallManager] Call accepted, waiting for offer from $callerName');
  }

  void _declineCall(String callerId, String callId) {
    _socket!.emit('call_decline', {
      'to': callerId,
      'from': _getCurrentUserId(),
      'callId': callId,
    });
  }

  String _getCurrentUserId() {
    // This should be set when initializing CallManager
    return _currentUserId ?? 'unknown';
  }

  void _handleCallOffer(Map<String, dynamic> data) {
    if (_pendingIncomingCall != null && _context != null) {
      final callInfo = _pendingIncomingCall!;
      _pendingIncomingCall = null;
      
      Navigator.of(_context!).push(
        MaterialPageRoute(
          builder: (context) => ModernCallScreen(
            partnerId: callInfo['callerId'],
            partnerName: callInfo['callerName'],
            callId: callInfo['callId'],
            isVideo: callInfo['isVideo'],
            isIncoming: true,
            incomingOffer: data['offer'],
            socket: _socket!,
            currentUserId: callInfo['currentUserId'],
            onCallEnded: () {
              print('[CallManager] Incoming call ended');
            },
          ),
        ),
      );
    }
  }

  void _handleCallAnswer(Map<String, dynamic> data) {
    _webrtcService?.handleAnswer(data['answer']);
  }

  void _handleIceCandidate(Map<String, dynamic> data) {
    // Handle ICE candidate - implementation depends on WebRTC service
    print('[CallManager] ICE candidate received');
  }

  void _handleCallEnd(Map<String, dynamic> data) {
    if (_context != null) {
      Navigator.of(_context!).pop();
    }
  }

  void _handleCallDecline(Map<String, dynamic> data) {
    if (_context != null) {
      Navigator.of(_context!).pop();
    }
  }

  void dispose() {
    _socket?.off('incoming_call');
    _socket?.off('call_offer');
    _socket?.off('call_answer');
    _socket?.off('ice_candidate');
    _socket?.off('call_end');
    _socket?.off('call_decline');
    _socket?.off('call_answered');
    
    _socket = null;
    _context = null;
    _webrtcService = null;
  }
}
