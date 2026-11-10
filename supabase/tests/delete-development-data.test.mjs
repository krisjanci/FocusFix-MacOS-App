import test from 'node:test';
import assert from 'node:assert/strict';

let handler;
globalThis.Deno = {
  env: { get: (key) => ({ SUPABASE_URL: 'https://example.supabase.co', SUPABASE_ANON_KEY: 'public-test', SUPABASE_SERVICE_ROLE_KEY: 'admin-test' })[key] },
  serve: (value) => { handler = value; },
};
await import('../functions/delete-development-data/index.ts');
const owner = '00000000-0000-4000-8000-000000000001';
const foreign = '00000000-0000-4000-8000-000000000002';

test('deletion requires a signed-in user before admin access', async () => {
  let calls = 0;
  globalThis.fetch = async () => { calls++; throw new Error('Unexpected request'); };
  assert.equal((await handler(new Request('https://example.invalid', { method: 'POST' }))).status, 401);
  assert.equal(calls, 0);
});

test('only verified owner data is deleted after consent is revoked', async () => {
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: owner });
    if (url.endsWith('/rpc/request_development_deletion')) return Response.json('30000000-0000-4000-8000-000000000001');
    if (url.endsWith('/object/list/development-recordings')) {
      const { prefix } = JSON.parse(options.body);
      if (prefix === owner) return Response.json([{ name: 'consent', id: null }]);
      assert.equal(prefix, `${owner}/consent`);
      return Response.json([{ name: 'recording.zip', id: 'object-id' }]);
    }
    return Response.json({});
  };
  const result = await handler(new Request('https://example.invalid', {
    method: 'POST', headers: { Authorization: 'Bearer user-test' }, body: JSON.stringify({ user_id: foreign }),
  }));
  assert.equal(result.status, 200);
  assert.ok(calls.find(({ url }) => url.endsWith('/rpc/request_development_deletion')));
  const deleted = calls.find(({ url, options }) => url.endsWith('/object/development-recordings') && options.method === 'DELETE');
  assert.deepEqual(JSON.parse(deleted.options.body), { prefixes: [`${owner}/consent/recording.zip`] });
  assert.ok(!JSON.stringify(calls).includes(foreign));
  assert.ok(!(await result.text()).includes('admin-test'));
});

test('failed cleanup keeps the deletion request pending and hides server details', async () => {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(url);
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: owner });
    if (url.endsWith('/rpc/request_development_deletion')) return Response.json('30000000-0000-4000-8000-000000000001');
    return new Response('sensitive server response', { status: 503 });
  };
  const result = await handler(new Request('https://example.invalid', {
    method: 'POST', headers: { Authorization: 'Bearer user-test' },
  }));
  assert.equal(result.status, 503);
  assert.ok(!calls.some(url => url.includes('/development_deletion_requests?')));
  assert.equal(await result.text(), '');
});
