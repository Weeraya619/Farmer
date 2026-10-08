import 'package:flutter/material.dart';
import 'theme.dart';
import 'text.dart';
import '/services/notification_service.dart';
import '/pages/notification.dart';

/// Header ที่ใช้ซ้ำทุกหน้า
/// ใส่ farmId เข้ามาแล้วปุ่มกระดิ่งจะพาไปหน้าแจ้งเตือนของฟาร์มนั้นเองอัตโนมัติ
/// ไม่ต้องเขียน onBellTap ซ้ำทุกหน้า (ถ้าไม่ส่ง farmId มา ปุ่มจะไม่ทำงาน — ใช้ตอนยังไม่รู้ farmId เช่นหน้า login)
/// ใช้แบบ: AppHeader(farmName: 'วุฒิพงศ์ฟาร์ม', farmId: farmId)
class AppHeader extends StatefulWidget implements PreferredSizeWidget {
  final String farmName;
  final String? farmId;

  const AppHeader({super.key, required this.farmName, this.farmId});

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  State<AppHeader> createState() => _AppHeaderState();
}

class _AppHeaderState extends State<AppHeader> {
  final notificationService = NotificationService();
  int unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  @override
  void didUpdateWidget(covariant AppHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.farmId != widget.farmId) _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    if (widget.farmId == null) return;
    final notifications = await notificationService.getForFarm(widget.farmId!);
    if (!mounted) return;
    setState(
      () => unreadCount = notificationService.unreadCount(notifications),
    );
  }

  Future<void> _openNotifications() async {
    if (widget.farmId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationsPage(farmId: widget.farmId!),
      ),
    );
    _loadUnreadCount(); // กลับมาแล้ว refresh ตัวเลขใหม่ เผื่ออ่านไปแล้ว
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: AppColors.primary,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryLight,
              child: ClipOval(
                child: Image.asset(
                  'assets/images/bull.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.farmName,
                style: AppTextStyles.subheading.copyWith(
                  color: AppColors.textOnPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _NotificationBell(count: unreadCount, onTap: _openNotifications),
          ],
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _NotificationBell({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.notifications_outlined,
              color: Colors.white,
              size: 24,
            ),
            if (count > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
