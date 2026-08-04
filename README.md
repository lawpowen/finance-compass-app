# Finance Compass

当前版本：`0.9.0+42`。工程文档索引见 [docs/README.md](docs/README.md)。

完整中文需求与设计文档请看：[finance-app-design.md](finance-app-design.md)。

`Finance Compass` is a Flutter-based personal finance app focused on:

- multi-account bookkeeping
- reusable budgets with rollover
- investment and retirement tracking
- monthly and cumulative reports
- exportable data for external AI analysis

This project is already beyond a simple MVP skeleton. It includes local persistence with `SQLite + Drift`, account and transaction management, reporting, asset snapshots, multi-currency exchange-rate settings, and import/export flows.

## Self-hosted Web / PWA

`0.9.0+42` adds a self-hosted Web/PWA build for iPhone/iPad Safari, Android Chrome and desktop browsers. The server **only serves static application files**. Each browser keeps its own Drift WASM SQLite data in its local browser storage; there is no server database, login system, cloud backup or device-to-device sync. Export JSON regularly and before clearing browser/site data.

The Docker deployment defaults to localhost-only. Put HTTPS and access control in your own reverse proxy before exposing it beyond the host. See [self-hosted Web/PWA guide](docs/SELF_HOSTING.md) for Ubuntu, Windows and macOS install scripts, PWA limits, backup and rollback.

