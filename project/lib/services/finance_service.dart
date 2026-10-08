import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:project/api/api_config.dart';
import 'package:project/main.dart';

class FinanceService {
  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${authService.accessToken}',
        'Content-Type': 'application/json',
      };

  Future<List<Map<String, dynamic>>> getFinances(String farmId, {String? from, String? to}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/finances').replace(
      queryParameters: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      },
    );
    final response = await http.get(uri, headers: _authHeaders);

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final List<dynamic> items = data['data'] ?? [];
    return items.map((f) => Map<String, dynamic>.from(f)).toList();
  }

  /// คืนค่า null ถ้าสำเร็จ หรือข้อความ error ถ้าไม่สำเร็จ
  Future<String?> createFinance({
    required String farmId,
    required String recordDate,
    double cowPurchase = 0,
    double feed = 0,
    double medicine = 0,
    double cowSale = 0,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/finances'),
        headers: _authHeaders,
        body: jsonEncode({
          'recordDate': recordDate,
          'cowPurchase': cowPurchase,
          'feed': feed,
          'medicine': medicine,
          'cowSale': cowSale,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        return data['error'] ?? 'บันทึกรายการไม่สำเร็จ';
      }
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }

  Future<String?> deleteFinance(String financeId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/finances/$financeId'),
        headers: _authHeaders,
      );
      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        return data['error'] ?? 'ลบรายการไม่สำเร็จ';
      }
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }

  /// บันทึกหลายรายการทีเดียว (ปุ่ม + เพิ่มรายการ) — ทุกรายการต้องเป็นหมวดเดียวกัน (feed หรือ medicine)
  Future<String?> createFinanceEntries({
    required String farmId,
    required String recordDate,
    required String category, // 'feed' | 'medicine'
    required List<Map<String, dynamic>> entries, // [{note, amount}, ...]
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/finance-entries'),
        headers: _authHeaders,
        body: jsonEncode({
          'recordDate': recordDate,
          'category': category,
          'entries': entries,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        return data['error'] ?? 'บันทึกรายการไม่สำเร็จ';
      }
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }
}