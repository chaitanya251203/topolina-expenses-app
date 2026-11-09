import pg from 'pg';
import { readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

const action = process.argv[2] ?? 'inspect';
if (!['inspect', 'migrate', 'verify', 'bootstrap', 'backup'].includes(action)) throw new Error('Use inspect, migrate, verify, bootstrap or backup.');
const client = new pg.Client({
  host: process.env.PGHOST ?? 'db.frpekgewxpdzcikpzsit.supabase.co',
  port: Number(process.env.PGPORT ?? 5432),
  user: process.env.PGUSER ?? 'postgres', database: 'postgres',
  password: process.env.PGPASSWORD,
  ssl: { rejectUnauthorized: true }, connectionTimeoutMillis: 15000,
});
try {
  await client.connect();
  const tables = await client.query("select table_name from information_schema.tables where table_schema='public' order by table_name");
  console.log(JSON.stringify({ tables: tables.rows.map(r => r.table_name) }));
  if(action==='backup'){
    // Exact JSON text is produced by Postgres, never parsed into JS doubles.
    // This is an app-data safety snapshot, not a replacement for project/Auth backup.
    const exports=[];
    await client.query('begin isolation level repeatable read read only');
    try{
      const sources=await client.query(`select table_schema,table_name from information_schema.tables
        where table_type='BASE TABLE' and (table_schema='public' or
          (table_schema='private' and table_name='financial_requests') or
          (table_schema='supabase_migrations' and table_name='schema_migrations'))
        order by table_schema,table_name`);
      const quote=name=>'"'+name.replaceAll('"','""')+'"';
      for(const source of sources.rows){
        const records=await client.query(`select row_to_json(t)::text exact_json from ${quote(source.table_schema)}.${quote(source.table_name)} t`);
        exports.push(JSON.stringify(`${source.table_schema}.${source.table_name}`)+':['+records.rows.map(row=>row.exact_json).join(',')+']');
      }
      await client.query('commit');
    }catch(error){await client.query('rollback');throw error;}
    const directory=new URL('../../.tooling/backups/',import.meta.url);
    await mkdir(directory,{recursive:true});
    const stamp=new Date().toISOString().replaceAll(':','-');
    const path=new URL(`topolina-app-data-${stamp}.json`,directory);
    await writeFile(path,'{"format":"topolina-app-data-v1","created_at":'+JSON.stringify(new Date().toISOString())+',"tables":{'+exports.join(',')+'}}',{flag:'wx'});
    console.log('Application-data safety snapshot saved in .tooling/backups.');
  }
  if (action === 'verify') {
    const result = await client.query(`select
      (select count(*)::int from public.categories) category_count,
      (select count(*)::int from public.profiles where role_code='admin') admin_count,
      (select count(*)::int from pg_policies where schemaname='public') policy_count,
      (select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='public' and c.relkind='r' and not c.relrowsecurity) unprotected_tables`);
    console.log(JSON.stringify(result.rows[0]));
  }
  if (action === 'bootstrap') {
    const email = process.env.TOPOLINA_ADMIN_EMAIL;
    const name = process.env.TOPOLINA_ADMIN_NAME;
    if (!email || !name) throw new Error('Admin email and name are required.');
    const users = await client.query('select id from auth.users where lower(email)=lower($1)', [email]);
    if (users.rowCount !== 1) throw new Error('Create the Auth user first.');
    await client.query('select public.bootstrap_admin($1,$2)', [users.rows[0].id, name]);
    console.log('Administrator profile provisioned.');
  }
  if (action === 'migrate') {
    const migrations = new URL('../../supabase/migrations/', import.meta.url);
    await client.query('create schema if not exists supabase_migrations');
    await client.query('create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text)');
    const files = (await readdir(migrations)).filter(f => f.endsWith('.sql')).sort();
    for (const file of files) {
      const version = file.split('_')[0];
      if ((await client.query('select 1 from supabase_migrations.schema_migrations where version=$1', [version])).rowCount) continue;
      const sql = await readFile(new URL(file, migrations), 'utf8');
      // Every migration is a single transaction; history is recorded in it.
      const body = sql.replace(/^begin;\s*$/im, '').replace(/^commit;\s*$/im, '');
      await client.query('begin');
      try {
        await client.query(body);
        await client.query('insert into supabase_migrations.schema_migrations(version,name,statements) values ($1,$2,$3)',
          [version, file.slice(version.length + 1, -4), [sql]]);
        await client.query('commit');
        console.log(`Applied ${file} (${createHash('sha256').update(sql).digest('hex').slice(0, 12)})`);
      } catch (error) { await client.query('rollback'); throw error; }
    }
  }
} catch (error) {
  // Never print the connection URL, password or database response payload.
  console.error(`Database operation failed (${error.code ?? error.name}).`);
  process.exitCode = 1;
} finally { await client.end(); }
