import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// โหลด .env จาก path ที่คำนวณจากตำแหน่งไฟล์นี้เอง (server/.env) แทนที่จะพึ่ง
// current working directory — กันปัญหา env ว่างเปล่าตอนรันคำสั่งจากคนละโฟลเดอร์
// (เช่นตอนรัน scripts/seed-demo-data.js จากนอกโฟลเดอร์ server)
const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '../.env') });

// ใช้สำหรับ proxy คำสั่ง auth (signup/login/logout) เท่านั้น
// เทียบเท่าสิทธิ์เดียวกับที่ client ทั่วไปมี ไม่ข้าม RLS
export const supabasePublic = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_ANON_KEY
);

// ใช้สำหรับอ่าน/เขียนข้อมูลธุรกิจทั้งหมด (farms, devices, sensor_data ฯลฯ)
// ข้าม RLS ได้ทั้งหมด — ต้องเช็คสิทธิ์เองในโค้ดก่อนใช้เสมอ
// ห้าม import ไฟล์นี้ไปใช้ที่ client-facing code ใดๆ นอกจาก backend เท่านั้น
export const supabaseAdmin = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);