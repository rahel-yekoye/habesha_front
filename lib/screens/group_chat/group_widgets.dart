import 'dart:io';

import 'package:chat_app_flutter/screens/chat/widgets.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/message.dart' as models;
// For InlineVideoPlayer, InlineAudioPlayer
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart'; // Add this import at the top
// Message bubble widget
class GroupMessageBubble extends StatelessWidget {
  final models.Message message;
  final bool isSender;
  final bool isSelected;
  final String? editingMessageId;
  final TextEditingController? editController;
  final void Function(LongPressStartDetails)? onLongPress;
  final VoidCallback? onTap;
  final Future<void> Function(String)? onEdit;
  final VoidCallback? onDelete;
  final String Function(String)? usernameResolver;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.isSender,
    this.isSelected = false,
    this.editingMessageId,
    this.editController,
    this.onLongPress,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.usernameResolver,
  });

  @override
  Widget build(BuildContext context) {
    final isEditing = editingMessageId == message.id;
    final bubbleColor = isSender
        ? (isSelected ? Colors.blue[400] : Colors.blue[200])
        : (isSelected ? Colors.grey[400] : Colors.grey[300]);
    final align = isSender ? Alignment.centerRight : Alignment.centerLeft;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isSender ? 16 : 0),
      bottomRight: Radius.circular(isSender ? 0 : 16),
    );

    return Align(
      alignment: align,
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: borderRadius,
            border: isSelected
                ? Border.all(color: Colors.blueAccent, width: 2)
                : null,
          ),
          child: isEditing && editController != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TextField(
                      controller: editController,
                      maxLines: null,
                      autofocus: true,
                      decoration: InputDecoration(
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.cancel),
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                editController?.clear();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.save),
                              onPressed: () async {
                                final text = editController!.text.trim();
                                if (text.isNotEmpty && onEdit != null) {
                                  await onEdit!(text);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isSender && usernameResolver != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2.0),
                        child: Text(
                          usernameResolver!(message.sender),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    if (message.fileUrl.isNotEmpty)
                      buildFilePreview(context, message),
                    Text(
                      message.content,
                      style: const TextStyle(fontSize: 16),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(message.timestamp),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54),
                        ),
                        if (onDelete != null)
                          IconButton(
                            icon: const Icon(Icons.delete, size: 16),
                            onPressed: onDelete,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

String _formatTime(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  } catch (_) {
    return '';
  }
}

// Input field widget
class GroupChatInputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool showEmojiPicker;
  final VoidCallback onEmojiToggle;
  final List<PlatformFile> selectedFiles;
  final void Function(int) onRemoveFile;
  final Future<List<PlatformFile>?> Function() pickFiles;
  final bool canSend;

  const GroupChatInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.showEmojiPicker,
    required this.onEmojiToggle,
    required this.selectedFiles,
    required this.onRemoveFile,
    required this.pickFiles,
    required this.canSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (selectedFiles.isNotEmpty)
          buildFilesPreview(selectedFiles, onRemoveFile),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined),
              onPressed: onEmojiToggle,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                minLines: 1,
                maxLines: 5,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: () async {
                await pickFiles();
              },
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: (canSend) ? onSend : null,
            ),
          ],
        ),
        if (showEmojiPicker)
          SizedBox(
            height: 250,
            child: Center(child: Text('Emoji picker here')), // Replace with your emoji picker widget
          ),
      ],
    );
  }
}

// Popup menu widget
Widget buildGroupPopupMenu({
  required BuildContext context,
  required models.Message message,
  required VoidCallback onCopy,
  required VoidCallback onEdit,
  required VoidCallback onDismiss,
  required Offset position,
  required bool isMe,
}) {
  return Positioned(
    left: position.dx,
    top: position.dy,
    child: Material(
      elevation: 4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy'),
            onTap: onCopy,
          ),
          if (isMe)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: onEdit,
            ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Dismiss'),
            onTap: onDismiss,
          ),
        ],
      ),
    ),
  );
}

