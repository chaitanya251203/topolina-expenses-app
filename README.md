# Topolina

An Android cafe accounting app built with Flutter and Supabase. Internet is
required. Version **1.0.0** includes the complete accounting workflow and a
privately signed production APK.

## What works now

User documentation: [Functionality guide](output/pdf/Topolina_Functionality_Guide.pdf)
and [Functionality flow map](output/pdf/Topolina_Functionality_Flow_Map.pdf).
Editable descriptions are in [docs/functionality-guide.md](docs/functionality-guide.md).

- Branded sign-in using the supplied Topolina logo, cream/forest-green Material 3
  styling, rounded buttons, subtle press/page/loading animations and reduced-motion support.
- Supabase Auth integration, session-aware navigation, active-account checks,
  distinct admin/waiter account presentation, retry and sign-out states.
- Live dashboard totals, shared admin/waiter expense entry and history, exact
  manual/calculated amounts, immediate/partial payments and on-credit purchases.
- Admin credit ledger with payment history and full/partial settlement.
- Vendor payment-statement PDFs with the logo, purchase dates, recorded payment
  dates, original/paid/pending amounts and an exact balance. Preview, save,
  print or share through Android's share menu.
- Daily expected sales and net collections, calculated reconciliation with
  contributing payments, close/reopen workflows and audited reasons.
- Category, vendor and item creation/editing/deactivation, searchable category
  pickers, full category labels and configurable icons.
- Normalized PostgreSQL foundation, explicit grants/RLS, audit triggers, initial
  category seeds, read models and service-only first-admin provisioning.
- Exact paise parsing, fractional-quantity rounding and reconciliation helpers.
- Asia/Kolkata calendar dates with the previous-day grace window ending at 01:00.
- Staff management, monthly salary obligations, partial payments, and linking an
  existing salary expense without duplicating it.
- Admin corrections and payment/expense voids with mandatory reasons, historical
  values, closed-day checks and an audit viewer.
- Waiter account creation, password resets, active/inactive accounts, configurable
  expense permissions and self-service password changes.
- Daily/monthly reports, category/vendor/staff/mode/status filters, historical
  balances, payment charts, reconciliation history and exact INR CSV exports.
- Manual and scheduled server snapshots, native Android file export/import,
  checksum validation, atomic restore and mandatory pre-restore safety snapshots.

Direct financial table writes remain revoked: transactions are saved through
permission-checked, idempotent RPCs. No demo financial data is seeded.

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
workspace, expenses, reconciliation, masters, payroll, audit, users, reports and
backup repositories/providers/screens.

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
or a portable in-app restore file. In-app backups use their own versioned,
checksummed envelope described below.

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
waiter accounts are created through **More → App users & permissions**.
Unprovisioned Auth users cannot access business records.

Deploy the Auth administration function after database migrations:

```powershell
npx supabase functions deploy manage-users --remote=YOUR_PROJECT_REF --use-api --yes
```

Its handler validates the caller through Auth and the live active admin profile.
The service-role key stays in Supabase's function environment. The handler never
accepts an arbitrary target role or returns credentials. Configurable waiter
permissions are enforced both by RPC boundaries and direct table RLS.

## Reports and recovery

In **Credit ledger**, choose **Share payment statement** under a vendor. The
statement fetches a fresh, coherent server snapshot and lists only that vendor's
pending purchases, plus payments already recorded against those purchases. It
includes the preparation time and reference. Sharing a statement changes no
accounting records. Vendor contact/address are included when entered; internal
notes and staff/payroll details are excluded. Assign a vendor to an expense
before creating its vendor statement.

Expense purchases follow their purchase dates; payments follow their actual
payment dates. Outstanding balances use only payments through the report's end
date and include older unpaid purchases. Expense filters do not allocate sales
to categories: sales and reconciliation always show the complete dates.
Status filters describe the balance at the report end date. CSV values remain
exact decimal INR strings, and free-form spreadsheet formulas are escaped.

**More → Backups & restore** creates a coherent application snapshot on the
server, then offers Android's native save dialog. Automatic daily/weekly
snapshots run on Supabase Cron even while the app is closed. The default is
daily, retaining 14 snapshots; the admin can change frequency and retention.
The hourly worker creates a snapshot only when the configured interval is due.

Restores require the current admin password, a reason and explicit confirmation.
Only matching project identity, format/version and SHA-256 checksums are
accepted. Database constraints and payment totals are checked transactionally.
A safety snapshot is taken before replacement. Failure rolls the entire restore
back. Audit history, users, roles and passwords are preserved. Saved request
receipts from before a restore cannot silently replay old writes.

These are application-data snapshots, **not complete Supabase project/Auth
backups**. A mobile restore accepts up to 50 MiB of payload (60 MiB file envelope).
Operator recovery is required for larger datasets. Export files contain cafe
financial data. Reinstalling the app does not delete the hosted ledger.

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
overpayment, closing snapshots, corrections/voids, historical reports, permission
changes, checksum rejection, atomic restore, safety snapshots and stale retries.
The account-handler tests also cover authorization and empty RPC responses.

`tools/database/smoke.mjs` validates the hosted authenticated transaction flow
inside a transaction which is always rolled back. `tools/check_connection.dart`
checks the actual app transport; optional `TOPOLINA_SMOKE_EMAIL` and
`TOPOLINA_SMOKE_PASSWORD` enable read-only authenticated API checks. These
credentials are environment-only and are never stored or printed.

`tools/database/account-smoke.mjs` tests hosted create/retry/login/reset and
deactivation using a temporary account, then removes it. It requires operator
CLI login and `TOPOLINA_ADMIN_EMAIL` / `TOPOLINA_ADMIN_PASSWORD`. It obtains a
cleanup credential in memory and never prints or saves it. It creates no
financial fixtures. `release-health.mjs` verifies protection/scheduling and
creates an actual release safety snapshot.

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

Output: `build/app/outputs/flutter-apk/app-release.apk`. The delivery copy is
`build/releases/Topolina-1.0.0-release.apk`. This universal APK includes supported
ARM and emulator architectures. Release mode removes Flutter's debug runtime
and debug-only assets. APKs and private signing material are excluded from Git.

The production certificate differs from the earlier development APK. For this
one-time transition, uninstall the development app, install the release APK,
and sign in again. Hosted cafe records remain in Supabase. Future releases use
the same private production key and can install as updates. Keep a secure copy
of `android/topolina-release.jks` and `android/key.properties`; losing this key
prevents updates to existing installations.

Automated and hosted checks are documented in `docs/release-1.0.0.md`. Physical
phone installation, vendor file-picker behavior and the user's Wi-Fi network
still require a real-device acceptance check.

## Confirmed business behavior

See `docs/decisions.md` for the accepted architecture change and delivery stages.
Collections are entered after expenses. Reconciliation is expected sales minus
(entered collections + payments actually made on that business date). Credit
purchases and unpaid salary do not count as payments. Admin and waiter entries
share one ledger. Closed records require an explicitly audited reopen to change.
