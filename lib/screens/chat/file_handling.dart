import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<bool> requestStoragePermission() async {
  if (await Permission.manageExternalStorage.isGranted) return true;
  final result = await Permission.manageExternalStorage.request();
  return result.isGranted;
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

Future<List<PlatformFile>?> pickFiles() async {
  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
  return result?.files;
}
Future<String?> uploadFileToServer(PlatformFile file, {String? jwtToken}) async {
  try {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://localhost:4000/upload'),
    );

    // Add JWT token for authentication
    if (jwtToken != null) {
      request.headers['Authorization'] = 'Bearer $jwtToken';
    }

    if (kIsWeb && file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else if (file.path != null) {
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path!),
      );
    }

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseBody = await response.stream.bytesToString();
      return jsonDecode(responseBody)['fileUrl'];
    } else {
      print('❌ Upload failed with status: ${response.statusCode}');
      return null;
    }
  } catch (e) {
    print('❌ Upload exception: $e');
    return null;
  }
}

Future<String?> _uploadFile(PlatformFile file) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('http://localhost:4000/upload'),
  );

  if (kIsWeb && file.bytes != null) {
    request.files.add(
      http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
    );
  } else if (file.path != null) {
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path!),
    );
  }

  final response = await request.send();
  if (response.statusCode == 200) {
    final responseBody = await response.stream.bytesToString();
    return jsonDecode(responseBody)['fileUrl'];
  } else {
    return null;
  }
}
