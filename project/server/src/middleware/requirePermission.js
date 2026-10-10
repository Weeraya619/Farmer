/// ต้องวางหลัง requireFarmMember() เสมอ (เพราะอ่านจาก req.farmPerms)
/// ใช้แบบ: router.post('/farms/:farmId/xxx', requireAuth, requireFarmMember(), requirePermission('canFinance'), handler)
export function requirePermission(permission, message = 'ไม่มีสิทธิ์ทำรายการนี้') {
    return (req, res, next) => {
        if (!req.farmPerms || !req.farmPerms[permission]) {
            return res.status(403).json({ error: message });
        }
        next();
    };
}