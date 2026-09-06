import 'package:flutter/material.dart';

// --- UPDATED IMPORTS MATCHING YOUR SCREENSHOT ---
import 'package:medicare_tract/family/dashboard/family_home_tab.dart';
import 'package:medicare_tract/family/medication_tab/medication_screen.dart';
import 'package:medicare_tract/family/care_task_tab/care_tasks_screen.dart';
import 'package:medicare_tract/family/messages/messages_list_screen.dart'; // Back to main lib
import 'package:medicare_tract/family/profile/profile_tab.dart'; // Back to main lib

class FamilyDashboard extends StatefulWidget {
  const FamilyDashboard({super.key});

  @override
  State<FamilyDashboard> createState() => _FamilyDashboardState();
}

class _FamilyDashboardState extends State<FamilyDashboard> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      FamilyHomeTab(onTabChange: _onItemTapped), // Tab 0
      const MedicationScreen(), // Tab 1
      const CareTasksScreen(), // Tab 2
      const MessagesListScreen(), // Tab 3
      const ProfileTab(), // Tab 4
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxBodyWidth = constraints.maxWidth > 900 ? 900.0 : null;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxBodyWidth ?? double.infinity,
              ),
              child: pages[_selectedIndex],
            ),
          );
        },
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Colors.grey.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: const Color(0xFFF2994A),
          unselectedItemColor: Colors.grey.shade400,
          showUnselectedLabels: true,
          iconSize: 28,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.medication),
              label: 'Medication',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.check_box),
              label: 'Care Tasks',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble),
              label: 'Messages',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_circle),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
