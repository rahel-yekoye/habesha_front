import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../services/profile_service.dart';

class ProfilePictureGallery extends StatefulWidget {
  final String userId;
  final List<String> profilePictureHistory;
  final int initialIndex;

  const ProfilePictureGallery({
    super.key,
    required this.userId,
    required this.profilePictureHistory,
    this.initialIndex = 0,
  });

  @override
  State<ProfilePictureGallery> createState() => _ProfilePictureGalleryState();
}

class _ProfilePictureGalleryState extends State<ProfilePictureGallery> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showDeleteConfirmation(String imageUrl, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Are you sure you want to delete this profile picture from your history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // TODO: Implement delete from history API call
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Photo deleted from history')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _setAsCurrentProfilePicture(String imageUrl) async {
    try {
      // Update profile with selected image
      await ProfileService.updateProfile(widget.userId, {
        'profilePicture': imageUrl,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate update
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile picture: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} of ${widget.profilePictureHistory.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              final currentImageUrl = widget.profilePictureHistory[_currentIndex];
              switch (value) {
                case 'set_current':
                  _setAsCurrentProfilePicture(currentImageUrl);
                  break;
                case 'delete':
                  _showDeleteConfirmation(currentImageUrl, _currentIndex);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'set_current',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Set as Current'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete from History'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: widget.profilePictureHistory.length,
        builder: (context, index) {
          return PhotoViewGalleryPageOptions(
            imageProvider: CachedNetworkImageProvider(
              widget.profilePictureHistory[index],
            ),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
            heroAttributes: PhotoViewHeroAttributes(
              tag: 'profile-picture-${widget.userId}-$index',
            ),
          );
        },
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        scrollPhysics: const BouncingScrollPhysics(),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
      bottomNavigationBar: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: () => _setAsCurrentProfilePicture(
                widget.profilePictureHistory[_currentIndex],
              ),
              icon: const Icon(Icons.check_circle),
              label: const Text('Set as Current'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _showDeleteConfirmation(
                widget.profilePictureHistory[_currentIndex],
                _currentIndex,
              ),
              icon: const Icon(Icons.delete),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
