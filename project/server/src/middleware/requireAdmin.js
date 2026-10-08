import { supabaseAdmin } from '../supabaseClient.js';

/// เช็คว่า user ที่ login อยู่เป็น admin จริงไหม (ต้องรัน requireAuth มาก่อนเสมอ)
/// ใช้แบบ: router.get('/admin/xxx', requireAuth, requireAdmin, handler)
export async function requireAdmin(req, res, next) {
  const { data, error } = await supabaseAdmin
    .from('users')
    .select('is_admin')
    .eq('user_id', req.userId)
    .maybeSingle();

  if (error || !data || !data.is_admin) {
    return res.status(403).json({ error: 'ต้องเป็นแอดมินเท่านั้นถึงจะเข้าถึงส่วนนี้ได้' });
  }

  next();
}
