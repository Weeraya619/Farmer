import { Router } from 'express';
import crypto from 'crypto';
import { supabaseAdmin } from '../supabaseClient.js';
import { requireAuth } from '../middleware/requireAuth.js';
import { requireFarmMember } from '../middleware/requireFarmMember.js';
import { toDeviceView } from '../utils/deviceHealth.js';

const router = Router();

function hashSecret(secret) {
    return crypto.createHash('sha256').update(secret).digest('hex');
}

// เทียบ secret ที่ ESP32 ส่งมากับ hash ที่เก็บไว้ แบบ constant-time (กัน timing attack)
function secretMatches(storedHash, secretFromDevice) {
    if (!storedHash || typeof secretFromDevice !== 'string') return false;
    const a = Buffer.from(storedHash, 'hex');
    const b = Buffer.from(hashSecret(secretFromDevice), 'hex');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// รูปแบบ MAC address ที่ยอมรับ เช่น AA:BB:CC:DD:EE:FF
const MAC_REGEX = /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/;

// รายชื่อ sensor ที่ระบบรู้จัก — ใช้ตรวจสอบค่าที่ ESP32 ส่งมาตอน pair ว่าถูกต้องไหม
const KNOWN_SENSORS = ['dht22', 'turbidity', 'tds'];

// ฟิลด์ข้อมูลที่แต่ละ sensor "มีสิทธิ์ส่ง" — ค่าของ sensor ที่บอร์ดไม่ได้แจ้งไว้ตอน pair จะถูกทิ้ง
// (ถ้าจะรองรับ pH: เพิ่ม 'ph' ใน KNOWN_SENSORS และเพิ่ม ph: ['ph'] ตรงนี้)
const SENSOR_FIELDS = {
    dht22: ['airTemperature', 'humidity'],
    turbidity: ['turbidity'],
    tds: ['tds'],
};

// ช่วงค่าที่ยอมรับของแต่ละฟิลด์ — นอกช่วง/ไม่ใช่ตัวเลข = ทิ้ง (กัน NaN, ค่าเพี้ยนจาก sensor เสีย)
const VALUE_RANGES = {
    airTemperature: [-40, 80],
    humidity: [0, 100],
    tds: [0, 100000],
    turbidity: [0, 10000],
    ph: [0, 14],
};

function cleanValue(field, value) {
    if (typeof value !== 'number' || !Number.isFinite(value)) return undefined;
    const [min, max] = VALUE_RANGES[field];
    return value >= min && value <= max ? value : undefined;
}

// กันแจ้งเตือนเรื่องเดียวกันซ้ำภายในกี่ชั่วโมง (ESP32 ส่งทุก ~1 ชม. จึงไม่ควรตั้งแค่ 1 ชม.)
const NOTIFICATION_DEDUPE_HOURS = 6;

// reading ที่เก่ากว่านี้ (เช่น ส่งย้อนหลังหลังเน็ตหลุด) จะถูกบันทึก แต่ไม่ใช้ตัดสินแจ้งเตือน/คำนวณ THI
const ALERT_MAX_AGE_MS = 3 * 60 * 60 * 1000;

// สถานะที่เกษตรกร/แอดมินตั้งเองได้ ('pending' ตั้งเองไม่ได้ ต้องผ่าน replace-mac หรือรีเซ็ต)
const SETTABLE_STATUSES = ['active', 'inactive', 'maintenance'];

// ============================================================
// Logic การตัดสินใจตาม flowchart ที่ตกลงกันไว้
// ============================================================

// ตารางกำหนดคุณภาพน้ำ — เช็ค TDS (>3000 mg/L ผิดปกติ) และ Turbidity (>5 NTU ผิดปกติ)
function evaluateWaterQuality(tds, turbidity) {
    const tdsAbnormal = tds != null && tds > 3000;
    const turbidityAbnormal = turbidity != null && turbidity > 5;

    if (tdsAbnormal && turbidityAbnormal) {
        return {
            category: 'water',
            severity: 'critical',
            title: 'คุณภาพน้ำอันตราย',
            message: 'ค่า TDS และความขุ่นของน้ำผิดปกติทั้งคู่ ควรตรวจสอบแหล่งน้ำโดยด่วน',
        };
    }
    if (tdsAbnormal) {
        return {
            category: 'water',
            severity: 'warning',
            title: 'ค่าแร่ธาตุในน้ำสูง',
            message: 'ค่า TDS สูงเกินเกณฑ์ปกติ อาจเป็นอันตรายต่อสุขภาพวัว',
        };
    }
    if (turbidityAbnormal) {
        return {
            category: 'water',
            severity: 'warning',
            title: 'น้ำขุ่นผิดปกติ',
            message: 'ค่าความขุ่นของน้ำสูงเกินเกณฑ์ อาจมีแบคทีเรียปนเปื้อน',
        };
    }
    return null; // ปกติ ไม่ต้องแจ้งเตือน
}

// สูตร THI มาตรฐาน (NRC) — ใช้อุณหภูมิเป็นองศาเซลเซียส
function calculateTHI(tempC, humidityPct) {
    return (0.8 * tempC) + (humidityPct * (tempC - 14.4)) + 46.4;
}

// เกณฑ์ THI ปรับสำหรับวัวลูกผสมไทย (อ้างอิงงานวิจัย Thai-Holstein crossbred)
// สูงกว่ามาตรฐานสากล เพราะวัวพันธุ์ผสมไทยทนร้อนได้มากกว่า
function evaluateTHI(thi) {
    if (thi < 72) return null; // เขตสบาย (comfort zone)
    if (thi <= 78) {
        return {
            category: 'heat',
            severity: 'warning',
            title: 'วัวเริ่มเครียดจากความร้อน (เล็กน้อย)',
            message: `ค่า THI อยู่ที่ ${thi.toFixed(1)} วัวเริ่มมีความเครียดจากความร้อนเล็กน้อย`,
        };
    }
    if (thi <= 89) {
        return {
            category: 'heat',
            severity: 'warning',
            title: 'วัวเครียดจากความร้อน (ปานกลาง)',
            message: `ค่า THI อยู่ที่ ${thi.toFixed(1)} ควรเพิ่มการระบายอากาศหรือน้ำดื่มให้วัว`,
        };
    }
    return {
        category: 'heat',
        severity: 'critical',
        title: 'วัวเครียดจากความร้อนรุนแรง',
        message: `ค่า THI อยู่ที่ ${thi.toFixed(1)} อยู่ในระดับอันตราย ควรดำเนินการลดความร้อนโดยด่วน`,
    };
}

async function createNotification(farmId, deviceId, result) {
    // กันแจ้งเตือนซ้ำเรื่องเดียวกันภายใน NOTIFICATION_DEDUPE_HOURS ชั่วโมง
    // (เช่น 2 device ส่งอุณหภูมิมาใกล้กันจนคำนวณ THI ซ้ำ หรือเงื่อนไขเดิมยังค้างอยู่ตอนข้อมูลรอบถัดไปเข้า)
    const since = new Date(Date.now() - NOTIFICATION_DEDUPE_HOURS * 60 * 60 * 1000).toISOString();
    const { data: recent } = await supabaseAdmin
        .from('notifications')
        .select('notification_id')
        .eq('farm_id', farmId)
        .eq('title', result.title)
        .gte('created_at', since)
        .limit(1)
        .maybeSingle();

    if (recent) return; // เพิ่งแจ้งเรื่องนี้ไปแล้ว ไม่ต้องซ้ำ

    await supabaseAdmin.from('notifications').insert({
        farm_id: farmId,
        device_id: deviceId,
        category: result.category,
        severity: result.severity,
        title: result.title,
        message: result.message,
    });
}

// ============================================================
// เกษตรกรลงทะเบียนอุปกรณ์ (ต้อง login, เป็นสมาชิกฟาร์ม)
// ============================================================

// GET /api/farms/:farmId/devices
// ส่งผ่าน toDeviceView: ตัด device_secret_hash ออก และเติม is_paired / connection_state / silent_for_minutes
router.get('/farms/:farmId/devices', requireAuth, requireFarmMember(), async (req, res) => {
    const { data, error } = await supabaseAdmin
        .from('devices')
        .select('*')
        .eq('farm_id', req.params.farmId)
        .order('created_at', { ascending: false });

    if (error) {
        console.error('GET DEVICES ERROR:', error.message);
        return res.status(500).json({ error: 'ไม่สามารถโหลดข้อมูลอุปกรณ์ได้' });
    }

    res.json({ data: data.map((d) => toDeviceView(d)) });
});

// POST /api/farms/:farmId/devices
// body: { macAddress, name }
// ยังไม่สร้าง secret ตอนนี้ — รอ ESP32 มาขอเองตอน pair ครั้งแรก
// ไม่ต้องเลือกชุดเซนเซอร์แล้ว — ESP32 จะบอกเองว่ามี sensor อะไรบ้างตอน pair (ดู POST /devices/pair)
router.post('/farms/:farmId/devices', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId } = req.params;
    const { macAddress, name } = req.body;

    // บทบาทผู้ชม (viewer) ดูได้อย่างเดียว ลงทะเบียนอุปกรณ์ไม่ได้
    if (req.farmRole === 'viewer') {
        return res.status(403).json({ error: 'บทบาทผู้ชมไม่มีสิทธิ์จัดการอุปกรณ์' });
    }

    if (!macAddress || !MAC_REGEX.test(macAddress)) {
        return res.status(400).json({ error: 'รูปแบบ MAC address ไม่ถูกต้อง (ตัวอย่าง AA:BB:CC:DD:EE:FF)' });
    }
    if (!name || !name.trim()) {
        return res.status(400).json({ error: 'กรุณาตั้งชื่ออุปกรณ์' });
    }

    const { data, error } = await supabaseAdmin
        .from('devices')
        .insert({
            farm_id: farmId,
            name: name.trim(),
            mac_address: macAddress.toUpperCase(),
            sensors: [], // จะถูกเติมอัตโนมัติตอน ESP32 มา pair ครั้งแรก
            status: 'pending',
        })
        .select()
        .single();

    if (error) {
        if (error.code === '23505') {
            // unique constraint violation บน mac_address
            return res.status(409).json({ error: 'MAC address นี้ถูกลงทะเบียนไปแล้ว' });
        }
        console.error('CREATE DEVICE ERROR:', error.message);
        return res.status(500).json({ error: 'ลงทะเบียนอุปกรณ์ไม่สำเร็จ' });
    }

    // ลงทะเบียนสำเร็จแล้ว ล้าง MAC นี้ออกจากรายการ "อุปกรณ์ที่ไม่รู้จัก" ของแอดมิน (ไม่ต้อง fail ถ้าล้างไม่สำเร็จ)
    await supabaseAdmin
        .from('unregistered_pair_attempts')
        .delete()
        .eq('mac_address', macAddress.toUpperCase());

    res.json({ data: toDeviceView(data) });
});

