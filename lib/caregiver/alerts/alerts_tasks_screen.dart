import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medicare_tract/caregiver/widgets/medication_update_sheet.dart';
import 'package:medicare_tract/core/services/reports_service.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

// --- A mini-database for the Global Shift Timeline ---
class ShiftTask {
  final String id;
  final DateTime scheduledAt;
  final DateTime urgentExpiresAt;
  final String time;
  final String title;
  final String patientName;
  final String type; // 'medication', 'care', or 'meal'
  bool isUrgent;
  String status; // 'pending', 'missed', 'done'

  ShiftTask({
    required this.id,
    required this.scheduledAt,
    required this.urgentExpiresAt,
    required this.time,
    required this.title,
    required this.patientName,
    required this.type,
    this.isUrgent = false,
    this.status = 'pending',
  });
}

class AlertsTasksScreen extends StatefulWidget {
  const AlertsTasksScreen({super.key});

  @override
  State<AlertsTasksScreen> createState() => _AlertsTasksScreenState();
}

class _AlertsTasksScreenState extends State<AlertsTasksScreen> {
  int _selectedTabIndex = 0; // 0 = All Schedule, 1 = Urgent Alerts

  final ReportsService _reportsService = ReportsService.instance;
  final ResidentService _residentService = ResidentService.instance;
  Timer? _refreshTimer;
  bool _isLoading = true;
  String? _errorMessage;
  String? _updatingTaskId;
  List<ShiftTask> _allTasks = const [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _updatingTaskId == null) {
        _loadTasks(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _toTimeLabel(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  DateTime? _parseApiDateTime(Object? value) {
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

  String _toShiftStatus(String rawStatus) {
    final status = rawStatus.toUpperCase();
    if (status == 'TAKEN' || status == 'DONE' || status == 'COMPLETED') {
      return 'done';
    }
    if (status == 'DELAYED') {
      return 'delayed';
    }
    if (status == 'MISSED') {
      return 'missed';
    }
    if (status == 'SKIPPED') {
      return 'skipped';
    }
    return 'pending';
  }

  bool _isActiveUrgent(ShiftTask task) {
    if (task.status == 'done') {
      return false;
    }

    final now = DateTime.now();
    final isDueToday =
        _isToday(task.scheduledAt) && !now.isBefore(task.scheduledAt);
    if (!isDueToday) {
      return false;
    }

    final needsAttention =
        task.status == 'pending' ||
        task.status == 'delayed' ||
        task.status == 'missed' ||
        task.status == 'skipped';
    return needsAttention || task.isUrgent;
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'TAKEN':
      case 'DONE':
      case 'COMPLETED':
        return 'done';
      case 'DELAYED':
        return 'delayed';
      case 'MISSED':
        return 'not administered';
      case 'SKIPPED':
        return 'not completed';
      default:
        return 'pending';
    }
  }

  Future<void> _openTaskStatusSheet(ShiftTask task) async {
    if (_updatingTaskId == task.id) {
      return;
    }

    if (task.type == 'medication') {
      final result = await MedicationUpdateSheet.show(
        context,
        task.title,
        '${task.patientName} - Scheduled: ${task.time}',
      );
      if (result == null) {
        return;
      }
      await _saveTaskStatus(task, result.status, remark: result.remark);
      return;
    }

    final result = await _CareTaskUpdateSheet.show(
      context,
      title: task.title,
      details: '${task.patientName} - Scheduled: ${task.time}',
    );
    if (result == null) {
      return;
    }
    await _saveTaskStatus(task, result.status, remark: result.remark);
  }

  Future<void> _saveTaskStatus(
    ShiftTask task,
    String status, {
    String? remark,
  }) async {
    setState(() => _updatingTaskId = task.id);
    try {
      if (task.type == 'medication') {
        await _residentService.updateMedicationEventStatus(
          eventId: task.id,
          status: status,
          remark: remark,
        );
      } else {
        await _residentService.updateCareTaskStatus(
          careTaskId: task.id,
          status: status,
          remark: remark,
        );
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${task.title} marked as ${_statusLabel(status)}.'),
          duration: const Duration(seconds: 1),
        ),
      );
      await _loadTasks();
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to update task.')));
    } finally {
      if (mounted) {
        setState(() => _updatingTaskId = null);
      }
    }
  }

  Future<void> _loadTasks({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final raw = await _reportsService.getShiftTimeline();
      final tasks = raw
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map((item) {
            final scheduledAt = _parseApiDateTime(item['scheduledAt']);
            if (scheduledAt == null || !_isToday(scheduledAt)) {
              return null;
            }
            final urgentExpiresAt =
                _parseApiDateTime(item['urgentExpiresAt']) ??
                scheduledAt.add(const Duration(hours: 2));

            final type = (item['kind'] ?? '').toString().toLowerCase();
            final taskType = (item['taskType'] ?? '').toString().toLowerCase();
            String normalizedType = 'care';
            if (type == 'medication') {
              normalizedType = 'medication';
            } else if (type == 'care_task' && taskType.contains('meal')) {
              normalizedType = 'meal';
            } else if (type == 'care_task') {
              normalizedType = 'care';
            }

            return ShiftTask(
              id: (item['id'] ?? '').toString(),
              scheduledAt: scheduledAt,
              urgentExpiresAt: urgentExpiresAt,
              time: _toTimeLabel(scheduledAt),
              title: (item['title'] ?? 'Untitled task').toString(),
              patientName: (item['residentName'] ?? 'Unknown resident')
                  .toString(),
              type: normalizedType,
              isUrgent: item['urgent'] == true,
              status: _toShiftStatus((item['status'] ?? '').toString()),
            );
          })
          .whereType<ShiftTask>()
          .toList();

      if (!mounted) {
        return;
      }
      setState(() {
        _allTasks = tasks;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _allTasks = const [];
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _allTasks = const [];
        _errorMessage = 'Unable to load shift timeline right now.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayTasks = _allTasks.where((task) {
      if (_selectedTabIndex == 1) {
        return _isActiveUrgent(task);
      }
      return true;
    }).toList();

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          final horizontalPadding = constraints.maxWidth < 420 ? 16.0 : 24.0;
          final contentWidth = isDesktop ? 860.0 : constraints.maxWidth;
          final Widget timelineBody;

          if (_isLoading) {
            timelineBody = const InlineLoading(
              message: 'Loading shift timeline...',
            );
          } else if (_errorMessage != null) {
            timelineBody = StatusView.error(
              title: 'Could not load timeline',
              message: _errorMessage!,
              onAction: _loadTasks,
            );
          } else if (displayTasks.isEmpty) {
            timelineBody = const StatusView.empty(
              icon: Icons.timeline_outlined,
              title: 'No timeline activity',
              message: 'There are no care updates scheduled for today.',
            );
          } else {
            timelineBody = ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              itemCount: displayTasks.length,
              itemBuilder: (context, index) {
                return _buildTimelineCard(displayTasks[index]);
              },
            );
          }

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      20,
                      horizontalPadding,
                      10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Shift Schedule",
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFFA726),
                                ),
                              ),
                              Text(
                                "Today's Timeline",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.calendar_month,
                            color: Color(0xFFFFA726),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 10,
                    ),
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildToggleButton("All Schedule", 0),
                          ),
                          Expanded(
                            child: _buildToggleButton("Urgent Alerts", 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _loadTasks,
                      child: timelineBody,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  // --- HELPER WIDGETS ---

  Widget _buildToggleButton(String title, int index) {
    bool isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? (index == 1
                      ? const Color(0xFFE53935)
                      : const Color(0xFF00BFA5))
                : Colors.grey.shade600,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineCard(ShiftTask task) {
    final isUrgent = _isActiveUrgent(task);
    final isMedication = task.type == 'medication';
    final isMissed = task.status == 'missed';
    final isDelayed = task.status == 'delayed';
    final isSkipped = task.status == 'skipped';
    final isNotCompleted = !isMedication && isSkipped;
    final isDone = task.status == 'done';
    final isMeal = task.type == 'meal';
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isCompact = viewportWidth < 380;
    final timeColumnWidth = isCompact ? 64.0 : 82.0;
    final cardPadding = isCompact ? 12.0 : 15.0;
    final timelineGap = isCompact ? 10.0 : 15.0;
    final iconPadding = isCompact ? 8.0 : 10.0;
    final iconSize = isCompact ? 22.0 : 24.0;
    final titleFontSize = isCompact ? 14.0 : 15.0;
    final residentFontSize = isCompact ? 12.0 : 13.0;

    Color themeColor;
    if (isDone) {
      themeColor = const Color(0xFF00C853);
    } else if (isUrgent || isMissed || isNotCompleted) {
      themeColor = const Color(0xFFE53935);
    } else if (isDelayed || isSkipped) {
      themeColor = const Color(0xFFFFA726);
    } else if (isMedication) {
      themeColor = const Color(0xFF00BFA5);
    } else if (isMeal) {
      themeColor = const Color(0xFFFFA726);
    } else {
      themeColor = const Color(0xFFFFCA28);
    }

    final bgColor = isUrgent || isMissed || isNotCompleted
        ? const Color(0xFFFFEBEE)
        : isDelayed || isSkipped
        ? const Color(0xFFFFF8E1)
        : Colors.white;

    IconData taskIcon = Icons.assignment_outlined;
    if (isMedication) taskIcon = Icons.medical_services_outlined;
    if (isMeal) taskIcon = Icons.restaurant_outlined;
    if (task.type == 'care') taskIcon = Icons.shower_outlined;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: timeColumnWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                task.time,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: themeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: themeColor.withValues(alpha: 0.4),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              Container(width: 2, height: 80, color: Colors.grey.shade200),
            ],
          ),
          SizedBox(width: timelineGap),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: isDone || _updatingTaskId == task.id
                    ? null
                    : () => _openTaskStatusSheet(task),
                child: Container(
                  padding: EdgeInsets.all(cardPadding),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isMissed || isUrgent || isNotCompleted
                          ? const Color(0xFFE53935).withValues(alpha: 0.3)
                          : isDelayed || isSkipped
                          ? const Color(0xFFFFA726).withValues(alpha: 0.28)
                          : Colors.grey.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(iconPadding),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          taskIcon,
                          color: themeColor,
                          size: iconSize,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: titleFontSize,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    task.patientName,
                                    softWrap: true,
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: residentFontSize,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (isUrgent ||
                                isMissed ||
                                isDelayed ||
                                isSkipped) ...[
                              const SizedBox(height: 6),
                              Text(
                                _timelineStatusText(task, isUrgent: isUrgent),
                                style: TextStyle(
                                  color: isUrgent || isMissed || isNotCompleted
                                      ? const Color(0xFFE53935)
                                      : const Color(0xFFFFA726),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(width: isCompact ? 6 : 10),
                      IconButton(
                        constraints: BoxConstraints.tightFor(
                          width: isCompact ? 40 : 48,
                          height: isCompact ? 40 : 48,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: isDone || _updatingTaskId == task.id
                            ? null
                            : () => _markDone(task),
                        icon: _updatingTaskId == task.id
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                isDone
                                    ? Icons.check_circle
                                    : Icons.check_circle_outline,
                                color: isDone
                                    ? const Color(0xFF00C853)
                                    : Colors.grey.shade400,
                                size: 28,
                              ),
                        tooltip: isDone ? 'Completed' : 'Quick mark completed',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timelineStatusText(ShiftTask task, {required bool isUrgent}) {
    if (isUrgent) {
      return 'URGENT: Action needed';
    }
    switch (task.status) {
      case 'delayed':
        return 'Delayed';
      case 'skipped':
        return task.type == 'medication' ? 'Skipped' : 'Not completed';
      case 'missed':
        return task.type == 'medication' ? 'Not administered' : 'Not completed';
      default:
        return '';
    }
  }

  Future<void> _markDone(ShiftTask task) async {
    await _saveTaskStatus(task, task.type == 'medication' ? 'TAKEN' : 'DONE');
  }
}

class _CareTaskUpdateResult {
  final String status;
  final String? remark;

  const _CareTaskUpdateResult({required this.status, this.remark});
}

class _CareTaskUpdateSheet extends StatefulWidget {
  final String title;
  final String details;

  const _CareTaskUpdateSheet({required this.title, required this.details});

  static Future<_CareTaskUpdateResult?> show(
    BuildContext context, {
    required String title,
    required String details,
  }) {
    return showModalBottomSheet<_CareTaskUpdateResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _CareTaskUpdateSheet(title: title, details: details),
    );
  }

  @override
  State<_CareTaskUpdateSheet> createState() => _CareTaskUpdateSheetState();
}

class _CareTaskUpdateSheetState extends State<_CareTaskUpdateSheet> {
  final TextEditingController _remarkController = TextEditingController();

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }

  void _complete(String status) {
    final remark = _remarkController.text.trim();
    Navigator.pop(
      context,
      _CareTaskUpdateResult(
        status: status,
        remark: remark.isEmpty ? null : remark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(25),
          topRight: Radius.circular(25),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.assignment_outlined,
                      color: Color(0xFFFFA726),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.details,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              const Text(
                'Update Care Task Status',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 15),
              const Text(
                'Caregiver Remarks (optional)',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _remarkController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Example: resident declined, task postponed',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8F9FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00BFA5)),
                  ),
                ),
              ),
              const SizedBox(height: 25),
              _buildActionButton(
                icon: Icons.check_circle,
                title: 'Mark Done',
                subtitle: 'Task was completed successfully',
                color: const Color(0xFF00C853),
                onTap: () => _complete('DONE'),
              ),
              _buildActionButton(
                icon: Icons.cancel,
                title: 'Not Completed',
                subtitle: 'Task was not completed',
                color: const Color(0xFFE53935),
                onTap: () => _complete('SKIPPED'),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                    softWrap: true,
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
