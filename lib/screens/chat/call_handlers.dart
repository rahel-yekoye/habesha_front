// This file is DEPRECATED and no longer needed
// Call functionality has been moved to:
// - CallManager for call orchestration
// - ChatScreen._onVoiceCallPressed() and _onVideoCallPressed() for UI integration
// - ModernCallScreen for call UI
// - WebRTCService for WebRTC handling

// The old CallScreen referenced here no longer exists and has been replaced
// by the new ModernCallScreen with proper WebRTC integration

/*import 'package:chat_app_flutter/screens/call_screen.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'chat_screen.dart';
// Your CallScreen widget import

void onVoiceCallPressed(BuildContext context, ChatScreen widget, bool isCallScreenOpen, VoidCallback onClosed) {
  if (isCallScreenOpen) return;

  const uuid = Uuid();
  final callId = uuid.v4();

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CallScreen(
        selfId: widget.currentUser,
        peerId: widget.otherUser,
        isCaller: true,
        voiceOnly: true,
        callerName: widget.currentUser,
        socketService: widget.socketService,
        callId: callId, // Pass the unique call ID
        onCallScreenClosed: onClosed,
      ),
    ),
  ).then((_) => onClosed());
}

void onVideoCallPressed(BuildContext context, ChatScreen widget, bool isCallScreenOpen, VoidCallback onClosed) {
  if (isCallScreenOpen) return;

  const uuid = Uuid();
  final callId = uuid.v4();

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CallScreen(
        selfId: widget.currentUser,
        peerId: widget.otherUser,
        isCaller: true,
        voiceOnly: false,
        callerName: widget.currentUser,
        socketService: widget.socketService,
        callId: callId, // Pass the unique call ID
        onCallScreenClosed: onClosed,
      ),
    ),
  ).then((_) => onClosed());
}
*/