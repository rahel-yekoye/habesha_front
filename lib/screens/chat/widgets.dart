import 'package:chat_app_flutter/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:gallery_saver/gallery_saver.dart';
import '../../models/message.dart' as models;
import 'package:path/path.dart' as path; // add this for basename extraction
import 'dart:html' as html;

Widget chatInputField({
  required TextEditingController controller,
  required FocusNode focusNode,
  required VoidCallback onSend,
  required bool showEmojiPicker,
  required VoidCallback onEmojiToggle,
  required List<PlatformFile> selectedFiles,
  required void Function(int) onRemoveFile,
  required Future<List<PlatformFile>?> Function() pickFiles,
  models.Message? replyingTo,
  VoidCallback? onCancelReply,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (replyingTo != null)
        Container(
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: Colors.blue, width: 3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Replying to ${replyingTo.sender}', 
                      style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                    Text(replyingTo.content.isNotEmpty ? replyingTo.content : 'File', 
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18),
                onPressed: onCancelReply,
              ),
            ],
          ),
        ),
      if (selectedFiles.isNotEmpty)
        SizedBox(
          height: 70,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: selectedFiles.length,
            itemBuilder: (context, index) {
              final file = selectedFiles[index];
              return Stack(
                children: [
                  Container(
                    margin: const EdgeInsets.all(8),
                    width: 60,
                    height: 60,
                    color: Colors.grey[300],
                    child: Center(child: Text(file.name)),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () => onRemoveFile(index),
                      child: const CircleAvatar(
                        radius: 10,
                        backgroundColor: Colors.red,
                        child: Icon(Icons.close, size: 12, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
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
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Type a message',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.attach_file),
            onPressed: () async {
              final files = await pickFiles();
              if (files != null && files.isNotEmpty) {
                // User's onAddFiles callback in main widget
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: onSend,
          ),
        ],
      ),
      if (showEmojiPicker)
        SizedBox(
          height: 250,
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) {
              controller.text += emoji.emoji;
              controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length));
            },
          ),
        ),
    ],
  );
}

Widget buildPopupMenu(
  models.Message msg, {
  required Offset position,
  required void Function(models.Message) onCopy,
  required void Function(models.Message) onEdit,
  required void Function(models.Message, bool forEveryone) onDelete,
  required void Function(models.Message, String emoji) onReact,
  required void Function(models.Message)? onReply,
  required VoidCallback onDismiss,
  required bool isCurrentUser,
}) {
  // Common emojis for quick reactions
  final List<String> quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  return Positioned(
    left: position.dx,
    top: position.dy,
    child: Material(
      elevation: 4,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick reactions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              width: 200,
              child: Wrap(
                spacing: 8,
                children: quickReactions.map((emoji) => GestureDetector(
                  onTap: () {
                    onReact(msg, emoji);
                    onDismiss();
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                )).toList(),
              ),
            ),
            const Divider(height: 1, thickness: 1),
            // Action buttons
            if (isCurrentUser) _buildMenuItem(
              icon: Icons.edit,
              label: 'Edit',
              onTap: () => onEdit(msg),
            ),
            _buildMenuItem(
              icon: Icons.copy,
              label: 'Copy',
              onTap: () => onCopy(msg),
            ),
            if (onReply != null) _buildMenuItem(
              icon: Icons.reply,
              label: 'Reply',
              onTap: () => onReply(msg),
            ),
            if (isCurrentUser) PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.delete_outline, size: 20),
              onSelected: (value) {
                onDelete(msg, value == 'forEveryone');
                onDismiss();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'forMe',
                  child: Text('Delete for me'),
                ),
                const PopupMenuItem(
                  value: 'forEveryone',
                  child: Text('Delete for everyone'),
                ),
              ],
              child: _buildMenuItem(
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: null, // Will be handled by PopupMenuButton
              ),
            ) else _buildMenuItem(
              icon: Icons.delete_outline,
              label: 'Delete',
              onTap: () => onDelete(msg, false),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildMenuItem({
  required IconData icon,
  required String label,
  required VoidCallback? onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    ),
  );
}

