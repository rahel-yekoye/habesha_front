import 'dart:convert';
import 'package:chat_app_flutter/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import '../services/socket_service.dart';
import '../services/auth_service.dart';
import 'chat/chat_screen.dart';
import 'create_group_screen.dart';
import 'search_user_screen.dart';
import 'profile_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';
import 'group_chat/group_chat_screen.dart';

class InboxScreen extends StatefulWidget {
  final String currentUser;
  final String jwtToken;

  const InboxScreen({
    super.key,
    required this.currentUser,
    required this.jwtToken,
  });

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> groups = [];
  bool isLoading = true;
  late SocketService socketService;

  late IO.Socket socket; // This socket instance is local to InboxScreen.
  Future<void> _markConversationAsRead(String otherUser) async {
    if (!mounted) return;
    
    try {
      // First update the local state immediately for better UX
      final index = conversations.indexWhere((c) => c['otherUser'] == otherUser);
      if (index == -1) return;
      
      // Create a completely new list to ensure state updates
      final updatedConversations = List<Map<String, dynamic>>.from(conversations);
      updatedConversations[index] = Map<String, dynamic>.from(conversations[index]);
      updatedConversations[index]['unreadCount'] = 0;
      
      // Update the state
      setState(() {
        conversations = updatedConversations;
      });

      // Then make the API call to update the server
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? widget.jwtToken;
      
      try {
        final response = await http.post(
          Uri.parse('http://localhost:4000/messages/mark-read'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'user1': widget.currentUser,
            'user2': otherUser,
          }),
        );

        // Always refresh from server to ensure consistency
        if (mounted) {
          _fetchConversations();
        }
      } catch (e) {
        print('Error marking messages as read: $e');
        // If API call fails, still keep the local state updated
      }
        } catch (e) {
      print('❌ Error in _markConversationAsRead: $e');
      // If anything fails, force a refresh
      if (mounted) {
        _fetchConversations();
      }
    }
}

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchConversations();
    _fetchGroups();
    socketService = SocketService();
    socketService.connect(userId: widget.currentUser);
    _connectToSocket();
    
    // Listen for read receipts
    socketService.socket.on('messages_read', (data) {
      if (mounted) {
        _fetchConversations();
      }
    });
  }

  Future<void> _fetchConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? '';
    final username = prefs.getString('username') ?? widget.currentUser;
    
    print('📱 Fetching conversations for userId: $userId, username: $username');
    
    final url = Uri.parse('http://localhost:4000/conversations?user=$username');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      
      print('📱 Conversations response: ${response.statusCode}');
      print('📱 Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          conversations =
              data.map((json) => Map<String, dynamic>.from(json)).toList();
          // Sort conversations by timestamp to show latest first
          conversations.sort((a, b) {
            final DateTime timeA =
                DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(0);
            final DateTime timeB =
                DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(0);
            return timeB.compareTo(timeA); // Descending order (latest first)
          });
          isLoading = false;
        });
        print('📱 Loaded ${conversations.length} conversations');
      } else {
        print('❌ Failed to fetch conversations: ${response.statusCode}');
        setState(() => isLoading = false);
      }
    } catch (e) {
      print('❌ Error fetching conversations: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchGroups() async {
    final url = Uri.parse('http://localhost:4000/groups');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          groups = data.map((json) => Map<String, dynamic>.from(json)).toList();
        });
      }
    } catch (_) {}
  }

  Future<String> _fetchLastGroupMessage(String groupId) async {
    final url = Uri.parse('http://localhost:4000/groups/$groupId/last-message');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && data is Map) {
          final sender = data['sender']?.toString() ?? 'Unknown';
          final content = data['content']?.toString() ?? '';
          if (content.isEmpty) return 'No messages yet.';
          return '$sender: $content';
        }
      }
    } catch (e) {
      print('Error fetching last group message: $e');
    }
    return 'No messages yet.';
  }

  void _connectToSocket() {
    socket = IO.io('http://localhost:4000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket.onConnect((_) {
      print('✅ Connected to Socket.IO server from InboxScreen');
      // Register the current user with the socket server
      socket.emit('register_user', widget.currentUser);
    });

    socket.onDisconnect((_) {
      print('❌ Disconnected from Socket.IO server from InboxScreen');
    });

    // Listen for profile updates to refresh inbox display
    socket.on('user_profile_updated', (data) {
      if (!mounted) return;
      try {
        final userId = data['userId']?.toString() ?? '';
        final newUsername = data['username']?.toString() ?? '';
        
        setState(() {
          // Update conversations list with new username/profile picture
          for (int i = 0; i < conversations.length; i++) {
            if (conversations[i]['otherUser'] == userId || conversations[i]['otherUser'] == newUsername) {
              conversations[i]['otherUser'] = newUsername;
              print('📱 Updated conversation for user: $newUsername');
            }
          }
          
          // Update groups list if needed
          for (int i = 0; i < groups.length; i++) {
            final members = groups[i]['members'] as List<dynamic>? ?? [];
            bool updated = false;
            for (int j = 0; j < members.length; j++) {
              if (members[j] == userId) {
                members[j] = newUsername;
                updated = true;
              }
            }
            if (updated) {
              groups[i]['members'] = members;
              print('📱 Updated group members for: ${groups[i]['name']}');
            }
          }
        });
      } catch (e) {
        debugPrint('Error handling profile update in inbox: $e');
      }
    });

    // This listener is key for real-time updates in the inbox.
    socket.on('conversation_update', (data) {
      final updated = Map<String, dynamic>.from(data);
      print('[SOCKET] Inbox conversation_update event received: $updated');

      if (updated['isGroup'] == true) return;

      setState(() {
        final index = conversations
            .indexWhere((c) => c['otherUser'] == updated['otherUser']);
        if (index != -1) {
          conversations[index] = updated; // Update existing conversation
        } else {
          conversations.add(updated); // Add new conversation
        }
        // Re-sort conversations after update/add
        conversations.sort((a, b) {
          final DateTime timeA =
              DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(0);
          final DateTime timeB =
              DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(0);
          return timeB.compareTo(timeA); // Descending order (latest first)
        });
      });
    });

    // Add a listener for group message updates if needed for the inbox view
    socket.on('group_message', (data) {
      // This would update the last message preview for groups in the inbox
      // You'd need to find the group by ID and update its last message/timestamp
      print('[SOCKET] Inbox group_message event received: $data');
      _fetchGroups(); // Re-fetch groups to update last message preview
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    socket.disconnect();
    socket.close();
    super.dispose();
  }

  String _formatTimestamp(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Widget _buildChatsTab() {
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : conversations.isEmpty
            ? const Center(child: Text('No conversations yet'))
            : ListView.separated(
                itemCount: conversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final c = conversations[index];

                  if (c['isGroup'] == true) {
                    return const SizedBox
                        .shrink(); // Should not happen if conversations are filtered correctly
                  }

                  final unreadCount = c['unreadCount'] ?? 0;
                  
                  return Container(
                    key: ValueKey('conversation_${c['otherUser']}_$unreadCount'),
                    child: ListTile(
                      onTap: () {
                        // Mark messages as read when tapped
                        if (unreadCount > 0) {
                          _markConversationAsRead(c['otherUser']);
                        }
                        
                        // Navigate to chat screen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              currentUser: widget.currentUser,
                              otherUser: c['otherUser'],
                              jwtToken: widget.jwtToken,
                              socketService: socketService,
                            ),
                          ),
                        ).then((_) {
                          // Refresh conversations when returning to inbox
                          _fetchConversations();
                        });
                      },
                      title: Text(
                        c['otherUser'],
                        style: TextStyle(
                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        c['lastMessage'] ?? 'No messages yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unreadCount > 0 ? Colors.black87 : Colors.grey[600],
                          fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      leading: GestureDetector(
                        onTap: () {
                          _showProfilePictureGallery(c['otherUser']);
                        },
                        child: CircleAvatar(
                          radius: 25,
                          child: Stack(
                            children: [
                              FutureBuilder<Map<String, dynamic>?>(
                                future: _getUserProfile(c['otherUser']),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData && snapshot.data?['profilePicture'] != null) {
                                    return CachedNetworkImage(
                                      imageUrl: snapshot.data!['profilePicture'],
                                      imageBuilder: (context, imageProvider) => Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          image: DecorationImage(
                                            image: imageProvider,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 2),
                                      errorWidget: (context, url, error) => Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.grey[300],
                                        ),
                                        child: Icon(
                                          Icons.person,
                                          color: Colors.grey[600],
                                          size: 28,
                                        ),
                                      ),
                                    );
                                  }
                                  return Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.grey[300],
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.grey[600],
                                      size: 28,
                                    ),
                                  );
                                },
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      unreadCount > 9 ? '9+' : '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      trailing: unreadCount > 0
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatTimestamp(c['timestamp'] ?? ''),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      unreadCount > 9 ? '9+' : unreadCount.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _formatTimestamp(c['timestamp'] ?? ''),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                    ),
                  );
                },
              );
  }

  Widget _buildGroupsTab() {
    return groups.isEmpty
        ? const Center(child: Text('No groups yet'))
        : ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final group = groups[index];
              return FutureBuilder<String>(
                future: _fetchLastGroupMessage(group['_id']),
                builder: (context, snapshot) {
                  final lastMessage =
                      snapshot.connectionState == ConnectionState.done
                          ? (snapshot.data ?? 'No messages yet.')
                          : 'Loading...';
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.group)),
                    title: Text(group['name'],
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupChatScreen(
                            groupId: group['_id'],
                            groupName: group['name'],
                            groupDescription: group['description'] ?? '',
                            currentUser: widget.currentUser,
                            jwtToken: widget.jwtToken,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
  }

  void _navigateToProfile() async {
    print('🔍 Navigating to profile...');
    
    try {
      // Get current user ID and token using AuthService
      print('🔑 Getting current user ID and token...');
      final currentUserId = await AuthService.getUserId() ?? '';
      final token = await AuthService.getToken();
      
      print('👤 Current User ID: $currentUserId');
      print('🔑 Token exists: ${token != null && token.isNotEmpty}');
      
      if (!mounted) {
        print('🚫 Widget not mounted, returning early');
        return;
      }
      
      if (token == null || token.isEmpty) {
        print('❌ No token found, redirecting to login');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please log in to view profile')),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }
      
      if (!mounted) {
        print('🚫 Widget not mounted after token check');
        return;
      }
      
      print('🚀 Navigating to ProfileScreen...');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfileScreen(
            userId: currentUserId,
            isCurrentUser: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    // Clear the user session
    await AuthService.clearSession();
    
    // Disconnect from socket
    socketService.disconnect();
    
    // Navigate to login screen and remove all previous routes
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _showProfilePictureGallery(String username) async {
    final userProfile = await _getUserProfile(username);
    final currentPicture = userProfile?['profilePicture'];
    final pictureHistory = userProfile?['profilePictureHistory'] as List<dynamic>? ?? [];
    
    // Combine current picture with history
    final allPictures = <String>[];
    if (currentPicture != null) allPictures.add(currentPicture);
    allPictures.addAll(pictureHistory.cast<String>());
    
    if (allPictures.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: PageView.builder(
                itemCount: allPictures.length,
                itemBuilder: (context, index) {
                  return PhotoView(
                    imageProvider: CachedNetworkImageProvider(allPictures[index]),
                    backgroundDecoration: const BoxDecoration(color: Colors.black),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2,
                  );
                },
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              child: Text(
                username,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (allPictures.length > 1)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${allPictures.length} photos • Swipe to see more',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  
  Future<Map<String, dynamic>?> _getUserProfile(String username) async {
    try {
      final response = await http.get(
        Uri.parse('http://localhost:4000/profile/$username'),
        headers: {
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }

  Future<void> _showMenu() async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        16,
        kToolbarHeight + 16,
        0,
        0,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'profile',
          child: const Row(
            children: [
              Icon(Icons.person_outline, size: 20),
              SizedBox(width: 8),
              Text('My Profile'),
            ],
          ),
          onTap: () => _navigateToProfile(),
        ),
        const PopupMenuItem<String>(
          value: 'contacts',
          child: Row(
            children: [
              Icon(Icons.contacts_outlined, size: 20),
              SizedBox(width: 8),
              Text('Contacts'),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 20),
              SizedBox(width: 8),
              Text('Settings'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          onTap: _handleLogout,
          child: const Row(
            children: [
              Icon(Icons.logout, size: 20, color: Colors.red),
              SizedBox(width: 8),
              Text('Logout', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );

    if (result == 'profile') {
      _navigateToProfile();
    } else if (result == 'contacts') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ContactsScreen(
            currentUser: widget.currentUser,
            jwtToken: widget.jwtToken,
          ),
        ),
      );
    } else if (result == 'settings') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SettingsScreen(
            currentUser: widget.currentUser,
            jwtToken: widget.jwtToken,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showMenu,
          child: Row(
            children: [
              Text('Messages'),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMenu,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Chats'),
            Tab(text: 'Groups'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatsTab(),
          _buildGroupsTab(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'searchUser',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SearchScreen(
                    loggedInUser: widget.currentUser,
                    jwtToken: widget.jwtToken,
                  ),
                ),
              );
            },
            tooltip: 'Search User',
            child: const Icon(Icons.search),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'createGroup',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateGroupScreen(
                    currentUser: widget.currentUser,
                    jwtToken: widget.jwtToken,
                  ),
                ),
              );
            },
            tooltip: 'Create Group',
            child: const Icon(Icons.group_add),
          ),
        ],
      ),
    );
  }
}
