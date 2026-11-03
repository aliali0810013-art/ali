# تدقيق المطابقة البصرية — NineSoft Pixel-Perfect Recovery

التاريخ: 2026-11-03
الفرع: `ui-redesign`
الحالة المحفوظة قبل التصحيح: `c945b72bf94310c94981ac50ca03129d51ee8c7e`
فرع الحفظ: `ui-redesign-before-pixel-perfect-20261103`

## الحكم الرسمي

العمل البرمجي متقدم، لكن المطابقة البصرية المطلوبة غير مكتملة وغير مثبتة.

الصور العشرون المرفقة هي مصدر الحقيقة الوحيد للتصميم. لا يجوز استخدام Goldens مولدة من التنفيذ الحالي كبديل عن الصور الأصلية.

## الصور الأصلية

كل الصور الأصلية المستلمة مقاسها 941x1672. يجب حفظ النسخة الأصلية غير المعدلة لاحقًا تحت:
`apps/nizami_app/test/reference_baselines/source/`

ويُنشأ لكل صورة مشتق viewport للاختبار تحت:
`apps/nizami_app/test/reference_baselines/normalized/`

لا يُعتبر الملف المشتق بديلاً عن المصدر الأصلي؛ يجب أن يبقى SHA-256 للمصدر مثبتًا.

| # | الشاشة | اسم ملف المصدر المستلم | SHA-256 | مسار الشاشة | الحالة |
|---|---|---|---|---|---|
| 1 | المبيعات / فاتورة بيع | 06_53_38 م-1.png | 6bcdae78253e0ae6c6089e46e92166d34a36e71f43f830463b26cced01daf64d | invoices/invoice_workspace_page.dart | يوجد Actual حالي، لكنه غير مطابق وغير مقارن بمصدر أصلي داخل CI |
| 2 | المشتريات | 06_53_39 م-2.png | 6094c9c0f35f191d8325ba0fe5a542bfc083f104cde6a60f6dcca44ae2314821 | purchases/purchase_workspace_page.dart | غير مثبت |
| 3 | المخزون والأصناف | 06_53_41 م-3.png | 48da04449e02e924ba958fb19db5e6476aba207e4a27e11a7dd2e721c78dff7e | modules/module_workspace_page.dart | يوجد Golden حالة فارغة فقط، غير صالح كدليل للمصدر |
| 4 | العملاء | 06_53_42 م-4.png | 6ba42772b3be8c35dd1f329f93569734650a506dacb0ed2623e3439207e0b2b0 | modules/module_workspace_page.dart | غير مثبت |
| 5 | الموردون | 06_53_44 م-5.png | 7f221f3009930bb83a62c53fae17b96a020d31cd2297e8df6e32267c3b7a866d | modules/module_workspace_page.dart | غير مثبت |
| 6 | شجرة الحسابات | 06_53_45 م-6.png | 7388d71beffcb18049b80598365e9b97fe486efd8e7075496a5e347a7c4953c7 | accounting/chart_accounts_page.dart | غير مثبت |
| 7 | القيود اليومية | 06_53_47 م-7.png | 82f4f9f804fca980735a581bf35da5fe0f72ca23ab8a0e5fd25e237d98c8db97 | accounting/simple_journal_page.dart | يوجد Actual حالي فقط، بلا Baseline أصلي |
| 8 | سندات القبض والصرف | 06_53_48 م-8.png | 214420f40d25a80d5def520ac46694f8cb81738a7df3079fe3cd909590b79d31 | modules/module_workspace_page.dart | غير مثبت |
| 9 | الصندوق والحسابات البنكية | 06_53_49 م-9.png | 8fbb0e4dce206c4d2e84f8cd73ef11a1439302b8e4b0f90d32577ceb6e23a19f | accounting/cashbox_page.dart | غير مثبت |
| 10 | الإعدادات والتحكم | 06_53_50 م-10.png | d2f38051552d2f41b8903c78aad186ae7d41790818d32d3795062dc783687b1a | settings/identity_settings_page.dart | غير مثبت |
| 11 | التقارير والتحليلات | 07_09_00 م-1.png | 5c09bb8d33ee63e8175eab4c8f911373b172f0d6ac63dc515af9b7b46869c753 | dashboard/section_hub_page.dart | غير مثبت |
| 12 | الأرباح والخسائر | 07_09_14 م-2.png | 6d81afd28905b1e606a85a2b6d362fab7108ab12e4a6e30cbf9f839807591934 | accounting/financial_reports_page.dart | غير مثبت |
| 13 | ميزان المراجعة | 07_09_15 م-3.png | d05e99bba1b54d2aa702f28be5edc4d422ea7662cc843924abfdc4580c8793d0 | accounting/financial_reports_page.dart | غير مثبت |
| 14 | دفتر الأستاذ | 07_09_16 م-4.png | 603183795387a9de6ef76a1380d74b14d69c50ce7064149ef841fecbe57f88de | accounting/account_statement_page.dart | غير مثبت |
| 15 | مرتجع مبيعات | 07_09_18 م-5.png | dd47cac0c0b1ae50b2be597640b0f92bcfb94f47da80788d2f29056f0becaa4f | returns/return_workspace_page.dart | غير مثبت |
| 16 | الجرد وتسوية المخزون | 07_09_19 م-6.png | 94bf1a9ba25cb78404248e75ccbdf379c9313c5029c316cec8101ca505d18d18 | inventory/stock_operations_page.dart | غير مثبت |
| 17 | تحويلات WASL | 07_09_20 م-7.png | 3dcbac12f9ddc94a3ec33ee1158b2e0a6b4b532ffa75c4c1f65943eb3a1f057c | wasl/wasl_page.dart | غير مثبت |
| 18 | واتساب | 07_09_21 م-8.png | 699b69e745703d1ea9490b3c2519202ab59e0b9371d89f946b48169dd102f0f9 | whatsapp/whatsapp_page.dart | غير مثبت |
| 19 | المزامنة والنسخ الاحتياطي | 07_09_24 م-9.png | 2127b668e7049925ca654f27ba7e6a081ade84cb63891313827eaaa47efededc | backup/backup_page.dart | غير مثبت |
| 20 | المستخدمون والصلاحيات | 07_09_26 م-10.png | dab7dbf0075aa1955b529a7e05132ea4cef1c3134220aab51981eec831dcc543 | administration/administration_page.dart | غير مثبت |

