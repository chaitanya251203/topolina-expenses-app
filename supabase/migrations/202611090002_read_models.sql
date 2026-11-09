begin;

create function public.session_context() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id = auth.uid();
  if not found then raise exception 'Account not provisioned' using errcode = '42501'; end if;
  return jsonb_build_object('id', p.id, 'full_name', p.full_name,
    'role_code', p.role_code, 'active', p.active, 'server_time', now());
end;
$$;
revoke all on function public.session_context() from public, anon, authenticated;
grant execute on function public.session_context() to authenticated;

create view public.expense_balances with (security_invoker = true) as
select e.*, coalesce(p.paid_paise, 0)::bigint as paid_paise,
  (e.amount_paise - coalesce(p.paid_paise, 0))::bigint as outstanding_paise,
  case when coalesce(p.paid_paise, 0) = 0 then 'outstanding'
    when p.paid_paise = e.amount_paise then 'paid' else 'partially_paid' end as payment_status
from public.expenses e left join (
  select expense_id, sum(amount_paise) as paid_paise from public.expense_payments
    where voided_at is null group by expense_id
) p on p.expense_id = e.id where e.voided_at is null;

create view public.salary_payments with (security_invoker = true) as
select p.*, s.staff_id, s.salary_month from public.salary_records s
join public.expense_payments p on p.expense_id = s.expense_id
where p.voided_at is null and private.is_admin();

create view public.daily_reconciliation with (security_invoker = true) as
select d.business_date, d.state as day_state, s.expected_paise,
  s.cash_paise, s.online_paise, s.other_paise,
  (s.cash_paise + s.online_paise + s.other_paise) as collections_paise,
  coalesce(p.paid_paise, 0)::bigint as paid_paise,
  (s.cash_paise + s.online_paise + s.other_paise + coalesce(p.paid_paise, 0))::bigint as accounted_paise,
  (s.expected_paise - s.cash_paise - s.online_paise - s.other_paise - coalesce(p.paid_paise, 0))::bigint as difference_paise
from public.business_days d
left join public.sales s using (business_date)
left join (
  select p.business_date, sum(p.amount_paise) as paid_paise
  from public.expense_payments p join public.expenses e on e.id = p.expense_id
  where p.voided_at is null and e.voided_at is null group by p.business_date
) p using (business_date)
where private.is_admin();

revoke all on public.expense_balances, public.salary_payments, public.daily_reconciliation from anon, authenticated;
grant select on public.expense_balances, public.salary_payments, public.daily_reconciliation to authenticated;
commit;
