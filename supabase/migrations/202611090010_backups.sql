begin;
create table private.backup_settings(singleton boolean primary key default true check(singleton),
  project_id uuid not null default gen_random_uuid(),enabled boolean not null default true,
  interval_hours integer not null default 24 check(interval_hours in (24,168)),retention integer not null default 14 check(retention between 2 and 60),
  epoch bigint not null default 0);
insert into private.backup_settings(singleton) values(true);
create table private.app_backups(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),
  actor_id uuid references public.profiles(id),reason text not null,payload text not null,checksum text not null);
revoke all on private.backup_settings,private.app_backups from public,anon,authenticated;
create function private.current_epoch() returns bigint language sql stable security definer set search_path='' as $$select epoch from private.backup_settings where singleton$$;
revoke all on function private.current_epoch() from public,anon,authenticated;
alter table private.financial_requests add column epoch bigint not null default 0;
alter table private.financial_requests alter column epoch set default private.current_epoch();
create or replace function private.replay_financial_request(p_id uuid,p_operation text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare previous private.financial_requests;
begin
  if p_id is null then raise exception 'A unique request reference is required.';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_id::text,784329));
  select * into previous from private.financial_requests where request_id=p_id;
  if found then
    if previous.actor_id<>auth.uid() or previous.operation<>p_operation or previous.payload<>p_payload then
      raise exception 'This request reference has already been used for different details. Refresh the entry before trying again.';end if;
    if previous.epoch<>private.current_epoch() then raise exception 'The ledger has been restored since this entry was saved. Refresh the app before making another entry.';end if;
    return previous.result;
  end if;return null;
end;$$;

create function private.capture_backup(p_reason text,p_actor uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare payload jsonb:='{}'::jsonb;t text;value jsonb;exact text;result uuid;
begin
  -- Serialize snapshots and restore. Table locks make each snapshot a coherent ledger.
  perform pg_advisory_xact_lock(571204883);
  lock table public.business_days,public.staff,public.categories,public.vendors,public.items,
    public.expenses,public.expense_payments,public.salary_records,public.sales,public.day_closures,public.app_settings in share mode;
  foreach t in array array['app_settings','business_days','categories','vendors','items','staff','expenses','expense_payments','salary_records','sales','day_closures'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.%I t',t) into value;
    payload:=payload||jsonb_build_object(t,value);
  end loop;
  exact:=payload::text;
  insert into private.app_backups(actor_id,reason,payload,checksum) values(p_actor,p_reason,exact,encode(sha256(convert_to(exact,'UTF8')),'hex')) returning id into result;
  delete from private.app_backups where id in(select id from private.app_backups order by created_at desc,id offset (select retention from private.backup_settings));
  return result;
end;$$;
revoke all on function private.capture_backup(text,uuid) from public,anon,authenticated;

create function public.backup_status() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();result jsonb;
begin
  select jsonb_build_object('project_id',s.project_id,'enabled',s.enabled,'interval_hours',s.interval_hours,'retention',s.retention,
    'backups',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'created_at',created_at,'reason',reason,'size',octet_length(payload)) order by created_at desc),'[]'::jsonb) from private.app_backups))
  into result from private.backup_settings s;return result;
