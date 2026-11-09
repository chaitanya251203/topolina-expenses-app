# Topolina functionality guide

Release 1.0.0. Prepared 9 November 2026.

## Topolina functionality guide

Application workflows for administrators and waiters

Version 1.0.0  |  9 November 2026

Topolina records the cafe’s sales, expenses, vendor dues and salary payments in one Supabase-backed ledger. This guide explains who can do each task, where to find it, how records move through the app, and which dates affect the accounts. Internet access is required to load and save app data.

### The central accounting rule

A purchase and a payment are separate records. An unpaid purchase creates an outstanding amount. Only money actually paid contributes to the payment date’s daily reconciliation. Admin and waiter expenses share the same ledger.

### What each dashboard shows

Admin Overview shows day status, expected sales, net collections, paid expenses, outstanding credit and monthly sales, incurred expenses and payments. Waiter My day shows that waiter’s expense count, incurred amount and paid amount. Quick actions open the allowed workflows.

### Find the workflow you need

| Topic | Guide page |
|---|---|
| Access roles and navigation | 2 |
| Shared expenses and payment status | 3 |
| Vendor credit and shareable statements | 4 |
| Staff and monthly salaries | 5 |
| Sales collections and reconciliation | 6 |
| Business dates closing and reopening | 7 |
| Corrections voids and audit history | 8 |
| Masters users and permissions | 9 |
| Reports charts and CSV export | 10 |
| Backup export and restore | 11 |
| Daily routine and date examples | 12 |

Use the companion functionality flow map for the visual routes. Its four pages cover access, transaction flows, day closing and corrections, and administration and recovery.

## Access roles and navigation

### Sign in and account access

Open Topolina, enter your email and password, and sign in. Supabase verifies the session and the app checks the account’s live profile. An active, provisioned account opens its role’s workspace. Retry a connection failure or incorrect password. Inactive or unprovisioned accounts cannot access cafe data.

Email and password → Active account check → Role workspace

### Who can do what

| Function | Waiter | Admin |
|---|---|---|
| Add expenses in any active category | If entry permission is enabled | Yes |
| View expenses and payment history | Own entries on eligible dates, if permitted | All entries and history |
| Record later credit payments | No | Yes |
| Manage staff and linked salaries | No | Yes |
| Enter sales and close or reopen days | No | Yes |
| Correct or void financial entries | No | Yes |
| Manage categories items and vendors | Browse active choices | Add edit deactivate |
| Create accounts and manage waiter permissions | No | Yes |
| Reports backups and audit history | No | Yes |
| Browse categories change own password sign out | Yes | Yes |

### Workspace navigation

Admin: Overview, Expenses, Day end and More. More contains Staff & salaries, Reports & export, App users & permissions, Backups & restore, Audit history, Categories, vendors & items, Sales & collections and Credit ledger.

Waiter: My day, Expenses and More. My day shows the waiter’s own entered amounts. More provides category browsing, password change and sign out. Admin has all waiter functions as well.

## Shared expenses and payment status

Start: Overview or My day → Add expense, or Expenses → Add expense.

1. Choose the eligible business date. The form defaults to the current calendar date in India.
2. Select an active category. Every active category is available to waiters, including Salary. Select an item and vendor when applicable, and enter a description.
3. Enter a manual rupee amount, or enter quantity, unit and rate. The app calculates quantity × rate and rounds once to paise.
4. Choose Paid, Partially paid or Outstanding. Enter the actual amount paid and Cash, Bank / online or Other when money has been paid.
5. Add notes if needed, save, then review the entry and its payment history. Admin sees the same entry with its creator attribution.

### What saving creates

| Choice | Purchase record | Payment record and remaining balance |
|---|---|---|
| Paid | Full expense amount | Full amount paid on the selected business date; balance zero |
| Partially paid | Full expense amount | Only the entered paid amount is a payment; the remainder is outstanding |
| Outstanding on credit | Full expense amount | No payment is created; the full amount remains outstanding |

One expense → Zero or more payments → Derived paid and pending

### Checks before a financial entry is accepted

The backend checks the active account, permission, business date, day state, selected masters, positive amount and payment limits. An immediate payment cannot exceed the expense. Later payment dates cannot precede the purchase date. Closed or expired dates require admin reopening.

If saving fails because of a connection problem, keep the form and retry the unchanged entry. Expense and payment retries from the same form are protected against duplicate submissions.

## Vendor credit and shareable statements

