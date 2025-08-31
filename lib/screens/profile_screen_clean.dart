import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../services/profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_picture_gallery.dart';

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
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = widget.userId.isNotEmpty ? widget.userId : (prefs.getString('userId') ?? '');
      
      if (userId.isEmpty) {
        throw Exception('User not logged in');
      }
      
      final userProfile = await ProfileService.getUserProfile(userId);
      
      if (!mounted) return;
      
      setState(() {
        _userProfile = userProfile;
        _nameController.text = userProfile.username;
        _statusController.text = userProfile.status ?? 'Hey there! I am using Chat App';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _errorMessage = 'Failed to load profile: $e';
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
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
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        final imageBytes = await pickedFile.readAsBytes();
        final fileName = pickedFile.name;
        
        setState(() {
          _isSaving = true;
        });
        
        try {
          final imageUrl = await ProfileService.uploadProfilePicture(imageBytes, fileName);
          
          if (mounted) {
            if (imageUrl != null) {
              await _updateProfile({'profilePicture': imageUrl});
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Profile picture updated successfully!'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.error, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Failed to upload profile picture'),
                    ],
                  ),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Failed to upload image: $e')),
                  ],
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Failed to pick image: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Profile Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.camera_alt, color: Colors.blue),
              ),
              title: const Text('Camera'),
              subtitle: const Text('Take a new photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.photo_library, color: Colors.green),
              ),
              title: const Text('Gallery'),
              subtitle: const Text('Choose from your photos'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_userProfile?.profilePictureHistory != null && _userProfile!.profilePictureHistory!.isNotEmpty)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.history, color: Colors.purple),
                ),
                title: const Text('View History'),
                subtitle: Text('${_userProfile!.profilePictureHistory!.length} photos'),
                onTap: () {
                  Navigator.pop(context);
                  _showProfilePictureGallery();
                },
              ),
            if (_userProfile?.profilePicture != null && _userProfile!.profilePicture!.isNotEmpty)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete, color: Colors.red),
                ),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Delete current photo'),
                onTap: () {
                  Navigator.pop(context);
                  _removeProfilePicture();
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showProfilePictureGallery() {
    if (_userProfile?.profilePictureHistory == null || _userProfile!.profilePictureHistory!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No profile picture history available')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePictureGallery(
          userId: _userProfile!.id,
          profilePictureHistory: _userProfile!.profilePictureHistory!,
          initialIndex: 0,
        ),
      ),
    ).then((updated) {
      if (updated == true) {
        // Reload profile to show updated picture
        _loadUserProfile();
      }
    });
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
  
  Widget _buildModernInfoItem(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.blue, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
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
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red[600], fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadUserProfile,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            floating: false,
            pinned: true,
            backgroundColor: Colors.blue,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.blue, Colors.lightBlue],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 60),
                    // Profile Picture with loading overlay
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        InkWell(
                          onTap: widget.isCurrentUser 
                              ? _showProfilePictureOptions 
                              : (_userProfile?.profilePictureHistory != null && 
                                 _userProfile!.profilePictureHistory!.isNotEmpty)
                                  ? () => _showProfilePictureGallery()
                                  : null,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Hero(
                                tag: 'profile-picture-${widget.userId}',
                                child: Container(
                                  width: 140.0,
                                  height: 140.0,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 4.0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 10,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                    image: (_userProfile?.profilePicture != null &&
                                              _userProfile!.profilePicture!.isNotEmpty)
                                        ? DecorationImage(
                                            image: CachedNetworkImageProvider(
                                              _userProfile!.profilePicture!,
                                            ),
                                            fit: BoxFit.cover,
                                            onError: (_, __) {
                                              // Handle image loading error
                                            },
                                          )
                                        : null,
                                  ),
                                  child: (_userProfile?.profilePicture == null ||
                                          _userProfile!.profilePicture!.isEmpty)
                                      ? const Icon(Icons.person, size: 70, color: Colors.grey)
                                      : null,
                                ),
                              ),
                              if (widget.isCurrentUser)
                                Container(
                                  padding: const EdgeInsets.all(8.0),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.blue,
                                    size: 20.0,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_isSaving)
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.5),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16.0),
                    // Username
                    Text(
                      _userProfile?.username ?? 'Unknown User',
                      style: const TextStyle(
                        fontSize: 28.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    // Status
                    if (_userProfile?.status != null && _userProfile!.status!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: Text(
                          _userProfile!.status!,
                          style: const TextStyle(
                            fontSize: 16.0,
                            color: Colors.white70,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              if (widget.isCurrentUser)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  onPressed: _editProfile,
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'About',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  _buildModernInfoItem(
                    Icons.email_outlined,
                    'Email',
                    _userProfile?.email ?? 'No email provided',
                  ),
                  if (_userProfile?.phoneNumber != null &&
                      _userProfile!.phoneNumber!.isNotEmpty)
                    _buildModernInfoItem(
                      Icons.phone_outlined,
                      'Phone',
                      _userProfile!.phoneNumber!,
                    ),
                  if (_userProfile?.lastSeen != null)
                    _buildModernInfoItem(
                      Icons.access_time_outlined,
                      'Last seen',
                      _formatLastSeen(_userProfile!.lastSeen!),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          if (widget.isCurrentUser)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: ElevatedButton.icon(
                  onPressed: _editProfile,
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Profile'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}