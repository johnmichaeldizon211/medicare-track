import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare_tract/core/models/facility_info.dart';
import 'package:medicare_tract/core/services/firebase_data_service.dart';

class FacilityInfoService {
  FacilityInfoService._();

  static final FacilityInfoService instance = FacilityInfoService._();

  static const String _documentPath = 'facilityInfo/details';

  final FirebaseDataService _firebase = FirebaseDataService.instance;
  FirebaseFirestore get _db => _firebase.db;

  FacilityInfo _current = FacilityInfo.fallback();

  FacilityInfo get current => _current;

  Stream<FacilityInfo> watchFacilityInfo() async* {
    await _firebase.ensureInitialized();
    yield _current;
    yield* _db.doc(_documentPath).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return _current;
      }
      final info = FacilityInfo.fromMap(
        FirebaseDataService.mapFromDoc(snapshot),
      );
      _current = info;
      return info;
    });
  }

  Future<FacilityInfo> getFacilityInfo() async {
    return _firebase.guard(() async {
      final snapshot = await _db.doc(_documentPath).get();
      if (!snapshot.exists) {
        _current = FacilityInfo.fallback();
        return _current;
      }
      _current = FacilityInfo.fromMap(FirebaseDataService.mapFromDoc(snapshot));
      return _current;
    }, fallbackMessage: 'Unable to load facility details right now.');
  }

  Future<FacilityInfo> updateFacilityInfo(FacilityInfo info) async {
    return _firebase.guard(() async {
      await _db.doc(_documentPath).set({
        ...info.toPayload(),
        'updatedAt': FirebaseDataService.timestampFrom(DateTime.now().toUtc()),
      }, SetOptions(merge: true));
      return getFacilityInfo();
    }, fallbackMessage: 'Unable to update facility details right now.');
  }

  void dispose() {}
}
