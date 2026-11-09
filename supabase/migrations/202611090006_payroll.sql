begin;

alter table public.salary_records add column voided_at timestamptz;
alter table public.salary_records add column void_reason text;
alter table public.salary_records add constraint salary_void_reason_required
  check ((voided_at is null and void_reason is null) or
    (voided_at is not null and void_reason is not null and length(trim(void_reason))>0));
alter table public.salary_records drop constraint salary_records_staff_id_salary_month_key;
create unique index salary_active_month_unique on public.salary_records(staff_id,salary_month) where voided_at is null;

create function public.save_staff(p_id uuid,p_code text,p_name text,p_designation text,
  p_joining_date date,p_contact text default null,p_salary_paise bigint default null,p_active boolean default true)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();
begin
  if p_id is null or nullif(trim(p_code),'') is null or length(trim(p_code))>40
    or nullif(trim(p_name),'') is null or length(trim(p_name))>120
    or nullif(trim(p_designation),'') is null or length(trim(p_designation))>120
    or p_joining_date is null or p_active is null or p_salary_paise<0 then
    raise exception 'Enter a staff ID, name, designation, joining date and valid salary.';
  end if;
  if exists(select 1 from public.staff where staff_code=trim(p_code) and id<>p_id) then
    raise exception 'This staff ID is already in use.';
  end if;
  insert into public.staff(id,staff_code,full_name,designation,joining_date,contact_number,default_salary_paise,active)
    values(p_id,trim(p_code),trim(p_name),trim(p_designation),p_joining_date,nullif(trim(p_contact),''),p_salary_paise,p_active)
  on conflict(id) do update set staff_code=excluded.staff_code,full_name=excluded.full_name,
    designation=excluded.designation,joining_date=excluded.joining_date,contact_number=excluded.contact_number,
    default_salary_paise=excluded.default_salary_paise,active=excluded.active,updated_at=now();
end;
$$;

create function public.create_salary(p_id uuid,p_staff_id uuid,p_month date,p_date date,
  p_amount_paise bigint,p_category_id uuid,p_existing_expense_id uuid default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); payload jsonb; replay jsonb; expense_id uuid;
  employee public.staff; expense public.expenses; result jsonb;
begin
  payload:=jsonb_build_object('staff',p_staff_id,'month',p_month,'date',p_date,'amount',p_amount_paise,
    'category',p_category_id,'existing',p_existing_expense_id,'notes',nullif(trim(p_notes),''));
  replay:=private.replay_financial_request(p_id,'salary',payload);
  if replay is not null then return replay; end if;
  if p_month is null or extract(day from p_month)<>1 or p_amount_paise is null or p_amount_paise<=0 then
    raise exception 'Choose a salary month and a positive salary amount.';
  end if;
  -- Lock business date before obligation/staff rows, like other financial writers.
  perform private.lock_financial_day(p_date);
  select * into employee from public.staff where id=p_staff_id for update;
  if not found or not employee.active then raise exception 'Choose an active staff member.'; end if;
  if exists(select 1 from public.salary_records where staff_id=p_staff_id and salary_month=p_month and voided_at is null) then
    raise exception 'A salary record already exists for this staff member and month. Open that record to make a payment.';
  end if;
  if p_existing_expense_id is null then
    expense_id:=gen_random_uuid();
    perform public.record_expense(expense_id,p_date,p_category_id,
      'Salary - '||employee.full_name||' - '||to_char(p_month,'Mon YYYY'),p_amount_paise,
      null,null,null,null,null,0,null,p_notes);
  else
    select * into expense from public.expenses where id=p_existing_expense_id for update;
    if not found or expense.voided_at is not null or expense.business_date<>p_date then
      raise exception 'Choose an available expense on the selected expense date.';
    end if;
    if expense.amount_paise<>p_amount_paise or expense.category_id<>p_category_id then
      raise exception 'The linked expense amount and category must stay unchanged.';
    end if;
    if exists(select 1 from public.salary_records s where s.expense_id=expense.id) then
      raise exception 'This expense has already been linked to payroll.';
    end if;
    expense_id:=expense.id;
  end if;
  insert into public.salary_records(id,staff_id,salary_month,expense_id,created_by)
    values(p_id,p_staff_id,p_month,expense_id,actor);
  result:=jsonb_build_object('id',p_id,'expense_id',expense_id);
  insert into private.financial_requests(request_id,actor_id,operation,payload,result)
    values(p_id,actor,'salary',payload,result);
  return result;
end;
$$;

create function public.list_payroll(p_month date,p_staff_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); result jsonb;
begin
  if p_month is null or extract(day from p_month)<>1 then raise exception 'Choose a salary month.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'staff_id',s.staff_id,'staff_name',t.full_name,
    'staff_code',t.staff_code,'designation',t.designation,'salary_month',s.salary_month,
    'expense_id',e.id,'expense_date',e.business_date,'category_id',e.category_id,'category_name',c.name,
    'amount_paise',b.amount_paise,'paid_paise',b.paid_paise,'outstanding_paise',b.outstanding_paise,
    'payment_status',b.payment_status,'notes',e.notes,
    'payments',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'business_date',p.business_date,
      'amount_paise',p.amount_paise,'payment_mode',p.payment_mode,'notes',p.notes)
      order by p.business_date,p.created_at),'[]'::jsonb) from public.expense_payments p
      where p.expense_id=e.id and p.voided_at is null)) order by t.full_name),'[]'::jsonb)
    into result from public.salary_records s join public.staff t on t.id=s.staff_id
      join public.expenses e on e.id=s.expense_id join public.expense_balances b on b.id=e.id
      join public.categories c on c.id=e.category_id
    where s.voided_at is null and s.salary_month=p_month and (p_staff_id is null or s.staff_id=p_staff_id);
  return result;
end;
$$;

revoke all on function public.save_staff(uuid,text,text,text,date,text,bigint,boolean) from public,anon,authenticated;
revoke all on function public.create_salary(uuid,uuid,date,date,bigint,uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.list_payroll(date,uuid) from public,anon,authenticated;
grant execute on function public.save_staff(uuid,text,text,text,date,text,bigint,boolean) to authenticated;
grant execute on function public.create_salary(uuid,uuid,date,date,bigint,uuid,uuid,text) to authenticated;
grant execute on function public.list_payroll(date,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
