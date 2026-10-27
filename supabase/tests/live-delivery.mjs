// Opt-in integration test: TWO PRE-CREATED disposable accounts, generated data only.
// Never run against the participant project. No tokens/passwords/server bodies are logged.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}
const origin = new URL(required('FOCUSFIX_TEST_SUPABASE_URL'));
const project = required('FOCUSFIX_TEST_PROJECT_REF');
assert.equal(origin.protocol, 'https:');
assert.equal(origin.hostname, `${project}.supabase.co`);
assert.ok(!origin.username && !origin.password && !origin.search && !origin.hash);
assert.equal(origin.pathname, '/');
assert.notEqual(project, 'ltgyhstpbiocuxvyjpcb', 'The configured participant project cannot be used for this test');
assert.equal(required('FOCUSFIX_TEST_ALLOW_ACCOUNT_DELETION'), 'YES_DISPOSABLE_ACCOUNTS');
const publicKey = required('FOCUSFIX_TEST_PUBLIC_KEY');
assert.ok(publicKey.startsWith('sb_publishable_'), 'Use a public publishable key, never a service credential');
const url = origin.origin;
async function call(path, body, session, method = 'POST', extraHeaders = {}) {
  const response = await fetch(`${url}/${path}`, {
    method,
    headers: { apikey: publicKey, 'Content-Type': 'application/json',
      ...(session ? { Authorization: `Bearer ${session.access_token}` } : {}), ...extraHeaders },
    body: method === 'GET' ? undefined : (Buffer.isBuffer(body) ? body : JSON.stringify(body ?? {})),
    redirect: 'error',
  });
  return response;
}
async function accepted(path, body, session, method, headers) {
  const response = await call(path, body, session, method, headers);
  assert.ok(response.ok, `Synthetic ${path.split('?')[0]} request failed: HTTP ${response.status}`);
  return response;
}
const sessions = [];
try {
  for (const name of ['A','B']) {
    const email = required(`FOCUSFIX_TEST_EMAIL_${name}`);
    assert.ok(email.endsWith('@example.invalid'), 'Only pre-created example.invalid fixtures are allowed');
    const session = await (await accepted('auth/v1/token?grant_type=password', {
      email, password: required(`FOCUSFIX_TEST_PASSWORD_${name}`),
    })).json();
    const refreshed = await (await accepted('auth/v1/token?grant_type=refresh_token', { refresh_token: session.refresh_token })).json();
    assert.equal(refreshed.user.id, session.user.id);
    sessions.push(refreshed);
  }
  assert.notEqual(sessions[0].user.id, sessions[1].user.id);
  const [study] = await (await accepted('rest/v1/research_study', null, sessions[0], 'GET')).json();
  assert.ok(study.collection_enabled && study.recruitment_enabled);
  assert.ok(study.determination_reference.startsWith('SYNTHETIC'), 'The test project must be explicitly configured for synthetic verification');
  assert.equal(study.future_training, false);
  const paths = [];
  for (const session of sessions) {
    await accepted('rest/v1/rpc/request_research_participation', { p_version: study.version, p_adult_us: true, p_eligible: true }, session);
    session.consentID = randomUUID();
    session.version = study.version;
    await accepted('rest/v1/rpc/set_research_consent', { p_consent_id: session.consentID, p_version: study.version, p_enabled: true }, session);
    const id = randomUUID();
    const archiveID = randomUUID();
    // Six generated files; no filesystem recordings or private profiles are read.
    const zip = execFileSync('python3', ['-c', `
import io, sys, zipfile, json
out=io.BytesIO()
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as archive:
    for name in ['events.csv','mouse_movement.csv','breaks.csv','surveys.csv','survey_prompts.csv']:
        archive.writestr(sys.argv[1]+'/'+name, 'synthetic_fixture\\nNO_HUMAN_DATA\\n')
    archive.writestr(sys.argv[1]+'/session.json',json.dumps({'session_id':sys.argv[1],'synthetic':True}))
sys.stdout.buffer.write(out.getvalue())
`, id]);
    const path = `${session.user.id}/${session.consentID}/${archiveID}.zip`;
    await accepted(`storage/v1/object/research-sessions/${path}`, zip, session, 'POST', { 'Content-Type': 'application/zip', 'x-upsert': 'true' });
    await accepted('rest/v1/rpc/confirm_research_upload', { p_archive_id: archiveID, p_object_name: path }, session);
    const receipts = await (await accepted(`rest/v1/research_upload_receipts?archive_id=eq.${archiveID}&select=archive_id`, null, session, 'GET')).json();
    assert.equal(receipts.length, 1);
    paths.push({ path, zip });
  }
  const foreignRead = await call(`storage/v1/object/authenticated/research-sessions/${paths[1].path}`, null, sessions[0], 'GET');
  assert.ok(!foreignRead.ok, 'Cross-user download was accepted');
  const foreignWrite = await call(`storage/v1/object/research-sessions/${paths[1].path}`, paths[0].zip, sessions[0], 'POST', { 'Content-Type': 'application/zip', 'x-upsert': 'true' });
  assert.ok(!foreignWrite.ok, 'Cross-user overwrite was accepted');
  const first = sessions[0];
  await accepted('rest/v1/rpc/set_research_consent', { p_consent_id: first.consentID, p_version: first.version, p_enabled: false }, first);
  const revoked = await call(`storage/v1/object/research-sessions/${first.user.id}/${first.consentID}/${randomUUID()}.zip`, paths[0].zip, first, 'POST', { 'Content-Type': 'application/zip' });
  assert.ok(!revoked.ok, 'Withdrawn consent could still upload');
  await accepted('functions/v1/delete-research-data', {}, first);
  const deletions = await (await accepted('rest/v1/research_deletion_requests?select=status', null, first, 'GET')).json();
  assert.ok(deletions.some(row => row.status === 'hosted_deleted'));
  console.log('Live disposable-project authentication, token refresh, ZIP delivery, receipts, isolation, withdrawal and hosted deletion passed.');
} finally {
  // Explicit opt-in above is required because this permanently deletes both fixture accounts.
  for (const session of sessions) {
    const result = await call('functions/v1/delete-account', {}, session);
    assert.ok(result.ok, `Disposable account cleanup needs attention: HTTP ${result.status}`);
  }
}
