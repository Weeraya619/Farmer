import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:project/api/api_config.dart';

/// จัดการ signup/login/logout ทั้งหมดผ่าน Node.js API (ไม่คุยกับ Supabase ตรง)
/// เก็บ access/refresh token ไว้ใน secure storage ของเครื่อง
/// ใช้แบบ: authService.signIn(email, password) แล้ว listen ผ่าน ChangeNotifier
class AuthService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;
  Map<String, dynamic>? _currentUser;

  String? get accessToken => _accessToken;
  Map<String, dynamic>? get currentUser => _currentUser;

  /// ชื่อผู้ใช้ของบัญชีที่ล็อกอินอยู่ — หาใน user['username'] ก่อน แล้วค่อยหาใน metadata
  String? get username {
    final user = _currentUser;
    if (user == null) return null;

    String? pick(dynamic map) {
      if (map is! Map) return null;
      for (final key in const ['username', 'display_name', 'name']) {
        final v = map[key];
        if (v != null && '$v'.trim().isNotEmpty) return '$v';
      }
      return null;
    }

    return pick(user) ?? pick(user['user_metadata']) ?? pick(user['raw_user_meta_data']);
  }

  bool get isLoggedIn => _accessToken != null;

  /// เรียกตอนเปิดแอปครั้งแรก เพื่อเช็คว่ามี session เดิมค้างอยู่ไหม
  Future<void> loadSession() async {
    _accessToken = await _storage.read(key: 'access_token');
    _refreshToken = await _storage.read(key: 'refresh_token');
    final userJson = await _storage.read(key: 'current_user');
    if (userJson != null) {
      _currentUser = jsonDecode(userJson);
    }
    notifyListeners();
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'username': username,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      return data['error'] ?? 'เกิดข้อผิดพลาดในการสมัครสมาชิก';
    }
    return null; // null = สำเร็จ ไม่มี error
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      return data['error'] ?? 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    }

    _accessToken = data['accessToken'];
    _refreshToken = data['refreshToken'];
    _currentUser = data['user'];
    debugPrint('LOGIN USER = ${jsonEncode(_currentUser)}'); // ชั่วคราว: ดูว่า backend ส่งอะไรมาบ้าง ลบได้หลังแก้เสร็จ

    await _storage.write(key: 'access_token', value: _accessToken);
    await _storage.write(key: 'refresh_token', value: _refreshToken);
    await _storage.write(key: 'current_user', value: jsonEncode(_currentUser));

    notifyListeners();
    return null;
  }

  /// เปลี่ยนรหัสผ่านของบัญชีที่ล็อกอินอยู่ ต้องยืนยันด้วยรหัสผ่านปัจจุบันก่อน
  /// คืน null ถ้าสำเร็จ หรือข้อความ error
  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/change-password'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      );

      final dynamic data = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
      if (response.statusCode != 200) {
        final message = data is Map ? data['error'] : null;
        return message?.toString() ?? 'เปลี่ยนรหัสผ่านไม่สำเร็จ';
      }
      return null;
    } catch (_) {
      return 'เชื่อมต่อ server ไม่ได้ ลองใหม่อีกครั้ง';
    }
  }

  Future<void> signOut() async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth/logout'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );
    } catch (_) {
      // ยิงไม่สำเร็จก็ไม่เป็นไร ยังเคลียร์ token ฝั่งเครื่องต่อได้
    }

    _accessToken = null;
    _refreshToken = null;
    _currentUser = null;

    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'current_user');

    notifyListeners();
  }
}