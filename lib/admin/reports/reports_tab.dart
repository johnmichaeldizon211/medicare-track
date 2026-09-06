import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/reports_service.dart';

enum _ActivityDateRange { today, thisWeek, custom }

enum _ActivityLayout { desktop, tablet, mobile }

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  Timer? _midnightTimer;

  bool _isLoading = false;
  int _taskCompletion = 0;
  int _medCompliance = 0;
  int _missedMeds = 0;
  int _pendingTasks = 0;
  int _takenMeds = 0;
  int _totalMeds = 0;
  int _doneTasks = 0;
  int _totalTasks = 0;
  List<_CaregiverMetric> _caregiverMetrics = const [];
  List<_AlertItem> _alerts = const [];
  bool _isActivityLoading = false;
  String? _activityError;
  List<_CaregiverOption> _activityCaregivers = const [];
  List<_ActivityRecord> _activityRecords = const [];
  String _selectedCaregiverId = 'all';
  _ActivityDateRange _selectedActivityRange = _ActivityDateRange.today;
  DateTimeRange? _customActivityRange;

  @override
  void initState() {
    super.initState();
    _loadReportData();
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
      _loadReportData();
      _scheduleMidnightRefresh();
    });
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _todayLabel() {
    final now = DateTime.now();
    const weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  Future<void> _loadReportData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    await Future.wait([
      _loadOverview(),
      _loadCaregiverPerformance(),
      _loadAlerts(),
      _loadCaregiverActivityHistory(),
    ]);

    if (!mounted) {
      return;
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadOverview() async {
    try {
      final overview = await ReportsService.instance.getOverview();
      if (!mounted) {
        return;
      }

      final totalTasks = _asInt(overview['totalTaskEvents']);
      final doneTasks = _asInt(overview['doneTaskEvents']);

      setState(() {
        _taskCompletion = _asInt(overview['taskCompletion']).clamp(0, 100);
        _medCompliance = _asInt(overview['medCompliance']).clamp(0, 100);
        _missedMeds = math.max(_asInt(overview['missedMedicationEvents']), 0);
        _takenMeds = math.max(_asInt(overview['takenMedicationEvents']), 0);
        _totalMeds = math.max(_asInt(overview['totalMedicationEvents']), 0);
        _doneTasks = math.max(doneTasks, 0);
        _totalTasks = math.max(totalTasks, 0);
        _pendingTasks = math.max(totalTasks - doneTasks, 0);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _taskCompletion = 0;
        _medCompliance = 0;
        _missedMeds = 0;
        _pendingTasks = 0;
        _takenMeds = 0;
        _totalMeds = 0;
        _doneTasks = 0;
        _totalTasks = 0;
      });
    }
  }

  Future<void> _loadCaregiverPerformance() async {
    try {
      final rawList = await ReportsService.instance.getCaregiverPerformance();
      final metrics = rawList.map((item) {
        final map = Map<String, dynamic>.from(item as Map);

        final totalMeds = math.max(_asInt(map['medicationsTotal']), 0);
        final takenMeds = math.max(_asInt(map['medicationsGiven']), 0);
        final missedMeds = math.max(_asInt(map['medicationsMissed']), 0);
        final totalTasks = math.max(_asInt(map['tasksTotal']), 0);
        final doneTasks = math.max(_asInt(map['tasksDone']), 0);
        final score = _asInt(map['score']).clamp(0, 100);

        return _CaregiverMetric(
          name: (map['caregiverName'] ?? 'Caregiver').toString(),
          assignedResidents: math.max(_asInt(map['assignedResidents']), 0),
          score: score,
          medsGiven: takenMeds,
          medsMissed: missedMeds,
          medsTotal: totalMeds,
          tasksDone: doneTasks,
          tasksTotal: totalTasks,
        );
      }).toList();

      if (!mounted) {
        return;
      }

      setState(() => _caregiverMetrics = metrics);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _caregiverMetrics = const []);
    }
  }

  Future<void> _loadAlerts() async {
    try {
      final rawTimeline = await ReportsService.instance.getShiftTimeline();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));

      final alerts = rawTimeline
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((item) => item['urgent'] == true)
          .where((item) {
            final scheduleRaw = item['scheduledAt']?.toString();
            final schedule = scheduleRaw == null
                ? null
                : DateTime.tryParse(scheduleRaw);
            if (schedule == null) {
              return false;
            }
            return !schedule.isBefore(start) && schedule.isBefore(end);
          })
          .map(
            (item) => _AlertItem(
              title: (item['title'] ?? 'Alert').toString(),
              residentName: (item['residentName'] ?? 'Unknown resident')
                  .toString(),
              status: _toTitleCase((item['status'] ?? '').toString()),
              kind: (item['kind'] ?? '').toString(),
            ),
          )
          .toList();

      if (!mounted) {
        return;
      }
      setState(() => _alerts = alerts);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _alerts = const []);
    }
  }

  Future<void> _loadCaregiverActivityHistory() async {
    if (mounted) {
      setState(() {
        _isActivityLoading = true;
        _activityError = null;
      });
    }

    try {
      final range = _activityRange();
      final data = await ReportsService.instance.getCaregiverActivityHistory(
        caregiverId: _selectedCaregiverId,
        start: range.start,
        end: range.end,
      );

      final caregivers = (data['caregivers'] as List<dynamic>? ?? const [])
          .map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            return _CaregiverOption(
              id: (map['caregiverId'] ?? '').toString(),
              name: (map['caregiverName'] ?? 'Caregiver').toString(),
            );
          })
          .where((caregiver) => caregiver.id.isNotEmpty)
          .toList();

      final records = (data['records'] as List<dynamic>? ?? const []).map((
        item,
      ) {
        final map = Map<String, dynamic>.from(item as Map);
        final completedAt = DateTime.tryParse(
          (map['completedAt'] ?? '').toString(),
        )?.toLocal();

        return _ActivityRecord(
          caregiverName: (map['caregiverName'] ?? 'Caregiver').toString(),
          residentName: (map['residentName'] ?? 'Resident').toString(),
          roomNumber: (map['roomNumber'] ?? '').toString(),
          type: (map['type'] ?? 'Activity').toString(),
          itemTitle: (map['itemTitle'] ?? 'Completed item').toString(),
          itemDetails: map['itemDetails']?.toString(),
          completedAt: completedAt,
        );
      }).toList();

      if (!mounted) {
        return;
      }
      setState(() {
        _activityCaregivers = caregivers;
        _activityRecords = records;
        _isActivityLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _activityError = 'Unable to load caregiver activity history.';
        _activityRecords = const [];
        _isActivityLoading = false;
      });
    }
  }

  DateTimeRange _activityRange() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    switch (_selectedActivityRange) {
      case _ActivityDateRange.today:
        return DateTimeRange(
          start: todayStart,
          end: todayStart.add(const Duration(days: 1)),
        );
      case _ActivityDateRange.thisWeek:
        final weekStart = todayStart.subtract(
          Duration(days: now.weekday - DateTime.monday),
        );
        return DateTimeRange(
          start: weekStart,
          end: weekStart.add(const Duration(days: 7)),
        );
      case _ActivityDateRange.custom:
        final custom = _customActivityRange;
        if (custom == null) {
          return DateTimeRange(
            start: todayStart,
            end: todayStart.add(const Duration(days: 1)),
          );
        }
        return DateTimeRange(
          start: DateTime(
            custom.start.year,
            custom.start.month,
            custom.start.day,
          ),
          end: DateTime(custom.end.year, custom.end.month, custom.end.day + 1),
        );
    }
  }

  Future<void> _changeActivityRange(_ActivityDateRange range) async {
    if (range == _ActivityDateRange.custom) {
      final current = _activityRange();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        initialDateRange: _customActivityRange ?? current,
        useRootNavigator: true,
        builder: (dialogContext, child) {
          final size = MediaQuery.of(dialogContext).size;
          final maxWidth = size.width < 700 ? size.width - 24 : 700.0;
          final maxHeight = size.height - 24;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: child,
            ),
          );
        },
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() {
        _selectedActivityRange = range;
        _customActivityRange = picked;
      });
    } else {
      setState(() => _selectedActivityRange = range);
    }

    await _loadCaregiverActivityHistory();
  }

  static String _toTitleCase(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value
        .toLowerCase()
        .split('_')
        .map((word) {
          if (word.isEmpty) {
            return word;
          }
          return '${word[0].toUpperCase()}${word.substring(1)}';
        })
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadReportData,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final horizontalPadding = width < 360
                ? 14.0
                : width < 700
                ? 20.0
                : 32.0;

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: width < 700 ? 20 : 24,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Reports",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2D0C57),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _todayLabel(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
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
                                  Icons.check_circle,
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
                      const SizedBox(height: 30),
                      const Text(
                        "Today's Overview",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D0C57),
                        ),
                      ),
                      const SizedBox(height: 15),
                      _buildOverviewGrid(),
                      const SizedBox(height: 30),
                      const Text(
                        "Alerts",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D0C57),
                        ),
                      ),
                      const SizedBox(height: 15),
                      if (_alerts.isEmpty)
                        _buildEmptyStateCard(
                          icon: Icons.notifications_none,
                          title: "No alerts today",
                          subtitle: _isLoading
                              ? "Loading alerts..."
                              : "Everything is clear right now.",
                        )
                      else
                        ..._alerts.map(
                          (alert) => _buildAlertCard(
                            alert.title,
                            '${alert.residentName} · ${alert.kind == "medication" ? "Medication" : "Care Task"}',
                            '"${alert.status}"',
                            alert.status,
                            alert.status.toUpperCase() == 'MISSED'
                                ? const Color(0xFFE53935)
                                : const Color(0xFFFFA726),
                          ),
                        ),
                      const SizedBox(height: 30),
                      const Text(
                        "Caregiver Performance",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D0C57),
                        ),
                      ),
                      const SizedBox(height: 15),
                      if (_caregiverMetrics.isEmpty)
                        _buildEmptyStateCard(
                          icon: Icons.people_outline,
                          title: "No caregiver performance yet",
                          subtitle: _isLoading
                              ? "Loading caregivers..."
                              : "No activity recorded for today.",
                        )
                      else
                        ..._caregiverMetrics.map(
                          (item) => _buildCaregiverCard(
                            item.name,
                            '${item.assignedResidents} residents assigned',
                            item.score,
                            '${item.medsGiven}/${item.medsTotal} meds given',
                            '${item.medsMissed}/${item.medsTotal} missed',
                            '${item.tasksDone}/${item.tasksTotal} tasks',
                          ),
                        ),
                      const SizedBox(height: 30),
                      const Text(
                        "Caregiver Activity History",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D0C57),
                        ),
                      ),
                      const SizedBox(height: 15),
                      _buildActivityHistorySection(),
                      if (_isLoading) ...[
                        const SizedBox(height: 10),
                        const Center(child: CircularProgressIndicator()),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOverviewGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 2 : 1;
        return _buildResponsiveWrap(
          columns: columns,
          spacing: 14,
          runSpacing: 14,
          children: [
            _buildOverviewCard(
              Icons.check_circle_outline,
              "$_taskCompletion%",
              "Task Completion",
              _totalTasks == 0
                  ? "0/0 tasks done today"
                  : "$_doneTasks/$_totalTasks tasks done",
              const Color(0xFF00BFA5),
            ),
            _buildOverviewCard(
              Icons.medical_services_outlined,
              "$_medCompliance%",
              "Med Compliance",
              _totalMeds == 0 ? "0/0 given" : "$_takenMeds/$_totalMeds given",
              const Color(0xFF00BFA5),
            ),
            _buildOverviewCard(
              Icons.error_outline,
              "$_missedMeds",
              "Missed Meds",
              _missedMeds == 0 ? "no missed meds today" : "requires attention",
              const Color(0xFFE53935),
            ),
            _buildOverviewCard(
              Icons.access_time,
              "$_pendingTasks",
              "Pending Tasks",
              _pendingTasks == 0
                  ? "no pending tasks today"
                  : "still in progress",
              const Color(0xFFFFA726),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResponsiveWrap({
    required int columns,
    required double spacing,
    required double runSpacing,
    required List<Widget> children,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map(
                (child) => SizedBox(
                  width: itemWidth.isFinite && itemWidth > 0
                      ? itemWidth
                      : width,
                  child: child,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildOverviewCard(
    IconData icon,
    String value,
    String title,
    String subtitle,
    Color themeColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: themeColor, size: 28),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: themeColor,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(
    String title,
    String patient,
    String quote,
    String badgeText,
    Color badgeColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: const Border(
          left: BorderSide(color: Color(0xFFFFA726), width: 4),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  patient,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  quote,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 130),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badgeText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: badgeColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaregiverCard(
    String name,
    String subtitle,
    int score,
    String stat1,
    String stat2,
    String stat3,
  ) {
    final scoreColor = score >= 75
        ? const Color(0xFF00BFA5)
        : score >= 50
        ? const Color(0xFFFFA726)
        : const Color(0xFFE53935);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE0F2F1),
                child: Text(
                  _getInitials(name),
                  style: const TextStyle(
                    color: Color(0xFF00BFA5),
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
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "$score%",
                  style: TextStyle(
                    color: scoreColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 15),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildSmallStat(
                Icons.check_circle,
                const Color(0xFF00C853),
                stat1,
              ),
              _buildSmallStat(Icons.cancel, const Color(0xFFE53935), stat2),
              _buildSmallStat(Icons.assignment_turned_in, Colors.grey, stat3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityHistorySection() {
    final caregiverIds = _activityCaregivers
        .map((caregiver) => caregiver.id)
        .toSet();
    final selectedCaregiverValue =
        caregiverIds.contains(_selectedCaregiverId) ||
            _selectedCaregiverId == 'all'
        ? _selectedCaregiverId
        : 'all';

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final isDesktop = viewportWidth > 1024;
        final isTablet = viewportWidth >= 600 && viewportWidth <= 1024;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildActivityFilters(
              selectedCaregiverValue: selectedCaregiverValue,
              layout: isDesktop
                  ? _ActivityLayout.desktop
                  : isTablet
                  ? _ActivityLayout.tablet
                  : _ActivityLayout.mobile,
            ),
            const SizedBox(height: 15),
            if (_isActivityLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_activityError != null)
              _buildInlineNotice(
                Icons.error_outline,
                'Could not load activity history',
                _activityError!,
              )
            else if (_activityRecords.isEmpty)
              _buildInlineNotice(
                Icons.history,
                'No completed activity found',
                'Completed care tasks and medications will appear here.',
              )
            else if (isDesktop)
              _buildActivityTable()
            else
              _buildActivityCardGrid(columns: isTablet ? 2 : 1),
          ],
        );
      },
    );
  }

  Widget _buildActivityFilters({
    required String selectedCaregiverValue,
    required _ActivityLayout layout,
  }) {
    final caregiverFilter = DropdownButtonFormField<String>(
      initialValue: selectedCaregiverValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Caregiver',
        prefixIcon: const Icon(Icons.person_search_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('All Caregivers')),
        ..._activityCaregivers.map(
          (caregiver) => DropdownMenuItem(
            value: caregiver.id,
            child: Text(caregiver.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) async {
        if (value == null) {
          return;
        }
        setState(() => _selectedCaregiverId = value);
        await _loadCaregiverActivityHistory();
      },
    );

    final dateRangeFilter = _buildDateRangeFilter(
      stacked: layout == _ActivityLayout.mobile,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (layout == _ActivityLayout.mobile)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                caregiverFilter,
                const SizedBox(height: 12),
                dateRangeFilter,
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: caregiverFilter),
                const SizedBox(width: 16),
                Expanded(child: dateRangeFilter),
              ],
            ),
          if (_selectedActivityRange == _ActivityDateRange.custom &&
              _customActivityRange != null) ...[
            const SizedBox(height: 10),
            Text(
              '${_formatDate(_customActivityRange!.start)} - ${_formatDate(_customActivityRange!.end)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateRangeFilter({required bool stacked}) {
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDateRangeButton(_ActivityDateRange.today),
          const SizedBox(height: 8),
          _buildDateRangeButton(_ActivityDateRange.thisWeek),
          const SizedBox(height: 8),
          _buildDateRangeButton(_ActivityDateRange.custom),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_ActivityDateRange>(
        selected: {_selectedActivityRange},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        segments: const [
          ButtonSegment(value: _ActivityDateRange.today, label: Text('Today')),
          ButtonSegment(
            value: _ActivityDateRange.thisWeek,
            label: Text('This Week'),
          ),
          ButtonSegment(
            value: _ActivityDateRange.custom,
            label: Text('Custom'),
          ),
        ],
        onSelectionChanged: (selection) {
          _changeActivityRange(selection.first);
        },
      ),
    );
  }

  Widget _buildDateRangeButton(_ActivityDateRange range) {
    final selected = _selectedActivityRange == range;
    final color = selected ? const Color(0xFF2D0C57) : Colors.grey.shade700;

    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => _changeActivityRange(range),
        icon: Icon(_activityRangeIcon(range), size: 18),
        label: Text(
          _activityRangeLabel(range),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: color,
          backgroundColor: selected
              ? const Color(0xFF2D0C57).withValues(alpha: 0.08)
              : Colors.white,
          side: BorderSide(
            color: selected ? const Color(0xFF2D0C57) : Colors.grey.shade300,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
      ),
    );
  }

  Widget _buildActivityTable() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8F9FA)),
          columnSpacing: 22,
          horizontalMargin: 12,
          dataRowMinHeight: 58,
          dataRowMaxHeight: 72,
          columns: const [
            DataColumn(label: Text('Caregiver Name')),
            DataColumn(label: Text('Resident / Room')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Item Title & Details')),
            DataColumn(label: Text('Completion Timestamp')),
          ],
          rows: _activityRecords.map((record) {
            return DataRow(
              cells: [
                DataCell(_buildTableText(record.caregiverName, width: 130)),
                DataCell(
                  _buildTableText(
                    record.roomNumber.isEmpty
                        ? record.residentName
                        : '${record.residentName} / Room ${record.roomNumber}',
                    width: 160,
                  ),
                ),
                DataCell(_buildTypeBadge(record.type)),
                DataCell(
                  _buildTableText(
                    record.itemDetails == null || record.itemDetails!.isEmpty
                        ? record.itemTitle
                        : '${record.itemTitle} - ${record.itemDetails}',
                    width: 220,
                    maxLines: 2,
                  ),
                ),
                DataCell(
                  _buildTableText(
                    record.completedAt == null
                        ? 'Unknown'
                        : _formatDateTime(record.completedAt!),
                    width: 155,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildActivityCardGrid({required int columns}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final width = constraints.maxWidth;
        final itemWidth = columns == 1
            ? width
            : (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: _activityRecords
              .map(
                (record) => SizedBox(
                  width: itemWidth.isFinite && itemWidth > 0
                      ? itemWidth
                      : width,
                  child: _buildActivityRecordCard(record),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildActivityRecordCard(_ActivityRecord record) {
    final residentText = record.roomNumber.isEmpty
        ? record.residentName
        : '${record.residentName} / Room ${record.roomNumber}';
    final itemText = record.itemDetails == null || record.itemDetails!.isEmpty
        ? record.itemTitle
        : '${record.itemTitle} - ${record.itemDetails}';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildTypeBadge(record.type)),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  record.completedAt == null
                      ? 'Unknown'
                      : _formatDateTime(record.completedAt!),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            itemText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildActivityDetailRow(Icons.person_outline, record.caregiverName),
          const SizedBox(height: 8),
          _buildActivityDetailRow(Icons.meeting_room_outlined, residentText),
        ],
      ),
    );
  }

  Widget _buildActivityDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildTableText(
    String text, {
    required double width,
    int maxLines = 1,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    final isMedication = type.toLowerCase().contains('medication');
    final color = isMedication
        ? const Color(0xFF5E35B1)
        : const Color(0xFF00897B);

    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        type,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _activityRangeLabel(_ActivityDateRange range) {
    switch (range) {
      case _ActivityDateRange.today:
        return 'Today';
      case _ActivityDateRange.thisWeek:
        return 'This Week';
      case _ActivityDateRange.custom:
        return 'Custom';
    }
  }

  IconData _activityRangeIcon(_ActivityDateRange range) {
    switch (range) {
      case _ActivityDateRange.today:
        return Icons.today;
      case _ActivityDateRange.thisWeek:
        return Icons.calendar_view_week;
      case _ActivityDateRange.custom:
        return Icons.date_range;
    }
  }

  Widget _buildInlineNotice(IconData icon, String title, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    return '${value.month}/${value.day}/${value.year}';
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour > 12
        ? value.hour - 12
        : (value.hour == 0 ? 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} $hour:$minute:$second $period';
  }

  Widget _buildSmallStat(IconData icon, Color iconColor, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyStateCard({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String fullName) {
    final names = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (names.isEmpty) {
      return '?';
    }
    if (names.length == 1) {
      return names.first.substring(0, 1).toUpperCase();
    }
    return (names[0][0] + names[1][0]).toUpperCase();
  }
}

class _CaregiverMetric {
  final String name;
  final int assignedResidents;
  final int score;
  final int medsGiven;
  final int medsMissed;
  final int medsTotal;
  final int tasksDone;
  final int tasksTotal;

  const _CaregiverMetric({
    required this.name,
    required this.assignedResidents,
    required this.score,
    required this.medsGiven,
    required this.medsMissed,
    required this.medsTotal,
    required this.tasksDone,
    required this.tasksTotal,
  });
}

class _AlertItem {
  final String title;
  final String residentName;
  final String status;
  final String kind;

  const _AlertItem({
    required this.title,
    required this.residentName,
    required this.status,
    required this.kind,
  });
}

class _CaregiverOption {
  final String id;
  final String name;

  const _CaregiverOption({required this.id, required this.name});
}

class _ActivityRecord {
  final String caregiverName;
  final String residentName;
  final String roomNumber;
  final String type;
  final String itemTitle;
  final String? itemDetails;
  final DateTime? completedAt;

  const _ActivityRecord({
    required this.caregiverName,
    required this.residentName,
    required this.roomNumber,
    required this.type,
    required this.itemTitle,
    required this.itemDetails,
    required this.completedAt,
  });
}