Start: Overview → Credit payments, or More → Credit ledger. Admin only.

### Settle an outstanding purchase

1. Review the total outstanding credit, credit payments this month and vendor groups. Purchases without a vendor appear in a separate group.
2. Open a purchase to review its original amount, purchase date, paid amount, remaining balance and payment history.
3. Choose Record payment. Enter the full balance or a partial amount, the actual payment date, payment mode and optional notes.
4. Save. The purchase remains one record; a new payment is added. The balance and the selected payment date’s accounts update. Repeat later if a balance remains.

Original purchase → Add dated payment → Reduce pending balance

Payment amounts cannot exceed the balance. An older payment date must be open through an explicit admin reopen when its ordinary cutoff has passed. Linked payroll obligations are handled in Staff & salaries rather than this credit ledger.

### Share a vendor payment statement

1. Under the vendor’s name, choose Share payment statement. An expense needs an assigned vendor for this route.
2. The app fetches a fresh statement for that vendor’s pending purchases and verifies the totals.
3. Preview the PDF, then save a copy, print, or use Android’s share menu to choose WhatsApp, email or another installed app.

The PDF includes the Topolina logo, vendor name and entered contact/address, a reference, preparation time, original purchase dates and amounts, recorded payment dates and modes, paid amounts and the remaining payable balance. Settled purchases, other vendors, internal notes and linked payroll details are excluded.

Sharing records no payment and sends nothing automatically. The dates shown are purchase dates and payments already recorded. Regenerate the statement after ledger changes to obtain a fresh balance.

## Staff and monthly salaries

Start: More → Staff & salaries. Admin only. Staff members and app login accounts are separate.

### Maintain staff records

In Staff members, add or edit the staff ID, full name, designation, joining date, contact number, optional monthly salary and active status. Inactive staff retain historical records. Add an active staff member before creating a new monthly salary record.

### Create or link a salary record

1. In Salaries, choose the month, Add salary record and the staff member.
2. Choose Create unpaid salary to enter the amount, expense date, category and optional notes. This creates an unpaid obligation.
3. Alternatively choose Link existing expense, find the already entered expense by its date and select it. Its original date, amount, category and payments are reused.
4. Confirm the salary month. One active salary record is allowed for each staff member and month.

Create or link obligation → Pay full or partial amount → Review salary history

### Record actual salary payments

Use Record payment on the salary record, choose the actual payment date and mode, and enter an amount up to the remaining balance. Each partial payment remains in history. The monthly view shows paid and pending amounts. Existing dues can still be paid after a staff member becomes inactive.

| Date concept | Meaning |
|---|---|
| Salary month | The month the obligation is for |
| Expense date | The business date assigned to the salary expense |
| Payment date | The actual dated payment that contributes to daily paid expenses |

An unpaid salary does not increase daily paid expenses. Linking a waiter-entered Salary expense does not duplicate it and does not reveal private staff/payroll records to the waiter.

## Sales collections and reconciliation

Start: More → Sales & collections, or the Overview quick action. Admin only.

1. Select the business date. Enter expected sales manually from the Petpooja total.
2. Enter the net collections after expenses, separated into Cash, Bank / online and Other. The app uses the amounts you enter.
3. Save, then open Day end. The app totals actual expense, credit and salary payments dated to that business date.
4. Review the contributing payment entries and the calculated difference before closing.

### The reconciliation calculation

Total accounted = net collections + expenses actually paid
Difference = expected sales − total accounted

| Result | Meaning | Closing requirement |
|---|---|---|
| Difference = ₹0 | Balanced | Review and close |
| Difference > ₹0 | Short | Enter an explanation before closing |
| Difference < ₹0 | Excess | Enter an explanation before closing |

### Illustrative balanced day

| Entered or calculated amount | Example |
|---|---|
| Expected sales | ₹10,000.00 |
| Cash collected | ₹5,000.00 |
| Bank / online collected | ₹3,500.00 |
| Other collected | ₹500.00 |
| Actual expense payments | ₹1,000.00 |
| Total accounted | ₹10,000.00 |
| Difference | ₹0.00 |

An unpaid vendor purchase or unpaid salary contributes zero to paid expenses. A payment against an older purchase contributes on the payment date. The Day end screen derives its figures from individual payments rather than a manually entered expense total.

## Business dates closing and reopening

### Date and cutoff rules

