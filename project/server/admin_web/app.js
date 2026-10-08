// ค่า config และฟังก์ชันช่วยเหลือที่ใช้ร่วมกันทุกหน้าของเว็บแอดมิน
const API_BASE = window.location.origin + '/api';

function getToken() {
  return localStorage.getItem('admin_token');
}

function setToken(token) {
  localStorage.setItem('admin_token', token);
}

function clearToken() {
  localStorage.removeItem('admin_token');
}

function requireLogin() {
  if (!getToken()) {
    window.location.href = '/admin/login.html';
  }
}

// wrapper เรียก API พร้อมแนบ token อัตโนมัติ — ถ้าโดน 401/403 เด้งกลับไปหน้า login ให้เลย
async function apiFetch(path, options = {}) {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${getToken()}`,
      ...(options.headers || {}),
    },
  });

  if (response.status === 401 || response.status === 403) {
    clearToken();
    window.location.href = '/admin/login.html';
    throw new Error('ไม่ได้รับอนุญาต');
  }

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || 'เกิดข้อผิดพลาด');
  }
  return data;
}

function logout() {
  clearToken();
  window.location.href = '/admin/login.html';
}

function formatThaiDateTime(isoString) {
  if (!isoString) return '-';
  const d = new Date(isoString);
  if (isNaN(d)) return isoString;
  const months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
  const buddhistYear = d.getFullYear() + 543;
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return `${d.getDate()} ${months[d.getMonth()]} ${buddhistYear} เวลา ${hh}:${mm} น.`;
}

// แปลงจำนวนนาทีที่อุปกรณ์เงียบเป็นข้อความอ่านง่าย เช่น "45 นาที", "2 ชม. 10 นาที"
function formatSilentMinutes(min) {
  if (min == null) return '';
  if (min < 60) return `${min} นาที`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h} ชม. ${m} นาที` : `${h} ชม.`;
}

function escapeHtml(str) {
  if (str == null) return '';
  return String(str)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}