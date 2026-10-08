import { supabaseAdmin } from '../supabaseClient.js';

/// เช็คว่า user ที่ login อยู่เป็นสมาชิกของฟาร์มที่ระบุใน req.params[paramName] จริงไหม
/// ใช้แบบ: router.get('/farms/:farmId/xxx', requireAuth, requireFarmMember(), handler)
export function requireFarmMember(paramName = 'farmId') {
    return async (req, res, next) => {
        const farmId = req.params[paramName];

        const { data, error } = await supabaseAdmin
            .from('farm_members')
            .select('role')
            .eq('farm_id', farmId)
            .eq('user_id', req.userId)
            .maybeSingle();

        if (error || !data) {
            return res.status(403).json({ error: 'ไม่มีสิทธิ์เข้าถึงฟาร์มนี้' });
        }

        req.farmRole = data.role;
        next();
    };
}