All business dates use Asia/Kolkata. A calendar day runs from midnight to the next midnight. The previous date remains available until just before 1 a.m. the next day; it is an explicit date selection. New entries default to the current calendar date.

| Time in India | Ordinary behavior |
|---|---|
| During the calendar day | Current date is eligible if it is not closed |
| Next day 00:00 to 00:59:59 | Current and previous dates are eligible; choose the previous date explicitly |
| Exactly 01:00 onward | The previous date’s ordinary entry and closing window has ended |
| A date already closed | Financial changes remain blocked even during the grace window |

### Close the business day

1. In Day end, select the date and review sales, all collection modes, paid expense contributors, outstanding purchases and the difference.
2. Enter sales first if they are missing. Add a reason when the difference is short or excess.
3. Choose Close day. The app stores the closing snapshot, actor and time, and locks ordinary financial changes for that date.

Review entered accounts → Close and lock date → Reopen only with reason

### Recover or correct an older day

An admin can explicitly reopen a closed date or a missed historical date with a mandatory reason. Make the permitted corrections, review the updated accounts and close again. Reopening preserves earlier closing snapshots and audit history.

The 1 a.m. cutoff does not automatically close an unfinished day or mark it balanced. Backend time authorizes writes. Reopening a historical date does not extend a waiter’s normal eligible-date window.

## Corrections voids and audit history

Open Expense details as admin. Use Audit history in More to review recorded changes.

| Action | Flow and checks |
|---|---|
| Correct expense | Open details → Correct expense → adjust description, amount, category, vendor or notes → enter reason → save. Amount cannot fall below active payments. |
| Change calculated amount | A corrected amount switches the expense to a manual amount. The original values remain in audit history. |
| Void payment | Open payment history → Void payment → enter reason → confirm. Its payment date must be writable; the balance and that date’s paid total update. |
| Void expense | Open details → Void expense → reason → confirm. All active payments must be voided first. A linked salary record is also voided. |
| Correct a wrong business date | The correction form keeps the date unchanged. Void the active payments and expense with reasons, then reenter on the correct writable dates. |

### Apply the day rules to every affected date

Reopen the original purchase date for an expense correction or void when necessary. A payment void uses its own payment date, which can differ from the purchase date. Several payment dates may therefore need separate reopening. A void keeps the original record in history while excluding it from current accounting totals.

Open affected date → Correct or void with reason → Review totals and audit

### Review the audit trail

More → Audit history lists the actor, operation, table and time. Expand a record to inspect original and changed values, including correction or void reasons. Load more to inspect older events. Master changes, permissions, financial entries and closing/reopening events retain their audit records.

Corrections update the shared ledger, so dashboards, dues and reports follow the corrected underlying records. Refresh an already open screen or regenerate a vendor statement after changes.

## Masters users and permissions

### Categories items and vendors

Start: More → Categories, vendors & items. Admin can add, edit or deactivate each type.

| Master | Managed data | Effect |
|---|---|---|
| Category | Readable name, icon and active status | Controls available category choices and their appearance |
| Item | Name, category, unit, optional rate and active status | Supplies defaults for expense entry |
| Vendor | Name, contact, address, notes and active status | Links purchases, credit groups and vendor statements |

Deactivation removes an option from new entry choices and preserves historical references. Browse expense categories is available to both roles. Category and vendor expense summaries are available in Reports.

### Create or manage an app account

Start: More → App users & permissions. Choose Create waiter account, enter the name, email and temporary password, then save. The waiter can sign in and change the password through More. A staff salary record does not automatically create a login.

For a waiter account, Edit account changes the name or active status. Reset password sets a new password. Deactivation blocks backend data access even for an already signed-in account. Admin accounts are not edited or promoted through this waiter-management screen.

### Waiter permissions

The two switches apply to every waiter: Enter expenses and View own current-day expenses. These permissions are enforced on the backend as well as in the interface. They do not grant access to payroll, sales, reports, backups or administration.

### Personal password and sign out

In More, choose Change your password, verify the current password, enter and confirm the new password, and save. Sign out ends the app session; signing back in checks the profile and role again.

## Reports charts and CSV export

Start: More → Reports & export, or Overview → Reports. Admin only. The initial report covers the current month through today.

1. Choose Dates & filters. Select a day or date range, category, vendor, staff member, payment mode and payment status as needed. The supported range is up to 367 days, ending today or earlier.
2. Review sales and collection totals, expenses incurred, actual payments, outstanding at the end date and linked salary payments.
3. Inspect the daily payment chart, category/vendor summaries and daily reconciliation history. Select a daily record to open its Day end view.
4. Choose Export CSV and select a location through the phone’s file picker.

