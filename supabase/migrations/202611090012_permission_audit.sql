begin;
create trigger audit_change after insert or update or delete on public.role_permissions for each row execute function private.audit_change();
commit;
