import 'package:flutter/material.dart';
import 'package:medicare_tract/caregiver/messages/chat_detail_screen.dart';
import 'package:medicare_tract/core/services/conversation_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

enum _MessageFilter { all, caregivers, family, unread }

class AdminMessagesTab extends StatefulWidget {
  const AdminMessagesTab({super.key});

  @override
  State<AdminMessagesTab> createState() => _AdminMessagesTabState();
}

class _AdminMessagesTabState extends State<AdminMessagesTab> {
  final ConversationService _conversationService = ConversationService.instance;
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _conversations = [];
  _MessageFilter _selectedFilter = _MessageFilter.all;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final data = await _conversationService.getConversations();
      if (!mounted) {
        return;
      }
      setState(() {
        _conversations = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to load conversations right now.';
        _loading = false;
      });
    }
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'NA';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  String _formatLastMessageTime(Map<String, dynamic>? lastMessage) {
    if (lastMessage == null) {
      return '';
    }
    final raw = (lastMessage['createdAt'] ?? '').toString();
    if (raw.isEmpty) {
      return '';
    }
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final suffix = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $suffix';
    } catch (_) {
      return '';
    }
  }

  String _displayPeerName(Map<String, dynamic> chat) {
    final peer = chat['peer'] as Map<String, dynamic>? ?? {};
    final caregiverProfile = peer['caregiverProfile'] as Map<String, dynamic>?;
    final familyProfile = peer['familyProfile'] as Map<String, dynamic>?;
    final caregiverName = (caregiverProfile?['displayName'] ?? '').toString();
    final familyName = (familyProfile?['contactName'] ?? '').toString();
    if (caregiverName.isNotEmpty) {
      return caregiverName;
    }
    if (familyName.isNotEmpty) {
      return familyName;
    }
    final username = (peer['username'] ?? '').toString();
    if (username.isNotEmpty) {
      return username;
    }
    return (peer['email'] ?? 'Conversation').toString();
  }

  String _displayPeerRole(Map<String, dynamic> chat) {
    return _isCaregiverConversation(chat) ? 'Caregiver' : 'Family';
  }

  String _residentSummary(Map<String, dynamic> chat) {
    final residentsRaw = chat['residents'] as List<dynamic>? ?? const [];
    final residents = residentsRaw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    if (_isCaregiverConversation(chat)) {
      if (residents.length > 1) {
        return '${residents.length} assigned residents';
      }
      if (residents.length == 1) {
        final room = (residents.first['room'] ?? '').toString();
        final name = (residents.first['name'] ?? 'Resident').toString();
        return room.isEmpty ? name : '$name, Room $room';
      }
      return 'Assigned residents';
    }

    final resident = chat['resident'] as Map<String, dynamic>? ?? {};
    final residentName = (resident['name'] ?? 'Resident').toString();
    final room = (resident['room'] ?? '').toString();
    return room.isEmpty ? residentName : '$residentName, Room $room';
  }

  bool _isCaregiverConversation(Map<String, dynamic> chat) {
    final type = (chat['type'] ?? '').toString().toUpperCase();
    if (type.isNotEmpty) {
      return type == 'CAREGIVER';
    }

    final peer = chat['peer'] as Map<String, dynamic>? ?? {};
    return peer['caregiverProfile'] != null;
  }

  int get _unreadConversationCount => _conversations
      .where((chat) => ((chat['unreadCount'] as num?)?.toInt() ?? 0) > 0)
      .length;

  List<Map<String, dynamic>> get _filteredConversations {
    return _conversations.where((chat) {
      final unreadCount = (chat['unreadCount'] as num?)?.toInt() ?? 0;

      switch (_selectedFilter) {
        case _MessageFilter.all:
          return true;
        case _MessageFilter.caregivers:
          return _isCaregiverConversation(chat);
        case _MessageFilter.family:
          return !_isCaregiverConversation(chat);
        case _MessageFilter.unread:
          return unreadCount > 0;
      }
    }).toList();
  }

  String get _selectedFilterLabel {
    switch (_selectedFilter) {
      case _MessageFilter.all:
        return 'All';
      case _MessageFilter.caregivers:
        return 'Caregivers';
      case _MessageFilter.family:
        return 'Family';
      case _MessageFilter.unread:
        return 'Unread';
    }
  }

  Widget _buildFilterChip({
    required _MessageFilter filter,
    required String label,
    int? count,
  }) {
    final selected = _selectedFilter == filter;
    final displayLabel = count == null ? label : '$label $count';

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ChoiceChip(
        label: Text(displayLabel),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) {
          setState(() => _selectedFilter = filter);
        },
        backgroundColor: const Color(0xFFE9EDF2),
        selectedColor: const Color(0xFFE3F2FD),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF1976D2) : Colors.grey.shade700,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildFilterChip(filter: _MessageFilter.all, label: 'All'),
          _buildFilterChip(
            filter: _MessageFilter.caregivers,
            label: 'Caregivers',
          ),
          _buildFilterChip(filter: _MessageFilter.family, label: 'Family'),
          _buildFilterChip(
            filter: _MessageFilter.unread,
            label: 'Unread',
            count: _unreadConversationCount,
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyView() {
    return ListView(
      children: [
        StatusView.empty(
          icon: Icons.filter_list_off,
          title: 'No $_selectedFilterLabel messages',
          message: 'Try another filter to see more conversations.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = width < 360
              ? 14.0
              : width < 700
              ? 20.0
              : 32.0;

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: width < 700 ? 20 : 24,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Messages",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFFA726),
                                  ),
                                ),
                                Text(
                                  "Admin hub conversations",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_user,
                                  color: Color(0xFFFFA726),
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  "Admin",
                                  style: TextStyle(
                                    color: Color(0xFFFFA726),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildFilterBar(),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadConversations,
                        child: _loading
                            ? const InlineLoading(
                                message: 'Loading conversations...',
                              )
                            : _errorMessage != null
                            ? ListView(
                                children: [
                                  StatusView.error(
                                    title: 'Could not load messages',
                                    message: _errorMessage!,
                                    onAction: _loadConversations,
                                  ),
                                ],
                              )
                            : _conversations.isEmpty
                            ? ListView(
                                children: const [
                                  StatusView.empty(
                                    icon: Icons.chat_bubble_outline,
                                    title: 'No conversations yet',
                                    message:
                                        'Family and caregiver conversations will appear here.',
                                  ),
                                ],
                              )
                            : _filteredConversations.isEmpty
                            ? _buildFilteredEmptyView()
                            : ListView.builder(
                                padding: const EdgeInsets.only(bottom: 20),
                                itemCount: _filteredConversations.length,
                                itemBuilder: (context, index) {
                                  final chat = _filteredConversations[index];
                                  final peerName = _displayPeerName(chat);
                                  final peerRole = _displayPeerRole(chat);
                                  final residentSummary = _residentSummary(
                                    chat,
                                  );
                                  final unreadCount =
                                      (chat['unreadCount'] as num?)?.toInt() ??
                                      0;
                                  final hasUnread = unreadCount > 0;
                                  final lastMessage =
                                      chat['lastMessage']
                                          as Map<String, dynamic>?;

                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatDetailScreen(
                                            residentName: residentSummary,
                                            isReadOnly: false,
                                            conversationId:
                                                (chat['conversationId'] ?? '')
                                                    .toString(),
                                            conversationTitle: peerName,
                                            conversationSubtitle:
                                                '$peerRole - $residentSummary',
                                          ),
                                        ),
                                      ).then((_) => _loadConversations());
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 15),
                                      padding: const EdgeInsets.all(15),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(15),
                                        border: Border.all(
                                          color: hasUnread
                                              ? const Color(
                                                  0xFF00BFA5,
                                                ).withValues(alpha: 0.5)
                                              : Colors.grey.withValues(
                                                  alpha: 0.2,
                                                ),
                                          width: hasUnread ? 2 : 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.02,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 25,
                                            backgroundColor: const Color(
                                              0xFFE0F2F1,
                                            ),
                                            child: Text(
                                              _initials(peerName),
                                              style: const TextStyle(
                                                color: Color(0xFF00BFA5),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 15),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  peerName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: hasUnread
                                                        ? FontWeight.w900
                                                        : FontWeight.bold,
                                                    fontSize: 16,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  "$peerRole - $residentSummary",
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF00BFA5),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  (lastMessage?['content'] ??
                                                          "No messages yet")
                                                      .toString(),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: hasUnread
                                                        ? Colors.black87
                                                        : Colors.grey,
                                                    fontWeight: hasUnread
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _formatLastMessageTime(
                                                  lastMessage,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: hasUnread
                                                      ? const Color(0xFF00BFA5)
                                                      : Colors.grey,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              if (hasUnread)
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    6,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Color(
                                                          0xFFFFA726,
                                                        ),
                                                        shape: BoxShape.circle,
                                                      ),
                                                  child: Text(
                                                    unreadCount.toString(),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                )
                                              else
                                                const Icon(
                                                  Icons.arrow_forward_ios,
                                                  color: Colors.grey,
                                                  size: 14,
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
