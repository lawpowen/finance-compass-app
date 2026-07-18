# Design QA

## Evidence

- Visual sources of truth for this correction: `artifacts/ui-reference/supplemental-budget-overview.png` and `artifacts/ui-reference/27-appearance.png`.
- Implementation captures: `artifacts/design-qa/budget-overview-390.png` and `artifacts/design-qa/appearance-carousel-390.png` at a 390×844 logical-pixel viewport.
- Combined comparison inputs: `artifacts/design-qa/budget-comparison.png` and `artifacts/design-qa/appearance-comparison.png`. Each places the reference and implementation in the same image before judging visible differences.
- State: dark mode with deterministic test data. Amounts and category names can differ from the illustrative reference, while information hierarchy, percentage semantics, color roles and interactions must match.

## Findings

- No actionable P0, P1 or P2 mismatch remains in the checked budget and appearance states.
- Budget composition now shows up to five actual categories rather than four categories plus a visually dominant “其他”. Each percentage is the category base budget divided by the month’s total allocated budget.
- Budget usage separates solid actual spend, diagonal-striped planned spend and unused capacity, matching the reference’s status grammar. Category cells use the reference’s teal-tinted grouping and remain width-safe at 390 px.
- Appearance exposes partial neighboring cards, page dots and a selected-card outline, so horizontal dragging is discoverable. Dragging changes only the local preview; the app theme changes only after the user presses the confirmation button.
- Total/transaction preview switching is functional and does not persist a theme by itself.
- Flutter’s widget-test renderer on this workstation has no CJK fallback font, so Chinese glyphs appear as squares in captures. Geometry, colors, hierarchy and interaction assertions remain inspectable; Android uses the device system font.

## Comparison history

1. The previous budget implementation combined all categories after the largest four into “其他” and used a nearly full orange strip, causing the result to diverge from the approved five-category composition.
2. The previous appearance page listed theme controls but did not expose the approved draggable carousel preview.
3. The corrected build was recaptured at 390×844 and combined with both references. The budget hierarchy, five-category composition, usage-state treatment and theme carousel now align with the approved direction.

## Primary interactions checked

- Horizontal drag between themes.
- Previewing a different theme without applying it.
- Switching the preview between dashboard and transaction content.
- Rendering the budget composition and allocation rows at 390 px without overflow.
- Opening an existing transaction from the v2 list and preserving its identity when saving.
- Navigating into a future month and automatically revealing planned transactions.
- Switching the dashboard forecast between 30 and 60 days at 390×844.
- Opening credit-card billed and unbilled rows in the same v2 transaction editor used for repayments.

## Known follow-up

- Verify Android system-font rendering, physical swipe feel, status/navigation-bar insets and native back behavior using the new Debug APK.
- Bank-specific logos and Google sign-in remain future enhancements.

## 2026-07-17 transaction and billing-cycle follow-up

- The approved screen hierarchy was retained; this correction adds missing tap targets and replaces the old repayment dialog with `TransactionComposerPage`.
- Billing labels now render actual month/day values from `CreditCardBillingPeriod` instead of hard-coded June/July/August samples.
- Widget checks at 390×844 confirm the future-month route reaches its planned transaction and the dashboard range menu updates without layout overflow.
- No P0, P1 or P2 interaction blocker remains in these paths.

## 2026-07-17 transaction action menu follow-up

- Visual source: the user-provided pre-redesign menu crop at `C:/Users/pwlaw/AppData/Local/Packages/MicrosoftWindows.Client.Core_cw5n1h2txyewy/TempState/ScreenClip/{C59239E0-A78D-4B67-A25A-654A053BC28D}.png`.
- Implementation capture: `artifacts/design-qa/transaction-menu-390.png` at 390×844 with the popup open.
- Combined comparison: `artifacts/design-qa/transaction-menu-comparison.png` places the source and implementation menu side by side before judging it.
- The implementation preserves the five-row order, leading icons, destructive divider and destructive color. Row height, menu density and corner treatment remain consistent with the old interaction while using the selected app theme.
- The menu is anchored at the transaction amount edge without replacing the full-row edit target. Automated interaction checks confirm every item is functional.
- The widget renderer lacks CJK and Material icon fonts on this workstation, so glyphs appear as squares in the implementation capture; the Android/Windows packaged app uses its normal fonts and icon assets.
- No actionable P0, P1 or P2 visual mismatch remains for this component.

final result: passed

## 2026-07-18 transaction calculation basis cards

