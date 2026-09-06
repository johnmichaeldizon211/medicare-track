import 'package:flutter/material.dart';
import 'package:medicare_tract/admin/dashboard/admin_dashboard.dart';
import 'package:medicare_tract/caregiver/dashboard/caregiver_dashboard.dart';
import 'package:medicare_tract/family/dashboard/family_dashboard.dart';
import 'package:medicare_tract/shared/auth/entry_screen.dart';

Widget dashboardForRole(String role) {
  switch (role.toUpperCase()) {
    case 'ADMIN':
      return const AdminDashboard();
    case 'CAREGIVER':
      return const CaregiverDashboard();
    case 'FAMILY':
      return const FamilyDashboard();
    default:
      return const EntryScreen();
  }
}

void goToDashboardForRole(BuildContext context, String role) {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => dashboardForRole(role)),
    (_) => false,
  );
}

void goToEntryScreen(BuildContext context) {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const EntryScreen()),
    (_) => false,
  );
}