Widget buildMessageContent(
  models.Message msg,
  String? editingMessageId,
  TextEditingController editController, {
  required VoidCallback onEditCancel,
  required Future<void> Function(String) onEditSave,
  models.Message? Function(String)? getMessageById,
  Function(models.Message)? onReactionTap,
}) {
  final isEditing = editingMessageId == msg.id;
  
  // Build reply preview if this message is a reply
  Widget? replyPreview;
  if (msg.replyTo != null && getMessageById != null) {
    final repliedMessage = getMessageById(msg.replyTo!);
    if (repliedMessage != null) {
      final previewText = repliedMessage.content.isNotEmpty 
          ? repliedMessage.content 
          : repliedMessage.fileUrl != null 
              ? 'File' 
              : 'Message';
              
      replyPreview = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8.0),
        margin: const EdgeInsets.only(bottom: 4.0),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8.0),
          border: Border(
            left: BorderSide(
              color: Colors.blue,
              width: 3.0,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Replying to ${repliedMessage.sender.split('@')[0]}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.0,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 4.0),
            Text(
              previewText.length > 50 
                  ? '${previewText.substring(0, 50)}...' 
                  : previewText,
              style: const TextStyle(fontSize: 14.0),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
  }

  if (isEditing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (replyPreview != null) replyPreview,
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
                  onPressed: onEditCancel,
                ),
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () async {
                    final text = editController.text.trim();
                    if (text.isNotEmpty) {
                      await onEditSave(text);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  } else {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (replyPreview != null) replyPreview,
        if (msg.fileUrl.isNotEmpty)
          _buildFilePreview(msg.fileUrl),
        if (msg.content.isNotEmpty) Text(msg.content),
        if (msg.reactions.isNotEmpty) 
          _buildReactionsDisplay(msg, onReactionTap),
      ],
    );
  }
}
Widget _buildReactionsDisplay(models.Message msg, Function(models.Message)? onReactionTap) {
  // Check if we have any reactions
  if ((msg.reactions.isEmpty) && 
      (msg.emojis.isEmpty)) {
    return const SizedBox.shrink();
  }
  
  // Group reactions by emoji and count them
  final Map<String, int> emojiCounts = {};
  
  // Process reactions (from backend)
  for (final reaction in msg.reactions) {
    if (reaction['emoji'] is String) {
      final emoji = reaction['emoji'] as String;
      if (emoji.isNotEmpty) {
        emojiCounts[emoji] = (emojiCounts[emoji] ?? 0) + 1;
      }
    }
  }
  
  // Fall back to emojis if no reactions found (legacy support)
  if (emojiCounts.isEmpty) {
    for (final emoji in msg.emojis) {
      if (emoji.isNotEmpty) {
        emojiCounts[emoji] = (emojiCounts[emoji] ?? 0) + 1;
      }
    }
  }
  
  if (emojiCounts.isEmpty) return const SizedBox.shrink();
  
  return Container(
    margin: const EdgeInsets.only(top: 4),
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: emojiCounts.entries.map((entry) {
        final emoji = entry.key;
        final count = entry.value;
        
        return GestureDetector(
          onTap: () => onReactionTap?.call(msg),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                if (count > 1) ...[
                  const SizedBox(width: 4),
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );
}

Widget _buildFilePreview(String fileUrl) {
  final isImage = fileUrl.endsWith('.jpg') ||
      fileUrl.endsWith('.jpeg') ||
      fileUrl.endsWith('.png') ||
      fileUrl.endsWith('.gif') ||
      fileUrl.endsWith('.webp');
  final fileName = path.basename(Uri.parse(fileUrl).path);

  final isVideo = fileUrl.endsWith('.mp4') || fileUrl.endsWith('.webm');
  final isAudio = fileUrl.endsWith('.mp3') || fileUrl.endsWith('.wav');

  if (isVideo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineVideoPlayer(url: fileUrl),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.download),
              label: const Text("Download"),
              onPressed: () => _downloadFile(fileUrl),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text("Save"),
              onPressed: () => _saveFileToGalleryOrDevice(fileUrl, fileName),
            ),
          ],
        ),
      ],
    );
  } else if (isAudio) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineAudioPlayer(url: fileUrl),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.download),
              label: const Text("Download"),
              onPressed: () => _downloadFile(fileUrl),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text("Save"),
              onPressed: () => _saveFileToGalleryOrDevice(fileUrl, fileName),
            ),
          ],
        ),
      ],
    );
  } else if (isImage) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: navigatorKey.currentContext!, // Make sure navigatorKey is defined
          builder: (_) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.network(fileUrl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text("Download"),
                      onPressed: () => _downloadFile(fileUrl),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.save_alt),
                      label: const Text("Save"),
                      onPressed: () => _saveFileToGalleryOrDevice(fileUrl, fileName),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            fileUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stackTrace) =>
                const Text('❌ Failed to load image'),
          ),
        ),
      ),
    );
  } else {
    // Other file types
    return Row(
      children: [
        const Icon(Icons.attach_file),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            fileName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.download),
          label: const Text("Download"),
          onPressed: () => _downloadFile(fileUrl),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          icon: const Icon(Icons.save_alt),
          label: const Text("Save"),
          onPressed: () => _saveFileToGalleryOrDevice(fileUrl, fileName),
        ),
      ],
    );
  }
}

