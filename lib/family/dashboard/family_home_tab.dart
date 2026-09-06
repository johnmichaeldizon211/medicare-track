import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/conversation_service.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';
import 'package:medicare_tract/core/utils/ux_helpers.dart';
import 'package:medicare_tract/family/dashboard/resident_detail_screen.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class FamilyHomeTab extends StatefulWidget {
  final Function(int) onTabChange;

  const FamilyHomeTab({super.key, required this.onTabChange});

  @override
  State<FamilyHomeTab> createState() => _FamilyHomeTabState();
}

class _FamilyHomeTabState extends State<FamilyHomeTab> {
  final ProfileService _profileService = ProfileService.instance;
  final ResidentService _residentService = ResidentService.instance;
  final ConversationService _conversationService = ConversationService.instance;

  Timer? _midnightTimer;
  bool _isLoading = true;
  String? _errorMessage;
  String _familyName = 'Family Member';
  String? _familyResidentId;
  Map<String, dynamic>? _residentSummary;
  List<_MedicationEventPreview> _todayMedicationEvents = const [];
  List<_CareTaskPreview> _todayCareTasks = const [];
  _ConversationPreview? _conversationPreview;

  @override
  void initState() {
    super.initState();
    _refreshDashboard();
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    super.dispose();
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();

    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final waitDuration =
        nextMidnight.difference(now) + const Duration(seconds: 1);

    _midnightTimer = Timer(waitDuration, () {
      if (!mounted) {
        return;
      }
      _refreshDashboard();
      _scheduleMidnightRefresh();
    });
  }

  Future<void> _refreshDashboard() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    String nextFamilyName = _familyName;
    String? nextResidentId = _familyResidentId;
    Map<String, dynamic>? nextResidentSummary;
    List<_MedicationEventPreview> nextMedicationEvents = const [];
    List<_CareTaskPreview> nextTodayCareTasks = const [];
    _ConversationPreview? nextConversationPreview;
    String? nextErrorMessage;

    try {
      final profile = await _profileService.getProfile();
      final familyProfile = asStringMap(profile['familyProfile']);
      final contactName = (familyProfile?['contactName'] ?? '')
          .toString()
          .trim();
      final username = (profile['username'] ?? '').toString().trim();
      final email = (profile['email'] ?? '').toString().trim();
      nextFamilyName = contactName.isNotEmpty
          ? contactName
          : (username.isNotEmpty
                ? username
                : (email.isNotEmpty ? email : 'Family Member'));
      final residentId = (familyProfile?['residentId'] ?? '').toString().trim();
      if (residentId.isNotEmpty) {
        nextResidentId = residentId;
      }
    } on ApiException catch (e) {
      nextErrorMessage = e.message;
    } catch (_) {
      nextErrorMessage = 'Unable to load profile details right now.';
    }

    try {
      final residents = await _residentService.getResidents();
      final residentList = mapListFrom(residents);

      if (residentList.isNotEmpty) {
        nextResidentSummary = residentList.first;
      }

      final fallbackId = nextResidentSummary == null
          ? nextResidentId
          : (nextResidentSummary['id'] ?? '').toString().trim();

      if (fallbackId != null && fallbackId.isNotEmpty) {
        final detail = await _residentService.getResidentDetail(fallbackId);
        nextResidentSummary = _mergeResidentSummaryWithDetail(
          summary: nextResidentSummary,
          detail: detail,
        );
        nextMedicationEvents = _extractTodayMedicationEvents(detail);
        nextTodayCareTasks = _extractTodayCareTasks(detail);
      }
    } on ApiException catch (e) {
      nextErrorMessage ??= e.message;
    } catch (_) {
      nextErrorMessage ??= 'Unable to load resident activity right now.';
    }

