import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:project/api/api_config.dart';
import 'package:project/main.dart';

/// ดึงข้อมูล sensor ของฟาร์ม ผ่าน Node.js API
class SensorService {
  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${authService.accessToken}',
      };

  /// คืนค่าล่าสุด — รวมอุณหภูมิ/ความชื้น/THI กับค่าน้ำ (TDS/Turbidity) แยกกัน
  /// เพราะมาจากคนละ device กัน ไม่ใช่แค่แถวล่าสุดแถวเดียว
  Future<Map<String, dynamic>?> getLatest(String farmId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/sensor-data/latest');
    final response = await http.get(uri, headers: _authHeaders);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    return data['data'] != null ? Map<String, dynamic>.from(data['data']) : null;
  }

  /// ดึงประวัติย้อนหลัง เรียงใหม่สุดก่อน — ใช้ทำกราฟแนวโน้ม
  /// ระบุ deviceId ได้ถ้าอยากได้เฉพาะอุปกรณ์เดียว (กันข้อมูลปนกันตอนมีหลายตัว)
  Future<List<Map<String, dynamic>>> getHistory(
    String farmId, {
    int? limit,
    String? deviceId,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/sensor-data').replace(
      queryParameters: {
        if (limit != null) 'limit': '$limit',
        if (deviceId != null) 'deviceId': deviceId,
      },
    );
    final response = await http.get(uri, headers: _authHeaders);

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final List<dynamic> readings = data['data'] ?? [];
    return readings.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}