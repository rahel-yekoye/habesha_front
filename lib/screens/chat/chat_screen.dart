import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:chat_app_flutter/main.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';

import '../../models/message.dart' as models;
import '../../services/profile_service.dart' show ProfileService;
import '../../services/api_service.dart';
import '../../services/socket_service.dart';
import 'widgets.dart';

class ChatScreen extends StatefulWidget {
  final String currentUser;
  final String otherUser;
  final String jwtToken;
  final SocketService socketService; // Assuming you have this service

  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.otherUser,
    required this.jwtToken,
    required this.socketService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<models.Message> messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isOtherTyping = false;
  bool _otherOnline = false;
  models.Message? _replyingToMessage;
  String? _editingMessageId;
  TextEditingController? _editController;
  bool _showEmojiPicker = false;
  final FocusNode _focusNode = FocusNode();
  // Removed selection state as we're using a single action menu
  final TextEditingController _replyController = TextEditingController();

  // Delivery status tracking (IDs or clientIds marked as delivered)
  final Set<String> _deliveredSet = <String>{};
  final List<PlatformFile> _selectedFiles = [];

  Timer? _undoTimer;
  final List<models.Message> _recentlyDeletedMessages = [];

  // Use global CallManager instead of creating a new instance

  DateTime? _otherLastSeen;
  Timer? _typingTimeout;
  Timer? _selfTypingDebounce;

  // Pagination state
  bool _isInitialLoading = false;

  Map<String, dynamic>? _otherUserProfile;

