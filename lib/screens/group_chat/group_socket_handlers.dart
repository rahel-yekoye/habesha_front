import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../models/message.dart' as models;
import '../chat/file_handling.dart'; // <-- Import your file upload logic
import 'package:file_picker/file_picker.dart';
class GroupSocketHandlers {
  static List<models.Message> messages = [];

  static void setInitialMessages(List<models.Message> initial) {
    messages = List<models.Message>.from(initial);
  }

  static void initializeSocket({
    required BuildContext context,
    required dynamic widget, // Pass your GroupChatScreen widget
    required Function(List<models.Message>) onMessagesUpdate,
    required Function(bool) onJoinedGroup,
    required Function(IO.Socket) onSocket,
    required VoidCallback onScrollToBottom,
  }) {
    IO.Socket? socket = IO.io('http://localhost:4000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'randomizationFactor': 0.5,
      'extraHeaders': {'Authorization': 'Bearer ${widget.jwtToken}'},
    });

    socket.on('disconnect', (_) {
      print('Disconnected from Socket.IO - attempting to reconnect');
      Future.delayed(const Duration(seconds: 2), () {
        socket.connect();
      });
    });

    socket.on('connect_error', (error) {
      print('Socket connection error: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection error')),
      );
    });

    socket.on('connect', (_) {
      print('Connected to Socket.IO, joining group: ${widget.groupId}');
      socket.emit('join_group', widget.groupId);
    });

    socket.on('joined_group', (data) {
      print('⚡️ Received joined_group event: $data');
      late final String joinedGroupId;

      if (data is String) {
        joinedGroupId = data;
      } else if (data is List && data.isNotEmpty && data.first is String) {
        joinedGroupId = data.first;
      } else {
        print('❌ Invalid joined_group data format: $data');
        return;
      }

      if (joinedGroupId == widget.groupId) {
        print('✅ Successfully joined group: $joinedGroupId');
        onJoinedGroup(true);
      } else {
        print('❌ Joined group ID doesn’t match current group: $joinedGroupId');
      }
    });

    socket.on('group_joined', (data) {
      print('Joined group via socket: $data');
      onJoinedGroup(true); // This sets _joinedGroup to true
    });

    // --- CRITICAL SECTION: group_message handler ---
    socket.on('group_message', (data) {
      print('[Socket] Received group_message: $data');
      try {
        final newMessage = models.Message.fromJson(Map<String, dynamic>.from(data));
        // Replace optimistic message if clientId matches
        final optimisticIndex = messages.indexWhere((m) => m.clientId == newMessage.clientId);

        if (optimisticIndex != -1) {
          // Replace the optimistic message with the real one
          messages[optimisticIndex] = newMessage;
        } else if (!messages.any((m) => m.id == newMessage.id && m.id.isNotEmpty)) {
          // Only add if not already present (avoid duplicates)
          messages.add(newMessage);
        }
        // Always sort by timestamp
        messages.sort((a, b) => DateTime.parse(a.timestamp).compareTo(DateTime.parse(b.timestamp)));
        // Update UI
        onMessagesUpdate(List<models.Message>.from(messages));
        onScrollToBottom();
      } catch (e) {
        print('❌ Error handling group_message: $e');
      }
    });

    socket.on('group_message_deleted', (data) {
      final messageId = data['messageId'] as String?;
      if (messageId != null) {
        messages.removeWhere((m) => m.id == messageId);
        onMessagesUpdate(List<models.Message>.from(messages));
      }
    });

    socket.on('group_message_edited', (data) {
      final messageId = data['messageId'] as String?;
      final newContent = data['newContent'] as String?;
      if (messageId != null && newContent != null) {
        final index = messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          messages[index] = messages[index].copyWith(
            content: newContent,
            edited: true,
          );
          onMessagesUpdate(List<models.Message>.from(messages));
        }
      }
    });

    onSocket(socket);
    socket.connect();

    // 🛠️ If already connected, make sure to emit join_group
    if (socket.connected) {
      print('Already connected to Socket.IO, manually emitting join_group: ${widget.groupId}');
      socket.emit('join_group', widget.groupId);
    }
  }

  static void disposeSocket(IO.Socket? socket, String groupId) {
    if (socket == null) return;
    socket.emit('leave_group', groupId);
    socket.off('connect');
    socket.off('group_message');
    socket.off('group_message_deleted');
    socket.off('group_message_edited');
    socket.off('connect_error');
    socket.offAny();
    socket.disconnect();
    socket.dispose();
  }

  static Future<void> sendMessage({
    required BuildContext context,
    required IO.Socket? socket,
    required bool joinedGroup,
    required dynamic widget,
    required TextEditingController messageController,
    required List<PlatformFile> selectedFiles,
    required Function(List<models.Message>) onUpdateMessages,
    required VoidCallback onClearFiles,
    required VoidCallback onScrollToBottom,
    required List<models.Message> currentMessages,
  }) async {
    final text = messageController.text.trim();
    String? fileUrl;

    // 1. Upload file if present
    if (selectedFiles.isNotEmpty) {
      // Only support one file per message for now
      final file = selectedFiles.first;
      fileUrl = await uploadFileToServer(file);
      if (fileUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File upload failed')),
        );
        return;
      }
    }

    // 2. Don't send empty messages
    if (text.isEmpty && fileUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message cannot be empty')),
      );
      return;
    }
    if (!joinedGroup || socket?.connected != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still connecting to group...')),
      );
      return;
    }

    final tempClientId = '${widget.currentUser}_${DateTime.now().millisecondsSinceEpoch}';
    final localMessage = models.Message(
      id: '',
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
    messages.add(localMessage);
    onUpdateMessages(List<models.Message>.from(messages));
    onScrollToBottom();
    messageController.clear();

    final messageData = {
      'clientId': tempClientId,
      'groupId': widget.groupId,
      'sender': widget.currentUser,
      'receiver': '', // or widget.groupId, or whatever your backend expects
      'content': text,
      'timestamp': localMessage.timestamp,
      'fileUrl': fileUrl ?? '',
      'isFile': fileUrl != null,
      'isGroup': true,
      'emojis': [],
      'readBy': [widget.currentUser],
    };
    try {
      socket!.emit('send_group_message', messageData);
      socket.emit('inbox_update', {
        'groupId': widget.groupId,
        'lastMessage': text.isEmpty ? '[File]' : text,
        'timestamp': localMessage.timestamp,
        'sender': widget.currentUser,
      });
      onClearFiles();
    } catch (e) {
      print('Error sending message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: ${e.toString()}')),
      );
    }
  }
}