begin;
create function public.get_vendor_statement(p_vendor_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); vendor public.vendors; result jsonb; stamp timestamptz:=now();
begin
  select * into vendor from public.vendors where id=p_vendor_id;
  if not found then raise exception 'Choose a vendor from the credit ledger.';end if;
  with pending as (
    select b.* from public.expense_balances b where b.vendor_id=vendor.id and b.outstanding_paise>0
      and not exists(select 1 from public.salary_records s where s.expense_id=b.id)
  ) select jsonb_build_object('server_time',stamp,'business_date',(stamp at time zone 'Asia/Kolkata')::date,
    'reference','TOP-'||to_char(stamp at time zone 'Asia/Kolkata','YYYYMMDD-HH24MISS')||'-'||upper(left(vendor.id::text,8)),
    'cafe_name',(select cafe_name from public.app_settings where singleton),
    'vendor',jsonb_build_object('id',vendor.id,'name',vendor.name,'contact',vendor.contact_number,'address',vendor.address),
    'amount_paise',(select coalesce(sum(amount_paise),0)::bigint from pending),
    'paid_paise',(select coalesce(sum(paid_paise),0)::bigint from pending),
    'outstanding_paise',(select coalesce(sum(outstanding_paise),0)::bigint from pending),
    'expenses',(select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'business_date',e.business_date,
      'description',e.description,'amount_paise',e.amount_paise,'paid_paise',e.paid_paise,'outstanding_paise',e.outstanding_paise,
      'payments',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'business_date',p.business_date,'amount_paise',p.amount_paise,
        'payment_mode',p.payment_mode) order by p.business_date,p.created_at,p.id),'[]'::jsonb) from public.expense_payments p
        where p.expense_id=e.id and p.voided_at is null)) order by e.business_date,e.created_at,e.id),'[]'::jsonb) from pending e)
  ) into result;return result;
end;$$;
revoke all on function public.get_vendor_statement(uuid) from public,anon,authenticated;
grant execute on function public.get_vendor_statement(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
