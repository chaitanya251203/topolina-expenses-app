# Topolina functionality flows

Editable diagram sources for release 1.0.0. The PDF flow map also covers access, administration, dates, corrections and restore.

## Shared expense entry

```mermaid
flowchart LR
  N0["Admin or permitted waiter<br/>Add expense"]
  N1["Choose eligible date<br/>Category item vendor description"]
  N2["Manual amount<br/>or quantity × rate"]
  N3["Paid full<br/>Partial amount<br/>or unpaid credit"]
  N4["One purchase and any<br/>immediate payment"]
  N5["Shared ledger<br/>Balances and date totals update"]
  N0 --> N1
  N1 --> N2
  N2 --> N3
  N3 --> N4
  N4 --> N5
```

## Vendor credit payment

```mermaid
flowchart LR
  N0["Admin opens<br/>Credit ledger"]
  N1["Choose vendor and<br/>outstanding purchase"]
  N2["Choose actual payment<br/>date and mode"]
  N3["Enter amount no more<br/>than remaining balance"]
  N4["Add a separate<br/>full or partial payment"]
  N5["Pending decreases<br/>Payment date totals update"]
  N0 --> N1
  N1 --> N2
  N2 --> N3
  N3 --> N4
  N4 --> N5
```

## Staff and salary payment

```mermaid
flowchart LR
  N0["Admin manages staff<br/>and selects salary month"]
  N1["Create unpaid salary<br/>or link existing expense"]
  N2["Reuse one expense<br/>and any existing payments"]
  N3["When money is paid<br/>Record full or partial payment"]
  N4["Payment contributes<br/>on its own date"]
  N5["Monthly paid pending<br/>and payment history"]
  N0 --> N1
  N1 --> N2
  N2 --> N3
  N3 --> N4
  N4 --> N5
```

## Vendor payment statement

```mermaid
flowchart LR
  N0["Admin selects vendor<br/>Share payment statement"]
  N1["Fresh snapshot of only<br/>that vendor pending purchases"]
  N2["Validate original paid<br/>and pending totals"]
  N3["Branded PDF with<br/>purchase and payment dates"]
  N4["Preview and choose<br/>save print or native share"]
  N5["User chooses action<br/>No payment is recorded"]
  N0 --> N1
  N1 --> N2
  N2 --> N3
  N3 --> N4
  N4 --> N5
```
