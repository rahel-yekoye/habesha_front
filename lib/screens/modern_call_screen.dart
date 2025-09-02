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
  Timer? _connectionMonitor;
  int _callDuration = 0;
  
  @override
  void initState() {
    super.initState();
    _initializeCall();
    _startConnectionMonitoring();
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
    
    _webrtcService.onWebRTCConnected = () {
      if (mounted && widget.isIncoming) {
        // For incoming calls, send call_answered event when WebRTC connection is established
        print('[CallScreen] WebRTC connection established for incoming call, sending call_answered to ${widget.partnerId}');
        widget.socket.emit('call_answered', {
          'to': widget.partnerId,
          'from': widget.currentUserId,
          'callId': widget.callId,
        });
      }
    };
    
    // Setup socket listeners for this call screen
    _setupSocketListeners();
  }

  Future<void> _startOutgoingCall() async {
    setState(() => _callState = CallState.connecting);
    
    print('[CallScreen] ===== STARTING OUTGOING CALL =====');
    print('[CallScreen] Partner ID: ${widget.partnerId}');
    print('[CallScreen] Partner Name: ${widget.partnerName}');
    print('[CallScreen] Current User ID: ${widget.currentUserId}');
    print('[CallScreen] Call ID: ${widget.callId}');
    print('[CallScreen] Is Video: ${widget.isVideo}');
    print('[CallScreen] Is Incoming: ${widget.isIncoming}');
    
    await _webrtcService.startCall(
      partnerId: widget.partnerId,
      callId: widget.callId,
      isVideo: widget.isVideo,
      socket: widget.socket,
      currentUserId: widget.currentUserId,
    );
  }

  Future<void> _answerCall() async {
    setState(() => _callState = CallState.connecting);
    
    if (widget.incomingOffer != null) {
      // If we have the offer, answer immediately
      await _webrtcService.answerCall(
        partnerId: widget.partnerId,
        callId: widget.callId,
        isVideo: widget.isVideo,
        offer: widget.incomingOffer!,
        socket: widget.socket,
        currentUserId: widget.currentUserId,
      );
    } else {
      // If no offer yet, wait for it via socket listener (already set up in _setupSocketListeners)
      print('[CallScreen] Waiting for call offer from ${widget.partnerId}');
    }
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

  void _startConnectionMonitoring() {
    // Monitor socket connection health every 5 seconds
    _connectionMonitor = Timer.periodic(Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final isConnected = widget.socket.connected;
      print('[CallScreen] 📡 Connection health check - Connected: $isConnected, Socket ID: ${widget.socket.id}');
      
      if (!isConnected && _callState != CallState.ended) {
        print('[CallScreen] ⚠️ Socket disconnected during active call, attempting reconnection...');
        try {
          widget.socket.connect();
        } catch (e) {
          print('[CallScreen] ❌ Failed to reconnect socket: $e');
        }
      }
    });
  }

  void _setupSocketListeners() {
    print('[CallScreen] Setting up socket listeners for call ${widget.callId}');
    print('[CallScreen] Socket connected: ${widget.socket.connected}');
    print('[CallScreen] Socket ID: ${widget.socket.id}');
    print('[CallScreen] Partner ID: ${widget.partnerId}');
    print('[CallScreen] Current User ID: ${widget.currentUserId}');
    print('[CallScreen] Is incoming: ${widget.isIncoming}');
    
    // Add comprehensive logging for all socket events
    widget.socket.onAny((event, data) {
      print('[CallScreen] 🔔 Socket event: $event, data: $data');
    });
    
    // Verify socket is connected before setting up listeners
    if (!widget.socket.connected) {
      print('[CallScreen] ⚠️ WARNING: Socket is not connected when setting up listeners!');
      print('[CallScreen] Socket state: ${widget.socket.connected}');
      print('[CallScreen] Socket ID: ${widget.socket.id}');
    } else {
      print('[CallScreen] ✅ Socket is connected, setting up listeners');
      
      
    }
    
    // Listen for call offers (for incoming calls)
    widget.socket.on('call_offer', (data) {
      print('[CallScreen] 📞 Received call_offer event: $data');
      print('[CallScreen] Offer callId: ${data['callId']}, our callId: ${widget.callId}');
      print('[CallScreen] Offer from: ${data['from']}, our partnerId: ${widget.partnerId}');
      print('[CallScreen] Offer data keys: ${data.keys.toList()}');
      print('[CallScreen] Offer isVideo: ${data['isVideo']}');
      
      if (mounted && data['callId'] == widget.callId && data['from'] == widget.partnerId) {
        print('[CallScreen] ✅ Processing call offer from partner');
        final offer = data['offer'];
        if (offer != null && widget.isIncoming) {
          print('[CallScreen] 🎯 Answering incoming call with received offer');
          _webrtcService.answerCall(
            partnerId: widget.partnerId,
            callId: widget.callId,
            isVideo: widget.isVideo,
            offer: offer,
            socket: widget.socket,
            currentUserId: widget.currentUserId,
          );
        } else {
          print('[CallScreen] ⚠️ Not answering - offer is null or not incoming call');
        }
      } else {
        print('[CallScreen] ❌ Ignoring call offer - mounted: $mounted, callId match: ${data['callId'] == widget.callId}, from match: ${data['from'] == widget.partnerId}');
        print('[CallScreen] Call ID comparison: "${data['callId']}" == "${widget.callId}" = ${data['callId'] == widget.callId}');
        print('[CallScreen] From comparison: "${data['from']}" == "${widget.partnerId}" = ${data['from'] == widget.partnerId}');
      }
    });
    
    // Listen for call answers (for outgoing calls)
    widget.socket.on('call_answer', (data) {
      print('[CallScreen] 📞 Received call_answer event: $data');
      if (mounted && data['callId'] == widget.callId && data['from'] == widget.partnerId) {
        print('[CallScreen] ✅ Processing call answer for our call');
        _webrtcService.handleAnswer(data['answer']);
      } else {
        print('[CallScreen] ❌ Ignoring call answer - mounted: $mounted, callId match: ${data['callId'] == widget.callId}, from match: ${data['from'] == widget.partnerId}');
      }
    });
    
    // Listen for ICE candidates
    widget.socket.on('ice_candidate', (data) {
      print('[CallScreen] 🧊 Received ice_candidate event: $data');
      if (mounted && data['from'] == widget.partnerId) {
        print('[CallScreen] ✅ Processing ICE candidate from partner');
        _webrtcService.handleIceCandidate(data['candidate']);
      } else {
        print('[CallScreen] ❌ Ignoring ICE candidate - mounted: $mounted, from match: ${data['from'] == widget.partnerId}');
      }
    });
    
    // Listen for call end
    widget.socket.on('call_end', (data) {
      print('[CallScreen] 📞 Received call_end event: $data');
      if (mounted && (data['callId'] == widget.callId || data['from'] == widget.partnerId)) {
        print('[CallScreen] ✅ Call ended by remote party');
        _endCall();
      } else {
        print('[CallScreen] ❌ Ignoring call end - mounted: $mounted, callId match: ${data['callId'] == widget.callId}, from match: ${data['from'] == widget.partnerId}');
      }
    });
    
    // Listen for call answered notification (for outgoing calls)
    widget.socket.on('call_answered', (data) {
      print('[CallScreen] 📞 Received call_answered notification: $data');
      if (mounted && data['callId'] == widget.callId && data['from'] == widget.partnerId) {
        print('[CallScreen] ✅ Call was answered by partner');
        setState(() => _callState = CallState.connected);
      }
    });
    
    // CRITICAL FIX: Listen for server instruction to start WebRTC offer (for outgoing calls)
    widget.socket.on('start_webrtc_offer', (data) {
      print('[CallScreen] 🚀 Received start_webrtc_offer event: $data');
      print('[CallScreen] Partner ID: ${data['partnerId']}, our partnerId: ${widget.partnerId}');
      print('[CallScreen] Call ID: ${data['callId']}, our callId: ${widget.callId}');
      print('[CallScreen] Is outgoing call: ${!widget.isIncoming}');
      
      if (mounted && 
          data['callId'] == widget.callId && 
          data['partnerId'] == widget.partnerId && 
          !widget.isIncoming) {
        print('[CallScreen] ✅ Starting WebRTC offer process as instructed by server');
        // The call was answered, now start the WebRTC offer process
        _webrtcService.startCall(
          partnerId: widget.partnerId,
          callId: widget.callId,
          isVideo: widget.isVideo,
          socket: widget.socket,
          currentUserId: widget.currentUserId,
        );
      } else {
        print('[CallScreen] ❌ Ignoring start_webrtc_offer - mounted: $mounted, callId match: ${data['callId'] == widget.callId}, partnerId match: ${data['partnerId'] == widget.partnerId}, is outgoing: ${!widget.isIncoming}');
      }
    });
    

    
    // Listen for socket disconnection
    widget.socket.onDisconnect((reason) {
      print('[CallScreen] ⚠️ Socket disconnected during call! Reason: $reason');
      print('[CallScreen] Socket state - connected: ${widget.socket.connected}, id: ${widget.socket.id}');
      if (mounted) {
        setState(() => _callState = CallState.ended);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection lost: ${reason ?? "Unknown"}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    });
    
    // Listen for socket reconnection
    widget.socket.onConnect((_) {
      print('[CallScreen] 🔄 Socket reconnected during call!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection restored'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
    
    // Listen for connection errors
    widget.socket.onError((error) {
      print('[CallScreen] ❌ Socket error during call: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $error'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    print('[CallScreen] Disposing call screen for call ${widget.callId}');
    _callTimer?.cancel();
    _connectionMonitor?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _webrtcService.dispose();
    // Clean up all socket listeners
    widget.socket.off('call_offer');
    widget.socket.off('call_answer');
    widget.socket.off('ice_candidate');
    widget.socket.off('call_end');
    widget.socket.off('call_answered');
    widget.socket.off('start_webrtc_offer');
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