  @override
  void initState() {
    super.initState();
    _connectToSocket();

    // CallManager is now initialized globally in main.dart

    // Scroll listener for pagination (load older when reaching top)
    _scrollController.addListener(_onScroll);

    // Typing emitter: debounce on local text changes
    _controller.addListener(_onTextChanged);

    // Initial presence fetch
    _fetchPresence();

    // Load initial messages and user profile
    _loadInitialMessages();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final profile = await _getUserProfile(widget.otherUser);
      if (mounted) {
        setState(() {
          _otherUserProfile = profile;
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _replyController.dispose();
    _editController?.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _undoTimer?.cancel();
    _typingTimeout?.cancel();
    _selfTypingDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _controller.removeListener(_onTextChanged);
    super.dispose();
  }

  Future<void> _loadInitialMessages() async {
    if (_isInitialLoading) return;
    setState(() => _isInitialLoading = true);
    try {
      final loaded = await ApiService.getMessages(
        user1: widget.currentUser,
        user2: widget.otherUser,
        currentUser: widget.currentUser,
        token: widget.jwtToken,
        limit: 30,
      );
      if (!mounted) return;
      setState(() {
        messages = loaded.where((m) => !m.deleted).toList()
          ..sort((a, b) => DateTime.parse(a.timestamp)
              .compareTo(DateTime.parse(b.timestamp)));
        _hasMore = loaded.length >= 30;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottomSmooth();
      });
      _markMessagesAsRead();
    } catch (e) {
      print('❌ Initial load error: $e');
    } finally {
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingMore || !_hasMore || messages.isEmpty) return;
    setState(() => _isLoadingMore = true);
    try {
      final oldest = DateTime.tryParse(messages.first.timestamp);
      final loaded = await ApiService.getMessages(
        user1: widget.currentUser,
        user2: widget.otherUser,
        currentUser: widget.currentUser,
        token: widget.jwtToken,
        limit: 30,
        before: oldest,
      );
      if (!mounted) return;
      if (loaded.isEmpty) {
        setState(() => _hasMore = false);
      } else {
        setState(() {
          final newOnes = loaded.where((m) => !m.deleted).toList();
          messages = [...newOnes, ...messages];
          messages.sort((a, b) => DateTime.parse(a.timestamp)
              .compareTo(DateTime.parse(b.timestamp)));
          _hasMore = loaded.length >= 30;
        });
      }
    } catch (e) {
      print('❌ Load older error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  // Scroll listener
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadOlderMessages();
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  Future<Map<String, dynamic>> _getUserProfile(String username) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? widget.jwtToken;

      // Check if token is expired
      if (token != null && token.isNotEmpty) {
        try {
          // Simple check for JWT expiration (this is a basic check, you might want to use a JWT library for production)
          final parts = token.split('.');
          if (parts.length == 3) {
            final payload = jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
            final exp = payload['exp'] as int?;
            if (exp != null &&
                DateTime.fromMillisecondsSinceEpoch(exp * 1000)
                    .isBefore(DateTime.now())) {
              await _logout();
              return {'username': username};
            }
          }
        } catch (e) {
          print('❌ Error checking token: $e');
          await _logout();
          return {'username': username};
        }
      }

      // Get the user profile directly by username
      final response = await http.get(
        Uri.parse('http://localhost:4000/profile/$username'),
        headers: {
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // If token is invalid or expired, log out
        if (response.body.contains('jwt expired') ||
            response.body.contains('jwt malformed')) {
          await _logout();
        }
        // Try without authentication
        final publicResponse = await http.get(
          Uri.parse('http://localhost:4000/profile/$username'),
          headers: {'Content-Type': 'application/json'},
        );

        if (publicResponse.statusCode == 200) {
          return jsonDecode(publicResponse.body);
        }
        return {'username': username};
      } else if (response.statusCode == 404) {
        return {'username': username};
      } else {
        print(
            '❌ Error fetching profile for $username: ${response.statusCode} - ${response.body}');
        return {'username': username};
      }
    } catch (e) {
      print('❌ Error in _getUserProfile: $e');
      rethrow; // Re-throw to be caught by the FutureBuilder
    }
  }

  // Compose current private room id
  String _currentRoomId() {
    return widget.currentUser.compareTo(widget.otherUser) < 0
        ? '${widget.currentUser}_${widget.otherUser}'
        : '${widget.otherUser}_${widget.currentUser}';
  }

  // Local typing -> emit typing, debounce stop
  void _onTextChanged() {
    final text = _controller.text;
    if (text.isNotEmpty) {
      SocketService().startTyping(
        to: widget.otherUser,
        isGroup: false,
        roomId: _currentRoomId(),
      );
      _selfTypingDebounce?.cancel();
      _selfTypingDebounce = Timer(const Duration(seconds: 4), _emitStopTyping);
    } else {
      _emitStopTyping();
    }
  }

  void _emitStopTyping() {
    SocketService().stopTyping(
      to: widget.otherUser,
      isGroup: false,
      roomId: _currentRoomId(),
    );
  }

  // Mark messages as read via REST (backend will propagate receipts)
  Future<void> _markMessagesAsRead() async {
    try {
      final url = Uri.parse('http://localhost:4000/messages/mark-read');
      await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode({
          'user': widget.currentUser,
          'otherUser': widget.otherUser,
        }),
      );
    } catch (e) {
      debugPrint('mark-read failed: $e');
    }
  }

  // Presence fetch via ApiService
  Future<void> _fetchPresence() async {
    try {
      final pres = await ApiService.getPresence(
          userIds: [widget.otherUser], token: widget.jwtToken);
      final data = pres[widget.otherUser];
      if (data is Map) {
        setState(() {
          _otherOnline = data['online'] == true;
          final ls = data['lastSeen'];
          _otherLastSeen = (ls is int)
              ? DateTime.fromMillisecondsSinceEpoch(ls)
              : (ls is String ? DateTime.tryParse(ls) : null);
        });
      }
    } catch (e) {
      print('Presence fetch error: $e');
    }
  }

  String _formatLastSeen(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  bool _socketInitialized = false;

  void _connectToSocket() async {
    if (_socketInitialized) return; // prevent reinitializing
    _socketInitialized = true;

    print('Registering listeners for user: ${widget.currentUser}');

    await SocketService().connect(
      userId: widget.currentUser,
      jwtToken: widget.jwtToken,
    );

    final roomId = widget.currentUser.compareTo(widget.otherUser) < 0
        ? '${widget.currentUser}_${widget.otherUser}'
        : '${widget.otherUser}_${widget.currentUser}';

    SocketService().joinRoom(roomId);

    SocketService().onMessageReceived((msg) {
      print('[SOCKET] receive_message event: ${msg.content}');
      print('📥 Received message id: ${msg.id}, clientId: ${msg.clientId}');

      final isDuplicate = messages.any((m) =>
          (msg.clientId != null &&
              msg.clientId!.isNotEmpty &&
              m.clientId == msg.clientId) ||
          (msg.id.isNotEmpty && m.id == msg.id));

      if (!isDuplicate) {
        if (mounted) {
          setState(() {
            messages.add(msg);
            messages.sort((a, b) {
              final aTime = DateTime.tryParse(a.timestamp) ?? DateTime(0);
              final bTime = DateTime.tryParse(b.timestamp) ?? DateTime(0);
              return aTime.compareTo(bTime);
            });
          });

          _scrollToBottomSmooth();

          // Only mark as read if the app is in foreground and user is viewing this chat
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && ModalRoute.of(context)?.isCurrent == true) {
              // Delay marking as read to ensure user actually sees the message
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted && ModalRoute.of(context)?.isCurrent == true) {
                  _markMessagesAsRead();
                }
              });
            }
          });
        }
      }
    });

