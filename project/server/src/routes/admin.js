import { Router } from 'express';
import { supabaseAdmin } from '../supabaseClient.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireAdmin } from '../middleware/requireAdmin.js';
import { getConnectionState, toDeviceView } from '../utils/deviceHealth.js';

const router = Router();

// ทุก route ในไฟล์นี้ต้อง login และเป็น admin เท่านั้น
router.use(requireAuth, requireAdmin);

// สถานะที่แอดมินตั้งเองได้ ('pending' ใช้ปุ่มรีเซ็ตแทน)
const ADMIN_SETTABLE_STATUSES = ['active', 'inactive', 'maintenance'];

// บันทึกทุกการกระทำของแอดมินลง admin_audit_log — เรียกจากทุก endpoint ที่แก้ไขข้อมูล
async function logAdminAction(req, { action, targetType, targetId, details }) {
  const { error } = await supabaseAdmin.from('admin_audit_log').insert({
    admin_id: req.userId,
    action,
    target_type: targetType,
    target_id: targetId ? String(targetId) : null,
    details: details || null,
  });
  if (error) {
    // ไม่ต้อง fail ทั้ง request แค่เพราะ log ไม่สำเร็จ แค่ print ให้เห็นไว้เฉยๆ
    console.error('AUDIT LOG ERROR:', error.message);
  }
}

// ============================================================
// จัดการผู้ใช้
// ============================================================

// GET /api/admin/users
router.get('/users', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('users')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) {
    console.error('ADMIN GET USERS ERROR:', error.message);
    return res.status(500).json({ error: 'ไม่สามารถโหลดรายชื่อผู้ใช้ได้' });
  }

  // ดึงสถานะระงับบัญชี + เวลา login ล่าสุดจาก Supabase Auth มารวมด้วย (public.users ไม่มีข้อมูลนี้)
  const { data: authList, error: authError } = await supabaseAdmin.auth.admin.listUsers({ perPage: 1000 });
  if (authError) {
    console.error('ADMIN LIST AUTH USERS ERROR:', authError.message);
  }
  const bannedMap = new Map((authList?.users || []).map((u) => [u.id, u.banned_until]));
  const lastSignInMap = new Map((authList?.users || []).map((u) => [u.id, u.last_sign_in_at]));

  const merged = data.map((u) => ({
    ...u,
    banned_until: bannedMap.get(u.user_id) || null,
    last_sign_in_at: lastSignInMap.get(u.user_id) || null,
  }));

  res.json({ data: merged });
});

// GET /api/admin/users/:userId — รายละเอียด + ฟาร์มที่เป็นสมาชิกอยู่
router.get('/users/:userId', async (req, res) => {
  const { userId } = req.params;

  const [{ data: user, error: userError }, { data: memberships, error: memberError }] = await Promise.all([
    supabaseAdmin.from('users').select('*').eq('user_id', userId).maybeSingle(),
    supabaseAdmin.from('farm_members').select('role, farms(farm_id, farm_name)').eq('user_id', userId),
  ]);

  if (userError || !user) {
    return res.status(404).json({ error: 'ไม่พบผู้ใช้นี้' });
  }
  if (memberError) {
    console.error('ADMIN GET USER FARMS ERROR:', memberError.message);
  }

  res.json({ data: { ...user, farms: memberships || [] } });
});

// PATCH /api/admin/users/:userId/disable — ระงับบัญชี (ban ผ่าน Supabase Auth)
router.patch('/users/:userId/disable', async (req, res) => {
  const { userId } = req.params;

  const { data: userRow } = await supabaseAdmin.from('users').select('username').eq('user_id', userId).maybeSingle();

  const { error } = await supabaseAdmin.auth.admin.updateUserById(userId, {
    ban_duration: '876000h', // ~100 ปี เทียบเท่าระงับถาวร ปลดได้ทีหลังด้วย ban_duration: 'none'
  });

  if (error) {
    console.error('ADMIN DISABLE USER ERROR:', error.message);
    return res.status(500).json({ error: 'ระงับบัญชีไม่สำเร็จ' });
  }

  await logAdminAction(req, {
    action: 'disable_user',
    targetType: 'user',
    targetId: userId,
    details: `ระงับบัญชี ${userRow?.username || userId}`,
  });

  res.json({ success: true });
});

