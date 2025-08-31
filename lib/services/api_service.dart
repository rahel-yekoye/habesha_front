import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:4000';
  static Future<bool> sendMessage(
      {required String sender, required String receiver, required String content, required String token}) async {
    final url = Uri.parse('$baseUrl/messages');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'sender': sender,
        'receiver': receiver,
        'content': content,
      }),
    );

    if (response.statusCode == 200) {
      print('✅ Message sent: ${response.body}');
      return true;
    } else {
      print('❌ Failed to send message: ${response.body}');
      return false;
    }
  }

  static Future<List<Message>> getMessages({
    required String user1,
    required String user2,
    required String currentUser,
    required String token,
    int limit = 30,
    DateTime? before,
  }) async {
    final qp = {
      'user1': user1,
      'user2': user2,
      'currentUser': currentUser,
      'limit': limit.toString(),
      if (before != null) 'before': before.toUtc().toIso8601String(),
    };
    final url = Uri.parse('$baseUrl/messages').replace(queryParameters: qp);

    final response = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      print('Fetched ${data.length} messages. Raw response: ${response.body}');

      List<Message> messages = [];
      for (var item in data) {
        try {
          final msg = Message.fromJson(Map<String, dynamic>.from(item));
          messages.add(msg);
          print('Processed message - ID: "${msg.id}", Sender: ${msg.sender}, Content: ${msg.content}');
        } catch (e) {
          print('Error parsing message: $e\nRaw message data: $item');
        }
      }
      return messages;
    } else {
      print('❌ Failed to fetch messages: ${response.body}');
      return [];
    }
  }

  static Future<List<String>> fetchGroupIds(String jwtToken) async {
    final url = Uri.parse('$baseUrl/groups');

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $jwtToken'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((group) => group['_id'].toString()).toList();
    } else {
      print('❌ Failed to fetch group IDs: ${response.statusCode}');
      throw Exception('Failed to fetch group IDs');
    }
  }

  static Future<List<Message>> getGroupMessages({
    required String groupId,
    required String token,
    int limit = 30,
    DateTime? before,
  }) async {
    final qp = {
      'limit': limit.toString(),
      if (before != null) 'before': before.toUtc().toIso8601String(),
    };
    final url = Uri.parse('$baseUrl/groups/$groupId/messages').replace(queryParameters: qp);
    final response = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
    });
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => Message.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  static Future<Map<String, dynamic>> getPresence({
    required List<String> userIds,
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/presence').replace(queryParameters: {
      'users': userIds.join(',')
    });
    final res = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
    });
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body));
    }
    throw Exception('Failed to fetch presence');
  }
}
