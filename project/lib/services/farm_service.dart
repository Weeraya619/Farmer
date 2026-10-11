import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:project/api/api_config.dart';
import 'package:project/main.dart';
import 'package:project/services/farm_permissions.dart';

/// ผลลัพธ์ของการเรียก API: สำเร็จ → data / ไม่สำเร็จ → error (ข้อความภาษาไทยจาก backend)
class ApiResult<T> {
  final T? data;
  final String? error;
  const ApiResult({this.data, this.error});
  bool get ok => error == null;
}

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

    // จำฟาร์มที่เลือกอยู่ไว้ก่อน — โหลดใหม่แล้วต้องไม่เด้งกลับไปฟาร์มแรก
    final previousId = selectedFarmId;

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/farms/me'),
        headers: _authHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> farmData = data['data'] ?? [];
        farms = farmData.map((f) => Map<String, dynamic>.from(f)).toList();
        FarmPermissions.updateFrom(farms);

        if (farms.isEmpty) {
          selectedFarm = null;
        } else {
          selectedFarm = farms.firstWhere(
            (f) => f['farm_id'] == previousId,
            orElse: () => farms.first,
          );
        }
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

  /// สิทธิ์ของ user ในฟาร์มที่เลือกอยู่
  FarmPermissions get selectedPermissions => FarmPermissions.of(selectedFarmId);

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

  // ============================================================
  // ตัวช่วยเรียก API ทั่วไป
  // ============================================================

  Future<ApiResult<dynamic>> _send(String method, String path, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      final http.Response response;

      if (method == 'GET') {
        response = await http.get(uri, headers: _authHeaders);
      } else if (method == 'POST') {
        response = await http.post(uri, headers: _authHeaders, body: jsonEncode(body ?? {}));
      } else if (method == 'PATCH') {
        response = await http.patch(uri, headers: _authHeaders, body: jsonEncode(body ?? {}));
      } else {
        response = await http.delete(uri, headers: _authHeaders);
      }

      final dynamic decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);

      if (response.statusCode != 200) {
        final message = decoded is Map ? decoded['error'] : null;
        return ApiResult(error: message?.toString() ?? 'เกิดข้อผิดพลาด (${response.statusCode})');
      }

      return ApiResult(data: decoded is Map ? decoded['data'] : null);
    } catch (e) {
      return const ApiResult(error: 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง');
    }
  }

  ApiResult<List<Map<String, dynamic>>> _asList(ApiResult<dynamic> result) {
    if (!result.ok) return ApiResult(error: result.error);
    final raw = result.data;
    final list = raw is List ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
    return ApiResult(data: list);
  }

  // ============================================================
  // สวิตช์สิทธิ์ของ worker (owner เท่านั้น) — ส่งเฉพาะค่าที่เปลี่ยน
  // ============================================================

  /// คืน null ถ้าสำเร็จ หรือข้อความ error
  Future<String?> updateSettings(String farmId, {bool? finance, bool? buyCow, bool? sellCow}) async {
    final body = <String, dynamic>{
      if (finance != null) 'workerFinanceEnabled': finance,
      if (buyCow != null) 'workerBuyCowEnabled': buyCow,
      if (sellCow != null) 'workerSellCowEnabled': sellCow,
    };

    final result = await _send('PATCH', '/farms/$farmId/settings', body: body);
    if (!result.ok) return result.error;

    await loadFarms(); // อัปเดต cache สิทธิ์ให้หน้าอื่นเห็นค่าใหม่
    return null;
  }

  // ============================================================
  // สมาชิกฟาร์ม
  // ============================================================

  /// สมาชิก: [{userId, username, role, isPrimaryOwner, addedAt}] (owner เท่านั้น)
  Future<ApiResult<List<Map<String, dynamic>>>> getMembers(String farmId) async {
    return _asList(await _send('GET', '/farms/$farmId/members'));
  }

  /// เลื่อน/ลดขั้น role เป็น 'owner' (เจ้าของร่วม) หรือ 'worker' — เจ้าของหลักเท่านั้น
  Future<String?> changeMemberRole(String farmId, String userId, String role) async {
    final result = await _send('PATCH', '/farms/$farmId/members/$userId/role', body: {'role': role});
    return result.error;
  }

  Future<String?> removeMember(String farmId, String userId) async {
    final result = await _send('DELETE', '/farms/$farmId/members/$userId');
    return result.error;
  }

  /// ออกจากฟาร์มเอง (เจ้าของหลักออกไม่ได้)
  Future<String?> leaveFarm(String farmId) async {
    final result = await _send('POST', '/farms/$farmId/leave');
    if (!result.ok) return result.error;
    await loadFarms();
    return null;
  }

  // ============================================================
  // คำขอเข้าฟาร์ม
  // ============================================================

  /// ค้นฟาร์มของ owner จาก username → [{farmId, farmName, pending}]
  Future<ApiResult<List<Map<String, dynamic>>>> searchOwnerFarms(String username) async {
    final query = Uri.encodeQueryComponent(username.trim());
    return _asList(await _send('GET', '/join-requests/owner-farms?username=$query'));
  }

  Future<String?> sendJoinRequest(String farmId) async {
    final result = await _send('POST', '/join-requests', body: {'farmId': farmId});
    return result.error;
  }

  /// คำขอที่ตัวเองส่งไป → [{requestId, farmName, status, createdAt, decidedAt}]
  Future<ApiResult<List<Map<String, dynamic>>>> getMyJoinRequests() async {
    return _asList(await _send('GET', '/join-requests/mine'));
  }

  /// คำขอที่รอตัวเองยืนยัน (ทุกฟาร์มที่เป็น owner) → [{requestId, farmId, farmName, username, createdAt}]
  Future<ApiResult<List<Map<String, dynamic>>>> getIncomingRequests() async {
    return _asList(await _send('GET', '/join-requests/incoming'));
  }

  Future<String?> decideJoinRequest(String requestId, {required bool approve}) async {
    final result = await _send(
      'PATCH',
      '/join-requests/$requestId',
      body: {'action': approve ? 'approve' : 'reject'},
    );
    return result.error;
  }
}