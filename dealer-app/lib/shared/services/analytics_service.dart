import 'dart:io';
import 'package:dio/dio.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_client.dart';
import '../models/dealer_analytics_model.dart';

class AnalyticsService {
  final ApiClient _apiClient;

  AnalyticsService(this._apiClient);

  Future<DealerAnalyticsData> getDealerAnalytics() async {
    try {
      final response = await _apiClient.get('/analytics/dealer');
      return DealerAnalyticsData.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<List<NeirExportRecord>> getNeirExportData({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (startDate != null) {
        queryParams['start_date'] = DateFormat('yyyy-MM-dd').format(startDate);
      }
      if (endDate != null) {
        queryParams['end_date'] = DateFormat('yyyy-MM-dd').format(endDate);
      }

      final response = await _apiClient.get(
        '/analytics/neir-export',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      final data = response.data as Map<String, dynamic>;
      final List<dynamic> recordsJson = data['devices'] as List<dynamic>? ?? [];
      return recordsJson
          .map((json) => NeirExportRecord.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<File> generateNeirExcel({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final records = await getNeirExportData(
      startDate: startDate,
      endDate: endDate,
    );

    final excel = Excel.createExcel();
    final sheet = excel['NEIR_Export'];

    final headerStyle = CellStyle(
      bold: true,
      fontSize: 12,
      horizontalAlign: HorizontalAlign.left,
      backgroundColor: HexColor('1F4E79'),
      fontColor: 'FFFFFF',
    );

    final headerRow = <CellValue>[
      TextCellValue('IMEI'),
      TextCellValue('Device Brand'),
      TextCellValue('Model'),
      TextCellValue('Dealer NID'),
      TextCellValue('Dealer Business Name'),
      TextCellValue('Registration Date'),
    ];

    for (var i = 0; i < headerRow.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = headerRow[i];
      cell.cellStyle = headerStyle;
    }

    final dateFormat = DateFormat('yyyy-MM-dd');
    final dateStyle = CellStyle(
      horizontalAlign: HorizontalAlign.left,
    );

    for (var rowIndex = 0; rowIndex < records.length; rowIndex++) {
      final record = records[rowIndex];
      final dataRow = <CellValue>[
        TextCellValue(record.imei),
        TextCellValue(record.deviceBrand),
        TextCellValue(record.deviceModel),
        TextCellValue(record.dealerNid),
        TextCellValue(record.dealerBusinessName),
        TextCellValue(dateFormat.format(record.registrationDate)),
      ];

      for (var colIndex = 0; colIndex < dataRow.length; colIndex++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex + 1));
        cell.value = dataRow[colIndex];
        if (colIndex == 5) {
          cell.cellStyle = dateStyle;
        }
      }
    }

    for (var colIndex = 0; colIndex < headerRow.length; colIndex++) {
      sheet.setColumnWidth(colIndex, 25);
    }

    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fileName = 'NEIR_Export_$timestamp.xlsx';
    final file = File('${directory.path}/$fileName');

    final fileBytes = excel.encode();
    if (fileBytes == null) {
      throw Exception('Failed to encode Excel file');
    }

    await file.writeAsBytes(fileBytes);
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

    final timestamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'NEIR Export - $timestamp - EMI Locker Platform',
      subject: 'NEIR Export for BTRC',
    );
  }
}