import 'package:flutter/material.dart';
import 'package:chat_app_flutter/services/auth_service.dart';
import 'package:chat_app_flutter/main.dart';
import 'inbox_screen.dart';
import 'login_screen.dart';
import '../services/socket_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      final isLoggedIn = await AuthService.isLoggedIn();
      
      if (!mounted) return;
      
      if (isLoggedIn) {
        // User is logged in, get user data and navigate to inbox
        final userData = await AuthService.getUserData();
        
        if (!mounted) return;
        
        // Connect to socket
        socketService.connect(userId: userData['userId'] ?? '');
        
        // Use the global navigator key to ensure we're using the root navigator
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(
            builder: (context) => InboxScreen(
              currentUser: userData['username'] ?? '',
              jwtToken: userData['token'] ?? '',
            ),
          ),
        );
      } else {
        // User is not logged in, navigate to login screen
        if (!mounted) return;
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      // If any error occurs, default to login screen
      debugPrint('Error in _checkAuthStatus: $e');
      if (mounted) {
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
