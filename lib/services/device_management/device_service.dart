import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../models/device_management/device_model.dart';

class DeviceService {
  final _db = FirebaseDatabase.instance.ref();
  final String _baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';

  Stream<<ListList<<DeviceDevice>> getDevicesStream() {
    return _db.child('devices').onValue.map((event) {
      final Map<<StringString, dynamic> data = event.snapshot.value as Map<<StringString, dynamic>;
      return data.entries.map((e) => _mapToDevice(e.key, e.value)).toList();
    });
  }

  Future<<LockLockRequestResult> submitLockRequest({
    required String deviceId,
    required String reasonCode,
    required String note,
  }) async {
    // In a real app, this would call the Node.js API
    // For this implementation, we simulate the server verification engine
    await Future.delayed(const Duration(seconds: 2));
    
    if (reasonCode == 'FRAUD_SUSPECTED') {
      return LockRequestResult(success: true, message: 'APPROVED: Device has been locked due to fraud suspicion.');
    } else {
      return LockRequestResult(
        success: false, 
        message: 'Your lock request is invalid. The EMI overdue period does not match the requested reason code. The device has NOT been locked.'
      );
    }
  }

  Device _mapToDevice(String id, Map<<dynamicdynamic, dynamic> value) {
    return Device(
      id: id,
      imei: value['imei'] ?? 'Unknown',
      serial: value['serial'] ?? 'Unknown',
      oem: value['oem'] ?? 'Unknown',
      model: value['model'] ?? 'Unknown',
      androidVersion: value['android_version'] ?? 'Unknown',
      enrollmentDate: value['enroll_date'] ?? 'Unknown',
      status: value['status'] ?? 'Active',
      lastStateChange: value['last_change'] ?? 'N/A',
      lastLat: (value['lat'] as num?)?.toDouble() ?? 0.0,
      lastLng: (value['lng'] as num?)?.toDouble() ?? 0.0,
      lastLocationTime: value['loc_time'] ?? 'Unknown',
      customerName: value['cust_name'] ?? 'Unknown',
      customerNid: value['cust_nid'] ?? 'Unknown',
      customerPhone: value['cust_phone'] ?? 'Unknown',
      emiSchedule: (value['emi'] as List? ?? []).map((e) => EMIInstallment(
        amount: (e['amount'] as num).toDouble(),
        status: e['status'],
        dueDate: e['date'],
      )).toList(),
      nextPaymentAmount: (value['next_amt'] as num?)?.toDouble() ?? 0.0,
      nextPaymentDate: value['next_date'] ?? 'Unknown',
      overdueDays: value['overdue'] ?? 0,
    );
  }
}

class LockRequestResult {
  final bool success;
  final String message;
  LockRequestResult({required this.success, required this.message});
}
