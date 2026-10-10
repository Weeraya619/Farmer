import { Router } from 'express';
import { supabaseAdmin } from '../supabaseClient.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { getFarmAccess } from '../utils/farmAccess.js';

const router = Router();

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// GET /api/join-requests/owner-farms?username=xxx
// ขั้นที่ 1 ของคนที่อยากเข้าฟาร์ม: ใส่ username ของ owner → ได้รายชื่อฟาร์มของ owner คนนั้น
// ซ่อนฟาร์มที่ตัวเองเป็นสมาชิกอยู่แล้ว และบอกว่าฟาร์มไหนมีคำขอที่รออยู่ (pending: true)
// ส่งกลับแค่ id กับชื่อฟาร์ม ไม่ส่งข้อมูลอื่น
router.get('/join-requests/owner-farms', requireAuth, async (req, res) => {
    const username = String(req.query.username || '').trim();
    if (!username) {
        return res.status(400).json({ error: 'กรุณากรอกชื่อผู้ใช้ของเจ้าของฟาร์ม' });
    }

    const { data: owner } = await supabaseAdmin
        .from('users')
        .select('user_id')
        .eq('username', username)
        .maybeSingle();

    if (!owner) {
        return res.status(404).json({ error: 'ไม่พบผู้ใช้ชื่อนี้' });
    }

    const { data: ownedRows, error } = await supabaseAdmin
        .from('farm_members')
        .select('farm_id, farms(farm_id, farm_name)')
        .eq('user_id', owner.user_id)
        .eq('role', 'owner');

    if (error) {
        console.error('SEARCH OWNER FARMS ERROR:', error.message);
        return res.status(500).json({ error: 'ค้นหาฟาร์มไม่สำเร็จ' });
    }

    const farmIds = ownedRows.map((r) => r.farm_id);
    if (farmIds.length === 0) {
        return res.json({ data: [] });
    }

    const [{ data: mine }, { data: pending }] = await Promise.all([
        supabaseAdmin
            .from('farm_members')
            .select('farm_id')
            .eq('user_id', req.userId)
            .in('farm_id', farmIds),
        supabaseAdmin
            .from('farm_join_requests')
            .select('farm_id')
            .eq('user_id', req.userId)
            .eq('status', 'pending')
            .in('farm_id', farmIds),
    ]);

    const memberSet = new Set((mine || []).map((r) => r.farm_id));
    const pendingSet = new Set((pending || []).map((r) => r.farm_id));

    const farms = ownedRows
        .filter((r) => !memberSet.has(r.farm_id) && r.farms)
        .map((r) => ({
            farmId: r.farms.farm_id,
            farmName: r.farms.farm_name,
            pending: pendingSet.has(r.farm_id),
        }));

    res.json({ data: farms });
});

// POST /api/join-requests — ส่งคำขอเข้าฟาร์ม (เป็น worker เมื่อ owner อนุมัติ)
// body: { farmId }
router.post('/join-requests', requireAuth, async (req, res) => {
    const { farmId } = req.body || {};

    if (!farmId || !UUID_RE.test(farmId)) {
        return res.status(400).json({ error: 'กรุณาเลือกฟาร์ม' });
    }

    const { data: farm } = await supabaseAdmin
        .from('farms')
        .select('farm_id')
        .eq('farm_id', farmId)
        .maybeSingle();

    if (!farm) {
        return res.status(404).json({ error: 'ไม่พบฟาร์มนี้' });
    }

    const { data: existingMember } = await supabaseAdmin
        .from('farm_members')
        .select('user_id')
        .eq('farm_id', farmId)
        .eq('user_id', req.userId)
        .maybeSingle();

    if (existingMember) {
        return res.status(409).json({ error: 'คุณเป็นสมาชิกฟาร์มนี้อยู่แล้ว' });
    }

    const { data, error } = await supabaseAdmin
        .from('farm_join_requests')
        .insert({ farm_id: farmId, user_id: req.userId })
        .select('request_id, status, created_at')
        .single();

    if (error) {
        if (error.code === '23505') {
            // ชน unique index คำขอที่ยังรออยู่
            return res.status(409).json({ error: 'ส่งคำขอไปแล้ว กรุณารอเจ้าของฟาร์มยืนยัน' });
        }
        console.error('CREATE JOIN REQUEST ERROR:', error.message);
        return res.status(500).json({ error: 'ส่งคำขอไม่สำเร็จ' });
    }

    res.json({ data });
});