// Example placeholder functions for saving file to gallery or device.
// You should implement these to fit your app's logic and platform support.

Future<void> _saveFileToGalleryOrDevice(String url, String fileName) async {
  if (kIsWeb) {
    // Web: trigger browser download
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
  } else {
    // Mobile / Android: save file using Dio + GallerySaver or open file
    try {
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/$fileName';

      final response = await Dio().download(url, savePath);

      if (response.statusCode == 200) {
        final isImage = fileName.endsWith('.jpg') || fileName.endsWith('.png') || fileName.endsWith('.jpeg');
        final isVideo = fileName.endsWith('.mp4') || fileName.endsWith('.mov');
        if (isImage) {
          await GallerySaver.saveImage(savePath);
          debugPrint('✅ Image saved to gallery: $fileName');
        } else if (isVideo) {
          await GallerySaver.saveVideo(savePath);
          debugPrint('✅ Video saved to gallery: $fileName');
        } else {
          await OpenFilex.open(savePath);
          debugPrint('✅ File opened: $fileName');
        }
      } else {
        debugPrint('❌ Failed to download file.');
      }
    } catch (e) {
      debugPrint('❌ Download error: $e');
    }
  }
}


Future<void> _downloadFile(String url) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = url.split('/').last;
    final savePath = '${dir.path}/$fileName';

    final response = await Dio().download(url, savePath);

    if (response.statusCode == 200) {
      final isImage = fileName.endsWith('.jpg') || fileName.endsWith('.png');
      if (isImage) {
        await GallerySaver.saveImage(savePath);
        debugPrint('✅ Image saved to gallery: $fileName');
      } else {
        await OpenFilex.open(savePath);
        debugPrint('✅ File opened: $fileName');
      }

      // Optional snackbar (requires BuildContext passed)
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text('Downloaded: $fileName')),
      // );
    } else {
      debugPrint('❌ Failed to download file.');
    }
  } catch (e) {
    debugPrint('❌ Download error: $e');
  }
}

