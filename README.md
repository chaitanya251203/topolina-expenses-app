# Topolina

An Android cafe accounting app built with Flutter and Supabase. Internet is
required. Version **0.2.0** adds working daily accounting workflows to the
foundation. It is a development build; the complete original scope is still in progress.

## What works now

- Branded sign-in using the supplied Topolina logo, cream/forest-green Material 3
  styling, rounded buttons, subtle press/page/loading animations and reduced-motion support.
- Supabase Auth integration, session-aware navigation, active-account checks,
  distinct admin/waiter account presentation, retry and sign-out states.
- Live dashboard totals, shared admin/waiter expense entry and history, exact
  manual/calculated amounts, immediate/partial payments and on-credit purchases.
- Admin credit ledger with payment history and full/partial settlement.
- Daily expected sales and net collections, calculated reconciliation with
  contributing payments, close/reopen workflows and audited reasons.
- Category, vendor and item creation/editing/deactivation, searchable category
  pickers, full category labels and configurable icons.
- Normalized PostgreSQL foundation, explicit grants/RLS, audit triggers, initial
  category seeds, read models and service-only first-admin provisioning.
- Exact paise parsing, fractional-quantity rounding and reconciliation helpers.
- Asia/Kolkata calendar dates with the previous-day grace window ending at 01:00.

Staff/payroll screens, waiter-account/permission management, reports, expense
corrections, in-app backup/restore and final production release signing remain
later stages. Direct financial table writes remain revoked: transactions are
saved through permission-checked, idempotent RPCs. No demo financial data is seeded.

## Setup

Validated with Flutter 3.47.9 / Dart 3.13.7. Install a compatible stable Flutter
SDK, Android SDK platform 36 and build tools, and a supported JDK. Dependencies
are pinned by `pubspec.lock`. A local SDK may also live in `.tooling/flutter`;
downloaded tooling is excluded from Git.

1. Copy `config/supabase.example.json` to `config/supabase.local.json`.
2. Set the project's root HTTPS URL and **publishable** key. Do not append
   `/rest/v1/` and do not put a database password or service-role key in this file.
3. Apply the database migrations below and provision the first admin.
4. Run:

```powershell
flutter pub get
flutter run --dart-define-from-file=config/supabase.local.json
```

On this Windows workspace, `scripts/flutter.ps1` locates the local SDK and sets
project-local Android/Gradle caches and a short Java socket directory:

```powershell
.\scripts\flutter.ps1 test
.\scripts\flutter.ps1 analyze
.\scripts\flutter.ps1 run --dart-define-from-file=config/supabase.local.json
```

The app tries normal device DNS first. If that lookup fails for its configured
Supabase host, it uses Google DNS over HTTPS with a short cache. Financial
requests still connect directly to Supabase with original-hostname TLS
verification. No system DNS/trust settings are modified. This addresses the
observed Wi-Fi DNS failure; wider network/IP blocking still requires device testing.

## Database and architecture

`lib/app` owns theme and navigation. `lib/core` contains configuration, exact
money/date logic and reusable widgets. `lib/features` separates authentication,
workspace presentation and category repositories/providers/screens. Future
features use the same feature-based boundaries.

Supabase is authoritative. Flutter repositories make HTTPS requests using the
signed-in user's session. PostgreSQL grants, RLS and transactional functions
enforce business rules independently of the UI. No local financial database or
offline synchronization is used. Supabase Auth owns password hashing.

The initial schema contains:

- `profiles → auth.users`, `roles`, `permissions`, `role_permissions`.
- `categories → items`, `vendors`, `staff`, `app_settings`.
- `business_days → sales`, `expenses → expense_payments`.
- `staff → salary_records → expenses`: payroll shares the canonical expense and
  payment ledger; `salary_payments` is a view, preventing a second payment copy.
- `day_closures` for historical closing/reopening events and `audit_logs`.
- Security-invoker views `expense_balances` and `daily_reconciliation` calculate
  balances and payment-date totals from underlying records.

Paise use PostgreSQL `bigint`; quantities use exact `numeric(16,6)`. Calculated
amounts round half up once. Statuses/balances are derived, not independently
editable. Deactivation preserves foreign-key references. Direct financial
insert/update/delete operations are not exposed to client roles.

