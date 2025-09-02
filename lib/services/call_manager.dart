import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import '../screens/modern_call_screen.dart';

class CallManager {
  IO.Socket? _socket;
  BuildContext? _context;
  Map<String, dynamic>? _pendingIncomingCall;
  String? _currentUserId;

  void initialize(IO.Socket socket, BuildContext context, String currentUserId) {
    print('[CallManager] ===== INITIALIZING CALL MANAGER =====');
    print('[CallManager] Socket ID: ${socket.id}');
    print('[CallManager] Socket connected: ${socket.connected}');
    print('[CallManager] Current user ID: $currentUserId');
    print('[CallManager] Previous user ID: $_currentUserId');
    
    // Always reinitialize to ensure fresh state
    print('[CallManager] Initializing for user: $currentUserId');
    _socket = socket;
    _context = context;
    _currentUserId = currentUserId;
    _pendingIncomingCall = null; // Reset pending call state
    
    // Ensure socket is connected before setting up listeners
    if (!socket.connected) {
      print('[CallManager] Socket not connected, waiting for connection...');
      socket.onConnect((_) {
        print('[CallManager] Socket connected, setting up listeners');
        _setupSocketListeners();
      });
    } else {
      _setupSocketListeners();
    }
    
    print('[CallManager] ===== CALL MANAGER INITIALIZATION COMPLETE =====');
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
    _socket!.off('call_decline');
    _socket!.off('call_answered');
    _socket!.off('test_incoming_call');
    _socket!.off('test_event');
    
    // Test event listener
    _socket!.on('test_incoming_call', (data) {
      print('[CallManager] ***********************');
      print('[CallManager] TEST INCOMING CALL RECEIVED: $data');
      print('[CallManager] Current socket ID: ${_socket?.id}');
      print('[CallManager] Current user ID: $_currentUserId');
      print('[CallManager] ***********************');
    });
    
    // Listen for test events to verify socket connection
    _socket!.on('test_event', (data) {
      print('[CallManager] TEST: Received test_event: $data');
    });
    
    // Socket disconnect handler
    _socket!.onDisconnect((_) {
      print('[CallManager] ⚠️ Socket disconnected!');
    });
    
    // Add a catch-all listener to see ALL events
    _socket!.onAny((event, data) {
      print('[CallManager] RECEIVED EVENT: $event with data: $data');
    });
    
    // Listen for incoming calls - this is the main event from backend
    _socket!.on('incoming_call', (data) {
      print('[CallManager] *** INCOMING_CALL EVENT RECEIVED ***');
      print('[CallManager] Raw data: $data');
      print('[CallManager] Data type: ${data.runtimeType}');
      
      if (_pendingIncomingCall != null) {
        print('[CallManager] Already have a pending call, ignoring new one');
        return;
      }
      _handleIncomingCall(data as Map<String, dynamic>);
    });
    
    // Listen for call offers (WebRTC signaling)
    _socket!.on('call_offer', (data) {
      print('[CallManager] Received call_offer: $data');
      _handleCallOffer(data as Map<String, dynamic>);
    });
    
    // Listen for call answers (WebRTC signaling)
    _socket!.on('call_answer', (data) {
      print('[CallManager] Received call_answer: $data');
      _handleCallAnswer(data as Map<String, dynamic>);
    });
    
    // Listen for ICE candidates (WebRTC signaling)
    _socket!.on('ice_candidate', (data) {
      print('[CallManager] Received ice_candidate: $data');
      _handleIceCandidate(data as Map<String, dynamic>);
    });
    
    // Listen for call decline
    _socket!.on('call_decline', (data) {
      print('[CallManager] Received call_decline: $data');
      _handleCallDecline(data as Map<String, dynamic>);
    });
    
    // Listen for call end
    _socket!.on('call_end', (data) {
      print('[CallManager] Received call_end: $data');
      _handleCallEnd(data as Map<String, dynamic>);
    });
    
    // Call answered (notification)
    _socket!.on('call_answered', (data) {
      print('[CallManager] Call was answered by ${data['from']}');
    });
    
    // Listen for server instruction to start WebRTC offer
    _socket!.on('start_webrtc_offer', (data) {
      print('[CallManager] ===== RECEIVED START_WEBRTC_OFFER =====');
      print('[CallManager] Data: $data');
      print('[CallManager] Partner ID: ${data['partnerId']}');
      print('[CallManager] Call ID: ${data['callId']}');
      // This event will be handled by the ModernCallScreen that's already open for the caller
    });
    
    // Listen for call invitation ready (URL-based calls)
    _socket!.on('call_invitation_ready', (data) {
      print('[CallManager] ===== RECEIVED CALL_INVITATION_READY =====');
      print('[CallManager] Data: $data');
      final callId = data['callId'];
      final callerId = data['callerId'];
      final calleeId = data['calleeId'];
      
      // If this is for the current user (as caller), initiate the WebRTC offer
      if (_currentUserId == callerId) {
        print('[CallManager] Current user is caller, initiating WebRTC offer');
        _socket!.emit('start_webrtc_offer', {
          'callId': callId,
          'partnerId': calleeId,
          'callerId': callerId,
        });
      } else if (_currentUserId == calleeId) {
        print('[CallManager] Current user is callee, waiting for WebRTC offer');
        // The callee just waits for the incoming call offer
      }
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

    print('[CallManager] ===== STARTING OUTGOING CALL =====');
    print('[CallManager] Partner ID: $partnerId');
    print('[CallManager] Partner Name: $partnerName');
    print('[CallManager] Current User ID: $currentUserId');
    print('[CallManager] Is Video: $isVideo');
    print('[CallManager] Socket ID: ${_socket!.id}');

    final callId = '${DateTime.now().millisecondsSinceEpoch}_${_socket!.id}_$partnerId';
    
    // Get the caller's actual display name to send
    String callerDisplayName = currentUserId;
    try {
      final callerProfile = await _getUserProfile(currentUserId);
      callerDisplayName = callerProfile['name'] ?? currentUserId;
      print('[CallManager] Resolved caller display name: $callerDisplayName');
    } catch (e) {
      print('[CallManager] Could not resolve caller name, using ID: $e');
      callerDisplayName = currentUserId;
    }
    
    // First, emit call_initiate event to notify the receiver
    _socket!.emit('call_initiate', {
      'to': partnerId,
      'from': currentUserId,
      'callerName': callerDisplayName, // Send actual display name
      'callId': callId,
      'isVideo': isVideo,
    });
    
    print('[CallManager] Emitted call_initiate to $partnerId with caller name: $callerDisplayName, callId: $callId');
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
    print('[CallManager] ===== OUTGOING CALL SETUP COMPLETE =====');
  }

  void _handleIncomingCall(Map<String, dynamic> data) async {
    print('[CallManager] ===== HANDLING INCOMING CALL =====');
    print('[CallManager] Raw incoming call data: $data');
    print('[CallManager] Context is null: ${_context == null}');
    print('[CallManager] Current user ID: $_currentUserId');
    
    if (_context == null) {
      print('[CallManager] ERROR: Context is null, cannot show incoming call dialog');
      return;
    }
    
    final String callerId = data['from'];
    final String callerIdFromData = data['callerName'] ?? 'Unknown'; // This is actually a user ID
    final String callId = data['callId'];
    final bool isVideo = data['isVideo'] ?? false;

    print('[CallManager] Extracted caller ID: $callerId');
    print('[CallManager] Extracted caller name from data: $callerIdFromData');
    print('[CallManager] Extracted call ID: $callId');
    print('[CallManager] Extracted is video: $isVideo');

    // Set pending call to prevent duplicate handling
    _pendingIncomingCall = data;

    // Resolve the caller's display name from their user ID
    String callerDisplayName = callerIdFromData;
    try {
      // Fetch the caller's profile to get their actual display name
      final callerProfile = await _getUserProfile(callerId);
      callerDisplayName = callerProfile['name'] ?? callerIdFromData;
      print('[CallManager] Resolved caller display name: $callerDisplayName');
    } catch (e) {
      print('[CallManager] Could not resolve caller name, using ID: $e');
      callerDisplayName = callerIdFromData;
    }

    print('[CallManager] Received incoming call from $callerId (name: $callerDisplayName)');
    print('[CallManager] Call ID: $callId, Video: $isVideo');
    print('[CallManager] Context available: ${_context != null}');

    showDialog(
      context: _context!,
      barrierDismissible: false,
      builder: (context) => _buildIncomingCallDialog(
        callerId: callerId,
        callerName: callerDisplayName,
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

    // Clear pending call state
    _pendingIncomingCall = null;

    final currentUserId = _getCurrentUserId();
    
    print('[CallManager] ===== ACCEPTING INCOMING CALL =====');
    print('[CallManager] Caller ID: $callerId');
    print('[CallManager] Caller Name: $callerName');
    print('[CallManager] Current User ID: $currentUserId');
    print('[CallManager] Call ID: $callId');
    print('[CallManager] Is Video: $isVideo');

    // Notify backend/caller that call is accepted
    _socket?.emit('call_answered', {
      'to': callerId,
      'from': currentUserId,
      'callId': callId,
    });

    print('[CallManager] Call accepted, navigating to call screen immediately');
    
    // Navigate to call screen immediately without waiting for offer
    Navigator.of(_context!).push(
      MaterialPageRoute(
        builder: (context) => ModernCallScreen(
          partnerId: callerId,        // The caller is our partner
          partnerName: callerName,    // The caller's name
          callId: callId,
          isVideo: isVideo,
          isIncoming: true,
          incomingOffer: null, // Will be handled when offer arrives
          socket: _socket!,
          currentUserId: currentUserId, // We are the current user (callee)
          onCallEnded: () {
            print('[CallManager] Incoming call ended');
          },
        ),
      ),
    );
    print('[CallManager] ===== INCOMING CALL ACCEPTED =====');
  }

  void _declineCall(String callerId, String callId) {
    // Clear pending call state
    _pendingIncomingCall = null;
    
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
    // Call offers are now handled directly by the ModernCallScreen
    // when it sets up its own listener, so this method is no longer needed
    print('[CallManager] Call offer received - forwarded to active call screen');
  }

  void _handleCallAnswer(Map<String, dynamic> data) {
    // Call answers are handled by ModernCallScreen directly
    print('[CallManager] Call answer received - forwarded to active call screen');
  }

  void _handleIceCandidate(Map<String, dynamic> data) {
    // ICE candidates are handled by ModernCallScreen directly
    print('[CallManager] ICE candidate received - forwarded to active call screen');
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

  // Fetch user profile to get display name
  Future<Map<String, dynamic>> _getUserProfile(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('http://localhost:4000/profile/$userId'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 404) {
        print('[CallManager] User profile not found for ID: $userId');
        return {'name': userId}; // Return a default profile
      } else {
        print('[CallManager] Failed to fetch profile, status: ${response.statusCode}');
        throw Exception('Failed to load user profile');
      }
    } catch (e) {
      print('[CallManager] Error fetching user profile: $e');
      return {'name': userId}; // Return a default profile on error
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
    _socket?.off('start_webrtc_offer');
    
    _socket = null;
    _context = null;
    _pendingIncomingCall = null;
  }
}
