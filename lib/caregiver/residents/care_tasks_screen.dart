import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class CareTasksScreen extends StatefulWidget {
  final String residentId;
  final String residentName;

  const CareTasksScreen({
    super.key,
    required this.residentId,
    required this.residentName,
  });

  @override
  State<CareTasksScreen> createState() => _CareTasksScreenState();
}

class _CareTasksScreenState extends State<CareTasksScreen> {
  final ResidentService _residentService = ResidentService.instance;
  final Map<String, TextEditingController> _controllers = {};

  Timer? _refreshTimer;
  bool _isLoading = true;
  String? _errorMessage;
  String? _updatingTaskId;
  List<_CareTaskItem> _tasks = [];

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
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTasks({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final rawTasks = await _residentService.getResidentCareTasks(
        widget.residentId,
      );
      final tasks = rawTasks.map((raw) {
        final task = Map<String, dynamic>.from(raw as Map);
        final eventRaw = task['event'];
        final event = eventRaw == null
            ? null
            : Map<String, dynamic>.from(eventRaw as Map);
        final status = (event?['status'] ?? 'PENDING').toString();
        final updatedAt = DateTime.tryParse(
          (event?['updatedAt'] ?? '').toString(),
        )?.toLocal();
        final timeCompleted = DateTime.tryParse(
          (event?['timeCompleted'] ?? '').toString(),
        )?.toLocal();

        return _CareTaskItem(
          id: (task['id'] ?? '').toString(),
          title: (task['title'] ?? 'Care task').toString(),
          type: (task['type'] ?? '').toString(),
          scheduledTime: (task['scheduledTime'] ?? '').toString(),
          status: status,
          remark: event?['remark']?.toString(),
          timeCompleted: timeCompleted,
          updatedAt: updatedAt,
        );
      }).toList();

      for (final task in tasks) {
        _controllers.putIfAbsent(
          task.id,
          () => TextEditingController(text: task.remark ?? ''),
        );
      }
      final taskIds = tasks.map((task) => task.id).toSet();
      final removedIds = _controllers.keys
          .where((id) => !taskIds.contains(id))
          .toList();
      for (final id in removedIds) {
        _controllers.remove(id)?.dispose();
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _tasks = tasks;
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
        _errorMessage = 'Unable to load care tasks right now.';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateTaskStatus(_CareTaskItem task, String newStatus) async {
    final remark = _controllers[task.id]?.text.trim();
    setState(() => _updatingTaskId = task.id);

    try {
      await _residentService.updateCareTaskStatus(
        careTaskId: task.id,
        status: newStatus,
        remark: remark == null || remark.isEmpty ? null : remark,
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${task.title} marked as ${_statusLabel(newStatus).toLowerCase()}.',
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update care task.')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingTaskId = null);
      }
    }
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'DONE':
        return 'Done';
      case 'SKIPPED':
        return 'Not Completed';
      case 'PENDING':
      default:
        return 'Pending';
    }
  }

  String _formatTime(DateTime? value, String fallback) {
    if (value == null) {
      return fallback;
    }

    final hour = value.hour > 12
        ? value.hour - 12
        : (value.hour == 0 ? 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final doneTasks = _tasks
        .where((task) => task.status.toUpperCase() == 'DONE')
        .length;
    final pendingTasks = _tasks
        .where((task) => task.status.toUpperCase() == 'PENDING')
        .length;
    final skippedTasks = _tasks
        .where((task) => task.status.toUpperCase() == 'SKIPPED')
        .length;
    final totalTasks = _tasks.length;
    final progress = totalTasks == 0
        ? 0.0
        : (doneTasks + skippedTasks) / totalTasks;
    final progressPercent = (progress * 100).toInt();

    final pendingList = _tasks
        .where((task) => task.status.toUpperCase() == 'PENDING')
        .toList();
    final completedList = _tasks
        .where((task) => task.status.toUpperCase() == 'DONE')
        .toList();
    final notCompletedList = _tasks
        .where((task) => task.status.toUpperCase() == 'SKIPPED')
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text(
              "Daily Care Checklist",
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.residentName,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadTasks,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (_isLoading)
              const InlineLoading(message: 'Loading care tasks...')
            else if (_errorMessage != null)
              StatusView.error(
                title: 'Could not load care tasks',
                message: _errorMessage!,
                onAction: _loadTasks,
              )
            else if (_tasks.isEmpty)
              const StatusView.empty(
                icon: Icons.assignment_outlined,
                title: 'No care tasks yet',
                message: 'Care tasks will appear here once they are scheduled.',
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Today's Progress",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    "$progressPercent%",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF00BFA5),
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
                  backgroundColor: Colors.grey.shade300,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF00BFA5),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  _buildStatDot("Done", doneTasks, const Color(0xFF00C853)),
                  const SizedBox(width: 15),
                  _buildStatDot(
                    "Pending",
                    pendingTasks,
                    const Color(0xFFFFA726),
                  ),
                  const SizedBox(width: 15),
                  _buildStatDot(
                    "Not Completed",
                    skippedTasks,
                    const Color(0xFFE53935),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              if (pendingList.isNotEmpty) ...[
                const Text(
                  "Pending Tasks",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                ...pendingList.map((task) => _buildPendingCard(task)),
                const SizedBox(height: 25),
              ],
              if (completedList.isNotEmpty) ...[
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Color(0xFF00C853),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      "Completed",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                ...completedList.map((task) => _buildCompletedCard(task)),
              ],
              if (notCompletedList.isNotEmpty) ...[
                const SizedBox(height: 25),
                const Row(
                  children: [
                    Icon(Icons.cancel, color: Color(0xFFE53935), size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Not Completed",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                ...notCompletedList.map((task) => _buildCompletedCard(task)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatDot(String label, int count, Color color) {
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(
          "$count $label",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildPendingCard(_CareTaskItem task) {
    final isUpdating = _updatingTaskId == task.id;

    return GestureDetector(
      onTap: () {
        setState(() {
          task.isExpanded = !task.isExpanded;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
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
        child: Column(
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  child: Icon(Icons.assignment, color: Color(0xFFFFA726)),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        task.scheduledTime.isEmpty
                            ? 'Pending'
                            : 'Pending - ${task.scheduledTime}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  task.isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.grey,
                ),
              ],
            ),
            if (task.isExpanded) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _controllers[task.id],
                decoration: InputDecoration(
                  hintText: "Add a remark (optional)",
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8F9FA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide(color: Color(0xFF00BFA5)),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isUpdating
                          ? null
                          : () => _updateTaskStatus(task, 'DONE'),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(isUpdating ? "Saving..." : "Mark Done"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00C853),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isUpdating
                          ? null
                          : () => _updateTaskStatus(task, 'SKIPPED'),
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Color(0xFFE53935),
                      ),
                      label: const Text(
                        "Not Completed",
                        style: TextStyle(color: Color(0xFFE53935)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE53935)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedCard(_CareTaskItem task) {
    final isSkipped = task.status.toUpperCase() == 'SKIPPED';
    final themeColor = isSkipped
        ? const Color(0xFFE53935)
        : const Color(0xFF00C853);
    final icon = isSkipped ? Icons.cancel : Icons.check_circle;
    final completedAt = task.timeCompleted ?? task.updatedAt;
    final prefix = isSkipped ? 'Not completed' : 'Done';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.5),
          width: 1.5,
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
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.assignment, color: themeColor, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  "$prefix at ${_formatTime(completedAt, 'just now')}",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (task.remark != null && task.remark!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.remark!,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(icon, color: themeColor),
        ],
      ),
    );
  }
}

class _CareTaskItem {
  final String id;
  final String title;
  final String type;
  final String scheduledTime;
  String status;
  String? remark;
  DateTime? timeCompleted;
  DateTime? updatedAt;
  bool isExpanded = false;

  _CareTaskItem({
    required this.id,
    required this.title,
    required this.type,
    required this.scheduledTime,
    required this.status,
    this.remark,
    this.timeCompleted,
    this.updatedAt,
  });
}
