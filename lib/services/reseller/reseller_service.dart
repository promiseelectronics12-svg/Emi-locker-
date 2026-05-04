import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/reseller/reseller_models.dart';

class ResellerService {
  final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';

  Future<<ListList<<DealerDealer>> getDealers() async {
    final response = await http.get(Uri.parse('$baseUrl/reseller/dealers'));
    if (response.statusCode == 200) {
      List data = json.decode(response.body);
      return data.map((d) => Dealer.fromJson(d)).toList();
    }
    throw Exception('Failed to load dealers');
  }

  Future<<KeyKeyInventory> getKeyInventory() async {
    final response = await http.get(Uri.parse('$baseUrl/reseller/inventory'));
    if (response.statusCode == 200) {
      return KeyInventory.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to load inventory');
  }

  Future<<voidvoid> updateDealerStatus(String dealerId, String status, {String? reason}) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/reseller/dealers/$dealerId/status'),
      body: jsonEncode({'status': status, 'reason': reason}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) throw Exception('Failed to update dealer status');
  }

  Future<<voidvoid> assignKeys(String dealerId, int quantity, String twoFactorCode) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reseller/assign-keys'),
      body: jsonEncode({'dealerId': dealerId, 'quantity': quantity, 'twoFactorCode': twoFactorCode}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) throw Exception('Failed to assign keys');
  }

  Future<<voidvoid> requestKeys(int quantity, String justification) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reseller/request-keys'),
      body: jsonEncode({'quantity': quantity, 'justification': justification}),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode != 200) throw Exception('Failed to request keys');
  }

  Future<<ListList<<KeyKeyRequest>> getKeyRequests() async {
    final response = await http.get(Uri.parse('$baseUrl/reseller/requests'));
    if (response.statusCode == 200) {
      List data = json.decode(response.body);
      return data.map((r) => KeyRequest.fromJson(r)).toList();
    }
    throw Exception('Failed to load requests');
  }
}
