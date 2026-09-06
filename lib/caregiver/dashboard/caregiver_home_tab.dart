import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/reports_service.dart';
import 'package:medicare_tract/caregiver/widgets/resident_list_card.dart';
import 'package:medicare_tract/core/services/push_notification_service.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/services/time_clock_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/logout_helper.dart';
import 'package:medicare_tract/core/utils/ux_helpers.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class CaregiverHomeTab extends StatefulWidget {
  final VoidCallback onNavigateToMedicalUpdates;
  final VoidCallback onNavigateToAllResidents;
  final VoidCallback onNavigateToShiftSchedule;

  const CaregiverHomeTab({
    super.key,
    required this.onNavigateToMedicalUpdates,
    required this.onNavigateToAllResidents,
    required this.onNavigateToShiftSchedule,
  });

  @override
  State<CaregiverHomeTab> createState() => _CaregiverHomeTabState();
}

class _CaregiverHomeTabState extends State<CaregiverHomeTab> {
  final ResidentService _residentService = ResidentService.instance;
  final ReportsService _reportsService = ReportsService.instance;
  final TimeClockService _timeClockService = TimeClockService.instance;

  Timer? _midnightTimer;
  Timer? _refreshTimer;
  bool _dashboardAlertVisible = false;
  bool _isLoading = true;
  bool _isClockActionLoading = false;
  String? _errorMessage;
  String? _clockErrorMessage;
  Map<String, dynamic>? _activeTimeLog;
  double _todayClockHours = 0;
  List<Map<String, dynamic>> _residents = const [];
  List<_UrgentMedicationItem> _urgentMedications = const [];
  List<_CaregiverTaskAlertItem> _upcomingTaskAlerts = const [];
  final Set<String> _shownReminderAlertKeys = {};
  final Set<String> _shownDueAlertKeys = {};
  int _completedCount = 0;
  int _pendingCount = 0;
  int _alertsCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshDashboard();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _refreshDashboard(showLoading: false);
      }
    });
    _scheduleMidnightRefresh();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshDashboard({bool showLoading = true}) async {
    await Future.wait([
      _loadResidents(showLoading: showLoading),
      _loadTodayStats(),
      _loadClockStatus(),
    ]);
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

  Future<void> _loadResidents({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _residentService.getResidents();
      if (!mounted) {
        return;
      }
      setState(() {
        _residents = data
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Unable to load caregiver dashboard right now.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTodayStats() async {
    try {
      final raw = await _reportsService.getShiftTimeline();
      final items = raw
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));

      int completed = 0;
      int pending = 0;
      int alerts = 0;
      final urgentMedications = <_UrgentMedicationItem>[];
      final taskAlertItems = <_CaregiverTaskAlertItem>[];

      for (final item in items) {
        final scheduledRaw = item['scheduledAt']?.toString();
        final scheduledAt = scheduledRaw == null
            ? null
            : DateTime.tryParse(scheduledRaw)?.toLocal();
        if (scheduledAt == null ||
            scheduledAt.isBefore(start) ||
            !scheduledAt.isBefore(end)) {
          continue;
        }

        final status = (item['status'] ?? '').toString().toUpperCase();
        final rawKind = (item['kind'] ?? '').toString().toLowerCase();
        final taskType = (item['taskType'] ?? '').toString().toLowerCase();
        final isMedication = rawKind == 'medication';
        final isCareTask = rawKind == 'care_task';
        final normalizedType = isMedication
            ? 'medication'
            : taskType.contains('meal')
            ? 'meal'
            : 'care';
        final isPendingStatus =
            status == 'PENDING' || status == 'DELAYED' || status.isEmpty;
        final isAlertMedication =
            isMedication &&
            _isMedicationAlertStatus(status) &&
            !now.isBefore(scheduledAt);

        if (status == 'TAKEN' || status == 'DONE') {
          completed += 1;
        } else if (status == 'PENDING' || status == 'DELAYED') {
          pending += 1;
        }

        if (isAlertMedication) {
          alerts += 1;
          urgentMedications.add(
            _UrgentMedicationItem(
              title: (item['title'] ?? 'Medication').toString(),
              residentName: (item['residentName'] ?? 'Unknown resident')
                  .toString(),
              status: status.isEmpty ? 'PENDING' : status,
              scheduledAt: scheduledAt,
            ),
          );
        }

        if ((isMedication || isCareTask) && isPendingStatus) {
          final alertItem = _CaregiverTaskAlertItem(
            id: (item['id'] ?? '').toString(),
            title: (item['title'] ?? 'Care task').toString(),
            residentName: (item['residentName'] ?? 'Unknown resident')
                .toString(),
            type: normalizedType,
            status: status.isEmpty ? 'PENDING' : status,
            scheduledAt: scheduledAt,
          );
          taskAlertItems.add(alertItem);
          if (!now.isBefore(scheduledAt)) {
            alerts += isMedication ? 0 : 1;
          }
        }
      }

      urgentMedications.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      taskAlertItems.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      if (!mounted) {
        return;
      }
      setState(() {
        _completedCount = completed;
        _pendingCount = pending;
        _alertsCount = alerts;
        _urgentMedications = urgentMedications;
        _upcomingTaskAlerts = taskAlertItems;
      });
      _syncTaskReminderNotifications(taskAlertItems);
      _showDashboardTaskAlerts(taskAlertItems);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _completedCount = 0;
        _pendingCount = 0;
        _alertsCount = 0;
        _urgentMedications = const [];
        _upcomingTaskAlerts = const [];
      });
    }
  }

  void _syncTaskReminderNotifications(List<_CaregiverTaskAlertItem> tasks) {
    unawaited(
      PushNotificationService.instance
          .syncCaregiverTaskReminders(
            tasks.map((task) {
              return TaskReminderScheduleItem(
                id: task.id,
                title: task.title,
                residentName: task.residentName,
                type: task.type,
                status: task.status,
                scheduledAt: task.scheduledAt,
              );
            }).toList(),
          )
          .catchError((_) {}),
    );
  }

  void _showDashboardTaskAlerts(List<_CaregiverTaskAlertItem> tasks) {
    final now = DateTime.now();
    final dueTask = _firstMatchingTask(
      tasks,
      (task) =>
          task.isPending &&
          !now.isBefore(task.scheduledAt) &&
          now.difference(task.scheduledAt) <= const Duration(minutes: 120),
    );

    if (dueTask != null && _shownDueAlertKeys.add(dueTask.alertKey('due'))) {
      _queueDashboardTaskDialog(dueTask, isDueNow: true);
      return;
    }

    final reminderTask = _firstMatchingTask(
      tasks,
      (task) =>
          task.isPending &&
          now.isBefore(task.scheduledAt) &&
          task.scheduledAt.difference(now) <= const Duration(minutes: 5),
    );
    if (reminderTask != null &&
        _shownReminderAlertKeys.add(reminderTask.alertKey('reminder'))) {
      _queueDashboardTaskDialog(reminderTask, isDueNow: false);
    }
  }

  _CaregiverTaskAlertItem? _firstMatchingTask(
    List<_CaregiverTaskAlertItem> tasks,
    bool Function(_CaregiverTaskAlertItem task) test,
  ) {
    for (final task in tasks) {
      if (test(task)) {
        return task;
      }
    }
    return null;
  }

  void _queueDashboardTaskDialog(
    _CaregiverTaskAlertItem task, {
    required bool isDueNow,
  }) {
    if (_dashboardAlertVisible || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _dashboardAlertVisible) {
        return;
      }
      _dashboardAlertVisible = true;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(isDueNow ? 'Task due now' : 'Task in 5 minutes'),
          content: Text(
            '${task.typeLabel}: ${task.title}\n'
            '${task.residentName}\n'
            'Scheduled at ${_formatClockTime(task.scheduledAt)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Dismiss'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFA726),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                widget.onNavigateToShiftSchedule();
              },
              child: const Text('View Schedule'),
            ),
          ],
        ),
      );
      _dashboardAlertVisible = false;
    });
  }

  Future<void> _loadClockStatus() async {
    try {
      final data = await _timeClockService.getMyStatus();
      if (!mounted) {
        return;
      }
      setState(() {
        final activeLog = data['activeLog'];
        _activeTimeLog = activeLog is Map
            ? Map<String, dynamic>.from(activeLog)
            : null;
        _todayClockHours = _safeDouble(data['todayTotalHours']);
        _clockErrorMessage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _activeTimeLog = null;
        _todayClockHours = 0;
        _clockErrorMessage = 'Unable to load time clock.';
      });
    }
  }

  Future<void> _handleTimeIn() async {
    setState(() => _isClockActionLoading = true);

    try {
      final data = await _timeClockService.timeIn();
      final activeLog = data['activeLog'];
      if (!mounted) {
        return;
      }
      setState(() {
        _activeTimeLog = activeLog is Map
            ? Map<String, dynamic>.from(activeLog)
            : _activeTimeLog;
        _clockErrorMessage = null;
      });
      await _loadClockStatus();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Time in recorded.')));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to record time in.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isClockActionLoading = false);
      }
    }
  }

  Future<void> _handleTimeOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Time out?'),
        content: const Text(
          'This will close your shift and log out your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Time Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isClockActionLoading = true);

    try {
      await _timeClockService.timeOut();
      if (!mounted) {
        return;
      }
      await performLogout(context);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to record time out.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isClockActionLoading = false);
      }
    }
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

  List<String> _conditionLabels(Map<String, dynamic> resident) {
    final raw = resident['conditions'] as List<dynamic>? ?? const [];
    final list = raw
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
    if (list.isEmpty) {
      return const ['No conditions'];
    }
    return list;
  }

  double _safeDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _parseDateTime(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text)?.toLocal();
  }

  String _formatClockTime(dynamic value) {
    final dateTime = _parseDateTime(value);
    if (dateTime == null) {
      return '--:--';
    }

    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final suffix = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _formatHours(double hours) {
    if (hours <= 0) {
      return '0h';
    }
    final totalMinutes = (hours * 60).round();
    final wholeHours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (wholeHours == 0) {
      return '${minutes}m';
    }
    if (minutes == 0) {
      return '${wholeHours}h';
    }
    return '${wholeHours}h ${minutes}m';
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour > 12
        ? value.hour - 12
        : (value.hour == 0 ? 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} $hour:$minute $period';
  }

  bool _isMedicationAlertStatus(String status) {
    return status == 'PENDING' ||
        status == 'DELAYED' ||
        status == 'MISSED' ||
        status.isEmpty;
  }

  String _medicationAlertStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'MISSED':
        return 'Not administered';
      case 'DELAYED':
        return 'Delayed';
      default:
        return 'Overdue';
    }
  }

  @override
  Widget build(BuildContext context) {
    final residentsCount = _residents.length;
    final previewResidents = _residents.take(2).toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshDashboard,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          children: [
            _buildHeader(),
            const SizedBox(height: 25),
            _buildStatsGrid(
              residentsCount: residentsCount,
              completedCount: _completedCount,
              pendingCount: _pendingCount,
              alertsCount: _alertsCount,
            ),
            const SizedBox(height: 20),
            if (_upcomingTaskAlerts.isNotEmpty) ...[
              GestureDetector(
                onTap: widget.onNavigateToShiftSchedule,
                child: _buildNextTaskReminderCard(),
              ),
              const SizedBox(height: 20),
            ],
            _buildTimeClockCard(),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: widget.onNavigateToMedicalUpdates,
              child: _buildMedicalUpdatesBanner(),
            ),
            const SizedBox(height: 25),
            const Text(
              "Urgent Medications",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D0C57),
              ),
            ),
            const SizedBox(height: 15),
            if (_urgentMedications.isEmpty)
              _buildEmptyUrgentCard()
            else
              ..._urgentMedications.map(_buildUrgentMedicationCard),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Residents",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D0C57),
                  ),
                ),
                TextButton(
                  onPressed: widget.onNavigateToAllResidents,
                  child: const Text(
                    "See all",
                    style: TextStyle(color: Color(0xFF00BFA5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_isLoading)
              const InlineLoading(message: 'Loading residents...')
            else if (_errorMessage != null)
              StatusView.error(
                title: 'Could not load dashboard',
                message: _errorMessage!,
                onAction: _refreshDashboard,
              )
            else if (previewResidents.isEmpty)
              const StatusView.empty(
                icon: Icons.people_outline,
                title: 'No residents yet',
                message:
                    'Residents will appear here once accounts are created.',
              )
            else
              ...previewResidents.map((resident) {
                final name = (resident['name'] ?? '').toString();
                final residentId = (resident['id'] ?? '').toString();
                final room = (resident['room'] ?? '').toString();
                final age = (resident['age'] ?? '').toString();
                final medicationCount =
                    (resident['medicationCount'] as num?)?.toInt() ?? 0;
                final careTaskCount =
                    (resident['careTaskCount'] as num?)?.toInt() ?? 0;
                final overallStatus = _statusLabel(
                  (resident['overallStatus'] ?? '').toString(),
                );

                return ResidentListCard(
                  residentId: residentId,
                  name: name,
                  room: room,
                  age: age,
                  conditions: _conditionLabels(resident),
                  medStatus: "$medicationCount meds",
                  taskStatus: "$careTaskCount tasks",
                  overallStatus: overallStatus,
                  onViewDetails: () {},
                );
              }),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greetingForNow(),
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const Text(
              "Caregiver",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFA726),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            "Caregiver",
            style: TextStyle(
              color: Color(0xFFFFA726),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid({
    required int residentsCount,
    required int completedCount,
    required int pendingCount,
    required int alertsCount,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                residentsCount.toString(),
                "Residents",
                Icons.people_alt,
                const Color(0xFFE0F7FA),
                const Color(0xFF00ACC1),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildStatCard(
                completedCount.toString(),
                "Completed",
                Icons.check_circle,
                const Color(0xFFE8F5E9),
                const Color(0xFF00C853),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                pendingCount.toString(),
                "Pending Tasks",
                Icons.access_time_filled,
                const Color(0xFFFFF3E0),
                const Color(0xFFFFA726),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildStatCard(
                alertsCount.toString(),
                "Alerts",
                Icons.error,
                const Color(0xFFFFEBEE),
                const Color(0xFFE53935),
              ),
            ),
          ],
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
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 15),
          Text(
            count,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTimeClockCard() {
    final isTimedIn = _activeTimeLog != null;
    final accentColor = isTimedIn
        ? const Color(0xFF00C853)
        : const Color(0xFFFFA726);
    final statusText = isTimedIn ? 'Timed In' : 'Not Timed In';
    final timeInText = isTimedIn
        ? _formatClockTime(_activeTimeLog?['timeIn'])
        : 'Ready to start';
    final hoursText = _formatHours(_todayClockHours);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.punch_clock, color: accentColor, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shift Time Clock',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF2D0C57),
                      ),
                    ),
                    Text(
                      'Caregiver attendance',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildClockDetail('Time In', timeInText, Icons.login),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildClockDetail('Hours Today', hoursText, Icons.timer),
              ),
            ],
          ),
          if (_clockErrorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _clockErrorMessage!,
              style: const TextStyle(color: Color(0xFFE53935), fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isClockActionLoading
                  ? null
                  : isTimedIn
                  ? _handleTimeOut
                  : _handleTimeIn,
              icon: _isClockActionLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(isTimedIn ? Icons.logout : Icons.login),
              label: Text(isTimedIn ? 'Time Out' : 'Time In'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isTimedIn
                    ? const Color(0xFFE53935)
                    : accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClockDetail(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2D0C57),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalUpdatesBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF00C853), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Color(0xFF00C853),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.info_outline,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 15),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Medical Updates",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                "Tap to View",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNextTaskReminderCard() {
    final now = DateTime.now();
    final due = _firstMatchingTask(
      _upcomingTaskAlerts,
      (task) => task.isPending && !now.isBefore(task.scheduledAt),
    );
    final upcoming = _firstMatchingTask(
      _upcomingTaskAlerts,
      (task) => task.isPending && now.isBefore(task.scheduledAt),
    );
    final task = due ?? upcoming ?? _upcomingTaskAlerts.first;
    final isDue = due != null;
    final accentColor = isDue
        ? const Color(0xFFE53935)
        : const Color(0xFFFFA726);
    final statusText = isDue
        ? 'Due now'
        : 'Next at ${_formatClockTime(task.scheduledAt)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDue ? const Color(0xFFFFEBEE) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.notifications_active, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF2D0C57),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '${task.typeLabel} - ${task.residentName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: accentColor),
        ],
      ),
    );
  }

  Widget _buildEmptyUrgentCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: const Text(
        "No urgent medication updates yet.",
        style: TextStyle(color: Colors.grey, fontSize: 14),
      ),
    );
  }

  Widget _buildUrgentMedicationCard(_UrgentMedicationItem medication) {
    final statusLabel = _medicationAlertStatusLabel(medication.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: const Color(0xFFE53935).withValues(alpha: 0.3),
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.medical_services_outlined,
              color: Color(0xFFE53935),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medication.title,
                  style: const TextStyle(
                    color: Color(0xFF2D0C57),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  medication.residentName,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '$statusLabel since ${_formatDateTime(medication.scheduledAt)}',
                  style: const TextStyle(
                    color: Color(0xFFE53935),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              statusLabel,
              style: const TextStyle(
                color: Color(0xFFE53935),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgentMedicationItem {
  final String title;
  final String residentName;
  final String status;
  final DateTime scheduledAt;

  const _UrgentMedicationItem({
    required this.title,
    required this.residentName,
    required this.status,
    required this.scheduledAt,
  });
}

class _CaregiverTaskAlertItem {
  final String id;
  final String title;
  final String residentName;
  final String type;
  final String status;
  final DateTime scheduledAt;

  const _CaregiverTaskAlertItem({
    required this.id,
    required this.title,
    required this.residentName,
    required this.type,
    required this.status,
    required this.scheduledAt,
  });

  bool get isPending {
    final normalized = status.toUpperCase();
    return normalized == 'PENDING' || normalized == 'DELAYED';
  }

  String get typeLabel {
    switch (type) {
      case 'medication':
        return 'Medication';
      case 'meal':
        return 'Meal task';
      default:
        return 'Care task';
    }
  }

  String alertKey(String kind) {
    return '$kind:$id:${scheduledAt.toUtc().toIso8601String()}';
  }
}
