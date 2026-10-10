import { getFarmAccess } from '../utils/farmaccess.js';

/// เช็คว่า user ที่ login อยู่เป็นสมาชิกของฟาร์มที่ระบุใน req.params[paramName] จริงไหม
/// แล้วใส่ req.farmRole ('owner' | 'worker') และ req.farmPerms (สิทธิ์ที่คำนวณแล้ว) ให้ handler ใช้ต่อ
/// ใช้แบบ: router.get('/farms/:farmId/xxx', requireAuth, requireFarmMember(), handler)
export function requireFarmMember(paramName = 'farmId') {
    return async (req, res, next) => {
        const access = await getFarmAccess(req.params[paramName], req.userId);

        if (!access) {
            return res.status(403).json({ error: 'ไม่มีสิทธิ์เข้าถึงฟาร์มนี้' });
        }

        req.farmRole = access.role;
        req.farmPerms = access.perms;
        next();
    };
}