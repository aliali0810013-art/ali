import 'package:flutter/material.dart';

part 'fast_gallery.dart';

class FastPreviewSpec {
  const FastPreviewSpec(this.title, this.icon);
  final String title;
  final IconData icon;
}

/// Order intentionally matches the 20 original NineSoft reference screens.
const fastPreviewScreens = <FastPreviewSpec>[
  FastPreviewSpec('المبيعات', Icons.shopping_cart_outlined),
  FastPreviewSpec('المشتريات', Icons.shopping_bag_outlined),
  FastPreviewSpec('مرتجع المبيعات', Icons.assignment_return_outlined),
  FastPreviewSpec('سندات القبض والصرف', Icons.receipt_long_outlined),
  FastPreviewSpec('القيود اليومية', Icons.menu_book_outlined),
  FastPreviewSpec('العملاء', Icons.groups_outlined),
  FastPreviewSpec('الموردون', Icons.local_shipping_outlined),
  FastPreviewSpec('المخزون والأصناف', Icons.inventory_2_outlined),
  FastPreviewSpec('شجرة الحسابات', Icons.account_tree_outlined),
  FastPreviewSpec('الصندوق والبنوك', Icons.account_balance_outlined),
  FastPreviewSpec('التقارير والتحليلات', Icons.insert_chart_outlined),
  FastPreviewSpec('الأرباح والخسائر', Icons.trending_up_rounded),
  FastPreviewSpec('ميزان المراجعة', Icons.balance_outlined),
  FastPreviewSpec('دفتر الأستاذ', Icons.auto_stories_outlined),
  FastPreviewSpec('الجرد والتسوية', Icons.fact_check_outlined),
  FastPreviewSpec('تحويلات WASL', Icons.swap_horiz_rounded),
  FastPreviewSpec('واتساب', Icons.chat_bubble_outline_rounded),
  FastPreviewSpec('المزامنة والنسخ الاحتياطي', Icons.cloud_sync_outlined),
  FastPreviewSpec('الإعدادات', Icons.settings_outlined),
  FastPreviewSpec('المستخدمون والصلاحيات', Icons.admin_panel_settings_outlined),
];

const _navy = Color(0xFF092C69);
const _blue = Color(0xFF0863D8);
const _green = Color(0xFF0B9A40);
const _orange = Color(0xFFE48706);
const _red = Color(0xFFD83A53);
const _purple = Color(0xFF7745D8);
const _ink = Color(0xFF13264B);
const _outline = Color(0xFFD9E3F3);

class _F {
  const _F(this.title, this.value, this.icon);
  final String title;
  final String value;
  final IconData icon;
}

class _S {
  const _S(this.title, this.value, this.icon, {this.foot});
  final String title;
  final String value;
  final IconData icon;
  final String? foot;
}

class FastPreviewScreen extends StatefulWidget {
  const FastPreviewScreen({
    required this.index,
    required this.onOpenScreen,
    super.key,
  });
  final int index;
  final ValueChanged<int> onOpenScreen;

  @override
  State<FastPreviewScreen> createState() => _FastPreviewScreenState();
}

class _FastPreviewScreenState extends State<FastPreviewScreen> {
  int _choice = 0;
  final Map<String, bool> _flags = <String, bool>{};