// PATCH /api/devices/:deviceId/replace-mac
// body: { newMacAddress }
// ใช้ตอน ESP32 พังแต่ sensor ยังดี — เปลี่ยนเป็นบอร์ดใหม่ (MAC ใหม่) โดย device_id เดิม
// ทำให้ประวัติข้อมูล sensor ทั้งหมดยังเชื่อมกับตัวตนเดิมต่อเนื่อง ไม่ขาดตอน
// ล้าง secret เดิมทิ้ง (บอร์ดใหม่ต้อง pair ใหม่) กลับเป็น pending
// เก็บ MAC เดิมและเวลาที่เปลี่ยนไว้ใน previous_mac_address / mac_replaced_at ให้แอดมินดูได้
router.patch('/devices/:deviceId/replace-mac', requireAuth, async (req, res) => {
    const { deviceId } = req.params;
    const { newMacAddress } = req.body;

    if (!newMacAddress || !MAC_REGEX.test(newMacAddress)) {
        return res.status(400).json({ error: 'รูปแบบ MAC address ไม่ถูกต้อง (ตัวอย่าง AA:BB:CC:DD:EE:FF)' });
    }

    const { data: existing } = await supabaseAdmin
        .from('devices')
        .select('farm_id, name, mac_address')
        .eq('device_id', deviceId)
        .maybeSingle();

    if (!existing) return res.status(404).json({ error: 'ไม่พบอุปกรณ์นี้' });

    const { data: membership } = await supabaseAdmin
        .from('farm_members')
        .select('role')
        .eq('farm_id', existing.farm_id)
        .eq('user_id', req.userId)
        .maybeSingle();

    if (!membership) return res.status(403).json({ error: 'ไม่มีสิทธิ์แก้ไขอุปกรณ์นี้' });
    if (membership.role === 'viewer') {
        return res.status(403).json({ error: 'บทบาทผู้ชมไม่มีสิทธิ์จัดการอุปกรณ์' });
    }

    const newMac = newMacAddress.toUpperCase();
    if (existing.mac_address && existing.mac_address.toUpperCase() === newMac) {
        return res.status(400).json({ error: 'MAC address ใหม่ซ้ำกับของเดิม' });
    }

    const { data, error } = await supabaseAdmin
        .from('devices')
        .update({
            mac_address: newMac,
            previous_mac_address: existing.mac_address,
            mac_replaced_at: new Date().toISOString(),
            device_secret_hash: null,
            status: 'pending',
            paired_at: null,
        })
        .eq('device_id', deviceId)
        .select()
        .single();

    if (error) {
        if (error.code === '23505') {
            return res.status(409).json({ error: 'MAC address นี้ถูกใช้กับอุปกรณ์อื่นอยู่แล้ว' });
        }
        console.error('REPLACE MAC ERROR:', error.message);
        return res.status(500).json({ error: 'เปลี่ยน ESP32 ไม่สำเร็จ' });
    }

    res.json({ data: toDeviceView(data) });
});

