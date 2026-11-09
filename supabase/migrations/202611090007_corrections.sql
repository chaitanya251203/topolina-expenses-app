begin;
create function public.correct_expense(p_id uuid,p_expense_id uuid,p_description text,p_amount_paise bigint,
  p_category_id uuid,p_vendor_id uuid,p_notes text,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); old public.expenses; paid numeric; payload jsonb; replay jsonb; result jsonb;
begin
  payload:=jsonb_build_object('expense',p_expense_id,'description',p_description,'amount',p_amount_paise,
    'category',p_category_id,'vendor',p_vendor_id,'notes',p_notes,'reason',p_reason);
  replay:=private.replay_financial_request(p_id,'correct_expense',payload);if replay is not null then return replay;end if;
  if nullif(trim(p_reason),'') is null or nullif(trim(p_description),'') is null or p_amount_paise is null or p_amount_paise<=0 then
    raise exception 'Enter a description, positive amount and reason for this correction.';end if;
  select * into old from public.expenses where id=p_expense_id;
  if not found or old.voided_at is not null then raise exception 'This expense is unavailable.';end if;
  perform private.lock_financial_day(old.business_date);
  select * into old from public.expenses where id=p_expense_id for update;
  if old.voided_at is not null then raise exception 'This expense has been voided.';end if;
  select coalesce(sum(amount_paise),0) into paid from public.expense_payments where expense_id=old.id and voided_at is null;
  if p_amount_paise<paid then raise exception 'Amount cannot be lower than payments already recorded. Correct the payments first.';end if;
  perform 1 from public.categories where id=p_category_id and (active or id=old.category_id) for share;
  if not found then raise exception 'Choose an active category.';end if;
  if p_vendor_id is not null then
    perform 1 from public.vendors where id=p_vendor_id and (active or id=old.vendor_id) for share;
    if not found then raise exception 'Choose an active vendor.';end if;
  end if;
  update public.expenses set description=trim(p_description),amount_paise=p_amount_paise,
    category_id=p_category_id,vendor_id=p_vendor_id,notes=nullif(trim(p_notes),''),
    amount_method=case when amount_paise=p_amount_paise then amount_method else 'manual' end,
    quantity=case when amount_paise=p_amount_paise then quantity else null end,
    unit=case when amount_paise=p_amount_paise then unit else null end,
    rate_paise=case when amount_paise=p_amount_paise then rate_paise else null end,
    item_id=case when category_id=p_category_id then item_id else null end,updated_at=now() where id=old.id;
  insert into public.audit_logs(actor_id,table_name,record_id,operation,before_data,after_data)
    values(actor,'expenses',old.id::text,'CORRECT',to_jsonb(old),jsonb_build_object('reason',trim(p_reason)));
  result:=jsonb_build_object('id',old.id);
  insert into private.financial_requests values(p_id,actor,'correct_expense',payload,result,now());return result;
end;$$;

create function public.void_payment(p_id uuid,p_payment_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); payment public.expense_payments; payload jsonb; replay jsonb; result jsonb;
begin
  payload:=jsonb_build_object('payment',p_payment_id,'reason',p_reason);
  replay:=private.replay_financial_request(p_id,'void_payment',payload);if replay is not null then return replay;end if;
  if nullif(trim(p_reason),'') is null then raise exception 'A reason is required to void a payment.';end if;
  select * into payment from public.expense_payments where id=p_payment_id;
  if not found then raise exception 'This payment is unavailable.';end if;
  perform private.lock_financial_day(payment.business_date);
  perform 1 from public.expenses where id=payment.expense_id for update;
  select * into payment from public.expense_payments where id=p_payment_id for update;
  if payment.voided_at is not null then raise exception 'This payment has already been voided.';end if;
  update public.expense_payments set voided_at=now(),void_reason=trim(p_reason) where id=payment.id;
  result:=jsonb_build_object('id',payment.id);
  insert into private.financial_requests values(p_id,actor,'void_payment',payload,result,now());return result;
end;$$;

create function public.void_expense(p_id uuid,p_expense_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); expense public.expenses; payload jsonb; replay jsonb; result jsonb;
begin
  payload:=jsonb_build_object('expense',p_expense_id,'reason',p_reason);
  replay:=private.replay_financial_request(p_id,'void_expense',payload);if replay is not null then return replay;end if;
  if nullif(trim(p_reason),'') is null then raise exception 'A reason is required to void an expense.';end if;
  select * into expense from public.expenses where id=p_expense_id;
  if not found then raise exception 'This expense is unavailable.';end if;
  perform private.lock_financial_day(expense.business_date);
  select * into expense from public.expenses where id=p_expense_id for update;
  if expense.voided_at is not null then raise exception 'This expense has already been voided.';end if;
  if exists(select 1 from public.expense_payments where expense_id=expense.id and voided_at is null) then
    raise exception 'Void the active payments first. Their payment dates must be open or explicitly reopened.';end if;
  update public.expenses set voided_at=now(),void_reason=trim(p_reason),updated_at=now() where id=expense.id;
  update public.salary_records set voided_at=now(),void_reason=trim(p_reason) where expense_id=expense.id and voided_at is null;
  result:=jsonb_build_object('id',expense.id);
  insert into private.financial_requests values(p_id,actor,'void_expense',payload,result,now());return result;
end;$$;

create function public.get_audit_logs(p_before bigint default null,p_table text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); result jsonb;
begin
  select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc),'[]'::jsonb) into result from (
    select l.*,coalesce(p.full_name,'System') actor_name from public.audit_logs l left join public.profiles p on p.id=l.actor_id
    where (p_before is null or l.id<p_before) and (p_table is null or l.table_name=p_table) order by l.id desc limit 50
  ) a;return result;
end;$$;
revoke all on function public.correct_expense(uuid,uuid,text,bigint,uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function public.void_payment(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.void_expense(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.get_audit_logs(bigint,text) from public,anon,authenticated;
grant execute on function public.correct_expense(uuid,uuid,text,bigint,uuid,uuid,text,text) to authenticated;
grant execute on function public.void_payment(uuid,uuid,text) to authenticated;
grant execute on function public.void_expense(uuid,uuid,text) to authenticated;
grant execute on function public.get_audit_logs(bigint,text) to authenticated;
notify pgrst,'reload schema';
commit;
