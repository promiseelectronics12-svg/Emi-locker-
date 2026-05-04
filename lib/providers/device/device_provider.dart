import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../models/device/device_model.dart';
import '../../services/device/device_service.dart';

class DeviceProvider with ChangeNotifier {
  final DeviceService _deviceService = DeviceService();
  List<<DeviceDeviceModel> _devices = [];
  bool _isLoading = false;

  List<<DeviceDeviceModel> get devices => _devices;
  bool get isLoading => _isLoading;

  void init() {
    _deviceService.streamDevices().listen((updatedDevices) {
      _devices = updatedDevices;
      notifyListeners();
    });
  }

  double get collectionRate {
    if (_devices.isEmpty) return 0.0;
    int paidOff = _devices.where((d) => d.status == DeviceStatus.paidOff).length;
    return (paidOff / _devices.length) * 100;
  }

  int get overdueCount {
    return _devices.where((d) => d.status == DeviceStatus.partialLock || d.status == DeviceStatus.fullLock).length;
  }

  int get upcomingEMIs() {
    // Simplified: in real app, scan EMI schedules for dates within 7 days
    return 5; 
  }
}
