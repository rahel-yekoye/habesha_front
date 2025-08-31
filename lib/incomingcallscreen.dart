import 'package:flutter/material.dart';

class IncomingCallScreen extends StatelessWidget {
  final String callerName;
  final bool voiceOnly;
  final Future<void> Function() onAccept;
  final VoidCallback onDecline;

  const IncomingCallScreen({
    super.key,
    required this.callerName,
    required this.voiceOnly,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              voiceOnly ? Icons.call : Icons.videocam,
              size: 100,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            Text(
              '$callerName is calling',
              style: const TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: onDecline,
                  icon: const Icon(Icons.call_end),
                  label: const Text('Decline'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // First pop the current screen
                    Navigator.pop(context);
                    // Then wait until after this frame to push the next screen
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      await onAccept();
                    });
                  },
                  icon: const Icon(Icons.call),
                  label: const Text('Accept'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
