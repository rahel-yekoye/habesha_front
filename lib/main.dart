import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'services/socket_service.dart';
import 'services/call_invitation_service.dart';
import 'providers/theme_provider.dart';

@immutable
class AvatarColors extends ThemeExtension<AvatarColors> {
  final Color defaultAvatar;
  final Color groupAvatar;
  final Color userAvatar;

  const AvatarColors({
    required this.defaultAvatar,
    required this.groupAvatar,
    required this.userAvatar,
  });

  @override
  AvatarColors copyWith({
    Color? defaultAvatar,
    Color? groupAvatar,
    Color? userAvatar,
  }) {
    return AvatarColors(
      defaultAvatar: defaultAvatar ?? this.defaultAvatar,
      groupAvatar: groupAvatar ?? this.groupAvatar,
      userAvatar: userAvatar ?? this.userAvatar,
    );
  }

  @override
  AvatarColors lerp(ThemeExtension<AvatarColors>? other, double t) {
    if (other is! AvatarColors) {
      return this;
    }
    return AvatarColors(
      defaultAvatar: Color.lerp(defaultAvatar, other.defaultAvatar, t) ?? defaultAvatar,
      groupAvatar: Color.lerp(groupAvatar, other.groupAvatar, t) ?? groupAvatar,
      userAvatar: Color.lerp(userAvatar, other.userAvatar, t) ?? userAvatar,
    );
  }
}

// Global navigator key for navigation from anywhere in the app
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final SocketService socketService = SocketService();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            title: 'Chat App',
            theme: ThemeData(
              colorScheme: ColorScheme.light(
                primary: const Color(0xFF0088CC), // Telegram Blue
                primaryContainer: const Color(0xFF0077B5), // Darker Blue
                secondary: const Color(0xFF5AC8FB), // Light Blue
                surface: Colors.white, // Light Gray Background
                onPrimary: Colors.white,
                onSecondary: Colors.black87,
                onSurface: Colors.black87,
                brightness: Brightness.light,
                surfaceContainerHighest: Colors.white,
                onSurfaceVariant: const Color(0xFF6B7B8F), // Gray Text
              ),
              useMaterial3: true,
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFFFFFFFF), // White
                foregroundColor: Colors.black87, // Dark Text
                elevation: 1,
                centerTitle: true,
              ),
              scaffoldBackgroundColor: const Color(0xFFF5F5F5), // Light Gray Background
              cardTheme: CardTheme(
                elevation: 1,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              // Custom color for avatar placeholders
              extensions: <ThemeExtension<dynamic>>[
                AvatarColors(
                  defaultAvatar: const Color(0xFF0088CC), // Telegram Blue
                  groupAvatar: const Color(0xFF34B7F1),   // Lighter Blue
                  userAvatar: const Color(0xFF5AC8FB),    // Light Blue
                ),
              ],
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.dark(
                primary: const Color(0xFF2AABEE), // Telegram Blue
                primaryContainer: const Color(0xFF1E96D2), // Darker Blue
                secondary: const Color(0xFF5AC8FB), // Light Blue
                surface: const Color(0xFF18222C), // Dark Blue-Black
                onPrimary: Colors.white,
                onSecondary: Colors.black87,
                onSurface: Colors.white,
                brightness: Brightness.dark,
                surfaceContainerHighest: const Color(0xFF1F2E3D), // Slightly Lighter Blue-Gray
                onSurfaceVariant: const Color(0xFFB0C4DE), // Light Blue-Gray Text
              ),
              useMaterial3: true,
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF17212B), // Dark Blue-Gray
                foregroundColor: Colors.white,
                elevation: 1,
                centerTitle: true,
              ),
              scaffoldBackgroundColor: const Color(0xFF0E1621), // Dark Blue-Black
              cardTheme: CardTheme(
                elevation: 1,
                color: const Color(0xFF17212B), // Dark Blue-Gray
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              dividerColor: Colors.white12,
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: const Color(0xFF1F2E3D), // Slightly Lighter Blue-Gray
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                hintStyle: const TextStyle(color: Color(0xFF7F8B9A)), // Muted Blue-Gray
              ),
              // Custom color for avatar placeholders
              extensions: <ThemeExtension<dynamic>>[
                AvatarColors(
                  defaultAvatar: const Color(0xFF2AABEE), // Telegram Blue
                  groupAvatar: const Color(0xFF34B7F1),   // Lighter Blue
                  userAvatar: const Color(0xFF5AC8FB),    // Light Blue
                ),
              ],
            ),
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
            // Add error handling for unknown routes
            onGenerateRoute: (settings) {
              // If we don't recognize the route, redirect to splash
              return MaterialPageRoute(
                builder: (context) => const SplashScreen(),
              );
            },
            // Add error builder for better error handling
            builder: (context, child) {
              ErrorWidget.builder = (FlutterErrorDetails errorDetails) {
                return Scaffold(
                  appBar: AppBar(
                    title: const Text('An error occurred'),
                  ),
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Something went wrong. Please restart the app.'),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            // Try to recover by going back to splash
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (context) => const SplashScreen(),
                              ),
                              (route) => false,
                            );
                          },
                          child: const Text('Restart App'),
                        ),
                      ],
                    ),
                  ),
                );
              };
              return child!;
            },
          );
        },
      ),
    );
  }
}