// PATCH /api/devices/:deviceId — แก้ชื่อ/สถานะ (สมาชิกฟาร์มที่ไม่ใช่ viewer)
router.patch('/devices/:deviceId', requireAuth, async (req, res) => {
    const { deviceId } = req.params;

    const { data: existing } = await supabaseAdmin
        .from('devices')
        .select('farm_id, device_secret_hash')
        .eq('device_id', deviceId)
        .maybeSingle();

    if (!existing) return res.status(404).json({ error: 'ไม่พบอุปกรณ์นี้' });

    const { data: membership } = await supabaseAdmin
        .from('farm_members')
        .select('role')
        .eq('farm_id', existing.farm_id)
        .eq('user_id', req.userId)
        .maybeSingle();

    if (!membership) return res.status(403).json({ error: 'ไม่มีสิทธิ์แก้ไขอุปกรณ์นี้' });
    if (membership.role === 'viewer') {
        return res.status(403).json({ error: 'บทบาทผู้ชมไม่มีสิทธิ์จัดการอุปกรณ์' });
    }

    const { name, status } = req.body;
    const updates = {};

    if (name !== undefined) {
        if (typeof name !== 'string' || !name.trim()) {
            return res.status(400).json({ error: 'ชื่ออุปกรณ์ไม่ถูกต้อง' });
        }
        updates.name = name.trim();
    }

    if (status !== undefined) {
        if (!SETTABLE_STATUSES.includes(status)) {
            return res.status(400).json({ error: 'สถานะไม่ถูกต้อง (active / inactive / maintenance)' });
        }
        // อุปกรณ์ที่ยังไม่เคย pair ไม่มี secret จึงตั้งเป็น active ไม่ได้
        if (status === 'active' && !existing.device_secret_hash) {
            return res.status(400).json({ error: 'อุปกรณ์ยังไม่ได้เชื่อมต่อ (pair) จึงตั้งเป็นใช้งานไม่ได้' });
        }
        updates.status = status;
    }

    if (Object.keys(updates).length === 0) {
        return res.status(400).json({ error: 'ไม่มีข้อมูลที่จะแก้ไข' });
    }

    const { data, error } = await supabaseAdmin
        .from('devices')
        .update(updates)
        .eq('device_id', deviceId)
        .select()
        .single();

    if (error) {
        console.error('UPDATE DEVICE ERROR:', error.message);
        return res.status(500).json({ error: 'แก้ไขไม่สำเร็จ' });
    }

    res.json({ data: toDeviceView(data) });
});

