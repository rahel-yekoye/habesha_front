import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;


class WebRTCService {
  // Remove singleton pattern to allow multiple instances
  WebRTCService();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  String? _currentCallId;
  String? _currentPartnerId;
  bool _isInCall = false;
  

  
  // Callbacks
  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;
  Function()? onCallConnected;
  Function(String)? onCallEnded;
  Function()? onWebRTCConnected; // New callback for when WebRTC connection is established
  Function()? onCallDeclined;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // Initialize WebRTC
  Future<void> initialize() async {
    print('[WebRTC] Initializing WebRTC service');
  }

  // Start a call (caller)
  Future<void> startCall({
    required String partnerId,
    required String callId,
    required bool isVideo,
    required IO.Socket socket,
    required String currentUserId,
  }) async {
    print('[WebRTC] ===== STARTING WEBRTC CALL =====');
    print('[WebRTC] Partner ID: $partnerId');
    print('[WebRTC] Current User ID: $currentUserId');
    print('[WebRTC] Call ID: $callId');
    print('[WebRTC] Is Video: $isVideo');
    print('[WebRTC] Starting ${isVideo ? 'video' : 'voice'} call to $partnerId');
    
    _currentCallId = callId;
    _currentPartnerId = partnerId;
    _isInCall = true;

    try {
      // Get user media
      _localStream = await _getUserMedia(isVideo: isVideo);
      onLocalStream?.call(_localStream!);

      // Create peer connection
      await _createPeerConnection(socket, currentUserId);

      // Add local stream tracks
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Create and send offer
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      print('[WebRTC] Sending call offer to $partnerId');
      print('[WebRTC] Offer data: ${offer.toMap()}');
      print('[WebRTC] Call ID: $callId');
      print('[WebRTC] Is Video: $isVideo');
      print('[WebRTC] Current User ID: $currentUserId');
      print('[WebRTC] Partner ID: $partnerId');
      
      // Send the offer
      socket.emit('call_offer', {
        'to': partnerId,
        'from': currentUserId,
        'offer': offer.toMap(),
        'callId': callId,
        'isVideo': isVideo,
      });
      
      print('[WebRTC] ✅ call_offer event emitted to socket');

    } catch (e) {
      print('[WebRTC] Error starting call: $e');
      endCall(socket, currentUserId);
    }
  }

