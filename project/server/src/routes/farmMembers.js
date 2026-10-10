import { Router } from 'express';
import { supabaseAdmin } from '../supabaseClient.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireFarmMember } from '../middleware/requireFarmMember.js';
import { requirePermission } from '../middleware/requirePermission.js';

const router = Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ONLY_OWNER = 'เฉพาะเจ้าของฟาร์มเท่านั้น';
const ONLY_PRIMARY = 'เฉพาะเจ้าของหลักของฟาร์มเท่านั้น';

async function getPrimaryOwnerId(farmId) {
    const { data } = await supabaseAdmin
        .from('farms')
        .select('created_by')
        .eq('farm_id', farmId)
        .maybeSingle();
    return data?.created_by || null;
}

// เป็นเจ้าของหลักไหม — ถ้าฟาร์มไม่มีเจ้าของหลัก (created_by ว่าง เช่นบัญชีเดิมถูกแอดมินลบ)
// ให้ owner คนไหนก็ได้ทำแทน กันฟาร์มค้างจนไม่มีใครเลื่อน/ลดขั้นได้
function canActAsPrimary(req, primaryId) {
    return req.farmPerms.isPrimaryOwner || (!primaryId && req.farmPerms.isOwner);
}

// GET /api/farms/:farmId/members — รายชื่อสมาชิก (owner เท่านั้น)
router.get(
    '/farms/:farmId/members',
    requireAuth,
    requireFarmMember(),
    requirePermission('canManageMembers', ONLY_OWNER),
    async (req, res) => {
        const { farmId } = req.params;

        const [{ data, error }, primaryId] = await Promise.all([
            supabaseAdmin
                .from('farm_members')
                .select('user_id, role, added_at, users(username)')
                .eq('farm_id', farmId)
                .order('added_at', { ascending: true }),
            getPrimaryOwnerId(farmId),
        ]);

        if (error) {
            console.error('GET MEMBERS ERROR:', error.message);
            return res.status(500).json({ error: 'ไม่สามารถโหลดรายชื่อสมาชิกได้' });
        }

        const members = data.map((m) => ({
            userId: m.user_id,
            username: m.users?.username || '-',
            role: m.role,
            isPrimaryOwner: m.role === 'owner' && m.user_id === primaryId,
            addedAt: m.added_at,
        }));

        res.json({ data: members });
    }
);

// PATCH /api/farms/:farmId/settings — owner ตั้งสวิตช์สิทธิ์ของ worker (ทั้งฟาร์ม ไม่แยกรายคน)
// body (ส่งเฉพาะที่จะเปลี่ยนก็ได้): { workerFinanceEnabled, workerBuyCowEnabled, workerSellCowEnabled }
router.patch(
    '/farms/:farmId/settings',
    requireAuth,
    requireFarmMember(),
    requirePermission('isOwner', ONLY_OWNER),
    async (req, res) => {
        const { farmId } = req.params;

        const columns = {
            workerFinanceEnabled: 'worker_finance_enabled',
            workerBuyCowEnabled: 'worker_buy_cow_enabled',
            workerSellCowEnabled: 'worker_sell_cow_enabled',
        };

        const updates = {};
        for (const [key, column] of Object.entries(columns)) {
            const value = req.body?.[key];
            if (value === undefined) continue;
            if (typeof value !== 'boolean') {
                return res.status(400).json({ error: `ค่า ${key} ต้องเป็น true หรือ false` });
            }
            updates[column] = value;
        }

        if (Object.keys(updates).length === 0) {
            return res.status(400).json({ error: 'ไม่มีข้อมูลที่จะแก้ไข' });
        }

        const { data, error } = await supabaseAdmin
            .from('farms')
            .update(updates)
            .eq('farm_id', farmId)
            .select('farm_id, worker_finance_enabled, worker_buy_cow_enabled, worker_sell_cow_enabled')
            .single();

        if (error) {
            console.error('UPDATE FARM SETTINGS ERROR:', error.message);
            return res.status(500).json({ error: 'บันทึกการตั้งค่าไม่สำเร็จ' });
        }

        res.json({ data });
    }
);

