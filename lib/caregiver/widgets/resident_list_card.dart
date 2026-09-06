import 'package:flutter/material.dart';
import 'package:medicare_tract/caregiver/residents/resident_detail_screen.dart';

class ResidentListCard extends StatelessWidget {
  final String residentId;
  final String name;
  final String room;
  final String age;
  final List<String> conditions;
  final String medStatus;
  final String taskStatus;
  final String overallStatus;
  final VoidCallback onViewDetails;

  const ResidentListCard({
    super.key,
    required this.residentId,
    required this.name,
    required this.room,
    required this.age,
    required this.conditions,
    required this.medStatus,
    required this.taskStatus,
    required this.overallStatus,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final bool isStable = overallStatus == "Stable";
    final Color statusColor = isStable
        ? const Color(0xFF00C853)
        : const Color(0xFFFFA726);
    final Color statusBg = isStable
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFFFF3E0);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE0F2F1),
                child: Text(
                  _getInitials(name),
                  style: const TextStyle(
                    color: Color(0xFF009688),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Room $room · Age $age",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      overallStatus,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: conditions
                .map((condition) => _buildConditionTag(condition))
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.add_box, size: 14, color: Color(0xFF00C853)),
              const SizedBox(width: 4),
              Text(
                medStatus,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.check_box, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                taskStatus,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    onViewDetails();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ResidentDetailScreen(
                          residentId: residentId,
                          residentName: name,
                          room: room,
                          age: age,
                          conditions: conditions,
                          medStatus: medStatus,
                          taskStatus: taskStatus,
                          overallStatus: overallStatus,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.visibility_outlined,
                    size: 16,
                    color: Color(0xFF00BFA5),
                  ),
                  label: const Text(
                    "View Details",
                    style: TextStyle(color: Color(0xFF00BFA5)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00BFA5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getInitials(String fullName) {
    List<String> names = fullName.split(" ");
    String initials = "";
    int numWords = names.length > 2 ? 2 : names.length;
    for (int i = 0; i < numWords; i++) {
      initials += names[i][0];
    }
    return initials.toUpperCase();
  }

  Widget _buildConditionTag(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF00BFA5),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