  // Answer a call (callee)
  Future<void> answerCall({
    required String partnerId,
    required String callId,
    required bool isVideo,
    required Map<String, dynamic> offer,
    required IO.Socket socket,
    required String currentUserId,
  }) async {
    print('[WebRTC] Answering ${isVideo ? 'video' : 'voice'} call from $partnerId');
    
    _currentCallId = callId;
    _currentPartnerId = partnerId;
    _isInCall = true;

    try {
      // Get user media
      _localStream = await _getUserMedia(isVideo: isVideo);
      onLocalStream?.call(_localStream!);

      // Create peer connection
      await _createPeerConnection(socket, currentUserId);

      // Add local stream tracks
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Set remote description (offer)
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type'])
      );

      // Create and send answer
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      print('[WebRTC] Sending call answer to $partnerId');
      socket.emit('call_answer', {
        'to': partnerId,
        'from': currentUserId,
        'answer': answer.toMap(),
        'callId': callId,
      });

      // Don't notify call_answered immediately - wait for WebRTC connection to be established
      print('[WebRTC] Call answered, waiting for WebRTC connection to be established before notifying');

    } catch (e) {
      print('[WebRTC] Error answering call: $e');
      endCall(socket, currentUserId);
    }
  }



  // Handle received answer (caller)
  Future<void> handleAnswer(Map<String, dynamic> answer) async {
    print('[WebRTC] Received answer from remote peer');
    
    if (_peerConnection == null) {
      print('[WebRTC] ERROR: Peer connection is null, cannot set remote description');
      return;
    }
    
    try {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type'])
      );
      print('[WebRTC] Answer set successfully');
    } catch (e) {
      print('[WebRTC] Error setting remote description: $e');
      onCallEnded?.call('Failed to establish connection');
    }
  }

  // Handle ICE candidate
  Future<void> handleIceCandidate(Map<String, dynamic> candidate) async {
    print('[WebRTC] Received ICE candidate');
    
    if (_peerConnection == null) {
      print('[WebRTC] ERROR: Peer connection is null, cannot add ICE candidate');
      return;
    }
    
    try {
      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          candidate['candidate'],
          candidate['sdpMid'],
          candidate['sdpMLineIndex'],
        )
      );
      print('[WebRTC] ICE candidate added successfully');
    } catch (e) {
      print('[WebRTC] Error adding ICE candidate: $e');
    }
  }

  // End call
  void endCall(IO.Socket socket, String currentUserId) {
    print('[WebRTC] Ending call');
    
    if (_currentPartnerId != null && _currentCallId != null) {
      socket.emit('call_end', {
        'to': _currentPartnerId,
        'from': currentUserId,
        'callId': _currentCallId,
      });
    }

    _cleanup();
  }

  // Get user media
  Future<MediaStream> _getUserMedia({required bool isVideo}) async {
    try {
      final Map<String, dynamic> constraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'sampleRate': 48000,
        },
        'video': isVideo ? {
          'width': {'min': 640, 'ideal': 1280, 'max': 1920},
          'height': {'min': 480, 'ideal': 720, 'max': 1080},
          'frameRate': {'min': 15, 'ideal': 30, 'max': 60},
          'facingMode': 'user',
        } : false,
      };

      print('[WebRTC] Requesting user media: ${isVideo ? 'video' : 'audio only'}');
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      print('[WebRTC] User media obtained successfully');
      return stream;
    } catch (e) {
      print('[WebRTC] Error getting user media: $e');
      throw Exception('Failed to access camera/microphone: $e');
    }
  }

  bool _isConnected = false;

  // Toggle mute
  void toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final isEnabled = audioTracks[0].enabled;
        audioTracks[0].enabled = !isEnabled;
        print('[WebRTC] Audio ${!isEnabled ? 'muted' : 'unmuted'}');
      }
    }
  }

  // Toggle video
  void toggleVideo() {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        final isEnabled = videoTracks[0].enabled;
        videoTracks[0].enabled = !isEnabled;
        print('[WebRTC] Video ${!isEnabled ? 'disabled' : 'enabled'}');
      }
    }
  }

  // Switch camera
  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks[0]);
        print('[WebRTC] Camera switched');
      }
    }
  }

  // Cleanup
  void _cleanup() {
    print('[WebRTC] Cleaning up resources');
    
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;
    
    _remoteStream?.dispose();
    _remoteStream = null;
    
    _peerConnection?.close();
    _peerConnection = null;
    
    _currentCallId = null;
    _currentPartnerId = null;
    _isInCall = false;
    _isConnected = false;
  }

  // Dispose
  void dispose() {
    _cleanup();
  }

  // Create peer connection
  Future<void> _createPeerConnection(IO.Socket socket, String currentUserId) async {
    try {
      print('[WebRTC] Creating peer connection');
      _peerConnection = await createPeerConnection(_iceServers);
      print('[WebRTC] Peer connection created successfully');

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (_currentPartnerId != null) {
          print('[WebRTC] Sending ICE candidate to $_currentPartnerId');
          socket.emit('ice_candidate', {
            'to': _currentPartnerId,
            'from': currentUserId,
            'candidate': candidate.toMap(),
            'callId': _currentCallId,
          });
        }
      };

      // Handle remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        print('[WebRTC] Received remote track: ${event.track.kind}');
        
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          onRemoteStream?.call(_remoteStream!);
        }
      };

      // Handle connection state changes
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        print('[WebRTC] Connection state: $state');
        
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          if (!_isConnected) {
            _isConnected = true;
            print('[WebRTC] Triggering onCallConnected callback');
            onCallConnected?.call();
            print('[WebRTC] Triggering onWebRTCConnected callback');
            onWebRTCConnected?.call();
          }
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                   state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          print('[WebRTC] Connection failed or disconnected: $state');
          onCallEnded?.call('Connection failed');
          _cleanup();
        }
      };
    } catch (e) {
      print('[WebRTC] Error creating peer connection: $e');
      throw Exception('Failed to create peer connection: $e');
    }
  }

  // Getters
  bool get isInCall => _isInCall;
  String? get currentCallId => _currentCallId;
  String? get currentPartnerId => _currentPartnerId;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
}
