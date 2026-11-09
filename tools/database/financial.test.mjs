import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { before, after, test } from 'node:test';
import assert from 'node:assert/strict';

const db = new PGlite();
const admin = '10000000-0000-4000-8000-000000000001';
const waiter = '10000000-0000-4000-8000-000000000002';
const otherWaiter = '10000000-0000-4000-8000-000000000003';
const inactive = '10000000-0000-4000-8000-000000000004';
const unprovisioned = '10000000-0000-4000-8000-000000000005';
let today, yesterday, historical, grocery, salaryCategory, dairy, vendor, item;

async function actor(id, work, role = 'authenticated') {
  await db.exec(`set role ${role}`);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id ?? '']);
  try { return await work(); }
  finally { await db.exec('reset role'); await db.exec("reset request.jwt.claim.sub"); }
}

function call(name, args = {}) {
  const entries = Object.entries(args);
  return db.query(`select public.${name}(${entries.map(([key],i)=>`${key} => $${i+1}`).join(',')}) value`,
    entries.map(([,value])=>value)).then(result=>result.rows[0].value);
}

async function rejected(work, pattern) {
  // Expected SQL failures must not poison the surrounding isolated test.
  await db.exec('savepoint expected_failure');
  let error;
  try { await work(); } catch (failure) { error = failure; }
  await db.exec('rollback to savepoint expected_failure; release savepoint expected_failure');
  assert.ok(error, 'expected the operation to fail');
  assert.match(error.message,pattern);
}

function scenario(name, work) {
  test(name, async()=>{
    await db.exec('begin');
    try { await work(); }
    finally { await db.exec('rollback'); await db.exec('reset role'); }
  });
}

function draft(overrides = {}) {
  return {p_id:randomUUID(),p_date:today,p_category_id:grocery,p_description:'Vegetables and groceries',
    p_amount_paise:200000,...overrides};
}
function sale(overrides = {}) {
  return call('save_sales',{p_date:today,p_expected_paise:1000000,p_cash_paise:500000,
    p_online_paise:350000,p_other_paise:50000,...overrides});
}

