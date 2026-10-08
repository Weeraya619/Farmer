// server/utils/deviceHealth.js
// สถานะการเชื่อมต่อของอุปกรณ์ คำนวณตอนมีคนขอดู — ไม่ใช้ cron และไม่ต้องมีตารางเพิ่ม
//
// ESP32 ส่งข้อมูลทุก ~60 นาทีแล้ว sleep => ถือว่า "เงียบ" เมื่อพลาดไป 2 รอบ (~2 ชม.)
// ตอนเดโมปรับให้สั้นได้ใน .env เช่น
//   DEVICE_REPORT_INTERVAL_MINUTES=1
//   DEVICE_MISSED_BEFORE_SILENT=2        (=> เงียบเมื่อไม่ส่งเกิน 2 นาที)

// อ่าน env ตอนเรียกใช้ (ไม่ใช่ตอน import) กันปัญหา .env ยังไม่ถูกโหลด
function silentAfterMs() {
    const intervalMin = Number(process.env.DEVICE_REPORT_INTERVAL_MINUTES) || 60;
    const missed = Number(process.env.DEVICE_MISSED_BEFORE_SILENT) || 2;
    return intervalMin * missed * 60 * 1000;
}

/**
 * state:
 *  - 'pending' : ลงทะเบียนแล้วแต่ยังไม่ได้ pair (หรือเพิ่ง replace-mac / reset)
 *  - 'paused'  : status เป็น inactive / maintenance — ไม่นับว่าเงียบ
 *  - 'silent'  : active แต่ไม่ส่งข้อมูลเกินเกณฑ์
 *  - 'online'  : active และยังส่งข้อมูลปกติ
 *
 * วัดความเงียบจากเวลาล่าสุดของ last_seen_at / paired_at / updated_at
 * ทำให้มีช่วงเผื่อหลัง pair ใหม่ หรือหลังเปลี่ยนสถานะกลับเป็น active
 * (updated_at ถูกอัปเดตเมื่อมีการแก้แถวนั้น)
 */
export function getConnectionState(device, now = Date.now()) {
    if (device.status === 'pending') return { state: 'pending', silentForMinutes: null };
    if (device.status !== 'active') return { state: 'paused', silentForMinutes: null };

    const times = [device.last_seen_at, device.paired_at, device.updated_at]
        .filter(Boolean)
        .map((t) => new Date(t).getTime());
    const latest = Math.max(...times);
    const silentMs = now - latest;

    if (silentMs > silentAfterMs()) {
        return { state: 'silent', silentForMinutes: Math.floor(silentMs / 60000) };
    }
    return { state: 'online', silentForMinutes: null };
}

/**
 * แปลงแถว devices เป็นข้อมูลที่ส่งออกจาก API ได้:
 *  - ตัด device_secret_hash ออก (client ไม่ควรเห็น) แล้วแทนด้วย is_paired
 *  - เติม connection_state และ silent_for_minutes
 */
export function toDeviceView(device, now = Date.now()) {
    const { device_secret_hash, ...safe } = device;
    const { state, silentForMinutes } = getConnectionState(device, now);
    return {
        ...safe,
        is_paired: Boolean(device_secret_hash),
        connection_state: state,
        silent_for_minutes: silentForMinutes,
    };
}