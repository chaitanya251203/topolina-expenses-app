-- All financial mutation goes through the following transactional commands.
-- Direct client writes remain revoked; SECURITY DEFINER functions explicitly
-- check the authenticated actor, role, masters and server-side business window.
begin;

create table private.financial_requests (
  request_id uuid primary key,
  actor_id uuid not null references public.profiles(id),
  operation text not null,
  payload jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now()
);
revoke all on private.financial_requests from public, anon, authenticated;

create function private.require_active_actor() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null or not exists(select 1 from public.profiles where id=actor and active) then
    raise exception 'Your account is not active. Please contact the administrator.' using errcode='42501';
  end if;
  return actor;
end;
$$;

create function private.require_admin_actor() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := private.require_active_actor();
begin
  if not private.is_admin() then
    raise exception 'Only an administrator can perform this action.' using errcode='42501';
  end if;
  return actor;
end;
$$;

create function private.lock_financial_day(p_date date) returns void
language plpgsql security definer set search_path = '' as $$
declare day_state text;
begin
  if p_date is null or p_date > (clock_timestamp() at time zone 'Asia/Kolkata')::date then
    raise exception 'Choose today or an available previous business date.';
  end if;
  -- An ordinary request can start an eligible date, but cannot manufacture an
  -- open historical day after cutoff. Historical recovery uses reopen_day.
  if private.in_entry_window(p_date, clock_timestamp()) then
    insert into public.business_days(business_date) values (p_date) on conflict do nothing;
  end if;
  select state into day_state from public.business_days where business_date=p_date for update;
  if not found then
    raise exception 'The entry cutoff has passed. An administrator must reopen this day with a reason.';
  end if;
  if day_state='closed' then
    raise exception 'This day is closed. An administrator must reopen it before making changes.';
  end if;
  if not private.in_entry_window(p_date, clock_timestamp()) and
     not (private.is_admin() and day_state='reopened') then
    raise exception 'The entry cutoff has passed. An administrator must reopen this day with a reason.';
  end if;
end;
$$;

-- Serialize retries before checking a receipt. The UUID is global across actors
-- and operations, preventing reuse of another user's known command reference.
create function private.replay_financial_request(p_id uuid, p_operation text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare previous private.financial_requests;
begin
  if p_id is null then raise exception 'A unique request reference is required.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_id::text, 784329));
  select * into previous from private.financial_requests where request_id=p_id;
  if found then
    if previous.actor_id <> auth.uid() or previous.operation <> p_operation or previous.payload <> p_payload then
      raise exception 'This request reference has already been used for different details. Refresh the entry before trying again.';
    end if;
    return previous.result;
  end if;
  return null;
end;
$$;

create function public.entry_context() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := private.require_active_actor(); result jsonb;
begin
  select jsonb_build_object(
    'server_time', now(),
    'business_dates', (select coalesce(jsonb_agg(x.business_date order by x.business_date desc),'[]'::jsonb) from (
      select (now() at time zone 'Asia/Kolkata')::date as business_date
      union select (now() at time zone 'Asia/Kolkata')::date-1
        where (now() at time zone 'Asia/Kolkata')::time < time '01:00'
      union select business_date from public.business_days
        where state='reopened' and private.is_admin()
          and business_date <= (now() at time zone 'Asia/Kolkata')::date
    ) x),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]'::jsonb)
      from public.categories where active),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'category_id',i.category_id,
      'default_unit',i.default_unit,'default_rate_paise',i.default_rate_paise) order by i.name),'[]'::jsonb)
      from public.items i join public.categories c on c.id=i.category_id where i.active and c.active),
    'vendors', (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]'::jsonb)
      from public.vendors where active)
  ) into result;
  return result;
end;
$$;