before(async()=>{
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated,anon,service_role;
    grant execute on function auth.uid() to authenticated,anon,service_role;`);
  const directory = new URL('../../supabase/migrations/',import.meta.url);
  for (const file of (await readdir(directory)).filter(file=>file.endsWith('.sql')).sort()) {
    await db.exec(await readFile(new URL(file,directory),'utf8'));
  }
  for (const [id,name,role,active] of [[admin,'Cafe Owner','admin',true],[waiter,'Rahul','waiter',true],
    [otherWaiter,'Priya','waiter',true],[inactive,'Inactive Staff','waiter',false]]) {
    await db.query('insert into auth.users values ($1)',[id]);
    await db.query('insert into public.profiles(id,full_name,role_code,active) values ($1,$2,$3,$4)',[id,name,role,active]);
  }
  await db.query('insert into auth.users values ($1)',[unprovisioned]);
  const dates = (await db.query(`select to_char((now() at time zone 'Asia/Kolkata')::date,'YYYY-MM-DD') today,
    to_char((now() at time zone 'Asia/Kolkata')::date-1,'YYYY-MM-DD') yesterday,
    to_char((now() at time zone 'Asia/Kolkata')::date-10,'YYYY-MM-DD') historical`)).rows[0];
  ({today,yesterday,historical}=dates);
  const categories = (await db.query('select id,name from public.categories')).rows;
  grocery=categories.find(row=>row.name==='Grocery').id;
  dairy=categories.find(row=>row.name==='Dairy').id;
  salaryCategory=categories.find(row=>row.name==='Salary').id;
  vendor=(await db.query("insert into public.vendors(name) values ('ABC Suppliers') returning id")).rows[0].id;
  item=(await db.query("insert into public.items(category_id,name,default_unit,default_rate_paise) values ($1,'Rice','kg',8000) returning id",[grocery])).rows[0].id;
});
after(async()=>db.close());

scenario('entry context is live, includes every category and excludes inactive masters', async()=>{
  await db.query("insert into public.categories(name,active) values ('Inactive category',false)");
  await db.query("insert into public.vendors(name,active) values ('Old vendor',false)");
  await actor(waiter,async()=>{
    const context=await call('entry_context');
    assert.equal(context.business_dates[0],today);
    assert.equal(context.categories.length,11);
    assert.ok(context.categories.some(row=>row.name==='Salary'));
    assert.ok(context.categories.some(row=>row.name==='Vegetables'&&row.icon_key==='vegetables'));
    assert.ok(context.categories.some(row=>row.name==='Staff Welfare Expense'&&row.icon_key==='staff'));
    assert.ok(!context.categories.some(row=>row.name==='Veg'||row.name==='Welfare Exp Staff'));
    assert.equal(context.items[0].default_rate_paise,8000);
    assert.equal(context.vendors.length,1);
    assert.ok(Date.parse(context.server_time));
  });
});

scenario('anonymous, inactive and unprovisioned users cannot execute financial commands', async()=>{
  await actor(null,async()=>{
    await rejected(()=>call('entry_context'),/permission denied/);
    await rejected(()=>call('record_expense',draft()),/permission denied/);
  },'anon');
  for (const id of [inactive,unprovisioned]) await actor(id,async()=>{
    await rejected(()=>call('entry_context'),/not active/);
    await rejected(()=>call('record_expense',draft()),/not active/);
  });
  await actor(waiter,async()=>{
    await rejected(()=>db.query('select * from private.financial_requests'),/permission denied/);
    await rejected(()=>db.query('select private.require_admin_actor()'),/permission denied/);
    await rejected(()=>db.query('insert into public.expenses default values'),/permission denied/);
  });
});

scenario('waiter submission saves one shared expense and only its actual payment', async()=>{
  const input=draft({p_paid_paise:50000,p_payment_mode:'cash',p_vendor_id:vendor,p_notes:'  Morning purchase  '});
  await actor(waiter,async()=>{
    assert.deepEqual(await call('record_expense',input),{id:input.p_id});
    const own=await call('list_expenses');
    assert.equal(own.length,1); assert.equal(own[0].created_by,waiter);
    assert.equal(own[0].created_by_name,'Rahul'); assert.equal(own[0].vendor_name,'ABC Suppliers');
    assert.equal(own[0].notes,'Morning purchase'); assert.equal(own[0].paid_paise,50000);
    assert.equal(own[0].outstanding_paise,150000); assert.equal(own[0].payment_status,'partially_paid');
    assert.equal(own[0].payments.length,1);
  });
  await actor(admin,async()=>{
    const all=await call('list_expenses'); assert.equal(all.length,1); assert.equal(all[0].id,input.p_id);
    const day=await call('get_day',{p_date:today});
    assert.equal(day.incurred_paise,200000); assert.equal(day.paid_paise,50000);
    assert.equal(day.outstanding_paise,150000); assert.equal(day.has_sales,false);
    assert.equal(day.difference_paise,null);
  });
  await actor(otherWaiter,async()=>assert.deepEqual(await call('list_expenses'),[]));
  const audit=(await db.query("select actor_id from public.audit_logs where table_name='expenses' and record_id=$1",[input.p_id])).rows;
  assert.equal(audit.length,1); assert.equal(audit[0].actor_id,waiter);
});

scenario('expense retries are idempotent and reject changed payload or another actor', async()=>{
  const input=draft({p_paid_paise:200000,p_payment_mode:'online'});
  await actor(waiter,async()=>{
    await call('record_expense',input); await call('record_expense',input);
    await rejected(()=>call('record_expense',{...input,p_amount_paise:200001}),/different details/);
  });
  await actor(otherWaiter,()=>rejected(()=>call('record_expense',input),/different details/));
  assert.equal((await db.query('select count(*)::int n from public.expenses')).rows[0].n,1);
  assert.equal((await db.query('select count(*)::int n from public.expense_payments')).rows[0].n,1);
});

scenario('quantity arithmetic matches exact rounding and validates masters and partial inputs', async()=>{
  await actor(waiter,async()=>{
    const input=draft({p_amount_paise:101,p_quantity:'1.005',p_rate_paise:100,p_unit:'kg',p_item_id:item});
    await call('record_expense',input);
    const entries=await call('list_expenses');
    assert.equal(entries[0].quantity,'1.005000'); assert.equal(entries[0].amount_method,'calculated');
    await rejected(()=>call('record_expense',draft({p_quantity:'1.0000001',p_rate_paise:100,p_amount_paise:100})),/six decimal/);
    await rejected(()=>call('record_expense',draft({p_quantity:'1',p_rate_paise:null})),/positive quantity/);
    await rejected(()=>call('record_expense',draft({p_quantity:'1',p_rate_paise:100,p_amount_paise:101})),/does not match/);
    await rejected(()=>call('record_expense',draft({p_category_id:dairy,p_item_id:item})),/selected category/);
    await rejected(()=>call('record_expense',draft({p_paid_paise:200001,p_payment_mode:'cash'})),/between zero/);
    await rejected(()=>call('record_expense',draft({p_paid_paise:1,p_payment_mode:'credit'})),/actual payment/);
  });
  await db.query('update public.vendors set active=false where id=$1',[vendor]);
  await actor(waiter,()=>rejected(()=>call('record_expense',draft({p_vendor_id:vendor})),/active vendor/));
});

scenario('unpaid credit is excluded and later partial payments use their payment date', async()=>{
  const input=draft({p_date:historical,p_vendor_id:vendor});
  await actor(admin,async()=>{
    await call('reopen_day',{p_date:historical,p_reason:'Enter opening credit purchase'});
    await call('record_expense',input);
    await sale({p_date:historical,p_expected_paise:0,p_cash_paise:0,p_online_paise:0,p_other_paise:0});
    await call('close_day',{p_date:historical});
    const old=await call('get_day',{p_date:historical}); assert.equal(old.paid_paise,0);
    const id=randomUUID();
    await call('record_payment',{p_id:id,p_expense_id:input.p_id,p_date:today,p_amount_paise:100000,p_payment_mode:'cash'});
    const now=await call('get_day',{p_date:today}); assert.equal(now.paid_paise,100000);
    assert.equal((await call('get_day',{p_date:historical})).paid_paise,0);
    const ledger=await call('list_expenses',{p_outstanding_only:true});
    assert.equal(ledger[0].outstanding_paise,100000); assert.equal(ledger[0].business_date,historical);
    assert.equal(ledger[0].payments[0].business_date,today);
    const snapshot=(await db.query("select snapshot from public.day_closures where event='close' and business_date=$1",[historical])).rows[0].snapshot;
    assert.equal(snapshot.outstanding_paise,200000);
  });
});

scenario('credit payments prevent overpay, duplicates and request reference reuse', async()=>{
  const input=draft({p_amount_paise:200000});
  await actor(admin,async()=>{
    await call('record_expense',input);
    const payment={p_id:randomUUID(),p_expense_id:input.p_id,p_date:today,p_amount_paise:100000,p_payment_mode:'cash'};
    await call('record_payment',payment); await call('record_payment',payment);
    await rejected(()=>call('record_payment',{...payment,p_amount_paise:99999}),/different details/);
    await rejected(()=>call('record_payment',{...payment,p_id:input.p_id}),/different details/);
    await rejected(()=>call('record_payment',{...payment,p_id:randomUUID(),p_amount_paise:100001}),/exceeds/);
    await call('record_payment',{...payment,p_id:randomUUID()});
    await rejected(()=>call('record_payment',{...payment,p_id:randomUUID(),p_amount_paise:1}),/exceeds/);
    const rows=await call('list_expenses'); assert.equal(rows[0].outstanding_paise,0); assert.equal(rows[0].payments.length,2);
    assert.deepEqual(await call('list_expenses',{p_outstanding_only:true}),[]);
  });
});

scenario('waiters cannot settle credit, see administrative totals or change sales', async()=>{
  const input=draft();
  await actor(waiter,async()=>{
    await call('record_expense',input);
    await rejected(()=>call('record_payment',{p_id:randomUUID(),p_expense_id:input.p_id,p_date:today,p_amount_paise:1,p_payment_mode:'cash'}),/Only an administrator/);
    await rejected(()=>sale(),/Only an administrator/);
    await rejected(()=>call('get_day',{p_date:today}),/Only an administrator/);
    await rejected(()=>call('close_day',{p_date:today}),/Only an administrator/);
    await rejected(()=>call('reopen_day',{p_date:today,p_reason:'test'}),/Only an administrator/);
    await rejected(()=>call('list_expenses',{p_outstanding_only:true}),/Only an administrator/);
    const dashboard=await call('get_dashboard',{p_date:today});
    assert.equal(dashboard.own_expense_count,1); assert.equal(dashboard.own_incurred_paise,200000);
    assert.equal(dashboard.day.business_date,today);
    assert.equal('monthly_expected_paise' in dashboard,false); assert.equal('expected_paise' in dashboard.day,false);
  });
});

scenario('a salary-category submission remains an ordinary own entry without payroll metadata', async()=>{
  const input=draft({p_category_id:salaryCategory,p_description:'Salary expense',p_paid_paise:50000,p_payment_mode:'cash'});
  await actor(waiter,()=>call('record_expense',input));
  await db.exec("insert into public.staff(staff_code,full_name,designation,joining_date) values ('S001','Private Staff Name','Chef',current_date)");
  await db.query(`insert into public.salary_records(staff_id,salary_month,expense_id,created_by)
    values ((select id from public.staff limit 1),date_trunc('month',now())::date,$1,$2)`,[input.p_id,admin]);
  await actor(waiter,async()=>{
    const rows=await call('list_expenses'); assert.equal(rows.length,1); assert.equal(rows[0].category_name,'Salary');
    assert.equal('staff_id' in rows[0],false); assert.equal('salary_month' in rows[0],false);
    assert.equal(JSON.stringify(rows).includes('Private Staff Name'),false);
    assert.equal((await db.query('select * from public.salary_records')).rows.length,0);
    assert.equal((await db.query('select * from public.salary_payments')).rows.length,0);
  });
  await actor(admin,async()=>{
    assert.deepEqual(await call('list_expenses',{p_outstanding_only:true}),[]);
    const dashboard=await call('get_dashboard',{p_date:today});
    assert.equal(dashboard.outstanding_paise,0,'Payroll dues must not inflate vendor credit');
    assert.equal(dashboard.monthly_incurred_paise,200000);
    assert.equal(dashboard.monthly_paid_paise,50000);
  });
});

scenario('closing requires sales and a discrepancy explanation, then locks every financial command', async()=>{
  await actor(admin,async()=>{
    await rejected(()=>call('close_day',{p_date:today}),/Enter the daily sales/);
    const input=draft({p_amount_paise:100000,p_paid_paise:100000,p_payment_mode:'cash'});
    await call('record_expense',input); await sale();
    let day=await call('get_day',{p_date:today}); assert.equal(day.difference_paise,0);
    await sale({p_expected_paise:1000100});
    await rejected(()=>call('close_day',{p_date:today}),/explanation/);
    await call('close_day',{p_date:today,p_reason:'₹1 shortage checked'});
    day=await call('get_day',{p_date:today}); assert.equal(day.state,'closed');
    await rejected(()=>sale(),/day is closed/);
    await rejected(()=>call('record_expense',draft()),/day is closed/);
    await rejected(()=>call('record_payment',{p_id:randomUUID(),p_expense_id:input.p_id,p_date:today,p_amount_paise:1,p_payment_mode:'cash'}),/day is closed/);
    await rejected(()=>call('close_day',{p_date:today,p_reason:'again'}),/day is closed/);
    // A lost-response retry remains safe even after the business day closed.
    assert.deepEqual(await call('record_expense',input),{id:input.p_id});
    const history=(await db.query("select * from public.day_closures where event='close'")).rows;
    assert.equal(history.length,1); assert.equal(history[0].snapshot.difference_paise,100);
    assert.equal(history[0].snapshot.payments.length,1); assert.equal(history[0].snapshot.closed_by,admin);
  });
});

scenario('reopen requires a reason, preserves closing snapshots, and permits audited correction', async()=>{
  await actor(admin,async()=>{
    await sale({p_expected_paise:900000});
    await call('close_day',{p_date:today});
    for (const reason of [null,'','   ']) await rejected(()=>call('reopen_day',{p_date:today,p_reason:reason}),/reason/);
    await call('reopen_day',{p_date:today,p_reason:'Correct Petpooja total'});
    await sale({p_expected_paise:900100});
    await call('close_day',{p_date:today,p_reason:'Reviewed ₹1 difference'});
    const history=(await db.query('select * from public.day_closures order by created_at,id')).rows;
    assert.equal(history.length,3);
    const closed=history.filter(row=>row.event==='close');
    assert.deepEqual(closed.map(row=>row.snapshot.expected_paise).sort(),[900000,900100]);
    assert.ok(history.some(row=>row.event==='reopen' && row.reason==='Correct Petpooja total'));
    assert.equal((await db.query("select count(*)::int n from public.audit_logs where table_name='sales'")).rows[0].n,2);
  });
});

scenario('historical writes require explicit admin reopen and waiter reads cannot widen their dates', async()=>{
  await actor(admin,async()=>{
    await rejected(()=>call('record_expense',draft({p_date:historical})),/cutoff has passed/);
    await rejected(()=>sale({p_date:historical}),/cutoff has passed/);
    await call('reopen_day',{p_date:historical,p_reason:'Recover missed day'});
    await call('record_expense',draft({p_date:historical}));
    await rejected(()=>call('reopen_day',{p_date:historical,p_reason:'again'}),/already reopened/);
  });
  await actor(waiter,async()=>{
    await rejected(()=>call('record_expense',draft({p_date:historical})),/cutoff has passed/);
    assert.deepEqual(await call('list_expenses',{p_from:historical,p_to:today}),[]);
    await rejected(()=>call('get_dashboard',{p_date:historical}),/current business-day/);
  });
});

scenario('a newly dated payment cannot precede the original expense or use a future day', async()=>{
  const input=draft();
  await actor(admin,async()=>{
    await call('record_expense',input);
    await call('reopen_day',{p_date:historical,p_reason:'Test correction window'});
    await rejected(()=>call('record_payment',{p_id:randomUUID(),p_expense_id:input.p_id,p_date:historical,p_amount_paise:1,p_payment_mode:'cash'}),/before its original/);
    const future=(await db.query("select to_char((now() at time zone 'Asia/Kolkata')::date+1,'YYYY-MM-DD') d")).rows[0].d;
    await rejected(()=>call('record_expense',draft({p_date:future})),/available previous business date/);
    await rejected(()=>call('reopen_day',{p_date:future,p_reason:'Future'}),/Only today or a previous day/);
  });
});

scenario('the previous-day write window ends at exactly 01:00 server India time', async()=>{
  // Override only the time input in the isolated test transaction. The deployed
  // helper itself is separately tested with explicit timestamps in foundation.
  await db.exec(`create or replace function private.in_entry_window(p_date date,p_now timestamptz default now())
    returns boolean language sql immutable set search_path='' as $$
    with tick as (select coalesce(nullif(current_setting('topolina.test_clock',true),''),p_now::text)::timestamptz t)
    select p_date=(t at time zone 'Asia/Kolkata')::date or
      (p_date=(t at time zone 'Asia/Kolkata')::date-1 and (t at time zone 'Asia/Kolkata')::time<time '01:00') from tick $$`);
  await db.query("select set_config('topolina.test_clock',$1,false)",[`${yesterday}T19:29:59Z`]);
  await actor(waiter,()=>call('record_expense',draft({p_date:yesterday})));
  await db.query("select set_config('topolina.test_clock',$1,false)",[`${yesterday}T19:30:00Z`]);
  await actor(waiter,()=>rejected(()=>call('record_expense',draft({p_date:yesterday})),/cutoff has passed/));
});

scenario('dashboard totals use entered net collections, incurred expenses and actual payments separately', async()=>{
  await actor(admin,async()=>{
    await call('record_expense',draft({p_amount_paise:100000,p_paid_paise:100000,p_payment_mode:'cash'}));
    await call('record_expense',draft({p_amount_paise:200000}));
    await sale({p_notes:'Net after expenses'});
    const dashboard=await call('get_dashboard',{p_date:today});
    assert.equal(dashboard.monthly_expected_paise,1000000);
    assert.equal(dashboard.monthly_incurred_paise,300000);
    assert.equal(dashboard.monthly_paid_paise,100000);
    assert.equal(dashboard.outstanding_paise,200000);
    assert.equal(dashboard.day.difference_paise,0);
    assert.equal(dashboard.day.notes,'Net after expenses');
  });
});
