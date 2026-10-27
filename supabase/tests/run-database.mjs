// Real PostgreSQL semantics in an isolated, in-memory database. No live service access.
import { verifySocial } from './social-database.mjs';
import { readFile, readdir } from 'node:fs/promises';
const { PGlite } = await import(process.env.FOCUSFIX_PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth; create schema storage;
    create table auth.users (id uuid primary key, email text);
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
    $$;
    grant usage on schema public,auth,storage to anon,authenticated;
    grant execute on function auth.uid() to anon,authenticated;
    create table storage.buckets (id text primary key, name text, public boolean,
      file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects (id uuid default gen_random_uuid() primary key,
      bucket_id text references storage.buckets(id), name text, unique(bucket_id,name));
    alter table storage.objects enable row level security;
    grant select,insert,update,delete on storage.objects to authenticated;
    create function storage.foldername(name text) returns text[] language sql immutable as $$
      select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1];
    $$;
  `);
  for (const file of (await readdir(new URL('../migrations/', import.meta.url))).filter(name => name.endsWith('.sql')).sort()) {
    await db.exec(await readFile(new URL(`../migrations/${file}`, import.meta.url), 'utf8'));
  }
  await db.exec(await readFile(new URL('consent-access.sql', import.meta.url), 'utf8'));
  await verifySocial(db);
  await db.exec(await readFile(new URL('social-live.sql', import.meta.url), 'utf8'));
  console.log('Rollback-only live verification script passed locally.');
  console.log('PostgreSQL: migrations, RLS, consent versions, withdrawal, deletion, cohort cap and account deletion passed.');
} finally { await db.close(); }
