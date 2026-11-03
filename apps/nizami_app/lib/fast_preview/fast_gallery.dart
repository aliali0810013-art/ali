part of 'fast_screens.dart';

extension _FastGalleryCore on _FastPreviewScreenState {
  Widget _sales() => _group([
    _panel('تحرير فاتورة مبيعات', Icons.receipt_long_outlined, [
      _fields(const [
        _F('العميل *', 'مؤسسة النور للتجارة', Icons.groups_outlined),
        _F('رقم الفاتورة *', 'INV-01542', Icons.description_outlined),
        _F('التاريخ *', '2025/01/30', Icons.calendar_today_outlined),
        _F('المخزن *', 'المخزن الرئيسي', Icons.warehouse_outlined),
        _F('مندوب المبيعات', 'أحمد سالم', Icons.person_outline),
        _F('طريقة الدفع', 'نقدي', Icons.account_balance_wallet_outlined),
      ], count: 2),
    ]),
    _pair(
      _search('بحث عن صنف (الاسم أو الباركود أو الكود)...'),
      _buttons(const ['مسح باركود']),
    ),
    _panel('أصناف فاتورة المبيعات', Icons.shopping_bag_outlined, [
      _table(const ['الصنف', 'الوحدة', 'الكمية', 'السعر', 'الخصم', 'الإجمالي'], const [
        ['لابتوب 15 بوصة', 'حبة', '30', '800.00', '10%', '21,600.00'],
        ['ماوس لاسلكي', 'حبة', '30', '95.00', '0%', '2,850.00'],
        ['لوحة مفاتيح', 'حبة', '5', '280.00', '5%', '1,260.00'],
        ['شاشة 24 بوصة', 'حبة', '6', '760.00', '0%', '4,560.00'],
      ]),
      _buttons(const ['إضافة صنف', 'مسح باركود']),
    ]),
    _pair(
      _panel('ملاحظات وتسوية', Icons.edit_note_outlined, [
        _fields(const [
          _F('الملاحظات', 'أضف ملاحظات على الفاتورة...', Icons.edit_outlined),
          _F('نوع السعر', 'سعر البيع', Icons.sell_outlined),
          _F('العملة', 'ريال يمني YER', Icons.monetization_on_outlined),
          _F('شامل الضريبة', 'نعم', Icons.percent_outlined),
        ], count: 2),
      ]),
      _panel('ملخص الفاتورة', Icons.calculate_outlined, [
        _stats(const [
          _S('إجمالي الأصناف', '30,270.00', Icons.layers_outlined),
          _S('الخصم', '-2,160.00', Icons.discount_outlined),
          _S('الضريبة', '4,216.50', Icons.percent_outlined),
          _S('الإجمالي النهائي', '32,326.50', Icons.receipt_outlined),
          _S('المبلغ المدفوع', '20,000.00', Icons.paid_outlined),
          _S('المتبقي', '12,326.50', Icons.schedule_outlined),
        ], columns: 2),
      ]),
    ),
    _buttons(const ['حفظ', 'طباعة', 'PDF', 'مشاركة واتساب']),
  ]);

  Widget _purchases() => _group([
    _panel('فاتورة مشتريات', Icons.description_outlined, [
      _choices(const ['مسودة', 'فاتورة جديدة', 'سجل المشتريات']),
      _fields(const [
        _F('المورد *', 'مؤسسة الشرق للتوريدات', Icons.groups_outlined),
        _F('رقم الفاتورة *', 'PV-2025-01542', Icons.numbers_outlined),
        _F('التاريخ *', '2025/01/30', Icons.calendar_today_outlined),
        _F('المستودع *', 'المستودع الرئيسي', Icons.warehouse_outlined),
        _F('نوع الدفع', 'آجل', Icons.paid_outlined),
        _F('رقم المرجع', 'PO-7789', Icons.description_outlined),
      ]),
    ]),
    _panel('إضافة الأصناف', Icons.inventory_2_outlined, [
      _pair(_search('بحث باسم الصنف أو الكود أو الباركود'), _buttons(const ['مسح باركود'])),
      _fields(const [
        _F('الصنف', 'لابتوب 15.6 بوصة', Icons.search_rounded),
        _F('الوحدة', 'قطعة', Icons.layers_outlined),
        _F('الكمية', '10', Icons.numbers_outlined),
        _F('سعر الشراء', '2,350.00', Icons.payments_outlined),
        _F('آخر سعر شراء', '2,280.00', Icons.history_rounded),
        _F('سعر المورد', '2,350.00', Icons.sell_outlined),
      ]),
      _buttons(const ['إضافة للصنف', 'مسح']),
      _table(const ['#', 'الصنف', 'الوحدة', 'الكمية', 'سعر الشراء', 'الخصم', 'الإجمالي'], const [
        ['1', 'لابتوب أعمال 15.6', 'قطعة', '10.00', '2,350.00', '5%', '22,325.00'],
        ['2', 'شاشة LED 24', 'قطعة', '15.00', '610.00', '0%', '9,150.00'],
        ['3', 'ماوس لاسلكي', 'قطعة', '20.00', '55.00', '10%', '990.00'],
      ]),
    ]),
    _stats(const [
      _S('الإجمالي الفرعي', '32,465', Icons.layers_outlined),
      _S('الخصم', '1,475', Icons.percent_outlined),
      _S('الضريبة', '4,648.50', Icons.balance_outlined),
      _S('الشحن', '350.00', Icons.local_shipping_outlined),
      _S('التكلفة النهائية', '35,988.50', Icons.calculate_outlined),
      _S('المدفوع', '10,000', Icons.paid_outlined),
      _S('المتبقي', '25,988.50', Icons.account_balance_wallet_outlined),
    ]),
    _buttons(const ['حفظ', 'ترحيل', 'طباعة', 'PDF', 'إضافة مرتجع']),
  ]);

