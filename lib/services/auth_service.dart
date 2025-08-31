import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _usernameKey = 'username';
  static const String _emailKey = 'email';
  static const String _profilePicKey = 'profile_pic';

  // Save user session
  static Future<void> saveUserSession({
    required String token,
    required String userId,
    required String username,
    required String email,
    String? profilePic,
  }) async {
    print('🔐 Saving user session:');
    print('   - User ID: $userId');
    print('   - Username: $username');
    print('   - Token length: ${token.length}');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_emailKey, email);
    
    if (profilePic != null) {
      await prefs.setString(_profilePicKey, profilePic);
      print('   - Profile picture: $profilePic');
    }
  }

  // Get user token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    print('🔑 Retrieved token: ${token != null ? '${token.length} chars' : 'null'}');
    return token;
  }

  // Get user ID
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  // Get user data
  static Future<Map<String, String?>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token': prefs.getString(_tokenKey),
      'userId': prefs.getString(_userIdKey),
      'username': prefs.getString(_usernameKey),
      'email': prefs.getString(_emailKey),
      'profilePic': prefs.getString(_profilePicKey),
    };
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) != null;
  }

  // Clear user session (logout)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_profilePicKey);
  }
}
