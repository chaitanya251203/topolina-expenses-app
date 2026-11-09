# Completion work

Release candidate: v1.0.0; 56 Flutter tests and 36 database/backend tests passed.

- [x] Staff and monthly payroll, partial payments, linking existing expenses.
- [x] Audited expense correction, payment/expense voiding, audit viewer.
- [x] Waiter accounts, backend permissions, password management.
- [x] Daily/monthly reports, filters, charts and export.
- [x] Server backups, validated export/restore, safety snapshots and automatic schedule.
- [x] Full regression, hosted rollback checks, visual review.
- [ ] Private release signing, final APK, GitHub push and handoff.

All 13 migrations and the authenticated account-management function are deployed.
Hosted financial fixtures were rolled back. Hosted temporary Auth accounts were
removed. Cron scheduling is active and a release safety snapshot was created.
No privileged keys are embedded in the APK. Production signing/build is the
remaining packaging step; physical phone acceptance follows delivery.

Added scope: vendor-wise shareable payment-statement PDFs with exact pending
balances, purchase and actual payment dates, preview, save/print/native share.
Backend isolation and amount checks passed. One-page and 14-page PDFs were
rendered and inspected, including all totals, dated payments and purchase rows.
The APK is being rebuilt to include statements.

Payroll uses the canonical expense/payment ledger. A salary month is separate
from the explicitly selected expense date and actual payment date. Linking a
waiter-entered Salary expense reuses that record and its existing payments.
