import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  OnboardingService._();

  static final OnboardingService instance = OnboardingService._();
  static const _completedKey = 'onboarding_completed';

  bool _isCompleted = false;

  bool get isCompleted => _isCompleted;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isCompleted = prefs.getBool(_completedKey) ?? false;
  }

  Future<void> complete() async {
    _isCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }
}
