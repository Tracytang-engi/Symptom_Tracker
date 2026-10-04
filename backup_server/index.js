const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const crypto = require('crypto');

const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'dev-only-change-me';
const databaseUrl = process.env.DATABASE_URL;
const pool = new Pool({
  connectionString: databaseUrl,
  // 带 render.com 的是外网地址，要 SSL。同一账号里 Web Service 用的内网地址不用。
  ssl: databaseUrl && databaseUrl.includes('render.com')
    ? { rejectUnauthorized: false }
    : undefined,
});

const app = express();
app.use(express.json({ limit: '80mb' }));

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

async function initDb() {
  await pool.query('CREATE SCHEMA IF NOT EXISTS symptom');
  await pool.query(`
    CREATE TABLE IF NOT EXISTS symptom.users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS symptom.backups (
      user_id TEXT PRIMARY KEY REFERENCES symptom.users(id),
      payload TEXT NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
}

function signToken(user) {
  return jwt.sign({ sub: user.id, email: user.email }, JWT_SECRET, { expiresIn: '30d' });
}

function auth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return res.status(401).json({ error: 'Login required.' });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch (_) {
    res.status(401).json({ error: 'Login expired. Enter your password again.' });
  }
}

app.post('/auth/register', async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  if (!email.includes('@') || password.length < 6) {
    return res.status(400).json({ error: 'Use an email and a password of at least 6 characters.' });
  }
  const hash = await bcrypt.hash(password, 10);
  const id = crypto.randomUUID();
  try {
    await pool.query(
      'INSERT INTO symptom.users (id, email, password_hash) VALUES ($1, $2, $3)',
      [id, email, hash],
    );
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'That email is already registered.' });
    throw err;
  }
  res.json({ token: signToken({ id, email }) });
});

app.post('/auth/login', async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  const result = await pool.query('SELECT id, email, password_hash FROM symptom.users WHERE email = $1', [email]);
  const user = result.rows[0];
  if (!user || !(await bcrypt.compare(password, user.password_hash))) {
    return res.status(401).json({ error: 'Email or password is wrong.' });
  }
  res.json({ token: signToken(user) });
});

app.put('/backup', auth, async (req, res) => {
  await pool.query(
    `INSERT INTO symptom.backups (user_id, payload, updated_at)
     VALUES ($1, $2, now())
     ON CONFLICT (user_id) DO UPDATE SET payload = EXCLUDED.payload, updated_at = now()`,
    [req.user.sub, JSON.stringify(req.body)],
  );
  res.json({ ok: true });
});

app.get('/backup', auth, async (req, res) => {
  const result = await pool.query('SELECT payload FROM symptom.backups WHERE user_id = $1', [req.user.sub]);
  if (!result.rows[0]) return res.status(404).json({ error: 'No backup stored for this account.' });
  res.type('json').send(result.rows[0].payload);
});

initDb()
  .then(() => app.listen(PORT, () => console.log(`backup server on ${PORT}`)))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
