import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../screens/modern_call_screen.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/call_manager.dart';

class CallInvitationService {
  static const String _baseUrl = 'http://localhost:3000'; // Frontend URL
  static Map<String, dynamic>? _pendingCallFromUrl;

  /// Generate a shareable call invitation URL
  static String generateCallInvitationUrl({
    required String callerId,
    required String callerName, 
    required String calleeId,
    required bool isVideo,
  }) {
    final callId = '${DateTime.now().millisecondsSinceEpoch}_${callerId}_${calleeId}';
    final callData = {
      'callerId': callerId,
      'callerName': callerName,
      'calleeId': calleeId,
      'callId': callId,
      'isVideo': isVideo,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    
    // Encode call data as base64 for URL
    final encodedData = base64Encode(utf8.encode(jsonEncode(callData)));
    final url = '$_baseUrl/#/call?data=$encodedData';
    
    print('[CallInvitation] Generated call URL: $url');
    return url;
  }

  /// Parse call invitation from URL
  static Map<String, dynamic>? parseCallInvitation(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.fragment.startsWith('/call')) return null;
      
      final queryParams = Uri.parse('http://dummy${uri.fragment}').queryParameters;
      final encodedData = queryParams['data'];
      if (encodedData == null) return null;
      
      final decodedJson = utf8.decode(base64Decode(encodedData));
      final callData = jsonDecode(decodedJson) as Map<String, dynamic>;
      
      // Validate required fields
      if (callData['callerId'] == null || 
          callData['calleeId'] == null || 
          callData['callId'] == null) {
        return null;
      }
      
      print('[CallInvitation] Parsed call data: $callData');
      return callData;
    } catch (e) {
      print('[CallInvitation] Error parsing call invitation URL: $e');
      return null;
    }
  }

  /// Handle call invitation from URL (when app loads with call URL)
  static Future<void> handleCallInvitationFromUrl(String url) async {
    print('[CallInvitation] ===== HANDLING CALL INVITATION FROM URL =====');
    print('[CallInvitation] URL: $url');
    
    final callData = parseCallInvitation(url);
    if (callData == null) {
      print('[CallInvitation] Invalid call invitation URL');
      return;
    }
    
    print('[CallInvitation] Valid call data found: $callData');
    
    // Check if user is logged in
    final isLoggedIn = await AuthService.isLoggedIn();
    final userData = await AuthService.getUserData();
    final currentUserId = userData['userId'];
    
    print('[CallInvitation] Is logged in: $isLoggedIn');
    print('[CallInvitation] Current user ID: $currentUserId');
    print('[CallInvitation] Call is for: ${callData['calleeId']}');
    
    if (!isLoggedIn || currentUserId == null) {
      // Store pending call and redirect to login
      print('[CallInvitation] User not logged in, storing pending call and redirecting to login');
      _pendingCallFromUrl = callData;
      _redirectToLogin();
      return;
    }
    
    // Verify this call is for the current user
    if (currentUserId != callData['calleeId']) {
      print('[CallInvitation] Call is not for current user (${currentUserId} vs ${callData['calleeId']})');
      _showWrongUserDialog(callData);
      return;
    }
    
    // Check if call is too old (older than 5 minutes)
    final timestamp = callData['timestamp'] as int;
    final callAge = DateTime.now().millisecondsSinceEpoch - timestamp;
    if (callAge > 5 * 60 * 1000) { // 5 minutes
      print('[CallInvitation] Call invitation has expired (${callAge / 1000} seconds old)');
      _showExpiredCallDialog();
      return;
    }
    
    // Connect to socket and join call
    await _connectAndJoinCall(callData, userData);
  }
  
  /// Connect to socket and join the call
  static Future<void> _connectAndJoinCall(Map<String, dynamic> callData, Map<String, String?> userData) async {
    try {
      print('[CallInvitation] Connecting to socket for call...');
      
      // Connect to socket service
      await socketService.connect(
        userId: userData['userId']!,
        jwtToken: userData['token'],
      );
      
      // Wait a moment for CallManager to initialize
      await Future.delayed(Duration(milliseconds: 500));
      
      final callManager = socketService.getCurrentCallManager();
      if (callManager == null) {
        print('[CallInvitation] CallManager not available, initializing...');
        // Force CallManager initialization
        if (navigatorKey.currentContext != null) {
          final newCallManager = CallManager();
          newCallManager.initialize(
            socketService.socket, 
            navigatorKey.currentContext!, 
            userData['userId']!
          );
        }
        
        // Wait and try again
        await Future.delayed(Duration(milliseconds: 500));
      }
      
      // Navigate directly to call screen as incoming call
      if (navigatorKey.currentContext != null) {
        Navigator.of(navigatorKey.currentContext!).push(
          MaterialPageRoute(
            builder: (context) => ModernCallScreen(
              partnerId: callData['callerId'],
              partnerName: callData['callerName'] ?? callData['callerId'],
              callId: callData['callId'],
              isVideo: callData['isVideo'] ?? false,
              isIncoming: true,
              socket: socketService.socket,
              currentUserId: userData['userId']!,
              onCallEnded: () {
                print('[CallInvitation] Call ended from URL invitation');
              },
            ),
          ),
        );
        
        // Simulate incoming call notification
        _simulateIncomingCall(callData, userData['userId']!);
      }
      
    } catch (e) {
      print('[CallInvitation] Error connecting and joining call: $e');
      _showConnectionErrorDialog();
    }
  }
  
  /// Simulate incoming call to trigger proper call flow
  static void _simulateIncomingCall(Map<String, dynamic> callData, String currentUserId) {
    // Emit to socket that we're ready to receive the call
    try {
      socketService.socket.emit('call_invitation_ready', {
        'callId': callData['callId'],
        'callerId': callData['callerId'],
        'calleeId': callData['calleeId'],
        'currentUserId': currentUserId,
      });
      print('[CallInvitation] Notified server that callee is ready for call');
    } catch (e) {
      print('[CallInvitation] Error notifying server: $e');
    }
  }
  
  /// Check for pending call after login
  static Future<void> checkPendingCallAfterLogin() async {
    if (_pendingCallFromUrl != null) {
      print('[CallInvitation] Processing pending call after login');
      final callData = _pendingCallFromUrl!;
      _pendingCallFromUrl = null;
      
      final userData = await AuthService.getUserData();
      await _connectAndJoinCall(callData, userData);
    }
  }
  
  /// Store current URL for processing after authentication
  static void storePendingCallUrl(String url) {
    final callData = parseCallInvitation(url);
    if (callData != null) {
      _pendingCallFromUrl = callData;
      print('[CallInvitation] Stored pending call data for after login: $callData');
    }
  }
  
  static void _redirectToLogin() {
    if (navigatorKey.currentContext != null) {
      Navigator.of(navigatorKey.currentContext!).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }
  
  static void _showWrongUserDialog(Map<String, dynamic> callData) {
    if (navigatorKey.currentContext != null) {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: Text('Wrong User'),
          content: Text('This call invitation is for ${callData['calleeId']}, but you are logged in as a different user.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }
  
  static void _showExpiredCallDialog() {
    if (navigatorKey.currentContext != null) {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: Text('Call Expired'),
          content: Text('This call invitation has expired. Please ask for a new call link.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }
  
  static void _showConnectionErrorDialog() {
    if (navigatorKey.currentContext != null) {
      showDialog(
        context: navigatorKey.currentContext!,
        builder: (context) => AlertDialog(
          title: Text('Connection Error'),
          content: Text('Could not connect to the call. Please check your internet connection and try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }
}