  Widget _returns() => _group([
    _fields(const [
      _F('العميل *', 'مؤسسة النور للتجارة', Icons.people_outlined),
      _F('رقم فاتورة البيع *', 'INV-01542', Icons.receipt_long_outlined),
      _F('التاريخ *', '2025/01/30', Icons.calendar_today_outlined),
      _F('المخزن *', 'المخزن الرئيسي', Icons.warehouse_outlined),
      _F('سبب المرتجع *', 'منتج تالف / عيب تصنيع', Icons.sell_outlined),
    ], count: 2),
    _pair(_search('بحث عن صنف (الاسم أو الباركود)...'), _buttons(const ['مسح باركود'])),
    _panel('الأصناف المرتجعة', Icons.assignment_return_outlined, [
      _table(const ['الصنف', 'الكمية الأصلية', 'المرتجعة', 'الوحدة', 'السعر', 'خصم', 'الإجمالي', 'الحالة'], const [
        ['لابتوب 15 بوصة', '30', '2', 'حبة', '800', '10%', '1,600', 'مقبول'],
        ['ماوس لاسلكي', '30', '3', 'حبة', '95', '0%', '285', 'مقبول'],
        ['لوحة مفاتيح', '5', '2', 'حبة', '280', '5%', '560', 'جزئي'],
        ['شاشة 24 بوصة', '6', '2', 'حبة', '760', '0%', '1,520', 'مقبول'],
      ]),
      _buttons(const ['إضافة صنف', 'تعديل كمية']),
    ]),
    _pair(
      _panel('بيانات الاسترداد', Icons.edit_note_outlined, [
        _fields(const [
          _F('ملاحظات', 'أضف ملاحظات عن سبب الإرجاع...', Icons.edit_outlined),
          _F('طريقة الاسترداد', 'رصيد حساب العميل', Icons.account_balance_wallet_outlined),
        ], count: 1),
        _switch('إعادة المبلغ إلى رصيد العميل'),
      ]),
      _panel('ملخص المرتجع', Icons.summarize_outlined, [
        _stats(const [
          _S('إجمالي المرتجع', '3,965.00', Icons.layers_outlined),
          _S('الضريبة 15%', '594.75', Icons.percent_outlined),
          _S('المبلغ المسترد', '4,559.75', Icons.wallet_outlined),
          _S('الرصيد بعد الخصم', '27,670.25', Icons.account_balance_wallet_outlined),
        ], columns: 2),
      ]),
    ),
    _buttons(const ['حفظ', 'ترحيل', 'طباعة', 'PDF', 'إشعار دائن']),
  ]);

