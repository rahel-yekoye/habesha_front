import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/socket_service.dart';

class ContactsScreen extends StatefulWidget {
  final String jwtToken;
  final String currentUser;

  const ContactsScreen({
    super.key,
    required this.jwtToken,
    required this.currentUser,
  });

  @override
  _ContactsScreenState createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> with SingleTickerProviderStateMixin {
  // Controllers
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _phoneSearchController = TextEditingController();
  
  // Contacts tab state
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _filteredContacts = [];
  List<Map<String, dynamic>> _phoneContacts = [];
  List<Map<String, dynamic>> _appUsers = [];
  bool _isLoading = true;
  bool _contactsPermissionGranted = false;
  
  // Search tab state
  Map<String, dynamic>? _searchResult;
  String? _errorMessage;
  bool _isSearching = false;
  
  // Socket service for chat
  final SocketService _socketService = SocketService();
  
  // Initialize socket connection
  bool _isSocketInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkContactsPermission();
    _searchController.addListener(_filterContacts);
    
    // Initialize socket connection if not already done
    if (!_isSocketInitialized && widget.jwtToken.isNotEmpty) {
      _socketService.connect(userId: widget.currentUser);
      _isSocketInitialized = true;
    }
  }

  Future<void> _checkContactsPermission() async {
    final status = await Permission.contacts.status;
    if (status.isGranted) {
      setState(() => _contactsPermissionGranted = true);
      await _loadPhoneContacts();
      await _loadAppUsers();
      _matchContactsWithAppUsers();
    } else if (status.isDenied) {
      final result = await Permission.contacts.request();
      if (result.isGranted) {
        setState(() => _contactsPermissionGranted = true);
        await _loadPhoneContacts();
        await _loadAppUsers();
        _matchContactsWithAppUsers();
      }
    }
  }

Future<void> _loadPhoneContacts() async {
  try {
    // Request permission first
    final PermissionStatus permissionStatus = await Permission.contacts.request();
    if (permissionStatus != PermissionStatus.granted) {
      setState(() => _contactsPermissionGranted = false);
      return;
    }

    // Get contacts
    final List<Contact> contacts = await ContactsService.getContacts(
      withThumbnails: false,
    );

    setState(() {
      _phoneContacts = contacts.map((contact) {
        final phone = contact.phones?.isNotEmpty == true 
            ? contact.phones!.first.value ?? '' 
            : '';
        return {
          'name': contact.displayName ?? 'Unknown',
          'phone': _cleanPhoneNumber(phone),
          'isAppUser': false, // Will be updated when matching with app users
        };
      }).toList();
    });
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading contacts: $e')),
      );
    }
  }
}
  String _cleanPhoneNumber(String phone) {
    // Remove all non-digit characters
    return phone.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _loadAppUsers() async {
    try {
      final response = await http.get(
        Uri.parse('http://localhost:4000/api/users'),
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _appUsers = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading app users: $e')),
        );
      }
    }
  }

  void _matchContactsWithAppUsers() {
    final matchedContacts = <Map<String, dynamic>>[];
    
    for (final contact in _phoneContacts) {
      final phone = contact['phone'];
      
      // Find matching app user by phone number
      final matchedUser = _appUsers.firstWhere(
        (user) => user['phone'] == phone,
        orElse: () => {},
      );
      
      if (matchedUser.isNotEmpty) {
        matchedContacts.add({
          'id': matchedUser['_id'],
          'name': contact['name'],
          'username': matchedUser['username'],
          'phone': phone,
          'avatar': matchedUser['avatar'],
          'isAppUser': true,
        });
      } else {
        matchedContacts.add({
          'name': contact['name'],
          'phone': phone,
          'isAppUser': false,
        });
      }
    }
    
    setState(() {
      _contacts = matchedContacts;
      _filteredContacts = List.from(matchedContacts);
      _isLoading = false;
    });
  }

  Future<void> _loadContacts() async {
    // TODO: Replace with actual API call to fetch contacts
    await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
    
    // Mock data - replace with actual API call
    setState(() {
      _contacts = [
        {
          'id': '1',
          'name': 'John Doe',
          'username': 'johndoe',
          'avatar': 'https://i.pravatar.cc/150?img=1',
          'status': 'online',
        },
        // Add more mock contacts as needed
      ];
      _filteredContacts = List.from(_contacts);
      _isLoading = false;
    });
  }

  void _filterContacts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredContacts = _contacts.where((contact) {
        return contact['name'].toLowerCase().contains(query) ||
            contact['username'].toLowerCase().contains(query);
      }).toList();
    });
  }

  void _showAddContactDialog() {
    final TextEditingController usernameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Contact'),
        content: TextField(
          controller: usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'Enter username to add',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Implement add contact logic
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.contacts), text: 'Contacts'),
            Tab(icon: Icon(Icons.search), text: 'Find People'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Contacts Tab
          _buildContactsTab(),
          // Find People Tab
          _buildFindPeopleTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildContactsTab() {
    if (!_contactsPermissionGranted) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.contacts, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Contacts Access Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Please grant contacts permission to see your contacts',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkContactsPermission,
              child: const Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search contacts...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        Expanded(
          child: _filteredContacts.isEmpty
              ? const Center(
                  child: Text('No contacts found'),
                )
              : ListView.builder(
                  itemCount: _filteredContacts.length,
                  itemBuilder: (context, index) {
                    final contact = _filteredContacts[index];
                    return _buildContactItem(contact);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFindPeopleTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _phoneSearchController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Search by phone number',
              hintText: 'Enter phone number',
              prefixIcon: const Icon(Icons.phone),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _searchUser,
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _searchUser(),
          ),
          const SizedBox(height: 20),
          
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            )
          else if (_searchResult != null)
            _buildSearchResult(),
        ],
      ),
    );
  }

  Future<void> _searchUser() async {
    final phone = _phoneSearchController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Please enter a phone number.');
      return;
    }
    
    setState(() {
      _isSearching = true;
      _searchResult = null;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse('http://localhost:4000/search?phoneNumber=$phone'),
        headers: {'Authorization': 'Bearer ${widget.jwtToken}'},
      );

      if (response.statusCode == 200) {
        setState(() {
          _searchResult = jsonDecode(response.body)['user'];
        });
      } else {
        setState(() {
          _errorMessage = jsonDecode(response.body)['error'] ?? 'User not found';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred. Please try again.';
      });
    } finally {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _inviteContact(String? phone) async {
    if (phone == null || phone.isEmpty) {
      return;
    }
    
    final message = 'Join me on Habesha Chat! Download the app at: https://habesha.chat/download';
    final smsUri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );
    
    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invitation sent!')),
          );
        }
      } else {
        throw Exception('Could not launch SMS');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send invitation')),
        );
      }
    }
  }

  Widget _buildContactItem(Map<String, dynamic> contact) {
    final isAppUser = contact['isAppUser'] == true;
    final name = contact['name']?.toString() ?? 'Unknown';
    final username = contact['username']?.toString();
    final phone = contact['phone']?.toString();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey[300],
        child: contact['avatar'] != null
            ? CachedNetworkImage(
                imageUrl: contact['avatar'],
                placeholder: (context, url) => const Icon(Icons.person, color: Colors.grey),
                errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.grey),
                imageBuilder: (context, imageProvider) => Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              )
            : Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
      ),
      title: Text(name),
      subtitle: Text(username ?? phone ?? ''),
      trailing: isAppUser
          ? IconButton(
              icon: const Icon(Icons.chat),
              onPressed: () => _startChatWithUser(contact),
              tooltip: 'Start Chat',
            )
          : TextButton(
              onPressed: () => _inviteContact(phone),
              child: const Text('INVITE'),
            ),
    );
  }

  Widget _buildSearchResult() {
    if (_searchResult == null) return const SizedBox.shrink();

    final user = _searchResult!;
    final profilePic = user['profilePic']?.toString();
    final username = user['username']?.toString() ?? 'Unknown User';
    final phone = user['phone']?.toString() ?? '';
    final name = user['name']?.toString() ?? username;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey[300],
          child: profilePic != null && profilePic.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: profilePic,
                  placeholder: (context, url) => const Icon(Icons.person, color: Colors.grey),
                  errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.grey),
                  imageBuilder: (context, imageProvider) => Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(
                        image: imageProvider,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                )
              : Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
        ),
        title: Text(name),
        subtitle: Text(phone),
        trailing: IconButton(
          icon: const Icon(Icons.chat),
          onPressed: () => _startChatWithUser(user),
          tooltip: 'Start Chat',
        ),
      ),
    );
  }

  Future<void> _startChatWithUser(Map<String, dynamic> user) async {
    final username = user['username']?.toString();
    if (username == null || username.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid user')),
        );
      }
      return;
    }

    // Navigate to chat screen
    if (mounted) {
      Navigator.pushReplacementNamed(
        context,
        '/chat',
        arguments: {
          'username': username,
          'jwtToken': widget.jwtToken,
          'currentUser': widget.currentUser,
        },
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _phoneSearchController.dispose();
    _tabController.dispose();
    // Don't dispose the socket service as it's a singleton
    super.dispose();
  }
}