## تصحيح عدد الأدلة

الـCI السابق رفع ستة ملفات Screenshot، لكنها ليست ست شاشات من الصور العشرين مثبتة:
- Dashboard Desktop
- Dashboard Mobile
- Sales Desktop
- Sales Phone
- Journal Phone
- Products Desktop Empty

والـDashboard ليس ضمن الصور العشرين أصلًا، وProducts Empty لا يطابق صورة الصنف المعبأة، وكل هذه الصور مولدة من التنفيذ الحالي.

لذلك عند تطبيق معيار Baseline الأصلي + Actual + Diff، **عدد الشاشات المثبتة حاليًا = 0/20**.
وبالتالي لا توجد 14 شاشة فقط بلا دليل؛ بل الصور العشرون كلها غير مثبتة بالمقياس المطلوب. هذا التصحيح يمنع استمرار ادعاء خاطئ.

## سبب رفض --update-goldens

كان Workflow يشغّل:
`flutter test test/reference_screenshot_test.dart --dart-define=NINESOFT_CAPTURE_SCREENSHOTS=true --update-goldens`

هذا يجعل التنفيذ الحالي يكتب ملف Expected بنفسه. نجاح الاختبار بعد ذلك لا يثبت أي تطابق مع الصور الأصلية.

السياسة الجديدة:
1. يمنع `--update-goldens` في CI.
2. المصدر الأصلي ثابت وغير قابل للتحديث من الاختبار.
3. Actual يولد في كل Run.
4. Diff يولد من Source/Normalized مقابل Actual.
5. الفشل يُصلح في الواجهة، وليس بتغيير Expected.
6. تحديث Baseline يحتاج تغييرًا مقصودًا لملف المصدر مع SHA جديد ومراجعة بشرية.

## أول مثال حقيقي قبل التصحيح

الشاشة: المبيعات / الهاتف.
Actual: `ninesoft-phone-sales.png` من آخر CI.
Expected: الصورة الأصلية `06_53_38 م-1.png` بعد Normalization مؤقت للمقاس 390x844 لأغراض إظهار الفارق فقط.
القياس الأولي:
- MAE: 47.44
- RMSE: 90.43
- Pixels with delta > 12: 51.25%

هذه النتيجة تثبت أن النسخة الحالية ليست Pixel-Perfect.

## ترتيب إعادة التنفيذ

1. المبيعات / فاتورة البيع.
2. المشتريات.
3. مرتجع المبيعات.
4. سندات القبض والصرف.
5. القيود اليومية.
6. العملاء.
7. الموردون.
8. المخزون والأصناف.
9. الجرد وتسوية المخزون.
10. شجرة الحسابات.
11. الصندوق والحسابات البنكية.
12. دفتر الأستاذ.
13. ميزان المراجعة.
14. الأرباح والخسائر.
15. التقارير والتحليلات.
16. تحويلات WASL.
17. واتساب.
18. المزامنة والنسخ الاحتياطي.
19. المستخدمون والصلاحيات.
20. الإعدادات والتحكم.

## تعريف الاكتمال

لا تنتقل أي شاشة إلى DONE إلا مع:
- Baseline أصلي ثابت.
- شاشة مرتبطة بالبيانات الحقيقية.
- Screenshot بالمقاس المعتمد.
- Diff/Overlay.
- نتيجة مقارنة موثقة.
- اختبار وظيفي.
- إثبات عدم تغيير المحرك المحاسبي أو عقود البيانات القديمة.

## أول شاشة

بدأ التصحيح من `المبيعات / فاتورة البيع`.
طبقة العرض المستهدفة:
`apps/nizami_app/lib/src/features/invoices/presentation/sales_invoice_reference_view.dart`

مع بقاء:
`SalesInvoicePresentationAdapter -> InvoiceDocument/API/Outbox/Sync`
دون تغيير.
