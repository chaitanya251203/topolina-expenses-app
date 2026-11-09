"""Build the released app's user guide and vector flow atlas. No live data used."""
from pathlib import Path
from html import escape
import textwrap
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, A3, landscape
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
                              PageBreak, KeepTogether, Flowable)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.lib.utils import simpleSplit, ImageReader

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output' / 'pdf'
OUT.mkdir(parents=True, exist_ok=True)
FONT = ROOT / 'assets' / 'fonts'
pdfmetrics.registerFont(TTFont('Roboto', str(FONT/'roboto-regular.ttf')))
pdfmetrics.registerFont(TTFont('RobotoBold', str(FONT/'roboto-bold.ttf')))
pdfmetrics.registerFontFamily('Roboto', normal='Roboto', bold='RobotoBold', italic='Roboto', boldItalic='RobotoBold')
INK = colors.HexColor('#18241F')
FOREST = colors.HexColor('#193F35')
CREAM = colors.HexColor('#F6F3EC')
GRAY = colors.HexColor('#D9D9D9')
MUTED = colors.HexColor('#5B665E')
GOLD = colors.HexColor('#F3DBAF')
LOGO = ImageReader(str(ROOT/'assets'/'brand'/'topolina-logo.png'))

# The prose and diagrams describe release 1.0.0, not proposed functionality.
PAGES = [
('Topolina functionality guide', [
('p', 'Application workflows for administrators and waiters'),
('p', '<b>Version 1.0.0  |  9 November 2026</b>'),
('p', 'Topolina records the cafe’s sales, expenses, vendor dues and salary payments in one Supabase-backed ledger. This guide explains who can do each task, where to find it, how records move through the app, and which dates affect the accounts. Internet access is required to load and save app data.'),
('h', 'The central accounting rule'),
('p', 'A purchase and a payment are separate records. An unpaid purchase creates an outstanding amount. Only money actually paid contributes to the payment date’s daily reconciliation. Admin and waiter expenses share the same ledger.'),
('h', 'What each dashboard shows'),
('p', 'Admin Overview shows day status, expected sales, net collections, paid expenses, outstanding credit and monthly sales, incurred expenses and payments. Waiter My day shows that waiter’s expense count, incurred amount and paid amount. Quick actions open the allowed workflows.'),
('h', 'Find the workflow you need'),
('table', (['Topic', 'Guide page'], [
['Access roles and navigation','2'],['Shared expenses and payment status','3'],
['Vendor credit and shareable statements','4'],['Staff and monthly salaries','5'],
['Sales collections and reconciliation','6'],['Business dates closing and reopening','7'],
['Corrections voids and audit history','8'],['Masters users and permissions','9'],
['Reports charts and CSV export','10'],['Backup export and restore','11'],['Daily routine and date examples','12']], [365,108])),
('p', 'Use the companion functionality flow map for the visual routes. Its four pages cover access, transaction flows, day closing and corrections, and administration and recovery.'),
]),
('Access roles and navigation', [
('h', 'Sign in and account access'),
('p', 'Open Topolina, enter your email and password, and sign in. Supabase verifies the session and the app checks the account’s live profile. An active, provisioned account opens its role’s workspace. Retry a connection failure or incorrect password. Inactive or unprovisioned accounts cannot access cafe data.'),
('flow', ['Email and password', 'Active account check', 'Role workspace']),
('h', 'Who can do what'),
('table', (['Function', 'Waiter', 'Admin'], [
['Add expenses in any active category','If entry permission is enabled','Yes'],
['View expenses and payment history','Own entries on eligible dates, if permitted','All entries and history'],
['Record later credit payments','No','Yes'],['Manage staff and linked salaries','No','Yes'],
['Enter sales and close or reopen days','No','Yes'],['Correct or void financial entries','No','Yes'],
['Manage categories items and vendors','Browse active choices','Add edit deactivate'],
['Create accounts and manage waiter permissions','No','Yes'],['Reports backups and audit history','No','Yes'],
['Browse categories change own password sign out','Yes','Yes']], [205,132,136])),
('h', 'Workspace navigation'),
('p', '<b>Admin:</b> Overview, Expenses, Day end and More. More contains Staff &amp; salaries, Reports &amp; export, App users &amp; permissions, Backups &amp; restore, Audit history, Categories, vendors &amp; items, Sales &amp; collections and Credit ledger.'),
('p', '<b>Waiter:</b> My day, Expenses and More. My day shows the waiter’s own entered amounts. More provides category browsing, password change and sign out. Admin has all waiter functions as well.'),
]),
('Shared expenses and payment status', [
('p', '<b>Start:</b> Overview or My day → Add expense, or Expenses → Add expense.'),
('steps', [
'Choose the eligible business date. The form defaults to the current calendar date in India.',
'Select an active category. Every active category is available to waiters, including Salary. Select an item and vendor when applicable, and enter a description.',
'Enter a manual rupee amount, or enter quantity, unit and rate. The app calculates quantity × rate and rounds once to paise.',
'Choose Paid, Partially paid or Outstanding. Enter the actual amount paid and Cash, Bank / online or Other when money has been paid.',
'Add notes if needed, save, then review the entry and its payment history. Admin sees the same entry with its creator attribution.' ]),
('h', 'What saving creates'),
('table', (['Choice', 'Purchase record', 'Payment record and remaining balance'], [
['Paid','Full expense amount','Full amount paid on the selected business date; balance zero'],
['Partially paid','Full expense amount','Only the entered paid amount is a payment; the remainder is outstanding'],
['Outstanding on credit','Full expense amount','No payment is created; the full amount remains outstanding']], [104,120,249])),
('flow', ['One expense', 'Zero or more payments', 'Derived paid and pending']),
('h', 'Checks before a financial entry is accepted'),
('p', 'The backend checks the active account, permission, business date, day state, selected masters, positive amount and payment limits. An immediate payment cannot exceed the expense. Later payment dates cannot precede the purchase date. Closed or expired dates require admin reopening.'),
('p', 'If saving fails because of a connection problem, keep the form and retry the unchanged entry. Expense and payment retries from the same form are protected against duplicate submissions.'),
]),
('Vendor credit and shareable statements', [
('p', '<b>Start:</b> Overview → Credit payments, or More → Credit ledger. Admin only.'),
('h', 'Settle an outstanding purchase'),
('steps', [
'Review the total outstanding credit, credit payments this month and vendor groups. Purchases without a vendor appear in a separate group.',
'Open a purchase to review its original amount, purchase date, paid amount, remaining balance and payment history.',
'Choose Record payment. Enter the full balance or a partial amount, the actual payment date, payment mode and optional notes.',
'Save. The purchase remains one record; a new payment is added. The balance and the selected payment date’s accounts update. Repeat later if a balance remains.' ]),
('flow', ['Original purchase', 'Add dated payment', 'Reduce pending balance']),
('p', 'Payment amounts cannot exceed the balance. An older payment date must be open through an explicit admin reopen when its ordinary cutoff has passed. Linked payroll obligations are handled in Staff &amp; salaries rather than this credit ledger.'),
('h', 'Share a vendor payment statement'),
('steps', [
'Under the vendor’s name, choose Share payment statement. An expense needs an assigned vendor for this route.',
'The app fetches a fresh statement for that vendor’s pending purchases and verifies the totals.',
'Preview the PDF, then save a copy, print, or use Android’s share menu to choose WhatsApp, email or another installed app.' ]),
('p', 'The PDF includes the Topolina logo, vendor name and entered contact/address, a reference, preparation time, original purchase dates and amounts, recorded payment dates and modes, paid amounts and the remaining payable balance. Settled purchases, other vendors, internal notes and linked payroll details are excluded.'),
('p', 'Sharing records no payment and sends nothing automatically. The dates shown are purchase dates and payments already recorded. Regenerate the statement after ledger changes to obtain a fresh balance.'),
]),
('Staff and monthly salaries', [
('p', '<b>Start:</b> More → Staff &amp; salaries. Admin only. Staff members and app login accounts are separate.'),
('h', 'Maintain staff records'),
('p', 'In Staff members, add or edit the staff ID, full name, designation, joining date, contact number, optional monthly salary and active status. Inactive staff retain historical records. Add an active staff member before creating a new monthly salary record.'),
('h', 'Create or link a salary record'),
('steps', [
'In Salaries, choose the month, Add salary record and the staff member.',
'Choose Create unpaid salary to enter the amount, expense date, category and optional notes. This creates an unpaid obligation.',
'Alternatively choose Link existing expense, find the already entered expense by its date and select it. Its original date, amount, category and payments are reused.',
'Confirm the salary month. One active salary record is allowed for each staff member and month.' ]),
('flow', ['Create or link obligation', 'Pay full or partial amount', 'Review salary history']),
('h', 'Record actual salary payments'),
('p', 'Use Record payment on the salary record, choose the actual payment date and mode, and enter an amount up to the remaining balance. Each partial payment remains in history. The monthly view shows paid and pending amounts. Existing dues can still be paid after a staff member becomes inactive.'),
('table', (['Date concept', 'Meaning'], [
['Salary month','The month the obligation is for'],['Expense date','The business date assigned to the salary expense'],['Payment date','The actual dated payment that contributes to daily paid expenses']], [132,341])),
('p', 'An unpaid salary does not increase daily paid expenses. Linking a waiter-entered Salary expense does not duplicate it and does not reveal private staff/payroll records to the waiter.'),
]),
('Sales collections and reconciliation', [
('p', '<b>Start:</b> More → Sales &amp; collections, or the Overview quick action. Admin only.'),
('steps', [
'Select the business date. Enter expected sales manually from the Petpooja total.',
'Enter the net collections after expenses, separated into Cash, Bank / online and Other. The app uses the amounts you enter.',
'Save, then open Day end. The app totals actual expense, credit and salary payments dated to that business date.',
'Review the contributing payment entries and the calculated difference before closing.' ]),
('h', 'The reconciliation calculation'),
('p', '<b>Total accounted = net collections + expenses actually paid</b><br/><b>Difference = expected sales − total accounted</b>'),
('table', (['Result', 'Meaning', 'Closing requirement'], [
['Difference = ₹0','Balanced','Review and close'],['Difference &gt; ₹0','Short','Enter an explanation before closing'],['Difference &lt; ₹0','Excess','Enter an explanation before closing']], [130,110,233])),
('h', 'Illustrative balanced day'),
('table', (['Entered or calculated amount', 'Example'], [
['Expected sales','₹10,000.00'],['Cash collected','₹5,000.00'],['Bank / online collected','₹3,500.00'],['Other collected','₹500.00'],['Actual expense payments','₹1,000.00'],['Total accounted','₹10,000.00'],['Difference','₹0.00']], [326,147])),
('p', 'An unpaid vendor purchase or unpaid salary contributes zero to paid expenses. A payment against an older purchase contributes on the payment date. The Day end screen derives its figures from individual payments rather than a manually entered expense total.'),
]),
('Business dates closing and reopening', [
('h', 'Date and cutoff rules'),
('p', 'All business dates use Asia/Kolkata. A calendar day runs from midnight to the next midnight. The previous date remains available until just before 1 a.m. the next day; it is an explicit date selection. New entries default to the current calendar date.'),
('table', (['Time in India', 'Ordinary behavior'], [
['During the calendar day','Current date is eligible if it is not closed'],['Next day 00:00 to 00:59:59','Current and previous dates are eligible; choose the previous date explicitly'],['Exactly 01:00 onward','The previous date’s ordinary entry and closing window has ended'],['A date already closed','Financial changes remain blocked even during the grace window']], [173,300])),
('h', 'Close the business day'),
('steps', [
'In Day end, select the date and review sales, all collection modes, paid expense contributors, outstanding purchases and the difference.',
'Enter sales first if they are missing. Add a reason when the difference is short or excess.',
'Choose Close day. The app stores the closing snapshot, actor and time, and locks ordinary financial changes for that date.' ]),
('flow', ['Review entered accounts', 'Close and lock date', 'Reopen only with reason']),
('h', 'Recover or correct an older day'),
('p', 'An admin can explicitly reopen a closed date or a missed historical date with a mandatory reason. Make the permitted corrections, review the updated accounts and close again. Reopening preserves earlier closing snapshots and audit history.'),
('p', 'The 1 a.m. cutoff does not automatically close an unfinished day or mark it balanced. Backend time authorizes writes. Reopening a historical date does not extend a waiter’s normal eligible-date window.'),
]),
('Corrections voids and audit history', [
('p', 'Open Expense details as admin. Use Audit history in More to review recorded changes.'),
('table', (['Action', 'Flow and checks'], [
['Correct expense','Open details → Correct expense → adjust description, amount, category, vendor or notes → enter reason → save. Amount cannot fall below active payments.'],
['Change calculated amount','A corrected amount switches the expense to a manual amount. The original values remain in audit history.'],
['Void payment','Open payment history → Void payment → enter reason → confirm. Its payment date must be writable; the balance and that date’s paid total update.'],
['Void expense','Open details → Void expense → reason → confirm. All active payments must be voided first. A linked salary record is also voided.'],
['Correct a wrong business date','The correction form keeps the date unchanged. Void the active payments and expense with reasons, then reenter on the correct writable dates.']], [145,328])),
('h', 'Apply the day rules to every affected date'),
('p', 'Reopen the original purchase date for an expense correction or void when necessary. A payment void uses its own payment date, which can differ from the purchase date. Several payment dates may therefore need separate reopening. A void keeps the original record in history while excluding it from current accounting totals.'),
('flow', ['Open affected date', 'Correct or void with reason', 'Review totals and audit']),
('h', 'Review the audit trail'),
('p', 'More → Audit history lists the actor, operation, table and time. Expand a record to inspect original and changed values, including correction or void reasons. Load more to inspect older events. Master changes, permissions, financial entries and closing/reopening events retain their audit records.'),
('p', 'Corrections update the shared ledger, so dashboards, dues and reports follow the corrected underlying records. Refresh an already open screen or regenerate a vendor statement after changes.'),
]),
('Masters users and permissions', [
('h', 'Categories items and vendors'),
('p', '<b>Start:</b> More → Categories, vendors &amp; items. Admin can add, edit or deactivate each type.'),
('table', (['Master', 'Managed data', 'Effect'], [
['Category','Readable name, icon and active status','Controls available category choices and their appearance'],
['Item','Name, category, unit, optional rate and active status','Supplies defaults for expense entry'],
['Vendor','Name, contact, address, notes and active status','Links purchases, credit groups and vendor statements']], [80,203,190])),
('p', 'Deactivation removes an option from new entry choices and preserves historical references. Browse expense categories is available to both roles. Category and vendor expense summaries are available in Reports.'),
('h', 'Create or manage an app account'),
('p', '<b>Start:</b> More → App users &amp; permissions. Choose Create waiter account, enter the name, email and temporary password, then save. The waiter can sign in and change the password through More. A staff salary record does not automatically create a login.'),
('p', 'For a waiter account, Edit account changes the name or active status. Reset password sets a new password. Deactivation blocks backend data access even for an already signed-in account. Admin accounts are not edited or promoted through this waiter-management screen.'),
('h', 'Waiter permissions'),
('p', 'The two switches apply to every waiter: Enter expenses and View own current-day expenses. These permissions are enforced on the backend as well as in the interface. They do not grant access to payroll, sales, reports, backups or administration.'),
('h', 'Personal password and sign out'),
('p', 'In More, choose Change your password, verify the current password, enter and confirm the new password, and save. Sign out ends the app session; signing back in checks the profile and role again.'),
]),
('Reports charts and CSV export', [
('p', '<b>Start:</b> More → Reports &amp; export, or Overview → Reports. Admin only. The initial report covers the current month through today.'),
('steps', [
'Choose Dates & filters. Select a day or date range, category, vendor, staff member, payment mode and payment status as needed. The supported range is up to 367 days, ending today or earlier.',
'Review sales and collection totals, expenses incurred, actual payments, outstanding at the end date and linked salary payments.',
'Inspect the daily payment chart, category/vendor summaries and daily reconciliation history. Select a daily record to open its Day end view.',
'Choose Export CSV and select a location through the phone’s file picker.' ]),
('h', 'Read the date bases correctly'),
('table', (['Figure', 'Date basis'], [
['Expenses incurred','Purchase or expense dates within the selected range'],['Expenses paid','Actual payment dates within the selected range, including older purchases'],['Outstanding at end date','All included purchases through the end date minus payments recorded through that date'],['Payment status','The balance as of the report end date'],['Linked salary payments','Actual payments attached to staff-linked salary obligations']], [158,315])),
('p', 'Expense filters apply to expense sections. Sales and daily reconciliation still show the complete selected dates; sales are not allocated to a category, vendor or staff member. Payment-mode filtering shows matching recorded payments and related purchases. Use All modes to include purchases that have no payment yet.'),
('flow', ['Choose dates and filters', 'Review dated totals', 'Export exact INR CSV']),
('p', 'The CSV includes report totals, daily reconciliation, purchase records and payment records. It retains exact rupee amounts. Reports describe entered activity and reconciliation; they do not calculate a definitive accounting profit.'),
]),
('Backup export and restore', [
('p', '<b>Start:</b> More → Backups &amp; restore. Admin only. The screen shows the last successful backup and server snapshots.'),
('h', 'Create and keep a backup'),
('p', 'Choose Create &amp; download backup. The server first captures a coherent application snapshot, then Android offers a location to save a file. Existing server snapshots can also be downloaded. Keep downloaded financial files in a location you control.'),
('p', 'Automatic backups can be enabled or disabled, set to daily or weekly, and configured to retain 2 to 60 snapshots. The default is daily with 14 snapshots. An hourly server worker checks whether the selected interval is due, so the app need not remain open.'),
('h', 'Restore from a file'),
('steps', [
'Choose Restore from a backup file and select a Topolina backup.',
'The app and backend check the project identity, supported format/version, checksum and required data. The mobile limit is a 50 MiB payload within a 60 MiB file envelope.',
'Enter the restore reason, type RESTORE and verify the current admin password.',
'The backend creates a safety snapshot before replacing application records. It validates record relationships and payment totals in one transaction.',
'Success restores the selected ledger and makes the safety snapshot available. Failure rolls the whole restore back, leaving the previous ledger in place.' ]),
('flow', ['Validate file and approval', 'Capture safety snapshot', 'Atomic restore or rollback']),
('p', 'Users, roles, passwords and audit history are preserved rather than replaced from the backup. The files cover application records, not the entire Supabase project or Auth service. A stale saved request from before restore cannot silently replay an old write; refresh the app after restore.'),
('p', 'Reinstalling Topolina does not erase its hosted records. A full-project incident or data beyond the mobile restore limit requires operator recovery outside this app workflow.'),
]),
('Daily routine and date examples', [
('h', 'Waiter routine'),
('p', 'Sign in → confirm the date → add expenses as they happen → record only money actually paid → review your own eligible entries. Tell the admin when an entry needs correction. Select the previous date explicitly during the midnight grace window when appropriate.'),
('h', 'Admin routine'),
('p', 'Review both admin and waiter entries → settle vendor or salary dues on their actual payment dates → enter expected sales and net collections → inspect Day end contributors and the difference → explain a discrepancy when needed → close the day. Use reports and backups to review and preserve the ledger.'),
('h', 'Illustrative credit purchase over several dates'),
('table', (['Business date', 'Recorded event', 'Paid that date', 'Balance after event'], [
['8 November','Purchase ₹2,000 on credit','₹0','₹2,000'],['12 November','First payment ₹1,000','₹1,000','₹1,000'],['15 November','Final payment ₹1,000','₹1,000','₹0']], [95,169,100,109])),
('p', 'The purchase appears as incurred on 8 November. The two later payments contribute only on 12 and 15 November. A report ending on 12 November still shows ₹1,000 outstanding, even when the current ledger is later fully settled. These amounts are an example, not cafe records.'),
('h', 'Common recovery routes'),
('table', (['Situation', 'Next action'], [
['Connection or loading failed','Check the connection and refresh. Keep an unsaved form and retry it.'],['Account cannot access data','Ask the admin to check active status, provisioning and waiter permissions.'],['Date is closed or cutoff passed','Admin opens Day end and reopens the affected date with a reason.'],['Payment would exceed the balance','Refresh the purchase and enter no more than the remaining amount.'],['Vendor statement is out of date','Regenerate it after recording the latest payments.'],['Restore failed validation','Use a valid matching backup; the failed restore does not replace the ledger.']], [170,303])),
('p', 'Coverage is for the released Topolina 1.0.0 workflows. The deployed backend and automated flows were verified; native installation, file picking, printing and sharing should also be checked on the cafe’s physical phone.'),
]),
]

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name='TopTitle', fontName='RobotoBold', fontSize=24, leading=29, textColor=colors.black, spaceAfter=14))
styles.add(ParagraphStyle(name='TopH', fontName='RobotoBold', fontSize=13, leading=17, textColor=colors.black, spaceBefore=12, spaceAfter=7, keepWithNext=True))
styles.add(ParagraphStyle(name='TopBody', fontName='Roboto', fontSize=10.6, leading=14.8, textColor=INK, spaceAfter=8))
styles.add(ParagraphStyle(name='TopCell', fontName='Roboto', fontSize=9.1, leading=12.2, textColor=INK))
styles.add(ParagraphStyle(name='TopCellHead', parent=styles['TopCell'], fontName='RobotoBold', textColor=colors.white))
styles.add(ParagraphStyle(name='TopAmount', parent=styles['TopCell'], alignment=2))
styles.add(ParagraphStyle(name='TopPage', parent=styles['TopCell'], alignment=1))
styles.add(ParagraphStyle(name='TopStep', parent=styles['TopBody'], leftIndent=17, firstLineIndent=-17, spaceAfter=6))

