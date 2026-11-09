import pg from 'pg';
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
const client=new pg.Client({host:process.env.PGHOST,user:process.env.PGUSER,password:process.env.PGPASSWORD,database:'postgres',ssl:{rejectUnauthorized:true},connectionTimeoutMillis:15000});
try{
  await client.connect();
  const actor=(await client.query("select id from public.profiles where active and role_code='admin' order by created_at limit 1")).rows[0]?.id;assert.ok(actor);
  await client.query('begin');await client.query('set local role authenticated');
  await client.query("select set_config('request.jwt.claim.sub',$1,true)",[actor]);
  assert.equal((await client.query('select public.backup_scheduler_status() ready')).rows[0].ready,true);
  const id=(await client.query("select public.create_backup('Release 1.0.0 safety snapshot') id")).rows[0].id;
  const backup=(await client.query('select public.download_backup($1) backup',[id])).rows[0].backup;
  await client.query('commit');
  const directory=new URL('../../.tooling/backups/',import.meta.url);await mkdir(directory,{recursive:true});
  await writeFile(new URL('topolina-release-1.0.0.topolina.json',directory),JSON.stringify(backup));
  const state=(await client.query(`select
    (select count(*)::int from supabase_migrations.schema_migrations) migrations,
    (select count(*)::int from auth.users where email like 'topolina-qa-%@example.invalid') temporary_accounts,
    (select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity) unprotected_public_tables,
    (select count(*)::int from cron.job where jobname='topolina-automatic-backup' and active) active_backup_jobs`)).rows[0];
  assert.equal(state.temporary_accounts,0);assert.equal(state.unprotected_public_tables,0);assert.equal(state.active_backup_jobs,1);
  console.log(JSON.stringify(state));console.log('Release snapshot created on the server and exported to ignored operator backups.');
}catch(e){try{await client.query('rollback');}catch{}console.error(`Release health verification failed (${e.code??e.name}).`);process.exitCode=1;}
finally{await client.end();}
