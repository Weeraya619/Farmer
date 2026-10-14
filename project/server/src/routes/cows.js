import { Router } from 'express';
import { supabaseAdmin } from '../supabaseClient.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireFarmMember } from '../middleware/requireFarmMember.js';
import { requirePermission } from '../middleware/requirePermission.js';
import { getFarmAccess } from '../utils/farmaccess.js';

const router = Router();

// GET /api/farms/:farmId/cows?availableForSale=true
// availableForSale กรองเฉพาะวัวที่ยังไม่ขาย (สำหรับ dropdown หน้าขายวัว)
// รวมวัวที่ตายแล้วด้วย เพราะขายซากได้ — ฝั่งแอปดูจาก death_date เพื่อติดแท็ก "ตายแล้ว"
// เรียงจากใหม่สุดก่อนเสมอ (created_at desc)
// worker ที่ไม่มีสิทธิ์การเงินจะไม่ได้รับราคาซื้อ/ขาย (ตัดที่ backend ไม่ใช่แค่ซ่อนในแอป)
router.get('/farms/:farmId/cows', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId } = req.params;
    let query = supabaseAdmin.from('cows').select('*').eq('farm_id', farmId);

    if (req.query.availableForSale === 'true') {
        query = query.is('sale_date', null);
    }

    const { data, error } = await query.order('created_at', { ascending: false });

    if (error) {
        console.error('GET COWS ERROR:', error.message);
        return res.status(500).json({ error: 'ไม่สามารถโหลดข้อมูลวัวได้' });
    }

    const rows = req.farmPerms.canFinance
        ? data
        : data.map(({ purchase_price, sale_price, ...rest }) => rest);

    res.json({ data: rows });
});

// POST /api/farms/:farmId/cows — บันทึกวัวที่มีอยู่แล้ว (ไม่ผูกกับรายจ่าย จึงไม่ต้องใช้สิทธิ์การเงิน)
// body: { cows: [{ gender, pregnancyStatus, nickname }, ...] }
router.post('/farms/:farmId/cows', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId } = req.params;
    const { cows } = req.body;

    if (!Array.isArray(cows) || cows.length === 0) {
        return res.status(400).json({ error: 'กรุณาระบุข้อมูลวัวอย่างน้อย 1 ตัว' });
    }

    const rows = cows.map((c) => ({
        farm_id: farmId,
        gender: c.gender,
        pregnancy_status: c.pregnancyStatus,
        nickname: c.nickname || null,
        origin_type: 'มีอยู่แล้ว',
    }));

    const { data, error } = await supabaseAdmin.from('cows').insert(rows).select();

    if (error) {
        console.error('CREATE COWS ERROR:', error.message);
        return res.status(500).json({ error: 'บันทึกข้อมูลวัวไม่สำเร็จ' });
    }

    res.json({ data });
});

// POST /api/farms/:farmId/cow-purchases — เขียน finances + cows พร้อมกัน (atomic)
// body: { recordDate, totalPrice, cows: [{ gender, pregnancyStatus, nickname }, ...] }
// วัวทุกตัวในคำสั่งเดียวกันนี้จะมี purchase_date เดียวกัน — ใช้วันที่นี้เป็น "เลขล็อต" แทนรหัสตัวเลข
router.post(
    '/farms/:farmId/cow-purchases',
    requireAuth,
    requireFarmMember(),
    requirePermission('canBuyCow', 'ไม่มีสิทธิ์บันทึกการซื้อวัว'),
    async (req, res) => {
        const { farmId } = req.params;
        const { recordDate, totalPrice, cows } = req.body;

        if (!Array.isArray(cows) || cows.length === 0) {
            return res.status(400).json({ error: 'กรุณาระบุข้อมูลวัวอย่างน้อย 1 ตัว' });
        }
        if (!totalPrice || totalPrice <= 0) {
            return res.status(400).json({ error: 'กรุณาระบุจำนวนเงินที่ถูกต้อง' });
        }

        const pricePerCow = Math.round((totalPrice / cows.length) * 100) / 100;
        const date = recordDate || new Date().toISOString().slice(0, 10);

        const { data: finance, error: financeError } = await supabaseAdmin
            .from('finances')
            .insert({ farm_id: farmId, record_date: date, cow_purchase: totalPrice })
            .select()
            .single();

        if (financeError) {
            console.error('CREATE COW-PURCHASE FINANCE ERROR:', financeError.message);
            return res.status(500).json({ error: 'บันทึกรายจ่ายไม่สำเร็จ' });
        }

        const cowRows = cows.map((c) => ({
            farm_id: farmId,
            gender: c.gender,
            pregnancy_status: c.pregnancyStatus,
            nickname: c.nickname || null,
            origin_type: 'ซื้อมาใหม่',
            purchase_date: date,
            purchase_price: pricePerCow,
        }));

        const { data: newCows, error: cowsError } = await supabaseAdmin
            .from('cows')
            .insert(cowRows)
            .select();

        if (cowsError) {
            console.error('CREATE COW-PURCHASE COWS ERROR:', cowsError.message);
            // rollback: ลบรายการรายจ่ายที่สร้างไปแล้ว กันข้อมูลค้างไม่ตรงกัน
            await supabaseAdmin.from('finances').delete().eq('finance_id', finance.finance_id);
            return res.status(500).json({ error: 'บันทึกข้อมูลวัวไม่สำเร็จ กำลังยกเลิกรายการที่บันทึกไปแล้ว' });
        }

        res.json({ data: { finance, cows: newCows } });
    }
);

