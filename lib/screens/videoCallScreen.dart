import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoCallScreen extends StatefulWidget {
  final MediaStream localStream;
  final MediaStream? remoteStream;
  final VoidCallback onEndCall;
  final void Function(bool muted) onToggleMute;
  final VoidCallback onSwitchCamera;
  final void Function(bool speakerOn) onToggleSpeaker;

  const VideoCallScreen({
    super.key,
    required this.localStream,
    this.remoteStream,
    required this.onEndCall,
    required this.onToggleMute,
    required this.onSwitchCamera,
    required this.onToggleSpeaker,
  });

  @override
  _VideoCallScreenState createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _muted = false;
  bool _speakerOn = true;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _localRenderer.srcObject = widget.localStream;

    if (widget.remoteStream != null) {
      _remoteRenderer.srcObject = widget.remoteStream;

      // 🧠 Optional: Listen for remote track addition
      widget.remoteStream!.onAddTrack = (MediaStreamTrack track) {
        print('[VideoCallScreen] 🟢 Remote track added: ${track.kind}');
        _remoteRenderer.srcObject = widget.remoteStream;
        setState(() {}); // refresh UI
      };
    }

    setState(() {});
  }

  @override
  void didUpdateWidget(covariant VideoCallScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.remoteStream != oldWidget.remoteStream &&
        widget.remoteStream != null) {
      print('[VideoCallScreen] 🔁 Remote stream updated.');
      _remoteRenderer.srcObject = widget.remoteStream;

      // Re-attach track listener
      widget.remoteStream!.onAddTrack = (track) {
        print(
            '[VideoCallScreen] 🔄 Track added to updated stream: ${track.kind}');
        _remoteRenderer.srcObject = widget.remoteStream;
        setState(() {});
      };

      setState(() {});
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    widget.onToggleMute(_muted);
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    widget.onToggleSpeaker(_speakerOn);
  }

  @override
  Widget build(BuildContext context) {
    final localVideo = SizedBox(
      width: 120,
      height: 160,
      child: RTCVideoView(
        _localRenderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );

    final remoteVideo = Expanded(
      child: widget.remoteStream == null
          ? const Center(
              child: Text('Waiting for remote video...',
                  style: TextStyle(color: Colors.white)))
          : RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            remoteVideo,
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white54, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: localVideo,
              ),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      _muted ? Icons.mic_off : Icons.mic,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: _toggleMute,
                    tooltip: _muted ? 'Unmute' : 'Mute',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.cameraswitch,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: widget.onSwitchCamera,
                    tooltip: 'Switch Camera',
                  ),
                  FloatingActionButton(
                    backgroundColor: Colors.red,
                    onPressed: widget.onEndCall,
                    heroTag: 'endCallBtn',
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                  IconButton(
                    icon: Icon(
                      _speakerOn ? Icons.volume_up : Icons.volume_off,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: _toggleSpeaker,
                    tooltip: _speakerOn ? 'Speaker On' : 'Speaker Off',
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
