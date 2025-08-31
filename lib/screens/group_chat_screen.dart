/*import 'dart:async'; // Added for Timer
import 'dart:core';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart'; // Still useful for local files on desktop
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/foundation.dart' show kIsWeb; // For kIsWeb
import 'package:dio/dio.dart'; // For Dio for file downloads
import 'package:permission_handler/permission_handler.dart'; // For permissions
import 'package:file_selector/file_selector.dart'; // For getSavePath
import 'package:flutter/services.dart'; // For Clipboard, and implicitly TextInputAction

import '../models/message.dart' as models; // Import the common message model
import 'chat/widgets.dart';
import 'chat/file_handling.dart';
import 'chat/message_actions.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String groupDescription;
  final String currentUser;
  final String jwtToken;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupDescription,
    required this.currentUser,
    required this.jwtToken,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  List<models.Message> messages = []; // Changed to models.Message
  IO.Socket? socket; // Make it nullable
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool isLoading = true;
  bool _joinedGroup = false;

  bool _showEmojiPicker = false;
  bool _isSelectionMode = false;
  Set<int> _selectedMessageIndices = {}; // Changed to indices for consistency
  List<dynamic> groupMembers = [];
  List<Map<String, dynamic>> allUsers = [];
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, ap.AudioPlayer> _audioPlayers = {};
  final List<PlatformFile> _selectedFiles = []; // For file preview
  List<models.Message> _recentlyDeletedMessages = []; // For undo delete
  Timer? _undoTimer; // For undo delete timer
  String? _editingMessageId; // For message editing
  final TextEditingController _editController =
      TextEditingController(); // For message editing
  Offset? _popupPosition; // For long press popup menu

  @override
  void initState() {
    super.initState();
    _initializeSocket();
    _fetchInitialData();

    _focusNode.addListener(() {
      if (!mounted) return; // Guard against setState after dispose
      if (_focusNode.hasFocus) {
        setState(() => _showEmojiPicker = false);
      }
    });

    _scrollController.addListener(() {
      if (!mounted) return; // Guard against setState after dispose
      _scrollListener();
    });
  }

  void _initializeSocket() {
    // Dispose of existing socket if it's already connected to prevent issues
    if (socket != null) {
      // && socket!.connected
      socket!.disconnect();
      socket!.dispose();
      socket = null;
    }

    socket = IO.io('http://localhost:4000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'randomizationFactor': 0.5,
      'extraHeaders': {'Authorization': 'Bearer ${widget.jwtToken}'},
    });

    socket!.on('disconnect', (_) {
      if (!mounted) return;
      print('Disconnected from Socket.IO - attempting to reconnect');
      // Attempt to reconnect after a delay
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        socket?.connect();
      });
    });

    socket!.on('connect_error', (error) {
      if (!mounted) return; // Guard against setState after dispose
      print('Socket connection error: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection error')),
      );
    });
    _registerSocketListeners();

    socket!.connect(); // Manually connect
  }

  void _registerSocketListeners() {
    socket?.offAny(); // ✅ Prevent duplicates

    print('Registering group socket listeners');
    socket!.on('connect', (_) {
      if (!mounted) return;
      print('Connected to Socket.IO, joining group: ${widget.groupId}');
      socket!.emit('join_group', widget.groupId);
    });
    socket!.on('joined_group', (data) {
      if (!mounted) return;
      print('⚡️ Received joined_group event: $data');
      final joinedGroupId = data as String;
      if (joinedGroupId == widget.groupId) {
        print('✅ Successfully joined group: $joinedGroupId');
        setState(() {
          _joinedGroup = true;
        });
      }
    });
socket!.on('group_message', (data) {
  if (!mounted) return;
  print('[Socket] Received group_message: $data');
  try {
    final newMessage = models.Message.fromJson(Map<String, dynamic>.from(data));

    setState(() {
      // Replace optimistic message if clientId matches
      if (newMessage.clientId != null && newMessage.clientId!.isNotEmpty) {
        final optimisticIndex = messages.indexWhere((m) => m.clientId == newMessage.clientId);
        if (optimisticIndex != -1) {
          messages[optimisticIndex] = newMessage;
          print('✅ Replaced optimistic message with server message: ${newMessage.content}');
        } else if (!messages.any((m) => m.id == newMessage.id)) {
          messages.add(newMessage);
          print('🆕 Server message added (no optimistic match): ${newMessage.content}');
        }
      } else if (!messages.any((m) => m.id == newMessage.id)) {
        messages.add(newMessage);
        print('📥 New message from another user added: ${newMessage.content}');
      }
      messages.sort((a, b) => DateTime.parse(a.timestamp).compareTo(DateTime.parse(b.timestamp)));
    });

    _scrollToBottomSmooth();
  } catch (e) {
    print('❌ Error handling group_message: $e');
  }
});

    // Re-add the 'connect' listener for future reconnects

    socket!.on('group_message_deleted', (data) {
      if (!mounted) return;
      final messageId = data['messageId'] as String?;
      if (messageId != null) {
        setState(() {
          messages.removeWhere((m) => m.id == messageId);
          _selectedMessageIndices.clear();
          _isSelectionMode = false;
        });
        print('🗑️ Group message deleted via socket: $messageId');
      }
    });

    socket!.on('group_message_edited', (data) {
      if (!mounted) return;
      final messageId = data['messageId'] as String?;
      final newContent = data['newContent'] as String?;
      if (messageId != null && newContent != null) {
        final index = messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          setState(() {
            messages[index] = messages[index].copyWith(
              content: newContent,
              edited: true,
            );
          });
          print('✏️ Group message edited via socket: $messageId');
        }
      }
    });

    socket!.on('connect_error', (error) {
      if (!mounted) return; // Guard against setState after dispose
      print('Socket connection error: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection error')),
      );
    });
  }

  Future<void> _sendMessage({String? content, String? fileUrl}) async {
    final text = content ?? _messageController.text.trim();
    print(
        '[SendMessage] Attempting to send message: "$text" | fileUrl: $fileUrl');
    print('[SendMessage] Socket connected: ${socket?.connected}');
    print('[SendMessage] Joined group: $_joinedGroup');
    if (text.isEmpty && (fileUrl == null || fileUrl.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message cannot be empty')),
      );
      return;
    }

    if (!_joinedGroup || socket?.connected != true) {
      print(
          '⚠️ Tried to send message before joining group or socket not connected');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still connecting to group...')),
      );
      return;
    }

    // Generate a unique client-side ID for optimistic updates
    final tempClientId =
        '${widget.currentUser}_${DateTime.now().millisecondsSinceEpoch}';

    final localMessage = models.Message(
      id: ''

      // Will be filled by server
      ,
      clientId: tempClientId,
      sender: widget.currentUser,
      receiver: widget.groupId,
      content: text,
      timestamp: DateTime.now().toIso8601String(),
      isGroup: true,
      fileUrl: fileUrl ?? '',
      emojis: [],
      readBy: [widget.currentUser],
    );

    if (!mounted) return;
    if (socket!.id != null && socket!.id!.isNotEmpty) {
      setState(() {
        messages.add(localMessage);
        messages.sort((a, b) =>
            DateTime.parse(a.timestamp).compareTo(DateTime.parse(b.timestamp)));
      });
    }

    _scrollToBottomSmooth();
    _messageController.clear();

    final messageData = {
      'clientId': tempClientId,
      'groupId': widget.groupId,
      'sender': widget.currentUser,
      'content': text,
      'timestamp': localMessage.timestamp,
      'fileUrl': fileUrl ?? '',
      'isFile': fileUrl != null && fileUrl.isNotEmpty,
    };

    try {
      print(
          '[SendMessage] Emitting send_group_message with data: $messageData');
      socket!.emit('send_group_message', messageData);
      socket!.emit('inbox_update', {
        'groupId': widget.groupId,
        'lastMessage': text.isEmpty ? '[File]' : text,
        'timestamp': localMessage.timestamp,
        'sender': widget.currentUser,
      });
    } catch (e) {
      print('Error sending message: $e');
      if (!mounted) return;
      setState(() {
        messages.removeWhere((m) => m.clientId == tempClientId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: ${e.toString()}')),
      );
    }
  }

  Future<void> _fetchInitialData() async {
    try {
      await Future.wait([
        _fetchMessages(),
        _fetchGroupMembers(),
        _fetchAllUsers(),
      ]);
      if (!mounted) return; // Guard against setState after dispose
      setState(() => isLoading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return; // Guard against setState after dispose
        _scrollToBottomSmooth();
      });
    } catch (error) {
      if (!mounted) return; // Guard against setState after dispose
      print('Error fetching initial data: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load data')),
      );
    }
  }

  Future<void> _fetchMessages() async {
    final url =
        Uri.parse('http://localhost:4000/groups/${widget.groupId}/messages');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );

      if (!mounted) return; // Guard against setState after dispose
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final newMessages = data
            .map((json) =>
                models.Message.fromJson(Map<String, dynamic>.from(json)))
            .toList();

        setState(() {
          // Merge with existing messages, avoiding duplicates
          for (final newMsg in newMessages) {
            if (!messages.any((m) => m.id == newMsg.id)) {
              messages.add(newMsg);
            }
          }
          messages.sort((a, b) => DateTime.parse(a.timestamp)
              .compareTo(DateTime.parse(b.timestamp)));
        });
      }
    } catch (error) {
      print('Error fetching messages: $error');
    }
  }

  Future<void> _fetchGroupMembers() async {
    final url = Uri.parse('http://localhost:4000/groups/${widget.groupId}');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );

      if (!mounted) return; // Guard against setState after dispose
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          groupMembers = data['members'] ?? [];
        });
      }
    } catch (e) {
      print('Error fetching group members: $e');
    }
  }

  Future<void> _fetchAllUsers() async {
    final url = Uri.parse('http://localhost:4000/users');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );

      if (!mounted) return; // Guard against setState after dispose
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          allUsers = data.map((u) => Map<String, dynamic>.from(u)).toList();
        });
      }
    } catch (e) {
      print('Error fetching users: $e');
    }
  }

  String _getUsername(String userId) {
    final user = allUsers.firstWhere(
      (u) => u['_id'] == userId,
      orElse: () => {'username': userId}, // Fallback to userId if not found
    );
    return user['username'] ?? userId;
  }

  void _scrollListener() {
    if (_isNearBottom()) {
      // Could implement read receipts here if needed
    }
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return (maxScroll - currentScroll) < 100;
  }

Future<List<PlatformFile>?> _pickAndAddFiles() async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: true);

  if (!mounted) return null; // Guard against setState after dispose
  if (result != null && result.files.isNotEmpty) {
    setState(() {
      _selectedFiles.addAll(result.files);
    });
    FocusScope.of(context).requestFocus(_focusNode);
    return result.files;
  }
  return null;
}
  Future<void> uploadAndSendFile(PlatformFile file) async {
    final tempClientId =
        UniqueKey().toString(); // Use UniqueKey for client-side ID

    final tempMessage = models.Message(
      id: '', // Server will assign
      clientId: tempClientId, // Store clientId for optimistic update
      sender: widget.currentUser,
      receiver: widget.groupId,
      content: '',
      timestamp: DateTime.now().toIso8601String(),
      isGroup: true,
      emojis: [],
      fileUrl: kIsWeb ? '' : (file.path ?? ''), // Path for local preview
      readBy: [widget.currentUser],
    );

    if (!mounted) return; // Guard against setState after dispose
    setState(() {
      messages.add(tempMessage);
      messages.sort((a, b) =>
          DateTime.parse(a.timestamp).compareTo(DateTime.parse(b.timestamp)));
    });
    _scrollToBottomSmooth();

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://localhost:4000/upload'),
      );

      if (kIsWeb && file.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes('file', file.bytes!,
              filename: file.name),
        );
      } else if (file.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath('file', file.path!),
        );
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (!mounted) return; // Guard against setState after dispose
      if (response.statusCode == 200) {
        final fileUrl = jsonDecode(responseBody)['fileUrl'];
        // Send message with file URL, passing the same clientId
        await _sendMessage(content: '', fileUrl: fileUrl);
        setState(() {
          messages.removeWhere((m) => m.clientId == tempClientId);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload file')),
        );
        setState(() {
          messages.removeWhere((m) => m.clientId == tempClientId);
        });
      }
    } catch (e) {
      print('File upload error: $e');
      if (!mounted) return; // Guard against setState after dispose
      setState(() {
        messages.removeWhere((m) => m.clientId == tempClientId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload file: ${e.toString()}')),
      );
    } finally {
      if (!mounted) return; // Guard against setState after dispose
      setState(() {
        _selectedFiles.remove(file);
      });
    }
  }

  Future<void> _deleteMessagesWithUndo(List<String> messageIds) async {
    if (messageIds.isEmpty) return;

    _recentlyDeletedMessages =
        messages.where((m) => messageIds.contains(m.id)).toList();

    if (!mounted) return; // Guard against setState after dispose
    setState(() {
      messages.removeWhere((m) => messageIds.contains(m.id));
      _selectedMessageIndices.clear();
      _isSelectionMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted ${_recentlyDeletedMessages.length} message(s)'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return; // Guard against setState after dispose
            setState(() {
              messages.insertAll(0, _recentlyDeletedMessages);
              messages.sort((a, b) => DateTime.parse(a.timestamp)
                  .compareTo(DateTime.parse(b.timestamp)));
            });
            _recentlyDeletedMessages.clear();
            _undoTimer?.cancel();
          },
        ),
        duration: const Duration(seconds: 5),
      ),
    );

    _undoTimer = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return; // Guard against setState after dispose
      if (_recentlyDeletedMessages.isNotEmpty) {
        final idsToDelete = _recentlyDeletedMessages.map((m) => m.id).toList();
        _recentlyDeletedMessages.clear();
        await _permanentlyDeleteMessages(idsToDelete);
      }
    });
  }

  Future<void> _permanentlyDeleteMessages(List<String> messageIds) async {
    for (final msgId in messageIds) {
      final url = Uri.parse(
          'http://localhost:4000/groups/${widget.groupId}/messages/$msgId');
      try {
        final response = await http.delete(
          url,
          headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
        );
        if (!mounted) return; // Guard against setState after dispose
        if (response.statusCode == 200) {
          print('✅ Permanently deleted group message $msgId on backend');
          socket!.emit('group_message_deleted', {
            'messageId': msgId,
            'groupId': widget.groupId
          });
        } else {
          print(
              '❌ Failed to delete group message $msgId on backend: ${response.body}');
        }
      } catch (e) {
        print('🔥 Error deleting group message $msgId: $e');
      }
    }
  }

  Future<void> _editMessage(String messageId, String newContent) async {
    final messageIndex = messages.indexWhere((msg) => msg.id == messageId);
    if (messageIndex == -1) return;

    if (!mounted) return; // Guard against setState after dispose
    setState(() {
      messages[messageIndex] =
          messages[messageIndex].copyWith(content: newContent, edited: true);
    });

    final url = Uri.parse(
        'http://localhost:4000/groups/${widget.groupId}/messages/$messageId');
    try {
      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.jwtToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'content': newContent}),
      );

      if (!mounted) return; // Guard against setState after dispose
      if (response.statusCode == 200) {
        print('Group message edited successfully on backend');
        socket!.emit('group_message_edited', {
          'messageId': messageId,
          'newContent': newContent,
          'groupId': widget.groupId
        });
      } else {
        print('Failed to edit group message on backend: ${response.body}');
        // Revert optimistic update if backend fails
        setState(() {
          messages[messageIndex] = messages[messageIndex]
              .copyWith(edited: false); // Or fetch original content
        });
      }
    } catch (error) {
      print('Error editing group message: $error');
      if (!mounted) return; // Guard against setState after dispose
      // Revert optimistic update
      setState(() {
        messages[messageIndex] = messages[messageIndex].copyWith(edited: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to edit message')),
      );
    }
  }

  void _scrollToBottomSmooth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isRemoteFile(String fileUrl) {
    return fileUrl.startsWith('http://') || fileUrl.startsWith('https://');
  }

  Widget _buildMessageContent(models.Message msg) {
    final bool hasFile = msg.fileUrl != null && msg.fileUrl.trim().isNotEmpty;
    final bool hasText = msg.content.trim().isNotEmpty;

    List<Widget> children = [];

    if (hasFile) {
      final ext = getFileExtension(msg.fileUrl);
      final isRemote = _isRemoteFile(msg.fileUrl);

      Widget fileWidget;

      if (['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext)) {
        fileWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isRemote
              ? Image.network(
                  msg.fileUrl,
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return SizedBox(
                      width: 150,
                      height: 150,
                      child: Center(
                        child: CircularProgressIndicator(
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) =>
                      const Text('[Image not available]'),
                )
              : Image.file(
                  File(msg.fileUrl),
                  width: 150,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Text('[Image file not found]'),
                ),
        );
      } else if (['.mp4', '.webm', '.mov', '.mkv'].contains(ext)) {
        fileWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 200,
              height: 150,
              child: InlineVideoPlayer(videoUrl: msg.fileUrl),
            ),
            TextButton.icon(
              icon: const Icon(Icons.download),
              label: const Text("Save Video"),
              onPressed: () async {
                final savedPath = await saveFileSmart(
                  msg.fileUrl,
                  'group_chat_video_${DateTime.now().millisecondsSinceEpoch}$ext',
                );
                if (!mounted) return; // Guard against setState after dispose
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(savedPath != null
                          ? 'Video saved to $savedPath'
                          : 'Save failed')),
                );
              },
            ),
          ],
        );
      } else if (['.mp3', '.wav', '.aac', '.m4a'].contains(ext)) {
        fileWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InlineAudioPlayer(audioUrl: msg.fileUrl),
            TextButton.icon(
              icon: const Icon(Icons.download),
              label: const Text("Save Audio"),
              onPressed: () async {
                final savedPath = await saveFileSmart(
                  msg.fileUrl,
                  'group_chat_audio_${DateTime.now().millisecondsSinceEpoch}$ext',
                );
                if (!mounted) return; // Guard against setState after dispose
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(savedPath != null
                          ? 'Audio saved to $savedPath'
                          : 'Save failed')),
                );
              },
            ),
          ],
        );
      } else {
        fileWidget = InkWell(
          onTap: () async {
            final savedPath = await saveFileSmart(
              msg.fileUrl,
              'group_chat_file_${DateTime.now().millisecondsSinceEpoch}$ext',
            );
            if (!mounted) return; // Guard against setState after dispose
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(savedPath != null
                      ? 'File saved to $savedPath'
                      : 'Save failed')),
            );
          },
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(msg.fileUrl.split('/').last,
                      style: const TextStyle(
                          color: Colors.blue))), // Corrected: use msg.fileUrl
            ],
          ),
        );
      }
      children.add(fileWidget);
    }

    if (hasText) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
      children.add(
        Text(
          msg.content.trim(),
          style: const TextStyle(color: Colors.black87, fontSize: 16),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String getFileExtension(String urlOrName) {
    try {
      final uri = Uri.parse(urlOrName);
      final segments = uri.pathSegments;
      if (segments.isEmpty) return '';
      final lastSegment = segments.last;
      final dotIndex = lastSegment.lastIndexOf('.');
      if (dotIndex == -1) return '';
      return lastSegment.substring(dotIndex).toLowerCase();
    } catch (_) {
      return '';
    }
  }

  Future<String?> saveFileSmart(String url, String fileName) async {
    if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final savePath = await getSavePath(suggestedName: fileName);
      if (savePath == null) {
        print('User cancelled save dialog');
        return null;
      }
      final dio = Dio();
      await dio.download(url, savePath);
      return savePath;
    } else if (Platform.isAndroid) {
      return await saveFileToPublicFolder(url, fileName);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$fileName';
      final dio = Dio();
      await dio.download(url, filePath);
      return filePath;
    }
  }

  Future<String?> saveFileToPublicFolder(String url, String fileName) async {
    try {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        print('Permission denied to write to external storage.');
        return null;
      }

      String? folderName;
      if (fileName.endsWith('.jpg') ||
          fileName.endsWith('.jpeg') ||
          fileName.endsWith('.png')) {
        folderName = 'Pictures';
      } else if (fileName.endsWith('.mp3') || fileName.endsWith('.wav')) {
        folderName = 'Music';
      } else if (fileName.endsWith('.mp4') || fileName.endsWith('.webm')) {
        folderName = 'Movies';
      } else if (fileName.endsWith('.pdf') || fileName.endsWith('.docx')) {
        folderName = 'Documents';
      } else {
        folderName = 'Download';
      }

      final dir = Directory('/storage/emulated/0/$folderName/ChatApp');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final fullPath = '${dir.path}/$fileName';

      final dio = Dio();
      await dio.download(url, fullPath);

      print('File saved to $fullPath');
      return fullPath;
    } catch (e) {
      print('❌ Error saving file: $e');
      return null;
    }
  }

  Widget _buildMessageItem(models.Message msg, int index) {
    final isSender = msg.sender == widget.currentUser;
    final timestamp = DateTime.tryParse(msg.timestamp ?? '');
    final formattedTime =
        timestamp != null ? DateFormat('hh:mm a').format(timestamp) : '';
    final isDeleted = msg.deleted;
    final isEdited = msg.edited;
    final isSelected = _selectedMessageIndices.contains(index);

    Widget messageContent() {
      if (_editingMessageId == msg.id) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TextField(
              controller: _editController,
              autofocus: true,
              maxLines: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(8),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () {
                    if (!mounted)
                      return; // Guard against setState after dispose
                    setState(() {
                      _editingMessageId = null;
                      _editController.clear();
                    });
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newText = _editController.text.trim();
                    if (newText.isNotEmpty) {
                      await _editMessage(msg.id, newText);
                      if (!mounted)
                        return; // Guard against setState after dispose
                      setState(() {
                        _editingMessageId = null;
                        _editController.clear();
                      });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        );
      } else {
        return _buildMessageContent(msg);
      }
    }

    return GestureDetector(
      onLongPressStart: (details) {
        if (!mounted) return; // Guard against setState after dispose
        setState(() {
          _isSelectionMode = true;
          _selectedMessageIndices = {index};
          _popupPosition = details.globalPosition;
        });
      },
      onTap: () {
        if (!mounted) return; // Guard against setState after dispose
        if (_isSelectionMode) {
          setState(() {
            if (_selectedMessageIndices.contains(index)) {
              _selectedMessageIndices.remove(index);
              if (_selectedMessageIndices.isEmpty) {
                _isSelectionMode = false;
                _popupPosition = null;
              }
            } else {
              _selectedMessageIndices.add(index);
            }
          });
        }
      },
      child: Align(
        alignment: isSender ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withOpacity(0.2)
                : (isSender ? Colors.blue[100] : Colors.grey[200]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment:
                isSender ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isSender)
                Text(
                  _getUsername(msg.sender),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              if (isDeleted)
                const Text('[Message deleted]',
                    style: TextStyle(fontStyle: FontStyle.italic))
              else
                messageContent(), // Use the messageContent widget here
              Text(
                formattedTime + (isEdited ? ' (edited)' : ''),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ));
  }

  Widget _buildPopupMenu(models.Message msg) {
    final isMe = msg.sender == widget.currentUser;

    return Positioned(
      left: _popupPosition!.dx - 60,
      top: _popupPosition!.dy - 100,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[200],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: msg.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message copied')),
                );
                _dismissPopup();
              },
            ),
            if (isMe)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit',
                onPressed: () {
                  if (!mounted) return; // Guard against setState after dispose
                  setState(() {
                    _editingMessageId = msg.id;
                    _editController.text = msg.content;
                    _dismissPopup();
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  void _dismissPopup() {
    if (!mounted) return; // Guard against setState after dispose
    setState(() {
      _isSelectionMode = false;
      _selectedMessageIndices.clear();
      _popupPosition = null;
    });
  }

  Widget _buildFilesPreview() {
    if (_selectedFiles.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedFiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final file = _selectedFiles[index];
          final isImage =
              file.extension?.toLowerCase().contains('png') == true ||
                  file.extension?.toLowerCase().contains('jpg') == true ||
                  file.extension?.toLowerCase().contains('jpeg') == true;

          return Stack(
            children: [
              Container(
                width: 70,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isImage && kIsWeb && file.bytes != null
                    ? Image.memory(file.bytes!, fit: BoxFit.cover)
                    : const Center(
                        child: Icon(Icons.insert_drive_file, size: 40),
                      ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () {
                    if (!mounted)
                      return; // Guard against setState after dispose
                    setState(() {
                      _selectedFiles.removeAt(index);
                    });
                  },
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }

  void _handleSend() async {
    final text = _messageController.text.trim();

    if (_selectedFiles.isNotEmpty) {
      for (final file in _selectedFiles) {
        await uploadAndSendFile(file);
      }
      if (text.isNotEmpty) {
        _sendMessage(content: text);
      }
      if (!mounted) return; // Guard against setState after dispose
      setState(() {
        _selectedFiles.clear();
        _messageController.clear();
      });
    } else if (text.isNotEmpty) {
      _sendMessage(content: text);
      _messageController.clear();
    }
  }

  Widget _buildInputField() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFilesPreview(),
          Row(
            children: [
              IconButton(
                icon: Icon(
                    _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions),
                onPressed: () {
                  _focusNode.unfocus();
                  if (!mounted) return; // Guard against setState after dispose
                  setState(() => _showEmojiPicker = !_showEmojiPicker);
                },
              ),
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: _pickAndAddFiles,
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  textInputAction:
                      TextInputAction.send, // Corrected: TextInputInputAction
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _handleSend,
              ),
            ],
          ),
          if (_showEmojiPicker)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  _messageController.text += emoji.emoji;
                  _messageController.selection = TextSelection.fromPosition(
                    TextPosition(offset: _messageController.text.length),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _videoControllers.values.forEach((controller) => controller.dispose());
    _audioPlayers.values.forEach((player) => player.dispose());
    _undoTimer?.cancel(); // Cancel timer on dispose
    socket?.emit('leave_group', widget.groupId); // Use ?. for null safety
    // Explicitly turn off all listeners to prevent setState after dispose
    socket?.off('connect');
    socket?.off('group_message');
    socket?.off('group_message_deleted');
    socket?.off('group_message_edited');
    socket?.off('connect_error');
    socket?.offAny();
    socket?.disconnect(); // Use ?. for null safety
    socket?.dispose(); // Use ?. for null safety
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _editController.dispose(); // Dispose edit controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<models.Message> filteredMessages =
        messages.where((msg) => !msg.deleted).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  _isSelectionMode = false;
                  _selectedMessageIndices.clear();
                });
              },
            ),
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                // ...your delete logic here...
              },
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showGroupInfo,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: filteredMessages.isEmpty
                          ? const Center(child: Text('No messages yet'))
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: filteredMessages.length,
                              itemBuilder: (context, index) {
                                return GroupMessageBubble(
                                  message: filteredMessages[index],
                                  isSender: filteredMessages[index].sender ==
                                      widget.currentUser,
                                  isSelected:
                                      _selectedMessageIndices.contains(index),
                                  usernameResolver: _getUsername,
                                  editingMessageId: _editingMessageId,
                                  editController: _editController,
                                  onLongPress: (details) {
                                    if (!mounted) return;
                                    setState(() {
                                      _isSelectionMode = true;
                                      _selectedMessageIndices = {index};
                                      _popupPosition = details.globalPosition;
                                    });
                                  },
                                  onTap: () {
                                    if (!mounted) return;
                                    if (_isSelectionMode) {
                                      setState(() {
                                        if (_selectedMessageIndices
                                            .contains(index)) {
                                          _selectedMessageIndices.remove(index);
                                          if (_selectedMessageIndices.isEmpty) {
                                            _isSelectionMode = false;
                                            _popupPosition = null;
                                          }
                                        } else {
                                          _selectedMessageIndices.add(index);
                                        }
                                      });
                                    }
                                  },
                                  onEdit: (newText) async {
                                    if (newText.isNotEmpty) {
                                      await _editMessage(
                                          filteredMessages[index].id, newText);
                                      if (!mounted) return;
                                      setState(() {
                                        _editingMessageId = null;
                                        _editController.clear();
                                      });
                                    }
                                  },
                                  onDelete: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Delete Message?'),
                                        content: const Text(
                                            'Are you sure you want to delete this message?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context)
                                                    .pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(true),
                                            child: const Text('Delete',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirmed == true) {
                                      await _deleteMessagesWithUndo(
                                          [filteredMessages[index].id]);
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                    GroupChatInputField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      showEmojiPicker: _showEmojiPicker,
                      selectedFiles: _selectedFiles,
                      onEmojiToggle: () {
                        _focusNode.unfocus();
                        if (!mounted) return;
                        setState(() => _showEmojiPicker = !_showEmojiPicker);
                      },
                      onSend: _handleSend,
                      pickFiles: _pickAndAddFiles, // <-- CORRECT
                      onRemoveFile: (index) {
                        if (!mounted) return;
                        setState(() {
                          _selectedFiles.removeAt(index);
                        });
                      },
                    ),
                  ],
                ),
                if (_isSelectionMode &&
                    _selectedMessageIndices.length == 1 &&
                    _popupPosition != null)
               if (_isSelectionMode &&
    _selectedMessageIndices.length == 1 &&
    _popupPosition != null)
  _buildPopupMenu(filteredMessages[_selectedMessageIndices.first]),
              ],
            ),
    );
  }

  void _showGroupInfo() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.groupName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (widget.groupDescription.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(widget.groupDescription),
                ),
              const Divider(),
              const Text(
                'Members',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: groupMembers.length,
                  itemBuilder: (context, index) {
                    final memberId = groupMembers[index].toString();
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(_getUsername(memberId)),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Re-using InlineVideoPlayer and InlineAudioPlayer from chatapp.txt
class InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const InlineVideoPlayer({super.key, required this.videoUrl});

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return; // Guard against setState after dispose
        setState(() {
          _isInitialized = true;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (!mounted) return; // Guard against setState after dispose
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isInitialized
        ? GestureDetector(
            onTap: _togglePlayPause,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
                if (!_controller.value.isPlaying)
                  const Icon(Icons.play_circle_fill,
                      size: 64, color: Colors.white),
              ],
            ),
          )
        : const Center(child: CircularProgressIndicator());
  }
}

class InlineAudioPlayer extends StatefulWidget {
  final String audioUrl;

  const InlineAudioPlayer({required this.audioUrl, super.key});

  @override
  _InlineAudioPlayerState createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  late final ap.AudioPlayer _audioPlayer;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = ap.AudioPlayer();
    _audioPlayer.onPlayerComplete.listen((event) {
      if (!mounted) return; // Guard against setState after dispose
      setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(ap.UrlSource(widget.audioUrl));
      }
      if (!mounted) return; // Guard against setState after dispose
      setState(() => _isPlaying = !_isPlaying);
    } catch (e) {
      print('Audio play error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isPlaying ? Icons.pause_circle : Icons.play_circle,
        color: Colors.blue,
        size: 36,
      ),
      onPressed: _togglePlayPause,
    );
  }
}
*/