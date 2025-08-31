import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:video_player/video_player.dart';
import '../../models/message.dart' as models;
import 'package:audioplayers/audioplayers.dart' as ap;
import 'group_widgets.dart';
import 'group_file_handling.dart';
import 'group_socket_handlers.dart';
import 'group_message_actions.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String groupDescription;
  final String currentUser;
  final String jwtToken;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.groupDescription,
    required this.currentUser,
    required this.jwtToken,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  List<models.Message> messages = [];
  IO.Socket? socket;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool isLoading = true;
  bool _joinedGroup = false;

  bool _showEmojiPicker = false;
  bool _isSelectionMode = false;
  Set<int> _selectedMessageIndices = {};
  List<dynamic> groupMembers = [];
  List<Map<String, dynamic>> allUsers = [];
  final List<PlatformFile> _selectedFiles = [];
  final List<models.Message> _recentlyDeletedMessages = [];
  Timer? _undoTimer;
  String? _editingMessageId;
  final TextEditingController _editController = TextEditingController();
  Offset? _popupPosition;

  @override
  void initState() {
    super.initState();
    GroupSocketHandlers.initializeSocket(
      context: context,
      widget: widget,
      onMessagesUpdate: (msgs) => setState(() {
        messages = msgs;
        // Always scroll after messages update
        _scrollToBottomSmooth();
      }),
      onJoinedGroup: (joined) => setState(() => _joinedGroup = joined),
      onSocket: (s) => socket = s,
      onScrollToBottom: _scrollToBottomSmooth,
    );
    _fetchInitialData();

    _focusNode.addListener(() {
      if (!mounted) return;
      if (_focusNode.hasFocus) {
        setState(() => _showEmojiPicker = false);
      }
    });

    _scrollController.addListener(() {
      if (!mounted) return;
      // Optionally: implement read receipts or lazy loading
    });
  }

  Future<void> _fetchInitialData() async {
    setState(() => isLoading = true);

    final fetchedMessages = await GroupFileHandling.fetchMessages(
      groupId: widget.groupId,
      jwtToken: widget.jwtToken,
    );
    final fetchedMembers = await GroupFileHandling.fetchGroupMembers(
      groupId: widget.groupId,
      jwtToken: widget.jwtToken,
    );
    final fetchedUsers = await GroupFileHandling.fetchAllUsers(
      jwtToken: widget.jwtToken,
    );

    setState(() {
      messages = fetchedMessages;
      groupMembers = fetchedMembers;
      allUsers = fetchedUsers;
      isLoading = false;
    });
    GroupSocketHandlers.setInitialMessages(fetchedMessages);

    // Always scroll after the frame is built and messages are set
    _scrollToBottomSmooth();
  }

  String _getUsername(String userId) {
    final user = allUsers.firstWhere(
      (u) => u['_id'] == userId,
      orElse: () => {'username': userId},
    );
    return user['username'] ?? userId;
  }

  Future<List<PlatformFile>?> _pickAndAddFiles() async {
    return await GroupFileHandling.pickAndAddFiles(
      context: context,
      selectedFiles: _selectedFiles,
      focusNode: _focusNode,
      onUpdate: () => setState(() {}),
    );
  }

  void _scrollToBottomSmooth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && messages.isNotEmpty) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    GroupSocketHandlers.disposeSocket(socket, widget.groupId);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _editController.dispose();
    _undoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<models.Message> filteredMessages =
        messages.where((msg) => !msg.deleted).toList();

    return Scaffold(
      appBar: buildGroupAppBar(
        context: context,
        groupName: widget.groupName,
        isSelectionMode: _isSelectionMode,
        onCloseSelection: () => setState(() {
          _isSelectionMode = false;
          _selectedMessageIndices.clear();
        }),
        onDeleteSelected: () async {
          await GroupMessageActions.deleteMessagesWithUndo(
            context: context,
            selectedIndices: _selectedMessageIndices,
            messages: messages,
            onUpdateMessages: (msgs) => setState(() => messages = msgs),
            onDeleteConfirmed: (ids) => setState(() {
              messages.removeWhere((m) => ids.contains(m.id));
              _selectedMessageIndices.clear();
              _isSelectionMode = false;
            }),
            groupId: widget.groupId,
            jwtToken: widget.jwtToken,
            socket: socket,
          );
        },
        onShowInfo: _showGroupInfo,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: filteredMessages.isEmpty
                          ? const Center(child: Text('No messages yet'))
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: filteredMessages.length,
                              itemBuilder: (context, index) {
                                return GroupMessageBubble(
                                  message: filteredMessages[index],
                                  isSender: filteredMessages[index].sender == widget.currentUser,
                                  isSelected: _selectedMessageIndices.contains(index),
                                  usernameResolver: _getUsername,
                                  editingMessageId: _editingMessageId,
                                  editController: _editController,
                                  onLongPress: (details) => GroupMessageActions.handleLongPress(
                                    context: context,
                                    index: index,
                                    details: details,
                                    onSelectionMode: (mode) => setState(() => _isSelectionMode = mode),
                                    onUpdateSelection: (indices) => setState(() => _selectedMessageIndices = indices),
                                    onPopupPosition: (pos) => setState(() => _popupPosition = pos),
                                  ),
                                  onTap: () => GroupMessageActions.handleTap(
                                    context: context,
                                    index: index,
                                    selectedIndices: _selectedMessageIndices,
                                    onUpdateSelection: (indices) => setState(() => _selectedMessageIndices = indices),
                                    onSelectionMode: (mode) => setState(() => _isSelectionMode = mode),
                                    onPopupPosition: (pos) => setState(() => _popupPosition = pos),
                                  ),
                                  onEdit: (newText) async {
                                    if (newText.isNotEmpty) {
                                      await GroupMessageActions.editMessage(
                                        context: context,
                                        messageId: filteredMessages[index].id,
                                        newContent: newText,
                                        groupId: widget.groupId,
                                        jwtToken: widget.jwtToken,
                                        socket: socket,
                                        onUpdateMessages: (msgs) => setState(() => messages = msgs),
                                      );
                                      setState(() {
                                        _editingMessageId = null;
                                        _editController.clear();
                                      });
                                    }
                                  },
                                  onDelete: () async {
                                    await GroupMessageActions.deleteMessagesWithUndo(
                                      context: context,
                                      selectedIndices: {index},
                                      messages: messages,
                                      onUpdateMessages: (msgs) => setState(() => messages = msgs),
                                      onDeleteConfirmed: (ids) => setState(() {
                                        messages.removeWhere((m) => ids.contains(m.id));
                                        _selectedMessageIndices.clear();
                                        _isSelectionMode = false;
                                      }),
                                      groupId: widget.groupId,
                                      jwtToken: widget.jwtToken,
                                      socket: socket,
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                    GroupChatInputField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      showEmojiPicker: _showEmojiPicker,
                      selectedFiles: _selectedFiles,
                      onEmojiToggle: () {
                        _focusNode.unfocus();
                        setState(() => _showEmojiPicker = !_showEmojiPicker);
                      },
                        canSend: _joinedGroup && (socket?.connected ?? false),

                      onSend: () => GroupSocketHandlers.sendMessage(
                        context: context,
                        socket: socket,
                        joinedGroup: _joinedGroup,
                        widget: widget,
                        messageController: _messageController,
                        selectedFiles: _selectedFiles,
                        onUpdateMessages: (msgs) => setState(() => messages = msgs),
                        onClearFiles: () => setState(() => _selectedFiles.clear()),
                        onScrollToBottom: _scrollToBottomSmooth,
                        currentMessages: messages, // <-- Add this line!
                      ),
                      pickFiles: _pickAndAddFiles,
                      onRemoveFile: (index) => setState(() => _selectedFiles.removeAt(index)),
                    ),
                  ],
                ),
                if (_isSelectionMode &&
                    _selectedMessageIndices.length == 1 &&
                    _popupPosition != null)
                  buildGroupPopupMenu(
                    context: context,
                    message: filteredMessages[_selectedMessageIndices.first],
                    onCopy: () => GroupMessageActions.copyMessage(
                      context: context,
                      message: filteredMessages[_selectedMessageIndices.first],
                      onDismiss: _dismissPopup,
                    ),
                    onEdit: () => setState(() {
                      _editingMessageId = filteredMessages[_selectedMessageIndices.first].id;
                      _editController.text = filteredMessages[_selectedMessageIndices.first].content;
                      _dismissPopup();
                    }),
                    onDismiss: _dismissPopup,
                    position: _popupPosition!,
                    isMe: filteredMessages[_selectedMessageIndices.first].sender == widget.currentUser,
                  ),
              ],
            ),
    );
  }

  void _dismissPopup() {
    setState(() {
      _isSelectionMode = false;
      _selectedMessageIndices.clear();
      _popupPosition = null;
    });
  }

  void _showGroupInfo() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return buildGroupInfoSheet(
          groupName: widget.groupName,
          groupDescription: widget.groupDescription,
          groupMembers: groupMembers,
          getUsername: _getUsername,
        );
      },
    );
  }
}