### Read the date bases correctly

| Figure | Date basis |
|---|---|
| Expenses incurred | Purchase or expense dates within the selected range |
| Expenses paid | Actual payment dates within the selected range, including older purchases |
| Outstanding at end date | All included purchases through the end date minus payments recorded through that date |
| Payment status | The balance as of the report end date |
| Linked salary payments | Actual payments attached to staff-linked salary obligations |

Expense filters apply to expense sections. Sales and daily reconciliation still show the complete selected dates; sales are not allocated to a category, vendor or staff member. Payment-mode filtering shows matching recorded payments and related purchases. Use All modes to include purchases that have no payment yet.

Choose dates and filters → Review dated totals → Export exact INR CSV

The CSV includes report totals, daily reconciliation, purchase records and payment records. It retains exact rupee amounts. Reports describe entered activity and reconciliation; they do not calculate a definitive accounting profit.

## Backup export and restore

Start: More → Backups & restore. Admin only. The screen shows the last successful backup and server snapshots.

### Create and keep a backup

Choose Create & download backup. The server first captures a coherent application snapshot, then Android offers a location to save a file. Existing server snapshots can also be downloaded. Keep downloaded financial files in a location you control.

Automatic backups can be enabled or disabled, set to daily or weekly, and configured to retain 2 to 60 snapshots. The default is daily with 14 snapshots. An hourly server worker checks whether the selected interval is due, so the app need not remain open.

### Restore from a file

1. Choose Restore from a backup file and select a Topolina backup.
2. The app and backend check the project identity, supported format/version, checksum and required data. The mobile limit is a 50 MiB payload within a 60 MiB file envelope.
3. Enter the restore reason, type RESTORE and verify the current admin password.
4. The backend creates a safety snapshot before replacing application records. It validates record relationships and payment totals in one transaction.
5. Success restores the selected ledger and makes the safety snapshot available. Failure rolls the whole restore back, leaving the previous ledger in place.

Validate file and approval → Capture safety snapshot → Atomic restore or rollback

Users, roles, passwords and audit history are preserved rather than replaced from the backup. The files cover application records, not the entire Supabase project or Auth service. A stale saved request from before restore cannot silently replay an old write; refresh the app after restore.

Reinstalling Topolina does not erase its hosted records. A full-project incident or data beyond the mobile restore limit requires operator recovery outside this app workflow.

## Daily routine and date examples

### Waiter routine

Sign in → confirm the date → add expenses as they happen → record only money actually paid → review your own eligible entries. Tell the admin when an entry needs correction. Select the previous date explicitly during the midnight grace window when appropriate.

### Admin routine

Review both admin and waiter entries → settle vendor or salary dues on their actual payment dates → enter expected sales and net collections → inspect Day end contributors and the difference → explain a discrepancy when needed → close the day. Use reports and backups to review and preserve the ledger.

### Illustrative credit purchase over several dates

| Business date | Recorded event | Paid that date | Balance after event |
|---|---|---|---|
| 8 November | Purchase ₹2,000 on credit | ₹0 | ₹2,000 |
| 12 November | First payment ₹1,000 | ₹1,000 | ₹1,000 |
| 15 November | Final payment ₹1,000 | ₹1,000 | ₹0 |

The purchase appears as incurred on 8 November. The two later payments contribute only on 12 and 15 November. A report ending on 12 November still shows ₹1,000 outstanding, even when the current ledger is later fully settled. These amounts are an example, not cafe records.

### Common recovery routes

| Situation | Next action |
|---|---|
| Connection or loading failed | Check the connection and refresh. Keep an unsaved form and retry it. |
| Account cannot access data | Ask the admin to check active status, provisioning and waiter permissions. |
| Date is closed or cutoff passed | Admin opens Day end and reopens the affected date with a reason. |
| Payment would exceed the balance | Refresh the purchase and enter no more than the remaining amount. |
| Vendor statement is out of date | Regenerate it after recording the latest payments. |
| Restore failed validation | Use a valid matching backup; the failed restore does not replace the ledger. |

Coverage is for the released Topolina 1.0.0 workflows. The deployed backend and automated flows were verified; native installation, file picking, printing and sharing should also be checked on the cafe’s physical phone.
