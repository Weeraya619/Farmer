/// สิทธิ์ของ user คนนี้ในฟาร์มหนึ่งๆ — สูตรเดียวกับ backend (server/src/utils/farmAccess.js)
/// ใช้แค่ "ซ่อน/จางปุ่ม" ให้ใช้ง่ายเท่านั้น สิทธิ์จริงบังคับที่ backend เสมอ
///
/// เก็บเป็น cache แบบ static ตาม farmId เพราะหลายหน้ารับมาแค่ farmId (ไม่ได้รับ FarmService)
/// FarmService.loadFarms() จะอัปเดต cache นี้ทุกครั้งที่โหลดฟาร์มใหม่
class FarmPermissions {
  final String role; // 'owner' | 'worker'
  final bool isPrimaryOwner;
  final bool workerFinanceEnabled;
  final bool workerBuyCowEnabled;
  final bool workerSellCowEnabled;

  const FarmPermissions({
    required this.role,
    required this.isPrimaryOwner,
    required this.workerFinanceEnabled,
    required this.workerBuyCowEnabled,
    required this.workerSellCowEnabled,
  });

  /// ค่าเริ่มต้นตอนไม่รู้จักฟาร์ม = ไม่มีสิทธิ์อะไรเลย (ปลอดภัยไว้ก่อน)
  const FarmPermissions.none()
      : role = 'worker',
        isPrimaryOwner = false,
        workerFinanceEnabled = false,
        workerBuyCowEnabled = false,
        workerSellCowEnabled = false;

  factory FarmPermissions.fromFarm(Map<String, dynamic> farm) {
    return FarmPermissions(
      role: farm['role'] == 'owner' ? 'owner' : 'worker',
      isPrimaryOwner: farm['isPrimaryOwner'] == true,
      workerFinanceEnabled: farm['worker_finance_enabled'] == true,
      workerBuyCowEnabled: farm['worker_buy_cow_enabled'] == true,
      workerSellCowEnabled: farm['worker_sell_cow_enabled'] == true,
    );
  }

  bool get isOwner => role == 'owner'; // เจ้าของหลักและเจ้าของร่วมทำได้เท่ากัน
  bool get canFinance => isOwner || workerFinanceEnabled;
  // สวิตช์การเงินเป็นสวิตช์หลัก: ปิดการเงิน = ซื้อ/ขายวัวถูกปิดตามอัตโนมัติ
  bool get canBuyCow => isOwner || (workerFinanceEnabled && workerBuyCowEnabled);
  bool get canSellCow => isOwner || (workerFinanceEnabled && workerSellCowEnabled);
  bool get canManageDevices => isOwner;
  bool get canManageMembers => isOwner;

  String get roleLabel => isPrimaryOwner ? 'เจ้าของหลัก' : (isOwner ? 'เจ้าของร่วม' : 'พนักงาน');

  // ---------- cache ----------
  static final Map<String, FarmPermissions> _cache = {};

  static FarmPermissions of(String? farmId) => _cache[farmId] ?? const FarmPermissions.none();

  static void updateFrom(List<Map<String, dynamic>> farms) {
    _cache.clear();
    for (final farm in farms) {
      _cache['${farm['farm_id']}'] = FarmPermissions.fromFarm(farm);
    }
  }
}