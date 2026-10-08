import { Router } from 'express';
import { supabaseAdmin } from '../supabaseClient.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireFarmMember } from '../middleware/requireFarmMember.js';

const router = Router();

// GET /api/farms/:farmId/finances?from=&to=
router.get('/farms/:farmId/finances', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId } = req.params;
    const { from, to } = req.query;

    let query = supabaseAdmin
        .from('finances')
        .select('*')
        .eq('farm_id', farmId)
        .order('record_date', { ascending: false });

    if (from) query = query.gte('record_date', from);
    if (to) query = query.lte('record_date', to);

    const { data, error } = await query;

    if (error) {
        console.error('GET FINANCES ERROR:', error.message);
        return res.status(500).json({ error: 'ไม่สามารถโหลดข้อมูลการเงินได้' });
    }

    res.json({ data });
});

// POST /api/farms/:farmId/finance-entries — บันทึกหลายรายการทีเดียว (ปุ่ม + เพิ่มรายการ)
// body: { recordDate, category: 'feed' | 'medicine', entries: [{ note, amount }, ...] }
router.post('/farms/:farmId/finance-entries', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId } = req.params;
    const { recordDate, category, entries } = req.body;

    if (!['feed', 'medicine'].includes(category)) {
        return res.status(400).json({ error: 'หมวดหมู่ไม่ถูกต้อง' });
    }
    if (!Array.isArray(entries) || entries.length === 0) {
        return res.status(400).json({ error: 'กรุณาระบุรายการอย่างน้อย 1 รายการ' });
    }
    for (const e of entries) {
        if (!e.note || !e.note.trim()) {
            return res.status(400).json({ error: 'กรุณากรอกรายละเอียดให้ครบทุกรายการ' });
        }
        if (!e.amount || e.amount <= 0) {
            return res.status(400).json({ error: 'กรุณากรอกจำนวนเงินให้ถูกต้องทุกรายการ' });
        }
    }

    const date = recordDate || new Date().toISOString().slice(0, 10);
    const rows = entries.map((e) => ({
        farm_id: farmId,
        record_date: date,
        note: e.note.trim(),
        feed: category === 'feed' ? e.amount : 0,
        medicine: category === 'medicine' ? e.amount : 0,
    }));

    const { data, error } = await supabaseAdmin.from('finances').insert(rows).select();

    if (error) {
        console.error('CREATE FINANCE ENTRIES ERROR:', error.message);
        return res.status(500).json({ error: 'บันทึกรายการไม่สำเร็จ' });
    }

    res.json({ data });
});

// POST /api/farms/:farmId/finances
router.post('/farms/:farmId/finances', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId } = req.params;
    const { recordDate, cowPurchase, feed, medicine, cowSale } = req.body;

    const { data, error } = await supabaseAdmin
        .from('finances')
        .insert({
            farm_id: farmId,
            record_date: recordDate || new Date().toISOString().slice(0, 10),
            cow_purchase: cowPurchase || 0,
            feed: feed || 0,
            medicine: medicine || 0,
            cow_sale: cowSale || 0,
        })
        .select()
        .single();

    if (error) {
        console.error('CREATE FINANCE ERROR:', error.message);
        return res.status(500).json({ error: 'บันทึกรายการไม่สำเร็จ' });
    }

    res.json({ data });
});

// PATCH /api/finances/:financeId
router.patch('/finances/:financeId', requireAuth, async (req, res) => {
    const { financeId } = req.params;

    // เช็คสิทธิ์: หา farm_id ของรายการนี้ก่อน แล้วเช็คว่า user เป็นสมาชิกฟาร์มนั้นไหม
    const { data: existing } = await supabaseAdmin
        .from('finances')
        .select('farm_id')
        .eq('finance_id', financeId)
        .maybeSingle();

    if (!existing) {
        return res.status(404).json({ error: 'ไม่พบรายการนี้' });
    }

    const { data: membership } = await supabaseAdmin
        .from('farm_members')
        .select('role')
        .eq('farm_id', existing.farm_id)
        .eq('user_id', req.userId)
        .maybeSingle();

    if (!membership) {
        return res.status(403).json({ error: 'ไม่มีสิทธิ์แก้ไขรายการนี้' });
    }

    const { recordDate, cowPurchase, feed, medicine, cowSale } = req.body;
    const updates = {};
    if (recordDate !== undefined) updates.record_date = recordDate;
    if (cowPurchase !== undefined) updates.cow_purchase = cowPurchase;
    if (feed !== undefined) updates.feed = feed;
    if (medicine !== undefined) updates.medicine = medicine;
    if (cowSale !== undefined) updates.cow_sale = cowSale;

    const { data, error } = await supabaseAdmin
        .from('finances')
        .update(updates)
        .eq('finance_id', financeId)
        .select()
        .single();

    if (error) {
        console.error('UPDATE FINANCE ERROR:', error.message);
        return res.status(500).json({ error: 'แก้ไขรายการไม่สำเร็จ' });
    }

    res.json({ data });
});

// DELETE /api/finances/:financeId
router.delete('/finances/:financeId', requireAuth, async (req, res) => {
    const { financeId } = req.params;

    const { data: existing } = await supabaseAdmin
        .from('finances')
        .select('farm_id')
        .eq('finance_id', financeId)
        .maybeSingle();

    if (!existing) {
        return res.status(404).json({ error: 'ไม่พบรายการนี้' });
    }

    const { data: membership } = await supabaseAdmin
        .from('farm_members')
        .select('role')
        .eq('farm_id', existing.farm_id)
        .eq('user_id', req.userId)
        .maybeSingle();

    if (!membership) {
        return res.status(403).json({ error: 'ไม่มีสิทธิ์ลบรายการนี้' });
    }

    const { error } = await supabaseAdmin.from('finances').delete().eq('finance_id', financeId);

    if (error) {
        console.error('DELETE FINANCE ERROR:', error.message);
        return res.status(500).json({ error: 'ลบรายการไม่สำเร็จ' });
    }

    res.json({ success: true });
});

export default router;