import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

export async function verifySocial(db) {
  const alice = randomUUID(), bob = randomUUID(), outsider = randomUUID();
  const now = new Date();
  const at = Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),now.getUTCDate()-1,12)/1000;
  const day = new Date(at*1000).toISOString().slice(0,10);
  async function as(user) {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [user]);
    await db.exec('set role authenticated');
  }
  async function rpc(action='sync', payload={}) {
    const result = await db.query('select public.social_state($1,$2::jsonb) state', [action,JSON.stringify({timezone:'UTC',...payload})]);
    return result.rows[0].state;
  }
  const event = (kind,seconds,ending=at) => ({id:randomUUID(),kind,seconds,at:ending});
  await db.query('insert into auth.users(id,email) values ($1,$2),($3,$4),($5,$6)', [alice,'alice@example.invalid',bob,'bob@example.invalid',outsider,'outsider@example.invalid']);
  await db.query('insert into public.account_profiles(user_id,profile) values ($1,$2),($3,$4)', [alice,JSON.stringify({name:'Alice',symbol:'leaf.fill',color:'teal',photo:'PRIVATE'}),bob,JSON.stringify({name:'Bob',symbol:'book.fill',color:'blue'})]);
  await as(alice);
  const activation = at-10000;
  let state = await rpc('create',{name:'Steady people',activatedAt:activation});
  const group = state.groups[0];
  assert.equal(group.name,'Steady people');
  assert.equal(group.code.length,32);
  assert.equal(group.members[0].name,'Alice');
  assert(!JSON.stringify(state).includes('PRIVATE'));
  assert(!JSON.stringify(state).includes('alice@example'));
  await assert.rejects(db.query('select * from public.social_events'), /permission denied/);
  await assert.rejects(rpc('leave',{group:group.id}), /Delete your group/);
  await as(bob);
  state=await rpc('sync',{activatedAt:activation});
  assert.equal(state.groups.length,0);
  // Existing personal credit never becomes group credit.
  const historical=event('work',3600);
  state=await rpc('sync',{events:[historical]});
  assert.equal(state.progress.days[day].workSeconds,3600);
  state=await rpc('join',{code:group.code});
  assert.equal(state.groups[0].members.find(m=>m.id===bob).work,0);
  assert.equal(state.groups[0].code,null);
  await assert.rejects(rpc('reset',{group:group.id}), /Only the creator/);
  // Move the synthetic join dates back to exercise split intervals without waiting.
  await db.exec('reset role');
  await db.query("update public.social_members set joined_at=to_timestamp($1) where group_id=$2",[at-7200,group.id]);
  await as(bob);
  const almost=event('work',3599);
  state=await rpc('sync',{events:[almost]});
  assert.equal(state.groups[0].members.find(m=>m.id===bob).work,0);
  state=await rpc('sync',{events:[almost,event('work',1),event('break',59.99)]});
  assert.equal(state.groups[0].members.find(m=>m.id===bob).work,1);
  assert.equal(state.groups[0].members.find(m=>m.id===bob).habits,0);
  const rest=event('break',60);
  state=await rpc('sync',{events:[rest,rest]});
  assert.equal(state.groups[0].members.find(m=>m.id===bob).habits,1);
  state=await rpc('sync',{events:[event('break',120)]});
  assert.equal(state.groups[0].members.find(m=>m.id===bob).habits,1);
  await as(alice);
  state=await rpc('sync',{events:[event('work',3600),event('break',60)]});
  assert(state.groups[0].members.every(m=>m.workRank===1 && m.habitsRank===1));
  assert.deepEqual(state.groups[0].members.map(m=>m.name),['Alice','Bob']);
  await as(outsider);
  assert.equal((await rpc()).groups.length,0);
  await assert.rejects(rpc('remove',{group:group.id,member:bob}),/membership required/);
  await assert.rejects(rpc('sync',{events:[event('work',-1)]}),/Invalid progress summary/);
  // Invalid attempts persist despite failure; correct guesses are also throttled.
  for(let i=0;i<10;i++) assert((await rpc('join',{code:'wrong'})).error.includes('invalid'));
  assert((await rpc('join',{code:group.code})).error.includes('Too many'));
  await as(alice);
  state=await rpc('reset',{group:group.id});
  const replacement=state.groups[0].code;
  assert.notEqual(replacement,group.code);
  await as(bob);
  await rpc('leave',{group:group.id});
  assert((await rpc('join',{code:group.code})).error.includes('invalid'));
  state=await rpc('join',{code:replacement});
  assert.equal(state.groups[0].members.find(m=>m.id===bob).work,0);
  await db.exec('reset role');
  await db.query("update public.social_members set joined_at=to_timestamp($1) where group_id=$2 and user_id=$3",[at-1800,group.id,bob]);
  await as(bob);
  state=await rpc('sync',{events:[event('work',3600),event('break',1801)]});
  assert.equal(state.groups[0].members.find(m=>m.id===bob).work,0); // Only 1800 seconds earned after joining.
  assert.equal(state.groups[0].members.find(m=>m.id===bob).habits,0); // Break began before joining.
  state=await rpc('sync',{events:[event('work',1800),event('break',60)]});
  assert.equal(state.groups[0].members.find(m=>m.id===bob).work,1);
  assert.equal(state.groups[0].members.find(m=>m.id===bob).habits,1);
  await as(alice);
  state=await rpc('remove',{group:group.id,member:bob});
  assert.equal(state.groups[0].members.length,1);
  // Server timezone is stable even when another device reports a different one.
  state=await rpc('sync',{timezone:'Asia/Tokyo'});
  assert.equal(state.timezone,'UTC');
  // Deterministic month-limited freezes under a serialized account-row lock.
  await db.exec('reset role');
  await db.query("update public.social_accounts set activated_at='2026-01-01T00:00:00Z' where user_id=$1",[alice]);
  await db.query("insert into public.social_days(user_id,day,seconds) values($1,'2026-01-01',3600),($1,'2026-01-05',3600),($1,'2026-01-07',3600),($1,'2026-01-09',3600) on conflict(user_id,day) do update set seconds=excluded.seconds",[alice]);
  await as(alice);
  state=await rpc();
  assert.deepEqual(state.progress.frozenDays.filter(d=>d.startsWith('2026-01')),['2026-01-02','2026-01-06','2026-01-08']);
  const repeated=await rpc();
  assert.deepEqual(repeated.progress.frozenDays,state.progress.frozenDays);
  await db.exec('reset role');
  await db.query("insert into public.social_days(user_id,day,seconds) values($1,'2026-01-02',3600)",[alice]);
  await as(alice);
  state=await rpc();
  assert(!state.progress.frozenDays.includes('2026-01-02'));
  await db.exec('reset role');
  // Account deletion cascades through owned groups, membership scores and summaries.
  await db.query('delete from auth.users where id=$1',[alice]);
  for(const table of ['social_accounts','social_events','social_days','social_members','social_member_days']) {
    const {rows}=await db.query(`select count(*)::int n from public.${table} where user_id=$1`,[alice]);
    assert.equal(rows[0].n,0);
  }
  assert.equal((await db.query('select count(*)::int n from public.social_groups where id=$1',[group.id])).rows[0].n,0);
  await db.exec("set role anon");
  await assert.rejects(rpc(),/permission denied/);
  await db.exec('reset role');
  console.log('Private groups: invite rotation/throttling, access control, join-time scoring, ties, retry deduplication, freezes, timezone and deletion passed.');
}
