# NineSoft UI Development Base

## Snapshot

- Export date: 2026-11-02
- Git branch: `feature/exact-entry-units-autopost`
- Base commit: `6cdcdc6154da3ffb323faee7ea02d14783baba74`
- The archive intentionally includes the current modified Flutter source files. Compare returned work against this archive as the merge base; do not overwrite the live workspace wholesale.

## Flutter project

- Application root: `apps/nizami_app`
- Main source: `apps/nizami_app/lib`
- Assets, logo and fonts: `apps/nizami_app/assets`
- Tests: `apps/nizami_app/test`
- Android host: `apps/nizami_app/android`
- Windows host: `apps/nizami_app/windows`
- Web host: `apps/nizami_app/web`
- Dependencies: `apps/nizami_app/pubspec.yaml`

## Main UI locations

- Dashboard: `lib/src/features/dashboard/ninesoft_reference_dashboard.dart`
- Sales editor/history: `lib/src/features/invoices/invoice_workspace_page.dart`
- Purchases: `lib/src/features/purchases/purchase_workspace_page.dart`
- Generic modules, contacts and vouchers: `lib/src/features/modules/module_workspace_page.dart`
- Account statement: `lib/src/features/accounting/account_statement_page.dart`
- Chart of accounts: `lib/src/features/accounting/chart_accounts_page.dart`
- Journal: `lib/src/features/accounting/simple_journal_page.dart`
- Reports: `lib/src/features/accounting/financial_reports_page.dart`
- Inventory inquiry: `lib/src/features/accounting/product_inquiry_page.dart`
- Shared entry UI: `lib/src/theme/ninesoft_entry_ui.dart`
- Navigation shell: `lib/src/features/navigation/ninesoft_workspace_shell.dart`

## Hard constraints

- UI/UX changes only. Keep all existing API field names and service calls.
- Do not change accounting posting, debit/credit rules, stock costing, synchronization, permissions, persistence, printing or database schemas.
- Reuse real callbacks and data. Do not hard-code the sample values from reference images.
- Prefer full-page editors, inline expansion and inline search results. Avoid dialogs, modal sheets and popup menus in redesigned flows.

## Commands

```powershell
cd apps/nizami_app
flutter pub get
flutter analyze
flutter test
flutter build web --release
```

Generated folders such as `build`, `.dart_tool`, `.gradle` and IDE caches are intentionally excluded from the archive. No production credentials or customer databases are included.