  Widget _vouchers() => _group([
    _choices(const ['سند قبض', 'سند صرف']),
    _panel('بيانات السند', Icons.receipt_long_outlined, [
      _fields(const [
        _F('رقم السند *', 'RC-0001543', Icons.tag_outlined),
        _F('التاريخ *', '2026/01/30', Icons.calendar_month_outlined),
        _F('الحساب *', 'الصندوق الرئيسي - 11101', Icons.account_balance_wallet_outlined),
        _F('العميل / المورد *', 'مؤسسة النور التجارية', Icons.person_outline),
        _F('طريقة الدفع *', 'تحويل بنكي', Icons.account_balance_outlined),
        _F('المبلغ *', '123,400.00', Icons.calculate_outlined),
        _F('العملة', 'ريال يمني', Icons.payments_outlined),
        _F('الوصف', 'تحصيل دفعة من الفاتورة', Icons.notes_outlined),
        _F('المرجع', 'INV-00882', Icons.description_outlined),
        _F('المرفق', 'INV-00882.pdf', Icons.attach_file_outlined),
      ], count: 2),
    ]),
    _panel('ملخص السند', Icons.calculate_outlined, [
      _stats(const [
        _S('مبلغ السند', '123,400', Icons.paid_outlined),
        _S('الرصيد قبل', '333,600', Icons.account_balance_wallet_outlined),
        _S('الرصيد بعد', '457,000', Icons.trending_up_rounded),
        _S('حالة السند', 'مسودة', Icons.watch_later_outlined),
      ]),
    ]),
    _panel('آخر السندات', Icons.history_outlined, [
      _table(const ['رقم السند', 'التاريخ', 'العميل / المورد', 'المبلغ', 'النوع'], const [
        ['RC-0001543', '2026/01/30', 'مؤسسة النور', '123,400', 'قبض'],
        ['PV-0000871', '2026/01/28', 'شركة الإمداد', '67,300', 'صرف'],
        ['RC-0001542', '2026/01/26', 'العميل الممتاز', '45,000', 'قبض'],
        ['PV-0000870', '2026/01/25', 'مصروفات تشغيل', '18,750', 'صرف'],
      ]),
    ]),
    _buttons(const ['حفظ', 'ترحيل', 'طباعة', 'PDF', 'مشاركة']),
  ]);

  Widget _journal() => _group([
    _search('بحث في القيود: رقم القيد، المرجع، الوصف، الحساب'),
    _panel('إنشاء قيد يومية', Icons.library_books_outlined, [
      _fields(const [
        _F('رقم القيد *', '#1543', Icons.tag_rounded),
        _F('التاريخ *', '2025-01-30', Icons.calendar_month_outlined),
        _F('المرجع', 'INV-882', Icons.description_outlined),
        _F('الوصف *', 'إثبات إيراد مبيعات آجلة', Icons.notes_rounded),
        _F('مركز التكلفة', 'مركز المبيعات', Icons.account_tree_outlined),
      ]),
      _table(const ['#', 'الحساب', 'الوصف', 'مدين', 'دائن', 'ملاحظات'], const [
        ['1', '1201 العملاء', 'مبيعات آجلة', '456,800.00', '-', 'فاتورة 882'],
        ['2', '4101 إيرادات المبيعات', 'إيراد مبيعات', '-', '397,217.39', '-'],
        ['3', '2201 ضريبة القيمة المضافة', 'ضريبة', '-', '59,582.61', 'VAT 15%'],
      ]),
      _buttons(const ['إضافة سطر', 'إرفاق مستند', 'فحص التوازن']),
    ]),
    _stats(const [
      _S('إجمالي المدين', '456,800.00', Icons.south_east_rounded),
      _S('إجمالي الدائن', '456,800.00', Icons.north_east_rounded),
      _S('الفرق', '0.00', Icons.balance_outlined),
      _S('الحالة', 'متوازن', Icons.check_circle_outline),
    ]),
    _buttons(const ['حفظ كمسودة', 'ترحيل القيد', 'طباعة']),
    _pair(
      _panel('آخر القيود', Icons.history_rounded, [
        _table(const ['القيد', 'التاريخ', 'المبلغ', 'الحالة'], const [
          ['#1542', '2025/01/29', '456,800', 'مرحل'],
          ['#1541', '2025/01/28', '67,300', 'مرحل'],
          ['#1540', '2025/01/28', '184,500', 'مسودة'],
        ]),
      ]),
      _panel('القوالب المحاسبية', Icons.layers_outlined, [
        _buttons(const ['قيد مبيعات قياسي', 'قيد مصروفات', 'قيد إهلاك', 'قيد رواتب']),
      ]),
    ),
  ]);