// POST /api/farms/:farmId/cow-sales — เขียน finances + อัปเดต cows (atomic พร้อม rollback)
// body: { recordDate, totalPrice, cowIds: [...], deadCowIds?: [...], deadTotalPrice? }
//   - cowIds + totalPrice          = วัวที่ยังมีชีวิต (ราคารวมเฉพาะวัวที่ไม่ตาย)
//   - deadCowIds + deadTotalPrice  = วัวที่ตายแล้ว แยกราคา ไม่เอาไปหารรวมกับวัวที่ไม่ตาย
// แต่ละกลุ่มบันทึกเป็นรายรับคนละแถวใน finances และหารราคาต่อตัวภายในกลุ่มของตัวเอง
router.post(
    '/farms/:farmId/cow-sales',
    requireAuth,
    requireFarmMember(),
    requirePermission('canSellCow', 'ไม่มีสิทธิ์บันทึกการขายวัว'),
    async (req, res) => {
        const { farmId } = req.params;
        const { recordDate } = req.body;
        const cowIds = req.body.cowIds ?? [];
        const deadCowIds = req.body.deadCowIds ?? [];
        const totalPrice = Number(req.body.totalPrice) || 0;
        const deadTotalPrice = Number(req.body.deadTotalPrice) || 0;

        if (!Array.isArray(cowIds) || !Array.isArray(deadCowIds)) {
            return res.status(400).json({ error: 'ข้อมูลวัวที่ต้องการขายไม่ถูกต้อง' });
        }
        if (cowIds.length + deadCowIds.length === 0) {
            return res.status(400).json({ error: 'กรุณาเลือกวัวที่ต้องการขายอย่างน้อย 1 ตัว' });
        }
        if (cowIds.length > 0 && totalPrice <= 0) {
            return res.status(400).json({ error: 'กรุณาระบุราคารวมของวัวที่ไม่ตาย' });
        }
        if (deadCowIds.length > 0 && deadTotalPrice <= 0) {
            return res.status(400).json({ error: 'กรุณาระบุราคาขายของวัวที่ตายแล้ว' });
        }

        // ตรวจซ้ำฝั่ง server: วัวต้องอยู่ในฟาร์มนี้ ยังไม่ถูกขาย และอยู่ถูกกลุ่ม (ตาย/ไม่ตาย)
        const allIds = [...cowIds, ...deadCowIds].map(String);
        if (new Set(allIds).size !== allIds.length) {
            return res.status(400).json({ error: 'มีวัวซ้ำในรายการที่เลือก' });
        }

        const { data: found, error: findError } = await supabaseAdmin
            .from('cows')
            .select('cow_id, sale_date, death_date')
            .eq('farm_id', farmId)
            .in('cow_id', allIds);

        if (findError) {
            console.error('CREATE COW-SALE LOOKUP ERROR:', findError.message);
            return res.status(500).json({ error: 'ตรวจสอบข้อมูลวัวไม่สำเร็จ' });
        }

        const byId = new Map(found.map((c) => [String(c.cow_id), c]));
        if (byId.size !== allIds.length) {
            return res.status(400).json({ error: 'ไม่พบข้อมูลวัวบางตัวในฟาร์มนี้' });
        }
        if (allIds.some((id) => byId.get(id).sale_date)) {
            return res.status(400).json({ error: 'มีวัวที่ถูกขายไปแล้ว กรุณารีเฟรชแล้วเลือกใหม่' });
        }
        if (cowIds.some((id) => byId.get(String(id)).death_date)) {
            return res.status(400).json({ error: 'มีวัวที่ตายแล้วอยู่ในกลุ่มวัวที่ไม่ตาย กรุณารีเฟรชแล้วเลือกใหม่' });
        }
        if (deadCowIds.some((id) => !byId.get(String(id)).death_date)) {
            return res.status(400).json({ error: 'มีวัวที่ยังไม่ตายอยู่ในกลุ่มวัวที่ตายแล้ว กรุณารีเฟรชแล้วเลือกใหม่' });
        }

        const date = recordDate || new Date().toISOString().slice(0, 10);

        const groups = [];
        if (cowIds.length > 0) groups.push({ ids: cowIds, total: totalPrice, note: null });
        if (deadCowIds.length > 0) groups.push({ ids: deadCowIds, total: deadTotalPrice, note: 'ขายวัวที่ตายแล้ว' });

        const financeRows = groups.map((g) => ({
            farm_id: farmId,
            record_date: date,
            cow_sale: g.total,
            ...(g.note ? { note: g.note } : {}),
        }));

        const { data: finances, error: financeError } = await supabaseAdmin
            .from('finances')
            .insert(financeRows)
            .select();

        if (financeError) {
            console.error('CREATE COW-SALE FINANCE ERROR:', financeError.message);
            return res.status(500).json({ error: 'บันทึกรายรับไม่สำเร็จ' });
        }

        const soldIds = [];
        const updatedCows = [];

        for (const g of groups) {
            const pricePerCow = Math.round((g.total / g.ids.length) * 100) / 100;
            const { data: updated, error: cowsError } = await supabaseAdmin
                .from('cows')
                .update({ sale_date: date, sale_price: pricePerCow })
                .in('cow_id', g.ids)
                .eq('farm_id', farmId)
                .select();

            if (cowsError) {
                console.error('CREATE COW-SALE UPDATE ERROR:', cowsError.message);
                // rollback: ลบรายรับที่สร้างไปแล้ว และคืนสถานะวัวกลุ่มที่อัปเดตไปแล้ว
                await supabaseAdmin
                    .from('finances')
                    .delete()
                    .in('finance_id', finances.map((f) => f.finance_id));
                if (soldIds.length > 0) {
                    await supabaseAdmin
                        .from('cows')
                        .update({ sale_date: null, sale_price: null })
                        .in('cow_id', soldIds)
                        .eq('farm_id', farmId);
                }
                return res.status(500).json({ error: 'อัปเดตข้อมูลวัวไม่สำเร็จ กำลังยกเลิกรายการที่บันทึกไปแล้ว' });
            }

            soldIds.push(...g.ids);
            updatedCows.push(...updated);
        }

        res.json({ data: { finances, cows: updatedCows } });
    }
);

