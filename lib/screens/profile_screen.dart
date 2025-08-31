import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Define custom colors if not available
const Color primaryColor = Colors.blue;
const Color secondaryColor = Colors.green;
const Color backgroundColor = Colors.white;
const Color textColor = Colors.black87;

// Define custom text styles
TextStyle get titleStyle => const TextStyle(
  fontSize: 24,
  fontWeight: FontWeight.bold,
  color: textColor,
);

TextStyle get subtitleStyle => TextStyle(
  fontSize: 16,
  color: Colors.grey[600],
);

// Custom widgets to replace missing ones
class CustomListTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const CustomListTile({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: primaryColor),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      onTap: onTap,
    );
  }
}

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int? maxLines;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
      validator: validator,
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool isCurrentUser;

  const ProfileScreen({
    super.key,
    required this.userId,
    this.isCurrentUser = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // State variables
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  UserProfile? _userProfile;
  
  // Controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _statusController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    print('_loadUserProfile: Starting to load profile...');
    if (!mounted) {
      print('_loadUserProfile: Not mounted, returning early');
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      print('_loadUserProfile: Getting SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();
      final userId = widget.userId.isNotEmpty ? widget.userId : (prefs.getString('userId') ?? '');
      print('_loadUserProfile: User ID = $userId');
      
      if (userId.isEmpty) {
        print('_loadUserProfile: User not logged in');
        throw Exception('User not logged in');
      }
      
      print('_loadUserProfile: Calling ProfileService.getUserProfile...');
      final userProfile = await ProfileService.getUserProfile(userId);
      print('_loadUserProfile: Received user profile: ${userProfile.username}');
      
      if (!mounted) {
        print('_loadUserProfile: Not mounted after API call, returning early');
        return;
      }
      
      setState(() {
        _userProfile = userProfile;
        _nameController.text = userProfile.username;
        _statusController.text = userProfile.status ?? 'Hey there! I am using Chat App';
        _isLoading = false;
        print('_loadUserProfile: State updated with user profile');
      });
    } catch (e) {
      if (!mounted) return;
      
      final errorMessage = e.toString();
      
      setState(() {
        _errorMessage = 'Failed to load profile: $e';
        _isLoading = false;
      });
      
      if (mounted) {
        if (errorMessage.contains('Authentication expired') || errorMessage.contains('Please log in again')) {
          // Token expired, redirect to login
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expired. Please log in again.')),
          );
          
          // Navigate back to login screen
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      }
    }
  }
  
  Future<void> _updateProfile(Map<String, dynamic> updates) async {
    if (_userProfile == null) return;
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      final updatedProfile = await ProfileService.updateProfile(
        _userProfile!.id,
        updates,
      );
      
      if (mounted) {
        setState(() {
          _userProfile = updatedProfile;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
  
 Future<void> _pickImage(ImageSource source) async {
  try {
    print('📸 Picking image from ${source.toString()}');
    final pickedFile = await _picker.pickImage(source: source);
    
    if (pickedFile != null) {
      print('🖼️ Image selected, reading bytes...');
      final imageBytes = await pickedFile.readAsBytes();
      final fileName = pickedFile.name;
      print('📤 Uploading image: $fileName (${imageBytes.length} bytes)');
      
      setState(() {
        _isSaving = true;
      });
      
      try {
        print('🔄 Uploading to server...');
        final imageUrl = await ProfileService.uploadProfilePicture(imageBytes, fileName);
        
        if (mounted) {
          if (imageUrl != null) {
            print('✅ Image uploaded successfully! URL: $imageUrl');
            await _updateProfile({'profilePicture': imageUrl});
            await _loadUserProfile();
            setState(() {
              _isSaving = false;
            });
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile picture updated successfully!')),
              );
            }
          } else {
            print('❌ Failed to upload image: Server returned null URL');
            if (mounted) {
              setState(() {
                _isSaving = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to upload profile picture. Please try again.')),
              );
            }
          }
        }
      } catch (e) {
        print('❌ Error during upload: $e');
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: ${e.toString()}')),
          );
        }
      }
    }
  } catch (e) {
    print('❌ Error picking image: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: ${e.toString()}')),
      );
    }
  }
}
  Future<void> _removeProfilePicture() async {
    if (_userProfile == null) return;
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      await ProfileService.deleteProfilePicture();
      
      await _updateProfile({'profilePicture': null});
      
      if (mounted) {
        setState(() {
          _userProfile = _userProfile?.copyWith(profilePicture: null);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove profile picture: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
  
  void _showProfilePictureOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Take Photo'),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from Gallery'),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
          ),
          if (_userProfile?.profilePicture != null && _userProfile!.profilePicture!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _removeProfilePicture();
              },
            ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Cancel'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
  
  void _editProfile() {
    if (_userProfile == null) return;
    
    _nameController.text = _userProfile?.username ?? '';
    _statusController.text = _userProfile?.status ?? '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _statusController,
                  decoration: const InputDecoration(labelText: 'Status'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _isSaving ? null : () async {
              if (_formKey.currentState?.validate() ?? false) {
                try {
                  setState(() {
                    _isSaving = true;
                  });
                  
                  await _updateProfile({
                    'username': _nameController.text.trim(),
                    'status': _statusController.text.trim(),
                  });
                  
                  if (mounted) {
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update profile: $e')),
                    );
                  }
                } finally {
                  if (mounted) {
                    setState(() {
                      _isSaving = false;
                    });
                  }
                }
              }
            },
            child: _isSaving 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
  
  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inDays > 7) {
      return '${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadUserProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (widget.isCurrentUser)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editProfile,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24.0),
            // Profile Picture
            Hero(
              tag: 'profile-picture-${widget.userId}',
              child: InkWell(
                onTap: widget.isCurrentUser ? _showProfilePictureOptions : null,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    Container(
                      width: 120.0,
                      height: 120.0,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[200],
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2.0,
                        ),
                      ),
                    ),
                    // Profile image or placeholder
                    if (_userProfile?.profilePicture != null && 
                        _userProfile!.profilePicture!.isNotEmpty)
                      ClipOval(
                        child: Image.network(
                          ProfileService.getProfilePictureUrl(_userProfile!.profilePicture!),
                          width: 116.0,
                          height: 116.0,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => 
                            const Icon(Icons.person, size: 60, color: Colors.grey),
                        ),
                      )
                    else
                      const Icon(Icons.person, size: 60, color: Colors.grey),
                    // Camera icon for current user
                    if (widget.isCurrentUser)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4.0),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20.0,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            // Username
            Text(
              _userProfile?.username ?? 'Unknown User',
              style: const TextStyle(
                fontSize: 24.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8.0),
            // Status
            if (_userProfile?.status != null && _userProfile!.status!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  _userProfile!.status!,
                  style: TextStyle(
                    fontSize: 16.0,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 24.0),
            // User Info Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20.0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Email
                  if (_userProfile?.email != null && _userProfile!.email!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Icon(Icons.email, color: Colors.grey[600]),
                          const SizedBox(width: 16.0),
                          Text(
                            _userProfile!.email!,
                            style: const TextStyle(fontSize: 16.0),
                          ),
                        ],
                      ),
                    ),
                  
                  // Phone Number
                  if (_userProfile?.phoneNumber != null && _userProfile!.phoneNumber!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Icon(Icons.phone, color: Colors.grey[600]),
                          const SizedBox(width: 16.0),
                          Text(
                            _userProfile!.phoneNumber!,
                            style: const TextStyle(fontSize: 16.0),
                          ),
                        ],
                      ),
                    ),
                  
                  // Last Seen
                  if (_userProfile?.lastSeen != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                      child: Row(
                        children: [
                          Icon(Icons.access_time, color: Colors.grey[600]),
                          const SizedBox(width: 16.0),
                          Text(
                            'Last seen ${_formatLastSeen(_userProfile!.lastSeen!)}',
                            style: const TextStyle(fontSize: 14.0, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  
                  // Edit Profile Button
                  if (widget.isCurrentUser)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _editProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 12.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                          ),
                          child: const Text(
                            'Edit Profile',
                            style: TextStyle(fontSize: 16.0, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
