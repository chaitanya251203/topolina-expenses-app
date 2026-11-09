# Topolina 1.0.0

Complete cafe accounting release for Android, backed by the connected Supabase
project. Internet is required.

## Included

- Shared admin/waiter expenses with category icons, manual or quantity/rate
  amounts, vendors, notes and creator attribution.
- Full/partial actual payments, outstanding credit and payment history.
- Vendor payment statements as branded PDFs, including purchase/payment dates,
  exact original/paid/pending amounts, preview, file save, print and native share.
- Manual expected sales, net cash/online/other collections, reconciliation,
  day closing and audited reopening. The India calendar day has a 1 a.m.
  next-day grace cutoff; closed dates remain locked until explicitly reopened.
- Staff management, monthly salaries and partial salary payments. Existing
  waiter/admin salary expenses can be linked without creating duplicates.
- Admin expense corrections, payment/expense voids and audit history.
- Waiter account creation, password resets, deactivation, configurable expense
  permissions and personal password changes.
- Daily/monthly reports, all requested filters, charts, historical outstanding
  balances, category/vendor summaries and CSV export.
- Manual and daily/weekly server backups, Android file export/import,
  checksum validation, atomic restore and pre-restore safety copies.
- Rounded cafe styling, animations, readable names and DNS fallback with
  hostname/certificate TLS verification.

## Validation

- Flutter analysis: no issues.
- 56 Flutter unit/widget tests passed, including four new module screens and
  statement validation and PDF generation.
- 36 embedded PostgreSQL/backend tests passed across all migrations, ledger
  arithmetic, authorization, audit, corrections, historical reports, rollback,
  backup integrity, restore, request replay and Auth handler boundaries.
- Hosted transactional smoke passed: entries, exact totals, retries, credit,
  payroll, closing/reopening, corrections, reports, voids and backup restore.
  Every financial fixture was rolled back.
- Hosted Auth flow passed: admin sign-in, waiter creation/retry, waiter sign-in,
  password reset, role isolation and immediate deactivation. Temporary accounts
  were deleted. No validation financial data was retained.
- New salary, report, backup and account screens were rendered and inspected
  at a 390 × 844 phone viewport.
- The vendor PDF was rendered and inspected as a one-page statement and a
  14-page statement with 60 purchases and 120 payments. Exact totals, dates,
  every purchase row, font glyphs, repeating headers and page counts were checked.
- All 13 migrations and the account function are deployed. Public data tables
  have RLS enabled. The hourly backup scheduler is active, and the initial
  release safety snapshot is available on the server.

## Install

Download the signed release APK. It uses a production certificate. The earlier
development APK used another certificate, so uninstall that development version
once before installing this release. Sign in with your existing account; hosted
cafe records remain in Supabase. Later production releases can install as updates.

On the phone, check sign-in on Wi-Fi and mobile data, then try expense entry,
partial payments, salary history and file export. This release has not been
installed on the user's physical phone by the developer. Android's native file
picker and device/network behavior need that final acceptance check.

Backup files cover application data. They do not restore Auth accounts/passwords
or the whole Supabase project. Mobile restore payloads are limited to 50 MiB.

Private production signing files remain local and are excluded from Git. Keep a
secure backup of the keystore and its configuration for future updates.
