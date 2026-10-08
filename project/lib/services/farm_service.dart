import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:project/api/api_config.dart';
import 'package:project/main.dart';

/// ดึงข้อมูลฟาร์มของ user ที่ login อยู่ ผ่าน Node.js API
/// (แทนที่ FarmSelectionService เดิมที่เรียก Supabase/getIdToken ตรง)
class FarmService extends ChangeNotifier {
  List<Map<String, dynamic>> farms = [];
  Map<String, dynamic>? selectedFarm;
  bool isLoading = true;
  String? errorMessage;

  Map<String, String> get _authHeaders => {
        'Authorization': 'Bearer ${authService.accessToken}',
        'Content-Type': 'application/json',
      };

  Future<void> loadFarms() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/farms/me'),
        headers: _authHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> farmData = data['data'] ?? [];
        farms = farmData.map((f) => Map<String, dynamic>.from(f)).toList();
        selectedFarm = farms.isNotEmpty ? farms.first : null;
      } else if (response.statusCode == 401) {
        errorMessage = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
      } else {
        errorMessage = 'ไม่สามารถโหลดข้อมูลฟาร์มได้';
      }
    } catch (e) {
      errorMessage = 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }

    isLoading = false;
    notifyListeners();
  }

  String? get selectedFarmId => selectedFarm?['farm_id'];
  String? get selectedFarmName => selectedFarm?['farm_name'];
  bool get hasFarmData => farms.isNotEmpty;

  /// สร้างฟาร์มใหม่ ผู้สร้างกลายเป็น owner อัตโนมัติ (ฝั่ง backend จัดการให้)
  /// คืนค่า null ถ้าสำเร็จ หรือข้อความ error ถ้าไม่สำเร็จ
  Future<String?> createFarm(String farmName) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/farms'),
        headers: _authHeaders,
        body: jsonEncode({'farmName': farmName}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode != 200) {
        return data['error'] ?? 'สร้างฟาร์มไม่สำเร็จ';
      }

      await loadFarms();
      return null;
    } catch (e) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }
}