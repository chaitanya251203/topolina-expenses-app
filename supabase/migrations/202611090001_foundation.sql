-- Phase 1. All financial writes will be introduced as transactional RPCs in
-- subsequent migrations; clients have no direct financial mutation grants.
begin;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.roles (
  code text primary key check (code in ('admin', 'waiter')),
  label text not null
);
create table public.permissions (
  code text primary key,
  description text not null
);
create table public.role_permissions (
  role_code text not null references public.roles(code),
  permission_code text not null references public.permissions(code),
  primary key (role_code, permission_code)
);
create table public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  full_name text not null check (length(trim(full_name)) between 1 and 120),
  role_code text not null default 'waiter' references public.roles(code),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.app_settings (
  singleton boolean primary key default true check (singleton),
  cafe_name text not null default 'Topolina',
  timezone text not null default 'Asia/Kolkata' check (timezone = 'Asia/Kolkata'),
  grace_minutes integer not null default 60 check (grace_minutes = 60),
  currency text not null default 'INR' check (currency = 'INR')
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 100),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index categories_name_unique on public.categories(lower(trim(name)));

create table public.items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete restrict,
  name text not null check (length(trim(name)) between 1 and 120),
  default_unit text,
  default_rate_paise bigint check (default_rate_paise >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index items_category_idx on public.items(category_id);

create table public.vendors (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  contact_number text,
  address text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.staff (
  id uuid primary key default gen_random_uuid(),
  staff_code text not null unique,
  full_name text not null check (length(trim(full_name)) between 1 and 120),
  contact_number text,
  designation text not null,
  joining_date date not null,
  default_salary_paise bigint check (default_salary_paise >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.business_days (
  business_date date primary key,
  state text not null default 'open' check (state in ('open', 'closed', 'reopened')),
  revision integer not null default 0 check (revision >= 0),
  updated_at timestamptz not null default now()
);
create table public.sales (
  business_date date primary key references public.business_days(business_date),
  expected_paise bigint not null check (expected_paise >= 0),
  cash_paise bigint not null check (cash_paise >= 0),
  online_paise bigint not null check (online_paise >= 0),
  other_paise bigint not null check (other_paise >= 0),
  notes text,
  created_by uuid not null references public.profiles(id),
  updated_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_date date not null references public.business_days(business_date),
  category_id uuid not null references public.categories(id),
  item_id uuid references public.items(id),
  vendor_id uuid references public.vendors(id),
  description text not null check (length(trim(description)) between 1 and 500),
  amount_method text not null check (amount_method in ('manual', 'calculated')),
  quantity numeric(16, 6),
  unit text,
  rate_paise bigint,
  amount_paise bigint not null check (amount_paise > 0),
  notes text,
  voided_at timestamptz,
  void_reason text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (amount_method = 'manual' and quantity is null and rate_paise is null) or
    (amount_method = 'calculated' and quantity > 0 and rate_paise > 0 and
      quantity is not null and rate_paise is not null and
      amount_paise = round(quantity * rate_paise))
  ),
  check ((voided_at is null and void_reason is null) or
         (voided_at is not null and length(trim(void_reason)) > 0))
);
create index expenses_date_idx on public.expenses(business_date);
create index expenses_creator_date_idx on public.expenses(created_by, business_date);
create index expenses_category_date_idx on public.expenses(category_id, business_date);
create index expenses_vendor_idx on public.expenses(vendor_id);
create index expenses_item_idx on public.expenses(item_id);

create table public.expense_payments (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null references public.expenses(id),
  business_date date not null references public.business_days(business_date),
  amount_paise bigint not null check (amount_paise > 0),
  payment_mode text not null check (payment_mode in ('cash', 'online', 'other')),
  notes text,
  voided_at timestamptz,
  void_reason text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check ((voided_at is null and void_reason is null) or
         (voided_at is not null and length(trim(void_reason)) > 0))
);
create index payments_expense_idx on public.expense_payments(expense_id);
create index payments_date_mode_idx on public.expense_payments(business_date, payment_mode);
create index payments_creator_idx on public.expense_payments(created_by);

-- Payroll reuses the expense/payment ledger, so a salary is counted once.
create table public.salary_records (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id),
  salary_month date not null check (extract(day from salary_month) = 1),
  expense_id uuid not null unique references public.expenses(id),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (staff_id, salary_month)
);

create table public.day_closures (
  id uuid primary key default gen_random_uuid(),
  business_date date not null references public.business_days(business_date),
  event text not null check (event in ('close', 'reopen')),
  reason text,
  snapshot jsonb,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check (event <> 'reopen' or length(trim(reason)) > 0),
  check (event <> 'close' or snapshot is not null)
);
create index closures_date_idx on public.day_closures(business_date, created_at);
create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  table_name text not null,
  record_id text not null,
  operation text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);
create index audit_created_idx on public.audit_logs(created_at);
create index audit_record_idx on public.audit_logs(table_name, record_id);

insert into public.roles values ('admin', 'Admin'), ('waiter', 'Waiter');
insert into public.permissions values
  ('expenses.create', 'Enter expenses during the business date window'),
  ('expenses.read_own', 'Read own entries during the business date window'),
  ('admin.manage', 'Administer the cafe and financial records');
insert into public.role_permissions values
  ('waiter', 'expenses.create'), ('waiter', 'expenses.read_own'),
  ('admin', 'expenses.create'), ('admin', 'expenses.read_own'), ('admin', 'admin.manage');
insert into public.app_settings(singleton) values (true);
insert into public.categories(name) values
  ('Bakery'), ('Veg'), ('Grocery'), ('Dairy'), ('Salary'), ('Welfare Exp Staff'),
  ('Conveyance'), ('Rent'), ('Beverages'), ('Frozen'), ('Software');

create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles
    where id = auth.uid() and active and role_code = 'admin');
