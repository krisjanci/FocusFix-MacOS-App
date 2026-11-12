import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
export async function verifyInvitations(db) {
  const [admin, recipient, outsider] = [randomUUID(), randomUUID(), randomUUID()];
  const email = `${recipient}@example.invalid`;
  await db.exec('begin');
  try {
    await db.query('insert into auth.users(id,email) values($1,$2),($3,$4),($5,$6)',
      [admin, `${admin}@example.invalid`, recipient, email, outsider, `${outsider}@example.invalid`]);
    const as = async id => {
      await db.exec('reset role');
      await db.query("select set_config('request.jwt.claim.sub',$1,true)", [id]);
      await db.exec('set role authenticated');
    };
    const rpc = async (action='sync', payload={}) => (await db.query('select public.social_state($1,$2) state', [action, {timezone:'UTC', ...payload}])).rows[0].state;
    const inbox = async () => (await db.query('select public.group_invitations() inbox')).rows[0].inbox;
    await as(admin);
    let state = await rpc('create', {name:'Invitation test'});
    const group = state.groups[0];
    await rpc('invite', {group:group.id, email:email.toUpperCase()});
    await rpc('invite', {group:group.id, email});
    assert.deepEqual(await inbox(), []);
    await as(outsider);
    assert.deepEqual(await inbox(), []);
    // Use a savepoint so expected permission errors cannot abort the outer fixture.
    const denied = async (action,payload) => {
      await db.exec('savepoint denied');
      await assert.rejects(rpc(action,payload));
      await db.exec('rollback to denied');
    };
    await denied('invite', {group:group.id,email});
    await denied('edit', {group:group.id,name:'Stolen'});
    await denied('transfer', {group:group.id,member:outsider});
    await as(recipient);
    let invitations = await inbox();
    assert.equal(invitations.length,1);
    assert.equal(invitations[0].groupName,'Invitation test');
    assert.deepEqual(Object.keys(invitations[0]).sort(),['groupID','groupName','id','inviterName']);
    const invite = invitations[0].id;
    await db.exec('reset role');
    assert.equal((await db.query('select count(*)::int n from public.social_accounts where user_id=$1',[recipient])).rows[0].n,0);
    await as(outsider);
    assert((await rpc('accept',{invitation:invite})).error);
    await db.query('select public.decline_group_invitation($1)',[invite]);
    await as(recipient);
    assert.equal((await inbox()).length,1); // Outsiders cannot decline another inbox item.
    await db.query('select public.decline_group_invitation($1)',[invite]);
    assert.deepEqual(await inbox(),[]);
    await db.exec('reset role');
    assert.equal((await db.query('select count(*)::int n from public.social_accounts where user_id=$1',[recipient])).rows[0].n,0);
    await as(admin);
    await rpc('invite',{group:group.id,email});
    await as(recipient);
    invitations=await inbox();
    state=await rpc('accept',{invitation:invitations[0].id});
    assert.equal(state.groups[0].members.length,2);
    assert.deepEqual(state.invitations,[]);
    assert((await rpc('accept',{invitation:invitations[0].id})).error); // Retry never duplicates membership.
    assert.equal(state.groups[0].code,null);
    // A current member can invite, without gaining group-management permissions.
    await rpc('invite',{group:group.id,email:`${outsider}@example.invalid`});
    await as(outsider);
    const memberInvite = (await inbox())[0];
    assert.equal(memberInvite.groupID,group.id);
    assert.equal(memberInvite.inviterName,'Group member');
    await db.query('select public.decline_group_invitation($1)',[memberInvite.id]);
    await as(recipient);
    await denied('edit',{group:group.id,name:'Member edit'});
    await denied('transfer',{group:group.id,member:admin});
    await as(admin);
    state=await rpc('edit',{group:group.id,name:'Updated group',description:'A shared routine'});
    assert.equal(state.groups[0].description,'A shared routine');
    assert.equal(state.groups[0].name,'Updated group');
    assert((await rpc('edit',{group:group.id,name:' '})).error);
    state=await rpc('transfer',{group:group.id,member:recipient});
    assert.equal(state.groups[0].owner,recipient);
    assert.equal(state.groups[0].code,null);
    await denied('edit',{group:group.id,name:'Old admin'});
    await denied('remove',{group:group.id,member:recipient});
    await as(recipient);
    state=await rpc('sync');
    assert(state.groups[0].code);
    state=await rpc('remove',{group:group.id,member:admin});
    assert.equal(state.groups[0].members.length,1);
    assert.equal(state.groups[0].members[0].id,recipient);
    await db.exec('reset role');
    // Exercise the same missed-day, freeze, thaw and weekday policy with healthy days.
    await db.query("update public.social_members set joined_at='2026-10-19' where group_id=$1",[group.id]);
    await db.query("insert into public.social_member_days(group_id,user_id,day,healthy) values($1,$2,'2026-10-19',true)",[group.id,recipient]);
    const streak = async at => (await db.query('select * from public.social_group_habit_streak($1,$2,$3)',[recipient,group.id,at])).rows[0];
    assert.deepEqual(await streak('2026-10-19T16:00Z'),{streak:1,frozen:false});
    assert.deepEqual(await streak('2026-10-21T16:00Z'),{streak:1,frozen:true});
    assert.deepEqual(await streak('2026-10-22T16:00Z'),{streak:0,frozen:false});
    await db.query("insert into public.social_member_days(group_id,user_id,day,healthy) values($1,$2,'2026-10-21',true)",[group.id,recipient]);
    assert.deepEqual(await streak('2026-10-21T16:00Z'),{streak:2,frozen:false});
    for (const signature of ['social_group_habit_streak(uuid,uuid,timestamptz)','social_state_work_streaks(text,jsonb)']) {
      assert.equal((await db.query("select has_function_privilege('authenticated',$1,'execute') allowed",[`public.${signature}`])).rows[0].allowed,false);
    }
    assert.equal((await db.query("select has_table_privilege('authenticated','public.social_invitations','select') allowed")).rows[0].allowed,false);
    await db.exec('set role anon');
    await db.exec('savepoint anon_denied');
    await assert.rejects(db.query('select public.group_invitations()'));
    await db.exec('rollback to anon_denied');
    console.log('Invitation inbox isolation, deduplication, accept/decline without implicit sharing, admin edit/transfer/removal and habit streak resets passed.');
  } finally { await db.exec('rollback'); }
}