// PATCH /api/admin/users/:userId/enable — ปลดระงับ
router.patch('/users/:userId/enable', async (req, res) => {
  const { userId } = req.params;

  const { data: userRow } = await supabaseAdmin.from('users').select('username').eq('user_id', userId).maybeSingle();

  const { error } = await supabaseAdmin.auth.admin.updateUserById(userId, {
    ban_duration: 'none',
  });

  if (error) {
    console.error('ADMIN ENABLE USER ERROR:', error.message);
    return res.status(500).json({ error: 'ปลดระงับบัญชีไม่สำเร็จ' });
  }

  await logAdminAction(req, {
    action: 'enable_user',
    targetType: 'user',
    targetId: userId,
    details: `ปลดระงับบัญชี ${userRow?.username || userId}`,
  });

  res.json({ success: true });
});

// DELETE /api/admin/users/:userId — ลบบัญชี (cascade ลบข้อมูลที่เกี่ยวข้องทั้งหมดอัตโนมัติ)
router.delete('/users/:userId', async (req, res) => {
  const { userId } = req.params;

  const { data: userRow } = await supabaseAdmin.from('users').select('username').eq('user_id', userId).maybeSingle();

  const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);

  if (error) {
    console.error('ADMIN DELETE USER ERROR:', error.message);
    return res.status(500).json({ error: 'ลบบัญชีไม่สำเร็จ' });
  }

  // log หลังลบสำเร็จ — เก็บ target_id ไว้แม้ user จะไม่มีอยู่จริงแล้วก็ตาม (เพื่อ audit trail)
  await logAdminAction(req, {
    action: 'delete_user',
    targetType: 'user',
    targetId: userId,
    details: `ลบบัญชี ${userRow?.username || userId} ถาวร`,
  });

  res.json({ success: true });
});

// ============================================================
// ดูอุปกรณ์ทุกฟาร์ม (สำหรับ diagnose ปัญหา)
// ============================================================

// GET /api/admin/devices
// ส่งผ่าน toDeviceView: ตัด device_secret_hash ออก และเติม is_paired / connection_state / silent_for_minutes
router.get('/devices', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('devices')
    .select('*, farms(farm_name)')
    .order('created_at', { ascending: false });

  if (error) {
    console.error('ADMIN GET DEVICES ERROR:', error.message);
    return res.status(500).json({ error: 'ไม่สามารถโหลดข้อมูลอุปกรณ์ได้' });
  }

  // หาเจ้าของ (role='owner') ของแต่ละฟาร์มที่เกี่ยวข้อง เพื่อให้แอดมินติดต่อได้เร็วเวลามีปัญหา
  const farmIds = [...new Set(data.map((d) => d.farm_id).filter(Boolean))];
  let ownerMap = new Map();

  if (farmIds.length > 0) {
    const { data: owners, error: ownerError } = await supabaseAdmin
      .from('farm_members')
      .select('farm_id, users(username, email)')
      .eq('role', 'owner')
      .in('farm_id', farmIds);

    if (ownerError) {
      console.error('ADMIN GET FARM OWNERS ERROR:', ownerError.message);
    } else {
      ownerMap = new Map(owners.map((o) => [o.farm_id, o.users]));
    }
  }

  const merged = data.map((d) => ({ ...toDeviceView(d), owner: ownerMap.get(d.farm_id) || null }));

  res.json({ data: merged });
});

