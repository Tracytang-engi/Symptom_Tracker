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

app.get('/privacy', (_req, res) => {
  res.type('html').send(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Symptom Tracker Privacy Policy</title>
  <style>
    body { max-width: 760px; margin: 48px auto; padding: 0 20px; font: 16px/1.6 system-ui, sans-serif; color: #17252a; }
    h1, h2 { line-height: 1.25; }
    h2 { margin-top: 28px; font-size: 1.15rem; }
  </style>
</head>
<body>
  <h1>Symptom Tracker Privacy Policy</h1>
  <p>Last updated: 4 October 2026</p>
  <h2>Data on your device</h2>
  <p>Episode records, notes, and voice recordings stay on your phone by default. The app does not read a server when it opens.</p>
  <h2>Optional account and backup</h2>
  <p>Backup is optional and manual. If you create or use a backup account, your account email is sent to the backup service. When you choose Back up now, episode records and their voice recordings are uploaded and linked to your account. This information is used only to provide account, backup, and recovery features. It is not used for tracking. SOS location is not included in backups.</p>
  <h2>SOS messages</h2>
  <p>The SOS feature only opens a text-message draft. You must review it and press Send yourself. If location permission is granted, your location may be placed in that draft for the recipient. Symptom Tracker is not an emergency service. In an emergency, call emergency services first or contact your guardian directly.</p>
  <h2>Health statement</h2>
  <p>Symptom Tracker is a recording tool. It does not diagnose or treat any condition.</p>
  <h2>Deleting your account</h2>
  <p>In the app, go to Settings &gt; Account &amp; backup &gt; Delete account. This deletes your account and backup from the server. Episode records stored on your phone are kept unless you separately delete them from the Privacy page.</p>
</body>
</html>`);
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

app.delete('/account', auth, async (req, res, next) => {
  let client;
  try {
    client = await pool.connect();
    await client.query('BEGIN');
    await client.query('DELETE FROM symptom.backups WHERE user_id = $1', [req.user.sub]);
    await client.query('DELETE FROM symptom.users WHERE id = $1', [req.user.sub]);
    await client.query('COMMIT');
    res.json({ ok: true });
  } catch (err) {
    if (client) await client.query('ROLLBACK');
    next(err);
  } finally {
    if (client) client.release();
  }
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'Server error.' });
});

initDb()
  .then(() => app.listen(PORT, () => console.log(`backup server on ${PORT}`)))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
