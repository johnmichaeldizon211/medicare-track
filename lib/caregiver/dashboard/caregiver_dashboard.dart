import 'package:flutter/material.dart';

// --- IMPORTS ---
import 'package:medicare_tract/caregiver/dashboard/caregiver_home_tab.dart';
import 'package:medicare_tract/caregiver/residents/residents_list_screen.dart';
import 'package:medicare_tract/caregiver/alerts/alerts_tasks_screen.dart';
import 'package:medicare_tract/caregiver/messages/messages_list_screen.dart';
import 'package:medicare_tract/caregiver/profile/profile_tab.dart';

class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  int _selectedIndex = 0;
  int _targetFilterIndex = 0; // Remembers which tab to open in the Directory!

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      if (index == 1) {
        _targetFilterIndex =
            0; // If they click the bottom bar, default to "All"
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      // Tab 0: Home Dashboard
      CaregiverHomeTab(
        onNavigateToMedicalUpdates: () {
          setState(() {
            _selectedIndex = 1; // Jump to the Directory Tab
            _targetFilterIndex =
                1; // Force it to open the "Medical Updates" filter
          });
        },
        onNavigateToAllResidents: () {
          setState(() {
            _selectedIndex = 1; // Jump to the Directory Tab
            _targetFilterIndex = 0; // Force it to open the "All" filter
          });
        },
        onNavigateToShiftSchedule: () {
          setState(() {
            _selectedIndex = 2;
          });
        },
      ),

      // Tab 1: The real Residents Directory
      ResidentsListScreen(
        key: ValueKey(_targetFilterIndex),
        initialFilterIndex: _targetFilterIndex,
      ),

      // --- NEW: TAB 2 IS NOW LIVE! ---
      const AlertsTasksScreen(),

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
          selectedItemColor: const Color(0xFFFFA726),
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
              icon: Icon(Icons.people_alt),
              label: 'Residents',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications),
              label: 'Alerts',
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
