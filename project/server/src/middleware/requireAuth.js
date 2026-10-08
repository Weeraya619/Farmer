import { supabaseAdmin } from '../supabaseClient.js';

/// เช็คว่า request มี access token ถูกต้องไหม
/// ถ้าผ่าน จะแนบ req.userId ไว้ให้ route ถัดไปใช้
export async function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  const token = authHeader?.split('Bearer ')[1];

  if (!token) {
    return res.status(401).json({ error: 'ไม่มี token กรุณาเข้าสู่ระบบ' });
  }

  const { data, error } = await supabaseAdmin.auth.getUser(token);

  if (error || !data.user) {
    return res.status(401).json({ error: 'token ไม่ถูกต้องหรือหมดอายุ' });
  }

  req.userId = data.user.id;
  next();
}
