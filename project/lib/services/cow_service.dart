import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:project/api/api_config.dart';
import 'package:project/main.dart';

/// ข้อมูลวัวหนึ่งตัวที่กำลังกรอกใน wizard (ยังไม่ได้ส่งขึ้น server)
class CowDraft {
  String gender = 'female'; // 'male' | 'female'
  String pregnancyStatus = 'ปกติ'; // 'ปกติ' | 'ท้อง'
  String nickname = '';

  Map<String, dynamic> toJson() => {
        'gender': gender,
        'pregnancyStatus': pregnancyStatus,
        'nickname': nickname,
      };
}

class CowService {
  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${authService.accessToken}',
        'Content-Type': 'application/json',
      };

  Future<List<Map<String, dynamic>>> getCows(String farmId, {bool availableForSaleOnly = false}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/cows').replace(
      queryParameters: availableForSaleOnly ? {'availableForSale': 'true'} : null,
    );
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body);
    final List<dynamic> items = data['data'] ?? [];
    return items.map((c) => Map<String, dynamic>.from(c)).toList();
  }

  /// บันทึกวัวที่มีอยู่แล้วในฟาร์ม (ไม่ผูกกับรายจ่าย)
  Future<String?> createExistingCows(String farmId, List<CowDraft> cows) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/cows'),
        headers: _authHeaders,
        body: jsonEncode({'cows': cows.map((c) => c.toJson()).toList()}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) return data['error'] ?? 'บันทึกไม่สำเร็จ';
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }

  /// บันทึกซื้อวัวใหม่ — เขียน finances + cows พร้อมกันในคำสั่งเดียว (atomic)
  Future<String?> createCowPurchase({
    required String farmId,
    required String recordDate,
    required double totalPrice,
    required List<CowDraft> cows,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/cow-purchases'),
        headers: _authHeaders,
        body: jsonEncode({
          'recordDate': recordDate,
          'totalPrice': totalPrice,
          'cows': cows.map((c) => c.toJson()).toList(),
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) return data['error'] ?? 'บันทึกไม่สำเร็จ';
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }

  /// บันทึกขายวัว — เขียน finances + อัปเดต cows พร้อมกันในคำสั่งเดียว (atomic)
  Future<String?> createCowSale({
    required String farmId,
    required String recordDate,
    required double totalPrice,
    required List<String> cowIds,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/cow-sales'),
        headers: _authHeaders,
        body: jsonEncode({
          'recordDate': recordDate,
          'totalPrice': totalPrice,
          'cowIds': cowIds,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) return data['error'] ?? 'บันทึกไม่สำเร็จ';
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }

  /// แก้ไขชื่อเล่น/สถานะสุขภาพ (ป่วย/ตาย) ของวัวตัวหนึ่ง
  Future<String?> updateCow({
    required String cowId,
    String? nickname,
    String? healthStatus,
    bool? isDead,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (nickname != null) body['nickname'] = nickname;
      if (healthStatus != null) body['healthStatus'] = healthStatus;
      if (isDead != null) body['isDead'] = isDead;

      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/cows/$cowId'),
        headers: _authHeaders,
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) return data['error'] ?? 'แก้ไขไม่สำเร็จ';
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }
}