// ============================================================
// ฝั่ง ESP32 — ไม่ใช้ user token (Supabase JWT) เพราะไม่ใช่ user ที่ login
// ใช้ MAC address / device secret แทน
// ============================================================

// POST /api/devices/pair
// body: { macAddress, sensors }
// เรียกครั้งแรกหลัง ESP32 ต่อ WiFi สำเร็จ — ถ้า MAC นี้ถูกลงทะเบียนไว้ในแอปแล้วและยังไม่เคย pair
// จะสร้าง secret ให้ตรงนี้ แล้วส่งกลับเป็น plaintext ครั้งเดียว (หลังจากนี้ดึงคืนไม่ได้อีก เก็บแค่ hash)
router.post('/devices/pair', async (req, res) => {
    const { macAddress, sensors } = req.body;

    if (!macAddress || !MAC_REGEX.test(macAddress)) {
        return res.status(400).json({ error: 'รูปแบบ MAC address ไม่ถูกต้อง' });
    }

    // ESP32 ต้องบอกมาว่ามี sensor อะไรติดอยู่บ้าง (แทนที่การเลือก preset ตอนลงทะเบียน)
    const sensorList = Array.isArray(sensors) ? sensors.filter((s) => KNOWN_SENSORS.includes(s)) : [];
    if (sensorList.length === 0) {
        return res.status(400).json({
            error: `กรุณาระบุ sensors อย่างน้อย 1 ตัวที่รู้จัก (${KNOWN_SENSORS.join(', ')})`,
        });
    }

    const { data: device, error: fetchError } = await supabaseAdmin
        .from('devices')
        .select('device_id, device_secret_hash')
        .eq('mac_address', macAddress.toUpperCase())
        .maybeSingle();

    if (fetchError) {
        console.error('PAIR LOOKUP ERROR:', fetchError.message);
        return res.status(500).json({ error: 'จับคู่อุปกรณ์ไม่สำเร็จ' });
    }

    if (!device) {
        // MAC นี้ยังไม่มีใครลงทะเบียน — จดไว้ให้แอดมินเห็น (เช่น เกษตรกรพิมพ์ MAC ผิดหรือจำไม่ได้)
        // ถ้าตารางยังไม่ถูกสร้าง (ยังไม่ได้รัน migration) แค่ข้ามไป ไม่กระทบการตอบ 404
        await supabaseAdmin.from('unregistered_pair_attempts').upsert(
            {
                mac_address: macAddress.toUpperCase(),
                reported_sensors: sensorList,
                last_ip: req.ip,
                last_seen_at: new Date().toISOString(),
            },
            { onConflict: 'mac_address' }
        );
        return res.status(404).json({ error: 'ยังไม่มีการลงทะเบียนอุปกรณ์นี้ กรุณาลงทะเบียนในแอปก่อน' });
    }

    if (device.device_secret_hash) {
        // เคย pair ไปแล้ว ไม่สร้าง secret ใหม่ซ้ำ (กันคนอื่นมาแย่ง pair)
        return res.status(409).json({ error: 'อุปกรณ์นี้เชื่อมต่อไปแล้ว' });
    }

    const secret = crypto.randomBytes(32).toString('hex');

    const { error: updateError } = await supabaseAdmin
        .from('devices')
        .update({
            device_secret_hash: hashSecret(secret),
            sensors: sensorList, // เติม/อัปเดต sensors จากที่ ESP32 รายงานมาเอง
            status: 'active',
            paired_at: new Date().toISOString(),
        })
        .eq('device_id', device.device_id);

    if (updateError) {
        console.error('PAIR DEVICE ERROR:', updateError.message);
        return res.status(500).json({ error: 'จับคู่อุปกรณ์ไม่สำเร็จ' });
    }

    res.json({ deviceId: device.device_id, deviceSecret: secret });
});

