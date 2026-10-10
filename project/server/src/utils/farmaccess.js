import { supabaseAdmin } from '../supabaseClient.js';

// คำนวณสิทธิ์ทั้งหมดจาก role + สวิตช์ของฟาร์ม
// กฎสิทธิ์ทั้งระบบอยู่ที่ไฟล์นี้ที่เดียว — จะเปลี่ยนกฎก็แก้ตรงนี้
export function buildPerms(role, farm, userId) {
    const isOwner = role === 'owner'; // owner หลักและ co-owner ทำได้เท่ากัน
    const financeOn = !!farm?.worker_finance_enabled;

    return {
        isOwner,
        isPrimaryOwner: isOwner && !!farm?.created_by && farm.created_by === userId,
        canFinance: isOwner || financeOn,
        // สวิตช์การเงินเป็นสวิตช์หลัก: ปิดการเงิน = ซื้อ/ขายวัวถูกปิดตามอัตโนมัติ
        canBuyCow: isOwner || (financeOn && !!farm?.worker_buy_cow_enabled),
        canSellCow: isOwner || (financeOn && !!farm?.worker_sell_cow_enabled),
        canManageDevices: isOwner,
        canManageMembers: isOwner,
    };
}

// คืน { role, perms } ถ้า user เป็นสมาชิกของฟาร์มนี้ ไม่งั้นคืน null
export async function getFarmAccess(farmId, userId) {
    const { data, error } = await supabaseAdmin
        .from('farm_members')
        .select('role, farms(created_by, worker_finance_enabled, worker_buy_cow_enabled, worker_sell_cow_enabled)')
        .eq('farm_id', farmId)
        .eq('user_id', userId)
        .maybeSingle();

    if (error || !data) return null;

    return { role: data.role, perms: buildPerms(data.role, data.farms, userId) };
}