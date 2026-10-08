import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:project/api/api_config.dart';
import 'package:project/main.dart';

/// ดึงแจ้งเตือนของฟาร์ม ผ่าน Node.js API (polling ตอนเปิดหน้า ไม่ใช้ Realtime ตรง)
class NotificationService {
  Map<String, String> get _authHeaders => {
    'Authorization': 'Bearer ${authService.accessToken}',
  };

  Future<List<Map<String, dynamic>>> getForFarm(String farmId) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/notifications'),
      headers: _authHeaders,
    );

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final List<dynamic> items = data['data'] ?? [];
    return items.map((n) => Map<String, dynamic>.from(n)).toList();
  }

  int unreadCount(List<Map<String, dynamic>> notifications) {
    return notifications.where((n) => n['is_read'] == false).length;
  }

  Future<bool> markAsRead(String notificationId) async {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/notifications/$notificationId/read'),
      headers: _authHeaders,
    );
    return response.statusCode == 200;
  }

  Future<bool> markAllAsRead(String farmId) async {
    final response = await http.patch(
      Uri.parse('${ApiConfig.baseUrl}/farms/$farmId/notifications/read-all'),
      headers: _authHeaders,
    );
    return response.statusCode == 200;
  }
}
