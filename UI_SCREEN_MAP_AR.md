# خريطة أقسام وشاشات NineSoft

| القسم | ملف العرض الرئيسي | الربط الفعلي |
|---|---|---|
| الرئيسية | `features/dashboard/ninesoft_reference_dashboard.dart` | يستدعي مخازن الفواتير والمشتريات والمزامنة ولا يحمل أرقامًا ثابتة |
| المبيعات | `features/invoices/invoice_workspace_page.dart` | `AccountingApi` + `SalesInvoiceOutbox` + سجل الفواتير المحلي |
| مرتجعات المبيعات والمشتريات | `features/returns/return_workspace_page.dart` | `ReturnsApi` ثم تحديث المخزون والقيد عبر الخادم |
| المشتريات | `features/purchases/purchase_workspace_page.dart` | `AccountingApi` + `PurchaseOutbox` + سجل المشتريات المحلي |
| العملاء والموردون | `features/modules/module_workspace_page.dart` | `CatalogSyncApi` و`AccountingApi` لكشوف الأطراف |
| الأصناف والوحدات | `features/modules/module_workspace_page.dart` | `CatalogSyncApi` وملفات `features/products` |
| المخزون والاستعلام | `features/accounting/product_inquiry_page.dart` و`features/inventory/stock_operations_page.dart` | `CatalogSyncApi` و`StockOperationsApi` وoutbox المخزون |
| الصندوق والسندات | `features/accounting/cashbox_page.dart` و`features/modules/module_workspace_page.dart` | `AccountingApi`؛ سند القبض والصرف يقيدان الحساب المقابل |
| شجرة الحسابات | `features/accounting/chart_accounts_page.dart` | `ChartAccountsApi` |
| القيد اليومي | `features/accounting/simple_journal_page.dart` | `AccountingApi`؛ يجب أن يتساوى المدين والدائن قبل الحفظ |
| الأرصدة الافتتاحية | `features/accounting/opening_balances_page.dart` | `AccountingApi` مع الفرع والحسابات الفعلية |
| التحويلات | `features/accounting/account_transfer_page.dart` | `AccountingApi` |
| كشوف الحساب | `features/accounting/account_statement_page.dart` | `AccountingApi` مع فتح المستند المصدر |
| التقارير | `features/accounting/financial_reports_page.dart` | بيانات الخادم المحاسبية، لا تعيد حساب الربح داخل الواجهة |
| الرواتب والموظفون | `features/payroll/employee_payroll_page.dart` و`payroll_run_page.dart` | `PayrollApi` + `PayrollOutbox` |
| المستخدمون والفروع | `features/administration/administration_page.dart` | `AdministrationApi` والصلاحيات القادمة من الجلسة |
| النسخ الاحتياطية | `features/backup/backup_page.dart` | `BackupApi` |
| المزامنة | `features/sync/realtime_sync_coordinator.dart` | نقطة الربط المركزية لجميع الأجهزة |
| الهوية والإعدادات | `features/settings/identity_settings_page.dart` | `IdentityApi` |
| واتساب | `features/whatsapp/whatsapp_page.dart` | `WhatsappApi` |

## الغلاف والتنقل

- `NineSoftWorkspaceShell` يقرر شكل الهاتف والكمبيوتر ويفتح الصفحات الحقيقية.
- `NineSoftModuleTaxonomy` يرتب الأقسام للعرض فقط، ولا يقرر الصلاحيات أو المحاسبة.
- `NineSoftModuleAccessPolicy` يطبق صلاحيات المستخدم، فلا تتجاوزه أثناء التصميم.
- اجعل كل زر جديد يستدعي المسار أو callback الموجود بدل إنشاء صفحة منفصلة غير مربوطة.

