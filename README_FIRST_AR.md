# حزمة تطوير واجهة NineSoft

هذه الحزمة مخصصة لبناء واجهة جديدة فوق نظام NineSoft الحالي، مع إبقاء المحاسبة والمخزون والمزامنة وواجهات API كما هي.

## من أين تبدأ

1. افتح المجلد `apps/nizami_app` كمشروع Flutter.
2. نفذ:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome --dart-define=NINESOFT_API_BASE_URL=https://ninesoft.qodynex.tech/api/v1
```

3. عدّل ملفات العرض داخل `apps/nizami_app/lib/src/features` وملفات الشكل المشتركة داخل `apps/nizami_app/lib/src/theme`.
4. لا تغيّر أسماء حقول API أو منطق المزامنة أو المحاسبة.

## مسار تشغيل التطبيق

```text
lib/main.dart
  -> lib/src/app.dart
  -> تسجيل الدخول واستعادة الجلسة
  -> NineSoftWorkspaceShell
  -> الصفحة الفعلية للقسم
  -> Api class الخاص بالقسم
  -> JsonTransport
  -> https://ninesoft.qodynex.tech/api/v1
```

## الملفات الأهم لتغيير الشكل

- الرئيسية: `lib/src/features/dashboard/ninesoft_reference_dashboard.dart`
- غلاف الهاتف والكمبيوتر: `lib/src/features/navigation/ninesoft_workspace_shell.dart`
- القائمة والتنقل: `lib/src/features/navigation/ninesoft_app_launcher.dart`
- تصنيف الأقسام: `lib/src/features/navigation/ninesoft_module_taxonomy.dart`
- المبيعات: `lib/src/features/invoices/invoice_workspace_page.dart`
- المشتريات: `lib/src/features/purchases/purchase_workspace_page.dart`
- الوحدات العامة والعملاء والموردون والسندات: `lib/src/features/modules/module_workspace_page.dart`
- شجرة الحسابات: `lib/src/features/accounting/chart_accounts_page.dart`
- كشف الحساب: `lib/src/features/accounting/account_statement_page.dart`
- القيود: `lib/src/features/accounting/simple_journal_page.dart`
- التقارير: `lib/src/features/accounting/financial_reports_page.dart`
- المخزون: `lib/src/features/accounting/product_inquiry_page.dart`
- الرواتب: `lib/src/features/payroll/employee_payroll_page.dart`
- الثيم والمكونات المشتركة: `lib/src/theme/`

## قواعد إلزامية

- الواجهة فقط: غيّر Widget وترتيب الحقول والألوان والاستجابة للشاشات.
- استخدم callbacks وApi classes الموجودة؛ لا تنشئ حفظًا وهميًا أو بيانات تجريبية داخل الصفحات.
- لا تحذف `RealtimeSyncCoordinator` أو outbox أو التخزين المحلي.
- لا تغيّر حقول `supplier_name` و`contact_id` و`local_operation_id` و`restore_generation` و`operation_created_at`.
- لا تغيّر طريقة إنشاء القيود أو تقييم المخزون أو حذف المستندات.
- لا تضع كلمة مرور أو token أو ملف `.env` داخل GitHub.
- عند تسليم الواجهة أعد المجلد كاملًا ZIP مع ملف `CHANGES_AR.md` يذكر كل الملفات المعدلة.

راجع أيضًا:

- `UI_SCREEN_MAP_AR.md`
- `API_AND_SYNC_MAP_AR.md`
- `RETURN_CHECKLIST_AR.md`