def rounded(c,x,y,w,h,text,fill=CREAM,size=11,bold=False,stroke=None):
    c.setFillColor(fill)
    if stroke: c.setStrokeColor(stroke)
    c.roundRect(x,y,w,h,8,stroke=bool(stroke),fill=1)
    font='RobotoBold' if bold else 'Roboto'
    c.setFont(font,size)
    c.setFillColor(colors.white if fill==FOREST else INK)
    lines=[]
    for part in text.split('\n'):
        lines+=simpleSplit(part,font,size,w-20)
    leading=size*1.28
    if len(lines)*leading>h-10:
        raise ValueError(f'Node text too tall: {text} ({len(lines)} lines)')
    yy=y+h/2+(len(lines)-1)*leading/2-size*.35
    for line in lines:
        c.drawCentredString(x+w/2,yy,line); yy-=leading

def arrow(c, points, label=None):
    import math
    c.setStrokeColor(MUTED);c.setLineWidth(1.0)
    p=c.beginPath();p.moveTo(*points[0])
    for x,y in points[1:]:p.lineTo(x,y)
    c.drawPath(p)
    x,y=points[-1];prev=points[-2];a=math.atan2(y-prev[1],x-prev[0]);s=5
    q=c.beginPath();q.moveTo(x,y);q.lineTo(x-s*math.cos(a-.48),y-s*math.sin(a-.48));q.lineTo(x-s*math.cos(a+.48),y-s*math.sin(a+.48));q.close()
    c.setFillColor(MUTED);c.drawPath(q,fill=1,stroke=0)
    if label:
        mx=(points[0][0]+points[1][0])/2;my=(points[0][1]+points[1][1])/2+6
        c.setFont('Roboto',9);c.drawCentredString(mx,my,label)

