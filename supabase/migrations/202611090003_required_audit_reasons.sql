-- SQL CHECK expressions also accept NULL; explicitly reject missing reasons.
begin;
alter table public.expenses add constraint expense_void_reason_required
  check (voided_at is null or (void_reason is not null and length(trim(void_reason)) > 0));
alter table public.expense_payments add constraint payment_void_reason_required
  check (voided_at is null or (void_reason is not null and length(trim(void_reason)) > 0));
alter table public.day_closures add constraint reopen_reason_required
  check (event <> 'reopen' or (reason is not null and length(trim(reason)) > 0));
commit;
