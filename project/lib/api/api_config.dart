/// ตั้งค่า URL ของ Node.js API ตรงนี้ที่เดียว
/// เปลี่ยนตอน deploy จริง (จาก localhost เป็น URL ของ server จริง)
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'https://farmer-production-6b65.up.railway.app/api';

  // เวลาทดสอบบน emulator/มือถือจริงในวง LAN เดียวกัน localhost จะใช้ไม่ได้
  // ต้องเปลี่ยนเป็น IP เครื่องที่รัน backend เช่น 'http://192.168.1.xx:3000/api'
  // หรือถ้าทดสอบบน Android emulator ใช้ 'http://10.0.2.2:3000/api'
}