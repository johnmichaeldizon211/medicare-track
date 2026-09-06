import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

enum _HistoryDateRange { today, thisWeek, custom }

class MedicationScreen extends StatefulWidget {
  const MedicationScreen({super.key});

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends State<MedicationScreen> {
  final ProfileService _profileService = ProfileService.instance;
  final ResidentService _residentService = ResidentService.instance;

  bool _isLoading = true;
  String? _errorMessage;
  String _residentName = 'Resident';
  List<_MedicationEventItem> _todayEvents = const [];
  List<_CompletionHistoryItem> _completionHistory = const [];
  _HistoryDateRange _selectedHistoryRange = _HistoryDateRange.today;
  DateTimeRange? _customHistoryRange;
  Timer? _urgencyRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _urgencyRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _urgencyRefreshTimer?.cancel();
    super.dispose();
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

  String _formatDateTime(DateTime value) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[value.month - 1]} ${value.day}, ${value.year}, ${_formatTime(value)}';
  }

  String _formatDate(DateTime value) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }

  DateTimeRange _historyRange() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    switch (_selectedHistoryRange) {
      case _HistoryDateRange.today:
        return DateTimeRange(
          start: todayStart,
          end: todayStart.add(const Duration(days: 1)),
        );
      case _HistoryDateRange.thisWeek:
        final weekStart = todayStart.subtract(
          Duration(days: now.weekday - DateTime.monday),
        );
        return DateTimeRange(
          start: weekStart,
          end: weekStart.add(const Duration(days: 7)),
        );
      case _HistoryDateRange.custom:
        final custom = _customHistoryRange;
        if (custom == null) {
          return DateTimeRange(
            start: todayStart,
            end: todayStart.add(const Duration(days: 1)),
          );
        }
        final start = DateTime(
          custom.start.year,
          custom.start.month,
          custom.start.day,
        );
        final end = DateTime(
          custom.end.year,
          custom.end.month,
          custom.end.day,
        ).add(const Duration(days: 1));
        return DateTimeRange(start: start, end: end);
    }
  }

  Future<void> _selectHistoryRange(_HistoryDateRange range) async {
    if (range == _HistoryDateRange.custom) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: today,
        initialDateRange:
            _customHistoryRange ?? DateTimeRange(start: today, end: today),
      );

      if (picked == null || !mounted) {
        return;
      }

      setState(() {
        _selectedHistoryRange = range;
        _customHistoryRange = picked;
      });
      await _loadData();
      return;
    }

    setState(() => _selectedHistoryRange = range);
    await _loadData();
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'TAKEN':
        return 'Completed';
      case 'MISSED':
        return 'Not Administered';
      case 'SKIPPED':
        return 'Skipped';
      case 'DELAYED':
        return 'Delayed';
      case 'PENDING':
      default:
        return 'Pending';
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'TAKEN':
        return const Color(0xFF00C853);
      case 'MISSED':
        return const Color(0xFFE53935);
      case 'SKIPPED':
        return const Color(0xFFFFA726);
      case 'DELAYED':
        return const Color(0xFFFFA726);
      case 'PENDING':
      default:
        return const Color(0xFF00BFA5);
    }
  }

  Future<String?> _resolveResidentId() async {
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

  Future<void> _loadData() async {
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
          _residentName = 'No linked resident';
          _todayEvents = const [];
          _completionHistory = const [];
          _isLoading = false;
        });
        return;
      }

      final detail = await _residentService.getResidentDetail(residentId);
      final historyRange = _historyRange();
      List<dynamic> rawHistory = const [];
      try {
        rawHistory = await _residentService.getResidentCompletionHistory(
          residentId,
          type: 'MEDICATION',
          start: historyRange.start,
          end: historyRange.end,
        );
      } catch (_) {
        rawHistory = const [];
      }
      final residentName = (detail['name'] ?? 'Resident').toString();
      final medications = mapListFrom(detail['medications']);
      final events = <_MedicationEventItem>[];
      final history = mapListFrom(rawHistory).map((map) {
        return _CompletionHistoryItem(
          title: (map['itemTitle'] ?? 'Medication').toString(),
          details: (map['itemDetails'] ?? '').toString(),
          caregiverName: (map['caregiverName'] ?? 'Caregiver').toString(),
          completedAt: _tryParseDateTime(map['completedAt']),
        );
      }).toList();

      for (final medication in medications) {
        final name = (medication['name'] ?? 'Medication').toString();
        final dosage = (medication['dosage'] ?? '').toString();

        for (final event in mapListFrom(medication['events'])) {
          final scheduledAt = _tryParseDateTime(event['scheduledAt']);
          if (scheduledAt == null || !_isToday(scheduledAt)) {
            continue;
          }

          events.add(
            _MedicationEventItem(
              name: name,
              dosage: dosage,
              scheduledAt: scheduledAt,
              status: (event['status'] ?? 'PENDING').toString().toUpperCase(),
              remark: (event['remark'] ?? '').toString(),
            ),
          );
        }
      }

      events.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      if (!mounted) {
        return;
      }
      setState(() {
        _residentName = residentName;
        _todayEvents = events;
        _completionHistory = history;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _todayEvents = const [];
        _completionHistory = const [];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to load medications right now.';
        _todayEvents = const [];
        _completionHistory = const [];
        _isLoading = false;
      });
    }
  }

  int _countByStatus(String status) {
    return _todayEvents.where((item) => item.status == status).length;
  }

  List<_MedicationEventItem> _eventsFor(List<String> statuses) {
    final set = statuses.map((item) => item.toUpperCase()).toSet();
    return _todayEvents.where((item) => set.contains(item.status)).toList();
  }

  bool _isAlertMedication(_MedicationEventItem item, DateTime now) {
    return item.status == 'PENDING' && now.isAfter(item.scheduledAt);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final takenCount = _countByStatus('TAKEN');
    final alerts = _todayEvents
        .where((item) => _isAlertMedication(item, now))
        .toList();
    final pending = _todayEvents
        .where(
          (item) => item.status == 'PENDING' && !_isAlertMedication(item, now),
        )
        .toList();
    final pendingCount = pending.length;
    final alertCount = alerts.length;
    final delayedCount = _countByStatus('DELAYED');
    final missedCount = _countByStatus('MISSED');
    final skippedCount = _countByStatus('SKIPPED');

    final delayed = _eventsFor(const ['DELAYED']);
    final administered = _eventsFor(const ['TAKEN']);
    final missed = _eventsFor(const ['MISSED']);
    final skipped = _eventsFor(const ['SKIPPED']);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Medication", style: TextStyle(color: Colors.black)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth > 700 ? 28.0 : 20.0;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  children: [
                    Text(
                      _residentName,
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    _buildSummaryRow(
                      takenCount: takenCount,
                      pendingCount: pendingCount,
                      alertCount: alertCount,
                      delayedCount: delayedCount,
                      missedCount: missedCount,
                      skippedCount: skippedCount,
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 14),
                      const InlineLoading(message: 'Loading medications...'),
                    ],
                    if (_errorMessage != null) ...[
                      StatusView.error(
                        title: 'Could not load medications',
                        message: _errorMessage!,
                        onAction: _loadData,
                      ),
                    ],
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      "Attention / Urgent Medications (${alerts.length})",
                      const Color(0xFFE53935),
                    ),
                    _buildMedicationSectionList(
                      alerts,
                      emptyText: "No urgent medication updates yet.",
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      "Pending (${pending.length})",
                      const Color(0xFF00BFA5),
                    ),
                    _buildMedicationSectionList(
                      pending,
                      emptyText: "No upcoming pending meds.",
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      "Delayed (${delayed.length})",
                      const Color(0xFFFFA726),
                    ),
                    _buildMedicationSectionList(
                      delayed,
                      emptyText: "No delayed meds today.",
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      "Completed / Administered (${administered.length})",
                      const Color(0xFF00C853),
                    ),
                    _buildMedicationSectionList(
                      administered,
                      emptyText: "No administered meds yet today.",
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      "Missed / Not Administered (${missed.length})",
                      const Color(0xFFE53935),
                    ),
                    _buildMedicationSectionList(
                      missed,
                      emptyText: "No missed meds today.",
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader(
                      "Skipped (${skipped.length})",
                      const Color(0xFFFFA726),
                    ),
                    _buildMedicationSectionList(
                      skipped,
                      emptyText: "No skipped meds today.",
                    ),
                    const SizedBox(height: 20),
                    _buildCompletionHistorySection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryRow({
    required int takenCount,
    required int pendingCount,
    required int alertCount,
    required int delayedCount,
    required int missedCount,
    required int skippedCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 10.0;
        final minCardWidth = 110.0;
        final columns = (constraints.maxWidth / (minCardWidth + gap)).floor();
        final safeColumns = columns < 2 ? 2 : columns;
        final usableWidth = constraints.maxWidth - (gap * (safeColumns - 1));
        final cardWidth = usableWidth / safeColumns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _statusBox(
              takenCount.toString(),
              "Completed",
              const Color(0xFFE8F5E9),
              const Color(0xFF00C853),
              width: cardWidth,
            ),
            _statusBox(
              pendingCount.toString(),
              "Pending",
              const Color(0xFFE0F2F1),
              const Color(0xFF00BFA5),
              width: cardWidth,
            ),
            _statusBox(
              alertCount.toString(),
              "Alerts",
              const Color(0xFFFFEBEE),
              const Color(0xFFE53935),
              width: cardWidth,
            ),
            _statusBox(
              delayedCount.toString(),
              "Delayed",
              const Color(0xFFFFF3E0),
              const Color(0xFFFFA726),
              width: cardWidth,
            ),
            _statusBox(
              missedCount.toString(),
              "Missed",
              const Color(0xFFFFEBEE),
              const Color(0xFFE53935),
              width: cardWidth,
            ),
            _statusBox(
              skippedCount.toString(),
              "Skipped",
              const Color(0xFFFFF3E0),
              const Color(0xFFFFB74D),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _statusBox(
    String value,
    String label,
    Color bgColor,
    Color textColor, {
    double? width,
  }) {
    return SizedBox(
      width: width ?? 110,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: textColor),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color dotColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 10, color: dotColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationSectionList(
    List<_MedicationEventItem> items, {
    required String emptyText,
  }) {
    if (items.isEmpty) {
      return _buildEmptySectionCard(emptyText);
    }
    return Column(
      children: items.map((item) {
        final statusColor = _statusColor(item.status);
        return _buildMedicationCard(
          item,
          _statusLabel(item.status),
          statusColor,
        );
      }).toList(),
    );
  }

  Widget _buildEmptySectionCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.grey, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationCard(
    _MedicationEventItem item,
    String tag,
    Color tagColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: tagColor.withValues(alpha: 0.1),
            child: Icon(
              Icons.medication_liquid_sharp,
              color: tagColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.dosage,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 14, color: Colors.grey),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        "Scheduled: ${_formatTime(item.scheduledAt)}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (item.remark.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.notes_outlined,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          item.remark.trim(),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tagColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              tag,
              style: TextStyle(
                color: tagColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.history, color: Color(0xFF00897B), size: 22),
            SizedBox(width: 10),
            Text(
              "Completion History",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildHistoryFilterCard(),
        const SizedBox(height: 12),
        if (_completionHistory.isEmpty)
          _buildEmptySectionCard("No completed medication history yet.")
        else
          ..._completionHistory.map(_buildHistoryCard),
      ],
    );
  }

  Widget _buildHistoryFilterCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildHistoryFilterOption(
            range: _HistoryDateRange.today,
            icon: Icons.calendar_today_outlined,
            label: 'Today',
          ),
          const SizedBox(height: 10),
          _buildHistoryFilterOption(
            range: _HistoryDateRange.thisWeek,
            icon: Icons.view_week_outlined,
            label: 'This Week',
          ),
          const SizedBox(height: 10),
          _buildHistoryFilterOption(
            range: _HistoryDateRange.custom,
            icon: Icons.date_range_outlined,
            label: _customHistoryRange == null
                ? 'Custom'
                : '${_formatDate(_customHistoryRange!.start)} - ${_formatDate(_customHistoryRange!.end)}',
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryFilterOption({
    required _HistoryDateRange range,
    required IconData icon,
    required String label,
  }) {
    final selected = _selectedHistoryRange == range;
    const accentColor = Color(0xFF00897B);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _selectHistoryRange(range),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          color: selected ? accentColor.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accentColor : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? accentColor : Colors.grey.shade600),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? accentColor : Colors.black54,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(_CompletionHistoryItem item) {
    final details = item.details.trim();
    final timestamp = item.completedAt == null
        ? 'Completion time unavailable'
        : _formatDateTime(item.completedAt!);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Color(0xFF00897B),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  details.isEmpty ? item.title : '${item.title} - $details',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                _buildHistoryMetaRow(Icons.event, timestamp),
                const SizedBox(height: 6),
                _buildHistoryMetaRow(
                  Icons.person_outline,
                  'Completed by ${item.caregiverName}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryMetaRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _MedicationEventItem {
  final String name;
  final String dosage;
  final DateTime scheduledAt;
  final String status;
  final String remark;

  const _MedicationEventItem({
    required this.name,
    required this.dosage,
    required this.scheduledAt,
    required this.status,
    required this.remark,
  });
}

class _CompletionHistoryItem {
  final String title;
  final String details;
  final String caregiverName;
  final DateTime? completedAt;

  const _CompletionHistoryItem({
    required this.title,
    required this.details,
    required this.caregiverName,
    required this.completedAt,
  });
}