create function public.list_expenses(p_from date default null,p_to date default null,p_outstanding_only boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := private.require_active_actor(); admin boolean := private.is_admin();
  from_date date := coalesce(p_from,p_to,(now() at time zone 'Asia/Kolkata')::date);
  to_date date := coalesce(p_to,p_from,(now() at time zone 'Asia/Kolkata')::date);
  result jsonb;
begin
  if p_outstanding_only is null then raise exception 'Choose a valid ledger filter.'; end if;
  if p_from is not null and p_to is not null and p_from>p_to then
    raise exception 'The start date must be on or before the end date.';
  end if;
  if p_outstanding_only and not admin then
    raise exception 'Only an administrator can view the credit ledger.' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'business_date',e.business_date,'category_id',e.category_id,'category_name',c.name,
    'item_id',e.item_id,'item_name',i.name,'vendor_id',e.vendor_id,'vendor_name',v.name,
    'description',e.description,'amount_method',e.amount_method,'quantity',e.quantity::text,
    'unit',e.unit,'rate_paise',e.rate_paise,'amount_paise',e.amount_paise,'paid_paise',b.paid_paise,
    'outstanding_paise',b.outstanding_paise,'payment_status',b.payment_status,'notes',e.notes,
    'created_by',e.created_by,'created_by_name',u.full_name,'created_at',e.created_at,
    'payments',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'business_date',p.business_date,
      'amount_paise',p.amount_paise,'payment_mode',p.payment_mode,'notes',p.notes)
      order by p.business_date,p.created_at,p.id),'[]'::jsonb)
      from public.expense_payments p where p.expense_id=e.id and p.voided_at is null)
    ) order by e.business_date desc,e.created_at desc,e.id),'[]'::jsonb) into result
  from public.expenses e join public.expense_balances b on b.id=e.id
  join public.categories c on c.id=e.category_id
  join public.profiles u on u.id=e.created_by
  left join public.items i on i.id=e.item_id left join public.vendors v on v.id=e.vendor_id
  where e.voided_at is null
    and (admin or (e.created_by=actor and private.in_entry_window(e.business_date)))
    and case when p_outstanding_only then
      b.outstanding_paise>0 and not exists(select 1 from public.salary_records sr where sr.expense_id=e.id)
      and (p_from is null or e.business_date>=p_from) and (p_to is null or e.business_date<=p_to)
    else e.business_date between from_date and to_date end;
  return result;
end;
$$;