// PATCH /api/admin/devices/:deviceId — เปลี่ยนสถานะ (เช่น เป็น maintenance)
router.patch('/devices/:deviceId', async (req, res) => {
  const { deviceId } = req.params;
  const { status } = req.body;

  if (!ADMIN_SETTABLE_STATUSES.includes(status)) {
    return res.status(400).json({ error: 'สถานะไม่ถูกต้อง (active / inactive / maintenance)' });
  }

  const { data: existing } = await supabaseAdmin
    .from('devices')
    .select('device_secret_hash')
    .eq('device_id', deviceId)
    .maybeSingle();

  if (!existing) return res.status(404).json({ error: 'ไม่พบอุปกรณ์นี้' });

  // อุปกรณ์ที่ยังไม่เคย pair ไม่มี secret จึงตั้งเป็น active ไม่ได้
  if (status === 'active' && !existing.device_secret_hash) {
    return res.status(400).json({ error: 'อุปกรณ์ยังไม่ได้เชื่อมต่อ (pair) จึงตั้งเป็นใช้งานไม่ได้' });
  }

  const { data, error } = await supabaseAdmin
    .from('devices')
    .update({ status })
    .eq('device_id', deviceId)
    .select()
    .single();

  if (error) {
    console.error('ADMIN UPDATE DEVICE ERROR:', error.message);
    return res.status(500).json({ error: 'แก้ไขไม่สำเร็จ' });
  }

  await logAdminAction(req, {
    action: 'update_device_status',
    targetType: 'device',
    targetId: deviceId,
    details: `เปลี่ยนสถานะอุปกรณ์ "${data.name}" เป็น ${status}`,
  });

  res.json({ data: toDeviceView(data) });
});

// POST /api/admin/devices/:deviceId/reset
// ล้าง secret ทิ้ง (กลับเป็น pending) ให้ ESP32 ไปขอ pair ใหม่ได้เลย
// ใช้ตอนอุปกรณ์ทำ secret หาย (เช่น factory reset) โดยไม่ต้องลบ/สร้างแถวใหม่
router.post('/devices/:deviceId/reset', async (req, res) => {
  const { deviceId } = req.params;

  const { data, error } = await supabaseAdmin
    .from('devices')
    .update({ device_secret_hash: null, status: 'pending', paired_at: null })
    .eq('device_id', deviceId)
    .select()
    .single();

  if (error) {
    console.error('ADMIN RESET DEVICE ERROR:', error.message);
    return res.status(500).json({ error: 'รีเซ็ตอุปกรณ์ไม่สำเร็จ' });
  }

  await logAdminAction(req, {
    action: 'reset_device',
    targetType: 'device',
    targetId: deviceId,
    details: `รีเซ็ตอุปกรณ์ "${data.name}" (ล้าง secret ให้ pair ใหม่)`,
  });

  res.json({ data: toDeviceView(data) });
});

// GET /api/admin/devices/:deviceId/latest-sensor-data — ดูค่า sensor ล่าสุดของอุปกรณ์นี้โดยตรง
router.get('/devices/:deviceId/latest-sensor-data', async (req, res) => {
  const { deviceId } = req.params;

  const { data, error } = await supabaseAdmin
    .from('sensor_data')
    .select('*')
    .eq('device_id', deviceId)
    .order('sensor_timestamp', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error('ADMIN GET LATEST SENSOR DATA ERROR:', error.message);
    return res.status(500).json({ error: 'ไม่สามารถโหลดข้อมูลได้' });
  }

  res.json({ data: data || null });
});

// GET /api/admin/unregistered-devices
// MAC ที่ ESP32 พยายาม pair เข้ามาแต่ยังไม่มีใครลงทะเบียน (พิมพ์ MAC ผิด/จำ MAC ไม่ได้)
// แอดมินดูแล้วแจ้งเกษตรกรให้ลงทะเบียน MAC นี้ในแอป
router.get('/unregistered-devices', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('unregistered_pair_attempts')
    .select('*')
    .order('last_seen_at', { ascending: false });

  if (error) {
    console.error('ADMIN GET UNREGISTERED DEVICES ERROR:', error.message);
    return res.status(500).json({ error: 'ไม่สามารถโหลดข้อมูลได้' });
  }

  res.json({ data });
});

// GET /api/admin/farms — รายชื่อฟาร์มทั้งหมด (สำหรับ filter dropdown)
router.get('/farms', async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('farms')
    .select('farm_id, farm_name')
    .order('farm_name', { ascending: true });

  if (error) {
    console.error('ADMIN GET FARMS ERROR:', error.message);
    return res.status(500).json({ error: 'ไม่สามารถโหลดรายชื่อฟาร์มได้' });
  }

  res.json({ data });
});

