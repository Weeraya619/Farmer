import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import 'dotenv/config';
import authRoutes from './routes/auth.js';
import farmRoutes from './routes/farms.js';
import financeRoutes from './routes/finances.js';
import cowRoutes from './routes/cows.js';
import deviceRoutes from './routes/devices.js';
import notificationRoutes from './routes/notifications.js';
import adminRoutes from './routes/admin.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
app.set('trust proxy', 1);

app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Device-Secret'],
}));
app.use(express.json());

app.use('/api/auth', authRoutes);
app.use('/api/farms', farmRoutes);
app.use('/api', financeRoutes);
app.use('/api', cowRoutes);
app.use('/api', deviceRoutes);
app.use('/api', notificationRoutes);
app.use('/api/admin', adminRoutes);

// เว็บแอดมิน — ไฟล์ HTML/CSS/JS ธรรมดา ไม่มี build step เข้าผ่าน http://localhost:3000/admin
app.use('/admin', express.static(path.join(__dirname, '../admin_web')));

app.get('/health', (req, res) => res.json({ status: 'ok' }));

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Server running on http://localhost:${port}`);
  console.log(`Admin panel: http://localhost:${port}/admin`);
});