`record_expense` atomically creates the purchase and any immediate payment;
`record_payment` locks its obligation and checks the remaining balance. Request
UUID receipts prevent duplicate submissions and reject altered retries. All
financial writers lock the affected business day. Sales, closing and reopening
are admin-only. Closing requires sales and an explanation for any discrepancy.
Reopening retains earlier closing snapshots and requires a reason.

Migrations are in `supabase/migrations`, applied in timestamp order. For the
standard Supabase CLI workflow:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

An alternative verified-TLS operator tool is available when using the database
pooler. Supply `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` through the process
environment. Add the Supabase CA through `NODE_EXTRA_CA_CERTS` if required.
Never commit the credential values.

```powershell
npm ci --prefix tools/database
node tools/database/remote.mjs inspect
node tools/database/remote.mjs migrate
node tools/database/remote.mjs verify
```

`node tools/database/remote.mjs backup` creates a consistent application-data
safety snapshot in ignored `.tooling/backups`, preserving PostgreSQL money as
exact JSON text. This is an operator safeguard, not a full Auth/project backup
or the pending in-app backup/restore feature.

The migration command records versions in Supabase's migration-history table,
applies each file transactionally and does not reset or delete existing data.
Inspect an existing database before applying the initial schema. Back up a
nonempty production database before future migrations.

## First admin

Create the intended user through Supabase Authentication (or the one-time
operator signup tool) using the intended email/password. Confirm the email when
required. Supply `TOPOLINA_ADMIN_EMAIL` and `TOPOLINA_ADMIN_NAME` and the database
connection environment, then run:

```powershell
node tools/database/remote.mjs bootstrap
```

This calls a privileged, transaction-locked bootstrap function. It cannot be
called by an anonymous or regular authenticated app user, and it refuses to
create a second initial admin. No default app password is stored in the repo.
The chosen admin password is entered at sign-in, not compiled into the APK.

`tools/database/initialize-auth.mjs create` and `verify` are optional one-time
operator commands using `TOPOLINA_ADMIN_EMAIL` / `TOPOLINA_ADMIN_PASSWORD`.
They never print credentials or tokens. `TOPOLINA_DNS_SERVER` optionally selects
a resolver for this operator tool only; it does not change device/system DNS.

Public sign-up should be disabled in production Auth settings after bootstrap;
waiter accounts will be created through the admin workflow in a later stage.
Unprovisioned Auth users cannot access business records.

## Validation

```powershell
flutter analyze
flutter test
npm ci --prefix tools/database
npm test --prefix tools/database
```

Flutter tests cover amount precision/overflow, fractional rounding,
balanced/short/excess reconciliation, date/year/month/cutoff boundaries, public
configuration keys, login errors, inactive accounts, account switching,
category search, expense/payment save/retry behavior, sales and closing/reopening
dialogs, master-data changes, category visuals, DNS fallback/TLS handshakes, and
small-screen layouts at large text sizes.

Database tests execute the migrations, triggers, views and RLS in embedded
PostgreSQL (PGlite, development-only). The Supabase Auth boundary is stubbed;
these tests do not replace hosted authentication or Android device testing.
They verify category seeds, anonymous denial, waiter restrictions, exact cutoff,
credit-payment dates, partial payroll history, closed-day locks, request replay,
overpayment, closing snapshots and audit/deactivation behavior.

`tools/database/smoke.mjs` validates the hosted authenticated transaction flow
inside a transaction which is always rolled back. `tools/check_connection.dart`
checks the actual app transport; optional `TOPOLINA_SMOKE_EMAIL` and
`TOPOLINA_SMOKE_PASSWORD` enable read-only authenticated API checks. These
credentials are environment-only and are never stored or printed.

## APK builds

Development APK:

```powershell
flutter build apk --debug --dart-define-from-file=config/supabase.local.json
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. This is a development
artifact, not the final signed production release.

Production requires a private signing keystore and ignored `android/key.properties`
containing `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. Preserve
the keystore securely for future APK updates. Then build:

```powershell
flutter build apk --release --dart-define-from-file=config/supabase.local.json
```

The final production APK, operational backup/recovery and real-device financial
acceptance checks are later delivery stages. Never use a debug-signed build as
the production release.

## Confirmed business behavior

See `docs/decisions.md` for the accepted architecture change and delivery stages.
Collections are entered after expenses. Reconciliation is expected sales minus
(entered collections + payments actually made on that business date). Credit
purchases and unpaid salary do not count as payments. Admin and waiter entries
share one ledger. Closed records require an explicitly audited reopen to change.
