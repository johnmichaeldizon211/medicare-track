import 'package:flutter/material.dart';

class MedicationUpdateResult {
  final String status;
  final String? remark;

  const MedicationUpdateResult({required this.status, this.remark});
}

class MedicationUpdateSheet extends StatefulWidget {
  final String medName;
  final String medDetails;

  const MedicationUpdateSheet({
    super.key,
    required this.medName,
    required this.medDetails,
  });

  static Future<MedicationUpdateResult?> show(
    BuildContext context,
    String name,
    String details,
  ) {
    return showModalBottomSheet<MedicationUpdateResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          MedicationUpdateSheet(medName: name, medDetails: details),
    );
  }

  @override
  State<MedicationUpdateSheet> createState() => _MedicationUpdateSheetState();
}

class _MedicationUpdateSheetState extends State<MedicationUpdateSheet> {
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
      MedicationUpdateResult(
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
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.medication_outlined,
                      color: Color(0xFF00BFA5),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.medName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.medDetails,
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
                "Update Medication Status",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 15),
              const Text(
                "Caregiver Remarks (optional)",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _remarkController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText:
                      "Example: administered after breakfast, tolerated well",
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
                title: "Administered",
                subtitle: "Medication was given successfully",
                color: const Color(0xFF00C853),
                onTap: () => _complete('TAKEN'),
              ),
              _buildActionButton(
                icon: Icons.access_time_filled,
                title: "Delayed",
                subtitle: "Medication was not given on schedule yet",
                color: const Color(0xFFFFA726),
                onTap: () => _complete('DELAYED'),
              ),
              _buildActionButton(
                icon: Icons.cancel,
                title: "Not Administered",
                subtitle: "Medication was missed or refused",
                color: const Color(0xFFE53935),
                onTap: () => _complete('MISSED'),
              ),
              _buildActionButton(
                icon: Icons.pause_circle_filled,
                title: "Skipped",
                subtitle: "Medication was intentionally skipped or held",
                color: const Color(0xFFFFA726),
                fillColor: const Color(0xFFFFF3E0),
                onTap: () => _complete('SKIPPED'),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
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
    Color? fillColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: fillColor ?? Colors.white,
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
