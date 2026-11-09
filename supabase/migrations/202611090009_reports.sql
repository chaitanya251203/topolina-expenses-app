begin;
create function public.get_report(p_from date,p_to date,p_category uuid default null,p_vendor uuid default null,
  p_mode text default null,p_status text default null,p_staff uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); result jsonb;
begin
  if p_from is null or p_to is null or p_from>p_to or p_to-p_from>366 or p_to>(now() at time zone 'Asia/Kolkata')::date then
    raise exception 'Choose a date range of up to 367 days, ending today or earlier.';end if;
  if p_mode is not null and p_mode not in ('cash','online','other') then raise exception 'Invalid payment mode.';end if;
  if p_status is not null and p_status not in ('paid','partially_paid','outstanding') then raise exception 'Invalid payment status.';end if;
  with balances as (
    select e.*,coalesce(p.paid,0)::bigint paid,(e.amount_paise-coalesce(p.paid,0))::bigint outstanding,
      case when coalesce(p.paid,0)=0 then 'outstanding' when p.paid=e.amount_paise then 'paid' else 'partially_paid' end status,
      s.staff_id,t.full_name staff_name,c.name category_name,c.icon_key,v.name vendor_name
    from public.expenses e join public.categories c on c.id=e.category_id left join public.vendors v on v.id=e.vendor_id
    left join public.salary_records s on s.expense_id=e.id and s.voided_at is null left join public.staff t on t.id=s.staff_id
    left join (select expense_id,sum(amount_paise) paid from public.expense_payments where voided_at is null and business_date<=p_to group by expense_id) p on p.expense_id=e.id
    where e.voided_at is null and e.business_date<=p_to and (p_category is null or e.category_id=p_category)
      and (p_vendor is null or e.vendor_id=p_vendor) and (p_staff is null or s.staff_id=p_staff)
  ), filtered as (
    select * from balances b where (p_status is null or b.status=p_status) and
      (p_mode is null or exists(select 1 from public.expense_payments p where p.expense_id=b.id and p.voided_at is null and p.business_date<=p_to and p.payment_mode=p_mode))
  ), payments as (
    select p.*,b.category_name,b.category_id,b.vendor_name,b.vendor_id,b.staff_id,b.staff_name,b.description,b.business_date purchase_date
    from public.expense_payments p join filtered b on b.id=p.expense_id
    where p.voided_at is null and p.business_date between p_from and p_to and (p_mode is null or p.payment_mode=p_mode)
  ), daily as (
    select d::date business_date,s.expected_paise,s.cash_paise,s.online_paise,s.other_paise,
      (coalesce(s.cash_paise,0)::numeric+coalesce(s.online_paise,0)+coalesce(s.other_paise,0))::bigint collections_paise,
      coalesce((select sum(p.amount_paise)::bigint from public.expense_payments p join public.expenses e on e.id=p.expense_id where p.business_date=d::date and p.voided_at is null and e.voided_at is null),0) paid_paise,
      coalesce((select sum(amount_paise)::bigint from payments where business_date=d::date),0) filtered_paid_paise,
      coalesce((select sum(amount_paise)::bigint from filtered where business_date=d::date),0) incurred_paise,
      coalesce(bd.state,'not_started') state
    from generate_series(p_from::timestamp,p_to::timestamp,interval '1 day') d
    left join public.sales s on s.business_date=d::date left join public.business_days bd on bd.business_date=d::date
  ) select jsonb_build_object('from',p_from,'to',p_to,'as_of',p_to,
    'expected_paise',(select coalesce(sum(expected_paise),0)::bigint from public.sales where business_date between p_from and p_to),
    'cash_paise',(select coalesce(sum(cash_paise),0)::bigint from public.sales where business_date between p_from and p_to),
    'online_paise',(select coalesce(sum(online_paise),0)::bigint from public.sales where business_date between p_from and p_to),
    'other_paise',(select coalesce(sum(other_paise),0)::bigint from public.sales where business_date between p_from and p_to),
    'incurred_paise',(select coalesce(sum(amount_paise),0)::bigint from filtered where business_date>=p_from),
    'paid_paise',(select coalesce(sum(amount_paise),0)::bigint from payments),
    'outstanding_paise',(select coalesce(sum(outstanding),0)::bigint from filtered),
    'salary_paid_paise',(select coalesce(sum(amount_paise),0)::bigint from payments where staff_id is not null),
    'categories',(select coalesce(jsonb_agg(to_jsonb(x) order by x.incurred_paise desc),'[]'::jsonb) from (
      select category_id id,category_name name,icon_key,sum(case when business_date>=p_from then amount_paise else 0 end)::bigint incurred_paise,sum(outstanding)::bigint outstanding_paise,
        coalesce((select sum(p.amount_paise) from payments p where p.category_id=f.category_id),0)::bigint paid_paise from filtered f group by category_id,category_name,icon_key
    ) x),
    'vendors',(select coalesce(jsonb_agg(to_jsonb(x) order by x.outstanding_paise desc),'[]'::jsonb) from (
      select vendor_id id,coalesce(vendor_name,'No vendor') name,sum(case when business_date>=p_from then amount_paise else 0 end)::bigint incurred_paise,sum(outstanding)::bigint outstanding_paise,
        coalesce((select sum(p.amount_paise) from payments p where p.vendor_id is not distinct from f.vendor_id),0)::bigint paid_paise from filtered f group by vendor_id,vendor_name
    ) x),
    'daily',(select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('difference_paise',case when expected_paise is null then null else (expected_paise::numeric-collections_paise-paid_paise)::bigint end) order by business_date),'[]'::jsonb) from daily d),
    'payments',(select coalesce(jsonb_agg(to_jsonb(p) order by business_date,created_at),'[]'::jsonb) from payments p),
    'expenses',(select coalesce(jsonb_agg(to_jsonb(f) order by business_date,created_at),'[]'::jsonb) from filtered f where business_date>=p_from)
  ) into result;return result;
end;$$;
create function public.get_credit_summary() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();
begin
  return jsonb_build_object('paid_this_month_paise',(select coalesce(sum(p.amount_paise),0)::bigint from public.expense_payments p join public.expenses e on e.id=p.expense_id
    where p.voided_at is null and e.voided_at is null and p.business_date>=date_trunc('month',now() at time zone 'Asia/Kolkata')::date
    and not exists(select 1 from public.salary_records s where s.expense_id=e.id)
    and exists(select 1 from private.financial_requests r where r.operation='payment' and r.result->>'id'=p.id::text)));
end;$$;
revoke all on function public.get_report(date,date,uuid,uuid,text,text,uuid),public.get_credit_summary() from public,anon,authenticated;
grant execute on function public.get_report(date,date,uuid,uuid,text,text,uuid),public.get_credit_summary() to authenticated;
notify pgrst,'reload schema';
commit;
