import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/profile_service.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

enum _HistoryDateRange { today, thisWeek, custom }

class CareTasksScreen extends StatefulWidget {
  const CareTasksScreen({super.key});

  @override
  State<CareTasksScreen> createState() => _CareTasksScreenState();
}

class _CareTasksScreenState extends State<CareTasksScreen> {
  final ProfileService _profileService = ProfileService.instance;
  final ResidentService _residentService = ResidentService.instance;

  bool _isLoading = true;
  String? _errorMessage;
  String _residentName = 'Resident';
  List<_CareTaskItem> _todayTasks = const [];
  List<_CompletionHistoryItem> _completionHistory = const [];
  _HistoryDateRange _selectedHistoryRange = _HistoryDateRange.today;
  DateTimeRange? _customHistoryRange;

  @override
  void initState() {
    super.initState();
    _loadData();
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
          _todayTasks = const [];
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
          type: 'CARE_TASK',
          start: historyRange.start,
          end: historyRange.end,
        );
      } catch (_) {
        rawHistory = const [];
      }
      final residentName = (detail['name'] ?? 'Resident').toString();
      final tasks = mapListFrom(detail['careTasks']);
      final todayTasks = <_CareTaskItem>[];
      final history = mapListFrom(rawHistory).map((map) {
        return _CompletionHistoryItem(
          title: (map['itemTitle'] ?? 'Care task').toString(),
          details: (map['itemDetails'] ?? '').toString(),
          caregiverName: (map['caregiverName'] ?? 'Caregiver').toString(),
          completedAt: _tryParseDateTime(map['completedAt']),
        );
      }).toList();

      for (final task in tasks) {
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

      if (!mounted) {
        return;
      }
      setState(() {
        _residentName = residentName;
        _todayTasks = todayTasks;
        _completionHistory = history;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _todayTasks = const [];
        _completionHistory = const [];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to load care tasks right now.';
        _todayTasks = const [];
        _completionHistory = const [];
        _isLoading = false;
      });
    }
  }

  int _countByStatus(String status) {
    return _todayTasks.where((item) => item.status == status).length;
  }

  List<_CareTaskItem> _tasksForStatus(String status) {
    return _todayTasks.where((item) => item.status == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = _countByStatus('DONE');
    final pendingCount = _countByStatus('PENDING');
    final skippedCount = _countByStatus('SKIPPED');
    final totalCount = _todayTasks.length;
    final progress = totalCount == 0 ? 0.0 : doneCount / totalCount;

    final pendingTasks = _tasksForStatus('PENDING');
    final completedTasks = _tasksForStatus('DONE');
    final skippedTasks = _tasksForStatus('SKIPPED');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          children: [
            const Text(
              "Daily Care Checklist",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              _residentName,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
        centerTitle: true,
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
                    const SizedBox(height: 20),
                    _buildProgressSection(
                      progress: progress,
                      doneCount: doneCount,
                      pendingCount: pendingCount,
                      skippedCount: skippedCount,
                    ),
                    if (_isLoading) ...[
                      const SizedBox(height: 14),
                      const InlineLoading(message: 'Loading care tasks...'),
                    ],
                    if (_errorMessage != null) ...[
                      StatusView.error(
                        title: 'Could not load care tasks',
                        message: _errorMessage!,
                        onAction: _loadData,
                      ),
                    ],
                    const SizedBox(height: 30),
                    const Text(
                      "Pending Tasks",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (pendingTasks.isEmpty)
                      _buildEmptyCard("No pending tasks for today.")
                    else
                      ...pendingTasks.map(
                        (task) => _buildPendingTask(task.title),
                      ),
                    const SizedBox(height: 30),
                    const Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Color(0xFF00C853),
                          size: 24,
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Completed",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00C853),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    if (completedTasks.isEmpty)
                      _buildEmptyCard("No completed tasks yet for today.")
                    else
                      ...completedTasks.map((task) {
                        final timeLabel = task.completedAt != null
                            ? _formatTime(task.completedAt!)
                            : _formatTime(task.updatedAt);
                        final note = task.remark.isNotEmpty
                            ? task.remark
                            : null;
                        return _buildCompletedTask(task.title, timeLabel, note);
                      }),
                    const SizedBox(height: 25),
                    if (skippedTasks.isNotEmpty) ...[
                      const Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Color(0xFFE53935),
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Skipped",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE53935),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      ...skippedTasks.map((task) {
                        final note = task.remark.isNotEmpty
                            ? task.remark
                            : "Task skipped";
                        return _buildSkippedTask(task.title, note);
                      }),
                    ],
                    const SizedBox(height: 30),
                    _buildCompletionHistorySection(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressSection({
    required double progress,
    required int doneCount,
    required int pendingCount,
    required int skippedCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Today's Progress",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              "${(progress * 100).round()}%",
              style: const TextStyle(
                color: Color(0xFF03A9F4),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: const Color(0xFFE1F5FE),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF03A9F4)),
          ),
        ),
        const SizedBox(height: 15),
        Wrap(
          spacing: 15,
          runSpacing: 8,
          children: [
            _StatusDot(
              color: const Color(0xFF00C853),
              label: "$doneCount Done",
            ),
            _StatusDot(color: Colors.orange, label: "$pendingCount Pending"),
            _StatusDot(color: Colors.red, label: "$skippedCount Skipped"),
          ],
        ),
      ],
    );
  }

  Widget _buildPendingTask(String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F7FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              "CT",
              style: TextStyle(
                color: Color(0xFF00ACC1),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Text(
                  "Pending",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.radio_button_unchecked, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildCompletedTask(String title, String time, String? note) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: const Border(
          left: BorderSide(color: Color(0xFF00C853), width: 4),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2F1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: Color(0xFF00C853),
              size: 20,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  "Done at $time",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (note != null && note.isNotEmpty)
                  Text(
                    note,
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: Color(0xFF00C853)),
        ],
      ),
    );
  }

  Widget _buildSkippedTask(String title, String note) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE53935).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.block, color: Color(0xFFE53935)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE53935),
                  ),
                ),
                Text(
                  note,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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

  Widget _buildCompletionHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.history, color: Color(0xFF03A9F4), size: 22),
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
          _buildEmptyCard("No completed care task history yet.")
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
    const accentColor = Color(0xFF03A9F4);

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
              color: const Color(0xFFE1F5FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Color(0xFF03A9F4),
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

class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;
  const _StatusDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
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