// PATCH /api/cows/:cowId — แก้ไขชื่อเล่นและสถานะสุขภาพ (ป่วย/ตาย) — สมาชิกทุกคนทำได้
// body: { nickname, healthStatus, isDead }
router.patch('/cows/:cowId', requireAuth, async (req, res) => {
    const { cowId } = req.params;

    const { data: existing } = await supabaseAdmin
        .from('cows')
        .select('farm_id')
        .eq('cow_id', cowId)
        .maybeSingle();

    if (!existing) {
        return res.status(404).json({ error: 'ไม่พบข้อมูลวัวนี้' });
    }

    const access = await getFarmAccess(existing.farm_id, req.userId);
    if (!access) {
        return res.status(403).json({ error: 'ไม่มีสิทธิ์แก้ไขข้อมูลนี้' });
    }

    const { nickname, healthStatus, isDead } = req.body;
    const updates = {};
    if (nickname !== undefined) updates.nickname = nickname;
    if (healthStatus !== undefined) updates.health_status = healthStatus;
    if (isDead !== undefined) {
        updates.death_date = isDead ? new Date().toISOString().slice(0, 10) : null;
    }

    const { data, error } = await supabaseAdmin
        .from('cows')
        .update(updates)
        .eq('cow_id', cowId)
        .select()
        .single();

    if (error) {
        console.error('UPDATE COW ERROR:', error.message);
        return res.status(500).json({ error: 'แก้ไขข้อมูลไม่สำเร็จ' });
    }

    // PATCH นี้ใช้ select ทั้งแถว จึงต้องตัดราคาออกสำหรับ worker ที่ไม่มีสิทธิ์การเงินเช่นกัน
    if (!access.perms.canFinance) {
        const { purchase_price, sale_price, ...rest } = data;
        return res.json({ data: rest });
    }

    res.json({ data });
});

export default router;