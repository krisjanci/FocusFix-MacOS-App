import test from 'node:test';
import assert from 'node:assert/strict';

let handler;
globalThis.Deno = {
  env: { get: (key) => ({ SUPABASE_URL: 'https://example.supabase.co', SUPABASE_ANON_KEY: 'public-test', SUPABASE_SERVICE_ROLE_KEY: 'admin-test' })[key] },
  serve: (value) => { handler = value; },
};
await import('../functions/delete-account/index.ts');
const owner = '00000000-0000-4000-8000-000000000001';
const foreign = '00000000-0000-4000-8000-000000000002';

test('requires authentication before any admin call', async () => {
  let calls = 0;
  globalThis.fetch = async () => { calls++; throw new Error('Unexpected network'); };
  assert.equal((await handler(new Request('https://example.invalid', { method: 'POST' }))).status, 401);
  assert.equal(calls, 0);
});

test('rejects an invalid user without touching storage or admin APIs', async () => {
  const calls = [];
  globalThis.fetch = async (url) => { calls.push(url); return new Response(null, { status: 401 }); };
  const result = await handler(new Request('https://example.invalid', { method: 'POST', headers: { Authorization: 'Bearer user-test' } }));
  assert.equal(result.status, 401);
  assert.deepEqual(calls, ['https://example.supabase.co/auth/v1/user']);
});

test('uses verified user ID; ignores a foreign user ID supplied in the request', async () => {
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: owner });
    if (url.endsWith('/rpc/request_research_deletion')) return Response.json('30000000-0000-4000-8000-000000000001');
    if (url.endsWith('/object/list/research-sessions')) {
      const { prefix } = JSON.parse(options.body);
      if (prefix === owner) return Response.json([{ name: 'consent', id: null }]);
      assert.equal(prefix, `${owner}/consent`);
      return Response.json([{ name: 'batch.zip', id: 'object-id' }]);
    }
    return Response.json({});
  };
  const result = await handler(new Request('https://example.invalid', {
    method: 'POST', headers: { Authorization: 'Bearer user-test' }, body: JSON.stringify({ user_id: foreign }),
  }));
  assert.equal(result.status, 200);
  const deleted = calls.find(({ url, options }) => url.endsWith('/object/research-sessions') && options.method === 'DELETE');
  assert.deepEqual(JSON.parse(deleted.options.body), { prefixes: [`${owner}/consent/batch.zip`] });
  assert.equal(calls.at(-1).url, `https://example.supabase.co/auth/v1/admin/users/${owner}`);
  assert.ok(!JSON.stringify(calls).includes(foreign));
  assert.ok(!(await result.text()).includes('admin-test'));
});

test('storage failure prevents deleting the account and hides server error contents', async () => {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(url);
    return url.endsWith('/auth/v1/user') ? Response.json({ id: owner }) : new Response('sensitive response', { status: 503 });
  };
  const result = await handler(new Request('https://example.invalid', { method: 'POST', headers: { Authorization: 'Bearer user-test' } }));
  assert.equal(result.status, 503);
  assert.ok(!calls.some((url) => url.includes('/auth/v1/admin/')));
  assert.equal(await result.text(), '');
});
