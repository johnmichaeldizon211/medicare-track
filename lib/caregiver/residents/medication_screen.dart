import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medicare_tract/caregiver/widgets/medication_update_sheet.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class MedicationScreen extends StatefulWidget {
  final String residentId;
  final String residentName;

  const MedicationScreen({
    super.key,
    required this.residentId,
    required this.residentName,
  });

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends State<MedicationScreen> {
  final ResidentService _residentService = ResidentService.instance;

  bool _isLoading = true;
  bool _isUpdating = false;
  String? _errorMessage;
  Timer? _urgencyRefreshTimer;
  List<_MedicationEventItem> _events = const [];

  @override
  void initState() {
    super.initState();
    _loadMedications();
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

  Future<void> _loadMedications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final medications = await _residentService.getResidentMedications(
        widget.residentId,
      );
      final events = <_MedicationEventItem>[];

      for (final medicationRaw in medications) {
        final medication = Map<String, dynamic>.from(medicationRaw as Map);
        final medName = (medication['name'] ?? 'Medication').toString();
        final dosage = (medication['dosage'] ?? '').toString();
        final eventList = medication['events'] as List<dynamic>? ?? const [];

        for (final eventRaw in eventList) {
          final event = Map<String, dynamic>.from(eventRaw as Map);
          final scheduledAt = DateTime.tryParse(
            (event['scheduledAt'] ?? '').toString(),
          )?.toLocal();
          if (scheduledAt == null) {
            continue;
          }

          events.add(
            _MedicationEventItem(
              eventId: (event['id'] ?? '').toString(),
              name: medName,
              dosage: dosage,
              scheduledAt: scheduledAt,
              status: (event['status'] ?? 'PENDING').toString(),
              remark: event['remark']?.toString(),
            ),
          );
        }
      }

      events.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

      if (!mounted) {
        return;
      }
      setState(() {
        _events = events;
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
        _errorMessage = 'Unable to load medications right now.';
        _isLoading = false;
      });
    }
  }

  List<_MedicationEventItem> _eventsFor(Set<String> statuses) {
    return _events
        .where((item) => statuses.contains(item.status.toUpperCase()))
        .toList();
  }

  bool _isAlertMedication(_MedicationEventItem item, DateTime now) {
    return item.status.toUpperCase() == 'PENDING' &&
        now.isAfter(item.scheduledAt);
  }

  Future<void> _updateMedication(_MedicationEventItem item) async {
    final result = await MedicationUpdateSheet.show(
      context,
      '${item.name} ${item.dosage}'.trim(),
      'Scheduled: ${_formatDateTime(item.scheduledAt)}',
    );
    if (result == null) {
      return;
    }

    setState(() => _isUpdating = true);
    try {
      await _residentService.updateMedicationEventStatus(
        eventId: item.eventId,
        status: result.status,
        remark: result.remark,
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medication status updated.')),
      );
      await _loadMedications();
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
        const SnackBar(content: Text('Failed to update medication.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour > 12
        ? value.hour - 12
        : (value.hour == 0 ? 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} $hour:$minute $period';
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

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'TAKEN':
        return 'Taken';
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final taken = _eventsFor({'TAKEN'});
    final alerts = _events
        .where((item) => _isAlertMedication(item, now))
        .toList();
    final pending = _events
        .where(
          (item) =>
              item.status.toUpperCase() == 'PENDING' &&
              !_isAlertMedication(item, now),
        )
        .toList();
    final attention = alerts;
    final delayed = _eventsFor({'DELAYED'});
    final missed = _eventsFor({'MISSED'});
    final skipped = _eventsFor({'SKIPPED'});

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
              "Medication",
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
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadMedications,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if (_isLoading)
                  const InlineLoading(message: 'Loading medications...')
                else if (_errorMessage != null)
                  StatusView.error(
                    title: 'Could not load medications',
                    message: _errorMessage!,
                    onAction: _loadMedications,
                  )
                else if (_events.isEmpty)
                  const StatusView.empty(
                    icon: Icons.medication_outlined,
                    title: 'No medications yet',
                    message:
                        'New medications assigned by admin will appear here.',
                  )
                else ...[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildStatBox(
                        taken.length.toString(),
                        "Taken",
                        const Color(0xFFE8F5E9),
                        const Color(0xFF00C853),
                      ),
                      _buildStatBox(
                        pending.length.toString(),
                        "Pending",
                        const Color(0xFFE0F2F1),
                        const Color(0xFF00BFA5),
                      ),
                      _buildStatBox(
                        alerts.length.toString(),
                        "Alerts",
                        const Color(0xFFFFEBEE),
                        const Color(0xFFE53935),
                      ),
                      _buildStatBox(
                        delayed.length.toString(),
                        "Delayed",
                        const Color(0xFFFFF3E0),
                        const Color(0xFFFFA726),
                      ),
                      _buildStatBox(
                        missed.length.toString(),
                        "Missed",
                        const Color(0xFFFFEBEE),
                        const Color(0xFFE53935),
                      ),
                      _buildStatBox(
                        skipped.length.toString(),
                        "Skipped",
                        const Color(0xFFFFF3E0),
                        const Color(0xFFFFA726),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _buildMedicationSection(
                    "Pending (${pending.length})",
                    pending,
                    emptyText: "No pending medications.",
                    allowUpdate: true,
                  ),
                  _buildMedicationSection(
                    "Attention / Urgent Medications (${attention.length})",
                    attention,
                    emptyText: "No urgent medication updates yet.",
                    allowUpdate: true,
                    iconColor: const Color(0xFFE53935),
                  ),
                  _buildMedicationSection(
                    "Delayed (${delayed.length})",
                    delayed,
                    emptyText: "No delayed medications.",
                    allowUpdate: true,
                    iconColor: const Color(0xFFFFA726),
                  ),
                  _buildMedicationSection(
                    "Administered (${taken.length})",
                    taken,
                    emptyText: "No administered medications yet.",
                    allowUpdate: false,
                  ),
                  _buildMedicationSection(
                    "Missed / Not Administered (${missed.length})",
                    missed,
                    emptyText: "No missed medications.",
                    allowUpdate: true,
                    iconColor: const Color(0xFFE53935),
                  ),
                  _buildMedicationSection(
                    "Skipped (${skipped.length})",
                    skipped,
                    emptyText: "No skipped medications.",
                    allowUpdate: false,
                  ),
                ],
              ],
            ),
          ),
          if (_isUpdating)
            Container(
              color: Colors.black.withValues(alpha: 0.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildStatBox(
    String count,
    String label,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              color: textColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationSection(
    String title,
    List<_MedicationEventItem> items, {
    required String emptyText,
    required bool allowUpdate,
    Color? iconColor,
  }) {
    final resolvedIconColor =
        iconColor ??
        (items.isEmpty ? Colors.grey : _statusColor(items.first.status));

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 12, color: resolvedIconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (items.isEmpty)
            _buildEmptyCard(emptyText)
          else
            ...items.map(
              (item) => _buildMedicationCard(item, allowUpdate: allowUpdate),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Text(text, style: const TextStyle(color: Colors.grey)),
    );
  }

  Widget _buildMedicationCard(
    _MedicationEventItem item, {
    required bool allowUpdate,
  }) {
    final isAlert = _isAlertMedication(item, DateTime.now());
    final statusColor = isAlert
        ? const Color(0xFFE53935)
        : _statusColor(item.status);
    final statusBg = statusColor.withValues(alpha: 0.12);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.medication_outlined,
                  color: Color(0xFF00BFA5),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
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
                    ),
                    Text(
                      item.dosage,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Colors.grey,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Scheduled: ${_formatDateTime(item.scheduledAt)}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAlert ? 'Urgent' : _statusLabel(item.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (item.remark != null && item.remark!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              item.remark!,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (allowUpdate) ...[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _updateMedication(item),
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: Color(0xFF00BFA5),
                  size: 18,
                ),
                label: const Text(
                  "Update Status",
                  style: TextStyle(
                    color: Color(0xFF00BFA5),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00BFA5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MedicationEventItem {
  final String eventId;
  final String name;
  final String dosage;
  final DateTime scheduledAt;
  final String status;
  final String? remark;

  const _MedicationEventItem({
    required this.eventId,
    required this.name,
    required this.dosage,
    required this.scheduledAt,
    required this.status,
    this.remark,
  });
}
