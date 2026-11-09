// Hosted, authenticated financial smoke test. Every financial operation is
// performed inside one transaction which is always rolled back.
import pg from 'pg';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

const client=new pg.Client({host:process.env.PGHOST,port:Number(process.env.PGPORT??5432),
  user:process.env.PGUSER,database:'postgres',password:process.env.PGPASSWORD,
  ssl:{rejectUnauthorized:true},connectionTimeoutMillis:15000});
const call=async(name,args={})=>{
  const entries=Object.entries(args);
  const response=await client.query(`select public.${name}(${entries.map(([key],index)=>`${key} => $${index+1}`).join(',')}) value`,entries.map(([,value])=>value));
  return response.rows[0].value;
};
try{
  await client.connect();
  const actor=(await client.query("select id from public.profiles where active and role_code='admin' order by created_at limit 1")).rows[0]?.id;
  assert.ok(actor,'An active admin is required');
  await client.query('begin');
  await client.query('set local role authenticated');
  await client.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claims',$2,true)",[actor,JSON.stringify({sub:actor,role:'authenticated'})]);
  const context=await call('entry_context');
  const category=context.categories.find(row=>row.name==='Grocery')??context.categories[0];
  assert.ok(category);
  const date='2000-01-02';
  await call('reopen_day',{p_date:date,p_reason:'Automated validation; transaction will be rolled back'});
  const first={p_id:randomUUID(),p_date:date,p_category_id:category.id,p_description:'Validation only — rolled back',p_amount_paise:10050,p_paid_paise:50,p_payment_mode:'cash'};
  await call('record_expense',first);
  await call('record_expense',first);
  await call('save_sales',{p_date:date,p_expected_paise:10050,p_cash_paise:10000,p_online_paise:0,p_other_paise:0});
  let day=await call('get_day',{p_date:date});
  assert.equal(day.difference_paise,0);assert.equal(day.paid_paise,50);assert.equal(day.incurred_paise,10050);
  assert.equal((await call('list_expenses',{p_from:date,p_to:date})).filter(row=>row.id===first.p_id).length,1);
  const credit={p_id:randomUUID(),p_date:date,p_category_id:category.id,p_description:'Credit validation — rolled back',p_amount_paise:20000};
  await call('record_expense',credit);
  const payment={p_id:randomUUID(),p_expense_id:credit.p_id,p_date:date,p_amount_paise:10000,p_payment_mode:'online'};
  await call('record_payment',payment);await call('record_payment',payment);
  day=await call('get_day',{p_date:date});assert.equal(day.paid_paise,10050);
  await call('save_sales',{p_date:date,p_expected_paise:20050,p_cash_paise:10000,p_online_paise:0,p_other_paise:0});
  await call('close_day',{p_date:date});
  assert.equal((await call('get_day',{p_date:date})).state,'closed');
  await client.query('savepoint expected_failure');
  let blocked=false;
  try{await call('record_expense',{...first,p_id:randomUUID()});}catch{blocked=true;}
  await client.query('rollback to savepoint expected_failure');assert.equal(blocked,true);
  await call('reopen_day',{p_date:date,p_reason:'Validate historical correction; rolled back'});
  assert.equal((await call('get_day',{p_date:date})).state,'reopened');
  console.log('Hosted financial flow verified: authenticated entry, exact totals, retries, partial payment, close, lock and reopen.');
}catch(error){console.error(`Hosted verification failed (${error.code??error.name}).`);process.exitCode=1;}
finally{
  try{await client.query('rollback');}catch{/* Connection may have failed before begin. */}
  await client.end();
  console.log('Verification transaction rolled back; no test financial records retained.');
}
