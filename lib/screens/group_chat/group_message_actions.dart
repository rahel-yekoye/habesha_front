import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/message.dart' as models;
import 'package:flutter/services.dart';

class GroupMessageActions {
  /// Edit a message (optimistic update, then HTTP + socket)
  static Future<void> editMessage({
    required BuildContext context,
    required String messageId,
    required String newContent,
    required String groupId,
    required String jwtToken,
    required dynamic socket,
    required Function(List<models.Message>) onUpdateMessages,
  }) async {
    try {
      print('✏️ Attempting to edit message: $messageId in group: $groupId');
      print('📝 New content: $newContent');
      
      final url = Uri.parse('http://localhost:4000/groups/$groupId/messages/$messageId');
      print('🌐 PUT URL: $url');
      
      final response = await http.put(
        url,
        headers: {
          'Authorization': 'Bearer $jwtToken',
          'Content-Type': 'application/json',
        },
        body: '{"content": "$newContent"}',
      );
      
      print('📡 PUT Response: ${response.statusCode} - ${response.body}');
      
      if (response.statusCode == 200) {
        print('✅ Message edited successfully, emitting socket event');
        socket?.emit('group_message_edited', {
          'messageId': messageId,
          'newContent': newContent,
          'groupId': groupId,
        });
      } else {
        print('❌ Edit failed with status: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to edit message: ${response.statusCode}')),
        );
      }
    } catch (e) {
      print('❌ Failed to edit group message: $e');
      print('❌ Error type: ${e.runtimeType}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Edit error: $e')),
      );
    }
  }

  /// Delete messages with undo support
  static Future<void> deleteMessagesWithUndo({
    required BuildContext context,
    required Set<int> selectedIndices,
    required List<models.Message> messages,
    required Function(List<models.Message>) onUpdateMessages,
    required Function(List<String>) onDeleteConfirmed,
    required String groupId,
    required String jwtToken,
    required dynamic socket,
  }) async {
    final ids = selectedIndices
        .map((i) => messages[i].id)
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;

    // Optimistic UI: mark as deleted
    final updatedMessages = List<models.Message>.from(messages);
    for (var i in selectedIndices) {
      updatedMessages[i] = updatedMessages[i].copyWith(deleted: true);
    }
    onUpdateMessages(updatedMessages);

    // Show undo snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted ${ids.length} message(s)'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Undo: restore messages
            onUpdateMessages(messages);
          },
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    // Wait for snackbar to disappear before permanent delete
    await Future.delayed(const Duration(seconds: 3));
    await permanentlyDeleteMessages(
      ids,
      groupId: groupId,
      jwtToken: jwtToken,
      socket: socket,
    );
    onDeleteConfirmed(ids);
  }

  /// Permanently delete messages (HTTP + socket)
  static Future<void> permanentlyDeleteMessages(
    List<String> messageIds, {
    required String groupId,
    required String jwtToken,
    required dynamic socket,
  }) async {
    for (final msgId in messageIds) {
      try {
        print('🗑️ Attempting to delete message: $msgId from group: $groupId');
        final url = Uri.parse('http://localhost:4000/groups/$groupId/messages/$msgId');
        print('🌐 DELETE URL: $url');
        
        final response = await http.delete(
          url,
          headers: {
            'Authorization': 'Bearer $jwtToken',
            'Content-Type': 'application/json',
          },
        );
        
        print('📡 DELETE Response: ${response.statusCode} - ${response.body}');
        
        if (response.statusCode == 200) {
          print('✅ Message deleted successfully');
          // Backend will emit the socket event, no need to emit from frontend
        } else {
          print('❌ Delete failed with status: ${response.statusCode}');
          print('❌ Response body: ${response.body}');
        }
      } catch (e) {
        print('❌ Failed to delete group message: $e');
        print('❌ Error type: ${e.runtimeType}');
      }
    }
  }

  /// Copy message content to clipboard
  static void copyMessage({
    required BuildContext context,
    required models.Message message,
    required VoidCallback onDismiss,
  }) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied')),
    );
    onDismiss();
  }

  /// Handle tap for selection logic
  static void handleTap({
    required BuildContext context,
    required int index,
    required Set<int> selectedIndices,
    required Function(Set<int>) onUpdateSelection,
    required Function(bool) onSelectionMode,
    required Function(Offset?) onPopupPosition,
  }) {
    if (selectedIndices.contains(index)) {
      final newSet = Set<int>.from(selectedIndices)..remove(index);
      onUpdateSelection(newSet);
      if (newSet.isEmpty) {
        onSelectionMode(false);
        onPopupPosition(null);
      }
    } else {
      final newSet = Set<int>.from(selectedIndices)..add(index);
      onUpdateSelection(newSet);
    }
  }

  /// Handle long press for selection and popup
  static void handleLongPress({
    required BuildContext context,
    required int index,
    required LongPressStartDetails details,
    required Function(bool) onSelectionMode,
    required Function(Set<int>) onUpdateSelection,
    required Function(Offset) onPopupPosition,
  }) {
    onSelectionMode(true);
    onUpdateSelection({index});
    onPopupPosition(details.globalPosition);
  }

  /// Reply to a message
  static void replyToMessage({
    required BuildContext context,
    required models.Message message,
    required Function(models.Message?) onSetReplyingTo,
    required VoidCallback onDismiss,
  }) {
    onSetReplyingTo(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Replying to ${message.sender.split('@')[0]}'),
        duration: const Duration(seconds: 2),
      ),
    );
    onDismiss();
  }

  /// Delete a single message
  static Future<void> deleteSingleMessage({
    required BuildContext context,
    required models.Message message,
    required int messageIndex,
    required List<models.Message> messages,
    required Function(List<models.Message>) onUpdateMessages,
    required Function(List<String>) onDeleteConfirmed,
    required String groupId,
    required String jwtToken,
    required dynamic socket,
    required VoidCallback onDismiss,
  }) async {
    onDismiss();
    await deleteMessagesWithUndo(
      context: context,
      selectedIndices: {messageIndex},
      messages: messages,
      onUpdateMessages: onUpdateMessages,
      onDeleteConfirmed: onDeleteConfirmed,
      groupId: groupId,
      jwtToken: jwtToken,
      socket: socket,
    );
  }
}