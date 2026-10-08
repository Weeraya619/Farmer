import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:project/api/api_config.dart';
import 'package:project/main.dart';

class DeviceService {
  Map<String, String> get _authHeaders => {
    'Authorization': 'Bearer ${authService.accessToken}',
    'Content-Type': 'application/json',
  };

  Future<List<Map<String, dynamic>>> getDevices(String farmId) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/devices'),
      headers: _authHeaders,
    );
    if (response.statusCode != 200) return [];
    final data = jsonDecode(response.body);
    final List<dynamic> items = data['data'] ?? [];
    return items.map((d) => Map<String, dynamic>.from(d)).toList();
  }

  /// ลงทะเบียนอุปกรณ์ใหม่ — ไม่ต้องเลือกชนิดเซนเซอร์ ESP32 จะบอกเองตอน pair ครั้งแรก
  Future<String?> registerDevice({
    required String farmId,
    required String macAddress,
    required String name,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/devices'),
        headers: _authHeaders,
        body: jsonEncode({'macAddress': macAddress, 'name': name}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200)
        return data['error'] ?? 'ลงทะเบียนไม่สำเร็จ';
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }

  /// เปลี่ยน ESP32 (บอร์ดพัง แต่ sensor ยังดี) — ใช้ MAC ใหม่ โดย device_id เดิม
  /// ประวัติข้อมูล sensor ทั้งหมดยังเชื่อมกับตัวตนเดิมต่อเนื่อง ไม่ขาดตอน
  Future<String?> replaceMac({
    required String deviceId,
    required String newMacAddress,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/devices/$deviceId/replace-mac'),
        headers: _authHeaders,
        body: jsonEncode({'newMacAddress': newMacAddress}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200)
        return data['error'] ?? 'เปลี่ยน ESP32 ไม่สำเร็จ';
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }

  Future<String?> updateDevice({required String deviceId, String? name}) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/devices/$deviceId'),
        headers: _authHeaders,
        body: jsonEncode({if (name != null) 'name': name}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode != 200) return data['error'] ?? 'แก้ไขไม่สำเร็จ';
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }
}
