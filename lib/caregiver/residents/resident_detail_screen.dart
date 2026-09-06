import 'package:flutter/material.dart';
import 'package:medicare_tract/caregiver/residents/care_tasks_screen.dart';
import 'package:medicare_tract/caregiver/residents/medication_screen.dart';
import 'package:medicare_tract/core/services/resident_service.dart';
import 'package:medicare_tract/core/utils/api_exception.dart';

class ResidentDetailScreen extends StatefulWidget {
  final String residentId;
  final String residentName;
  final String room;
  final String age;
  final List<String> conditions;
  final String medStatus;
  final String taskStatus;
  final String overallStatus;

  const ResidentDetailScreen({
    super.key,
    required this.residentId,
    required this.residentName,
    required this.room,
    required this.age,
    required this.conditions,
    required this.medStatus,
    required this.taskStatus,
    required this.overallStatus,
  });

  @override
  State<ResidentDetailScreen> createState() => _ResidentDetailScreenState();
}

class _ResidentDetailScreenState extends State<ResidentDetailScreen> {
  final ResidentService _residentService = ResidentService.instance;

  late List<String> _conditions;
  String _medicalNotes = 'No medical notes available yet.';
  Map<String, dynamic>? _familyProfile;
  bool _isLoadingResident = true;
  String? _residentError;

  String get residentId => widget.residentId;
  String get residentName => widget.residentName;
  String get room => widget.room;
  String get age => widget.age;
  List<String> get conditions => _conditions;
  String get medStatus => widget.medStatus;
  String get taskStatus => widget.taskStatus;
  String get overallStatus => widget.overallStatus;

  @override
  void initState() {
    super.initState();
    _conditions = widget.conditions;
    _loadResidentDetail();
  }

  Future<void> _loadResidentDetail() async {
    try {
      final detail = await _residentService.getResidentDetail(residentId);
      if (!mounted) return;
      setState(() {
        _conditions = _conditionLabels(detail['conditions']);
        _familyProfile = _asMap(detail['familyProfile']);
        final notes = (detail['medicalNotes'] ?? '').toString().trim();
        _medicalNotes = notes.isEmpty ? 'No medical notes available yet.' : notes;
        _isLoadingResident = false;
        _residentError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingResident = false;
        _residentError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingResident = false;
        _residentError = 'Unable to load resident details.';
      });
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  List<String> _conditionLabels(dynamic raw) {
    final list = raw as List<dynamic>? ?? const [];
    return list
        .map((item) {
          if (item is Map) {
            return (item['name'] ?? '').toString().trim();
          }
          return item.toString().trim();
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _familyContactDetail() {
    final profile = _familyProfile;
    if (_isLoadingResident) {
      return 'Loading family contact...';
    }
    if (profile == null) {
      return 'Family contact not available';
    }

    final name = (profile['contactName'] ?? '').toString().trim();
    final relationship = (profile['relationship'] ?? '').toString().trim();
    final phone = (profile['contactNumber'] ?? '').toString().trim();
    final secondaryPhone = (profile['secondaryContactNumber'] ?? '')
        .toString()
        .trim();
    final parts = <String>[
      if (name.isNotEmpty) name,
      if (relationship.isNotEmpty) relationship,
      if (phone.isNotEmpty) 'Primary: $phone',
      if (secondaryPhone.isNotEmpty) 'Secondary: $secondaryPhone',
    ];

    return parts.isEmpty ? 'Family contact not available' : parts.join('\n');
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'CRITICAL':
        return const Color(0xFFE53935);
      case 'NEEDS ATTENTION':
      case 'NEEDS_ATTENTION':
        return const Color(0xFFFFA726);
      case 'STABLE':
      default:
        return const Color(0xFF00C853);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE0F2F1),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxContentWidth = constraints.maxWidth > 900 ? 900.0 : null;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxContentWidth ?? double.infinity,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(bottom: 25),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE0F2F1),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        children: [
                          const CircleAvatar(
                            radius: 35,
                            backgroundColor: Color(0xFF00BFA5),
                            child: Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            residentName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "Room ${room.isEmpty ? '-' : room} - Age ${age.isEmpty ? '-' : age}",
                            style: const TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(overallStatus),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Text(
                              overallStatus,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 25),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _StatColumn(medStatus, 'Meds'),
                              _StatColumn(taskStatus, 'Tasks'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                            builder: (context, inner) {
                              final buttons = [
                                _buildActionButton(
                                  Icons.medical_services_outlined,
                                  'Medications',
                                  medStatus,
                                  const Color(0xFF00BFA5),
                                  () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => MedicationScreen(
                                          residentId: residentId,
                                          residentName: residentName,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _buildActionButton(
                                  Icons.assignment_outlined,
                                  'Care Tasks',
                                  taskStatus,
                                  const Color(0xFFFFA726),
                                  () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CareTasksScreen(
                                          residentId: residentId,
                                          residentName: residentName,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ];

                              if (inner.maxWidth < 420) {
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: buttons,
                                );
                              }

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: buttons,
                              );
                            },
                          ),
                          if (_residentError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _residentError!,
                              style: const TextStyle(
                                color: Color(0xFFE53935),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 25),
                          const Text(
                            'Medical Conditions',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_isLoadingResident)
                            const Text(
                              'Loading medical conditions...',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            )
                          else if (conditions.isEmpty)
                            const Text(
                              'No medical conditions listed yet.',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            )
                          else
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: conditions.map(_buildConditionChip).toList(),
                            ),
                          const SizedBox(height: 25),
                          Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.grey.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.note_alt_outlined, color: Colors.grey),
                                    SizedBox(width: 10),
                                    Text(
                                      'Medical Notes',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _medicalNotes,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                                const Divider(height: 30),
                                _buildContactRow(
                                  Icons.contact_phone_outlined,
                                  'Emergency Contact',
                                  _familyContactDetail(),
                                ),
                                const SizedBox(height: 15),
                                _buildContactRow(
                                  Icons.person_outline,
                                  'Care Team Access',
                                  'Available to caregivers',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String title,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 105,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
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
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00BFA5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, color: Color(0xFF00BFA5), size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF00BFA5),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String title, String detail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2F1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF00BFA5), size: 20),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;

  const _StatColumn(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
