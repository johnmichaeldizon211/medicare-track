import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/conversation_service.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class ResidentDetailScreen extends StatefulWidget {
  final Function(int)? onTabChange;
  final String? residentId;

  const ResidentDetailScreen({super.key, this.onTabChange, this.residentId});

  @override
  State<ResidentDetailScreen> createState() => _ResidentDetailScreenState();
}

class _ResidentDetailScreenState extends State<ResidentDetailScreen> {
  final ProfileService _profileService = ProfileService.instance;
  final ResidentService _residentService = ResidentService.instance;
  final ConversationService _conversationService = ConversationService.instance;

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _resident;
  List<_MedicationEventItem> _todayMedications = const [];
  List<_CareTaskItem> _todayCareTasks = const [];
  int _unreadMessages = 0;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  DateTime? _tryParseDateTime(dynamic value) {
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

  String _statusLabel(String raw) {
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

  Color _statusColor(String raw) {
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
        return const Color(0xFF00BFA5);
    }
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'R';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Future<String?> _resolveResidentId() async {
    if (widget.residentId != null && widget.residentId!.trim().isNotEmpty) {
      return widget.residentId!.trim();
    }

    try {
      final profile = await _profileService.getProfile();
      final familyProfile = asStringMap(profile['familyProfile']);
      final residentId = (familyProfile?['residentId'] ?? '').toString().trim();
      if (residentId.isNotEmpty) {
        return residentId;
      }
    } catch (_) {
      // fallback below
    }

    final residents = await _residentService.getResidents();
    if (residents.isEmpty) {
      return null;
    }
    final first = stringMapFrom(residents.first);
    final residentId = (first['id'] ?? '').toString().trim();
    return residentId.isEmpty ? null : residentId;
  }

  Future<void> _loadUnreadMessages(String residentId) async {
    try {
      final conversations = await _conversationService.getConversations();
      final match = conversations.firstWhere((item) {
        final resident = stringMapFrom(item['resident']);
        return (resident['id'] ?? '').toString() == residentId;
      }, orElse: () => <String, dynamic>{});
      final count = (match['unreadCount'] as num?)?.toInt() ?? 0;
      _unreadMessages = count < 0 ? 0 : count;
    } catch (_) {
      _unreadMessages = 0;
    }
  }

  Future<void> _loadDetail() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final residentId = await _resolveResidentId();
      if (residentId == null) {
        if (!mounted) {
          return;
        }
        setState(() {
          _resident = null;
          _todayMedications = const [];
          _todayCareTasks = const [];
          _unreadMessages = 0;
          _isLoading = false;
        });
        return;
      }

      final detail = await _residentService.getResidentDetail(residentId);
      final medications = mapListFrom(detail['medications']);
      final careTasks = mapListFrom(detail['careTasks']);

      final todayMeds = <_MedicationEventItem>[];
      for (final medication in medications) {
        final name = (medication['name'] ?? 'Medication').toString();
        final dosage = (medication['dosage'] ?? '').toString();
        for (final event in mapListFrom(medication['events'])) {
          final scheduledAt = _tryParseDateTime(event['scheduledAt']);
          if (scheduledAt == null || !_isToday(scheduledAt)) {
            continue;
          }
          todayMeds.add(
            _MedicationEventItem(
              name: name,
              dosage: dosage,
              status: (event['status'] ?? 'PENDING').toString().toUpperCase(),
              scheduledAt: scheduledAt,
              remark: (event['remark'] ?? '').toString(),
            ),
          );
        }
      }
      todayMeds.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      final todayTasks = <_CareTaskItem>[];
      for (final task in careTasks) {
        final event = asStringMap(task['event']);
        if (event == null) continue;
        final updatedAt = _tryParseDateTime(event['updatedAt']);
        if (updatedAt == null || !_isToday(updatedAt)) {
          continue;
        }
        todayTasks.add(
          _CareTaskItem(
            title: (task['title'] ?? 'Care task').toString(),
            status: (event['status'] ?? 'PENDING').toString().toUpperCase(),
            updatedAt: updatedAt,
            completedAt: _tryParseDateTime(event['timeCompleted']),
            remark: (event['remark'] ?? '').toString(),
          ),
        );
      }
      todayTasks.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

      await _loadUnreadMessages(residentId);

      if (!mounted) {
        return;
      }
      setState(() {
        _resident = detail;
        _todayMedications = todayMeds;
        _todayCareTasks = todayTasks;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _resident = null;
        _todayMedications = const [];
        _todayCareTasks = const [];
        _unreadMessages = 0;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to load resident details right now.';
        _resident = null;
        _todayMedications = const [];
        _todayCareTasks = const [];
        _unreadMessages = 0;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final residentName = (_resident?['name'] ?? 'No linked resident')
        .toString();
    final room = (_resident?['room'] ?? '-').toString();
    final age = (_resident?['age']?.toString() ?? '0');
    final overallStatusRaw = (_resident?['overallStatus'] ?? '').toString();
    final residentStatus = _resident == null
        ? 'Waiting for assignment'
        : _statusLabel(overallStatusRaw);
    final residentStatusColor = _resident == null
        ? Colors.grey
        : _statusColor(overallStatusRaw);

    final medsDone = _todayMedications
        .where((item) => item.status == 'TAKEN')
        .length;
    final medsTotal = _todayMedications.length;
    final tasksDone = _todayCareTasks
        .where((item) => item.status == 'DONE')
        .length;
    final tasksTotal = _todayCareTasks.length;

    final conditions = stringListFrom(_resident?['conditions']);

    final familyProfile = asStringMap(_resident?['familyProfile']);
    final medicalNotes = (_resident?['medicalNotes'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: RefreshIndicator(
        onRefresh: _loadDetail,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildTopHeader(
              context: context,
              residentName: residentName,
              room: room,
              age: age,
              status: residentStatus,
              statusColor: residentStatusColor,
              medsText: '$medsDone/$medsTotal',
              tasksText: '$tasksDone/$tasksTotal',
              unreadText: _unreadMessages.toString(),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: InlineLoading(message: 'Loading resident details...'),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: StatusView.error(
                  title: 'Could not load resident details',
                  message: _errorMessage!,
                  onAction: _loadDetail,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _buildNavigationCards(
                    medsText: "$medsDone/$medsTotal Today",
                    tasksText: "$tasksDone/$tasksTotal Today",
                    messagesText: _unreadMessages == 0
                        ? "No unread"
                        : "$_unreadMessages unread",
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    "Medical Conditions",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  if (conditions.isEmpty)
                    _buildMutedTextCard("No medical conditions listed yet.")
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: conditions.map(_buildConditionChip).toList(),
                    ),
                  const SizedBox(height: 25),
                  _buildInfoSection(
                    title: "Medical Notes",
                    body: medicalNotes.isEmpty
                        ? "No medical notes available."
                        : medicalNotes,
                  ),
                  const SizedBox(height: 25),
                  _buildContactInfo(familyProfile),
                  const SizedBox(height: 25),
                  const Text(
                    "Today's Medications",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  if (_todayMedications.isEmpty)
                    _buildMutedTextCard("No medication events for today.")
                  else
                    ..._todayMedications.map((item) {
                      final detail = item.remark.isNotEmpty
                          ? item.remark
                          : "Scheduled: ${_formatTime(item.scheduledAt)}";
                      return _buildMedicationItem(
                        context,
                        item.name,
                        detail,
                        _medStatusLabel(item.status),
                        _medStatusColor(item.status),
                      );
                    }),
                  const SizedBox(height: 25),
                  const Text(
                    "Today's Care Tasks",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  if (_todayCareTasks.isEmpty)
                    _buildMutedTextCard("No care task events for today.")
                  else
                    ..._todayCareTasks.map((item) {
                      final isDone = item.status == 'DONE';
                      final subtitle = isDone && item.completedAt != null
                          ? "Done at ${_formatTime(item.completedAt!)}"
                          : item.remark.isNotEmpty
                          ? item.remark
                          : _formatTime(item.updatedAt);
                      return _buildTaskItem(
                        context,
                        item.title,
                        subtitle,
                        isDone,
                      );
                    }),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader({
    required BuildContext context,
    required String residentName,
    required String room,
    required String age,
    required String status,
    required Color statusColor,
    required String medsText,
    required String tasksText,
    required String unreadText,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 40, bottom: 20),
      decoration: const BoxDecoration(
        color: Color(0xFFE0F2F1),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
            ],
          ),
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF80CBC4),
            child: Text(
              _initials(residentName),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            residentName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(
            "Room $room - Age $age",
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          _buildStatusBadge(status, statusColor),
          const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildHeaderStat(medsText, "Meds Today"),
              Container(width: 1, height: 30, color: Colors.black12),
              _buildHeaderStat(tasksText, "Tasks Done"),
              Container(width: 1, height: 30, color: Colors.black12),
              _buildHeaderStat(unreadText, "Unread Msgs"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationCards({
    required String medsText,
    required String tasksText,
    required String messagesText,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _navCard(
          "Medications",
          medsText,
          Icons.medical_services,
          const Color(0xFFE0F2F1),
          const Color(0xFF00BFA5),
          1,
        ),
        _navCard(
          "Care Tasks",
          tasksText,
          Icons.assignment,
          const Color(0xFFFFF3E0),
          const Color(0xFFFFA726),
          2,
        ),
        _navCard(
          "Messages",
          messagesText,
          Icons.chat_bubble,
          const Color(0xFFEDE7F6),
          const Color(0xFF9575CD),
          3,
        ),
      ],
    );
  }

  Widget _navCard(
    String title,
    String subtitle,
    IconData icon,
    Color bg,
    Color iconCol,
    int index,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        if (widget.onTabChange != null) {
          widget.onTabChange!(index);
        }
      },
      child: Container(
        width: MediaQuery.of(context).size.width * 0.28,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: bg,
              radius: 20,
              child: Icon(icon, color: iconCol, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF009688),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildInfoSection({required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildContactInfo(Map<String, dynamic>? familyProfile) {
    final contactName = (familyProfile?['contactName'] ?? '').toString().trim();
    final relationship = (familyProfile?['relationship'] ?? '')
        .toString()
        .trim();
    final contactNumber = (familyProfile?['contactNumber'] ?? '')
        .toString()
        .trim();
    final secondaryContactNumber =
        (familyProfile?['secondaryContactNumber'] ?? '').toString().trim();
    final address = (familyProfile?['address'] ?? '').toString().trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Family Contact",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          _contactRow("Name", contactName.isEmpty ? "-" : contactName),
          _contactRow(
            "Relationship",
            relationship.isEmpty ? "-" : relationship,
          ),
          _contactRow(
            "Primary Contact",
            contactNumber.isEmpty ? "-" : contactNumber,
          ),
          _contactRow(
            "Secondary Contact",
            secondaryContactNumber.isEmpty ? "-" : secondaryContactNumber,
          ),
          _contactRow("Address", address.isEmpty ? "-" : address),
        ],
      ),
    );
  }

  Widget _contactRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildMedicationItem(
    BuildContext context,
    String name,
    String detail,
    String status,
    Color statusCol,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        if (widget.onTabChange != null) {
          widget.onTabChange!(1);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE0F2F1),
              radius: 18,
              child: Icon(Icons.medication, color: statusCol, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusCol.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: statusCol,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskItem(
    BuildContext context,
    String name,
    String subtitle,
    bool isDone,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        if (widget.onTabChange != null) {
          widget.onTabChange!(2);
        }
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(
              isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isDone ? const Color(0xFF00C853) : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDone ? Colors.black : Colors.black54,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMutedTextCard(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
    );
  }
}

class _MedicationEventItem {
  final String name;
  final String dosage;
  final String status;
  final DateTime scheduledAt;
  final String remark;

  const _MedicationEventItem({
    required this.name,
    required this.dosage,
    required this.status,
    required this.scheduledAt,
    required this.remark,
  });
}

class _CareTaskItem {
  final String title;
  final String status;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final String remark;

  const _CareTaskItem({
    required this.title,
    required this.status,
    required this.updatedAt,
    required this.completedAt,
    required this.remark,
  });
}
