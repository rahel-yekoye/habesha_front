import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

import '../../models/message.dart' as models;

Future<void> deleteMessagesWithUndo(
  BuildContext context,
  List<String> messageIds,
  List<models.Message> messages,
  Function(List<models.Message>) onUpdateMessages,
  Function(List<String>) onDeleteConfirmed,
) async {
  final deletedMsgs = messages.where((msg) => messageIds.contains(msg.id)).toList();

  final updatedMessages = List<models.Message>.from(messages);
  for (var msg in deletedMsgs) {
    final index = updatedMessages.indexWhere((m) => m.id == msg.id);
    if (index != -1) {
      updatedMessages[index] = msg.copyWith(deleted: true);
    }
  }

  onUpdateMessages(updatedMessages);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Messages deleted'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          onUpdateMessages(messages); // Restore original list
        },
      ),
      duration: const Duration(seconds: 5),
    ),
  );

  await Future.delayed(const Duration(seconds: 5));

  onDeleteConfirmed(messageIds);
}

Future<void> permanentlyDeleteMessages(List<String> messageIds, String jwtToken) async {
  if (messageIds.isEmpty) return;

  try {
    final response = await http.delete(
      Uri.parse('http://localhost:4000/messages/delete-many'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'ids': messageIds,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      print('Successfully deleted messages from the backend.');
    } else {
      print('Failed to delete messages. Status: ${response.statusCode}, Body: ${response.body}');
    }
  } catch (e) {
    print('Error deleting messages: $e');
  }
}

Future<void> deleteMessagesUnified(
  List<String> messageIds,
  String jwtToken,
  String mode, // 'for_me' | 'for_everyone'
) async {
  if (messageIds.isEmpty) return;
  try {
    final response = await http.delete(
      Uri.parse('http://localhost:4000/messages'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({
        'ids': messageIds,
        'mode': mode,
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      print('Unified delete ($mode) succeeded for ${messageIds.length} message(s).');
    } else {
      print('Unified delete failed. Status: ${response.statusCode}, Body: ${response.body}');
    }
  } catch (e) {
    print('Error in unified delete: $e');
  }
}
