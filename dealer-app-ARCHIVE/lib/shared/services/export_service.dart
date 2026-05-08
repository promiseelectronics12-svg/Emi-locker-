import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../models/device.dart';
import 'package:intl/intl.dart';

class ExportService {
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  Future<File> generateNeirExport(List<Device> devices, String dealerName) async {
    final excel = Excel.createExcel();
    final sheet = excel['NEIR_Export'];

    final headers = [
      'IMEI 1',
      'IMEI 2',
      'MAC Address',
      'Customer Name',
      'Customer Phone',
      'Customer NID',
      'Date of Birth',
      'EMI Amount (BDT)',
      'Tenure (Months)',
      'Enrollment Date',
      'Device Status',
    ];

    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, row: 0)).value =
          TextCellValue(headers[i]);
    }

    final dateFormat = DateFormat('yyyy-MM-dd');
    final currencyFormat = NumberFormat('#,##0.00', 'en_BD');

    for (var rowIndex = 0; rowIndex < devices.length; rowIndex++) {
      final device = devices[rowIndex];
      final row = rowIndex + 1;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, row: row)).value =
          TextCellValue(device.imei1);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, row: row)).value =
          TextCellValue(device.imei2 ?? 'N/A');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, row: row)).value =
          TextCellValue(device.macAddress ?? 'N/A');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, row: row)).value =
          TextCellValue(device.customerName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, row: row)).value =
          TextCellValue(device.customerPhone);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, row: row)).value =
          TextCellValue(device.customerNid);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, row: row)).value =
          TextCellValue(dateFormat.format(device.customerDob));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, row: row)).value =
          TextCellValue(currencyFormat.format(device.emiAmount));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, row: row)).value =
          IntCellValue(device.tenureMonths);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, row: row)).value =
          TextCellValue(dateFormat.format(device.enrollmentDate));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, row: row)).value =
          TextCellValue(_formatStatus(device.status));
    }

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${directory.path}/NEIR_Export_${dealerName}_$timestamp.xlsx');

    final List<int>? bytes = excel.save();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }

    return file;
  }

  String _formatStatus(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.active:
        return 'Active';
      case DeviceStatus.locked:
        return 'Locked';
      case DeviceStatus.gracePeriod:
        return 'Grace Period';
      case DeviceStatus.decoupling:
        return 'Decoupling';
      case DeviceStatus.decoupled:
        return 'Decoupled';
    }
  }

  Future<void> shareFile(File file) async {
    // Implementation would use share_plus package
  }
}