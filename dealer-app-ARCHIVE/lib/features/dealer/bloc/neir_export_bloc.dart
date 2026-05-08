import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/api/api_client.dart';
import '../../shared/models/analytics.dart';

part 'neir_export_event.dart';
part 'neir_export_state.dart';

class NeirExportBloc extends Bloc<NeirExportEvent, NeirExportState> {
  final ApiClient _apiClient;

  NeirExportBloc(this._apiClient) : super(const NeirExportInitial()) {
    on<LoadNeirDevices>(_onLoadNeirDevices);
    on<ExportNeirExcel>(_onExportNeirExcel);
    on<ShareNeirExcel>(_onShareNeirExcel);
  }

  Future<void> _onLoadNeirDevices(
    LoadNeirDevices event,
    Emitter<NeirExportState> emit,
  ) async {
    emit(const NeirExportLoading());
    try {
      final response = await _apiClient.get('/analytics/neir-export');
      final data = response.data as Map<String, dynamic>;
      final List<dynamic> devicesJson = data['devices'] as List<dynamic>? ?? [];
      final devices = devicesJson
          .map((json) => NeirDeviceRecord.fromJson(json as Map<String, dynamic>))
          .toList();
      emit(NeirDevicesLoaded(devices));
    } catch (e) {
      emit(NeirExportError(e.toString()));
    }
  }

  Future<void> _onExportNeirExcel(
    ExportNeirExcel event,
    Emitter<NeirExportState> emit,
  ) async {
    emit(const NeirExportLoading());
    try {
      final response = await _apiClient.get('/analytics/neir-export');
      final data = response.data as Map<String, dynamic>;
      final List<dynamic> devicesJson = data['devices'] as List<dynamic>? ?? [];
      final devices = devicesJson
          .map((json) => NeirDeviceRecord.fromJson(json as Map<String, dynamic>))
          .toList();

      final file = await _generateBtrcExcel(devices);
      emit(NeirExportSuccess(file));
    } catch (e) {
      emit(NeirExportError(e.toString()));
    }
  }

  Future<void> _onShareNeirExcel(
    ShareNeirExcel event,
    Emitter<NeirExportState> emit,
  ) async {
    emit(const NeirExportLoading());
    try {
      final response = await _apiClient.get('/analytics/neir-export');
      final data = response.data as Map<String, dynamic>;
      final List<dynamic> devicesJson = data['devices'] as List<dynamic>? ?? [];
      final devices = devicesJson
          .map((json) => NeirDeviceRecord.fromJson(json as Map<String, dynamic>))
          .toList();

      final file = await _generateBtrcExcel(devices);
      final timestamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'NEIR Export - $timestamp - EMI Locker Platform',
        subject: 'NEIR Export for BTRC',
      );
      emit(NeirExportShared(devices.length));
    } catch (e) {
      emit(NeirExportError(e.toString()));
    }
  }

  Future<File> _generateBtrcExcel(List<NeirDeviceRecord> devices) async {
    final excel = Excel.createExcel();
    final sheet = excel['NEIR_Export'];

    final headerStyle = CellStyle(
      bold: true,
      fontSize: 12,
      horizontalAlign: HorizontalAlign.left,
      backgroundColor: HexColor('1F4E79'),
      fontColor: 'FFFFFF',
    );

    final headers = [
      'IMEI',
      'Device Brand',
      'Model',
      'Dealer NID',
      'Dealer Business Name',
      'Registration Date',
    ];

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    final dateFormat = DateFormat('yyyy-MM-dd');

    for (var rowIndex = 0; rowIndex < devices.length; rowIndex++) {
      final record = devices[rowIndex];
      final dataRow = [
        TextCellValue(record.imei),
        TextCellValue(record.deviceModel),
        TextCellValue(record.deviceModel),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue(dateFormat.format(DateTime.now())),
      ];

      for (var colIndex = 0; colIndex < dataRow.length; colIndex++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: colIndex, rowIndex: rowIndex + 1));
        cell.value = dataRow[colIndex];
      }
    }

    for (var colIndex = 0; colIndex < headers.length; colIndex++) {
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
}