- Visual source of truth: `C:/Users/pwlaw/.codex/generated_images/019f5ba9-2b1f-7cf3-bf9a-2da8a4633995/exec-f4136a98-86fe-402b-a555-7098de94f50d.png`, the user-selected Product Design option 2.
- Implementation capture: `artifacts/design-qa/transaction-basis-cards-390.png` at a 390×844 logical-pixel viewport with deterministic cash, credit, income, expense, transfer and planned data.
- Combined comparison: `artifacts/design-qa/transaction-basis-comparison.png`; the reference and implementation were judged in one image at the same width.
- Full-page evidence confirms the retained month navigation, grouped transaction list, equal-size lightning/add actions and bottom navigation. Focused evidence confirms the selected wide card, two compact cards, page indicator, actual/planned segment, dual metric legend and three quick-filter pills plus search.
- The implementation preserves the approved deep-navy surface, teal selection border and orange negative-value grammar. Amounts differ because the implementation capture uses test ledger data rather than the concept image's illustrative values.
- All three cards are real controls. Switching cards changes the summary and metric labels; the actual/planned segment changes the underlying status scope; account, type and category pills open real selectors. Transaction rows remain available under every calculation basis.
- No actionable P0, P1 or P2 mismatch remains. The implementation card row is slightly more compact vertically to preserve more transaction content at 390×844, without changing hierarchy or touch-target clarity.
- The Flutter widget renderer on this workstation lacks CJK and Material icon fallback fonts, so glyphs appear as boxes in automated captures. Layout, color, spacing and control state remain inspectable; packaged Android uses system glyphs.

### Iteration history

1. First capture implemented the three basis cards and status switch but retained four legacy transaction-type chips.
2. The filter row was revised to the approved account/type/category pills with a compact search control, and all pills were connected to real filters.
3. The corrected state was recaptured and recombined with the selected reference; geometry and interaction hierarchy now align at the 390 px baseline.

final result: passed

## 2026-07-18 Shopee PayLater original-statement follow-up

- The approved credit-card detail hierarchy is unchanged. The correction only changes bill-month naming and amount semantics: the month is derived from the day before statement close, and a paid historical bill keeps its original amount for reconciliation.
- The unbilled/confirmed statement amount now uses one billing period rather than the cumulative account balance. The visible July rows MYR 69.85, MYR 161.33 and MYR 82.11 therefore reconcile to MYR 313.29 instead of MYR 151.96.
- No new visual primitive, spacing rule, navigation pattern or 390 px responsive constraint was introduced. Existing historical and future-statement interaction baselines remain applicable.

final result: passed

## 2026-07-18 future confirmed credit-card statements follow-up

- The approved credit-card detail composition is retained. The existing statement picker now extends forward only when future transactions are explicitly `actual`/`settled`; those rows are labeled “已确定”, while planned rows remain excluded.
- Selecting a future statement reuses the same amount hierarchy, timeline, transaction list and return-to-current interaction. The compact top action uses “已确定” to remain width-safe at the 390 px baseline.
- Future confirmed statements display the original amount for that individual billing period rather than the cumulative account balance. Repayments affect the remaining debt state without erasing the historical amount used for reconciliation.
- A 390×844 widget test covers the future picker, confirmed transaction visibility and absence of narrow-screen overflow.

final result: passed

## 2026-07-18 transaction edit delete and signed amount follow-up

- The approved full-screen transaction editor keeps its existing hierarchy and orange primary save action. Edit mode now adds a 52 px orange-outline “删除交易” action immediately above save, so destructive intent remains separated from the primary action.
- Tapping delete opens a native confirmation dialog that states both irreversibility and account-balance restoration. Cancelling leaves the user in the same scrolled edit view; confirming returns to the originating transaction or credit-card list and refreshes it through the existing mutation provider.
- The amount field now requests a signed decimal keyboard and preserves `0.00` and negative draft values instead of displaying an empty field. No new component width, navigation pattern or 390 px overflow risk was introduced.
- Widget and repository tests cover cancel/confirm behavior, zero and negative edit saves, negative expense/transfer balance direction, and exact balance restoration after deletion.

final result: passed

## 2026-07-18 historical credit-card statement follow-up

- The existing “查看账单” control now opens a bottom-sheet month list with billing range, due date and amount; selecting a row switches the approved detail composition rather than navigating to a visually unrelated page.
- Historical mode reuses the amount hierarchy, timeline and transaction rows, replaces the current/unbilled segment with a clear historical-month label and “返回本期”, and keeps the live credit-usage bar unchanged.
- A 390×844 widget interaction test opens the picker, selects a previous cycle and confirms that only transactions from that exact period remain visible. The compact header button retains its original text-only layout to avoid narrow-screen overflow.

final result: passed

## 2026-07-18 credit commitment and recurring-status follow-up

- The approved account and credit-card layouts are unchanged; the existing amount slot now labels the account-row value as “当前欠款”, while statement-state chips and the detail header continue to describe the current billing cycle.
- Credit-limit usage reuses the approved progress component and changes only its data source: future actual installments are included, planned records are excluded.
- Recurring-generation helper copy now states that every generated month preserves the selected actual/planned state. No component dimensions, navigation, color tokens or 390 px responsive constraints changed.
- Functional and repository tests cover these semantic changes; no new visual primitive or overflow risk was introduced, so the existing 390×844 visual baseline remains applicable without a new capture.

final result: passed
