import { Router } from 'express';
import { supabaseAdmin } from '../supabaseClient.js';
import { requireAuth } from '../middleware/requireAuth.js';

const router = Router();

// GET /api/farms/me — ฟาร์มทั้งหมดที่ user คนนี้เป็นสมาชิก
router.get('/me', requireAuth, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('farm_members')
    .select('role, farms(*)')
    .eq('user_id', req.userId);

  if (error) {
    console.error('GET FARMS ERROR:', error.message);
    return res.status(500).json({ error: 'ไม่สามารถโหลดข้อมูลฟาร์มได้' });
  }

  const farms = data.map((row) => ({ ...row.farms, role: row.role }));
  res.json({ data: farms });
});

// POST /api/farms — สร้างฟาร์มใหม่ ผู้สร้างกลายเป็น owner อัตโนมัติ
router.post('/', requireAuth, async (req, res) => {
  const { farmName } = req.body;

  if (!farmName || !farmName.trim()) {
    return res.status(400).json({ error: 'กรุณากรอกชื่อฟาร์ม' });
  }

  const { data: farm, error: farmError } = await supabaseAdmin
    .from('farms')
    .insert({ farm_name: farmName.trim() })
    .select()
    .single();

  if (farmError) {
    console.error('CREATE FARM ERROR:', farmError.message);
    return res.status(500).json({ error: 'สร้างฟาร์มไม่สำเร็จ' });
  }

  const { error: memberError } = await supabaseAdmin
    .from('farm_members')
    .insert({ farm_id: farm.farm_id, user_id: req.userId, role: 'owner' });

  if (memberError) {
    console.error('ADD FARM MEMBER ERROR:', memberError.message);
    // ฟาร์มสร้างไปแล้วแต่ผูกสมาชิกไม่สำเร็จ — ลบฟาร์มทิ้งกันข้อมูลค้าง
    await supabaseAdmin.from('farms').delete().eq('farm_id', farm.farm_id);
    return res.status(500).json({ error: 'สร้างฟาร์มไม่สำเร็จ' });
  }

  res.json({ data: { ...farm, role: 'owner' } });
});

export default router;