// PATCH /api/farms/:farmId/members/:userId/role — เลื่อน worker เป็น co-owner / ลด co-owner เป็น worker
// body: { role: 'owner' | 'worker' } — เฉพาะเจ้าของหลัก
router.patch('/farms/:farmId/members/:userId/role', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId, userId } = req.params;
    const { role } = req.body || {};

    if (!['owner', 'worker'].includes(role)) {
        return res.status(400).json({ error: 'บทบาทไม่ถูกต้อง (owner / worker)' });
    }
    if (!UUID_RE.test(userId)) {
        return res.status(404).json({ error: 'ไม่พบสมาชิกคนนี้ในฟาร์ม' });
    }

    const primaryId = await getPrimaryOwnerId(farmId);
    if (!canActAsPrimary(req, primaryId)) {
        return res.status(403).json({ error: ONLY_PRIMARY });
    }
    if (userId === primaryId) {
        return res.status(400).json({ error: 'ไม่สามารถเปลี่ยนบทบาทของเจ้าของหลักได้' });
    }
    if (userId === req.userId && role === 'worker') {
        return res.status(400).json({ error: 'ไม่สามารถลดบทบาทของตัวเองได้' });
    }

    const { data: target } = await supabaseAdmin
        .from('farm_members')
        .select('role')
        .eq('farm_id', farmId)
        .eq('user_id', userId)
        .maybeSingle();

    if (!target) {
        return res.status(404).json({ error: 'ไม่พบสมาชิกคนนี้ในฟาร์ม' });
    }
    if (target.role === role) {
        return res.json({ data: { userId, role } });
    }

    const { error } = await supabaseAdmin
        .from('farm_members')
        .update({ role })
        .eq('farm_id', farmId)
        .eq('user_id', userId);

    if (error) {
        console.error('UPDATE MEMBER ROLE ERROR:', error.message);
        return res.status(500).json({ error: 'เปลี่ยนบทบาทไม่สำเร็จ' });
    }

    res.json({ data: { userId, role } });
});

// DELETE /api/farms/:farmId/members/:userId — เอาสมาชิกออก
// owner เอา worker ออกได้ / เอา co-owner ออกได้เฉพาะเจ้าของหลัก / เอาเจ้าของหลักออกไม่ได้เลย
router.delete(
    '/farms/:farmId/members/:userId',
    requireAuth,
    requireFarmMember(),
    requirePermission('canManageMembers', ONLY_OWNER),
    async (req, res) => {
        const { farmId, userId } = req.params;

        if (!UUID_RE.test(userId)) {
            return res.status(404).json({ error: 'ไม่พบสมาชิกคนนี้ในฟาร์ม' });
        }
        if (userId === req.userId) {
            return res.status(400).json({ error: 'หากต้องการออกจากฟาร์ม ให้ใช้ปุ่ม "ออกจากฟาร์ม"' });
        }

        const primaryId = await getPrimaryOwnerId(farmId);
        if (userId === primaryId) {
            return res.status(403).json({ error: 'ไม่สามารถเอาเจ้าของหลักออกจากฟาร์มได้' });
        }

        const { data: target } = await supabaseAdmin
            .from('farm_members')
            .select('role')
            .eq('farm_id', farmId)
            .eq('user_id', userId)
            .maybeSingle();

        if (!target) {
            return res.status(404).json({ error: 'ไม่พบสมาชิกคนนี้ในฟาร์ม' });
        }
        if (target.role === 'owner' && !canActAsPrimary(req, primaryId)) {
            return res.status(403).json({ error: ONLY_PRIMARY });
        }

        const { error } = await supabaseAdmin
            .from('farm_members')
            .delete()
            .eq('farm_id', farmId)
            .eq('user_id', userId);

        if (error) {
            console.error('REMOVE MEMBER ERROR:', error.message);
            return res.status(500).json({ error: 'เอาสมาชิกออกไม่สำเร็จ' });
        }

        res.json({ success: true });
    }
);

// POST /api/farms/:farmId/leave — ออกจากฟาร์มเอง (สมาชิกทุกคน ยกเว้นเจ้าของหลัก)
router.post('/farms/:farmId/leave', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId } = req.params;

    const primaryId = await getPrimaryOwnerId(farmId);
    if (req.userId === primaryId) {
        return res.status(400).json({ error: 'เจ้าของหลักออกจากฟาร์มไม่ได้' });
    }

    // กันฟาร์มไม่มี owner เหลือเลย (กรณีฟาร์มไม่มีเจ้าของหลัก)
    if (req.farmRole === 'owner') {
        const { count } = await supabaseAdmin
            .from('farm_members')
            .select('user_id', { count: 'exact', head: true })
            .eq('farm_id', farmId)
            .eq('role', 'owner');

        if ((count || 0) <= 1) {
            return res.status(400).json({ error: 'ฟาร์มต้องมีเจ้าของอย่างน้อย 1 คน' });
        }
    }

    const { error } = await supabaseAdmin
        .from('farm_members')
        .delete()
        .eq('farm_id', farmId)
        .eq('user_id', req.userId);

    if (error) {
        console.error('LEAVE FARM ERROR:', error.message);
        return res.status(500).json({ error: 'ออกจากฟาร์มไม่สำเร็จ' });
    }

    res.json({ success: true });
});

export default router;