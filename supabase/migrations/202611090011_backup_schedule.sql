begin;
do $$begin
  if exists(select 1 from pg_available_extensions where name='pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.schedule('topolina-automatic-backup','15 * * * *','select private.scheduled_backup()');
  end if;
end;$$;
create function public.backup_scheduler_status() returns boolean language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.require_admin_actor();result boolean:=false;
begin
  if exists(select 1 from pg_namespace where nspname='cron') then
    execute 'select exists(select 1 from cron.job where jobname=''topolina-automatic-backup'' and active)' into result;
  end if;return result;
end;$$;
revoke all on function public.backup_scheduler_status() from public,anon,authenticated;
grant execute on function public.backup_scheduler_status() to authenticated;
notify pgrst,'reload schema';
commit;
