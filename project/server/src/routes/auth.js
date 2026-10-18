import { Router } from 'express';
import { supabasePublic, supabaseAdmin } from '../supabaseClient.js';

const router = Router();

// POST /api/auth/signup
router.post('/signup', async (req, res) => {
  const { email, password, username } = req.body;

  if (!email || !password || !username) {
    return res.status(400).json({ error: 'กรุณากรอกข้อมูลให้ครบถ้วน' });
  }

  const { data, error } = await supabasePublic.auth.signUp({
    email,
    password,
    options: { data: { username } },
  });

  if (error) {
    console.error('SIGNUP ERROR:', error.message);
    return res.status(400).json({ error: translateAuthError(error.message) });
  }

  res.json({ user: { id: data.user?.id, email: data.user?.email } });
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  let { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'กรุณากรอกข้อมูลให้ครบถ้วน' });
  }

  // ถ้าไม่ใช่รูปแบบ email (เช่น พิมพ์ username มา) ให้หา email จริงจาก username ก่อน
  // Supabase Auth รู้จักแค่ email เท่านั้น ไม่มีแนวคิด username ในตัวเอง
  if (!email.includes('@')) {
    const { data: userRow, error: lookupError } = await supabaseAdmin
      .from('users')
      .select('email')
      .eq('username', email)
      .maybeSingle();

    if (lookupError || !userRow) {
      // ไม่พบ username นี้ — ตอบข้อความเดียวกับรหัสผ่านผิด กันคนแอบไล่เดาว่า username ไหนมีอยู่จริง
      return res.status(401).json({ error: 'อีเมลหรือรหัสผ่านไม่ถูกต้อง' });
    }

    email = userRow.email;
  }

  const { data, error } = await supabasePublic.auth.signInWithPassword({ email, password });

  if (error) {
    console.error('LOGIN ERROR:', error.message);
    return res.status(401).json({ error: translateAuthError(error.message) });
  }

  res.json({
    accessToken: data.session.access_token,
    refreshToken: data.session.refresh_token,
    user: {
      id: data.user.id,
      email: data.user.email,
      // username ถูกเก็บใน metadata ตอน signup (options.data)
      username: data.user.user_metadata?.username ?? null,
    },
  });
});

// POST /api/auth/change-password
// ต้องส่ง Authorization: Bearer <accessToken> และ body { currentPassword, newPassword }
router.post('/change-password', async (req, res) => {
  const { currentPassword, newPassword } = req.body;

  if (!currentPassword || !newPassword) {
    return res.status(400).json({ error: 'กรุณากรอกข้อมูลให้ครบถ้วน' });
  }
  if (newPassword.length < 6) {
    return res.status(400).json({ error: 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร' });
  }

  // 1) ตรวจ token ว่าเป็นใคร (ไม่พึ่ง middleware ตัวอื่น)
  const token = (req.headers.authorization || '').replace('Bearer ', '');
  if (!token) {
    return res.status(401).json({ error: 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่' });
  }

  const { data: userData, error: tokenError } = await supabaseAdmin.auth.getUser(token);
  if (tokenError || !userData?.user) {
    return res.status(401).json({ error: 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่' });
  }
  const user = userData.user;

  // 2) ตรวจรหัสผ่านปัจจุบันด้วยการลอง login ด้วยอีเมลของ user คนนี้
  const { error: verifyError } = await supabasePublic.auth.signInWithPassword({
    email: user.email,
    password: currentPassword,
  });
  if (verifyError) {
    return res.status(400).json({ error: 'รหัสผ่านปัจจุบันไม่ถูกต้อง' });
  }

  // 3) รหัสปัจจุบันถูกต้อง ค่อยเปลี่ยนรหัสผ่าน
  const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
    password: newPassword,
  });
  if (updateError) {
    console.error('CHANGE PASSWORD ERROR:', updateError.message);
    return res.status(400).json({ error: translateAuthError(updateError.message) });
  }

  res.json({ success: true });
});

// POST /api/auth/logout
router.post('/logout', async (req, res) => {
  // ฝั่ง client ลบ token เองอยู่แล้ว endpoint นี้แค่ตอบรับให้ครบ flow
  res.json({ success: true });
});

function translateAuthError(message) {
  if (message.includes('Invalid login credentials')) {
    return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
  }
  if (message.includes('Email not confirmed')) {
    return 'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ';
  }
  if (message.includes('User already registered')) {
    return 'อีเมลนี้ถูกใช้สมัครสมาชิกไปแล้ว';
  }
  if (message.includes('Password should be at least')) {
    return 'รหัสผ่านสั้นเกินไป ต้องมีอย่างน้อย 6 ตัวอักษร';
  }
  if (message.includes('should be different from the old password')) {
    return 'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านเดิม';
  }
  if (message.includes('Unable to validate email')) {
    return 'รูปแบบอีเมลไม่ถูกต้อง';
  }
  return 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
}

export default router;