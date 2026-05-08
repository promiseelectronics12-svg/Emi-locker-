import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';

class NeirExportService {
  Future<void> exportDevicesToExcel(List<Map<String, dynamic>> devices) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['NEIR_Export'];
    excel.delete('Sheet1');

    // Headers
    sheetObject.appendRow([
      TextCellValue('IMEI 1'),
      TextCellValue('IMEI 2'),
      TextCellValue('Brand'),
      TextCellValue('Model'),
      TextCellValue('Customer Name'),
      TextCellValue('NID'),
      TextCellValue('Date of Enrollment')
    ]);

    // Data rows
    for (var device in devices) {
      sheetObject.appendRow([
        TextCellValue(device['imei1'] ?? ''),
        TextCellValue(device['imei2'] ?? ''),
        TextCellValue(device['brand'] ?? ''),
        TextCellValue(device['model'] ?? ''),
        TextCellValue(device['customerName'] ?? ''),
        TextCellValue(device['customerNid'] ?? ''),
        TextCellValue(device['enrollmentDate'] ?? '')
      ]);
    }

    // Save and Share
    var fileBytes = excel.save();
    var directory = await getApplicationDocumentsDirectory();
    String filePath = "${directory.path}/NEIR_Export_${DateTime.now().millisecondsSinceEpoch}.xlsx";
    
    File(filePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes!);

    await Share.shareXFiles([XFile(filePath)], text: 'NEIR Export for BTRC Submission');
  }
}
