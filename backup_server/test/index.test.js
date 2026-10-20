const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function setup() {
  const routes = new Map();
  const middleware = [];
  const queries = [];
  let config;
  let failure;
  const pool = {
    on() {},
    async query(sql, values) {
      queries.push({ sql, values });
      if (failure) throw failure;
      return { rows: [] };
    },
  };
  const app = { use(handler) { middleware.push(handler); }, listen() {} };
  for (const method of ['get', 'post', 'put', 'delete']) {
    app[method] = (route, ...handlers) => routes.set(`${method} ${route}`, handlers);
  }
  const express = Object.assign(() => app, { json: () => () => {} });
  const dependencies = {
    express,
    bcryptjs: { hash: async () => 'hash', compare: async () => true },
    jsonwebtoken: { verify: () => ({ sub: 'test-user' }), sign: () => 'token' },
    pg: { Pool: function (options) { config = options; return pool; } },
    crypto: { randomUUID: () => 'test-user' },
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8'), {
    require: (name) => dependencies[name],
    process: { env: {}, exit() { throw new Error('Unexpected exit'); } },
    console: { log() {}, error() {} },
  });
  await new Promise(setImmediate);
  return { routes, queries, config, middleware, fail(error) { failure = error; } };
}

function response() {
  return { code: 200, body: null,
    status(code) { this.code = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('Backup acknowledges only after database save and requires login', async () => {
  const server = await setup();
  const [auth, upload] = server.routes.get('put /backup');
  const unauthorized = response();
  auth({ headers: {} }, unauthorized, () => assert.fail('Must require login'));
  assert.equal(unauthorized.code, 401);
  const res = response();
  await upload({ user: { sub: 'test-user' }, body: { events: [] } }, res,
    () => assert.fail('Unexpected error'));
  assert.equal(res.body.ok, true);
  const query = server.queries.at(-1);
  assert.match(query.sql, /INSERT INTO symptom.backups/);
  assert.equal(query.values[0], 'test-user');
  assert.equal(query.values[1], '{"events":[]}');
  assert.equal(server.config.connectionTimeoutMillis, 10000);
  assert.equal(server.config.statement_timeout, 25000);
  assert.equal(server.config.query_timeout, 30000);
});

test('Database failures are forwarded, not left as unhandled rejections', async () => {
  const server = await setup();
  const failure = new Error('Query timed out');
  server.fail(failure);
  for (const route of ['put /backup', 'get /backup', 'post /auth/login', 'post /auth/register']) {
    let error;
    await server.routes.get(route).at(-1)({
      user: { sub: 'test-user' }, body: { email: 'test@example.com', password: 'example-password' },
    }, response(), (err) => { error = err; });
    assert.equal(error, failure, route);
  }
  const res = response();
  server.middleware.at(-1)(failure, {}, res, () => {});
  assert.equal(res.code, 500);
  assert.equal(res.body.error, 'Server error.');
});

test('Oversized backup has a specific HTTP 413 response', async () => {
  const server = await setup();
  const res = response();
  server.middleware.at(-1)({ type: 'entity.too.large' }, {}, res, () => {});
  assert.equal(res.code, 413);
});
