import 'package:flutter/material.dart';
import 'package:medicare_tract/core/config/app_branding.dart';

class LegalDocumentScreen extends StatelessWidget {
  final String title;

  const LegalDocumentScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final isPrivacy = title.toLowerCase().contains('privacy');
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppBranding.appName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFFA726),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isPrivacy
                  ? 'This privacy summary explains what information is used to operate resident care updates, authentication, messaging, and account support.'
                  : 'These terms summarize expected account use, caregiver/family responsibilities, and safe use of Medicare Track.',
              style: const TextStyle(color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 24),
            _section(
              isPrivacy ? 'Data We Use' : 'Responsible Use',
              isPrivacy
                  ? 'Account details, contact details, resident profile data, care task updates, medication updates, and messages are used to provide care coordination features.'
                  : 'Users must keep credentials private and use the app only for legitimate care coordination related to assigned residents.',
            ),
            _section(
              isPrivacy ? 'Care Data' : 'Care Information',
              'The app supports care visibility but does not replace professional medical judgment, emergency services, or facility protocols.',
            ),
            _section(
              isPrivacy ? 'Account Control' : 'Account Changes',
              'Family users can request account deletion in-app. Facility administrators can deactivate caregiver and family accounts when needed.',
            ),
            _section(
              'Contact',
              'For official legal text, publish your facility-approved policy URL in the Play Console and update this screen to match it.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String heading, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(color: Colors.black87, height: 1.45),
          ),
        ],
      ),
    );
  }
}