$$;
create function private.is_active_user() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles where id = auth.uid() and active);
$$;
create function private.in_entry_window(p_date date, p_now timestamptz default now())
returns boolean language sql immutable set search_path = '' as $$
  select p_date = (p_now at time zone 'Asia/Kolkata')::date or (
    p_date = (p_now at time zone 'Asia/Kolkata')::date - 1 and
    (p_now at time zone 'Asia/Kolkata')::time < time '01:00'
  );
$$;

create function private.audit_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  old_row jsonb;
  new_row jsonb;
begin
  if TG_OP <> 'INSERT' then old_row := to_jsonb(OLD); end if;
  if TG_OP <> 'DELETE' then new_row := to_jsonb(NEW); end if;
  insert into public.audit_logs(actor_id, table_name, record_id, operation, before_data, after_data)
    values (auth.uid(), TG_TABLE_NAME,
      coalesce(new_row->>'id', old_row->>'id', new_row->>'business_date',
               old_row->>'business_date', new_row->>'singleton', 'settings'),
      TG_OP, old_row, new_row);
  return coalesce(NEW, OLD);
end;
$$;

-- Exposed tables start with explicit minimal grants, regardless of project defaults.
do $$
declare t text;
begin
  foreach t in array array['roles', 'permissions', 'role_permissions', 'profiles',
    'app_settings', 'categories', 'items', 'vendors', 'staff', 'business_days',
    'sales', 'expenses', 'expense_payments', 'salary_records', 'day_closures', 'audit_logs']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  foreach t in array array['profiles', 'app_settings', 'categories', 'items', 'vendors',
    'staff', 'business_days', 'sales', 'expenses', 'expense_payments', 'salary_records', 'day_closures']
  loop
    execute format('create trigger audit_change after insert or update or delete on public.%I
      for each row execute function private.audit_change()', t);
  end loop;
end;
$$;

create policy profile_self_or_admin on public.profiles for select to authenticated
  using (id = auth.uid() or private.is_admin());

do $$
declare t text;
begin
  foreach t in array array['roles', 'permissions', 'role_permissions', 'app_settings'] loop
    execute format('create policy active_user_read on public.%I for select to authenticated
      using (private.is_active_user())', t);
  end loop;
  foreach t in array array['categories', 'items', 'vendors'] loop
    execute format('create policy master_read on public.%I for select to authenticated
      using (private.is_admin() or (active and private.is_active_user()))', t);
    execute format('grant insert, update on public.%I to authenticated', t);
    execute format('create policy admin_insert on public.%I for insert to authenticated
      with check (private.is_admin())', t);
    execute format('create policy admin_update on public.%I for update to authenticated
      using (private.is_admin()) with check (private.is_admin())', t);
  end loop;
  foreach t in array array['staff', 'sales', 'salary_records', 'day_closures', 'audit_logs'] loop
    execute format('create policy admin_read on public.%I for select to authenticated
      using (private.is_admin())', t);
  end loop;
end;
$$;
create policy days_read on public.business_days for select to authenticated
  using (private.is_admin() or (private.is_active_user() and private.in_entry_window(business_date)));
create policy expense_read on public.expenses for select to authenticated
  using (private.is_admin() or (private.is_active_user() and created_by = auth.uid()
    and private.in_entry_window(business_date)));
create policy payment_read on public.expense_payments for select to authenticated
  using (private.is_admin() or (private.is_active_user() and exists (
    select 1 from public.expenses e where e.id = expense_id and e.created_by = auth.uid()
      and private.in_entry_window(e.business_date))));

revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.is_active_user() to authenticated;
grant execute on function private.in_entry_window(date, timestamptz) to authenticated;

-- Service-only bootstrap: clients cannot become the first admin by racing signup.
create function public.bootstrap_admin(p_user_id uuid, p_full_name text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(837246190);
  if exists(select 1 from public.profiles where role_code = 'admin') then
    raise exception 'An admin already exists';
  end if;
  insert into public.profiles(id, full_name, role_code)
    values (p_user_id, p_full_name, 'admin');
end;
$$;
revoke all on function public.bootstrap_admin(uuid, text) from public, anon, authenticated;
grant execute on function public.bootstrap_admin(uuid, text) to service_role;

commit;
