import 'package:firebase_database/firebase_database.dart';
import '../models/device.dart';

class FirebaseService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  Stream<List<Device>> listenToDealerDevices(String dealerId) {
    return _db.ref('devices').orderByChild('dealerId').equalTo(dealerId).onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return [];
      
      return data.entries.map((e) {
        final deviceData = Map<String, dynamic>.from(e.value as Map);
        deviceData['id'] = e.key;
        return Device.fromJson(deviceData);
      }).toList();
    });
  }

  Future<void> updateDeviceLockStatus(String deviceId, bool isLocked) async {
    await _db.ref('devices/$deviceId').update({
      'isLocked': isLocked,
      'lastUpdate': ServerValue.timestamp,
    });
  }
}