- [Ubuntu 自托管包 v0.9.0](https://github.com/lawpowen/finance-compass-app/releases/download/v0.9.0/FinanceCompass-SelfHost-Ubuntu-v0.9.0.zip)
- [Windows 自托管包 v0.9.0](https://github.com/lawpowen/finance-compass-app/releases/download/v0.9.0/FinanceCompass-SelfHost-Windows-v0.9.0.zip)
- [macOS 自托管包 v0.9.0](https://github.com/lawpowen/finance-compass-app/releases/download/v0.9.0/FinanceCompass-SelfHost-macOS-v0.9.0.zip)

三个自托管包都需要 Docker Engine/Desktop；它们不是原生 `.deb`、`.msi` 或 `.dmg`。解压后按 `SELF_HOSTING.md` 启动，并在对外访问前配置 HTTPS 和认证。

## Download / 普通用户下载

无需安装 Flutter 或其他开发工具，请按设备选择：

### Windows 10/11 x64

**[下载 Windows 安装版（推荐）](https://github.com/lawpowen/finance-compass-app/releases/download/v0.9.0/FinanceCompass-Windows-x64-Setup-v0.9.0.exe)**

安装包目前没有商业 Authenticode 代码签名，Windows 可能显示“未知发布者”或 SmartScreen 提示。请确认文件来自本仓库，并可使用发布页提供的 SHA-256 校验值核对。

不想安装时，可使用 **[Windows 便携版 ZIP](https://github.com/lawpowen/finance-compass-app/releases/download/v0.9.0/FinanceCompass-Windows-x64-Portable-v0.9.0.zip)**。必须完整解压后运行 `FinanceCompass.exe`，不能只复制单个 EXE。

### Android

**[下载 Android APK](https://github.com/lawpowen/finance-compass-app/releases/download/v0.9.0/FinanceCompass-Android-v0.9.0.apk)**

APK 使用 Finance Compass 独立发布密钥签名。首次侧载时，Android 可能要求允许浏览器或文件管理器“安装未知应用”。

还可以进入 **[全部版本和校验文件](https://github.com/lawpowen/finance-compass-app/releases/latest)**。GitHub 自动显示的 `Source code` 压缩包不是普通用户安装包。

## Current Highlights

- 全应用交互门禁：可见箭头和启用控件必须执行真实操作；周期规则、预算月份、报表区间、货币格式和应用内提醒均已接入，计划能力明确禁用。
- 交易页顶部三种口径为“实际消费”“实际现金”“信用/贷款”；“实际现金”卡以“需准备现金”为副标题，把已知现金流出与尚未安排的到期信用卡/贷款合并，已安排还款不重复计算，不再额外占用独立大卡。未来月份的现金流出按现金账户整笔进出计算，贷款转账使用完整月供。
- 报表收入/支出统一为实际现金流入/流出；资产目标按不扣除信用卡和贷款的总资产计算；信用账户还款使用“选择同币种现金账户 → 确认金额”的专用流程。
- 月度预算是按生效月延续的规则：新月份金额只覆盖该月及以后，更早月份继续使用当时有效的旧规则。

- Cross-platform Flutter app for Android, Windows, iOS, macOS, Linux, and Web targets.
- Local-first finance database using SQLite and Drift.
- Multi-currency support for `MYR`, `USD`, `CNY`, and `TWD`.
- Per-account currency display with base-currency totals.
- Cross-currency transfers with separate source and target amounts.
- Reusable budgets with positive and negative rollover.
- Planned versus actual transaction states.
- Transaction editing with confirmed deletion and finite signed amounts, including zero and negative values.
- Credit-card statement history preserves each cycle's original bill amount after repayment, while remaining debt is calculated separately. Day-one statement cuts are labeled as the month that just ended, matching PayLater bill-month conventions.
- Loan accounts calculate complete amortization schedules for equal installments, equal principal, and flat-rate loans, with an optional bank-quoted regular payment for equal-installment and flat-rate contracts.
- Recurring transaction rules and compact quick templates.
- Account cutoff-month calculations that exclude future transactions.
- Investment and retirement snapshots with contribution, withdrawal, cost, cash balance, and PnL views.
- Multiple net-asset goals with reached-date tracking.
- Full JSON backup/import, AI summary JSON export, and future planning CSV export.
- Exported AI summary can be opened by the operating system so another app can read the JSON.

## Product Scope

The app is designed for personal finance scenarios where the user wants to manage:

- daily cash, e-wallet, savings, and credit accounts
- MYR, USD, CNY, and TWD account and transaction currencies
- category-based income and expense records
- transfer flows between accounts
- investment and retirement accounts with market value tracking
- monthly budgets and rollover logic
- future planned transactions and future budget usage
- planned versus actual cash-flow tracking
- summarized exports for analysis outside the app

## Module Map

### Dashboard

Purpose:

- quick financial overview
- time-filtered period income, expense, and net summary
- monthly comparison
- budget watch
- future expense reservation and simple forecast
- future cash-flow projection from planned transactions
- credit card payment reminders

Key behavior:

- Dashboard is the main page that uses its own selected time range for calculations.
- Period-level values change with the selected year and month filters.

### Accounts

Purpose:

- show grouped balances for `cash`, `credit`, `investment`, and `retirement`
- manage accounts
- view investment and retirement summaries
- manage asset goals

Key behavior:

- Accounts page supports a real cutoff-month selector from the earliest ledger month through the current month.
- All balances and asset summaries respect the selected month-end cutoff, and account details inherit the same cutoff.
- Historical account details are explicitly read-only and offer a one-tap return to the current month; future and planned transactions are excluded.
- Each account can show a balance trace explaining how the cutoff balance is derived.
- Each account can be marked as reconciled up to a selected month.
- Loan setup accepts the contract principal, annual rate, term, tracking start date, monthly payment day, repayment method, and an optional opening outstanding balance for loans first recorded mid-contract. The loan detail shows only the installments that remain to be tracked, including principal, interest, payment, and remaining principal.
- Recording a scheduled loan payment creates a principal transfer to the loan plus a separate interest expense, so cash outflow and outstanding principal remain accurate.

### Transactions

Purpose:

- add, edit, delete, and filter transactions
- create recurring monthly transaction records
- reuse common transaction templates for faster entry
- manage recurring transaction rules
- separate transactions into planned and actual states
- maintain categories used by bookkeeping

Key behavior:

- filters support `month from`, `month to`, `type`, `category`, and `account`
- account filtering includes both transfer-out and transfer-in records
- default filter is current month to current month
- transactions can be reused directly or saved as templates
- templates prefill amount, account, category, type, description, merchant, and currency
- planned transactions are shown in planning views but do not change account balances
- the transaction page defaults to actual records; switching to `包含预计` keeps actual records visible and adds planned records to the list, income, expense, and net cash-flow totals
- the middle transaction-basis card becomes the unfiltered funding-need total for current and future months: known cash outflow plus uncovered credit-card and loan payments due in that month, without a second standalone card or duplicate repayment counting
- recurring rules generate 1-12 selected months while preserving the rule's actual or planned status for every month

### Budgets

Purpose:

- define reusable category budgets
- monitor budget usage by month
- apply rollover logic across months
- compare actual usage and planned usage
- show annualized budget and year-to-date usage

Key behavior:

- budgets are stored as reusable rules by category and effective month
- rollover supports both positive carry and negative carry
- overspending in one month can reduce the next month when rollover is enabled
- budget screens show actual spending, planned spending, and remaining pool balance separately

### Reports

Purpose:

- provide chart and table views for financial data
- compare income and expense trends
- inspect category distributions

Key behavior:

- supports line, pie, and table views
- supports monthly and cumulative modes
- supports last 3 months, last 6 months, last 12 months, and current year

### Settings

Purpose:

- theme selection
- example data setup
- data import and export
- AI summary export

Key behavior:

- full JSON import/export is supported
- full JSON export validates the backup structure before saving
- AI summary export excludes full raw transaction detail and is intended for external analysis
- future planning CSV export is available

## Data Model

The app persists its data in SQLite through Drift.

### `accounts`

Represents real-world accounts such as:

- cash
- bank saving
- e-wallet
- credit card
- pension
- stock
- crypto
- trading
- fund
- loan

Important fields:

- `id`
- `name`
- `accountType`
- `reportGroup`
- `currency`
- `initialBalance`
- `currentBalance`
- `institution`
- `note`
- `isActive`

Important distinction:

- `accountType` is the real account type
- `reportGroup` is the reporting bucket used by the app:
  - `cash`
  - `credit`
  - `investment`
  - `retirement`

Supported currencies:

- `MYR`
- `USD`
- `CNY`
- `TWD`

Note:

- Currency selection is stored per account and transaction.
- Currency priority is configured in Settings by drag-and-drop.
- The first currency is the reporting base currency; the second is used as the secondary hint currency.
- Exchange rates are configured as `1 currency = base currency amount`.
- Individual accounts keep their own currency balance; Dashboard, reports, AI summaries, budget usage, and asset goals convert totals back to the selected base currency.

### `categories`

Represents transaction categories.

Category types:

- `income`
- `expense`
- `investment`
- `transfer`

Important fields:

- `id`
- `name`
- `type`
- `parentId`

### `budgets`

Represents reusable category budget rules.

Important fields:

- `id`
- `categoryId`
- `monthKey`
- `amount`
- `currency`
- `alertThreshold`
- `rolloverEnabled`

Meaning:

- `monthKey` is the month when that rule starts being effective
- later months reuse the latest applicable rule
- budget amounts keep their own currency and are converted into the selected base currency before monitoring, rollover, reports, and exports are calculated

### `transactions`

Represents bookkeeping entries.

Transaction types:

- `income`
- `expense`
- `transfer`
- `adjustment`

Important fields:

- `id`
- `type`
- `accountId`
- `toAccountId`
- `categoryId`
- `amount`
- `currency`
- `toAmount`
- `toCurrency`
- `transactionDate`
- `status`
- `recurringRuleId`
- `description`
- `merchant`

Business meaning:

- `income`: increases one account
- `expense`: reduces one account
- `transfer`: moves funds between two accounts; `amount/currency` is the source account amount and `toAmount/toCurrency` is the target account amount
- `adjustment`: contribution or manual funding adjustment, mainly for investment and retirement accounts
- `status = planned`: used for expected future cash flow and budget planning; it does not affect account balances
- Credit-card committed debt and limit usage include every actual/settled record, including future-dated installments that already lock the limit, while excluding every planned record. Billing periods and due reminders still stop at today.
- Credit-card details provide a statement-month picker derived from the account statement day. Selecting a historical month switches the amount, timeline and transaction list to that exact billing cycle.
- `status = actual`: counted as real bookkeeping and affects account balances

### `asset_snapshots`

Represents periodic valuation records for investment and retirement accounts.

Important fields:

- `id`
- `accountId`
- `snapshotDate`
- `marketValue`
- `costBasis`
- `cashBalance`
- `unrealizedPnl`

Meaning:

- snapshots are the valuation anchor for investment-style accounts
- later calculations are rewound or projected from snapshots plus transactions

### `app_meta`

Stores app-level metadata such as:

- theme selection
- seed/example data state
- asset goals
- account reconciliation month markers
- transaction templates
- recurring transaction rules

## Core Business Rules

### Time Semantics

- Dashboard uses its own selected time filter.
- Accounts page uses its selected cutoff month.
- If no special cutoff is chosen, account-related calculations default to current month.
- Future transactions are not included in present-time account calculations.

### Ledger Traceability

- Account balances can be traced from the current account balance or the latest eligible asset snapshot.
- The trace shows the cutoff date, source amount, future transactions reversed for that cutoff, and the final traced balance.
- Reconciliation markers are stored per account so the user can see which month has already been checked against real-world statements.

### Budget Rollover

- If rollover is disabled, unused or overspent budget does not carry forward.
- If rollover is enabled:
  - positive remaining budget carries to next month
  - negative remaining budget also carries to next month
- This means overspending can reduce next month’s available budget.

### Planned Vs Actual

- Planned transactions are for forecasts, future commitments, and budget reservation.
- Actual transactions are treated as real ledger entries.
- Future cash-flow projection reads planned transactions, recurring generated transactions, and future-dated real transactions.
- Budget monitoring separates actual spend from planned spend so future commitments do not look like already-spent money.

### Recurring Transactions

- A transaction can be saved as a recurring rule.
- Rules support monthly, every-2-months, quarterly, and yearly intervals.
- Saving a rule immediately creates planned transactions through the next three complete calendar months; future occurrences are always planned rather than posted to balances.
- The automation page can extend a rule by a chosen 1-12 month range and avoids already generated months.

### Credit Card Reminders

- Credit accounts with negative balances are surfaced as payment reminders.
- Credit-card accounts support a credit limit, statement day, and payment due day.
- Legacy cards without those fields keep an explicitly estimated reminder on the 25th of the next month until setup is completed.
- Card purchases remain ordinary transactions; billing dates are not stored per transaction.

### Loan Amortization

- Equal installments use the reducing-balance annuity formula. Equal-installment and flat-rate contracts may use a bank-quoted regular monthly payment; the final installment automatically reconciles the remaining principal and contractual interest.
- Equal principal keeps the principal component level and produces a declining payment.
- Flat-rate loans calculate interest from the original principal for the full term.
- A mid-contract opening balance does not create historical payment transactions. Its future flat-rate rows keep the original contract's monthly interest basis and continue from the reported outstanding principal.
- The first tracked payment is scheduled in the month after the tracking start date. Payment days 29–31 are clamped to the last day of shorter months.
- The schedule is derived from account terms. After creating a loan, the app asks whether to generate every remaining installment as a planned principal transfer plus a planned interest expense; the same action remains available on the loan detail page.
- Recording an actual installment replaces its matching planned pair. Only the principal transfer reduces the loan balance, while principal plus interest leaves the selected repayment account.

### Investment and Retirement Calculations

For investment and retirement accounts:

- contribution flows affect:
  - market value
  - cost basis
  - cash balance
- cumulative contribution and withdrawal are derived from transaction history
- unrealized PnL is based on remaining cost basis, not only raw cumulative cost

Current display values for these accounts are aligned by cutoff date:

- market value
- cumulative contribution
- cumulative withdrawal
- cumulative cost basis
- cash balance
- unrealized PnL

### Transfer Filtering

When filtering transactions by account:

- transfer-out records are included
- transfer-in records are also included

This keeps account-based transaction history complete.

## Import / Export

Supported exports:

- full JSON export
- AI summary JSON export
- future planning CSV export

Supported import:

- full JSON import with preview

Notes:

- full JSON export is intended for backup and restore
- full JSON export validates required backup sections such as accounts, categories, budgets, transactions, snapshots, and metadata
- AI summary JSON is intended for external AI analysis when AI is not directly integrated inside the app

## Project Structure

Main structure under `lib/src`:

- `core/data`
  - repository logic
  - sample data
- `core/database`
  - Drift database
  - tables
  - seed/bootstrap services
- `core/models`
  - domain models
- `core/settings`
  - theme and app settings state
- `core/theme`
  - visual theme system
- `core/utils`
  - formatters and helper functions
- `features/dashboard`
  - overview screen
- `features/accounts`
  - account screens and asset snapshot flows
- `features/transactions`
  - transaction list and transaction form
- `features/budgets`
  - budget list and budget form
- `features/reports`
  - report views and charts
- `features/settings`
  - import/export and app settings
- `features/shared`
  - reusable UI building blocks

## Buy the developer a coffee / 请开发者喝杯咖啡

Finance Compass 免费提供。如果它对你有帮助，欢迎自愿支持继续开发。支持不会解锁额外功能，也不形成服务权益；付款前请确认收款人是 **LAW PO WEN**。

<img src="assets/support/touch-n-go-support-qr.jpg" alt="Touch 'n Go QR code for voluntarily supporting Finance Compass development" width="360">

应用只显示这张静态二维码，不接入支付 SDK、不读取付款结果，也不会自动上传财务资料。

## Development

Run from the project folder with the configured Flutter SDK:

```powershell
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

Build Android APK:

```powershell
flutter build apk --release
```

Build the side-by-side installable debug APK for a physical ARM64 device:

```powershell
flutter build apk --debug --split-per-abi
```

The debug variant is labeled `Finance Compass Debug` and uses the independent
application ID `com.financecompass.app.debug`. It can be installed beside the
release application (`com.financecompass.app`) and has a separate Android data
directory.

Android release builds require local `android/key.properties` and a release keystore. See [public release workflow](docs/RELEASE_WORKFLOW.md); signing secrets are never committed.

Build Android release APK:

```powershell
flutter build apk --release
```

Build Windows release:

```powershell
flutter build windows --release
```

Distribute the complete Windows Release directory through the installer or portable ZIP. `FinanceCompass.exe` depends on adjacent DLL and `data/` files and must not be distributed alone.