// POST /api/devices/:deviceId/sensor-data
// Headers: X-Device-Secret: <secret ที่ได้จากตอน pair>
// body: { sensorTimestamp?, airTemperature, humidity, tds, turbidity }
// ส่งเฉพาะค่าของ sensor ที่บอร์ดมีและอ่านได้สำเร็จ (อ่านไม่ได้ให้ "ไม่ส่งฟิลด์" ห้ามส่ง 0/NaN)
router.post('/devices/:deviceId/sensor-data', async (req, res) => {
    const { deviceId } = req.params;
    const secretFromDevice = req.headers['x-device-secret'];

    if (!secretFromDevice) {
        return res.status(401).json({ error: 'missing device secret' });
    }

    const { data: device } = await supabaseAdmin
        .from('devices')
        .select('device_secret_hash, farm_id, status, sensors')
        .eq('device_id', deviceId)
        .maybeSingle();

    if (!device || !secretMatches(device.device_secret_hash, secretFromDevice)) {
        return res.status(401).json({ error: 'invalid device secret' });
    }

    // เก็บเฉพาะค่าของ sensor ที่บอร์ดแจ้งไว้ตอน pair และต้องเป็นตัวเลขในช่วงที่สมเหตุสมผล
    const allowedFields = new Set((device.sensors || []).flatMap((s) => SENSOR_FIELDS[s] || []));
    const readings = {};
    for (const field of allowedFields) {
        const value = cleanValue(field, req.body?.[field]);
        if (value !== undefined) readings[field] = value;
    }
    const { airTemperature, humidity, tds, turbidity, ph } = readings;

    // เวลาของ reading: ใช้ที่บอร์ดส่งมาถ้า parse ได้และไม่ใช่อนาคตเกิน 5 นาที ไม่งั้นใช้เวลาเซิร์ฟเวอร์
    let sensorTime = new Date();
    if (req.body?.sensorTimestamp) {
        const parsed = new Date(req.body.sensorTimestamp);
        if (!isNaN(parsed) && parsed.getTime() <= Date.now() + 5 * 60 * 1000) sensorTime = parsed;
    }

    // ไม่มีค่าที่ใช้ได้เลย (เช่น sensor เสียทุกตัว) — ไม่บันทึกแถว แต่ถือว่าบอร์ด "ยังมีชีวิต"
    if (Object.keys(readings).length === 0) {
        await supabaseAdmin
            .from('devices')
            .update({ last_seen_at: new Date().toISOString() })
            .eq('device_id', deviceId);
        return res.json({ data: null, note: 'ไม่มีค่า sensor ที่ใช้ได้ในคำขอนี้ จึงไม่ได้บันทึกค่า' });
    }

    const { data, error } = await supabaseAdmin
        .from('sensor_data')
        .insert({
            farm_id: device.farm_id,
            device_id: deviceId,
            sensor_timestamp: sensorTime.toISOString(),
            air_temperature: airTemperature,
            humidity,
            ph,
            tds,
            turbidity,
        })
        .select()
        .single();

    if (error) {
        console.error('INSERT SENSOR DATA ERROR:', error.message);
        return res.status(500).json({ error: 'บันทึกข้อมูล sensor ไม่สำเร็จ' });
    }

    // last_seen_at อัปเดตอัตโนมัติผ่าน trigger touch_device_last_seen (สร้างโดย migration_minimal.sql)

    // reading เก่า (เช่น ส่งย้อนหลัง) บันทึกไว้ได้ แต่ไม่ใช้ตัดสินแจ้งเตือนหรือคำนวณ THI
    const isFresh = Date.now() - sensorTime.getTime() <= ALERT_MAX_AGE_MS;

    // --- ตรวจสอบคุณภาพน้ำ (เฉพาะ reading ที่มีค่า tds/turbidity ส่งมา) ---
    if (isFresh && (tds != null || turbidity != null)) {
        const waterResult = evaluateWaterQuality(tds, turbidity);
        if (waterResult) {
            await createNotification(device.farm_id, deviceId, waterResult);
        }
    }

    // --- คำนวณ THI (เฉพาะ reading ที่มีอุณหภูมิ/ความชื้น) ---
    // เฉลี่ยกับ reading ล่าสุดของ "ทุก device อื่น" ในฟาร์มเดียวกันที่วัดอุณหภูมิ/ความชื้นได้
    // (ภายใน 3 ชม.ที่ผ่านมา) — รองรับ DHT22 กี่ตัวก็ได้ (1, 2, 3 หรือมากกว่า) ไม่ผูกกับจำนวนตายตัว
    if (isFresh && airTemperature != null && humidity != null) {
        const threeHoursAgo = new Date(Date.now() - 3 * 60 * 60 * 1000).toISOString();
        const { data: recentReadings } = await supabaseAdmin
            .from('sensor_data')
            .select('doc_id, device_id, air_temperature, humidity')
            .eq('farm_id', device.farm_id)
            .neq('device_id', deviceId)
            .not('air_temperature', 'is', null)
            .gte('sensor_timestamp', threeHoursAgo)
            .order('sensor_timestamp', { ascending: false });

        // เก็บแค่ reading ล่าสุดของแต่ละ device (เรียงใหม่→เก่าอยู่แล้ว ตัวแรกที่เจอของแต่ละ device คือล่าสุด)
        const latestPerDevice = new Map();
        for (const r of recentReadings || []) {
            if (!latestPerDevice.has(r.device_id)) latestPerDevice.set(r.device_id, r);
        }
        const others = [...latestPerDevice.values()];

        const temps = [airTemperature, ...others.map((r) => r.air_temperature)];
        const humidities = [humidity, ...others.map((r) => r.humidity)];
        const avgTemp = temps.reduce((a, b) => a + b, 0) / temps.length;
        const avgHumidity = humidities.reduce((a, b) => a + b, 0) / humidities.length;

        const thi = calculateTHI(avgTemp, avgHumidity);

        // เก็บค่า THI ไว้ในแถวนี้ และย้อนไปเติมให้แถวของ device อื่นที่ร่วมเฉลี่ยด้วย (ให้กราฟแนวโน้มถูกต้องทุกตัว)
        await supabaseAdmin.from('sensor_data').update({ thi }).eq('doc_id', data.doc_id);
        for (const r of others) {
            await supabaseAdmin.from('sensor_data').update({ thi }).eq('doc_id', r.doc_id);
        }

        const thiResult = evaluateTHI(thi);
        if (thiResult) {
            await createNotification(device.farm_id, deviceId, thiResult);
        }
    }

    res.json({ data });
});