end;$$;
create function public.create_backup(p_reason text default 'Manual backup') returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();begin return private.capture_backup(coalesce(nullif(trim(p_reason),''),'Manual backup'),actor);end;$$;
create function public.download_backup(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();b private.app_backups;
begin
  select * into b from private.app_backups where id=p_id;if not found then raise exception 'This backup is unavailable.';end if;
  return jsonb_build_object('format','topolina-backup','version',1,'project_id',(select project_id from private.backup_settings),'created_at',b.created_at,'payload',b.payload,'sha256',b.checksum);
end;$$;
create function public.configure_backups(p_enabled boolean,p_interval_hours integer,p_retention integer) returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();begin
  if p_enabled is null or p_interval_hours is null or p_interval_hours not in (24,168) or p_retention is null or p_retention not between 2 and 60 then raise exception 'Choose daily or weekly backups and retention between 2 and 60.';end if;
  update private.backup_settings set enabled=p_enabled,interval_hours=p_interval_hours,retention=p_retention;
  insert into public.audit_logs(actor_id,table_name,record_id,operation,after_data)values(actor,'backup_settings','singleton','CONFIGURE',jsonb_build_object('enabled',p_enabled,'interval_hours',p_interval_hours,'retention',p_retention));
end;$$;
create function public.restore_backup(p_backup jsonb,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();payload jsonb;t text;safety uuid;exact text;
begin
  if nullif(trim(p_reason),'') is null then raise exception 'A restore reason is required.';end if;
  if p_backup->>'format' is distinct from 'topolina-backup' or p_backup->>'version' is distinct from '1'
    or p_backup->>'project_id' is distinct from (select project_id::text from private.backup_settings) then raise exception 'This backup belongs to another project or an unsupported format.';end if;
  exact:=p_backup->>'payload';
  if exact is null or octet_length(exact)>52428800 or encode(sha256(convert_to(exact,'UTF8')),'hex') is distinct from p_backup->>'sha256' then raise exception 'The backup checksum is invalid or the file is too large.';end if;
  payload:=exact::jsonb;
  foreach t in array array['app_settings','business_days','categories','vendors','items','staff','expenses','expense_payments','salary_records','sales','day_closures'] loop
    if jsonb_typeof(payload->t) is distinct from 'array' then raise exception 'The backup is missing a required data table.';end if;
  end loop;
  -- All-or-nothing replacement. Other financial writers take business_days first.
  -- A concurrent master update can deadlock; Postgres aborts one transaction safely.
  perform pg_advisory_xact_lock(571204883);
  lock table public.business_days,public.staff,public.categories,public.vendors,public.items,
    public.expenses,public.expense_payments,public.salary_records,public.sales,public.day_closures,public.app_settings in exclusive mode;
  safety:=private.capture_backup('Safety backup before restore: '||trim(p_reason),actor);
  delete from public.day_closures;delete from public.salary_records;delete from public.expense_payments;
  delete from public.sales;delete from public.expenses;delete from public.items;delete from public.staff;
  delete from public.vendors;delete from public.categories;delete from public.business_days;delete from public.app_settings;
  foreach t in array array['app_settings','business_days','categories','vendors','items','staff','expenses','expense_payments','salary_records','sales','day_closures'] loop
    execute format('insert into public.%I select * from jsonb_populate_recordset(null::public.%I,$1)',t,t) using payload->t;
  end loop;
  if (select count(*) from public.app_settings)<>1 then raise exception 'The backup must contain cafe settings.';end if;
  if exists(select 1 from public.expenses e join public.expense_payments p on p.expense_id=e.id where p.voided_at is null group by e.id having sum(p.amount_paise)>e.amount_paise)
    or exists(select 1 from public.expense_payments p join public.expenses e on e.id=p.expense_id where p.voided_at is null and (p.business_date<e.business_date or e.voided_at is not null))
    or exists(select 1 from public.salary_records s join public.expenses e on e.id=s.expense_id where s.voided_at is null and e.voided_at is not null) then
    raise exception 'The backup contains inconsistent payments or salary records.';end if;
  update private.backup_settings set epoch=epoch+1;
  insert into public.audit_logs(actor_id,table_name,record_id,operation,after_data) values(actor,'backups',safety::text,'RESTORE',jsonb_build_object('reason',trim(p_reason),'source_created_at',p_backup->>'created_at','safety_backup',safety));
  return safety;
end;$$;
create function private.scheduled_backup() returns void language plpgsql security definer set search_path='' as $$
begin
  if (select enabled from private.backup_settings) and not exists(select 1 from private.app_backups where created_at>now()-make_interval(hours=>(select interval_hours from private.backup_settings))) then
    perform private.capture_backup('Scheduled backup');
  end if;
end;$$;
revoke all on function private.scheduled_backup() from public,anon,authenticated;
grant execute on function private.scheduled_backup() to service_role;
do $$declare f record;begin
  for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in
    ('backup_status','create_backup','download_backup','configure_backups','restore_backup') loop
    execute format('revoke all on function %s from public,anon,authenticated',f.signature);execute format('grant execute on function %s to authenticated',f.signature);
  end loop;
end;$$;
notify pgrst,'reload schema';
commit;
