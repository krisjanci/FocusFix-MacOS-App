// FF: SCALABILITY BENCHMARK. Synthetic in-memory PostgreSQL only; no hosted traffic.
// Run: node supabase/tests/scalability-benchmark.mjs [--storage]
// Reports serialized response bytes, NOT billed HTTP bytes or hosted load capacity.
import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID, createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import assert from 'node:assert/strict';
const db = new PGlite();
const results = { method: 'Isolated migration schema; serialized PostgreSQL JSON and illustrative gzip only', scenarios: [] };
function image(seed, length) {
  const chunks = Array.from({ length: Math.ceil(length / 32) }, (_, i) => createHash('sha256').update(seed + ':' + i).digest());
  return Buffer.concat(chunks).subarray(0, length).toString('base64');
}
async function rpc(payload = {}) {
  const start = performance.now();
  const { rows } = await db.query("select public.social_state('sync',$1)::text state", [JSON.stringify({ timezone: 'UTC', ...payload })]);
  const raw = rows[0].state;
  return { state: JSON.parse(raw), rawBytes: Buffer.byteLength(raw), gzipBytes: gzipSync(raw).length, milliseconds: performance.now() - start };
}
function size(result) { const { state, ...measurement } = result; return measurement; }
try {
  const runner = await readFile(new URL('run-database.mjs', import.meta.url), 'utf8');
  await db.exec(runner.split('await db.exec(`')[1].split('`);')[0]);
  for (const file of (await readdir(new URL('../migrations/', import.meta.url))).filter(x => x.endsWith('.sql')).sort()) {
    await db.exec(await readFile(new URL('../migrations/' + file, import.meta.url), 'utf8'));
  }
  for (const [members, days] of [[3, 30], [10, 30], [10, 360], [50, 30]]) {
    await db.exec('begin');
    const users = Array.from({ length: members }, () => randomUUID()), group = randomUUID(), photos = {};
    for (const [i, user] of users.entries()) {
      const thumbnail = image(user, 4096); photos[user] = createHash('md5').update(thumbnail).digest('hex');
      await db.query('insert into auth.users(id,email) values($1,$2)', [user, `synthetic-${i}@example.invalid`]);
      await db.query('insert into public.account_profiles(user_id,profile) values($1,$2)', [user, JSON.stringify({ name: `Member ${i}`, symbol: 'leaf.fill', color: 'teal', photo: image(user + 'private', 16384), groupPhoto: thumbnail })]);
      await db.query("insert into public.social_accounts(user_id,timezone,activated_at) values($1,'UTC',current_date-$2::int)", [user, days]);
    }
    await db.query('insert into public.social_groups(id,owner,name) values($1,$2,$3)', [group, users[0], 'Synthetic group']);
    for (const user of users) {
      await db.query('insert into public.social_members(group_id,user_id,joined_at) values($1,$2,current_date-$3::int)', [group, user, days]);
      await db.query("insert into public.social_days(user_id,day,seconds,breaks) select $1,current_date-d,7200,array[md5(d::text||1)::uuid::text,md5(d::text||2)::uuid::text,md5(d::text||3)::uuid::text,md5(d::text||4)::uuid::text] from generate_series(1,$2::int)d", [user, days]);
      await db.query('insert into public.social_member_days(group_id,user_id,day,seconds,healthy) select $1,$2,current_date-d,7200,true from generate_series(1,$3::int)d', [group, user, days]);
    }
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [users[0]]);
    const legacy = await rpc();
    const cold = await rpc({ syncVersion: 2 });
    const base = { syncVersion: 2, progressRevision: cold.state.progressRevision, progressMetadataVersion: cold.state.progressMetadataVersion, groupVersion: cold.state.groupVersion, photoVersions: photos };
    const warm = await rpc(base);
    assert.equal(warm.state.groupsIncluded, false);
    assert.deepEqual(warm.state.progress.days, {});
    assert(warm.rawBytes < 1500, 'Unchanged transfer must remain bounded independent of history and group photo size');
    const now = Number((await db.query('select extract(epoch from now())::float8 t')).rows[0].t);
    const hiddenWrite = await rpc({ ...base, includeGroups: false, segments: [{ ownerID: users[0], segmentID: randomUUID(), contractVersion: 2, revision: 1, startedAt: now - 3600, observedThrough: now, intervals: [{ start: now - 3600, end: now }] }] });
    assert.equal(hiddenWrite.state.groupsIncluded, false);
    assert.equal(hiddenWrite.state.acknowledgedWork.length, 1);
    const changed = await rpc({ ...base, progressRevision: hiddenWrite.state.progressRevision });
    assert.equal(changed.state.groupsIncluded, true);
    assert(changed.state.groups.every(g => g.members.every(m => m.photo === undefined)), 'Known photos retransmitted');
    results.scenarios.push({ members, historyDays: days, thumbnailBytes: 4096, legacy: size(legacy), compactCold: size(cold), compactUnchanged: size(warm), compactHiddenWork: size(hiddenWrite), compactChangedScores: size(changed) });
    await db.exec('rollback');
  }
  if (process.argv.includes('--storage')) {
    // One clean month for 1,000 users, two work segments and four breaks per day.
    await db.exec(`
      create temporary table benchmark_users as select i,md5('bench-user-'||i)::uuid u,md5('bench-group-'||((i-1)/10))::uuid g from generate_series(1,1000)i;
      insert into auth.users(id,email) select u,'bench-'||i||'@example.invalid' from benchmark_users;
      insert into public.account_profiles(user_id,profile) select u,jsonb_build_object('name','Member '||i,'symbol','leaf.fill','color','teal') from benchmark_users;
      insert into public.social_accounts(user_id,timezone,activated_at) select u,'UTC',current_date-30 from benchmark_users;
      insert into public.social_groups(id,owner,name) select g,u,'Group '||i from benchmark_users where (i-1)%10=0;
      insert into public.social_members(group_id,user_id,joined_at) select g,u,current_date-30 from benchmark_users;
      insert into public.social_events(user_id,id,kind,ended_at,seconds) select u,md5(u::text||d||b)::uuid,'break',current_date-d+b*interval '1 hour',60 from benchmark_users cross join generate_series(1,30)d cross join generate_series(1,4)b;
      insert into public.social_days(user_id,day,seconds,declared_seconds,breaks) select u,current_date-d,7200,7200,array[md5(u::text||d||1)::uuid::text,md5(u::text||d||2)::uuid::text,md5(u::text||d||3)::uuid::text,md5(u::text||d||4)::uuid::text] from benchmark_users cross join generate_series(1,30)d;
      insert into public.social_member_days(group_id,user_id,day,seconds,declared_seconds,healthy) select g,u,current_date-d,7200,7200,true from benchmark_users cross join generate_series(1,30)d;
      insert into public.social_work_segments(segment_id,user_id,revision,started_at,observed_through,intervals) select md5(u::text||d||s)::uuid,u,1,current_date-d+s*interval '2 hours',current_date-d+s*interval '2 hours'+interval '1 hour',jsonb_build_array(jsonb_build_object('start',extract(epoch from current_date-d+s*interval '2 hours'),'end',extract(epoch from current_date-d+s*interval '2 hours'+interval '1 hour'))) from benchmark_users cross join generate_series(1,30)d cross join generate_series(1,2)s;
      insert into public.social_work_days(segment_id,user_id,day,seconds) select segment_id,user_id,started_at::date,3600 from public.social_work_segments;
      insert into public.social_work_member_days(segment_id,group_id,user_id,day,seconds) select s.segment_id,u.g,s.user_id,s.started_at::date,3600 from public.social_work_segments s join benchmark_users u on s.user_id=u.u;
    `);
    await db.exec('vacuum full');
    await db.exec('analyze');
    results.storage = (await db.query("select t.tablename,pg_total_relation_size(quote_ident(t.schemaname)||'.'||quote_ident(t.tablename))::text bytes from pg_tables t where schemaname='public' and (tablename like 'social_%' or tablename='account_profiles') order by tablename")).rows;
    results.storageNote = '1,000 social users, 30 days, two segments and four breaks per user-day; no images, production Auth, bloat or populated derived caches';
  }
  console.log(JSON.stringify(results, null, 2));
} finally { await db.close(); }