class MiniFlow(Flowable):
    def __init__(self,labels): Flowable.__init__(self);self.labels=labels;self.width=473;self.height=76
    def draw(self):
        w=145;gap=19
        for i,label in enumerate(self.labels):
            rounded(self.canv,i*(w+gap),8,w,58,label,size=10.1,fill=CREAM)
            if i<2:arrow(self.canv,[(i*(w+gap)+w,37),((i+1)*(w+gap)-3,37)])

def guide_footer(c,doc):
    c.setFont('Roboto',8);c.setFillColor(MUTED)
    c.drawString(54,26,'TOPOLINA 1.0.0  •  Functionality guide')
    c.drawRightString(A4[0]-54,26,f'{doc.page}')
    if doc.page==1:c.drawImage(LOGO,A4[0]-102,A4[1]-101,width=47,height=47,mask='auto',preserveAspectRatio=True)

def build_guide():
    def markup(value):
        return value.replace('<b>Start:</b>', 'Open from').replace('→', ' &gt; ').replace('−', '-')
    story=[]
    for index,(title,blocks) in enumerate(PAGES):
        if index:story.append(PageBreak())
        story.append(Paragraph(title,styles['TopTitle']))
        for kind,data in blocks:
            if kind=='p':story.append(Paragraph(markup(data),styles['TopBody']))
            elif kind=='h':story.append(Paragraph(data,styles['TopH']))
            elif kind=='flow':story.append(MiniFlow(data));story.append(Spacer(1,4))
            elif kind=='steps':
                for n,item in enumerate(data,1):story.append(Paragraph(f'<b>{n}.</b> {markup(escape(item))}',styles['TopStep']))
            elif kind=='table':
                heads,rows,widths=data
                cells=[[Paragraph(escape(str(x)),styles['TopCellHead']) for x in heads]]
                cells += [[Paragraph(markup(str(x)),styles['TopAmount'] if str(x).startswith('₹') else styles['TopPage'] if str(x).isdigit() else styles['TopCell']) for x in row] for row in rows]
                table=Table(cells,colWidths=widths,repeatRows=1,hAlign='LEFT')
                table.setStyle(TableStyle([
                    ('BACKGROUND',(0,0),(-1,0),colors.HexColor('#343D38')),
                    ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor('#F4F5F3')]),
                    ('GRID',(0,0),(-1,-1),.5,GRAY),('VALIGN',(0,0),(-1,-1),'MIDDLE'),
                    ('LEFTPADDING',(0,0),(-1,-1),9),('RIGHTPADDING',(0,0),(-1,-1),9),
                    ('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7)]))
                story.extend([Spacer(1,3),table,Spacer(1,10)])
    doc=SimpleDocTemplate(str(OUT/'Topolina_Functionality_Guide.pdf'),pagesize=A4,rightMargin=54,leftMargin=54,
                          topMargin=48,bottomMargin=48,title='Topolina functionality guide',author='Topolina')
    doc.build(story,onFirstPage=guide_footer,onLaterPages=guide_footer)

FLOW_ROWS = [
('Shared expense entry', ['Admin or permitted waiter\nAdd expense','Choose eligible date\nCategory item vendor description','Manual amount\nor quantity × rate','Paid full\nPartial amount\nor unpaid credit','One purchase and any\nimmediate payment','Shared ledger\nBalances and date totals update']),
('Vendor credit payment', ['Admin opens\nCredit ledger','Choose vendor and\noutstanding purchase','Choose actual payment\ndate and mode','Enter amount no more\nthan remaining balance','Add a separate\nfull or partial payment','Pending decreases\nPayment date totals update']),
('Staff and salary payment', ['Admin manages staff\nand selects salary month','Create unpaid salary\nor link existing expense','Reuse one expense\nand any existing payments','When money is paid\nRecord full or partial payment','Payment contributes\non its own date','Monthly paid pending\nand payment history']),
('Vendor payment statement', ['Admin selects vendor\nShare payment statement','Fresh snapshot of only\nthat vendor pending purchases','Validate original paid\nand pending totals','Branded PDF with\npurchase and payment dates','Preview and choose\nsave print or native share','User chooses action\nNo payment is recorded']),
]

def atlas_header(c,title,subtitle,page):
    w,h=landscape(A3)
    c.setFillColor(colors.white);c.rect(0,0,w,h,fill=1,stroke=0)
    c.drawImage(LOGO,40,h-89,width=47,height=47,mask='auto',preserveAspectRatio=True)
    c.setFont('RobotoBold',23);c.setFillColor(INK);c.drawString(102,h-60,title)
    c.setFont('Roboto',11);c.setFillColor(MUTED);c.drawString(102,h-80,subtitle)
    c.setFont('Roboto',9);c.drawString(40,25,'TOPOLINA 1.0.0  •  9 November 2026  •  All business dates use Asia/Kolkata')
    c.drawRightString(w-40,25,f'{page} / 4')

def flow_row(c,title,steps,y,note=None):
    c.setFillColor(INK);c.setFont('RobotoBold',14);c.drawString(40,y+80,title)
    n=len(steps);gap=20;w=(landscape(A3)[0]-80-gap*(n-1))/n;h=64
    for i,label in enumerate(steps):
        x=40+i*(w+gap);rounded(c,x,y,w,h,label,size=10.7,fill=FOREST if i==0 else CREAM,bold=i==0)
        if i<n-1:arrow(c,[(x+w,y+h/2),(x+w+gap-3,y+h/2)])
    if note:c.setFont('Roboto',10);c.setFillColor(MUTED);c.drawString(40,y-19,note)

def text(c,x,y,text,width,size=11,color=INK,bold=False):
    font='RobotoBold' if bold else 'Roboto';c.setFont(font,size);c.setFillColor(color)
    for line in simpleSplit(text,font,size,width):c.drawString(x,y,line);y-=size*1.4
    return y

def build_atlas():
    w,h=landscape(A3)
    c=canvas.Canvas(str(OUT/'Topolina_Functionality_Flow_Map.pdf'),pagesize=(w,h))
    c.setTitle('Topolina functionality flow map');c.setAuthor('Topolina')
    # Page 1 is the navigation overview; pages 2-4 are executable business flows.
    atlas_header(c,'Access and the complete workspace','Follow the role branches first then use pages 2 to 4 for the detailed workflows',1)
    topy=655;top=[(40,180,'Open Topolina\nInternet connection'),(250,210,'Email and password\nSupabase authentication'),(500,210,'Active provisioned\naccount profile'),(750,220,'Route by role\nAdmin or waiter')]
    for x,bw,label in top:rounded(c,x,topy,bw,65,label,fill=FOREST,size=12,bold=True)
    for (x,bw,_),(nx,_,_) in zip(top,top[1:]):arrow(c,[(x+bw,topy+32),(nx-4,topy+32)])
    rounded(c,500,547,210,63,'Failed connection or access\nRetry or ask admin\nNo cafe data access',fill=GOLD,size=11)
    arrow(c,[(605,655),(605,615)])
    rounded(c,55,415,300,85,'WAITER\nMy day  •  Expenses  •  More',fill=FOREST,size=13,bold=True)
    rounded(c,815,415,320,85,'ADMIN\nOverview  •  Expenses\nDay end  •  More',fill=FOREST,size=13,bold=True)
    arrow(c,[(860,655),(860,625),(205,625),(205,505)],'Waiter')
    arrow(c,[(970,687),(1108,687),(1108,505)],'Admin')
    rounded(c,55,270,300,108,'Enter any active expense category\nView own entries on eligible dates\nSubject to waiter permissions\nBrowse categories\nChange own password and sign out',size=11.3)
    arrow(c,[(205,415),(205,383)])
    rounded(c,410,270,320,108,'ONE SHARED LEDGER\nAdmin and waiter expenses\nOriginal purchase plus dated payments\nNo second admin copy',fill=GOLD,size=12,bold=True)
    arrow(c,[(355,325),(405,325)])
    rounded(c,815,270,320,108,'All waiter functions plus\nDashboard totals and quick actions\nSales net collections and reconciliation\nDay closing reopening and corrections\nAdmin and waiter creator attribution',size=11.3)
    arrow(c,[(975,415),(975,383)])
    arrow(c,[(815,325),(735,325)])
    labels=['Credit ledger\nVendor PDF statements','Staff records\nMonthly salaries','Categories items\nand vendors','Reports charts\nand CSV export','Waiter accounts\nand permissions','Backups restore\nand audit history']
    yy=102;bw=170;gap=18
    for i,label in enumerate(labels):rounded(c,40+i*(bw+gap),yy,bw,66,label,size=11)
    arrow(c,[(1135,313),(1150,313),(1150,202),(125,202)])
    for i in range(6):arrow(c,[(125+i*(bw+gap),202),(125+i*(bw+gap),173)])
    text(c,40,63,'Financial records feed dashboard totals daily reconciliation credit balances salary history and reports. Administrative functions are restricted by the backend.',1110,size=10)
    c.showPage()
    atlas_header(c,'Purchases payments salaries and vendor statements','Each row is a separate workflow all financial records reuse the same underlying expense and payment ledger',2)
    for y,(title,steps) in zip([620,455,290,125],FLOW_ROWS):flow_row(c,title,steps,y)
    text(c,40,78,'Entry gate: active account + permission + server date + writable day. Payments must be positive cannot exceed the balance and cannot precede the purchase date.',1110,size=10)
    c.showPage()
    atlas_header(c,'Reconciliation closing and corrections','Only actual payments affect the payment date unpaid purchases and unpaid salary do not increase paid expenses',3)
    flow_row(c,'Sales and daily reconciliation',[
        'Admin enters expected\nsales from Petpooja','Enter net cash bank\nand other collections','Sum payments dated\nto the business date','Difference = expected −\ncollections − paid expenses','Zero is balanced\nPositive short\nNegative excess','Review contributors\nExplain nonzero difference'],620)
    flow_row(c,'Close reopen and close again',[
        'Review the date\nSales must be entered','Close day\nStore closing snapshot','Date becomes locked\nNo ordinary financial edits','If changes are needed\nAdmin reopens with reason','Make eligible corrections\nReview updated accounts','Close again\nPrior snapshots retained'],450)
    flow_row(c,'Correct or void with full history',[
        'Admin opens expense\nor payment history','Reopen each affected\ndate when required','Correct expense OR\nvoid payment OR void expense','Mandatory reason\nCheck payment limits','Recompute balances\nand affected date totals','Audit retains actor time\nand original changed values'],280)
    rounded(c,40,95,340,126,'DATE WINDOW\nCalendar day 00:00 to 24:00\nPrevious date selectable until 00:59:59\nAt 01:00 ordinary grace has ended',fill=GOLD,size=12,bold=True)
    rounded(c,425,95,340,126,'CLOSED OR HISTORICAL DATE\nAdmin explicitly reopens with reason\nCutoff never automatically closes a day\nWaiter history remains date restricted',size=11.5)
    rounded(c,810,95,340,126,'CORRECTION CHECKS\nAmount cannot fall below active payments\nVoid expense after voiding its payments\nWrong date requires void and reentry',size=11.5)
    c.showPage()
    atlas_header(c,'Administration reporting and recovery','Management changes preserve historical references reports preserve date meanings restore preserves users and audit history',4)
    flow_row(c,'Categories items and vendors',[
        'Admin opens\nCategories vendors and items','Add or edit names\ncategory icon and defaults','Set active or inactive','Active choices appear\nin new expense forms','Existing references\nremain in history','Master changes\nare audited'],630)
    flow_row(c,'App accounts and personal access',[
        'Admin opens\nApp users and permissions','Create waiter OR edit\nreset deactivate OR\nchange waiter permissions','Backend checks active\nadmin and selected action','Save account change\nor global waiter permissions','Updated access enforced\nby backend role checks','Active waiter can sign in\nchange password or sign out'],482)
    flow_row(c,'Reports and export',[
        'Select dates\nand up to 367 days','Filter category vendor\nstaff mode and status','Review incurred paid\nand end date outstanding','View chart groups\nand daily reconciliation','Open a day\nfor detailed review','Export CSV\nthrough file picker'],334,
        'Expense filters do not allocate sales: sales and daily reconciliation remain complete. Outstanding uses only payments through the report end date.')
    flow_row(c,'Manual or automatic backup',[
        'Manual request OR\ndaily weekly schedule','Server captures\ncoherent app snapshot','Keep configured\n2 to 60 snapshots','View last successful\nbackup and snapshot list','Optional download\nof selected backup file','User saves a copy\nwith Android file picker'],186)
    flow_row(c,'Restore from a backup file',[
        'Select matching\nTopolina backup file','Validate project version\nchecksum and required data','Verify password reason\nand type RESTORE','Create safety backup\nbefore replacement','Atomic restore and\nrelationship validation','Success refresh ledger\nFailure rolls back'],55)
    c.save()

def build_sources():
    out=['# Topolina functionality guide','','Release 1.0.0. Prepared 9 November 2026.','']
    for title,blocks in PAGES:
        out+=['## '+title,'']
        for kind,data in blocks:
            if kind in ('p','h'):
                s=data.replace('<b>','').replace('</b>','').replace('<br/>','\n').replace('&amp;','&').replace('&gt;','>').replace('&lt;','<')
                out+=[('### ' if kind=='h' else '')+s,'']
            elif kind=='steps':out += [f'{i}. {s}' for i,s in enumerate(data,1)]+['']
            elif kind=='flow':out+=[' → '.join(data),'']
            elif kind=='table':
                heads,rows,_=data;out+=['| '+' | '.join(heads)+' |','|'+'|'.join(['---']*len(heads))+'|']
                out+=['| '+' | '.join(row).replace('&gt;','>').replace('&lt;','<')+' |' for row in rows]+['']
    (ROOT/'docs'/'functionality-guide.md').write_text('\n'.join(out),encoding='utf-8')
    flow=['# Topolina functionality flows','','Editable diagram sources for release 1.0.0. The PDF flow map also covers access, administration, dates, corrections and restore.','']
    for title,steps in FLOW_ROWS:
        flow += ['## '+title,'','```mermaid','flowchart LR']
        for i,step in enumerate(steps):flow.append(f'  N{i}["{step.replace(chr(10),"<br/>")}"]')
        flow += [f'  N{i} --> N{i+1}' for i in range(len(steps)-1)]+['```','']
    (ROOT/'docs'/'functionality-flows.md').write_text('\n'.join(flow),encoding='utf-8')

if __name__=='__main__':
    build_guide();build_atlas();build_sources()
    print('Created the functionality guide and four page flow map.')