    try {
      final conversations = await _conversationService.getConversations();
      nextConversationPreview = _buildConversationPreview(conversations);
    } catch (_) {
      nextConversationPreview = null;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _familyName = nextFamilyName;
      _familyResidentId = nextResidentId;
      _residentSummary = nextResidentSummary;
      _todayMedicationEvents = nextMedicationEvents;
      _todayCareTasks = nextTodayCareTasks;
      _conversationPreview = nextConversationPreview;
      _errorMessage = nextErrorMessage;
      _isLoading = false;
    });
  }

  static DateTime? _tryParseDateTime(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toLocal();
  }

  bool _isToday(DateTime value) {
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _residentStatusLabel(String raw) {
    switch (raw.toUpperCase()) {
      case 'NEEDS_ATTENTION':
        return 'Needs Attention';
      case 'CRITICAL':
        return 'Critical';
      case 'STABLE':
      default:
        return 'Stable';
    }
  }

  Color _residentStatusColor(String raw) {
    switch (raw.toUpperCase()) {
      case 'NEEDS_ATTENTION':
        return const Color(0xFFFFA726);
      case 'CRITICAL':
        return const Color(0xFFE53935);
      case 'STABLE':
      default:
        return const Color(0xFF00C853);
    }
  }

  String _medStatusLabel(String raw) {
    switch (raw.toUpperCase()) {
      case 'TAKEN':
        return 'Taken';
      case 'MISSED':
        return 'Missed';
      case 'SKIPPED':
        return 'Skipped';
      case 'DELAYED':
        return 'Delayed';
      case 'PENDING':
      default:
        return 'Pending';
    }
  }

  Color _medStatusColor(String raw) {
    switch (raw.toUpperCase()) {
      case 'TAKEN':
        return const Color(0xFF00C853);
      case 'MISSED':
        return const Color(0xFFE53935);
      case 'SKIPPED':
        return Colors.grey;
      case 'DELAYED':
        return const Color(0xFFFFA726);
      case 'PENDING':
      default:
        return const Color(0xFFFFA726);
    }
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'NA';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Map<String, dynamic> _mergeResidentSummaryWithDetail({
    required Map<String, dynamic>? summary,
    required Map<String, dynamic> detail,
  }) {
    final detailConditions = stringListFrom(detail['conditions']);

    final merged = <String, dynamic>{
      ...?summary,
      'id': (detail['id'] ?? summary?['id'] ?? '').toString(),
      'name': (detail['name'] ?? summary?['name'] ?? 'Resident').toString(),
      'room': (detail['room'] ?? summary?['room'] ?? '-').toString(),
      'age': detail['age'] ?? summary?['age'] ?? 0,
      'overallStatus':
          (detail['overallStatus'] ?? summary?['overallStatus'] ?? 'STABLE')
              .toString(),
      'conditions': detailConditions.isEmpty
          ? stringListFrom(summary?['conditions'])
          : detailConditions,
      'medicationCount': listFrom(detail['medications']).length,
      'careTaskCount': listFrom(detail['careTasks']).length,
    };
    return merged;
  }

  List<_MedicationEventPreview> _extractTodayMedicationEvents(
    Map<String, dynamic> detail,
  ) {
    final events = <_MedicationEventPreview>[];

    for (final medication in mapListFrom(detail['medications'])) {
      final medName = (medication['name'] ?? 'Medication').toString();
      final medDosage = (medication['dosage'] ?? '').toString();

      for (final event in mapListFrom(medication['events'])) {
        final scheduledAt = _tryParseDateTime(event['scheduledAt']);
        if (scheduledAt == null || !_isToday(scheduledAt)) {
          continue;
        }

        final status = (event['status'] ?? 'PENDING').toString().toUpperCase();
        events.add(
          _MedicationEventPreview(
            name: medName,
            dosage: medDosage,
            scheduledAt: scheduledAt,
            status: status,
          ),
        );
      }
    }

    events.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return events;
  }

  List<_CareTaskPreview> _extractTodayCareTasks(Map<String, dynamic> detail) {
    final previews = <_CareTaskPreview>[];

    for (final task in mapListFrom(detail['careTasks'])) {
      final event = asStringMap(task['event']);
      if (event == null) continue;
      final updatedAt = _tryParseDateTime(event['updatedAt']);
      if (updatedAt == null || !_isToday(updatedAt)) {
        continue;
      }

      previews.add(
        _CareTaskPreview(
          title: (task['title'] ?? 'Care task').toString(),
          status: (event['status'] ?? 'PENDING').toString().toUpperCase(),
          updatedAt: updatedAt,
          completedAt: _tryParseDateTime(event['timeCompleted']),
          scheduledTimeText: (task['scheduledTime'] ?? '').toString(),
        ),
      );
    }

    previews.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return previews;
  }

  _ConversationPreview? _buildConversationPreview(
    List<Map<String, dynamic>> raw,
  ) {
    if (raw.isEmpty) {
      return null;
    }

    final conversations = List<Map<String, dynamic>>.from(raw);
    conversations.sort((a, b) {
      final aLast = _tryParseDateTime(
        asStringMap(a['lastMessage'])?['createdAt'],
      );
      final bLast = _tryParseDateTime(
        asStringMap(b['lastMessage'])?['createdAt'],
      );
      if (aLast == null && bLast == null) {
        return 0;
      }
      if (aLast == null) {
        return 1;
      }
      if (bLast == null) {
        return -1;
      }
      return bLast.compareTo(aLast);
    });

    final first = conversations.first;
    final resident = stringMapFrom(first['resident']);
    final residentName = (resident['name'] ?? 'Care Team').toString();
    final lastMessage = asStringMap(first['lastMessage']);
    final message = (lastMessage?['content'] ?? 'No messages yet.').toString();
    final createdAt = _tryParseDateTime(lastMessage?['createdAt']);

    return _ConversationPreview(
      title: residentName,
      message: message,
      timeLabel: createdAt == null ? '' : _formatTime(createdAt),
    );
  }

  _MedicationEventPreview? _findUpcomingMedication() {
    if (_todayMedicationEvents.isEmpty) {
      return null;
    }
    final pendingEvents =
        _todayMedicationEvents
            .where(
              (item) => item.status == 'PENDING' || item.status == 'DELAYED',
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    if (pendingEvents.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    for (final event in pendingEvents) {
      if (!event.scheduledAt.isBefore(now)) {
        return event;
      }
    }
    return pendingEvents.first;
  }

  @override
  Widget build(BuildContext context) {
    final hasResident = _residentSummary != null;
    final residentName = hasResident
        ? (_residentSummary!['name'] ?? 'Resident').toString()
        : 'No linked resident';
    final residentRoom = hasResident
        ? (_residentSummary!['room'] ?? '-').toString()
        : '-';
    final residentAge = hasResident
        ? (_residentSummary!['age']?.toString() ?? '0')
        : '0';
    final residentStatusRaw = hasResident
        ? (_residentSummary!['overallStatus'] ?? 'STABLE').toString()
        : '';
    final residentStatus = hasResident
        ? _residentStatusLabel(residentStatusRaw)
        : 'Waiting for assignment';
    final residentStatusColor = hasResident
        ? _residentStatusColor(residentStatusRaw)
        : Colors.grey;

    final medsTaken = _todayMedicationEvents
        .where((item) => item.status == 'TAKEN')
        .length;
    final medsTotal = _todayMedicationEvents.length;
    final tasksDone = _todayCareTasks
        .where((item) => item.status == 'DONE')
        .length;
    final tasksTotal = _todayCareTasks.length;
    final upcomingMedication = _findUpcomingMedication();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          children: [
            _buildHeader(_familyName),
            const SizedBox(height: 25),
            GestureDetector(
              onTap: hasResident
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ResidentDetailScreen(
                            onTabChange: widget.onTabChange,
                            residentId: (_residentSummary?['id'] ?? '')
                                .toString(),
                          ),
                        ),
                      );
                    }
                  : null,
              child: _buildPatientCard(
                name: residentName,
                room: residentRoom,
                age: residentAge,
                status: residentStatus,
                statusColor: residentStatusColor,
                isActive: hasResident,
              ),
            ),
            const SizedBox(height: 20),
            _buildStatsRow(
              medicationsValue: '$medsTaken/$medsTotal',
              tasksValue: '$tasksDone/$tasksTotal',
            ),
            if (_isLoading) ...[
              const SizedBox(height: 12),
              const InlineLoading(message: 'Loading dashboard...'),
            ],
            if (_errorMessage != null) ...[
              StatusView.error(
                title: 'Could not refresh dashboard',
                message: _errorMessage!,
                onAction: _refreshDashboard,
              ),
            ],
            const SizedBox(height: 25),
            const Text(
              "Upcoming Medications",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D0C57),
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: () => widget.onTabChange(1),
              child: upcomingMedication == null
                  ? _buildEmptyInfoCard(
                      icon: Icons.medical_services_outlined,
                      text: "No upcoming medications today.",
                    )
                  : _buildUpcomingMedCard(
                      upcomingMedication.name,
                      '${upcomingMedication.dosage}, ${_formatTime(upcomingMedication.scheduledAt)}',
                      _medStatusLabel(upcomingMedication.status),
                      _medStatusColor(upcomingMedication.status),
                    ),
            ),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Today's Care Tasks",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D0C57),
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onTabChange(2),
                  child: const Text(
                    "See all",
                    style: TextStyle(color: Color(0xFF00BFA5)),
                  ),
                ),
              ],
            ),
            if (_todayCareTasks.isEmpty)
              _buildEmptyInfoCard(
                icon: Icons.checklist_outlined,
                text: "No care task activity yet for today.",
              )
            else
              ..._todayCareTasks.take(3).map((task) {
                final label = task.completedAt != null
                    ? "Done at ${_formatTime(task.completedAt!)}"
                    : (task.scheduledTimeText.isNotEmpty
                          ? task.scheduledTimeText
                          : _formatTime(task.updatedAt));
                return _buildTaskItem(task.title, label, task.status == 'DONE');
              }),
            const SizedBox(height: 25),
            const Text(
              "Messages",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D0C57),
              ),
            ),
            const SizedBox(height: 15),
            GestureDetector(
              onTap: () => widget.onTabChange(3),
              child: _buildMessagePreviewCard(
                _conversationPreview?.title ?? 'No conversations yet',
                _conversationPreview?.message ?? 'No updates yet.',
                _conversationPreview?.timeLabel ?? '',
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String familyName) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greetingForNow(),
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              Text(
                familyName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFA726),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFEDE7F6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_alt, size: 16, color: Color(0xFF5E35B1)),
              SizedBox(width: 6),
              Text(
                "Family Member",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFF5E35B1),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPatientCard({
    required String name,
    required String room,
    required String age,
    required String status,
    required Color statusColor,
    required bool isActive,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: const Color(0xFFE0F2F1),
            child: Text(
              _initials(name),
              style: const TextStyle(
                color: Color(0xFF00BFA5),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive
                      ? "Room $room - Age $age"
                      : "Waiting for resident assignment",
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            color: isActive ? Colors.black87 : Colors.grey.shade400,
            size: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow({
    required String medicationsValue,
    required String tasksValue,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            medicationsValue,
            "Medications",
            Icons.medication,
            const Color(0xFFE3F2FD),
            const Color(0xFF42A5F5),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: _buildStatCard(
            tasksValue,
            "Completed Tasks",
            Icons.check_box,
            const Color(0xFFE8F5E9),
            const Color(0xFF66BB6A),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String count,
    String label,
    IconData icon,
    Color bgColor,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            count,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00BFA5),
            ),
          ),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildUpcomingMedCard(
    String name,
    String detail,
    String status,
    Color statusColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.medical_services,
              color: Color(0xFF00BFA5),
              size: 20,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 12, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskItem(String title, String timeLabel, bool isDone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isDone ? const Color(0xFF00C853) : Colors.grey.shade400,
            size: 24,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                color: isDone ? Colors.black : Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            timeLabel,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagePreviewCard(
    String sender,
    String message,
    String timeLabel,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.chat_bubble,
              color: Color(0xFF00BFA5),
              size: 20,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (timeLabel.isNotEmpty)
            Text(
              timeLabel,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyInfoCard({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicationEventPreview {
  final String name;
  final String dosage;
  final DateTime scheduledAt;
  final String status;

  const _MedicationEventPreview({
    required this.name,
    required this.dosage,
    required this.scheduledAt,
    required this.status,
  });
}

class _CareTaskPreview {
  final String title;
  final String status;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String scheduledTimeText;

  const _CareTaskPreview({
    required this.title,
    required this.status,
    required this.updatedAt,
    required this.completedAt,
    required this.scheduledTimeText,
  });
}

class _ConversationPreview {
  final String title;
  final String message;
  final String timeLabel;

  const _ConversationPreview({
    required this.title,
    required this.message,
    required this.timeLabel,
  });
}
