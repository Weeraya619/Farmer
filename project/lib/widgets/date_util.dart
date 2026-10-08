const _thaiMonthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

/// แปลง ISO timestamp (เช่น "2026-09-02T06:15:48.211085+00:00") เป็นรูปแบบไทยอ่านง่าย
/// เช่น "2 ก.ย. 2569 เวลา 13:15 น." (แปลงเป็นเวลาท้องถิ่นของเครื่องให้อัตโนมัติ)
String formatThaiDateTime(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '-';
  final parsed = DateTime.tryParse(isoString);
  if (parsed == null) return isoString; // แปลงไม่ได้ ก็คืนค่าเดิมไปก่อน ดีกว่าไม่แสดงอะไรเลย

  final local = parsed.toLocal();
  final buddhistYear = local.year + 543;
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');

  return '${local.day} ${_thaiMonthsShort[local.month - 1]} $buddhistYear เวลา $hour:$minute น.';
}

/// แบบสั้น ไม่มีเวลา ใช้ตอนแค่ต้องการวันที่ เช่น "2 ก.ย. 2569"
String formatThaiDate(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '-';
  final parsed = DateTime.tryParse(isoString);
  if (parsed == null) return isoString;

  final local = parsed.toLocal();
  final buddhistYear = local.year + 543;
  return '${local.day} ${_thaiMonthsShort[local.month - 1]} $buddhistYear';
}

/// เวลาที่ผ่านมาแบบสัมพัทธ์ เช่น "5 นาทีที่แล้ว" "2 ชั่วโมงที่แล้ว" — เหมาะกับ "ข้อมูลล่าสุด"
String formatRelativeTime(String? isoString) {
  if (isoString == null || isoString.isEmpty) return '-';
  final parsed = DateTime.tryParse(isoString);
  if (parsed == null) return isoString;

  final diff = DateTime.now().difference(parsed.toLocal());

  if (diff.inMinutes < 1) return 'เมื่อสักครู่';
  if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
  if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
  if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
  return formatThaiDate(isoString);
}