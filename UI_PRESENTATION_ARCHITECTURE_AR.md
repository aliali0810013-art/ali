# فصل الواجهة الجديدة عن المحرك — NineSoft Presentation Architecture

## المسار الإلزامي

واجهة المستخدم الجديدة
↓
ViewModel / Presentation State
↓
Presentation Adapter / Mapper
↓
الخدمات والمحرك المحاسبي الحالي
↓
API / Database / Sync

## القاعدة

الواجهة الجديدة لا تعتمد على ترتيب الحقول القديم. ترتيب الشاشة، التجميع، البطاقات، الجداول، البحث، والخطوات يمكن تغييره بحرية داخل طبقة العرض.

## ما يبقى ثابتًا خلف Adapter

- أسماء ومعاني الحقول المحاسبية الحالية.
- InvoiceDocument وInvoiceLine وصيغ التخزين الحالية ما لم يعتمد Migration منفصل لاحقًا.
- API payloads الحالية.
- Outbox / Sync / Restore semantics.
- أرقام العمليات ومعرفات idempotency.
- حساب الكميات الدقيقة والأسعار والخصومات في طبقة المجال الحالية.

## دعم البيانات القديمة

1. قراءة السجل الحالي بالنموذج القديم/الحالي.
2. تحويله إلى ViewModel عند العرض.
3. تحريره في الواجهة الجديدة.
4. تحويل ViewModel إلى نموذج المجال الحالي عند الحفظ.
5. الاحتفاظ بأي حقول لا تظهر في الشاشة ضمن Adapter وعدم إسقاطها.
6. اختبار Round-Trip لكل مستند رئيسي قبل اعتماد إعادة التصميم.

## التنفيذ الأول

تم بدء فصل المبيعات:
- sales_invoice_view_model.dart
- sales_invoice_adapter.dart
- sales_invoice_presentation_adapter_test.dart
- InvoiceWorkspacePage._readInvoice() يمر الآن عبر Adapter.

المراحل التالية تطبق نفس النمط على:
- Purchase invoice
- Sales/Purchase returns
- Journal entry
- Receipt/payment voucher
- Customer/supplier/product editors
