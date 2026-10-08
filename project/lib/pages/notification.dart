import 'package:flutter/material.dart';
import '/widgets/theme.dart';
import '/widgets/text.dart';
import '/services/notification_service.dart';
import '/widgets/date_util.dart';

/// หน้ารายการแจ้งเตือนทั้งหมดของฟาร์ม เรียงใหม่สุดก่อน
/// สีต่างกันตามระดับความรุนแรง (info/warning/critical)
class NotificationsPage extends StatefulWidget {
  final String farmId;
  const NotificationsPage({super.key, required this.farmId});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final notificationService = NotificationService();
  List<Map<String, dynamic>> notifications = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => isLoading = true);
    final data = await notificationService.getForFarm(widget.farmId);
    if (!mounted) return;
    setState(() {
      notifications = data;
      isLoading = false;
    });
  }

  Future<void> _markAsRead(Map<String, dynamic> notification) async {
    if (notification['is_read'] == true) return;
    final success = await notificationService.markAsRead('${notification['notification_id']}');
    if (success && mounted) {
      setState(() => notification['is_read'] = true);
    }
  }

  Future<void> _markAllAsRead() async {
    final success = await notificationService.markAllAsRead(widget.farmId);
    if (success && mounted) {
      setState(() {
        for (final n in notifications) {
          n['is_read'] = true;
        }
      });
    }
  }

  (Color, Color, IconData) _severityStyle(String? severity) {
    switch (severity) {
      case 'critical':
        return (AppColors.dangerBg, AppColors.danger, Icons.error_outline);
      case 'warning':
        return (AppColors.warningBg, AppColors.warning, Icons.warning_amber_outlined);
      default:
        return (AppColors.primaryLight, AppColors.primary, Icons.info_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = notifications.any((n) => n['is_read'] == false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('การแจ้งเตือน'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text('อ่านทั้งหมด', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: notifications.isEmpty
                    ? ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 80),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(Icons.notifications_none, size: 48, color: AppColors.textMuted),
                                  const SizedBox(height: 12),
                                  Text('ยังไม่มีการแจ้งเตือน', style: AppTextStyles.bodySecondary),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: notifications.length,
                        itemBuilder: (context, index) => _notificationTile(notifications[index]),
                      ),
              ),
      ),
    );
  }

  Widget _notificationTile(Map<String, dynamic> notification) {
    final (bg, fg, icon) = _severityStyle(notification['severity']);
    final isRead = notification['is_read'] == true;

    return InkWell(
      onTap: () => _markAsRead(notification),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? AppColors.surface : bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isRead ? AppColors.border : fg.withOpacity(0.3), width: isRead ? 0.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: isRead ? AppColors.textMuted : fg, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification['title'] ?? '-',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: isRead ? FontWeight.w400 : FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(notification['message'] ?? '', style: AppTextStyles.bodySecondary),
                  const SizedBox(height: 6),
                  Text(formatThaiDateTime(notification['created_at']), style: AppTextStyles.caption),
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}