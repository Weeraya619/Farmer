// วาด sidebar navigation ซ้ำทุกหน้า — เรียกจาก script ท้ายไฟล์ HTML แต่ละหน้า
function renderSidebar(activePage) {
  const items = [
    { href: '/admin/index.html', label: 'ภาพรวม', icon: '📊', key: 'overview' },
    { href: '/admin/users.html', label: 'จัดการผู้ใช้', icon: '👤', key: 'users' },
    { href: '/admin/devices.html', label: 'อุปกรณ์ทั้งหมด', icon: '📡', key: 'devices' },
    { href: '/admin/unregistered.html', label: 'อุปกรณ์ที่ไม่รู้จัก', icon: '❓', key: 'unregistered' },
    { href: '/admin/logs.html', label: 'Log การแจ้งเตือน', icon: '🔔', key: 'logs' },
    { href: '/admin/audit_logs.html', label: 'Audit Log แอดมิน', icon: '📝', key: 'audit' },
  ];

  const linksHtml = items
    .map(
      (item) =>
        `<a href="${item.href}" class="${item.key === activePage ? 'active' : ''}"><span class="icon">${item.icon}</span>${item.label}</a>`
    )
    .join('');

  document.getElementById('sidebar').innerHTML = `
    <div class="brand">🐄 เว็บแอดมิน</div>
    <div class="admin-info">เข้าสู่ระบบเป็น<br><strong id="adminEmail">...</strong></div>
    <nav>${linksHtml}</nav>
    <div class="logout">
      <a href="#" onclick="logout(); return false;"><span class="icon">🚪</span>ออกจากระบบ</a>
    </div>
  `;

  // เติมอีเมลผู้ดูแลที่ login อยู่ ให้รู้ทันทีว่ากำลังใช้บัญชีไหนอยู่
  const cached = localStorage.getItem('admin_email');
  if (cached) document.getElementById('adminEmail').textContent = cached;
}