class InlineVideoPlayer extends StatefulWidget {
  final String url;
  const InlineVideoPlayer({super.key, required this.url});

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late VideoPlayerController _videoController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.network(widget.url)
      ..initialize().then((_) {
        setState(() {
          _initialized = true;
        });
      });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return AspectRatio(
      aspectRatio: _videoController.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_videoController),
          VideoProgressIndicator(_videoController, allowScrubbing: true),
          Positioned(
            bottom: 8,
            right: 8,
            child: IconButton(
              icon: Icon(
                _videoController.value.isPlaying
                    ? Icons.pause_circle
                    : Icons.play_circle,
                size: 30,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  if (_videoController.value.isPlaying) {
                    _videoController.pause();
                  } else {
                    _videoController.play();
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class InlineAudioPlayer extends StatefulWidget {
  final String url;
  const InlineAudioPlayer({super.key, required this.url});

  @override
  State<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();

    _audioPlayer.onPlayerStateChanged.listen((state) {
         if (!mounted) return;
      setState(() {
        _isPlaying = state == ap.PlayerState.playing;
      });
    });

    _audioPlayer.onDurationChanged.listen((d) {
        if (!mounted) return;
      setState(() {
        _duration = d;
      });
    });

    _audioPlayer.onPositionChanged.listen((p) {
         if (!mounted) return;
      setState(() {
        _position = p;
      });
    });
  _initAudio();
  }
Future<void> _initAudio() async {
  try {
    await _audioPlayer
        .setSourceUrl(widget.url)
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    print('❌ Failed to load audio from ${widget.url}: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio failed to load')),
      );
    }
  }  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Slider(
          min: 0,
          max: _duration.inMilliseconds.toDouble(),
          value: _position.inMilliseconds.clamp(0, _duration.inMilliseconds).toDouble(),
          onChanged: (value) {
            _audioPlayer.seek(Duration(milliseconds: value.toInt()));
          },
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                if (_isPlaying) {
                  _audioPlayer.pause();
                } else {
                  _audioPlayer.resume();
                }
              },
            ),
            Text('${_position.inSeconds}/${_duration.inSeconds} sec'),
          ],
        ),
      ],
    );
  }
}



/// A chat bubble for group messages, with sender, time, edit, delete, selection, etc.
class GroupMessageBubble extends StatelessWidget {
  final models.Message message;
  final bool isSender;
  final bool isSelected;
  final String? editingMessageId;
  final TextEditingController? editController;
  final VoidCallback? onTap;
  final void Function(LongPressStartDetails)? onLongPress;
  final Future<void> Function(String)? onEdit;
  final VoidCallback? onDelete;
  final String Function(String)? usernameResolver;
  final models.Message? Function(String)? getMessageById;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.isSender,
    this.isSelected = false,
    this.editingMessageId,
    this.editController,
    this.onTap,
    this.onLongPress,
    this.onEdit,
    this.onDelete,
    this.usernameResolver,
    this.getMessageById,
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
          child: buildMessageContent(
            message,
            isEditing ? message.id : null,
            editController ?? TextEditingController(text: message.content),
            onEditCancel: () {
              if (onEdit != null) {
                onEdit!(message.id);
              }
            },
            onEditSave: (newText) async {
              if (onEdit != null) {
                await onEdit!(newText);
              }
            },
            getMessageById: getMessageById,
            onReactionTap: (msg) {
              // This will be handled by the chat screen's _showReactionPicker
            },
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

Widget GroupChatInputField({
  required TextEditingController controller,
  required FocusNode focusNode,
  required VoidCallback onSend,
  required bool showEmojiPicker,
  required VoidCallback onEmojiToggle,
  required List<PlatformFile> selectedFiles,
  required void Function(int) onRemoveFile,
  required Future<List<PlatformFile>?> Function() pickFiles,
}) =>
    chatInputField(
      controller: controller,
      focusNode: focusNode,
      onSend: onSend,
      showEmojiPicker: showEmojiPicker,
      onEmojiToggle: onEmojiToggle,
      selectedFiles: selectedFiles,
      onRemoveFile: onRemoveFile,
      pickFiles: pickFiles,
    );
