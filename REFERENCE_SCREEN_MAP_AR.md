# خريطة الصور المرجعية — NineSoft Reference UI

هذه الصور هي مرجع قبول بصري مباشر، وليست إلهامًا عامًا.

| # | الصورة المرجعية | الشاشة الفعلية | الملف/المسار الرئيسي |
|---|---|---|---|
| 1 | المبيعات / تحرير فاتورة بيع | Sales invoice editor | apps/nizami_app/lib/src/features/invoices/invoice_workspace_page.dart |
| 2 | المستخدمون والصلاحيات | Users & permissions | apps/nizami_app/lib/src/features/administration/administration_page.dart |
| 3 | المزامنة والنسخ الاحتياطي | Sync & backup | apps/nizami_app/lib/src/features/backup/backup_page.dart |
| 4 | واتساب | WhatsApp center | apps/nizami_app/lib/src/features/whatsapp/whatsapp_page.dart |
| 5 | تحويلات WASL | WASL transfers | apps/nizami_app/lib/src/features/wasl/wasl_page.dart |
| 6 | الجرد وتسوية المخزون | Stock count/reconciliation | apps/nizami_app/lib/src/features/inventory/stock_operations_page.dart |
| 7 | مرتجع مبيعات | Sales return | apps/nizami_app/lib/src/features/returns/return_workspace_page.dart |
| 8 | دفتر الأستاذ | General ledger / account statement | apps/nizami_app/lib/src/features/accounting/account_statement_page.dart |
| 9 | ميزان المراجعة | Trial balance | apps/nizami_app/lib/src/features/accounting/financial_reports_page.dart |
| 10 | الأرباح والخسائر | Profit & loss | apps/nizami_app/lib/src/features/accounting/financial_reports_page.dart |
| 11 | التقارير والتحليلات | Reports hub | apps/nizami_app/lib/src/features/dashboard/section_hub_page.dart |
| 12 | الإعدادات والتحكم | Settings control center | apps/nizami_app/lib/src/features/settings/identity_settings_page.dart + navigation/admin entry points |
| 13 | الصندوق والحسابات البنكية | Cashbox & bank accounts | apps/nizami_app/lib/src/features/accounting/cashbox_page.dart |
| 14 | سندات القبض والصرف | Receipt/payment vouchers | apps/nizami_app/lib/src/features/modules/module_workspace_page.dart |
| 15 | القيود اليومية | Journal editor | apps/nizami_app/lib/src/features/accounting/simple_journal_page.dart |
| 16 | شجرة الحسابات | Chart of accounts | apps/nizami_app/lib/src/features/accounting/chart_accounts_page.dart |
| 17 | الموردون | Supplier editor/details | apps/nizami_app/lib/src/features/modules/module_workspace_page.dart |
| 18 | العملاء | Customer editor/details | apps/nizami_app/lib/src/features/modules/module_workspace_page.dart |
| 19 | المخزون والأصناف | Product/item editor | apps/nizami_app/lib/src/features/modules/module_workspace_page.dart |
| 20 | المشتريات | Purchase invoice editor | apps/nizami_app/lib/src/features/purchases/purchase_workspace_page.dart |

## معيار القبول

كل شاشة تُعد منتهية فقط عندما:
1. تستخدم البيانات الحقيقية الحالية.
2. لا تُغيّر عقود API أو التخزين أو المزامنة بصمت.
3. تكون بنية العرض مستقلة عن ترتيب الإدخال القديم.
4. توجد لقطة فعلية من التطبيق تقارن بالصورة المرجعية.
5. ينجح flutter analyze وflutter test وبناء Web بعد التغيير.
