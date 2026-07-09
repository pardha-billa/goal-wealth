# GoalWealth Rails

Rails 6.1 + Ruby 3.2 + SQLite + RailsAdmin application for GoalWealth Phase 1.

## Revised Domain Model

```text
Investor
  -> Investment Account
       -> Asset
            -> Transaction

Institution
  -> Investment Account

Financial Goal
  -> Transaction
```

Important rule:

```text
Transaction references only:
- asset_id
- financial_goal_id
```

Investor, Institution and Investment Account are derived from Asset:

```text
Transaction -> Asset -> Investment Account -> Institution
Transaction -> Asset -> Investment Account -> Investor
```

## Requirements

- Ruby 3.2.x
- Rails 6.1.x
- SQLite3

## Install and Run

```bash
unzip goalwealth-rails.zip
cd goalwealth-rails
bundle install
bundle exec rails db:create
bundle exec rails db:migrate
bundle exec rails db:seed
bundle exec rails s
```

Open:

```text
http://localhost:3000/admin
```

## Data Entry Order

Use RailsAdmin in this order:

1. Institutions - seeded, but you can add more
2. Investors
3. Investment Accounts
4. Financial Goals
5. Assets
6. Transactions
7. Price Histories

## Important Field Meanings

### Investment Account

One record per folio/demat/PPF account.

Examples:

- Pramod / HDFC AMC / MF Folio / 12345678
- Pramod / HDFC AMC / MF Folio / 87654321
- Pramod / Upstox / Demat / UPX001
- Pramod / India Post / PPF / PPF001

`label` is only a friendly name such as Main MF, Emergency, Trading or PPF.

### Asset

Asset belongs to one investment account.

Examples:

- PPFCF inside HDFC AMC Folio 12345678
- PPFCF inside Upstox UPX001
- NIFTYBEES inside Upstox UPX001
- PPF inside India Post PPF001

### Transaction

Transaction has only:

- Asset
- Financial Goal
- Type
- Date
- Amount
- NAV/Price

Units are calculated as:

```text
units = amount / nav
```

For PPF, NAV can be blank.

## Enums

### Institution Type

- amc
- broker
- government
- bank
- retirement
- other

### Account Type

- mf_folio
- demat
- ppf
- epf
- nps
- fd
- other

### Asset Type

- mutual_fund
- etf
- ppf
- stock
- epf
- nps
- fd
- other

### Transaction Type

- buy
- sell
- deposit
- withdrawal
- interest

## Notes

- No custom CRUD pages are included.
- RailsAdmin is used for all data entry.
- Holdings/current values are not stored yet. They will be calculated later from transactions and price history.