  Widget _customers() => _group([
    _search('بحث عن عميل (الاسم، الجوال، الرقم الضريبي...)'),
    _panel('إضافة / تعديل عميل', Icons.person_add_alt_outlined, [
      _fields(const [
        _F('اسم العميل *', 'شركة النور للتجارة', Icons.person_outline),
        _F('الجوال *', '+966 50 123 4567', Icons.phone_outlined),
        _F('العنوان', 'حي العليا، شارع الملك فهد', Icons.location_on_outlined),
        _F('المدينة', 'الرياض', Icons.location_city_outlined),
        _F('الرقم الضريبي', '300123456700003', Icons.description_outlined),
        _F('حد الائتمان', '100,000.00', Icons.savings_outlined),
        _F('الرصيد الافتتاحي', '5,000.00', Icons.balance_outlined),
        _F('شروط السداد', '30 يوم', Icons.calendar_month_outlined),
        _F('حالة الحساب', 'نشط', Icons.check_circle_outline),
      ], count: 2),
      _buttons(const ['حفظ', 'كشف حساب', 'إرسال واتساب', 'إضافة فاتورة', 'تحصيل']),
    ]),
    _stats(const [
      _S('إجمالي الفواتير', '200,000', Icons.receipt_long_outlined, foot: '32 فاتورة'),
      _S('المدفوع', '141,600', Icons.check_circle_outline, foot: '24 فاتورة مدفوعة'),
      _S('المتبقي', '58,400', Icons.account_balance_wallet_outlined, foot: '8 فواتير مفتوحة'),
      _S('المتأخرات', '12,500', Icons.warning_amber_outlined, foot: '3 فواتير متأخرة'),
    ]),
    _panel('آخر العمليات (كشف حساب مختصر)', Icons.layers_outlined, [
      _table(const ['التاريخ', 'البيان', 'مدين', 'دائن', 'الرصيد'], const [
        ['2025/01/30', 'فاتورة مبيعات #1542', '12,000', '-', '63,400'],
        ['2025/01/28', 'تحصيل من العميل', '-', '20,000', '51,400'],
        ['2025/01/25', 'فاتورة مبيعات #1536', '8,500', '-', '71,400'],
        ['2025/01/20', 'إشعار خصم', '500', '-', '71,900'],
        ['2025/01/15', 'تحصيل من العميل', '-', '15,000', '71,400'],
      ]),
    ]),
  ]);

  Widget _suppliers() => _group([
    _stats(const [
      _S('إجمالي المشتريات', '1,248,500', Icons.shopping_cart_outlined),
      _S('إجمالي المسدد', '980,000', Icons.payments_outlined),
      _S('الرصيد المستحق', '268,500', Icons.wallet_outlined),
      _S('آخر تاريخ شراء', '30 يناير', Icons.calendar_today_outlined),
    ]),
    _panel('إضافة / تعديل مورد', Icons.person_add_alt_outlined, [
      _fields(const [
        _F('اسم المورد *', 'مؤسسة الجزيرة التجارية', Icons.person_outline),
        _F('رقم الهاتف', '+966 55 123 4567', Icons.call_outlined),
        _F('العنوان', 'الرياض - حي الورود', Icons.location_on_outlined),
        _F('الرقم الضريبي', '300987654300003', Icons.description_outlined),
        _F('شروط الدفع', '30 يوم', Icons.calendar_month_outlined),
        _F('الحد الائتماني', '500,000.00', Icons.savings_outlined),
        _F('الرصيد الافتتاحي', '0.00', Icons.balance_outlined),
        _F('الحساب المرتبط', '2140 - الموردون', Icons.account_tree_outlined),
        _F('الحالة', 'نشط', Icons.check_circle_outline),
      ], count: 2),
      _buttons(const ['حفظ', 'كشف حساب', 'إنشاء فاتورة شراء', 'سداد', 'مراسلة']),
    ]),
    _pair(
      _panel('آخر سعر شراء', Icons.sell_outlined, [
        _note('مكيف سبليت 1.5 حصان: آخر سعر 1,520 ر.س'),
        _note('تم الشراء في 28 يناير 2025، فاتورة PO-4521'),
      ]),
      _panel('أهم الأصناف الموردة', Icons.inventory_2_outlined, [
        _table(const ['الصنف', 'إجمالي مشتريات'], const [
          ['مكيف سبليت 1.5 حصان', '320,000'],
          ['شاشة LED 55 بوصة', '210,500'],
          ['ثلاجة 16 قدم', '146,000'],
        ]),
      ]),
    ),
    _panel('كشف المشتريات / الرصيد المستحق', Icons.receipt_long_outlined, [
      _table(const ['التاريخ', 'النوع', 'رقم المستند', 'القيمة', 'المدفوع', 'الرصيد'], const [
        ['30 يناير', 'فاتورة شراء', '#PO-4521', '152,000', '0', '268,500'],
        ['28 يناير', 'سداد', '#PY-3187', '-100,000', '100,000', '116,500'],
        ['25 يناير', 'فاتورة شراء', '#PO-4510', '116,500', '0', '216,500'],
      ]),
    ]),
  ]);

