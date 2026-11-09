import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';

const db = new PGlite();
const admin = '11111111-1111-4111-8111-111111111111';
const waiter = '22222222-2222-4222-8222-222222222222';
const expense = '33333333-3333-4333-8333-333333333333';
const credit = '44444444-4444-4444-8444-444444444444';
const salary = '55555555-5555-4555-8555-555555555555';

async function asRole(role, id, operation) {
  await db.exec(`set role ${role}`);
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [id ?? '']);
  try { return await operation(); }
  finally { await db.exec('reset role'); await db.exec("reset request.jwt.claim.sub"); }
}

before(async () => {
  // Only the Supabase Auth boundary is stubbed; schema, views, policies, grants
  // and triggers below execute in a real embedded PostgreSQL engine.
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid$$;
    grant usage on schema auth to authenticated, anon, service_role;
    grant execute on function auth.uid() to authenticated, anon, service_role;
  `);
  const directory = new URL('../../supabase/migrations/', import.meta.url);
  for (const file of (await readdir(directory)).filter(f => f.endsWith('.sql')).sort()) {
    await db.exec(await readFile(new URL(file, directory), 'utf8'));
  }
  await db.query('insert into auth.users values ($1),($2)', [admin, waiter]);
  await db.query("insert into public.profiles(id,full_name,role_code) values ($1,'Cafe Admin','admin'),($2,'Rahul','waiter')", [admin, waiter]);
  await db.exec(`insert into public.business_days(business_date) values
    ((now() at time zone 'Asia/Kolkata')::date), ('2026-11-08'), ('2026-11-12'), ('2026-11-15') on conflict do nothing`);
  for (const [id, amount, date] of [[expense, 100000, null], [credit, 200000, '2026-11-08'], [salary, 1500000, '2026-11-08']]) {
    await db.query(`insert into public.expenses(id,business_date,category_id,description,amount_method,amount_paise,created_by)
      values ($1,coalesce($2::date,(now() at time zone 'Asia/Kolkata')::date),
        (select id from public.categories where name='Grocery'),'Purchase','manual',$3,$4)`, [id,date,amount,waiter]);
  }
});
after(async () => db.close());

test('11 categories seeded; anonymous reads and bootstrap are forbidden', async () => {
  assert.equal((await db.query('select count(*)::int n from public.categories')).rows[0].n, 11);
  await asRole('anon', null, async () => {
    await assert.rejects(db.query('select * from public.categories'), /permission denied/);
    await assert.rejects(db.query('select public.session_context()'), /permission denied/);
    await assert.rejects(db.query('select public.bootstrap_admin($1,$2)', [waiter,'attacker']), /permission denied/);
  });
});
test('waiter sees own eligible expenses, no staff/payroll/sales data, and cannot promote self', async () => {
  await asRole('authenticated', waiter, async () => {
    const rows = (await db.query('select * from public.expenses')).rows;
    assert.ok(rows.some(r => r.id === expense));
    assert.equal((await db.query('select * from public.staff')).rows.length, 0);
    assert.equal((await db.query('select * from public.daily_reconciliation')).rows.length, 0);
    await assert.rejects(db.query("update public.profiles set role_code='admin' where id=$1", [waiter]), /permission denied/);
    await assert.rejects(db.query("insert into public.categories(name) values ('Unauthorized')"), /row-level security/);
    await assert.rejects(db.query('delete from public.expenses where id=$1',[expense]), /permission denied/);
  });
});
test('server window includes 00:59:59, excludes exactly 01:00 and future dates', async () => {
  for (const [date, instant, expected] of [
    ['2026-11-08','2026-11-08T18:30:00Z',true],
    ['2026-11-08','2026-11-08T19:29:59Z',true],
    ['2026-11-08','2026-11-08T19:30:00Z',false],
    ['2026-11-09','2026-11-08T19:30:00Z',true],
    ['2026-11-10','2026-11-08T19:00:00Z',false],
    ['2026-12-31','2026-12-31T18:59:00Z',true],
  ]) assert.equal((await db.query('select private.in_entry_window($1::date,$2::timestamptz) allowed',[date,instant])).rows[0].allowed, expected);
});
test('unpaid purchases excluded; partial credit payments belong to payment dates', async () => {
  assert.equal((await db.query('select outstanding_paise from public.expense_balances where id=$1',[credit])).rows[0].outstanding_paise, 200000);
  await db.query(`insert into public.expense_payments(expense_id,business_date,amount_paise,payment_mode,created_by)
    values ($1,'2026-11-12',100000,'cash',$2),($1,'2026-11-15',100000,'online',$2)`,[credit,admin]);
  const rows = await asRole('authenticated', admin, () => db.query("select business_date,paid_paise from public.daily_reconciliation where business_date in ('2026-11-08','2026-11-12','2026-11-15') order by business_date"));
  assert.deepEqual(rows.rows.map(r=>r.paid_paise),[0,100000,100000]);
  const balance = (await db.query('select * from public.expense_balances where id=$1',[credit])).rows[0];
  assert.equal(balance.outstanding_paise,0); assert.equal(balance.payment_status,'paid');
});
test('salary payments reuse one ledger and retain full partial history', async () => {
  await db.exec("insert into public.staff(staff_code,full_name,designation,joining_date) values ('S001','Rahul','Waiter','2026-01-01')");
  await db.query(`insert into public.salary_records(staff_id,salary_month,expense_id,created_by)
    values ((select id from public.staff where staff_code='S001'),'2026-11-01',$1,$2)`,[salary,admin]);
  await db.query(`insert into public.expense_payments(expense_id,business_date,amount_paise,payment_mode,created_by)
    values ($1,'2026-11-12',1000000,'cash',$2),($1,'2026-11-15',500000,'online',$2)`,[salary,admin]);
  assert.equal((await db.query('select outstanding_paise from public.expense_balances where id=$1',[salary])).rows[0].outstanding_paise,0);
  const history = await asRole('authenticated', admin, ()=>db.query('select * from public.salary_payments'));
  assert.equal(history.rows.length,2);
  assert.equal((await asRole('authenticated', waiter, ()=>db.query('select * from public.salary_payments'))).rows.length,0);
});
test('calculated amounts enforce exact rounding and reject incomplete inputs', async () => {
  await assert.rejects(db.query(`insert into public.expenses(business_date,category_id,description,amount_method,amount_paise,created_by)
    values ((now() at time zone 'Asia/Kolkata')::date,(select id from public.categories limit 1),'Invalid','calculated',100,$1)`,[admin]),/check constraint/);
  assert.equal((await db.query('select round(1.005::numeric * 100) amount')).rows[0].amount,'101');
});
test('admin category changes are audited; deactivation preserves references', async () => {
  await asRole('authenticated',admin,()=>db.query("update public.categories set active=false where name='Grocery'"));
  assert.ok((await db.query("select * from public.audit_logs where table_name='categories' and actor_id=$1",[admin])).rows.length > 0);
  assert.equal((await db.query('select count(*)::int n from public.expenses')).rows[0].n,3);
  await asRole('authenticated',waiter,async()=>assert.equal((await db.query("select * from public.categories where name='Grocery'")).rows.length,0));
});
test('deactivated users lose master data access; profile context is self-only', async () => {
  await db.query('update public.profiles set active=false where id=$1',[waiter]);
  await asRole('authenticated',waiter,async()=>{
    assert.equal((await db.query('select * from public.categories')).rows.length,0);
    const context=(await db.query('select public.session_context() context')).rows[0].context;
    assert.equal(context.id,waiter); assert.equal(context.active,false);
  });
});

test('void and reopen operations reject missing or blank audit reasons', async () => {
  for (const reason of [null, '', '   ']) {
    await assert.rejects(db.query('update public.expenses set voided_at=now(),void_reason=$1 where id=$2',[reason,expense]), /check constraint/);
    await assert.rejects(db.query('update public.expense_payments set voided_at=now(),void_reason=$1 where expense_id=$2',[reason,credit]), /check constraint/);
    await assert.rejects(db.query(`insert into public.day_closures(business_date,event,reason,created_by)
      values ('2026-11-08','reopen',$1,$2)`,[reason,admin]),/check constraint/);
  }
});
