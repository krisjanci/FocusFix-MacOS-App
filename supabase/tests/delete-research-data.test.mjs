import test from 'node:test';
import assert from 'node:assert/strict';
let handler;
globalThis.Deno = {
  env: { get: (key) => ({ SUPABASE_URL: 'https://example.supabase.co', SUPABASE_ANON_KEY: 'public-test', SUPABASE_SERVICE_ROLE_KEY: 'admin-test' })[key] },
  serve: (value) => { handler = value; },
};
await import('../functions/delete-research-data/index.ts');
const owner = '00000000-0000-4000-8000-000000000001';
const requestID = '30000000-0000-4000-8000-000000000001';
const request = () => new Request('https://example.invalid', { method: 'POST', headers: { Authorization: 'Bearer test-access' }, body: '{"user_id":"foreign"}' });

test('research deletion revokes before storage cleanup and keeps the account', async () => {
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: owner });
    if (url.endsWith('/rpc/request_research_deletion')) {
      assert.equal(options.headers.Authorization, 'Bearer test-access');
      return Response.json(requestID);
    }
    if (url.endsWith('/object/list/research-sessions')) return Response.json([{ name: 'fixture.zip', id: 'object' }]);
    return Response.json({});
  };
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).status, 'hosted_deleted');
  assert.ok(calls[1].url.endsWith('/rpc/request_research_deletion'));
  assert.ok(!calls.some(({ url }) => url.includes('/auth/v1/admin/')));
  assert.ok(calls.at(-1).url.includes(`participant_reference=eq.${owner}`));
  assert.deepEqual(JSON.parse(calls.at(-1).options.body), { status: 'hosted_deleted' });
  assert.ok(!JSON.stringify(calls).includes('foreign'));
});

test('cleanup failure leaves the previously recorded request pending for retry', async () => {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(url);
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: owner });
    if (url.endsWith('/rpc/request_research_deletion')) return Response.json(requestID);
    return new Response('private server response', { status: 503 });
  };
  const response = await handler(request());
  assert.equal(response.status, 503);
  assert.equal(await response.text(), '');
  assert.ok(calls[1].endsWith('/rpc/request_research_deletion'));
  assert.ok(!calls.some((url) => url.includes('research_deletion_requests?')));
});

test('rejects unsafe storage paths and does not mark cleanup completed', async () => {
  globalThis.fetch = async (url) => {
    if (url.endsWith('/auth/v1/user')) return Response.json({ id: owner });
    if (url.endsWith('/rpc/request_research_deletion')) return Response.json(requestID);
    if (url.endsWith('/object/list/research-sessions')) return Response.json([{ name: '../foreign', id: 'object' }]);
    assert.fail('Unsafe path reached deletion');
  };
  assert.equal((await handler(request())).status, 503);
});
