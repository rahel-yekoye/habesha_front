import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import '../models/message.dart' as models;
import '../main.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'call_manager.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  String? _jwtToken;
  String? _selfId;
  Timer? _heartbeatTimer;
  final int _reconnectAttempts = 0;
  final String _baseUrl = 'http://localhost:4000';
  
  // Store CallManager instances per user ID
  final Map<String, CallManager> _callManagers = {};

  IO.Socket get socket {
    if (_socket == null) {
      throw Exception('Socket not initialized. Call connect() first.');
    }
    return _socket!;
  }

  bool _isPrivateListenerSet = false;
  bool _isGroupListenerSet = false;
  bool _isDeletedForMeListenerSet = false;
  bool _isDeletedForEveryoneListenerSet = false;
  bool _isReactionsListenerSet = false;

  void setAuthToken(String token) {
    _jwtToken = token;
    if (_socket?.io.options != null) {
      _socket!.io.options!['extraHeaders'] = {
        'Authorization': 'Bearer $token',
      };
    }
  }

  void onMessagesDeletedForMe(Function(List<String>) callback) {
    if (!_isDeletedForMeListenerSet && _socket != null) {
      _socket!.on('messages_deleted_for_me', (data) {
        try {
          if (data is Map && data['messageIds'] is List) {
            final ids = List<String>.from(data['messageIds'].map((e) => e.toString()));
            print('🗑️ messages_deleted_for_me received: $ids');
            callback(ids);
          }
        } catch (e) {
          print('Error handling messages_deleted_for_me: $e');
        }
      });
      _isDeletedForMeListenerSet = true;
    }
  }

  // -------------------
  // Message Interactions
  // -------------------
  
  /// Delete messages for the current user only
  Future<void> deleteMessageForMe(List<String> messageIds) async {
    try {
      if (_jwtToken == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.delete(
        Uri.parse('$_baseUrl/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({
          'ids': messageIds,
          'mode': 'for_me',
        }),
      );

      if (response.statusCode == 401) {
        _jwtToken = null;
        throw Exception('Session expired. Please log in again.');
      } else if (response.statusCode != 200) {
        throw Exception('Failed to delete messages: ${response.body}');
      }
    } catch (e) {
      print('Error deleting messages for me: $e');
      rethrow;
    }
  }

  /// Delete messages for everyone in the chat
  Future<void> deleteMessageForEveryone(List<String> messageIds, {String? otherUserId}) async {
    try {
      if (_jwtToken == null) {
        throw Exception('Not authenticated');
      }
      if (otherUserId == null) {
        throw Exception('otherUserId is required for deleting messages for everyone');
      }
      if (_selfId == null) {
        throw Exception('User ID not available');
      }

      print('🔍 Deleting messages for everyone. Message IDs: $messageIds');
      print('🔍 Current user ID: $_selfId, Other user ID: $otherUserId');

      final response = await http.delete(
        Uri.parse('$_baseUrl/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({
          'ids': messageIds,
          'mode': 'for_everyone',
          'otherUser': otherUserId, // The other participant in the chat
          'currentUser': _selfId,   // Current user ID for server-side validation
        }),
      );

      print('🔍 Delete response status: ${response.statusCode}');
      print('🔍 Delete response body: ${response.body}');

      if (response.statusCode == 401) {
        _jwtToken = null;
        throw Exception('Session expired. Please log in again.');
      } else if (response.statusCode != 200) {
        throw Exception('Failed to delete messages: ${response.body}');
      }
    } catch (e) {
      print('Error deleting messages for everyone: $e');
      rethrow;
    }
  }

  /// Edit an existing message
  Future<void> editMessage(String messageId, String newContent) async {
    if (_socket == null || _selfId == null) {
      print('Socket not initialized or user not authenticated');
      return;
    }

    if (!_socket!.connected) {
      print('Socket not connected, skipping message edit');
      return;
    }

    print('Editing message: messageId=$messageId, newContent=$newContent');
    try {
      _socket!.emit('edit_message', {
        'messageId': messageId,
        'newContent': newContent,
        'userId': _selfId,
      });
    } catch (e) {
      print('Error editing message: $e');
      // Re-throw to handle in the UI
      rethrow;
    }
  }

  /// Add or update a reaction to a message
  Future<void> reactToMessage(String messageId, String emoji) async {
    // Ensure socket is connected and _selfId is set
    if (_socket == null || _selfId == null) {
      print('Socket not initialized or user not authenticated');
      return;
    }

    // If socket is not connected, skip sending
    if (!_socket!.connected) {
      print('Socket not connected, skipping reaction send');
      return;
    }

    print('Sending reaction: messageId=$messageId, userId=$_selfId, emoji=$emoji');
    try {
      _socket!.emit('add_reaction', {
        'messageId': messageId,
        'userId': _selfId,
        'emoji': emoji,
      });
    } catch (e) {
      print('Error sending reaction: $e');
      // If sending fails, try to reconnect and resend once
      try {
        await connect(userId: _selfId!);
        _socket!.emit('add_reaction', {
          'messageId': messageId,
          'userId': _selfId,
          'emoji': emoji,
        });
      } catch (retryError) {
        print('Failed to resend reaction after reconnect: $retryError');
      }
    }
  }

  /// Remove a reaction from a message
  Future<void> removeReactionFromMessage(String messageId) async {
    if (_socket != null && _socket!.connected && _selfId != null) {
      _socket!.emit('remove_reaction', {
        'messageId': messageId,
        'userId': _selfId,
      });
    }
  }

  void onReactionsUpdated(void Function(Map<String, dynamic>) callback) {
    if (!_isReactionsListenerSet && _socket != null) {
      _socket!.on('message_reactions_updated', (data) {
        try {
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            callback(map);
          }
        } catch (e) {
          print('Error handling message_reactions_updated: $e');
        }
      });
      _isReactionsListenerSet = true;
    }
  }

  void onMessagesDeletedForEveryone(Function(List<String>) callback) {
    if (!_isDeletedForEveryoneListenerSet && _socket != null) {
      _socket!.on('messages_deleted_for_everyone', (data) {
        try {
          if (data is Map && data['messageIds'] is List) {
            final ids = List<String>.from(data['messageIds'].map((e) => e.toString()));
            print('🗑️ messages_deleted_for_everyone received: $ids');
            callback(ids);
          }
        } catch (e) {
          print('Error handling messages_deleted_for_everyone: $e');
        }
      });
      _isDeletedForEveryoneListenerSet = true;
    }
  }
  Future<void> connect({required String userId, String? jwtToken}) async {
    print('SocketService instance hash (connect): ${identityHashCode(this)}');
    
    // Validate user ID
    if (userId.isEmpty) {
      print('❌ Error: Cannot connect with empty user ID');
      throw Exception('User ID cannot be empty');
    }

    // Store JWT token if provided
    if (jwtToken != null) {
      _jwtToken = jwtToken;
    } else if (_jwtToken == null) {
      print('⚠️ Warning: No JWT token provided for authentication');
    }

    // If we're already connected for this user, just return
    if (_socket != null && _socket!.connected && _selfId == userId) {
      print('🔁 Socket already connected for user: $userId');
      return;
    }

    print('[SOCKET] ===== CONNECTING TO SOCKET =====');
    print('[SOCKET] Attempting to connect for user: $userId');
    print('[SOCKET] Previous user ID: $_selfId');
    print('🔌 Establishing new socket connection for user: $userId');
    
    // Properly disconnect and dispose the old socket if it exists
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }
    
    // Set the user ID immediately
    _selfId = userId;
    print('[SOCKET] Set _selfId to: $_selfId');
    resetListeners();

    // Prepare connection options
    final options = <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 5,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'timeout': 20000,
    };

    // Add auth headers if token exists
    if (_jwtToken != null) {
      options['extraHeaders'] = {
        'Authorization': 'Bearer $_jwtToken',
      };
    }

    // Configure socket options for better reliability
    options['transports'] = ['websocket'];
    options['autoConnect'] = true;
    options['reconnection'] = true;
    options['reconnectionAttempts'] = 5;
    options['reconnectionDelay'] = 1000;
    options['reconnectionDelayMax'] = 5000;
    options['timeout'] = 10000;
    options['forceNew'] = false;

    // Create new socket instance with proper URL handling
    final serverUrl = _baseUrl.replaceAll(RegExp(r'^https?://'), '');
    final socketUrl = 'ws://$serverUrl';
    print('🔄 Connecting to socket at: $socketUrl');
    
    _socket = IO.io(socketUrl, options);
    
    final completer = Completer<void>();
    int connectionAttempts = 0;
    const maxAttempts = 3;
    final timeout = Duration(seconds: 10);
    
    print('⏳ Setting up socket connection with timeout: $timeout');
    
    // Function to handle connection timeout
    void handleConnectionTimeout() {
      if (completer.isCompleted) return;
      
      connectionAttempts++;
      if (connectionAttempts >= maxAttempts) {
        final error = '❌ Failed to connect after $maxAttempts attempts for user: $userId';
        print(error);
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
        return;
      }
      
      print('⚠️ Connection attempt $connectionAttempts of $maxAttempts...');
      // Don't manually disconnect/reconnect - let socket handle it automatically
    }
    
    // Set up connection timer
    Timer? connectionTimer;
    
    void startConnectionTimer() {
      connectionTimer?.cancel();
      connectionTimer = Timer.periodic(timeout, (_) {
        if (!completer.isCompleted) {
          handleConnectionTimeout();
        } else {
          connectionTimer?.cancel();
        }
      });
    }
    
    // Cleanup function
    void cleanup() {
      connectionTimer?.cancel();
    }
    
    // Handle successful connection - REMOVED DUPLICATE HANDLER
    
    // Handle connection errors
    _socket!.onConnectError((error) {
      print('❌ Socket connection error: $error');
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
      cleanup();
    });
    
    // Set up other socket event handlers
    _socket!.onDisconnect((reason) {
      print('ℹ️ Socket disconnected. Reason: $reason');
      _stopHeartbeat();
    });
    _socket!.onError((error) => print('❌ Socket error: $error'));
    _socket!.onReconnect((_) {
      print('🔄 Socket reconnected!');
      _startHeartbeat();
    });
    _socket!.onReconnectAttempt((attempt) => print('🔄 Reconnection attempt: $attempt'));
    _socket!.onReconnectError((error) => print('❌ Reconnection error: $error'));
    
    // Start the initial connection attempt and timer
    startConnectionTimer();
    _socket!.connect();

    _socket!.onConnect((_) {
      try {
        print('✅ Connected to the socket server for user: $_selfId');
        print('[SOCKET] Socket ID: ${_socket!.id}');
        
        if (_selfId == null) {
          throw Exception('_selfId is null during connection');
        }

        // Register user with the server
        print('[SOCKET] Registering user: $_selfId');
        _socket!.emit('register_user', {
          'userId': _selfId,
          'username': _selfId, // For now, use same value for both
        });
        
        // Join presence channel
        _socket!.emit('join', _selfId);
        print('[SOCKET] Joined presence channel for user: $_selfId');
        
        // Start presence heartbeat
        _startHeartbeat();
        print('[SOCKET] Started heartbeat for user: $_selfId');
        
        // Initialize CallManager if context is available
        if (navigatorKey.currentContext != null) {
          print('[SOCKET] Initializing CallManager for user: $_selfId');
          _getOrCreateCallManager(_selfId!).initialize(_socket!, navigatorKey.currentContext!, _selfId!);
        } else {
          print('⚠️ [SOCKET] Navigator context not available, will retry CallManager initialization');
          // Schedule a retry for CallManager initialization
          Future.delayed(Duration(seconds: 2), () {
            if (navigatorKey.currentContext != null) {
              print('[SOCKET] Retrying CallManager initialization');
              _getOrCreateCallManager(_selfId!).initialize(_socket!, navigatorKey.currentContext!, _selfId!);
            }
          });
        }
        
        if (!completer.isCompleted) {
          print('[SOCKET] Completing connection successfully');
          completer.complete();
        }
      } catch (e, stackTrace) {
        print('❌ Error during socket connection: $e');
        print('Stack trace: $stackTrace');
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    });

    _socket!.onDisconnect((reason) {
      print('🔌 Disconnected from socket server. Reason: $reason');
      _stopHeartbeat();
      
      // Let socket handle reconnection automatically
      print('🔄 Socket will attempt automatic reconnection...');
    });

    _socket!.onConnectError((error) {
      final errorMsg = '❌ Socket connection error: $error';
      print(errorMsg);
      if (!completer.isCompleted) {
        completer.completeError(errorMsg);
      }
      
      // Let socket handle reconnection automatically
      print('🔄 Socket will attempt automatic reconnection...');
    });
    
    // Handle reconnection events
    _socket!.onReconnect((data) => print('🔄 Reconnecting to socket... (attempt: ${data as int? ?? 1})'));
    _socket!.onReconnectAttempt((data) => print('🔄 Reconnection attempt: ${data as int? ?? 1}'));
    _socket!.onReconnectError((error) => print('❌ Reconnection error: $error'));
    _socket!.onReconnectFailed((_) => print('❌❌ All reconnection attempts failed'));
    
    _socket!.onError((data) {
      print('❌ General Error: $data');
    });

    _socket!.connect();

    return completer.future;
  }

  void disconnect() {
    if (_socket != null && _socket!.connected) {
      _socket!.disconnect();
    }
    _stopHeartbeat();
  }

  // -------------------
  // Private chat
  // -------------------

  void registerUser(String username) {
    print('🧑‍💻 Registering user: $username');
    _socket?.emit('join_room', username);
  }

  void joinRoom(String roomId) {
    if (_socket == null) {
      print('❌ Socket not initialized.');
      return;
    }

    _socket!.off('connect');

    if (_socket!.connected) {
      _socket!.emit('join_room', roomId);
      print('✅ Immediately joined room: $roomId');
    } else {
      _socket!.on('connect', (_) {
        print('🔁 Socket connected later. Now joining room: $roomId');
        _socket!.emit('join_room', roomId);
      });

      if (!_socket!.connected && !_socket!.active) {
        print('⚙️ Connecting socket...');
        _socket!.connect();
      }
    }
  }

  void onMessagesRead(Function(Map<String, dynamic>) callback) {
    _socket?.off('messages_read');
    _socket?.on('messages_read', (data) {
      print('📩 messages_read event received: $data');
      if (data is Map<String, dynamic>) {
        callback(data);
      } else if (data is Map) {
        // Some dart:io socket.io versions may not cast perfectly
        callback(Map<String, dynamic>.from(data));
      }
    });
  }

  void onMessageRead(Function(Map<String, dynamic>) callback) {
    _socket?.off('message_read');
    _socket?.on('message_read', (data) {
      print('📩 message_read event received: $data');
      if (data is Map<String, dynamic>) {
        callback(data);
      } else if (data is Map) {
        callback(Map<String, dynamic>.from(data));
      }
    });
  }

  void onMessageEdited(Function(Map<String, dynamic>) callback) {
    _socket?.off('message_edited');
    _socket?.on('message_edited', (data) {
      print('✍️ message_edited event received: $data');
      if (data is Map<String, dynamic>) {
        callback(data);
      } else if (data is Map) {
        callback(Map<String, dynamic>.from(data));
      }
    });
  }

  void onMessageDelivered(Function(Map<String, dynamic>) callback) {
    _socket?.off('message_delivered');
    _socket?.on('message_delivered', (data) {
      print('📫 message_delivered event received: $data');
      if (data is Map<String, dynamic>) {
        callback(data);
      } else if (data is Map) {
        callback(Map<String, dynamic>.from(data));
      }
    });
  }

  void sendMessage(Map<String, dynamic> messageData) {
    if (_socket != null && _socket!.connected) {
      print('📤 Sending private message: $messageData');
      _socket!.emit('send_message', messageData);
    } else {
      print('❌ Socket not connected');
    }
  }

  void onMessageReceived(Function(models.Message) callback) {
    if (_socket != null) {
      _socket!.off('receive_message');
      _socket!.on('receive_message', (data) {
        print('📨 Private message received: $data');
        final msg = _processRawMessage(data);
        callback(msg);
      });
    }
  }

  // -------------------
  // Group chat
  // -------------------

  void joinGroups(List<String> groupIds) {
    if (_socket != null) {
      print('👥 Joining groups: $groupIds');
      _socket!.emit('join_group', groupIds);
    }
  }

  void sendGroupMessage(Map<String, dynamic> messageData) {
    if (_socket != null && _socket!.connected) {
      print('📤 Sending group message: $messageData');
      _socket!.emit('send_group_message', messageData);
    } else {
      print('❌ Socket not connected');
    }
  }

  void onGroupMessageReceived(Function(models.Message) callback) {
    if (!_isGroupListenerSet && _socket != null) {
      _socket!.on('group_message', (data) {
        print('📨 Group message received: $data');
        final msg = _processRawMessage(data);
        callback(msg);
      });
      _isGroupListenerSet = true;
    }
  }

  // -------------------
  // Typing indicators & Presence
  // -------------------

  void startTyping({String? to, bool isGroup = false, String? roomId}) {
    final payload = {
      'from': _selfId,
      'to': to,
      'isGroup': isGroup,
      'roomId': roomId,
    }..removeWhere((k, v) => v == null);
    _socket?.emit('typing', payload);
  }

  void stopTyping({String? to, bool isGroup = false, String? roomId}) {
    final payload = {
      'from': _selfId,
      'to': to,
      'isGroup': isGroup,
      'roomId': roomId,
    }..removeWhere((k, v) => v == null);
    _socket?.emit('stop_typing', payload);
  }

  void onTyping(void Function(Map<String, dynamic>) handler) {
    _socket?.off('typing');
    _socket?.on('typing', (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }

  void onStopTyping(void Function(Map<String, dynamic>) handler) {
    _socket?.off('stop_typing');
    _socket?.on('stop_typing', (data) {
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }

  void onPresenceUpdate(void Function(Map<String, dynamic>) handler) {
    _socket?.off('presence_update');
    _socket?.on('presence_update', (data) {
      print('[SOCKET] Received presence_update: $data');
      if (data is Map) handler(Map<String, dynamic>.from(data));
    });
  }


  // -------------------
  // Helpers
  // -------------------

  models.Message _processRawMessage(dynamic data) {
    return models.Message.fromJson(Map<String, dynamic>.from(data));
  }

  void resetListeners() {
    _isPrivateListenerSet = false;
    _isGroupListenerSet = false;
    _isDeletedForMeListenerSet = false;
    _isDeletedForEveryoneListenerSet = false;

    _socket?.off('receive_message');
    _socket?.off('group_message');
    _socket?.off('typing');
    _socket?.off('stop_typing');
    _socket?.off('presence_update');
    _socket?.off('messages_read');
    _socket?.off('message_read');
    _socket?.off('message_edited');
    _socket?.off('message_delivered');
    _socket?.off('messages_deleted_for_me');
    _socket?.off('messages_deleted_for_everyone');
  }

  void dispose() {
    resetListeners();
    _socket?.dispose();
    _stopHeartbeat();
  }

  void offMessageReceived() {
    _socket?.off('receive_message');
  }


  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (_selfId == null) return;
    print('[SOCKET] Starting heartbeat timer for user: $_selfId');
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      try {
        if (_socket?.connected == true) {
          print('[SOCKET] Sending heartbeat for user: $_selfId');
          _socket?.emit('heartbeat', _selfId);
        } else {
          print('[SOCKET] Skipping heartbeat - socket not connected');
        }
      } catch (e) {
        print('[SOCKET] Heartbeat error: $e');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  // -------------------
  // CallManager Management
  // -------------------
  
  /// Get or create a CallManager instance for a specific user
  CallManager _getOrCreateCallManager(String userId) {
    if (!_callManagers.containsKey(userId)) {
      print('[SOCKET] Creating new CallManager instance for user: $userId');
      _callManagers[userId] = CallManager();
    } else {
      print('[SOCKET] Using existing CallManager instance for user: $userId');
    }
    return _callManagers[userId]!;
  }
  
  /// Get the CallManager for the current user
  CallManager? getCurrentCallManager() {
    if (_selfId == null) return null;
    return _callManagers[_selfId!];
  }
  
  /// Clean up CallManager instances for users who have disconnected
  void _cleanupCallManagers() {
    // In a real implementation, you might want to track active sessions
    // and remove CallManager instances for users who have logged out
    // For now, we'll keep all instances to avoid unexpected behavior
  }
}
