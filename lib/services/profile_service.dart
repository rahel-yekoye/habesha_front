import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'auth_service.dart';

class UserProfile {
  final String id;
  final String username;
  final String email;
  final String? phoneNumber;
  final String? status;
  final String? profilePicture;
  final List<String>? profilePictureHistory;
  final DateTime? lastSeen;

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    this.phoneNumber,
    this.status,
    this.profilePicture,
    this.profilePictureHistory,
    this.lastSeen,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['_id'] ?? json['id'],
      username: json['username'],
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      status: json['status'],
      profilePicture: json['profilePicture'],
      profilePictureHistory: json['profilePictureHistory'] != null 
          ? List<String>.from(json['profilePictureHistory'])
          : null,
      lastSeen: json['lastSeen'] != null ? DateTime.parse(json['lastSeen']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'phoneNumber': phoneNumber,
      'status': status,
      'profilePicture': profilePicture,
      'profilePictureHistory': profilePictureHistory,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }
  
  UserProfile copyWith({
    String? id,
    String? username,
    String? email,
    String? phoneNumber,
    String? status,
    String? profilePicture,
    List<String>? profilePictureHistory,
    DateTime? lastSeen,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      status: status ?? this.status,
      profilePicture: profilePicture ?? this.profilePicture,
      profilePictureHistory: profilePictureHistory ?? this.profilePictureHistory,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

class ProfileService {
  static const String baseUrl = 'http://localhost:4000';
  
  // Helper method to get full profile picture URL
  static String getProfilePictureUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    // If it's already a full URL, return as is
    if (path.startsWith('http')) return path;
    // Otherwise, construct the full URL
    return '$baseUrl/$path';
  }
  
  // Get user profile
  static Future<UserProfile> getUserProfile(String userId) async {
    print('🔑 Getting token for profile access...');
    final token = await AuthService.getToken();
    
    if (token == null || token.isEmpty) {
      print('❌ No authentication token found in SharedPreferences');
      throw Exception('Please log in to view profile');
    }
    
    print('🔑 Token found, making request to profile endpoint...');
    print('🔗 URL: $baseUrl/profile/$userId');
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/profile/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      
      print('📡 Profile API Response Status: ${response.statusCode}');
      print('📡 Response Body: ${response.body}');
      
      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          print('✅ Successfully parsed profile data');
          return UserProfile.fromJson(data);
        } catch (e) {
          print('❌ Error parsing profile data: $e');
          throw Exception('Failed to parse profile data');
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        print('🔐 Authentication error: ${response.statusCode} - ${response.body}');
        await AuthService.clearSession();
        throw Exception('Authentication expired. Please log in again.');
      } else {
        throw Exception('Failed to load profile: ${response.statusCode}');
      }
    } catch (e) {
      if (e.toString().contains('Authentication expired')) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }
  
  // Update user profile
  static Future<UserProfile> updateProfile(String userId, Map<String, dynamic> updates) async {
    final token = await AuthService.getToken();
    
    if (token == null || token.isEmpty) {
      print('No authentication token found when updating profile');
      throw Exception('Please log in to update profile');
    }
    
    try {
      final response = await http.put(
        Uri.parse('http://localhost:4000/profile/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(updates),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return UserProfile.fromJson(data);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Token expired or invalid
        await AuthService.clearSession();
        throw Exception('Authentication expired. Please log in again.');
      } else {
        throw Exception('Failed to update profile: ${response.statusCode}');
      }
    } catch (e) {
      if (e.toString().contains('Authentication expired')) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }
  
  // Upload profile picture
  static Future<String?> uploadProfilePicture(Uint8List imageBytes, String fileName) async {
    print('🔑 Getting token for file upload...');
    final token = await AuthService.getToken();
    
    if (token == null || token.isEmpty) {
      print('❌ No authentication token found');
      throw Exception('No authentication token found');
    }
    
    print('🔑 Token found, preparing upload...');
    
    try {
      // Create the multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://localhost:4000/upload'),
      );
      
      // Add headers
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      
      print('📤 Creating multipart file...');
      
      // Add the file to the request
      var multipartFile = http.MultipartFile.fromBytes(
        'file',
        imageBytes,
        filename: fileName,
        contentType: fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')
            ? MediaType('image', 'jpeg')
            : fileName.endsWith('.png')
                ? MediaType('image', 'png')
                : MediaType('application', 'octet-stream'),
      );
      
      request.files.add(multipartFile);
      
      print('🚀 Sending upload request...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        try {
          final jsonResponse = jsonDecode(response.body);
          if (jsonResponse is Map && jsonResponse.containsKey('fileUrl')) {
            final fileUrl = jsonResponse['fileUrl'];
            print('✅ Upload successful! File URL: $fileUrl');
            return fileUrl;
          } else {
            print('❌ Invalid response format: Missing fileUrl');
            throw Exception('Invalid server response format');
          }
        } catch (e) {
          print('❌ Error parsing response: $e');
          throw Exception('Failed to parse server response');
        }
      } else {
        print('❌ Upload failed with status: ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        throw Exception('Failed to upload file: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Profile picture upload exception: $e');
      return null;
    }
  }
  
  // Delete profile picture
  static Future<void> deleteProfilePicture() async {
    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 500));
    
    // In a real app, you would make a DELETE request to remove the profile picture
    // For now, we'll just complete the future
  }
}
