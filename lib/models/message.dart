import 'dart:developer';

class Message {
  final String id;
  final String? clientId; // optional client-side temporary ID

  final String sender;
  final String receiver;
  final String content;
  final String timestamp;
  final bool isGroup;
  final List<String> emojis;
  final String fileUrl;
  final List<String> readBy;
  final String? type;
  final String? direction;
  final int? duration;
  final bool isFile;
  final bool deleted;
  final bool edited;
  final List<Map<String, String>> reactions; // [{ user, emoji }]
  final String? replyTo; // message id being replied to
  final Map<String, dynamic>? senderMetadata; // Additional sender info like profile picture

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientId': clientId,
    'sender': sender,
    'receiver': receiver,
    'content': content,
    'timestamp': timestamp,
    'isGroup': isGroup,
    'emojis': emojis,
    'fileUrl': fileUrl,
    'readBy': readBy,
    'type': type,
    'direction': direction,
    'duration': duration,
    'isFile': isFile,
    'deleted': deleted,
    'edited': edited,
    'reactions': reactions,
    'replyTo': replyTo,
    'senderMetadata': senderMetadata,
  };

  Message({
    required this.id,
    required this.sender,
    required this.receiver,
    required this.content,
    required this.timestamp,
    required this.isGroup,
    required this.emojis,
    required this.fileUrl,
    required this.readBy,
    this.type,
    this.direction,
    this.duration,
    this.isFile = false,
    this.deleted = false,
    this.edited = false,
    this.clientId,
    this.reactions = const [],
    this.replyTo,
    this.senderMetadata,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    String idString = '';
    
    // Try to get ID from different possible fields
    final idValue = json['_id'] ?? json['id'];
    
    if (idValue != null) {
      if (idValue is String) {
        idString = idValue;
      } else if (idValue is Map && idValue['\$oid'] is String) {
        // Handle MongoDB's ObjectId format: { "$oid": "..." }
        idString = idValue['\$oid'];
      } else {
        // Fallback to string representation
        idString = idValue.toString();
      }
    }
    
    // Clean up the ID string
    if (idString.startsWith('ObjectId(') && idString.endsWith(')')) {
      idString = idString.substring(9, idString.length - 1);
    }
    idString = idString.replaceAll('"', '').trim();
    
    log('Parsed message ID: "$idString" from: $idValue');

    return Message(
      id: idString,
      sender: json['sender'] ?? 'Unknown',
      receiver: json['receiver'] ?? 'Unknown',
      content: json['content'] ?? '',
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      isGroup: json['isGroup'] ?? false,
      emojis: (json['emojis'] as List<dynamic>?)?.cast<String>() ?? [],
      fileUrl: json['fileUrl'] ?? '',
      readBy: (json['readBy'] as List<dynamic>?)?.cast<String>() ?? [],
      type: json['type'],
      direction: json['direction'],
      duration: json['duration'] is int
          ? json['duration']
          : int.tryParse(json['duration']?.toString() ?? ''),
      isFile: json['fileUrl'] != null && (json['fileUrl'] as String).isNotEmpty,
      deleted: json['deleted'] ?? false,
      edited: json['edited'] ?? false,
      clientId: json['clientId'], // keep as-is (nullable)
      reactions: ((json['reactions'] as List?) ?? [])
          .map<Map<String, String>>((e) {
        if (e is Map) {
          final m = Map<String, dynamic>.from(e);
          return {
            'user': m['user']?.toString() ?? '',
            'emoji': m['emoji']?.toString() ?? '',
          };
        }
        return {'user': '', 'emoji': ''};
      }).where((m) => m['user']!.isNotEmpty && m['emoji']!.isNotEmpty).toList(),
      replyTo: (json['replyTo']?.toString().isNotEmpty ?? false)
          ? json['replyTo'].toString()
          : null,
      senderMetadata: json['senderMetadata'] != null 
          ? Map<String, dynamic>.from(json['senderMetadata']) 
          : null,
    );
  }

  Message copyWith({
    String? id,
    String? sender,
    String? receiver,
    String? content,
    String? timestamp,
    bool? isGroup,
    Map<String, dynamic>? senderMetadata,
    List<String>? emojis,
    String? fileUrl,
    List<String>? readBy,
    String? type,
    String? direction,
    int? duration,
    bool? isFile,
    bool? deleted,
    bool? edited,
    String? clientId,  // added clientId here for updates
    List<Map<String, String>>? reactions,
    String? replyTo,
  }) {
    return Message(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      receiver: receiver ?? this.receiver,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isGroup: isGroup ?? this.isGroup,
      emojis: emojis ?? this.emojis,
      fileUrl: fileUrl ?? this.fileUrl,
      readBy: readBy ?? this.readBy,
      type: type ?? this.type,
      direction: direction ?? this.direction,
      duration: duration ?? this.duration,
      isFile: isFile ?? this.isFile,
      deleted: deleted ?? this.deleted,
      edited: edited ?? this.edited,
      clientId: clientId ?? this.clientId,
      reactions: reactions ?? this.reactions,
      replyTo: replyTo ?? this.replyTo,
      senderMetadata: senderMetadata ?? this.senderMetadata,
    );
  }
}