    // Typing indicators
    SocketService().onTyping((data) {
      if (data['from'] == widget.otherUser) {
        if (mounted) setState(() => _isOtherTyping = true);
        _typingTimeout?.cancel();
        _typingTimeout = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _isOtherTyping = false);
        });
      }
    });
    SocketService().onStopTyping((data) {
      if (data['from'] == widget.otherUser) {
        if (mounted) setState(() => _isOtherTyping = false);
      }
    });

    // Listen for profile updates to update chat display names and profile pictures
    SocketService().socket.on('user_profile_updated', (data) {
      if (!mounted) return;
      try {
        final userId = data['userId']?.toString() ?? '';
        final newUsername = data['username']?.toString() ?? '';
        final newProfilePicture = data['profilePicture']?.toString();

        // If this is the other user in the chat, update the display
        if (widget.otherUser == userId || widget.otherUser == newUsername) {
          if (mounted) {
            setState(() {
              // Update the other user's profile data
              _otherUserProfile = {
                ...?_otherUserProfile,
                'username':
                    newUsername.isNotEmpty ? newUsername : widget.otherUser,
                'profilePicture':
                    newProfilePicture ?? _otherUserProfile?['profilePicture'],
                'name': newUsername.isNotEmpty ? newUsername : widget.otherUser,
              };

              // Update messages with new username and profile picture
              for (int i = 0; i < messages.length; i++) {
                bool updated = false;
                var updatedMessage = messages[i];

                if (messages[i].sender == widget.otherUser) {
                  // Create or update sender metadata when username changes
                  final newMetadata = {
                    ...?updatedMessage.senderMetadata,
                    'name':
                        newUsername.isNotEmpty ? newUsername : widget.otherUser,
                    if (newProfilePicture != null)
                      'profilePicture': newProfilePicture,
                  };

                  updatedMessage = updatedMessage.copyWith(
                    sender: newUsername,
                    senderMetadata: newMetadata,
                  );
                  updated = true;
                }

                if (messages[i].receiver == widget.otherUser) {
                  updatedMessage =
                      updatedMessage.copyWith(receiver: newUsername);
                  updated = true;
                }

                // Update sender metadata for existing messages
                if (messages[i].sender == widget.otherUser) {
                  final currentMetadata = updatedMessage.senderMetadata ?? {};
                  final updatedMetadata = {
                    ...currentMetadata,
                    'name':
                        newUsername.isNotEmpty ? newUsername : widget.otherUser,
                    if (newProfilePicture != null)
                      'profilePicture': newProfilePicture,
                  };

                  updatedMessage = updatedMessage.copyWith(
                    senderMetadata: updatedMetadata,
                  );
                  updated = true;
                }

                if (updated) {
                  messages[i] = updatedMessage;
                }
              }

              debugPrint(
                  '📱 User profile updated: $newUsername, Profile Picture: ${newProfilePicture != null ? 'Updated' : 'No change'}');
            });
          }
        }
      } catch (e) {
        debugPrint('Error handling profile update: $e');
      }
    });

    // Presence updates
    SocketService().onPresenceUpdate((data) {
      final userId = data['userId']?.toString();
      if (userId != null && userId == widget.otherUser) {
        if (mounted) {
          setState(() {
            _otherOnline = data['online'] == true;
            final ls = data['lastSeen'];
            _otherLastSeen = (ls is int)
                ? DateTime.fromMillisecondsSinceEpoch(ls)
                : (ls is String ? DateTime.tryParse(ls) : null);
          });
        }
      }
    });

    // Read receipts (bulk)
    SocketService().onMessagesRead((data) {
      final reader = data['reader']?.toString();
      final ids = (data['messageIds'] is List)
          ? List<String>.from(
              (data['messageIds'] as List).map((e) => e.toString()))
          : <String>[];
      if (reader == widget.otherUser && ids.isNotEmpty) {
        if (mounted) {
          setState(() {
            messages = messages.map((m) {
              if (ids.contains(m.id)) {
                final rb = {...m.readBy, reader!}.toList();
                return m.copyWith(readBy: rb);
              }
              return m;
            }).toList();
          });
        }
      }
    });

    // Read receipt (single)
    SocketService().onMessageRead((data) {
      if (!mounted) return;
      final String reader = data['reader'];
      final List<String> messageIds =
          List<String>.from(data['messageIds'] ?? []);

      setState(() {
        for (var msgId in messageIds) {
          final msgIndex = messages.indexWhere((m) => m.id == msgId);
          if (msgIndex != -1) {
            messages[msgIndex].readBy.add(reader);
          }
        }
      });
    });

    // Delivery receipt (sent to sender when receiver is online)
    SocketService().onMessageDelivered((data) {
      final to = data['to']?.toString();
      final id = data['messageId']?.toString();
      final clientId = data['clientId']?.toString();
      // Ensure it's for this chat (we are sender, 'to' should be other user)
      if (to == widget.otherUser) {
        if (mounted) {
          setState(() {
            if (id != null && id.isNotEmpty) _deliveredSet.add(id);
            if (clientId != null && clientId.isNotEmpty)
              _deliveredSet.add(clientId);
          });
        }
      }
    });

    SocketService().onMessageEdited((data) {
      if (!mounted) return;
      final String messageId = data['messageId'];
      final String newContent = data['newContent'];

      final messageIndex = messages.indexWhere((msg) => msg.id == messageId);
      if (messageIndex != -1) {
        setState(() {
          messages[messageIndex] = messages[messageIndex].copyWith(
            content: newContent,
            edited: true,
          );
        });
      }
    });

    // Deletions: for me (remove locally only for this user)
    SocketService().onMessagesDeletedForMe((ids) {
      if (!mounted) return;
      setState(() {
        messages.removeWhere((m) => ids.contains(m.id));
      });
    });

    // Deletions: for everyone (mark as deleted and sanitize)
    SocketService().onMessagesDeletedForEveryone((ids) {
      if (!mounted) return;
      setState(() {
        messages = messages
            .map((m) => ids.contains(m.id)
                ? m.copyWith(
                    deleted: true,
                    content: 'This message was deleted',
                    fileUrl: '',
                    emojis: [],
                  )
                : m)
            .toList();
      });
    });

    // Incoming calls are now handled by CallManager automatically

    // Reactions updates
    SocketService().onReactionsUpdated((data) {
      if (!mounted) return;
      try {
        final String messageId = data['messageId']?.toString() ?? '';
        final List<dynamic> list = (data['reactions'] as List?) ?? [];
        final List<Map<String, String>> reactions = list
            .map<Map<String, String>>((e) {
              if (e is Map) {
                final m = Map<String, dynamic>.from(e);
                return {
                  'user': m['user']?.toString() ?? '',
                  'emoji': m['emoji']?.toString() ?? '',
                };
              }
              return {'user': '', 'emoji': ''};
            })
            .where((m) => m['user']!.isNotEmpty && m['emoji']!.isNotEmpty)
            .toList();

        setState(() {
          final idx = messages.indexWhere((m) => m.id == messageId);
          if (idx != -1) {
            messages[idx] = messages[idx].copyWith(reactions: reactions);
          }
        });
      } catch (e) {
        debugPrint('Error applying reactions update: $e');
      }
    });

    // Message editing updates
    SocketService().onMessageEdited((data) {
      if (!mounted) return;
      try {
        final String messageId = data['messageId']?.toString() ?? '';
        final String newContent = data['newContent']?.toString() ?? '';
        final bool edited = data['edited'] ?? true;

        setState(() {
          final idx = messages.indexWhere((m) => m.id == messageId);
          if (idx != -1) {
            messages[idx] = messages[idx].copyWith(
              content: newContent,
              edited: edited,
            );
          }
        });
      } catch (e) {
        debugPrint('Error applying message edit update: $e');
      }
    });
  }

  Future<void> uploadAndSendFile(PlatformFile file) async {
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now().toIso8601String();
    final roomId = widget.currentUser.compareTo(widget.otherUser) < 0
        ? '${widget.currentUser}_${widget.otherUser}'
        : '${widget.otherUser}_${widget.currentUser}';

    // Get current user's profile data for sender metadata
    final currentUserProfile = await _getUserProfile(widget.currentUser);

    // First upload the file
    final fileUrl = await _uploadFileToServer(file);

    if (fileUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload file')),
      );
      return;
    }

    // Create message with the uploaded file URL
    final message = models.Message(
      id: '',
      clientId: tempId,
      sender: widget.currentUser,
      receiver: widget.otherUser,
      content: '',
      timestamp: timestamp,
      isGroup: false,
      emojis: [],
      fileUrl: fileUrl,
      readBy: [widget.currentUser],
      isFile: true,
      senderMetadata: {
        'name': currentUserProfile?['name'] ?? widget.currentUser,
        'profilePicture': currentUserProfile?['profilePicture'],
      },
    );

    // Add to local state immediately for instant feedback
    setState(() {
      messages.add(message);
      messages.sort((a, b) =>
          DateTime.parse(a.timestamp).compareTo(DateTime.parse(b.timestamp)));
    });
    _scrollToBottomSmooth();

    // Prepare message data for server
    final messageData = {
      'roomId': roomId,
      'sender': widget.currentUser,
      'receiver': widget.otherUser,
      'content': '',
      'timestamp': timestamp,
      'fileUrl': fileUrl,
      'clientId': tempId,
      'isFile': true,
    };

    print('Sending file message data: $messageData');
    SocketService().sendMessage(messageData);

    setState(() {
      _selectedFiles.remove(file);
    });
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();

    if (_selectedFiles.isNotEmpty) {
      for (final file in _selectedFiles) {
        await uploadAndSendFile(file);
      }
      if (text.isNotEmpty) {
        _sendMessage(text);
      }
      setState(() {
        _selectedFiles.clear();
        _controller.clear();
      });
    } else if (text.isNotEmpty) {
      _sendMessage(text);
      _controller.clear();
      _emitStopTyping();
    }
  }

  void _scrollToBottomSmooth() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _editMessage(String messageId, String newText) async {
    final messageIndex = messages.indexWhere((msg) => msg.id == messageId);
    if (messageIndex == -1) return;

    setState(() {
      messages[messageIndex] =
          messages[messageIndex].copyWith(content: newText, edited: true);
    });

    try {
      final url = Uri.parse('http://localhost:4000/messages/$messageId');
      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode({'content': newText, 'edited': true}),
      );
      if (response.statusCode == 200) {
        print('Message edited successfully on backend');
      } else {
        print('Failed to edit message on backend: ${response.body}');
      }
    } catch (e) {
      print('Error editing message: $e');
    }
  }

  Future<void> _sendMessage(String content, {String fileUrl = ''}) async {
    if (content.trim().isEmpty && fileUrl.isEmpty) return;

    final roomId = widget.currentUser.compareTo(widget.otherUser) < 0
        ? '${widget.currentUser}_${widget.otherUser}'
        : '${widget.otherUser}_${widget.currentUser}';

    final currentUserProfile = await _getUserProfile(widget.currentUser);
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final timestamp = DateTime.now().toIso8601String();

    // Create message object for local state
    final message = models.Message(
      id: '',
      clientId: tempId,
      sender: widget.currentUser,
      receiver: widget.otherUser,
      content: content.trim(),
      timestamp: timestamp,
      isGroup: false,
      emojis: [],
      fileUrl: fileUrl,
      readBy: [widget.currentUser],
      isFile: fileUrl.isNotEmpty,
      senderMetadata: {
        'name': currentUserProfile?['name'] ?? widget.currentUser,
        'profilePicture': currentUserProfile?['profilePicture'],
      },
      replyTo: _replyingToMessage?.id,
    );

    // Add to local state immediately for instant feedback
    setState(() {
      messages.add(message);
      messages.sort((a, b) =>
          DateTime.parse(a.timestamp).compareTo(DateTime.parse(b.timestamp)));
    });

    _scrollToBottomSmooth();

    // Prepare message data for server
    final messageData = {
      'roomId': roomId,
      'sender': widget.currentUser,
      'receiver': widget.otherUser,
      'content': content.trim(),
      'timestamp': timestamp,
      'fileUrl': fileUrl,
      'clientId': tempId,
      'replyTo': _replyingToMessage?.id,
    };

    print('Sending message data: $messageData');
    SocketService().sendMessage(messageData);

    _replyingToMessage = null;
    _emitStopTyping();
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  void _showProfilePictureGallery(String username) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: _getUserProfile(username),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                );
              }

              if (snapshot.hasError || !snapshot.hasData) {
                return AlertDialog(
                  backgroundColor: Colors.black,
                  content: const Text('Failed to load profile',
                      style: TextStyle(color: Colors.white)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close',
                          style: TextStyle(color: Colors.blue)),
                    ),
                  ],
                );
              }

              final userProfile = snapshot.data!;
              final currentPicture = userProfile['profilePicture'];
              final pictureHistory =
                  userProfile['profilePictureHistory'] as List<dynamic>? ?? [];

              final allPictures = <String>[];
              if (currentPicture != null) allPictures.add(currentPicture);
              allPictures.addAll(pictureHistory.cast<String>());

              if (allPictures.isEmpty) {
                return AlertDialog(
                  backgroundColor: Colors.black,
                  content: const Text('No profile pictures available',
                      style: TextStyle(color: Colors.white)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close',
                          style: TextStyle(color: Colors.blue)),
                    ),
                  ],
                );
              }

              return StatefulBuilder(
                builder: (context, setGalleryState) {
                  final pageController = PageController();
                  int currentPage = 0;

                  return GestureDetector(
                    onVerticalDragEnd: (details) {
                      if (details.primaryVelocity != null &&
                          details.primaryVelocity! > 0) {
                        Navigator.pop(context);
                      }
                    },
                    child: Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(0),
                      child: Stack(
                        children: [
                          // Main image viewer
                          PageView.builder(
                            controller: pageController,
                            itemCount: allPictures.length,
                            onPageChanged: (index) {
                              setGalleryState(() => currentPage = index);
                            },
                            itemBuilder: (context, index) {
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: PhotoView(
                                  key: ValueKey<String>(allPictures[index]),
                                  imageProvider: CachedNetworkImageProvider(
                                    allPictures[index],
                                    headers: {
                                      'Authorization':
                                          'Bearer ${widget.jwtToken}'
                                    },
                                  ),
                                  loadingBuilder: (context, event) => Center(
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      padding: const EdgeInsets.all(8),
                                      child: const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  backgroundDecoration:
                                      const BoxDecoration(color: Colors.black),
                                  minScale: PhotoViewComputedScale.contained,
                                  maxScale: PhotoViewComputedScale.covered * 3,
                                  heroAttributes: PhotoViewHeroAttributes(
                                    tag:
                                        'profile-$username-${allPictures[index]}',
                                    transitionOnUserGestures: true,
                                  ),
                                ),
                              );
                            },
                          ),

                          // Top gradient overlay
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 100,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.7),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Bottom gradient overlay with page indicator
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Column(
                              children: [
                                // Page indicator dots
                                if (allPictures.length > 1)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: List<Widget>.generate(
                                        allPictures.length,
                                        (index) => Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: currentPage == index
                                                ? Colors.white
                                                : Colors.white.withOpacity(0.5),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // Bottom gradient
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 30, horizontal: 20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        Colors.black.withOpacity(0.8),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // Username and photo count
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            username,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (allPictures.length > 1)
                                            Text(
                                              '${currentPage + 1} of ${allPictures.length} photos',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 14,
                                              ),
                                            ),
                                        ],
                                      ),

                                      // Close button
                                      IconButton(
                                        icon: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: const BoxDecoration(
                                            color: Colors.black38,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.close,
                                              color: Colors.white, size: 24),
                                        ),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteMessages(
      List<String> messageIds, String deleteType) async {
    try {
      if (deleteType == 'for_everyone') {
        await SocketService().deleteMessageForEveryone(
          messageIds,
          otherUserId: widget.otherUser,
        );
      } else {
        await SocketService().deleteMessageForMe(messageIds);
      }

      setState(() {
        messages.removeWhere((msg) => messageIds.contains(msg.id));
      });
    } catch (e) {
      print('Error deleting messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete messages: $e')),
        );
      }
    }
  }

  Future<void> _deleteMessage(String messageId,
      {bool forEveryone = false}) async {
    try {
      if (forEveryone) {
        await SocketService().deleteMessageForEveryone(
          [messageId],
          otherUserId: widget.otherUser,
        );
      } else {
        await SocketService().deleteMessageForMe([messageId]);
      }

      if (mounted) {
        setState(() {
          messages.removeWhere((msg) => msg.id == messageId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete message: $e')),
        );
      }
    }
  }

  void _showMessageOptions(models.Message message) {
    final isMe = message.sender == widget.currentUser;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  _setReplyingTo(message);
                },
              ),
              if (isMe) ...[
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    _startEditing(message);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Delete for me',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(message.id, forEveryone: false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Delete for everyone',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(message.id, forEveryone: true);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<List<PlatformFile>> pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null) {
        return result.files;
      }
      return [];
    } catch (e) {
      print('Error picking files: $e');
      return [];
    }
  }

  Future<String?> _uploadFileToServer(PlatformFile file) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://localhost:4000/upload'),
      );

      request.headers['Authorization'] = 'Bearer ${widget.jwtToken}';

      if (kIsWeb) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path!,
          filename: file.name,
        ));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return responseData['fileUrl'] as String?;
      } else {
        print('Failed to upload file. Status code: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  Widget _buildProfilePicture() {
    final username =
        _otherUserProfile?['username']?.toString() ?? widget.otherUser;

    return FutureBuilder<Map<String, dynamic>>(
      future: _getUserProfile(username),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildDefaultAvatar(username: username);
        }

        if (snapshot.hasError || !snapshot.hasData) {
          print('❌ Error loading profile for $username: ${snapshot.error}');
          return _buildDefaultAvatar(username: username);
        }

        final data = snapshot.data!;
        final profilePic = data['profilePicture'] ??
            data['user']?['profilePicture'] ??
            data['data']?['profilePicture'];

        if (profilePic != null && profilePic.toString().isNotEmpty) {
          final imageUrl =
              ProfileService.getProfilePictureUrl(profilePic.toString());
          print('🖼️ Loading profile picture for $username: $imageUrl');

          return GestureDetector(
            onTap: () => _showProfilePictureGallery(username),
            child: Hero(
              tag: 'profile-picture-$username',
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                httpHeaders: const {'Cache-Control': 'max-age=3600'},
                imageBuilder: (context, imageProvider) => Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withOpacity(0.5),
                      width: 1.5,
                    ),
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                placeholder: (context, url) =>
                    _buildDefaultAvatar(username: username),
                errorWidget: (context, url, error) {
                  print(
                      '❌ Error loading profile picture for $username: $error');
                  return _buildDefaultAvatar(username: username);
                },
                memCacheHeight: 80,
                memCacheWidth: 80,
                maxHeightDiskCache: 160,
                maxWidthDiskCache: 160,
              ),
            ),
          );
        }

        return GestureDetector(
          onTap: () => _showProfilePictureGallery(username),
          child: _buildDefaultAvatar(username: username),
        );
      },
    );
  }

  Widget _buildDefaultAvatar({String? username}) {
    final initial =
        username?.isNotEmpty == true ? username![0].toUpperCase() : '?';
    final colorIndex =
        (username?.hashCode ?? 0).abs() % Colors.primaries.length;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.primaries[colorIndex].withOpacity(0.7),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // Copy message text to clipboard
  void _copyMessage(models.Message msg) {
    if (msg.content.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: msg.content));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message copied to clipboard')),
        );
      }
    }
  }

  // Set message to reply to
  void _setReplyingTo(models.Message msg) {
    setState(() {
      _replyingToMessage = msg;
    });
    // Optionally focus the text field
    FocusScope.of(context).requestFocus(_focusNode);
  }

  // Start editing a message
  void _startEditing(models.Message msg) {
    setState(() {
      _editingMessageId = msg.id;
      _editController = TextEditingController(text: msg.content);
    });
    // Focus the message input field
    FocusScope.of(context).requestFocus(_focusNode);
  }

  // Save edited message
  Future<void> _saveEditedMessage() async {
    if (_editingMessageId == null || _editController == null) return;

    final newText = _editController!.text.trim();
    if (newText.isEmpty) return;

    try {
      await SocketService().editMessage(_editingMessageId!, newText);

      if (mounted) {
        setState(() {
          final index = messages.indexWhere((m) => m.id == _editingMessageId);
          if (index != -1) {
            messages[index] = messages[index].copyWith(
              content: newText,
              edited: true,
            );
          }
          _editingMessageId = null;
          _editController?.dispose();
          _editController = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to edit message: $e')),
        );
      }
    }
  }

  // Cancel editing
  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _editController?.dispose();
      _editController = null;
    });
  }

  // Show reaction picker
  void _showReactionPicker(models.Message msg) async {
    if (msg.id.isEmpty) return;

    final reactions = [
      '👍',
      '❤️',
      '😂',
      '😮',
      '😢',
      '😡',
      '👏',
      '🔥',
      '💯',
      '🎉'
    ];
    final currentUser = widget.currentUser;

    try {
      await showModalBottomSheet(
        context: context,
        isDismissible: true,
        enableDrag: true,
        builder: (context) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('React to message',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: reactions.map((emoji) {
                  final userAlreadyReacted = msg.reactions.any(
                      (r) => r['user'] == currentUser && r['emoji'] == emoji);

                  return GestureDetector(
                    onTap: () async {
                      try {
                        Navigator.pop(context);
                        if (userAlreadyReacted) {
                          await SocketService()
                              .removeReactionFromMessage(msg.id);
                        } else {
                          await SocketService().reactToMessage(msg.id, emoji);
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Failed to update reaction: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: userAlreadyReacted
                            ? Colors.blue.withOpacity(0.2)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: userAlreadyReacted
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to show reactions: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<models.Message> filteredMessages =
        messages.where((msg) => !msg.deleted).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            // Profile picture
            GestureDetector(
              onTap: () => _showProfilePictureGallery(widget.otherUser),
              child: _buildProfilePicture(),
            ),
            const SizedBox(width: 12),
            // Username and status
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.otherUser,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_otherOnline)
                  const Text(
                    'online',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                    ),
                  )
                else if (_otherLastSeen != null)
                  Text(
                    'last seen ${_formatLastSeen(_otherLastSeen!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.green),
            tooltip: 'Voice Call',
            onPressed: _onVoiceCallPressed,
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.blue),
            tooltip: 'Video Call',
            onPressed: _onVideoCallPressed,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: filteredMessages.length + (_isLoadingMore ? 1 : 0),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  itemBuilder: (context, index) {
                    if (_isLoadingMore && index == 0) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Center(
                            child: SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    final adjIndex = _isLoadingMore ? index - 1 : index;
                    final msg = filteredMessages[adjIndex];
                    final isMe = msg.sender == widget.currentUser;

                    return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                   onLongPress: () {
  final RenderBox box = context.findAncestorRenderObjectOfType<RenderBox>()!;
  final position = box.localToGlobal(Offset.zero);
  _showMessageActions(msg, position);
},
                      onDoubleTap: () {
                        _showReactionPicker(msg);
                      },
                      child: Container(
                        color: Colors.transparent,
                        child: Row(
                          mainAxisAlignment: isMe
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(12),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.7,
                              ),
                              decoration: BoxDecoration(
                                color: msg.sender == widget.currentUser
                                    ? Colors.blue[200]
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: isMe
                                      ? const Radius.circular(12)
                                      : Radius.zero,
                                  bottomRight: isMe
                                      ? Radius.zero
                                      : const Radius.circular(12),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  buildMessageContent(
                                      msg,
                                      _editingMessageId,
                                      _editController ??
                                          TextEditingController(),
                                      onEditCancel: () {
                                    setState(() {
                                      _editingMessageId = null;
                                      _editController?.clear();
                                    });
                                  }, onEditSave: (newText) async {
                                    if (newText.trim().isNotEmpty) {
                                      await _editMessage(
                                          msg.id, newText.trim());
                                      setState(() {
                                        _editingMessageId = null;
                                        _editController?.clear();
                                      });
                                    }
                                  }, getMessageById: (id) {
                                    try {
                                      return messages
                                          .firstWhere((m) => m.id == id);
                                    } catch (e) {
                                      return null;
                                    }
                                  }, onReactionTap: (msg) {
                                    _showReactionPicker(msg);
                                  }),
                                  if (isMe)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: _readStatusIcon(
                                          msg, widget.otherUser),
                                    ),
                                  const SizedBox(height: 4),
                                  // Reactions are handled in buildMessageContent in widgets.dart
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              chatInputField(
                controller: _controller,
                focusNode: _focusNode,
                onSend: _handleSend,
                showEmojiPicker: _showEmojiPicker,
                onEmojiToggle: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _showEmojiPicker = !_showEmojiPicker;
                  });
                },
                selectedFiles: _selectedFiles,
                onRemoveFile: (index) {
                  setState(() {
                    _selectedFiles.removeAt(index);
                  });
                },
                pickFiles: () async {
                  final files = await pickFiles();
                  if (files.isNotEmpty) {
                    setState(() {
                      _selectedFiles.addAll(files);
                    });
                    FocusScope.of(context).requestFocus(_focusNode);
                  }
                  return null;
                },
                replyingTo: _replyingToMessage,
                onCancelReply: () {
                  setState(() {
                    _replyingToMessage = null;
                  });
                },
              ),
            ],
          ),
          // Message actions are now handled by the bottom sheet in _showMessageActions
        ],
      ),
    );
  }

  // Show message actions menu when a message is long-pressed
  void _showMessageActions(models.Message msg, Offset position) {
    final isMe = msg.sender == widget.currentUser;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                _setReplyingTo(msg);
              },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _startEditing(msg);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(context);
                _copyMessage(msg);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(
                isMe ? 'Delete for me' : 'Remove',
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _deleteMessage(msg.id, forEveryone: false);
              },
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'Delete for everyone',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete for everyone?'),
                      content: const Text(
                          'This will delete the message for all participants. This action cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await _deleteMessage(msg.id, forEveryone: true);
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _readStatusIcon(models.Message msg, String otherUser) {
    if (!msg.sender.contains(widget.currentUser))
      return const SizedBox.shrink();
    // Read -> double check blue
    if (msg.readBy.contains(otherUser)) {
      return const Icon(Icons.done_all, size: 16, color: Colors.blueAccent);
    }
    // Delivered (but not read) -> single check grey
    final key = (msg.id.isNotEmpty ? msg.id : (msg.clientId ?? ''));
    if (key.isNotEmpty && _deliveredSet.contains(key)) {
      return const Icon(Icons.done, size: 16, color: Colors.grey);
    }
    // Sent only -> single check grey
    return const Icon(Icons.done, size: 16, color: Colors.grey);
  }

  void _dismissPopup() {
    Navigator.of(context).pop();
  }

  // Handle voice call button press
  void _onVoiceCallPressed() async {
    if (!mounted) return;

    // Get current user's display name
    final currentUserProfile = await _getUserProfile(widget.currentUser);
    final callerName = currentUserProfile?['name'] ?? widget.currentUser;

    globalCallManager.startCall(
      partnerId: widget.otherUser,
      partnerName: callerName,
      isVideo: false,
      currentUserId: widget.currentUser,
    );
  }

  // Handle video call button press
  void _onVideoCallPressed() async {
    if (!mounted) return;

    // Get current user's display name
    final currentUserProfile = await _getUserProfile(widget.currentUser);
    final callerName = currentUserProfile?['name'] ?? widget.currentUser;

    globalCallManager.startCall(
      partnerId: widget.otherUser,
      partnerName: callerName,
      isVideo: true,
      currentUserId: widget.currentUser,
    );
  }
}
