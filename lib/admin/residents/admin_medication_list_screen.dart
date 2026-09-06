import 'package:flutter/material.dart';
import 'package:medicare_tract/admin/residents/add_medication_screen.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';
import 'package:medicare_tract/core/utils/data_parsing.dart';
import 'package:medicare_tract/shared/widgets/status_view.dart';

class AdminMedicationListScreen extends StatefulWidget {
  final String residentId;
  final String residentName;

  const AdminMedicationListScreen({
    super.key,
    required this.residentId,
    required this.residentName,
  });

  @override
  State<AdminMedicationListScreen> createState() =>
      _AdminMedicationListScreenState();
}

class _AdminMedicationListScreenState extends State<AdminMedicationListScreen> {
  final ResidentService _residentService = ResidentService.instance;
  final Set<String> _busyMedicationIds = {};

  bool _isLoading = true;
  bool _changed = false;
  String? _errorMessage;
  List<_AdminMedicationItem> _medications = const [];

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  Future<void> _loadMedications({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final rawMedications = await _residentService.getResidentMedications(
        widget.residentId,
      );
      final medications = mapListFrom(
        rawMedications,
      ).map(_AdminMedicationItem.fromMap).toList();

      if (!mounted) {
        return;
      }
      setState(() {
        _medications = medications;
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

  Future<void> _openMedicationForm({_AdminMedicationItem? medication}) async {
    if (medication?.isCompleted == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completed medicines cannot be edited.')),
      );
      return;
    }

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddMedicationScreen(
          residentId: widget.residentId,
          residentName: widget.residentName,
          medication: medication?.rawData,
        ),
      ),
    );

    if (saved == true && mounted) {
      _changed = true;
      await _loadMedications();
    }
  }

  Future<void> _confirmDeleteMedication(_AdminMedicationItem medication) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete medicine?'),
        content: Text(
          'Are you sure you want to delete "${medication.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyMedicationIds.add(medication.id));
    try {
      await _residentService.deleteMedication(medication.id);
      if (!mounted) {
        return;
      }
      _changed = true;
      messenger.showSnackBar(
        const SnackBar(content: Text('Medicine deleted.')),
      );
      await _loadMedications(showLoading: false);
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Failed to delete medicine.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyMedicationIds.remove(medication.id));
      }
    }
  }

  int _countByStatus(String status) => _medications
      .where((medication) => medication.statusLabel == status)
      .length;

  int get _pendingCount => _countByStatus('Pending');

  int get _completedCount =>
      _medications.where((medication) => medication.isCompleted).length;

  int get _delayedCount => _countByStatus('Delayed');

  int get _skippedCount => _countByStatus('Skipped');

  int get _missedCount => _countByStatus('Missed / Not Administered');

  Color _statusColor(String status) {
    switch (status) {
      case 'Completed':
        return const Color(0xFF00C853);
      case 'Delayed':
        return const Color(0xFFFFA726);
      case 'Skipped':
        return const Color(0xFFFFA726);
      case 'Missed / Not Administered':
        return const Color(0xFFE53935);
      case 'Active':
        return const Color(0xFF00BFA5);
      case 'Pending':
      default:
        return const Color(0xFFFFA726);
    }
  }

  void _close() {
    Navigator.pop(context, _changed ? _medications.length : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: _close,
        ),
        title: Column(
          children: [
            const Text(
              'Medication List',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.residentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openMedicationForm(),
        backgroundColor: const Color(0xFF00BFA5),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Medicine'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMedications,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final horizontalPadding = width < 360
                ? 14.0
                : width < 700
                ? 20.0
                : 32.0;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    width < 700 ? 20 : 24,
                    horizontalPadding,
                    96,
                  ),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    if (_isLoading)
                      const InlineLoading(message: 'Loading medications...')
                    else if (_errorMessage != null)
                      StatusView.error(
                        title: 'Could not load medications',
                        message: _errorMessage!,
                        onAction: _loadMedications,
                      )
                    else if (_medications.isEmpty)
                      _buildEmptyState()
                    else
                      _buildMedicationGrid(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Admin Medication List',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D0C57),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_medications.length} created medicines',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          );
          final addButton = ElevatedButton.icon(
            onPressed: () => _openMedicationForm(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Medicine'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          );

          final summary = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildSummaryChip(
                'Pending',
                _pendingCount,
                const Color(0xFFFFA726),
              ),
              _buildSummaryChip(
                'Completed',
                _completedCount,
                const Color(0xFF00C853),
              ),
              _buildSummaryChip(
                'Delayed',
                _delayedCount,
                const Color(0xFFFFA726),
              ),
              _buildSummaryChip(
                'Skipped',
                _skippedCount,
                const Color(0xFFFFA726),
              ),
              _buildSummaryChip(
                'Missed',
                _missedCount,
                const Color(0xFFE53935),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 14),
                summary,
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: addButton),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 14), summary],
                ),
              ),
              const SizedBox(width: 16),
              addButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.medication_outlined,
            color: Colors.grey.shade400,
            size: 44,
          ),
          const SizedBox(height: 14),
          const Text(
            'No medicines created yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF37474F),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create the first medicine schedule for this resident.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: () => _openMedicationForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add Medicine'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA5),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicationGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        const spacing = 14.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: _medications.map((medication) {
            return SizedBox(
              width: itemWidth.isFinite && itemWidth > 0
                  ? itemWidth
                  : constraints.maxWidth,
              child: _buildMedicationCard(medication),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMedicationCard(_AdminMedicationItem medication) {
    final statusColor = _statusColor(medication.statusLabel);
    final busy = _busyMedicationIds.contains(medication.id);
    final editDisabled = medication.isCompleted || busy;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;
          final icon = Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.medication_outlined,
              color: statusColor,
              size: 24,
            ),
          );
          final statusChip = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              medication.statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: editDisabled
                    ? null
                    : () => _openMedicationForm(medication: medication),
                icon: const Icon(Icons.edit_outlined),
                color: medication.isCompleted
                    ? Colors.grey
                    : const Color(0xFF00BFA5),
                tooltip: medication.isCompleted
                    ? 'Completed medicines cannot be edited'
                    : 'Edit medicine',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: busy
                    ? null
                    : () => _confirmDeleteMedication(medication),
                icon: const Icon(Icons.delete_outline),
                color: const Color(0xFFE53935),
                tooltip: 'Delete medicine',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                medication.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D0C57),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                medication.dosage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 10),
              _buildDetailRow(Icons.repeat, 'Frequency', medication.frequency),
              const SizedBox(height: 6),
              _buildReminderRow(medication),
              if (medication.statusCounts.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildMedicationStatusBadges(medication),
              ],
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [icon, const Spacer(), actions]),
                const SizedBox(height: 12),
                Row(children: [statusChip]),
                const SizedBox(height: 12),
                details,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: 14),
              Expanded(child: details),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [statusChip, const SizedBox(height: 8), actions],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReminderRow(_AdminMedicationItem medication) {
    final reminderText = medication.reminderLabels.isEmpty
        ? 'No reminder times'
        : medication.reminderLabels.join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.access_time, size: 15, color: Colors.grey),
        const SizedBox(width: 6),
        const Text(
          'Times: ',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        Expanded(
          child: Text(
            reminderText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF37474F),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMedicationStatusBadges(_AdminMedicationItem medication) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: medication.statusCounts.entries.map((entry) {
        final label = entry.key;
        final count = entry.value;
        final color = _statusColor(label);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Text(
            count > 1 ? '$count $label' : label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AdminMedicationItem {
  final String id;
  final String name;
  final String dosage;
  final String frequency;
  final String statusLabel;
  final Map<String, int> statusCounts;
  final List<String> reminderLabels;
  final Map<String, dynamic> rawData;

  const _AdminMedicationItem({
    required this.id,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.statusLabel,
    required this.statusCounts,
    required this.reminderLabels,
    required this.rawData,
  });

  factory _AdminMedicationItem.fromMap(Map<String, dynamic> data) {
    final reminders = mapListFrom(data['reminders']);
    final events = mapListFrom(data['events']);
    final statusCounts = <String, int>{};
    for (final event in events) {
      final label = _eventStatusLabel((event['status'] ?? '').toString());
      if (label == null) {
        continue;
      }
      statusCounts[label] = (statusCounts[label] ?? 0) + 1;
    }
    final status = _resolveStatus(data['status']?.toString(), statusCounts);

    return _AdminMedicationItem(
      id: (data['id'] ?? '').toString(),
      name: (data['name'] ?? 'Medicine').toString(),
      dosage: (data['dosage'] ?? '').toString(),
      frequency: (data['frequency'] ?? 'Daily').toString(),
      statusLabel: status,
      statusCounts: statusCounts,
      reminderLabels: reminders.map((reminder) {
        final time = (reminder['time'] ?? '').toString();
        final meal = (reminder['meal'] ?? '').toString();
        return meal.isEmpty ? time : '$time ($meal)';
      }).toList(),
      rawData: data,
    );
  }

  static String? _eventStatusLabel(String rawStatus) {
    switch (rawStatus.toUpperCase()) {
      case 'TAKEN':
      case 'DONE':
      case 'COMPLETED':
        return 'Completed';
      case 'DELAYED':
        return 'Delayed';
      case 'SKIPPED':
        return 'Skipped';
      case 'MISSED':
        return 'Missed / Not Administered';
      case 'PENDING':
        return 'Pending';
      default:
        return null;
    }
  }

  static String _resolveStatus(
    String? rawStatus,
    Map<String, int> statusCounts,
  ) {
    final totalEvents = statusCounts.values.fold<int>(
      0,
      (total, count) => total + count,
    );
    if (totalEvents > 0 && (statusCounts['Completed'] ?? 0) == totalEvents) {
      return 'Completed';
    }
    if ((statusCounts['Missed / Not Administered'] ?? 0) > 0) {
      return 'Missed / Not Administered';
    }
    if ((statusCounts['Delayed'] ?? 0) > 0) {
      return 'Delayed';
    }
    if ((statusCounts['Skipped'] ?? 0) > 0) {
      return 'Skipped';
    }
    if ((statusCounts['Pending'] ?? 0) > 0) {
      return 'Pending';
    }

    final normalized = rawStatus?.trim().toUpperCase();
    if (normalized == 'COMPLETED' || normalized == 'COMPLETE') {
      return 'Completed';
    }
    if (normalized == 'ACTIVE') {
      return 'Active';
    }
    if (normalized == 'PENDING') {
      return 'Pending';
    }

    return 'Pending';
  }

  bool get isCompleted => statusLabel == 'Completed';
}
