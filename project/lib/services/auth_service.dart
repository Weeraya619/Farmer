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

    await _storage.write(key: 'access_token', value: _accessToken);
    await _storage.write(key: 'refresh_token', value: _refreshToken);
    await _storage.write(key: 'current_user', value: jsonEncode(_currentUser));

    notifyListeners();
    return null;
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