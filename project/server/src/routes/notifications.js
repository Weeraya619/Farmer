import { Router } from 'express';
import { supabaseAdmin } from '../supabaseClient.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireFarmMember } from '../middleware/requireFarmMember.js';

const router = Router();

// GET /api/farms/:farmId/notifications — เรียงใหม่สุดก่อน
router.get('/farms/:farmId/notifications', requireAuth, requireFarmMember(), async (req, res) => {
    const { data, error } = await supabaseAdmin
        .from('notifications')
        .select('*')
        .eq('farm_id', req.params.farmId)
        .order('created_at', { ascending: false });

    if (error) {
        console.error('GET NOTIFICATIONS ERROR:', error.message);
        return res.status(500).json({ error: 'ไม่สามารถโหลดการแจ้งเตือนได้' });
    }

    res.json({ data });
});

// PATCH /api/notifications/:notificationId/read
router.patch('/notifications/:notificationId/read', requireAuth, async (req, res) => {
    const { notificationId } = req.params;

    const { data: existing } = await supabaseAdmin
        .from('notifications')
        .select('farm_id')
        .eq('notification_id', notificationId)
        .maybeSingle();

    if (!existing) return res.status(404).json({ error: 'ไม่พบการแจ้งเตือนนี้' });

    const { data: membership } = await supabaseAdmin
        .from('farm_members')
        .select('role')
        .eq('farm_id', existing.farm_id)
        .eq('user_id', req.userId)
        .maybeSingle();

    if (!membership) return res.status(403).json({ error: 'ไม่มีสิทธิ์เข้าถึงการแจ้งเตือนนี้' });

    const { data, error } = await supabaseAdmin
        .from('notifications')
        .update({ is_read: true })
        .eq('notification_id', notificationId)
        .select()
        .single();

    if (error) {
        console.error('MARK READ ERROR:', error.message);
        return res.status(500).json({ error: 'อัปเดตไม่สำเร็จ' });
    }

    res.json({ data });
});

// PATCH /api/farms/:farmId/notifications/read-all — อ่านทั้งหมดทีเดียว
router.patch('/farms/:farmId/notifications/read-all', requireAuth, requireFarmMember(), async (req, res) => {
    const { error } = await supabaseAdmin
        .from('notifications')
        .update({ is_read: true })
        .eq('farm_id', req.params.farmId)
        .eq('is_read', false);

    if (error) {
        console.error('MARK ALL READ ERROR:', error.message);
        return res.status(500).json({ error: 'อัปเดตไม่สำเร็จ' });
    }

    res.json({ success: true });
});

export default router;