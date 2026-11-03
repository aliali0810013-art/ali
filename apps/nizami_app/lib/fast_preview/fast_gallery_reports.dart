part of 'fast_screens.dart';

extension _FastGalleryReports on _FastPreviewScreenState {
  Widget _reports() => _group([
    _pair(
      _search('بحث في التقارير أو المؤشرات...'),
      _fields(const [
        _F('الفترة', 'هذا الشهر', Icons.calendar_month_outlined),
      ], count: 1),
    ),
    _stats(const [
      _S('المبيعات', '456,800', Icons.shopping_cart_outlined, foot: 'ر.ي'),
      _S('الأرباح', '123,400', Icons.trending_up_outlined, foot: 'ر.ي'),
      _S('المصروفات', '67,300', Icons.account_balance_wallet_outlined),
      _S('هامش صافي الربح', '27.0%', Icons.percent_outlined),
    ]),
    _panel('اتجاه المبيعات', Icons.stacked_line_chart_rounded, [
      _choices(const ['يومي', 'أسبوعي', 'شهري']),
      _stats(const [
        _S('إجمالي المبيعات', '456,800', Icons.bar_chart_outlined),
        _S('مقارنة بالفترة السابقة', '+18.7%', Icons.arrow_upward_outlined),
      ], columns: 2),
      _chart(),
    ]),
    _fields(const [
      _F('الفرع', 'الفرع الرئيسي', Icons.storefront_outlined),
      _F('المستودع', 'جميع المستودعات', Icons.warehouse_outlined),
      _F('المندوب', 'جميع المندوبين', Icons.person_outline),
    ]),
    _panel('التقارير المالية', Icons.analytics_outlined, [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in const [
            ('الأرباح والخسائر', 11, Icons.trending_up_rounded),
            ('ميزان المراجعة', 12, Icons.balance_outlined),
            ('دفتر الأستاذ', 13, Icons.menu_book_outlined),
            ('تقييم المخزون', 14, Icons.inventory_2_outlined),
            ('مبيعات الأصناف', 0, Icons.shopping_cart_outlined),
            ('كشف الحساب', 5, Icons.description_outlined),
          ])
            OutlinedButton.icon(
              onPressed: () => widget.onOpenScreen(item.$2),
              icon: Icon(item.$3, size: 18),
              label: Text(item.$1, style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    ]),
    _panel('آخر التقارير', Icons.history_rounded, [
      _table(const ['اسم التقرير', 'الوقت', 'التصدير'], const [
        ['تقرير الأرباح والخسائر - هذا الشهر', '10:18 ص', 'PDF'],
        ['تقرير مبيعات الأصناف', '09:47 ص', 'Excel'],
        ['تقرير تقييم المخزون', '09:30 ص', 'PDF'],
        ['ميزان المراجعة', '09:05 ص', 'PDF'],
      ]),
      _buttons(const ['تصدير PDF', 'تصدير Excel']),
    ]),
    _note('الرسوم والأرقام بيانات عرض تجريبية وليست حسابات محاسبية منشورة.'),
  ]);

  Widget _profitLoss() => _group([
    _search('عرض قائمة الأرباح والخسائر وتحليل الأداء المالي'),
    _fields(const [
      _F('الفترة *', '2025/01/01 - 2025/01/30', Icons.calendar_month_outlined),
      _F('الفرع', 'الفرع الرئيسي', Icons.storefront_outlined),
      _F('مقارنة', 'مع الفترة السابقة', Icons.compare_arrows_rounded),
    ]),
    _switch('مقارنة بمدة سابقة'),
    _stats(const [
      _S('الإيرادات', '486,800.00', Icons.bar_chart_outlined),
      _S('تكلفة البضاعة', '(292,080.00)', Icons.inventory_2_outlined),
      _S('مجمل الربح', '194,720.00', Icons.savings_outlined, foot: 'هامش 40%'),
      _S('المصروفات التشغيلية', '(51,360.00)', Icons.work_outline),
      _S('صافي الربح', '143,360.00', Icons.trending_up_rounded, foot: 'هامش 29.5%'),
    ]),
    _panel('تطور صافي الربح', Icons.stacked_line_chart_rounded, [
      _stats(const [
        _S('صافي الربح', '143,360.00', Icons.trending_up_rounded),
        _S('التغير', '+21.4%', Icons.arrow_upward_rounded),
      ], columns: 2),
      _chart(color: _blue),
    ]),
    _panel('قائمة الدخل - مقارنة الفترات', Icons.table_chart_outlined, [
      _table(const ['البند', 'الفترة الحالية', 'السابقة', 'التغير', 'النسبة'], const [
        ['المبيعات', '486,800', '410,000', '+76,800', '+18.7%'],
        ['المرتجعات', '(12,400)', '(9,800)', '(2,600)', '+26.5%'],
        ['صافي المبيعات', '474,400', '400,200', '+74,200', '+18.5%'],
        ['تكلفة المبيعات', '(292,080)', '(249,120)', '(42,960)', '+17.2%'],
        ['مجمل الربح', '194,720', '151,080', '+43,640', '+28.9%'],
        ['المصاريف الإدارية', '(24,600)', '(21,000)', '(3,600)', '+17.1%'],
        ['المصاريف التشغيلية', '(26,760)', '(24,360)', '(2,400)', '+9.9%'],
        ['صافي الربح', '143,360', '105,720', '+37,640', '+35.6%'],
      ]),
    ]),
    _buttons(const ['PDF', 'Excel', 'طباعة']),
  ]);

  Widget _trialBalance() => _group([
    _note('عرض أرصدة الحسابات المدينة والدائنة ومطابقة إجمالي الميزان.'),
    _fields(const [
      _F('الفترة المحاسبية *', 'من 2025/01/01 إلى 2025/01/31', Icons.calendar_month_outlined),
      _F('مستوى العرض *', 'تفصيلي (كل الحسابات)', Icons.layers_outlined),
    ], count: 2),
    _pair(_search('بحث برقم الحساب أو اسم الحساب...'), _buttons(const ['تصفية'])),
    _stats(const [
      _S('إجمالي المدين', '1,250,000', Icons.trending_up_outlined),
      _S('إجمالي الدائن', '1,250,000', Icons.south_west_outlined),
      _S('الفرق', '0.00', Icons.balance_outlined),
      _S('عدد الحسابات', '128', Icons.account_tree_outlined),
    ]),
    _panel('ميزان المراجعة التفصيلي', Icons.balance_outlined, [
      _table(const ['رقم الحساب', 'اسم الحساب', 'مدين', 'دائن', 'الحالة'], const [
        ['1010', 'النقدية في الصندوق', '120,000', '0.00', 'متوازن'],
        ['1020', 'البنك - حساب جاري', '0.00', '350,000', 'متوازن'],
        ['1120', 'العملاء', '210,000', '0.00', 'متوازن'],
        ['1140', 'المخزون', '180,000', '0.00', 'متوازن'],
        ['1210', 'الأصول الثابتة', '450,000', '0.00', 'متوازن'],
        ['2110', 'الموردون', '0.00', '250,000', 'متوازن'],
        ['2210', 'قروض طويلة الأجل', '0.00', '300,000', 'متوازن'],
        ['3110', 'رأس المال', '0.00', '400,000', 'متوازن'],
        ['4110', 'مصاريف تشغيلية', '150,000', '0.00', 'متوازن'],
        ['5110', 'إيرادات المبيعات', '0.00', '100,000', 'متوازن'],
        ['الإجمالي', '-', '1,250,000', '1,250,000', 'متوازن'],
      ]),
      _note('الميزان التجريبي: إجمالي المدين يساوي إجمالي الدائن.'),
    ]),
    _buttons(const ['طباعة', 'PDF', 'Excel', 'مشاركة']),
  ]);

  Widget _generalLedger() => _group([
    _search('عرض حركات الحساب والأرصدة التفصيلية لفترة محددة'),
    _fields(const [
      _F('الحساب *', '1101 - الصندوق الرئيسي', Icons.account_tree_outlined),
      _F('الفترة *', 'من 2025/01/01 إلى 2025/01/31', Icons.calendar_month_outlined),
    ], count: 2),
    _stats(const [
      _S('الرصيد الافتتاحي', '20,000.00', Icons.savings_outlined),
      _S('إجمالي المدين', '32,350.00', Icons.trending_up_rounded),
      _S('إجمالي الدائن', '12,326.50', Icons.arrow_downward_rounded),
      _S('رصيد الحساب', '40,023.50', Icons.balance_outlined),
    ]),
    _choices(const ['جميع الحركات', 'المرحل', 'المسودة']),
    _search('بحث في الحركات (البيان، المرجع، المبلغ...)'),
    _panel('كشف حركات الحساب', Icons.menu_book_rounded, [
      _table(const ['التاريخ', 'البيان', 'المرجع', 'مدين', 'دائن', 'الرصيد'], const [
        ['01/01', 'رصيد افتتاحي', 'OP-0001', '-', '-', '20,000'],
        ['01/05', 'تحصيل من عميل', 'RCV-1156', '10,000', '-', '30,000'],
        ['01/08', 'سداد مورد', 'PY-0783', '-', '4,500', '25,500'],
        ['01/12', 'مصاريف تشغيلية', 'EXP-0321', '-', '1,260', '24,240'],
        ['01/18', 'تحصيل من عميل', 'RCV-1189', '15,750', '-', '39,990'],
        ['01/22', 'سداد مصروفات', 'EXP-0334', '-', '2,160', '37,830'],
        ['01/28', 'تحويل بين حسابات', 'TR-0019', '6,600', '-', '44,430'],
        ['01/30', 'سداد مورد', 'PY-0792', '-', '4,406.50', '40,023.50'],
      ]),
    ]),
    _buttons(const ['كشف الحساب', 'Excel', 'PDF', 'طباعة']),
  ]);

  Widget _stockCount() => _group([
    _search('إجراء جرد للأصناف ومقارنة الرصيد الفعلي مع النظام'),
    _fields(const [
      _F('المخزن *', 'المخزن الرئيسي', Icons.warehouse_outlined),
      _F('رقم جلسة الجرد *', 'SC-00078', Icons.description_outlined),
      _F('التاريخ *', '2025/01/30', Icons.calendar_month_outlined),
      _F('الموظف المسؤول *', 'أحمد سالم', Icons.person_outline),
    ], count: 2),
    _panel('تقدم عملية الجرد', Icons.track_changes_outlined, [
      _progress('تم جرد 39 من 50 صنف', 0.78),
    ]),
    _pair(_search('بحث عن صنف (الاسم أو الباركود)...'), _buttons(const ['مسح باركود'])),
    _panel('مطابقة كميات الأصناف', Icons.fact_check_outlined, [
      _table(const ['الصنف', 'الرصيد النظامي', 'الفعلي', 'الفرق', 'نوع التسوية', 'الحالة'], const [
        ['لابتوب 15 بوصة', '30', '32', '+2', 'زيادة', 'معتمد'],
        ['ماوس لاسلكي', '30', '28', '-2', 'عجز', 'معلق'],
        ['لوحة مفاتيح', '5', '5', '0', 'بدون', 'معتمد'],
        ['شاشة 24 بوصة', '6', '7', '+1', 'زيادة', 'معلق'],
        ['سماعة رأس', '20', '18', '-2', 'عجز', 'معلق'],
      ]),
    ]),
    _stats(const [
      _S('الأصناف المعدودة', '39/50', Icons.inventory_2_outlined),
      _S('الزيادة', '+3', Icons.arrow_upward_rounded),
      _S('العجز', '-4', Icons.arrow_downward_rounded),
      _S('قيمة الفروقات', '980.00', Icons.monetization_on_outlined),
    ]),
    _panel('خيارات التسوية', Icons.edit_note_outlined, [
      _switch('إنشاء قيود تسوية تلقائيًا'),
      _switch('تحديث رصيد المخزون بعد الاعتماد', initial: false),
      _fields(const [
        _F('ملاحظات', 'أضف ملاحظات عن الجرد أو التسوية...', Icons.edit_note_outlined),
      ], count: 1),
    ]),
    _buttons(const ['حفظ', 'اعتماد', 'طباعة', 'استيراد', 'جرد جديد']),
  ]);

  Widget _wasl() => _group([
    _search('بحث عن تحويل (الرمز، المرسل، المستلم، رقم الهاتف...)'),
    _stats(const [
      _S('إجمالي التحويلات', '6,870', Icons.swap_horiz_rounded),
      _S('قيد التنفيذ', '328', Icons.schedule_rounded),
      _S('مكتملة', '5,480', Icons.check_circle_outlined),
      _S('الملغاة', '62', Icons.cancel_outlined),
    ]),
    _pair(
      _panel('بيانات التحويل', Icons.layers_outlined, [
        _choices(const ['إرسال', 'استلام', 'متابعة']),
        _fields(const [
          _F('المرسل *', 'أحمد محمد سالم', Icons.person_outline),
          _F('المستلم *', 'خالد عبدالله العتيبي', Icons.person_outline),
          _F('المبلغ *', '5,000.00', Icons.calculate_outlined),
          _F('رسوم التحويل', '50.00', Icons.sell_outlined),
          _F('المحفظة المصدر *', 'محفظة WASL الرئيسية', Icons.wallet_outlined),
          _F('رمز التحويل', 'WASL-987655', Icons.copy_outlined),
          _F('المدينة / الفرع', 'صنعاء', Icons.location_on_outlined),
          _F('ملاحظات', 'ملاحظة التحويل...', Icons.edit_outlined),
        ], count: 2),
        _stats(const [
          _S('المبلغ الصافي', '4,950.00', Icons.account_balance_wallet_outlined),
        ]),
      ]),
      _panel('حالة التحويل', Icons.timeline_outlined, [
        for (final entry in const [
          '✓  تم إنشاء التحويل',
          '◉  قيد التنفيذ',
          '○  قيد التسليم',
          '○  مكتمل',
        ])
          ListTile(
            dense: true,
            leading: const Icon(Icons.radio_button_checked_outlined, color: _blue),
            title: Text(entry, style: const TextStyle(fontSize: 12)),
          ),
        const Divider(),
        const Text('آخر التحويلات', style: TextStyle(fontWeight: FontWeight.bold)),
        _table(const ['الرقم', 'المبلغ', 'الحالة'], const [
          ['WASL-987654', '1,250', 'مكتمل'],
          ['WASL-987653', '3,000', 'قيد التنفيذ'],
          ['WASL-987652', '750', 'مكتمل'],
          ['WASL-987651', '2,500', 'ملغي'],
        ]),
      ]),
    ),
    _buttons(const ['إرسال', 'حفظ', 'طباعة', 'مشاركة']),
  ]);

  Widget _whatsapp() => _group([
    _search('بحث عن عميل، رقم جوال، رسالة...'),
    _pair(
      _panel('حالة الاتصال بالواتساب', Icons.link_rounded, [
        _stats(const [
          _S('الحالة', 'متصل', Icons.check_circle_outline, foot: 'نموذج عرض فقط'),
        ], columns: 1),
        _note('عينة عرض، لا توجد جلسة واتساب حقيقية متصلة بهذه المعاينة.'),
      ]),
      _panel('العميل المحدد', Icons.person_outline, [
        _fields(const [
          _F('العميل', 'مؤسسة النور للتجارة', Icons.business_outlined),
          _F('الجوال', '+967 777 123 456', Icons.phone_outlined),
          _F('الرصيد', '12,326.50', Icons.account_balance_wallet_outlined),
        ], count: 1),
      ]),
    ),
    _fields(const [
      _F('قالب الرسالة', 'إرسال فاتورة للعميل', Icons.layers_outlined),
    ], count: 1),
    _buttons(const ['إرسال فاتورة', 'إرسال كشف حساب', 'تذكير سداد', 'مشاركة PDF']),
    _panel('المحادثة مع العميل', Icons.chat_bubble_outline_rounded, [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F4F9),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Text('مرحبًا، هل يمكن إرسال فاتورة طلبية رقم 1542؟',
            style: TextStyle(fontSize: 12)),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 290,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFDFF9E5),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تم إرسال الفاتورة INV-01542 بمبلغ 32,326.50 ر.ي.',
              style: TextStyle(fontSize: 12)),
            SizedBox(height: 6),
            Text('INV-01542.pdf',
              style: TextStyle(fontSize: 11, color: Color(0xFF157439))),
          ]),
        ),
      ),
      _search('اكتب رسالتك هنا...'),
      _buttons(const ['إرسال الرسالة', 'إرفاق PDF']),
    ], accent: _green),
    _panel('الرسائل المرسلة حديثًا', Icons.history_outlined, [
      _table(const ['العميل', 'المستند', 'الوقت', 'الحالة'], const [
        ['مؤسسة النور', 'فاتورة INV-01542', '10:15', 'تم التسليم'],
        ['شركة البدر', 'كشف حساب', '09:47', 'تمت القراءة'],
        ['مؤسسة الريان', 'تذكير سداد', '09:30', 'قيد الإرسال'],
      ]),
    ]),
  ]);

  Widget _backups() => _group([
    _search('إدارة مزامنة البيانات والنسخ الاحتياطي واستعادة النسخ'),
    _stats(const [
      _S('حالة المزامنة', 'متزامن', Icons.sync_rounded),
      _S('آخر مزامنة', '10:12 ص', Icons.schedule_rounded),
      _S('اتصال الخادم', 'متصل', Icons.dns_outlined, foot: 'مؤشر عرض'),
      _S('استخدام التخزين', '68.4 GB', Icons.storage_outlined, foot: 'من 100 GB'),
    ]),
    _pair(
      _panel('المزامنة والنسخ التلقائية', Icons.autorenew_rounded, [
        _switch('المزامنة التلقائية'),
        _switch('النسخ الاحتياطي التلقائي'),
      ]),
      _panel('جدولة المزامنة والنسخ', Icons.calendar_month_outlined, [
        _fields(const [
          _F('تكرار الجدولة', 'يوميًا', Icons.speed_outlined),
          _F('وقت التنفيذ', '02:00 ص', Icons.schedule_outlined),
          _F('الاحتفاظ بالنسخ', '30 يومًا', Icons.storage_outlined),
        ], count: 1),
      ]),
    ),
    _panel('سعة التخزين', Icons.storage_rounded, [
      _progress('68.4 GB مستخدم من 100 GB', 0.684),
      _stats(const [
        _S('سعة التخزين الكلية', '100 GB', Icons.dns_outlined),
        _S('المستخدم', '68.4 GB', Icons.storage_outlined),
        _S('المتبقي', '31.6 GB', Icons.check_circle_outline),
      ], columns: 3),
    ]),
    _panel('سجل النسخ الاحتياطية', Icons.backup_outlined, [
      _table(const ['النسخة', 'الحالة', 'التاريخ', 'الحجم'], const [
        ['نسخة تلقائية', 'مكتملة', '30 يناير - 02:00', '2.84 GB'],
        ['نسخة تلقائية', 'مكتملة', '29 يناير - 02:00', '2.79 GB'],
        ['نسخة تلقائية', 'مكتملة', '28 يناير - 02:00', '2.76 GB'],
        ['نسخة تلقائية', 'مكتملة', '27 يناير - 02:00', '2.71 GB'],
      ]),
    ]),
    _panel('نقاط الاستعادة', Icons.settings_backup_restore_rounded, [
      _table(const ['النقطة', 'النوع', 'التاريخ', 'الحجم'], const [
        ['قبل تحديث النظام', 'يدوية', '26 يناير - 09:00', '3.01 GB'],
        ['قبل إغلاق الشهر', 'تلقائية', '20 يناير - 11:30', '2.68 GB'],
      ]),
      _note('أزرار الاستعادة والحذف معطلة في المعاينة لحماية بيانات الإنتاج.'),
    ]),
    _buttons(const ['مزامنة الآن', 'إنشاء نسخة', 'عرض النسخ']),
  ]);

  Widget _settings() => _group([
    _search('إدارة المستخدمين والصلاحيات، المزامنة والنسخ والإعدادات العامة'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final link in const [
          ('المستخدمون', 19, Icons.groups_outlined),
          ('النسخ الاحتياطي', 17, Icons.storage_outlined),
          ('المزامنة', 17, Icons.sync_rounded),
          ('واتساب', 16, Icons.chat_outlined),
          ('تحويلات WASL', 15, Icons.swap_horiz_rounded),
        ])
          OutlinedButton.icon(
            onPressed: () => widget.onOpenScreen(link.$2),
            icon: Icon(link.$3),
            label: Text(link.$1, style: const TextStyle(fontSize: 12)),
          ),
      ],
    ),
    _pair(
      _panel('بيانات المستخدم', Icons.person_outline, [
        _fields(const [
          _F('اسم المستخدم *', 'أحمد محمد', Icons.person_outline),
          _F('الدور *', 'مدير النظام', Icons.admin_panel_settings_outlined),
        ], count: 1),
        _panel('صلاحيات المستخدم', Icons.lock_outline, [
          _switch('إدارة المبيعات'),
          _switch('إدارة المشتريات'),
          _switch('إدارة المخزون'),
          _switch('إدارة التقارير'),
          _switch('الإعدادات العامة', initial: false),
        ]),
      ]),
      _panel('حالة الاتصال', Icons.wifi_rounded, [
        _stats(const [
          _S('الخادم', 'متصل', Icons.dns_outlined),
          _S('الاستجابة', '42 ms', Icons.speed_outlined),
          _S('آخر مزامنة', '10:12', Icons.sync_outlined),
        ], columns: 3),
        _panel('التكاملات', Icons.extension_outlined, [
          _note('واتساب • WASL • الطباعة • النسخ الاحتياطية: مؤشرات للعرض فقط'),
        ]),
      ]),
    ),
    _panel('تفضيلات النظام', Icons.tune_outlined, [
      _fields(const [
        _F('نوع الطابعة', 'A4', Icons.print_outlined),
        _F('لون هوية الفاتورة', 'أزرق', Icons.palette_outlined),
        _F('وضع العرض', 'فاتح', Icons.light_mode_outlined),
        _F('اللغة', 'العربية', Icons.language_rounded),
      ], count: 2),
      _switch('المزامنة التلقائية'),
      _switch('إشعارات النظام'),
      _switch('تنبيهات المخزون'),
      _switch('تنبيهات الفواتير'),
    ]),
    _buttons(const ['حفظ الإعدادات', 'إضافة مستخدم', 'مزامنة الآن', 'نسخ احتياطي']),
  ]);

  Widget _users() => _group([
    _search('بحث عن مستخدم (الاسم، اسم المستخدم، الدور...)'),
    _stats(const [
      _S('عدد المستخدمين', '12', Icons.groups_outlined),
      _S('المتصلون الآن', '3', Icons.sensors_outlined),
      _S('الأدوار', '6', Icons.verified_user_outlined),
      _S('الصلاحيات المخصصة', '28', Icons.layers_outlined),
    ]),
    _buttons(const ['إضافة مستخدم', 'تحديث', 'تصفية']),
    _pair(
      _panel('تفاصيل المستخدم', Icons.person_outline, [
        _stats(const [
          _S('المستخدم المحدد', 'أحمد محمد', Icons.person_outline, foot: 'مدير النظام'),
        ], columns: 1),
        _fields(const [
          _F('اسم المستخدم', 'ahmed.m', Icons.person_outline),
          _F('الفرع', 'الفرع الرئيسي', Icons.storefront_outlined),
          _F('آخر دخول', 'اليوم 10:12', Icons.calendar_month_outlined),
          _F('الحالة', 'نشط', Icons.check_circle_outline),
        ], count: 2),
        _panel('الصلاحيات', Icons.lock_outline, [
          _switch('المبيعات'),
          _switch('المشتريات'),
          _switch('المخزون'),
          _switch('التقارير'),
          _switch('الإعدادات', initial: false),
          _switch('المستخدمون', initial: false),
        ]),
        _buttons(const ['حفظ', 'إلغاء']),
      ]),
      _panel('قائمة المستخدمين (12)', Icons.groups_outlined, [
        for (final name in const [
          'أحمد محمد - مدير النظام - نشط',
          'سارة علي - المبيعات - نشط',
          'محمد خالد - المشتريات - نشط',
          'نورة عبدالله - المخزون - غير نشط',
          'خالد سعيد - التقارير - نشط',
        ])
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE4EEFF),
              child: Icon(Icons.person_rounded, color: _navy),
            ),
            title: Text(name, style: const TextStyle(fontSize: 11)),
            trailing: IconButton(
              tooltip: 'فتح التفاصيل',
              onPressed: () => _toast('عرض مستخدم'),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ),
        const Divider(),
        _note('صفحة 1 من 3 - اختر مستخدمًا لتعديل الصلاحيات.'),
      ]),
    ),
  ]);
}
