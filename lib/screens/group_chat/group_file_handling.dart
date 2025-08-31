import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../../models/message.dart' as models;

/// All file-related logic for group chat.
class GroupFileHandling {
  /// Pick files and add to selectedFiles, update UI
  static Future<List<PlatformFile>?> pickAndAddFiles({
    required BuildContext context,
    required List<PlatformFile> selectedFiles,
    required FocusNode focusNode,
    required VoidCallback onUpdate,
  }) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      selectedFiles.addAll(result.files);
      onUpdate();
      FocusScope.of(context).requestFocus(focusNode);
      return result.files;
    }
    return null;
  }

  /// Download a file (web or mobile/desktop)
  static Future<void> downloadFile(String url, String fileName) async {
    if (kIsWeb) {
      // Web: trigger browser download
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
    } else {
      // Mobile/Desktop: download to device
      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/$fileName';
      await Dio().download(url, savePath);
      // Optionally open or notify user
    }
  }

  /// Save file to gallery or device (for images/videos)
  static Future<void> saveFileToGalleryOrDevice(String url, String fileName) async {
    // You can use gallery_saver or similar package for images/videos
    // For now, just download to device
    await downloadFile(url, fileName);
  }

  /// Save file to a public folder (Android)
  static Future<String?> saveFileToPublicFolder(String url, String fileName) async {
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

  /// Save file smartly (web, desktop, Android, iOS)
  static Future<String?> saveFileSmart(String url, String fileName) async {
    if (kIsWeb) {
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      return null;
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$fileName';
      await Dio().download(url, filePath);
      return filePath;
    } else if (Platform.isAndroid) {
      return await saveFileToPublicFolder(url, fileName);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$fileName';
      await Dio().download(url, filePath);
      return filePath;
    }
  }

  /// Fetch group messages from backend
  static Future<List<models.Message>> fetchMessages({
    required String groupId,
    required String jwtToken,
  }) async {
    final url = Uri.parse('http://localhost:4000/groups/$groupId/messages');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $jwtToken'},
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data
          .map((json) => models.Message.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    }
    throw Exception('Failed to fetch messages');
  }

  /// Fetch group members
  static Future<List<dynamic>> fetchGroupMembers({
    required String groupId,
    required String jwtToken,
  }) async {
    final url = Uri.parse('http://localhost:4000/groups/$groupId');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $jwtToken'},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['members'] ?? [];
    }
    throw Exception('Failed to fetch group members');
  }

  /// Fetch all users (for username resolving)
  static Future<List<Map<String, dynamic>>> fetchAllUsers({
    required String jwtToken,
  }) async {
    final url = Uri.parse('http://localhost:4000/users');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $jwtToken'},
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((u) => Map<String, dynamic>.from(u)).toList();
    }
    throw Exception('Failed to fetch users');
  }}