// ============================================================
// Log การแจ้งเตือนทุกฟาร์ม (system-wide) — รองรับ filter ตามฟาร์ม/หมวดหมู่
// ============================================================

// GET /api/admin/notifications?limit=&farmId=&category=
router.get('/notifications', async (req, res) => {
  const { limit, farmId, category } = req.query;

  let query = supabaseAdmin
    .from('notifications')
    .select('*, farms(farm_name)')
    .order('created_at', { ascending: false });

  if (farmId) query = query.eq('farm_id', farmId);
  if (category) query = query.eq('category', category);
  if (limit) query = query.limit(parseInt(limit, 10));

  const { data, error } = await query;

  if (error) {
    console.error('ADMIN GET NOTIFICATIONS ERROR:', error.message);
    return res.status(500).json({ error: 'ไม่สามารถโหลดการแจ้งเตือนได้' });
  }

  res.json({ data });
});

// ============================================================
// Audit Log ของแอดมิน — ใครทำอะไร กับอะไร เมื่อไหร่
// ============================================================

// GET /api/admin/audit-log?limit=
router.get('/audit-log', async (req, res) => {
  const { limit } = req.query;

  let query = supabaseAdmin
    .from('admin_audit_log')
    .select('*, users(username, email)')
    .order('created_at', { ascending: false });

  if (limit) query = query.limit(parseInt(limit, 10));

  const { data, error } = await query;

  if (error) {
    console.error('ADMIN GET AUDIT LOG ERROR:', error.message);
    return res.status(500).json({ error: 'ไม่สามารถโหลด audit log ได้' });
  }

  res.json({ data });
});

// ============================================================
// ภาพรวมระบบ (สำหรับหน้า dashboard แรกเข้า)
// ============================================================

// GET /api/admin/overview
router.get('/overview', async (req, res) => {
  const [
    { count: userCount },
    { count: farmCount },
    { count: deviceCount },
    { count: activeDeviceCount },
    { count: unreadNotificationCount },
    { data: activeDevices },
  ] = await Promise.all([
    supabaseAdmin.from('users').select('*', { count: 'exact', head: true }),
    supabaseAdmin.from('farms').select('*', { count: 'exact', head: true }),
    supabaseAdmin.from('devices').select('*', { count: 'exact', head: true }),
    supabaseAdmin.from('devices').select('*', { count: 'exact', head: true }).eq('status', 'active'),
    supabaseAdmin.from('notifications').select('*', { count: 'exact', head: true }).eq('is_read', false),
    supabaseAdmin
      .from('devices')
      .select('device_id, name, status, last_seen_at, paired_at, updated_at, farms(farm_name)')
      .eq('status', 'active'),
  ]);

  // อุปกรณ์ที่สถานะบอกว่า "เชื่อมต่อแล้ว" แต่ไม่ส่งข้อมูลเกินเกณฑ์ (ค่าเริ่มต้น ~2 ชม. ปรับได้ผ่าน .env)
  // status ในตารางไม่ได้อัปเดตอัตโนมัติตามความเงียบ จึงคำนวณจากเวลาล่าสุดด้วย getConnectionState
  const silentDevices = (activeDevices || [])
    .map((d) => ({ d, health: getConnectionState(d) }))
    .filter(({ health }) => health.state === 'silent')
    .map(({ d, health }) => ({
      deviceId: d.device_id,
      name: d.name,
      farmName: d.farms?.farm_name,
      lastSeenAt: d.last_seen_at,
      silentForMinutes: health.silentForMinutes,
    }));

  res.json({
    data: {
      userCount: userCount || 0,
      farmCount: farmCount || 0,
      deviceCount: deviceCount || 0,
      activeDeviceCount: activeDeviceCount || 0,
      unreadNotificationCount: unreadNotificationCount || 0,
      silentDevices,
    },
  });
});

export default router;