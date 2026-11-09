begin;
create function private.has_permission(p_code text) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.profiles p join public.role_permissions rp on rp.role_code=p.role_code
    where p.id=auth.uid() and p.active and (rp.permission_code=p_code or rp.permission_code='admin.manage'));
$$;
revoke all on function private.has_permission(text) from public,anon,authenticated;
grant execute on function private.has_permission(text) to authenticated;
create or replace function public.session_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;
begin
  select * into p from public.profiles where id=auth.uid();
  if not found then raise exception 'Account not provisioned' using errcode='42501';end if;
  return jsonb_build_object('id',p.id,'full_name',p.full_name,'role_code',p.role_code,'active',p.active,'server_time',now(),
    'permissions',(select coalesce(jsonb_agg(permission_code),'[]'::jsonb) from public.role_permissions where role_code=p.role_code));
end;$$;
create function public.provision_waiter(p_user_id uuid,p_name text) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();
begin
  if p_user_id is null or nullif(trim(p_name),'') is null or length(trim(p_name))>120 then raise exception 'Enter a valid name.';end if;
  if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'Create the authentication account first.';end if;
  if exists(select 1 from public.profiles where id=p_user_id and role_code<>'waiter') then raise exception 'This account is an administrator.';end if;
  insert into public.profiles(id,full_name,role_code) values(p_user_id,trim(p_name),'waiter') on conflict(id) do nothing;
end;$$;
create function public.list_users() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'full_name',p.full_name,'role_code',p.role_code,'active',p.active,'email',u.email) order by p.full_name),'[]'::jsonb)
    into result from public.profiles p join auth.users u on u.id=p.id;return result;
end;$$;
create function public.find_auth_user(p_email text) returns uuid language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor(); result uuid;
begin select id into result from auth.users where lower(email)=lower(trim(p_email));return result;end;$$;
create function public.update_waiter(p_user_id uuid,p_name text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();
begin
  if p_active is null or nullif(trim(p_name),'') is null then raise exception 'Enter a name and account status.';end if;
  update public.profiles set full_name=trim(p_name),active=p_active,updated_at=now() where id=p_user_id and role_code='waiter';
  if not found then raise exception 'Only waiter accounts can be changed here.';end if;
end;$$;
create function public.set_waiter_permission(p_code text,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();
begin
  if p_code is null or p_code not in ('expenses.create','expenses.read_own') or p_enabled is null then
    raise exception 'Only waiter expense permissions can be changed.';end if;
  if p_enabled then insert into public.role_permissions values('waiter',p_code) on conflict do nothing;
  else delete from public.role_permissions where role_code='waiter' and permission_code=p_code;end if;
end;$$;
create function public.log_password_reset(p_user_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();
begin
  if not exists(select 1 from public.profiles where id=p_user_id and role_code='waiter') then raise exception 'Choose a waiter account.';end if;
  insert into public.audit_logs(actor_id,table_name,record_id,operation,after_data) values(actor,'profiles',p_user_id::text,'PASSWORD_RESET','{"password":"changed securely"}'::jsonb);
end;$$;
alter policy expense_read on public.expenses using (private.is_admin() or (private.has_permission('expenses.read_own') and created_by=auth.uid() and private.in_entry_window(business_date)));
alter policy payment_read on public.expense_payments using (private.is_admin() or (private.has_permission('expenses.read_own') and exists(select 1 from public.expenses e where e.id=expense_id and e.created_by=auth.uid() and private.in_entry_window(e.business_date))));

-- Keep the existing, tested implementation private; enforce configurable permissions at every public command boundary.
alter function public.record_expense(uuid,date,uuid,text,bigint,text,text,bigint,uuid,uuid,bigint,text,text) set schema private;
create function public.record_expense(p_id uuid,p_date date,p_category_id uuid,p_description text,p_amount_paise bigint,
  p_quantity text default null,p_unit text default null,p_rate_paise bigint default null,p_item_id uuid default null,
  p_vendor_id uuid default null,p_paid_paise bigint default 0,p_payment_mode text default null,p_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  perform private.require_active_actor();
  if not private.has_permission('expenses.create') then raise exception 'Expense entry is disabled for your account.' using errcode='42501';end if;
  return private.record_expense(p_id,p_date,p_category_id,p_description,p_amount_paise,p_quantity,p_unit,p_rate_paise,p_item_id,p_vendor_id,p_paid_paise,p_payment_mode,p_notes);
end;$$;
alter function public.list_expenses(date,date,boolean) set schema private;
create function public.list_expenses(p_from date default null,p_to date default null,p_outstanding_only boolean default false) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform private.require_active_actor();
  if not private.has_permission('expenses.read_own') then raise exception 'Expense history is disabled for your account.' using errcode='42501';end if;
  return private.list_expenses(p_from,p_to,p_outstanding_only);
end;$$;
alter function public.get_dashboard(date) set schema private;
create function public.get_dashboard(p_date date) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.has_permission('expenses.read_own') then
    perform private.require_active_actor();return jsonb_build_object('day',jsonb_build_object('business_date',p_date,'state','not_started'),'own_expense_count',0,'own_incurred_paise',0,'own_paid_paise',0);
  end if;
  return private.get_dashboard(p_date);
end;$$;
revoke all on function private.record_expense(uuid,date,uuid,text,bigint,text,text,bigint,uuid,uuid,bigint,text,text),private.list_expenses(date,date,boolean),private.get_dashboard(date) from public,anon,authenticated;
do $$declare f record;begin
  for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in
    ('provision_waiter','list_users','find_auth_user','update_waiter','set_waiter_permission','log_password_reset','record_expense','list_expenses','get_dashboard') loop
    execute format('revoke all on function %s from public,anon,authenticated',f.signature);
    execute format('grant execute on function %s to authenticated',f.signature);
  end loop;
end;$$;
notify pgrst,'reload schema';
commit;