// GET /api/farms/:farmId/sensor-data/latest
// รวมค่าล่าสุดของ "อุณหภูมิ/ความชื้น" กับ "ค่าน้ำ" แยกกัน เพราะมาจากคนละ device
// (ถ้าใช้แค่ "แถวล่าสุดแถวเดียว" อาจได้ค่าจาก device ที่ไม่มีข้อมูลน้ำมา ทำให้ดูเหมือนไม่มีข้อมูลทั้งที่จริงมี)
router.get('/farms/:farmId/sensor-data/latest', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId } = req.params;

    const [{ data: climateRows, error: climateError }, { data: waterRows, error: waterError }] = await Promise.all([
        supabaseAdmin
            .from('sensor_data')
            .select('air_temperature, humidity, thi, sensor_timestamp')
            .eq('farm_id', farmId)
            .not('air_temperature', 'is', null)
            .order('sensor_timestamp', { ascending: false })
            .limit(1),
        supabaseAdmin
            .from('sensor_data')
            .select('tds, turbidity, sensor_timestamp')
            .eq('farm_id', farmId)
            .or('tds.not.is.null,turbidity.not.is.null')
            .order('sensor_timestamp', { ascending: false })
            .limit(1),
    ]);

    if (climateError || waterError) {
        console.error('GET LATEST SUMMARY ERROR:', climateError?.message || waterError?.message);
        return res.status(500).json({ error: 'ไม่สามารถโหลดข้อมูล sensor ได้' });
    }

    const climate = climateRows?.[0] || null;
    const water = waterRows?.[0] || null;

    res.json({
        data: {
            airTemperature: climate?.air_temperature ?? null,
            humidity: climate?.humidity ?? null,
            thi: climate?.thi ?? null,
            climateTimestamp: climate?.sensor_timestamp ?? null,
            tds: water?.tds ?? null,
            turbidity: water?.turbidity ?? null,
            waterTimestamp: water?.sensor_timestamp ?? null,
        },
    });
});

// GET /api/farms/:farmId/sensor-data?limit=&deviceId=&from=&to=
// ใช้ดึงประวัติสำหรับกราฟแนวโน้ม (สำหรับค่าล่าสุดรวม ใช้ /sensor-data/latest แทน)
router.get('/farms/:farmId/sensor-data', requireAuth, requireFarmMember(), async (req, res) => {
    const { farmId } = req.params;
    const { limit, deviceId, from, to } = req.query;

    let query = supabaseAdmin
        .from('sensor_data')
        .select('*')
        .eq('farm_id', farmId)
        .order('sensor_timestamp', { ascending: false });

    if (deviceId) query = query.eq('device_id', deviceId);
    if (from) query = query.gte('sensor_timestamp', from);
    if (to) query = query.lte('sensor_timestamp', to);
    if (limit) query = query.limit(parseInt(limit, 10));

    const { data, error } = await query;

    if (error) {
        console.error('GET SENSOR DATA ERROR:', error.message);
        return res.status(500).json({ error: 'ไม่สามารถโหลดข้อมูล sensor ได้' });
    }

    res.json({ data });
});

export default router;