create function public.record_expense(
  p_id uuid,p_date date,p_category_id uuid,p_description text,p_amount_paise bigint,
  p_quantity text default null,p_unit text default null,p_rate_paise bigint default null,
  p_item_id uuid default null,p_vendor_id uuid default null,p_paid_paise bigint default 0,
  p_payment_mode text default null,p_notes text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := private.require_active_actor(); quantity_value numeric; method text;
  payload jsonb; replay jsonb; result jsonb;
begin
  payload := jsonb_build_object('date',p_date,'category_id',p_category_id,'description',trim(p_description),
    'amount_paise',p_amount_paise,'quantity',trim(p_quantity),'unit',nullif(trim(p_unit),''),
    'rate_paise',p_rate_paise,'item_id',p_item_id,'vendor_id',p_vendor_id,'paid_paise',p_paid_paise,
    'payment_mode',case when p_paid_paise>0 then p_payment_mode end,'notes',nullif(trim(p_notes),''));
  replay := private.replay_financial_request(p_id,'expense',payload);
  if replay is not null then return replay; end if;
  if exists(select 1 from public.expenses where id=p_id) then raise exception 'This expense reference has already been used.'; end if;
  if p_description is null or length(trim(p_description)) not between 1 and 500 then
    raise exception 'Enter an expense description between 1 and 500 characters.';
  end if;
  if p_amount_paise is null or p_amount_paise<=0 then raise exception 'The expense amount must be greater than zero.'; end if;
  if p_paid_paise is null or p_paid_paise<0 or p_paid_paise>p_amount_paise then
    raise exception 'The amount paid must be between zero and the expense amount.';
  end if;
  if p_paid_paise>0 and (p_payment_mode is null or p_payment_mode not in ('cash','online','other')) then
    raise exception 'Choose Cash, Bank / Online, or Others for an actual payment.';
  end if;
  if p_quantity is null and p_rate_paise is null then method := 'manual';
  else
    if p_quantity is null or p_rate_paise is null or p_rate_paise<=0
       or trim(p_quantity) !~ '^[0-9]+(\.[0-9]{1,6})?$' then
      raise exception 'Enter a positive quantity with up to six decimal places and a positive rate.';
    end if;
    quantity_value := trim(p_quantity)::numeric;
    if quantity_value<=0 or quantity_value>9999999999.999999 then raise exception 'The quantity is outside the supported range.'; end if;
    if round(quantity_value*p_rate_paise)<>p_amount_paise then raise exception 'The amount does not match quantity multiplied by rate.'; end if;
    method := 'calculated';
  end if;
  perform private.lock_financial_day(p_date);
  perform 1 from public.categories where id=p_category_id and active for share;
  if not found then
    raise exception 'Choose an active expense category.';
  end if;
  if p_item_id is not null then
    perform 1 from public.items where id=p_item_id and active and category_id=p_category_id for share;
    if not found then raise exception 'Choose an active item from the selected category.'; end if;
  end if;
  if p_vendor_id is not null then
    perform 1 from public.vendors where id=p_vendor_id and active for share;
    if not found then raise exception 'Choose an active vendor.'; end if;
  end if;
  insert into public.expenses(id,business_date,category_id,item_id,vendor_id,description,
    amount_method,quantity,unit,rate_paise,amount_paise,notes,created_by)
  values(p_id,p_date,p_category_id,p_item_id,p_vendor_id,trim(p_description),method,quantity_value,
    nullif(trim(p_unit),''),p_rate_paise,p_amount_paise,nullif(trim(p_notes),''),actor);
  if p_paid_paise>0 then
    insert into public.expense_payments(expense_id,business_date,amount_paise,payment_mode,notes,created_by)
    values(p_id,p_date,p_paid_paise,p_payment_mode,nullif(trim(p_notes),''),actor);
  end if;
  result := jsonb_build_object('id',p_id);
  insert into private.financial_requests(request_id,actor_id,operation,payload,result)
    values(p_id,actor,'expense',payload,result);
  return result;
end;
$$;

create function public.record_payment(p_id uuid,p_expense_id uuid,p_date date,p_amount_paise bigint,
  p_payment_mode text,p_notes text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare actor uuid := private.require_admin_actor(); expense public.expenses; paid numeric;
  payload jsonb; replay jsonb; result jsonb;
begin
  payload := jsonb_build_object('expense_id',p_expense_id,'date',p_date,'amount_paise',p_amount_paise,
    'payment_mode',p_payment_mode,'notes',nullif(trim(p_notes),''));
  replay := private.replay_financial_request(p_id,'payment',payload);
  if replay is not null then return replay; end if;
  if exists(select 1 from public.expense_payments where id=p_id) then raise exception 'This payment reference has already been used.'; end if;
  if p_amount_paise is null or p_amount_paise<=0 then raise exception 'The payment amount must be greater than zero.'; end if;
  if p_payment_mode is null or p_payment_mode not in ('cash','online','other') then
    raise exception 'Choose Cash, Bank / Online, or Others for an actual payment.';
  end if;
  -- All writers lock the business day before an expense. Closing locks the same
  -- day, and payments lock their obligation before checking its remaining sum.
  perform private.lock_financial_day(p_date);
  select * into expense from public.expenses where id=p_expense_id for update;
  if not found or expense.voided_at is not null then raise exception 'This expense is not available for payment.'; end if;
  if p_date<expense.business_date then raise exception 'A payment cannot be dated before its original expense.'; end if;
  select coalesce(sum(amount_paise),0) into paid from public.expense_payments
    where expense_id=p_expense_id and voided_at is null;
  if p_amount_paise>expense.amount_paise-paid then raise exception 'The payment exceeds the remaining outstanding amount.'; end if;
  insert into public.expense_payments(id,expense_id,business_date,amount_paise,payment_mode,notes,created_by)
    values(p_id,p_expense_id,p_date,p_amount_paise,p_payment_mode,nullif(trim(p_notes),''),actor);
  result := jsonb_build_object('id',p_id);
  insert into private.financial_requests(request_id,actor_id,operation,payload,result)
    values(p_id,actor,'payment',payload,result);
  return result;
end;
$$;

create function public.save_sales(p_date date,p_expected_paise bigint,p_cash_paise bigint,
  p_online_paise bigint,p_other_paise bigint,p_notes text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid := private.require_admin_actor();
begin
  if p_expected_paise is null or p_cash_paise is null or p_online_paise is null or p_other_paise is null
     or p_expected_paise<0 or p_cash_paise<0 or p_online_paise<0 or p_other_paise<0 then
    raise exception 'Enter nonnegative expected sales and collection amounts.';
  end if;
  -- Detect unsupported combined totals before storing rather than overflowing.
  perform (p_cash_paise::numeric+p_online_paise+p_other_paise)::bigint;
  perform private.lock_financial_day(p_date);
  insert into public.sales(business_date,expected_paise,cash_paise,online_paise,other_paise,notes,created_by,updated_by)
    values(p_date,p_expected_paise,p_cash_paise,p_online_paise,p_other_paise,nullif(trim(p_notes),''),actor,actor)
  on conflict(business_date) do update set expected_paise=excluded.expected_paise,cash_paise=excluded.cash_paise,
    online_paise=excluded.online_paise,other_paise=excluded.other_paise,notes=excluded.notes,
    updated_by=actor,updated_at=now();
end;
$$;

create function public.get_day(p_date date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := private.require_admin_actor(); sale public.sales; has_sale boolean;
  day_state text; paid bigint; incurred bigint; outstanding bigint; payments jsonb;
begin
  if p_date is null then raise exception 'Choose a business date.'; end if;
  select * into sale from public.sales where business_date=p_date;
  has_sale := found;
  select state into day_state from public.business_days where business_date=p_date;
  select coalesce(sum(p.amount_paise),0)::bigint into paid from public.expense_payments p
    join public.expenses e on e.id=p.expense_id where p.business_date=p_date and p.voided_at is null and e.voided_at is null;
  select coalesce(sum(amount_paise),0)::bigint into incurred from public.expenses where business_date=p_date and voided_at is null;
  select coalesce(sum(outstanding_paise),0)::bigint into outstanding from public.expense_balances where business_date=p_date;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'expense_id',p.expense_id,
    'description',e.description,'category_name',c.name,'amount_paise',p.amount_paise,
    'payment_mode',p.payment_mode,'created_by_name',u.full_name) order by p.created_at,p.id),'[]'::jsonb)
    into payments from public.expense_payments p join public.expenses e on e.id=p.expense_id
    join public.categories c on c.id=e.category_id join public.profiles u on u.id=p.created_by
    where p.business_date=p_date and p.voided_at is null and e.voided_at is null;
  return jsonb_build_object('business_date',p_date,'state',coalesce(day_state,'not_started'),
    'has_sales',has_sale,'expected_paise',sale.expected_paise,'cash_paise',coalesce(sale.cash_paise,0),
    'online_paise',coalesce(sale.online_paise,0),'other_paise',coalesce(sale.other_paise,0),
    'paid_paise',paid,'incurred_paise',incurred,'outstanding_paise',outstanding,
    'difference_paise',(sale.expected_paise::numeric-sale.cash_paise-sale.online_paise-sale.other_paise-paid)::bigint,
    'notes',sale.notes,'payments',payments);
end;
$$;

create function public.get_dashboard(p_date date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := private.require_active_actor(); first_day date; next_month date;
  day_state text; result jsonb;
begin
  if p_date is null then raise exception 'Choose a business date.'; end if;
  if private.is_admin() then
    first_day := date_trunc('month',p_date::timestamp)::date;
    next_month := (first_day+interval '1 month')::date;
    select jsonb_build_object('day',public.get_day(p_date),
      'monthly_expected_paise',(select coalesce(sum(expected_paise),0)::bigint from public.sales where business_date>=first_day and business_date<next_month),
      'monthly_incurred_paise',(select coalesce(sum(amount_paise),0)::bigint from public.expenses where voided_at is null and business_date>=first_day and business_date<next_month),
      'monthly_paid_paise',(select coalesce(sum(p.amount_paise),0)::bigint from public.expense_payments p join public.expenses e on e.id=p.expense_id
        where p.voided_at is null and e.voided_at is null and p.business_date>=first_day and p.business_date<next_month),
      'outstanding_paise',(select coalesce(sum(b.outstanding_paise),0)::bigint from public.expense_balances b
        where not exists(select 1 from public.salary_records sr where sr.expense_id=b.id))
    ) into result;
  else
    if not private.in_entry_window(p_date) then raise exception 'Waiters can only view their current business-day entries.' using errcode='42501'; end if;
    select state into day_state from public.business_days where business_date=p_date;
    select jsonb_build_object('day',jsonb_build_object('business_date',p_date,'state',coalesce(day_state,'not_started')),
      'own_expense_count',(select count(*) from public.expenses where created_by=actor and business_date=p_date and voided_at is null),
      'own_incurred_paise',(select coalesce(sum(amount_paise),0)::bigint from public.expenses where created_by=actor and business_date=p_date and voided_at is null),
      'own_paid_paise',(select coalesce(sum(p.amount_paise),0)::bigint from public.expense_payments p join public.expenses e on e.id=p.expense_id
        where e.created_by=actor and p.business_date=p_date and p.voided_at is null and e.voided_at is null)
    ) into result;
  end if;
  return result;
end;
$$;

create function public.close_day(p_date date,p_reason text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid := private.require_admin_actor(); snapshot jsonb; new_revision integer;
begin
  perform private.lock_financial_day(p_date);
  snapshot := public.get_day(p_date);
  if not (snapshot->>'has_sales')::boolean then raise exception 'Enter the daily sales and collections before closing this day.'; end if;
  if (snapshot->>'difference_paise')::bigint<>0 and nullif(trim(p_reason),'') is null then
    raise exception 'Add an explanation before closing a day with a short or excess amount.';
  end if;
  update public.business_days set state='closed',revision=revision+1,updated_at=now()
    where business_date=p_date returning revision into new_revision;
  snapshot := snapshot || jsonb_build_object('state','closed','revision',new_revision,'closed_by',actor,'closed_at',now());
  insert into public.day_closures(business_date,event,reason,snapshot,created_by)
    values(p_date,'close',nullif(trim(p_reason),''),snapshot,actor);
end;
$$;

create function public.reopen_day(p_date date,p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare actor uuid := private.require_admin_actor(); previous_state text;
begin
  if nullif(trim(p_reason),'') is null then raise exception 'Enter a reason for reopening this day.'; end if;
  if p_date is null or p_date>(clock_timestamp() at time zone 'Asia/Kolkata')::date then
    raise exception 'Only today or a previous day can be reopened.';
  end if;
  insert into public.business_days(business_date) values(p_date) on conflict do nothing;
  select state into previous_state from public.business_days where business_date=p_date for update;
  if previous_state='reopened' then raise exception 'This day is already reopened.'; end if;
  update public.business_days set state='reopened',revision=revision+1,updated_at=now() where business_date=p_date;
  insert into public.day_closures(business_date,event,reason,snapshot,created_by)
    values(p_date,'reopen',trim(p_reason),jsonb_build_object('previous_state',previous_state),actor);
end;
$$;

-- New functions never inherit the usual PUBLIC execute privilege.
revoke all on function private.require_active_actor() from public,anon,authenticated;
revoke all on function private.require_admin_actor() from public,anon,authenticated;
revoke all on function private.lock_financial_day(date) from public,anon,authenticated;
revoke all on function private.replay_financial_request(uuid,text,jsonb) from public,anon,authenticated;

do $$
declare signature text;
begin
  foreach signature in array array[
    'public.entry_context()', 'public.list_expenses(date,date,boolean)',
    'public.record_expense(uuid,date,uuid,text,bigint,text,text,bigint,uuid,uuid,bigint,text,text)',
    'public.record_payment(uuid,uuid,date,bigint,text,text)',
    'public.save_sales(date,bigint,bigint,bigint,bigint,text)',
    'public.get_day(date)', 'public.get_dashboard(date)',
    'public.close_day(date,text)', 'public.reopen_day(date,text)'
  ] loop
    execute 'revoke all on function '||signature||' from public,anon,authenticated';
    execute 'grant execute on function '||signature||' to authenticated';
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