  void _toast([String? action]) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(action == null
          ? 'هذه معاينة محلية فقط. لا تُحفظ البيانات في الخادم.'
          : 'معاينة: ' + action + ' - لا يوجد ترحيل أو حفظ فعلي.'),
      duration: const Duration(seconds: 3),
    ));

  @override
  Widget build(BuildContext context) {
    final metadata = fastPreviewScreens[widget.index];
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width >= 720 ? 24 : 12,
        vertical: 16,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1260),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading(metadata.title, metadata.icon),
              const SizedBox(height: 13),
              _bodyFor(),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E9),
                  border: Border.all(color: const Color(0xFFFFE2A7)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(children: [
                  Icon(Icons.visibility_outlined, color: _orange, size: 20),
                  SizedBox(width: 9),
                  Expanded(child: Text(
                    'NineSoft Local UI Fast Preview: بيانات عرض مؤقتة. الأزرار لا ترسل عمليات محاسبية.',
                    style: TextStyle(fontSize: 11, color: _ink),
                  )),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bodyFor() => switch (widget.index) {
    0 => _sales(),
    1 => _purchases(),
    2 => _returns(),
    3 => _vouchers(),
    4 => _journal(),
    5 => _customers(),
    6 => _suppliers(),
    7 => _products(),
    8 => _accountsTree(),
    9 => _cashAndBanks(),
    10 => _reports(),
    11 => _profitLoss(),
    12 => _trialBalance(),
    13 => _generalLedger(),
    14 => _stockCount(),
    15 => _wasl(),
    16 => _whatsapp(),
    17 => _backups(),
    18 => _settings(),
    19 => _users(),
    _ => const SizedBox.shrink(),
  };

  Widget _heading(String title, IconData icon, {String? hint}) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFFE1EEFF),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: _blue, size: 27),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              color: _ink, fontSize: 24, fontWeight: FontWeight.w900,
            )),
            if (hint != null)
              Text(hint, style: const TextStyle(
                color: Color(0xFF6B7C96), fontSize: 11,
              )),
          ],
        ),
      ),
      OutlinedButton.icon(
        onPressed: () => _toast('فتح المحدد'),
        icon: const Icon(Icons.expand_more_rounded, size: 16),
        label: const Text('عرض', style: TextStyle(fontSize: 11)),
      ),
    ],
  );

  Widget _group(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final child in children)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: child,
        ),
    ],
  );

  Widget _panel(String title, IconData icon, List<Widget> children, {
    Color accent = _blue,
    Widget? trailing,
  }) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _outline),
      borderRadius: BorderRadius.circular(17),
      boxShadow: const [BoxShadow(
        color: Color(0x080F285E), blurRadius: 10, offset: Offset(0, 3),
      )],
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: accent.withAlpha(19),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(
              title,
              style: const TextStyle(
                color: _ink, fontSize: 16, fontWeight: FontWeight.w800,
              ),
            )),
            if (trailing != null) trailing,
          ]),
          if (children.isNotEmpty) const SizedBox(height: 12),
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: child,
            ),
        ],
      ),
    ),
  );

  Widget _fields(List<_F> items, {int? count}) => LayoutBuilder(
    builder: (context, box) {
      final columns = count ?? (box.maxWidth >= 800 ? 3 : 2);
      const gap = 10.0;
      final width = (box.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: 11,
        children: [
          for (final field in items)
            SizedBox(width: width, child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(field.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: _ink,
                    )),
                const SizedBox(height: 5),
                TextFormField(
                  initialValue: field.value,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    prefixIcon: Icon(field.icon, size: 19, color: _blue),
                    prefixIconConstraints: const BoxConstraints(minWidth: 30),
                    suffixIcon: const Icon(Icons.expand_more_rounded,
                        size: 16, color: Color(0xFF7D8A9F)),
                    suffixIconConstraints: const BoxConstraints(minWidth: 23),
                  ),
                ),
              ],
            )),
        ],
      );
    },
  );

  Widget _search(String hint) => TextField(
    style: const TextStyle(fontSize: 12),
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded, color: _ink),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _outline),
      ),
    ),
  );

  Widget _stats(List<_S> values, {int? columns}) => LayoutBuilder(
    builder: (context, box) {
      final count = columns ?? (box.maxWidth >= 700 ? 4 : (values.length <= 3 ? values.length : 2));
      const gap = 9.0;
      final width = (box.maxWidth - (count - 1) * gap) / count;
      const colors = [_blue, _green, _red, _purple, _orange];
      const backgrounds = [
        Color(0xFFE2EEFF),
        Color(0xFFE5FBEA),
        Color(0xFFFFEDF1),
        Color(0xFFF1E9FF),
        Color(0xFFFFF3DF),
      ];
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < values.length; i++)
            Container(
              width: width,
              constraints: const BoxConstraints(minHeight: 91),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: backgrounds[i % backgrounds.length],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: colors[i % colors.length].withAlpha(25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(values[i].title,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: _ink,
                      ),
                    )),
                    Icon(values[i].icon, size: 21, color: colors[i % colors.length]),
                  ]),
                  const SizedBox(height: 7),
                  Text(values[i].value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w900, color: _ink,
                    ),
                  ),
                  if (values[i].foot != null)
                    Text(values[i].foot!,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF51617A)),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _table(List<String> headers, List<List<String>> rows) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _outline),
      borderRadius: BorderRadius.circular(13),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFE5EEFD)),
        headingRowHeight: 39,
        dataRowMinHeight: 38,
        dataRowMaxHeight: 50,
        columnSpacing: 19,
        horizontalMargin: 12,
        showCheckboxColumn: false,
        columns: [
          for (final header in headers)
            DataColumn(label: Text(header,
              style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: _ink,
              ),
            )),
        ],
        rows: [
          for (final row in rows)
            DataRow(cells: [
              for (final value in row)
                DataCell(Text(value,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 11, color: _ink),
                )),
            ]),
        ],
      ),
    ),
  );

  Widget _buttons(List<String> labels) => Wrap(
    spacing: 7,
    runSpacing: 8,
    children: [
      for (var i = 0; i < labels.length; i++)
        FilledButton.tonalIcon(
          onPressed: () => _toast(labels[i]),
          style: FilledButton.styleFrom(
            backgroundColor: i == 0
                ? _navy
                : (i % 4 == 1 ? const Color(0xFFDFF4E6)
                    : i % 4 == 2 ? const Color(0xFFE8EFFF)
                    : const Color(0xFFF5EAFF)),
            foregroundColor: i == 0 ? Colors.white : _navy,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          icon: Icon(i == 0 ? Icons.save_outlined
              : i == 1 ? Icons.check_circle_outline
              : i == 2 ? Icons.print_outlined
              : Icons.open_in_new_rounded,
              size: 17),
          label: Text(labels[i], style: const TextStyle(fontSize: 12)),
        ),
    ],
  );

  Widget _choices(List<String> labels) => Wrap(
    spacing: 8,
    runSpacing: 7,
    children: [
      for (var i = 0; i < labels.length; i++)
        ChoiceChip(
          label: Text(labels[i], style: const TextStyle(fontSize: 11)),
          selected: _choice == i,
          onSelected: (_) => setState(() => _choice = i),
        ),
    ],
  );

  Widget _switch(String label, {bool initial = true}) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(label, style: const TextStyle(fontSize: 12)),
    value: _flags[label] ?? initial,
    onChanged: (v) => setState(() => _flags[label] = v),
  );

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < 650) {
        return Column(children: [
          first,
          const SizedBox(height: 12),
          second,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ]);
    },
  );

  Widget _chart({Color color = _blue}) => Container(
    height: 155,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7FAFF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _outline),
    ),
    child: CustomPaint(
      painter: _PreviewLinePainter(color),
      child: const SizedBox.expand(),
    ),
  );

  Widget _progress(String title, double percentage) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
        )),
        Text((percentage * 100).round().toString() + '%',
          style: const TextStyle(color: _green, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LinearProgressIndicator(
          value: percentage,
          minHeight: 11,
          backgroundColor: const Color(0xFFE7EDF6),
          color: _green,
        ),
      ),
    ],
  );

  Widget _note(String message) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, color: _blue, size: 20),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(fontSize: 11))),
    ]),
  );
}

class _PreviewLinePainter extends CustomPainter {
  const _PreviewLinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFFDDE7F5)..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final points = <double>[0.70, 0.61, 0.65, 0.45, 0.53, 0.31, 0.39, 0.26, 0.34, 0.16];
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(
        size.width * i / (points.length - 1),
        size.height * points[i],
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(80), color.withAlpha(4)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke);
    canvas.drawCircle(Offset(size.width, size.height * points.last), 4,
      Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PreviewLinePainter old) => old.color != color;
}
