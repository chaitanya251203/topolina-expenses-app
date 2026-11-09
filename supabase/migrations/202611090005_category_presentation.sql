-- Full category names and configurable icons, preserving all existing IDs and
-- historical expense references. Existing clients may ignore the extra fields.
begin;
alter table public.categories add column icon_key text not null default 'category'
  check (length(icon_key) between 1 and 64);
update public.categories set name='Vegetables',updated_at=now() where name='Veg';
update public.categories set name='Staff Welfare Expense',updated_at=now() where name='Welfare Exp Staff';
update public.categories set icon_key=case name
  when 'Bakery' then 'bakery' when 'Vegetables' then 'vegetables'
  when 'Grocery' then 'grocery' when 'Dairy' then 'dairy' when 'Salary' then 'salary'
  when 'Staff Welfare Expense' then 'staff' when 'Conveyance' then 'conveyance'
  when 'Rent' then 'rent' when 'Beverages' then 'beverages' when 'Frozen' then 'frozen'
  when 'Software' then 'software' else 'category' end;

create or replace function public.entry_context() returns jsonb
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
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'icon_key',icon_key) order by name),'[]'::jsonb)
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

create or replace function public.list_expenses(p_from date default null,p_to date default null,p_outstanding_only boolean default false)
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
    'id',e.id,'business_date',e.business_date,'category_id',e.category_id,'category_name',c.name,'category_icon_key',c.icon_key,
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


notify pgrst, 'reload schema';
commit;
