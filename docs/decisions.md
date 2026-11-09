# Topolina — confirmed product decisions

This document supersedes the original offline-only brief where they differ.

- Android Flutter app, distributed as an APK, initially used on one device.
- Internet is required. Supabase hosts PostgreSQL, authentication and backend logic. No SQLite, Drift, offline write queue or synchronization engine.
- Admin enters the Petpooja sales total manually. Collections are entered **after expenses**. Never try to reconstruct or change those figures.
- Reconciliation: expected sales minus (entered net collections + actual payments on that business date).
- Admin and waiter expenses share one ledger. Created-by attribution distinguishes submissions; no second admin copy or approval step.
- Waiters can select every active category, including Salary. This does not grant access to staff payroll records. Linking an existing Salary expense to payroll must reuse it, rather than create a second expense/payment.
- Business dates are calendar dates in Asia/Kolkata, midnight to midnight. Between midnight and 01:00, the previous date remains available for expense entry/editing and ordinary day closing. New entries default to the current calendar date; the previous date is an explicit selection.
- The grace window ends exactly at 01:00. Backend time, rather than phone time, authorizes writes.
- Closed days are locked even during the grace window. An admin can explicitly reopen a historical day with a reason, then correct/reclose it. This preserves the original requirement for audited historical corrections.
- An admin may close a day with a difference, with a mandatory explanation for a nonzero difference.
- The passage of 01:00 does not automatically mark an unfinished day closed or balanced. It ends the ordinary edit/close window; recovery requires an audited admin reopen.
- Monetary values use integer paise. Quantity/rate multiplication uses exact decimal arithmetic and rounds once, half up, to the nearest paise.
- Category labels use readable capitalized words and expanded names: Vegetables and Staff Welfare Expense. Every category has an icon, selectable by admin; unknown future icon keys fall back safely.
- The affected Wi-Fi resolver is handled by a Google DNS-over-HTTPS fallback only when normal lookup of the configured Supabase host fails. TLS certificate and original-hostname validation stay enabled.
- Supabase Auth handles passwords. There are no plaintext passwords or privileged Supabase keys in the APK. Email/password is the initial login method; a local PIN is not a replacement for backend authentication.

## Navigation

Admin: Overview, Expenses, Day end, More. More contains Sales, Credit ledger,
Masters (categories/items/vendors), Staff/payroll, Reports, Users/permissions,
Backups and Audit history.

Waiter: My day, Expenses and More, with Add expense available by permission.
Available category/item/vendor data is shared;
financial history is limited to that user's entries on currently eligible dates.

## Delivery stages

1. Foundation: Flutter Android shell, theme, router, Supabase configuration,
   login/session/profile boundary, initial SQL schema/migrations, category seeds,
   secure first-admin provisioning and financial/date-policy unit tests.
2. User and master-data management with backend permission tests.
3. Daily sales and shared expense entry, payments and credit ledger.
4. Payroll, reconciliation, closing/reopening and audit review.
5. Reports, operational backups/recovery and signed production APK.

Each stage must pass analysis and relevant tests before the next stage. A runnable
foundation is not represented as a finished financial product.
