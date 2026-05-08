import 'dart:io';
import 'package:dio/dio.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/exceptions.dart';
import '../api/api_client.dart';
import '../models/analytics.dart';
import '../models/device.dart';

class AnalyticsRepository {
  final ApiClient _apiClient;

  AnalyticsRepository(this._apiClient);

  Future<DealerAnalytics> getDealerAnalytics() async {
    try {
      final response = await _apiClient.get('/analytics/dealer');
      return DealerAnalytics.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<List<Device>> getNeirExportData({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final response = await _apiClient.get(
        '/analytics/neir-export',
        queryParameters: {
          if (startDate != null) 'start_date': startDate.toIso8601String(),
          if (endDate != null) 'end_date': endDate.toIso8601String(),
        },
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> devicesJson = data['devices'] as List<dynamic>;
      return devicesJson
          .map((json) => Device.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is DioException) {
        throw ApiException.fromDioError(e);
      }
      rethrow;
    }
  }

  Future<File> generateNeirExcel({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final devices = await getNeirExportData(
      startDate: startDate,
      endDate: endDate,
    );

    final excel = Excel.createExcel();
    final sheet = excel['NEIR_Export'];

    sheet.appendRow([
      TextCellValue('IMEI'),
      TextCellValue('Device Model'),
      TextCellValue('Customer Name'),
      TextCellValue('Customer NID'),
      TextCellValue('Customer Phone'),
      TextCellValue('EMI Amount (BDT)'),
      TextCellValue('Total Installments'),
      TextCellValue('Paid Installments'),
      TextCellValue('Enrollment Date'),
      TextCellValue('Status'),
    ]);

    for (final device in devices) {
      sheet.appendRow([
        TextCellValue(device.imei1),
        TextCellValue('Unknown'),
        TextCellValue(device.customerName),
        TextCellValue(device.customerNid),
        TextCellValue(device.customerPhone),
        DoubleCellValue(device.emiAmount),
        IntCellValue(device.totalInstallments),
        IntCellValue(device.paidInstallments),
        TextCellValue(DateFormat('yyyy-MM-dd').format(device.enrolledAt)),
        TextCellValue(device.status.name.toUpperCase()),
      ]);
    }

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${directory.path}/NEIR_Export_$timestamp.xlsx');
    final fileBytes = excel.encode();

    if (fileBytes != null) {
      await file.writeAsBytes(fileBytes);
    }

    return file;
  }

  Future<void> shareNeirExcel({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final file = await generateNeirExcel(
      startDate: startDate,
      endDate: endDate,
    );

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'NEIR Export - ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
    );
  }
}