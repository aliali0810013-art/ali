# خريطة API والمزامنة

## عنوان API

العنوان الافتراضي موجود داخل الكود:

```text
https://ninesoft.qodynex.tech/api/v1
```

ولتغيير بيئة البناء دون تعديل المصدر:

```powershell
flutter run -d chrome --dart-define=NINESOFT_API_BASE_URL=https://example.com/api/v1
```

التوثيق يتم عبر token الجلسة. لا تحفظ token داخل الكود أو GitHub.

## طبقة النقل

- `lib/src/auth/json_transport.dart`: العقدة العامة للطلبات.
- `json_transport_io.dart`: Android وWindows.
- `json_transport_web.dart`: الويب.
- `http_auth_api.dart`: الدخول والخروج والتحقق من الجلسة وتغيير كلمة المرور.

## عملاء API

- `AccountingApi`: البيع والشراء والسندات والقيود والكشوف والتقارير والتحويلات والمرتجعات.
- `ChartAccountsApi`: شجرة الحسابات.
- `CatalogSyncApi`: الأصناف والعملاء والموردون والوحدات والمخزون.
- `BusinessDocumentApi`: المستندات العامة.
- `StockOperationsApi`: عمليات المخزون.
- `PayrollApi`: الموظفون والرواتب والسلف والصرف.
- `AdministrationApi`: المستخدمون والصلاحيات والفروع ونسخ العملاء.
- `BackupApi`: النسخ الاحتياطية والاستعادة.
- `IdentityApi`: هوية المنشأة والطباعة.
- `WhatsappApi`: إرسال الفواتير.
- `ReturnsApi`: المرتجعات المرتبطة والمباشرة.

## دورة حفظ العملية

```text
المستخدم يضغط حفظ
  -> الصفحة تتحقق من المدخلات
  -> يحفظ الطلب محليًا عند دعم العمل دون إنترنت
  -> يضاف إلى outbox بنفس local_operation_id
  -> Api class يرسله إلى الخادم
  -> الخادم ينفذ المستند والقيد والمخزون والطرف داخل معاملة واحدة
  -> الخادم يسجل change event
  -> RealtimeSyncCoordinator يجلب sync/changes
  -> InvoiceDeltaRouter والمخازن المحلية تحدث بقية الشاشات
```

لا تستبدل هذا المسار بطلب HTTP مباشر داخل Widget.

## ملفات المزامنة التي لا تُحذف

- `features/sync/realtime_sync_coordinator.dart`
- `features/sync/invoice_delta_router.dart`
- `features/sync/sales_invoice_outbox.dart`
- `features/sync/purchase_outbox.dart`
- `features/sync/catalog_outbox.dart`
- `features/sync/stock_operation_outbox.dart`
- `features/sync/payroll_outbox.dart`
- `features/sync/restore_snapshot_store.dart`
- `features/sync/restore_submission_policy.dart`
- `features/sync/pending_invoice_sync.dart`

## حقول لا تُعاد تسميتها

```text
local_operation_id
restore_generation
operation_created_at
contact_id
supplier_name
branch_id
tenant_id
```

الواجهة تستطيع تغيير العناوين العربية الظاهرة فقط، لكن مفاتيح JSON تبقى كما هي.