// GET /api/join-requests/mine — คำขอที่ตัวเองส่งไป (ดูสถานะ รอ/อนุมัติ/ปฏิเสธ)
router.get('/join-requests/mine', requireAuth, async (req, res) => {
    const { data, error } = await supabaseAdmin
        .from('farm_join_requests')
        .select('request_id, status, created_at, decided_at, farms(farm_name)')
        .eq('user_id', req.userId)
        .order('created_at', { ascending: false })
        .limit(50);

    if (error) {
        console.error('GET MY JOIN REQUESTS ERROR:', error.message);
        return res.status(500).json({ error: 'ไม่สามารถโหลดคำขอได้' });
    }

    res.json({
        data: data.map((r) => ({
            requestId: r.request_id,
            farmName: r.farms?.farm_name || '-',
            status: r.status,
            createdAt: r.created_at,
            decidedAt: r.decided_at,
        })),
    });
});

// GET /api/join-requests/incoming — คำขอที่รออยู่ ของทุกฟาร์มที่ตัวเองเป็น owner
// ใช้ทั้งทำจุดแจ้งเตือนบนหน้าโปรไฟล์ และรายการให้กดอนุมัติ/ปฏิเสธ (Flutter กรองตาม farmId เองได้)
router.get('/join-requests/incoming', requireAuth, async (req, res) => {
    const { data: owned, error: ownedError } = await supabaseAdmin
        .from('farm_members')
        .select('farm_id')
        .eq('user_id', req.userId)
        .eq('role', 'owner');

    if (ownedError) {
        console.error('GET OWNED FARMS ERROR:', ownedError.message);
        return res.status(500).json({ error: 'ไม่สามารถโหลดคำขอได้' });
    }

    const farmIds = (owned || []).map((r) => r.farm_id);
    if (farmIds.length === 0) {
        return res.json({ data: [] });
    }

    // ตารางนี้อ้าง users 2 ทาง (user_id, decided_by) จึงต้องระบุชื่อ FK ให้ชัด ไม่งั้น PostgREST error
    const { data, error } = await supabaseAdmin
        .from('farm_join_requests')
        .select('request_id, farm_id, created_at, users!farm_join_requests_user_id_fkey(username), farms(farm_name)')
        .eq('status', 'pending')
        .in('farm_id', farmIds)
        .order('created_at', { ascending: true });

    if (error) {
        console.error('GET INCOMING JOIN REQUESTS ERROR:', error.message);
        return res.status(500).json({ error: 'ไม่สามารถโหลดคำขอได้' });
    }

    res.json({
        data: data.map((r) => ({
            requestId: r.request_id,
            farmId: r.farm_id,
            farmName: r.farms?.farm_name || '-',
            username: r.users?.username || '-',
            createdAt: r.created_at,
        })),
    });
});

// PATCH /api/join-requests/:requestId — owner อนุมัติ/ปฏิเสธ
// body: { action: 'approve' | 'reject' }
router.patch('/join-requests/:requestId', requireAuth, async (req, res) => {
    const { requestId } = req.params;
    const { action } = req.body || {};

    if (!['approve', 'reject'].includes(action)) {
        return res.status(400).json({ error: 'action ต้องเป็น approve หรือ reject' });
    }
    if (!UUID_RE.test(requestId)) {
        return res.status(404).json({ error: 'ไม่พบคำขอนี้' });
    }

    const { data: request } = await supabaseAdmin
        .from('farm_join_requests')
        .select('request_id, farm_id, user_id, status')
        .eq('request_id', requestId)
        .maybeSingle();

    if (!request) {
        return res.status(404).json({ error: 'ไม่พบคำขอนี้' });
    }

    const access = await getFarmAccess(request.farm_id, req.userId);
    if (!access || !access.perms.canManageMembers) {
        return res.status(403).json({ error: 'เฉพาะเจ้าของฟาร์มเท่านั้นที่ตอบคำขอได้' });
    }
    if (request.status !== 'pending') {
        return res.status(409).json({ error: 'คำขอนี้ถูกดำเนินการไปแล้ว' });
    }

    if (action === 'approve') {
        const { error: memberError } = await supabaseAdmin
            .from('farm_members')
            .insert({ farm_id: request.farm_id, user_id: request.user_id, role: 'worker' });

        // 23505 = เป็นสมาชิกอยู่แล้ว (เช่นกดซ้ำ) ถือว่าสำเร็จ แล้วปิดคำขอต่อ
        if (memberError && memberError.code !== '23505') {
            console.error('APPROVE JOIN REQUEST ERROR:', memberError.message);
            return res.status(500).json({ error: 'อนุมัติคำขอไม่สำเร็จ' });
        }
    }

    const status = action === 'approve' ? 'approved' : 'rejected';
    const { error: updateError } = await supabaseAdmin
        .from('farm_join_requests')
        .update({ status, decided_at: new Date().toISOString(), decided_by: req.userId })
        .eq('request_id', requestId)
        .eq('status', 'pending');

    if (updateError) {
        console.error('UPDATE JOIN REQUEST ERROR:', updateError.message);
        return res.status(500).json({ error: 'บันทึกผลคำขอไม่สำเร็จ' });
    }

    res.json({ data: { requestId, status } });
});

export default router;