// Re-using InlineVideoPlayer and InlineAudioPlayer from chatapp.txt
class InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;

  const InlineVideoPlayer({super.key, required this.videoUrl});

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

@override
void initState() {
  super.initState();
  _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
  _controller.initialize().then((_) {
    if (!mounted) return;
    _controller.setVolume(1.0);  // Set volume after initialized
    setState(() {
      _isInitialized = true;
    });
  });
}


  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (!mounted) return; // Guard against setState after dispose
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isInitialized
        ? GestureDetector(
            onTap: _togglePlayPause,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
                if (!_controller.value.isPlaying)
                  const Icon(Icons.play_circle_fill,
                      size: 64, color: Colors.white),
              ],
            ),
          )
        : const Center(child: CircularProgressIndicator());
  }
}

class InlineAudioPlayer extends StatefulWidget {
  final String audioUrl;

  const InlineAudioPlayer({required this.audioUrl, super.key});

  @override
  _InlineAudioPlayerState createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  late final ap.AudioPlayer _audioPlayer;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = ap.AudioPlayer();
    _audioPlayer.onPlayerComplete.listen((event) {
      if (!mounted) return; // Guard against setState after dispose
      setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.play(ap.UrlSource(widget.audioUrl));
      }
      if (!mounted) return; // Guard against setState after dispose
      setState(() => _isPlaying = !_isPlaying);
    } catch (e) {
      print('Audio play error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _isPlaying ? Icons.pause_circle : Icons.play_circle,
        color: Colors.blue,
        size: 36,
      ),
      onPressed: _togglePlayPause,
    );
  }
}
