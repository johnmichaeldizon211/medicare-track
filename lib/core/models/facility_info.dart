import 'package:medicare_tract/core/config/app_branding.dart';

class FacilityInfo {
  final String id;
  final String name;
  final String contactNumber;
  final String email;
  final String address;
  final DateTime? updatedAt;

  const FacilityInfo({
    required this.id,
    required this.name,
    required this.contactNumber,
    required this.email,
    required this.address,
    this.updatedAt,
  });

  factory FacilityInfo.fallback() {
    return const FacilityInfo(
      id: 'details',
      name: AppBranding.facilityName,
      contactNumber: '',
      email: '',
      address: '',
    );
  }

  factory FacilityInfo.fromMap(Map<String, dynamic> map) {
    return FacilityInfo(
      id: (map['id'] ?? 'details').toString(),
      name: _valueOrFallback(map['name'], AppBranding.facilityName),
      contactNumber: _textFrom(map['contactNumber']),
      email: _textFrom(map['email']),
      address: _textFrom(map['address']),
      updatedAt: DateTime.tryParse((map['updatedAt'] ?? '').toString()),
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      'name': name.trim(),
      'contactNumber': contactNumber.trim(),
      'email': email.trim(),
      'address': address.trim(),
    };
  }

  bool hasSameContent(FacilityInfo other) {
    return name == other.name &&
        contactNumber == other.contactNumber &&
        email == other.email &&
        address == other.address;
  }

  static String _textFrom(dynamic value) => (value ?? '').toString().trim();

  static String _valueOrFallback(dynamic value, String fallback) {
    final text = _textFrom(value);
    return text.isEmpty ? fallback : text;
  }
}
