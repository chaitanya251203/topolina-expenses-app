import { PGlite } from '@electric-sql/pglite';
import { readFile,readdir } from 'node:fs/promises';
import { before,after,test } from 'node:test';
import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const db=new PGlite();
const admin=randomUUID(),waiter=randomUUID();let today,month,category,employee;
const call=async(name,args={})=>{
  const pairs=Object.entries(args);
  return (await db.query(`select public.${name}(${pairs.map(([key],i)=>`${key}=>$${i+1}`).join(',')}) value`,pairs.map(([,v])=>v))).rows[0].value;
};
async function asActor(id,work){await db.exec('set role authenticated');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);try{return await work();}finally{try{await db.exec("reset role;reset request.jwt.claim.sub");}catch{/* Preserve the original database error; scenario rolls back. */}}}
async function rejected(work,pattern){await db.exec('savepoint expected');let error;try{await work();}catch(e){error=e;}await db.exec('rollback to savepoint expected;release savepoint expected');assert.ok(error);assert.match(error.message,pattern);}
function scenario(name,work){test(name,async()=>{await db.exec('begin');try{await work();}finally{await db.exec('rollback;reset role');}});}
before(async()=>{
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
    create schema auth;create table auth.users(id uuid primary key,email text);
    create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to authenticated,anon,service_role;`);
  const directory=new URL('../../supabase/migrations/',import.meta.url);
  for(const file of (await readdir(directory)).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(new URL(file,directory),'utf8'));
  await db.query("insert into auth.users(id,email) values($1,'admin@example.invalid'),($2,'waiter@example.invalid')",[admin,waiter]);
  await db.query("insert into public.profiles(id,full_name,role_code) values($1,'Admin','admin'),($2,'Waiter','waiter')",[admin,waiter]);
  const dates=(await db.query("select to_char((now() at time zone 'Asia/Kolkata')::date,'YYYY-MM-DD') today,to_char(date_trunc('month',now() at time zone 'Asia/Kolkata'),'YYYY-MM-DD') salary_month")).rows[0];today=dates.today;month=dates.salary_month;
  category=(await db.query("select id from public.categories where name='Salary'")).rows[0].id;employee=randomUUID();
});
after(async()=>db.close());

scenario('staff and payroll require admin; unpaid salary does not become a payment',async()=>{
  await asActor(waiter,()=>rejected(()=>call('save_staff',{p_id:employee,p_code:'S001',p_name:'Rahul',p_designation:'Waiter',p_joining_date:today}),/administrator/));
  await asActor(admin,async()=>{
    await call('save_staff',{p_id:employee,p_code:'S001',p_name:'Rahul',p_designation:'Waiter',p_joining_date:today,p_salary_paise:1500000});
    const request={p_id:randomUUID(),p_staff_id:employee,p_month:month,p_date:today,p_amount_paise:1500000,p_category_id:category};
    const result=await call('create_salary',request);assert.deepEqual(await call('create_salary',request),result);
    const list=await call('list_payroll',{p_month:month});assert.equal(list.length,1);assert.equal(list[0].outstanding_paise,1500000);assert.equal(list[0].paid_paise,0);
    assert.equal((await call('get_day',{p_date:today})).paid_paise,0);
    await rejected(()=>call('create_salary',{...request,p_id:randomUUID()}),/already exists/);
  });
});
scenario('partial salary payments use canonical ledger once and keep payment history',async()=>{
  await asActor(admin,async()=>{
    await call('save_staff',{p_id:employee,p_code:'S001',p_name:'Rahul',p_designation:'Waiter',p_joining_date:today});
    const salary=await call('create_salary',{p_id:randomUUID(),p_staff_id:employee,p_month:month,p_date:today,p_amount_paise:1500000,p_category_id:category});
    await call('record_payment',{p_id:randomUUID(),p_expense_id:salary.expense_id,p_date:today,p_amount_paise:1000000,p_payment_mode:'cash'});
    let rows=await call('list_payroll',{p_month:month});assert.equal(rows[0].outstanding_paise,500000);assert.equal(rows[0].payments.length,1);
    await call('record_payment',{p_id:randomUUID(),p_expense_id:salary.expense_id,p_date:today,p_amount_paise:500000,p_payment_mode:'online'});
    rows=await call('list_payroll',{p_month:month});assert.equal(rows[0].outstanding_paise,0);assert.equal(rows[0].payments.length,2);
    const day=await call('get_day',{p_date:today});assert.equal(day.paid_paise,1500000);assert.equal(day.incurred_paise,1500000);
    assert.deepEqual(await call('list_expenses',{p_outstanding_only:true}),[]);
  });
  await asActor(waiter,()=>rejected(()=>call('list_payroll',{p_month:month}),/administrator/));
});
scenario('linking an existing waiter salary expense reuses amount and existing payments',async()=>{
  const expenseId=randomUUID();
  await asActor(waiter,()=>call('record_expense',{p_id:expenseId,p_date:today,p_category_id:category,p_description:'Salary payment',p_amount_paise:100000,p_paid_paise:50000,p_payment_mode:'cash'}));
  await asActor(admin,async()=>{
    await call('save_staff',{p_id:employee,p_code:'S001',p_name:'Rahul',p_designation:'Waiter',p_joining_date:today});
    await call('create_salary',{p_id:randomUUID(),p_staff_id:employee,p_month:month,p_date:today,p_amount_paise:100000,p_category_id:category,p_existing_expense_id:expenseId});
    const rows=await call('list_payroll',{p_month:month});assert.equal(rows[0].paid_paise,50000);
    assert.equal((await call('get_day',{p_date:today})).paid_paise,50000);
    assert.equal((await db.query('select count(*)::int n from public.expenses')).rows[0].n,1);
  });
  await asActor(waiter,async()=>assert.equal((await call('list_expenses')).length,1));
});

scenario('corrections preserve audit, reject underpayment and closed-date mutation, and voids restore balances',async()=>{
  const id=randomUUID(),payment=randomUUID();
  await asActor(admin,async()=>{
    await call('record_expense',{p_id:id,p_date:today,p_category_id:category,p_description:'Salary',p_amount_paise:100000});
    await call('record_payment',{p_id:payment,p_expense_id:id,p_date:today,p_amount_paise:50000,p_payment_mode:'cash'});
    const params={p_id:randomUUID(),p_expense_id:id,p_description:'Corrected salary',p_amount_paise:120000,p_category_id:category,p_vendor_id:null,p_notes:'Correction',p_reason:'Original figure omitted overtime'};
    await call('correct_expense',params);await call('correct_expense',params);
    await rejected(()=>call('correct_expense',{...params,p_id:randomUUID(),p_amount_paise:40000}),/lower than payments/);
    await rejected(()=>call('void_expense',{p_id:randomUUID(),p_expense_id:id,p_reason:'Mistake'}),/payments first/);
    await call('save_sales',{p_date:today,p_expected_paise:50000,p_cash_paise:0,p_online_paise:0,p_other_paise:0});
    await call('close_day',{p_date:today});
    await rejected(()=>call('void_payment',{p_id:randomUUID(),p_payment_id:payment,p_reason:'Duplicate'}),/closed/);
    await call('reopen_day',{p_date:today,p_reason:'Correct duplicate payment'});
    await call('void_payment',{p_id:randomUUID(),p_payment_id:payment,p_reason:'Duplicate'});
    assert.equal((await call('get_day',{p_date:today})).paid_paise,0);
    await call('void_expense',{p_id:randomUUID(),p_expense_id:id,p_reason:'Recorded under wrong date'});
    assert.equal((await call('list_expenses')).length,0);
    const history=await call('get_audit_logs');assert.ok(history.some(r=>r.operation==='CORRECT'&&r.after_data.reason.includes('overtime')));
    assert.ok(history.some(r=>r.after_data?.void_reason==='Duplicate'));
  });
  await asActor(waiter,()=>rejected(()=>call('get_audit_logs'),/administrator/));
});

scenario('reports use actual payment dates and historical balances as of the end date',async()=>{
  const old='2020-01-02',middle='2020-01-03',last='2020-01-04',id=randomUUID();
  await asActor(admin,async()=>{
    for(const d of [old,middle,last])await call('reopen_day',{p_date:d,p_reason:'Historical fixture'});
    await call('record_expense',{p_id:id,p_date:old,p_category_id:category,p_description:'Older credit purchase',p_amount_paise:200000});
    await call('record_payment',{p_id:randomUUID(),p_expense_id:id,p_date:middle,p_amount_paise:100000,p_payment_mode:'cash'});
    await call('record_payment',{p_id:randomUUID(),p_expense_id:id,p_date:last,p_amount_paise:100000,p_payment_mode:'online'});
    await call('save_sales',{p_date:middle,p_expected_paise:300000,p_cash_paise:200000,p_online_paise:0,p_other_paise:0});
    const report=await call('get_report',{p_from:middle,p_to:middle});
    assert.equal(report.incurred_paise,0);assert.equal(report.paid_paise,100000);assert.equal(report.outstanding_paise,100000);
    assert.equal(report.payments[0].purchase_date,old);assert.equal(report.daily[0].difference_paise,0);
    const online=await call('get_report',{p_from:middle,p_to:middle,p_mode:'online'});assert.equal(online.paid_paise,0);assert.equal(online.expected_paise,300000);
    const all=await call('get_report',{p_from:old,p_to:last});assert.equal(all.outstanding_paise,0);assert.equal(all.incurred_paise,200000);assert.equal(all.paid_paise,200000);
  });
  await asActor(waiter,()=>rejected(()=>call('get_report',{p_from:today,p_to:today}),/administrator/));
});

scenario('configurable waiter permissions apply to RPCs and direct RLS reads without admin escalation',async()=>{
  const id=randomUUID();
  await asActor(waiter,()=>call('record_expense',{p_id:id,p_date:today,p_category_id:category,p_description:'Waiter entry',p_amount_paise:10000}));
  await asActor(admin,async()=>{
    await call('set_waiter_permission',{p_code:'expenses.create',p_enabled:false});await call('set_waiter_permission',{p_code:'expenses.read_own',p_enabled:false});
    await rejected(()=>call('set_waiter_permission',{p_code:'admin.manage',p_enabled:true}),/Only waiter/);
    assert.equal((await call('list_users')).length,2);
    await rejected(()=>call('update_waiter',{p_user_id:admin,p_name:'Admin',p_active:false}),/Only waiter accounts/);
  });
  await asActor(waiter,async()=>{
    await rejected(()=>call('record_expense',{p_id:randomUUID(),p_date:today,p_category_id:category,p_description:'Denied',p_amount_paise:1}),/disabled/);
    await rejected(()=>call('list_expenses'),/disabled/);
    assert.equal((await db.query('select * from public.expenses')).rows.length,0);
    assert.equal((await call('get_dashboard',{p_date:today})).own_expense_count,0);
    await rejected(()=>call('provision_waiter',{p_user_id:waiter,p_name:'Escalation'}),/administrator/);
  });
});

scenario('backup restore is atomic, retains identities and audit, creates a safety snapshot and rejects stale retries',async()=>{
  await asActor(admin,async()=>{
    const first={p_id:randomUUID(),p_date:today,p_category_id:category,p_description:'Original',p_amount_paise:10000};
    await call('record_expense',first);
    const id=await call('create_backup');const backup=await call('download_backup',{p_id:id});
    await call('record_expense',{...first,p_id:randomUUID(),p_description:'Later entry'});
    await rejected(()=>call('restore_backup',{p_backup:{...backup,sha256:'bad'},p_reason:'Invalid file test'}),/checksum/);
    assert.equal((await call('list_expenses')).length,2);
    await rejected(()=>call('restore_backup',{p_backup:{...backup,project_id:randomUUID()},p_reason:'Wrong project'}),/another project/);
    const safety=await call('restore_backup',{p_backup:backup,p_reason:'Restore known ledger'});
    assert.equal((await call('list_expenses')).length,1);
    const status=await call('backup_status');assert.ok(status.backups.some(b=>b.id===safety));
    assert.equal((await call('list_users')).length,2);
    assert.ok((await call('get_audit_logs')).some(r=>r.operation==='RESTORE'));
    await rejected(()=>call('record_expense',first),/restored/);
  });
  await asActor(waiter,()=>rejected(()=>call('create_backup'),/administrator/));
});

scenario('backup integrity and relational validation fail before any ledger replacement can persist',async()=>{
  await asActor(admin,async()=>{
    const id=await call('create_backup');const backup=await call('download_backup',{p_id:id});
    const payload=JSON.parse(backup.payload);payload.app_settings=[];const exact=JSON.stringify(payload);
    const {createHash}=await import('node:crypto');
    await rejected(()=>call('restore_backup',{p_backup:{...backup,payload:exact,sha256:createHash('sha256').update(exact).digest('hex')},p_reason:'Invalid relationship test'}),/cafe settings/);
    assert.equal((await db.query('select count(*)::int n from public.app_settings')).rows[0].n,1);
  });
});

scenario('vendor statements contain only that vendor pending purchases and exact dated payment history',async()=>{
  const vendor=randomUUID(),other=randomUUID(),expense=randomUUID(),date='2020-01-02';let before;
  await asActor(admin,async()=>{
    await db.query("insert into public.vendors(id,name) values($1,'ABC Suppliers'),($2,'Other vendor')",[vendor,other]);
    await call('reopen_day',{p_date:date,p_reason:'Statement test fixture'});
    await call('record_expense',{p_id:expense,p_date:date,p_category_id:category,p_vendor_id:vendor,p_description:'Older purchase',p_amount_paise:2000000,p_paid_paise:200000,p_payment_mode:'cash'});
    const payment=randomUUID();await call('record_payment',{p_id:payment,p_expense_id:expense,p_date:today,p_amount_paise:400000,p_payment_mode:'online'});
    await call('record_expense',{p_id:randomUUID(),p_date:today,p_category_id:category,p_vendor_id:vendor,p_description:'Another purchase',p_amount_paise:500000,p_paid_paise:100000,p_payment_mode:'cash'});
    await call('record_expense',{p_id:randomUUID(),p_date:today,p_category_id:category,p_vendor_id:vendor,p_description:'Settled purchase',p_amount_paise:100000,p_paid_paise:100000,p_payment_mode:'cash'});
    await call('record_expense',{p_id:randomUUID(),p_date:today,p_category_id:category,p_vendor_id:other,p_description:'Other vendor purchase',p_amount_paise:7770000});
    before=await call('get_vendor_statement',{p_vendor_id:vendor});assert.equal(before.vendor.name,'ABC Suppliers');
    assert.equal(before.expenses.length,2);assert.equal(before.amount_paise,2500000);assert.equal(before.paid_paise,700000);assert.equal(before.outstanding_paise,1800000);
    assert.equal(before.expenses[0].business_date,date);assert.equal(before.expenses[0].payments[0].business_date,date);assert.equal(before.expenses[0].payments[1].business_date,today);
    await call('void_payment',{p_id:randomUUID(),p_payment_id:payment,p_reason:'Statement reversal validation'});
    const refreshed=await call('get_vendor_statement',{p_vendor_id:vendor});assert.equal(refreshed.paid_paise,300000);assert.equal(refreshed.outstanding_paise,2200000);
    assert.equal(before.outstanding_paise,1800000,'Previously generated snapshot must stay immutable');
  });
  await asActor(waiter,()=>rejected(()=>call('get_vendor_statement',{p_vendor_id:vendor}),/administrator/));
});