  Widget _products() => _group([
    _panel('إضافة / تعديل صنف', Icons.inventory_2_outlined, [
      _pair(
        Container(
          height: 138,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F1FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.headphones_rounded, size: 105, color: _navy),
        ),
        _fields(const [
          _F('اسم الصنف *', 'سماعة رأس لاسلكية', Icons.inventory_2_outlined),
          _F('كود الصنف SKU *', 'HP-1001', Icons.tag_outlined),
          _F('الباركود', '6224009871234', Icons.qr_code_rounded),
        ], count: 1),
      ),
      _fields(const [
        _F('التصنيف *', 'إلكترونيات > سماعات', Icons.folder_outlined),
        _F('الوحدة *', 'قطعة', Icons.widgets_outlined),
      ], count: 2),
      _stats(const [
        _S('سعر الشراء', '150.00', Icons.paid_outlined),
        _S('سعر البيع', '199.00', Icons.sell_outlined),
        _S('سعر الجملة', '175.00', Icons.inventory_outlined),
      ], columns: 3),
      _fields(const [
        _F('الرصيد الافتتاحي', '50', Icons.layers_outlined),
        _F('الحد الأدنى للمخزون', '10', Icons.notifications_outlined),
        _F('الضريبة', '15%', Icons.percent_outlined),
        _F('حالة الصنف', 'نشط', Icons.check_circle_outline),
      ], count: 2),
      _buttons(const ['حفظ', 'توليد باركود', 'طباعة ملصق', 'إضافة وحدة', 'حركة الصنف']),
    ]),
    _pair(
      _panel('رصيد المخازن', Icons.warehouse_outlined, [
        _stats(const [_S('إجمالي الكمية', '124', Icons.donut_large_outlined)]),
        _table(const ['المستودع', 'الكمية'], const [
          ['المستودع الرئيسي', '70'],
          ['مستودع الفرع (شمال)', '34'],
          ['مستودع الفرع (جنوب)', '20'],
        ]),
      ]),
      _panel('ملخص الصنف', Icons.info_outline, [
        _stats(const [
          _S('الكمية الحالية', '124', Icons.inventory_2_outlined),
          _S('المحجوزة', '12', Icons.lock_outline),
          _S('متوسط التكلفة', '151.20', Icons.calculate_outlined),
        ], columns: 3),
      ]),
    ),
    _panel('آخر حركات الصنف', Icons.history_outlined, [
      _table(const ['التاريخ', 'نوع الحركة', 'الكمية', 'الرصيد بعد', 'المستودع'], const [
        ['اليوم 10:14', 'إضافة (مشتريات)', '+50', '124', 'الرئيسي'],
        ['أمس 15:22', 'صرف (مبيعات)', '-10', '74', 'شمال'],
        ['28 يناير', 'إضافة (تحويل)', '+20', '84', 'جنوب'],
        ['27 يناير', 'جرد (تسوية)', '-6', '64', 'الرئيسي'],
      ]),
    ]),
  ]);

  Widget _accountsTree() => _group([
    _search('بحث في الحسابات (الاسم، الرقم...)'),
    _stats(const [
      _S('الأصول', '65', Icons.account_balance_wallet_outlined, foot: 'حساب'),
      _S('الخصوم', '27', Icons.layers_outlined, foot: 'حساب'),
      _S('الإيرادات', '18', Icons.trending_up_rounded, foot: 'حساب'),
      _S('المصروفات', '42', Icons.wallet_outlined, foot: 'حساب'),
    ]),
    _pair(
      _panel('إضافة / تعديل حساب', Icons.edit_outlined, [
        _fields(const [
          _F('اسم الحساب *', 'البنك', Icons.text_fields_rounded),
          _F('رقم الحساب *', '1112', Icons.tag_outlined),
          _F('الحساب الأب *', '111 - النقدية وما في حكمها', Icons.account_tree_outlined),
          _F('نوع الحساب *', 'أصل', Icons.layers_outlined),
          _F('العملة *', 'ريال يمني', Icons.paid_outlined),
          _F('الرصيد الافتتاحي *', '250,000', Icons.calculate_outlined),
          _F('الطبيعة', 'مدين', Icons.check_circle_outline),
          _F('الحالة', 'فعال', Icons.verified_outlined),
        ], count: 2),
      ]),
      _panel('معاينة شجرة الحسابات', Icons.account_tree_outlined, [
        for (final entry in const [
          '1 - الأصول',
          '  11 - الأصول المتداولة',
          '    111 - النقدية وما في حكمها',
          '      1111 - الصندوق',
          '      1112 - البنك',
          '    112 - المدينون',
          '    113 - المخزون',
          '2 - الخصوم',
          '3 - حقوق الملكية',
          '4 - الإيرادات',
          '5 - المصروفات',
        ])
          InkWell(
            onTap: () => _toast('اختيار حساب ' + entry.trim()),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                const Icon(Icons.folder_outlined, size: 17, color: _blue),
                const SizedBox(width: 7),
                Expanded(child: Text(entry, style: const TextStyle(fontSize: 12))),
                const Icon(Icons.chevron_left_rounded, size: 17),
              ]),
            ),
          ),
      ]),
    ),
    _buttons(const ['حفظ', 'إضافة حساب فرعي', 'ترحيل رصيد افتتاحي', 'كشف حركة']),
    _panel('الحسابات الفرعية', Icons.list_alt_outlined, [
      _table(const ['رقم الحساب', 'اسم الحساب', 'الطبيعة', 'الرصيد الافتتاحي', 'الحالة'], const [
        ['1111', 'الصندوق', 'مدين', '50,000', 'فعال'],
        ['1112', 'البنك', 'مدين', '250,000', 'فعال'],
        ['11121', 'بنك الراجحي', 'مدين', '150,000', 'فعال'],
        ['11122', 'البنك الأهلي', 'مدين', '100,000', 'فعال'],
      ]),
    ]),
  ]);

  Widget _cashAndBanks() => _group([
    _search('بحث في الحركات (رقم السند، الحساب، المبلغ، البيان...)'),
    _stats(const [
      _S('رصيد الصندوق', '98,600', Icons.savings_outlined),
      _S('رصيد الحسابات البنكية', '357,900', Icons.account_balance_outlined),
      _S('حركة اليوم', '+86,250', Icons.swap_horiz_rounded, foot: 'إيداع 125,000 - سحب 38,750'),
    ], columns: 3),
    _choices(const ['الصندوق', 'الحسابات البنكية', 'التحويلات', 'أسعار الصرف']),
    _panel('تحويل داخلي', Icons.swap_horiz_rounded, [
      _fields(const [
        _F('رقم السند', '#TR-0001542', Icons.tag_outlined),
        _F('من الحساب *', 'الصندوق الرئيسي', Icons.account_balance_wallet_outlined),
        _F('إلى الحساب *', 'حساب البنك الأهلي', Icons.account_balance_outlined),
        _F('المبلغ *', '50,000.00', Icons.calculate_outlined),
        _F('العملة *', 'ريال يمني', Icons.monetization_on_outlined),
        _F('سعر الصرف', '1.0000', Icons.currency_exchange_outlined),
        _F('الرسوم', '0.00', Icons.percent_outlined),
        _F('التاريخ *', '2025/01/30', Icons.calendar_month_outlined),
        _F('ملاحظات', 'تحويل تغذية حساب البنك', Icons.edit_note_outlined),
      ]),
      _buttons(const ['حفظ التحويل', 'إيداع', 'سحب', 'طباعة حركة', 'مطابقة']),
    ]),
    _panel('أسعار الصرف السريعة', Icons.currency_exchange_outlined, [
      _stats(const [
        _S('الريال اليمني YER', '1.0000', Icons.flag_outlined),
        _S('الريال السعودي SAR', '70.2000', Icons.paid_outlined),
        _S('الدولار الأمريكي USD', '265.0000', Icons.attach_money_rounded),
      ], columns: 3),
    ]),
    _panel('آخر حركات الصندوق والحسابات', Icons.history_outlined, [
      _table(const ['الوقت', 'رقم السند', 'البيان', 'من الحساب', 'إلى الحساب', 'المبلغ'], const [
        ['10:18', 'TR-0001542', 'تحويل داخلي', 'الصندوق', 'البنك الأهلي', '50,000'],
        ['09:47', 'RC-0000882', 'إيداع نقدي', '-', 'الصندوق', '25,000'],
        ['09:30', 'PY-0000671', 'سحب نقدي', 'الصندوق', '-', '15,000'],
      ]),
    ]),
  ]);
}