// File preview widget for a message
Widget buildFilePreview(BuildContext context, models.Message msg) {
  if (msg.fileUrl.isEmpty) return const SizedBox.shrink();
  final ext = msg.fileUrl.split('.').last.toLowerCase();
  final fileName = msg.fileUrl.split('/').last;

  if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => Dialog(
              child: InteractiveViewer(
                child: Image.network(msg.fileUrl),
              ),
            ),
          );
        },
        child: Image.network(msg.fileUrl, width: 180, fit: BoxFit.cover),
      ),
    );
  }

  // --- Video preview and dialog ---
  if (['mp4', 'mov', 'webm', 'avi'].contains(ext)) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => Dialog(
              child: _VideoDialogPlayer(url: msg.fileUrl),
            ),
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 180,
              height: 120,
              color: Colors.black12,
              child: const Icon(Icons.videocam, size: 48, color: Colors.black45),
            ),
            const Icon(Icons.play_circle_fill, size: 48, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  if (['mp3', 'wav', 'ogg', 'aac', 'm4a'].contains(ext)) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: GestureDetector(
        onTap: () => downloadAndOpenFile(context, msg.fileUrl, fileName),
        child: InlineAudioPlayer(url: msg.fileUrl),
      ),
    );
  }
  // For other files
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      children: [
        const Icon(Icons.insert_drive_file),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => downloadAndOpenFile(context, msg.fileUrl, fileName),
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        ),
      ],
    ),
  );
}

// File preview widget for selected files before sending
Widget buildFilesPreview(List<PlatformFile> files, void Function(int) onRemove) {
  return SizedBox(
    height: 80,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final ext = file.extension?.toLowerCase() ?? '';
        Widget preview;
        if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
          if (file.bytes != null) {
            // For web: use bytes
            preview = Image.memory(
              file.bytes!,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
            );
          } else if (file.path != null) {
            // For mobile/desktop: use file path
            preview = Image.file(
              File(file.path!),
              width: 70,
              height: 70,
              fit: BoxFit.cover,
            );
          } else {
            preview = Container(
              width: 70,
              height: 70,
              color: Colors.grey[300],
              child: Icon(Icons.insert_drive_file, size: 40),
            );
          }
        } else {
          preview = Container(
            width: 70,
            height: 70,
            color: Colors.grey[300],
            child: Icon(Icons.insert_drive_file, size: 40),
          );
        }
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: preview,
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => onRemove(index),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

// Group info bottom sheet
Widget buildGroupInfoSheet({
  required String groupName,
  required String groupDescription,
  required List<dynamic> groupMembers,
  required String Function(String) getUsername,
}) {
  return Padding(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(groupName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(groupDescription, style: const TextStyle(fontSize: 16)),
        const Divider(),
        const Text('Members:', style: TextStyle(fontWeight: FontWeight.bold)),
        ...groupMembers.map((m) => Text(getUsername(m.toString()))),
      ],
    ),
  );
}
// AppBar builder
PreferredSizeWidget buildGroupAppBar({
  required BuildContext context,
  required String groupName,
  required bool isSelectionMode,
  required VoidCallback onCloseSelection,
  required VoidCallback onDeleteSelected,
  required VoidCallback onShowInfo,
}) {
  return AppBar(
    title: Text(groupName),
    actions: [
      if (isSelectionMode)
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: onCloseSelection,
        ),
      if (isSelectionMode)
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: onDeleteSelected,
        ),
      IconButton(
        icon: const Icon(Icons.info_outline),
        onPressed: onShowInfo,
      ),
    ],
  );
  
}Future<void> downloadAndOpenFile(BuildContext context, String url, String fileName) async {
  try {
    // Request storage permission
    if (await Permission.storage.request().isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission denied')),
      );
      return;
    }
    final dir = await getExternalStorageDirectory();
    final savePath = '${dir!.path}/$fileName';
    await Dio().download(url, savePath);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloaded to $savePath')),
    );
    await OpenFile.open(savePath);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to download/open: $e')),
    );
  }
}
class _VideoDialogPlayer extends StatefulWidget {
  final String url;

  const _VideoDialogPlayer({required this.url});

  @override
  __VideoDialogPlayerState createState() => __VideoDialogPlayerState();
}

class __VideoDialogPlayerState extends State<_VideoDialogPlayer> {
  late VideoPlayerController _controller;
  late Future<void> _initializeVideoPlayerFuture;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url);
    _initializeVideoPlayerFuture = _controller.initialize().then((_) {
      setState(() {}); // Refresh UI after starting playback
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializeVideoPlayerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                VideoPlayer(_controller),
                _ControlsOverlay(controller: _controller),
                VideoProgressIndicator(_controller, allowScrubbing: true),
              ],
            ),
          );
        } else {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }
      },
    );
  }
}
class _ControlsOverlay extends StatefulWidget {
  final VideoPlayerController controller;

  const _ControlsOverlay({required this.controller});

  @override
  __ControlsOverlayState createState() => __ControlsOverlayState();
}

class __ControlsOverlayState extends State<_ControlsOverlay> {
  late VideoPlayerController controller;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
    controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    if (mounted) {
      setState(() {
        // Rebuild on controller state changes
      });
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
      },
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: Icon(
            controller.value.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            color: Colors.white70,
            size: 64,
          ),
        ),
      ),
    );
  }
}
