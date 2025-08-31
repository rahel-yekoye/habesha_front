import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../services/webrtc_service.dart';

enum CallState { connecting, ringing, connected, ended }

class ModernCallScreen extends StatefulWidget {
  final String partnerId;
  final String partnerName;
  final String callId;
  final bool isVideo;
  final bool isIncoming;
  final Map<String, dynamic>? incomingOffer;
  final IO.Socket socket;
  final String currentUserId;
  final VoidCallback? onCallEnded;

  const ModernCallScreen({
    super.key,
    required this.partnerId,
    required this.partnerName,
    required this.callId,
    required this.isVideo,
    required this.isIncoming,
    required this.socket,
    required this.currentUserId,
    this.incomingOffer,
    this.onCallEnded,
  });

  @override
  State<ModernCallScreen> createState() => _ModernCallScreenState();
}

class _ModernCallScreenState extends State<ModernCallScreen> {
  final WebRTCService _webrtcService = WebRTCService();
  
  CallState _callState = CallState.connecting;
  bool _isMuted = false;
  bool _isVideoEnabled = true;
  bool _isSpeakerOn = false;
  
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  
  Timer? _callTimer;
  int _callDuration = 0;
  
  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    
    _setupWebRTCCallbacks();
    
    if (widget.isIncoming) {
      setState(() => _callState = CallState.ringing);
      // Auto-answer incoming calls since user already pressed green button
      _answerCall();
    } else {
      _startOutgoingCall();
    }
  }

  void _setupWebRTCCallbacks() {
    _webrtcService.onLocalStream = (stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }
    };

    _webrtcService.onRemoteStream = (stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      }
    };

    _webrtcService.onCallConnected = () {
      if (mounted) {
        setState(() => _callState = CallState.connected);
        _startCallTimer();
      }
    };

    _webrtcService.onCallEnded = (reason) {
      if (mounted) {
        _endCall();
      }
    };
  }

  Future<void> _startOutgoingCall() async {
    setState(() => _callState = CallState.connecting);
    
    await _webrtcService.startCall(
      partnerId: widget.partnerId,
      callId: widget.callId,
      isVideo: widget.isVideo,
      socket: widget.socket,
      currentUserId: widget.currentUserId,
    );
  }

  Future<void> _answerCall() async {
    if (widget.incomingOffer == null) return;
    
    setState(() => _callState = CallState.connecting);
    
    await _webrtcService.answerCall(
      partnerId: widget.partnerId,
      callId: widget.callId,
      isVideo: widget.isVideo,
      offer: widget.incomingOffer!,
      socket: widget.socket,
      currentUserId: widget.currentUserId,
    );
  }


  void _endCall() {
    _callTimer?.cancel();
    _webrtcService.endCall(widget.socket, widget.currentUserId);
    
    setState(() => _callState = CallState.ended);
    
    if (widget.onCallEnded != null) {
      widget.onCallEnded!();
    }
    
    Navigator.of(context).pop();
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _callDuration++);
      }
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _toggleMute() {
    _webrtcService.toggleMute();
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleVideo() {
    _webrtcService.toggleVideo();
    setState(() => _isVideoEnabled = !_isVideoEnabled);
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    // Implement speaker toggle logic
  }

  Future<void> _switchCamera() async {
    await _webrtcService.switchCamera();
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.black,
                  ],
                ),
              ),
            ),
            
            // Video views
            if (widget.isVideo) _buildVideoViews(),
            
            // Call info overlay
            _buildCallInfoOverlay(),
            
            // Controls
            _buildCallControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoViews() {
    return Stack(
      children: [
        // Remote video (full screen)
        if (_remoteRenderer.srcObject != null)
          Positioned.fill(
            child: RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        
        // Local video (small overlay)
        if (_localRenderer.srcObject != null)
          Positioned(
            top: 50,
            right: 20,
            child: Container(
              width: 120,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: RTCVideoView(
                  _localRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: true,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCallInfoOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            // Partner avatar
            if (!widget.isVideo || _remoteRenderer.srcObject == null)
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
                ),
                child: Icon(
                  Icons.person,
                  size: 60,
                  color: Colors.grey[600],
                ),
              ),
            
            SizedBox(height: 20),
            
            // Partner name
            Text(
              widget.partnerName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            
            SizedBox(height: 8),
            
            // Call status
            Text(
              _getCallStatusText(),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCallStatusText() {
    switch (_callState) {
      case CallState.connecting:
        return 'Connecting...';
      case CallState.ringing:
        return widget.isIncoming ? 'Incoming call' : 'Ringing...';
      case CallState.connected:
        return _formatDuration(_callDuration);
      case CallState.ended:
        return 'Call ended';
    }
  }

  Widget _buildCallControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main controls
            if (_callState == CallState.connected) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute button
                  _buildControlButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    onPressed: _toggleMute,
                    backgroundColor: _isMuted ? Colors.red : Colors.white24,
                  ),
                  
                  // Video toggle (only for video calls)
                  if (widget.isVideo)
                    _buildControlButton(
                      icon: _isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                      onPressed: _toggleVideo,
                      backgroundColor: _isVideoEnabled ? Colors.white24 : Colors.red,
                    ),
                  
                  // Speaker toggle
                  _buildControlButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    onPressed: _toggleSpeaker,
                    backgroundColor: _isSpeakerOn ? Colors.blue : Colors.white24,
                  ),
                  
                  // Camera switch (only for video calls)
                  if (widget.isVideo)
                    _buildControlButton(
                      icon: Icons.flip_camera_ios,
                      onPressed: _switchCamera,
                      backgroundColor: Colors.white24,
                    ),
                ],
              ),
              
              SizedBox(height: 30),
            ],
            
            // Answer/Decline or End call buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // End call button
                _buildControlButton(
                  icon: Icons.call_end,
                  onPressed: _endCall,
                  backgroundColor: Colors.red,
                  size: 60,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    double size = 50,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor,
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: size * 0.4,
        ),
      ),
    );
  }
}
