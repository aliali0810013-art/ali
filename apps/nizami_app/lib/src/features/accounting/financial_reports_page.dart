import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/pdf/pdf_export_service.dart';
import '../../theme/ninesoft_financial_ui.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/nizami_theme.dart';
import 'accounting_api.dart';

class FinancialReportsPage extends StatefulWidget {
  const FinancialReportsPage({
    required this.token,
    required this.branchIds,
    this.initialReport = 'trial',
    super.key,
  });

  final String token;
  final List<String> branchIds;
  final String initialReport;

  @override
  State<FinancialReportsPage> createState() => _FinancialReportsPageState();
}

class _FinancialReportsPageState extends State<FinancialReportsPage> {
  late final AccountingApi _api = AccountingApi(token: widget.token);
  late String _report = _normalizeReport(widget.initialReport);
  late DateTime _from = DateTime(DateTime.now().year, 1, 1);
  late DateTime _to = DateTime.now();
  String? _branchId;
  bool _loading = false;
  bool _hasLoadedResult = false;
  String? _error;
  Map<String, dynamic> _result = const {};

  static const _reports = <String, String>{
    'trial': 'ميزان المراجعة',
    'profit_loss': 'الأرباح والخسائر',
    'balance_sheet': 'المركز المالي',
    'cash_flow': 'التدفقات النقدية',
  };

  @override
  void initState() {
    super.initState();
    _branchId = widget.branchIds.firstOrNull;
    _load();
  }

  String _normalizeReport(String value) => switch (value) {
    'profit-loss' || 'profit_loss' => 'profit_loss',
    'balance-sheet' || 'balance_sheet' => 'balance_sheet',
    'cash-flow' || 'cash_flow' => 'cash_flow',
    _ => 'trial',
  };

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final branchId = _branchId;
    if (branchId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = _date(_from);
      final to = _date(_to);
      final value = switch (_report) {
        'profit_loss' => await _api.profitAndLoss(
          branchId: branchId,
          from: from,
          to: to,
        ),
        'balance_sheet' => await _api.balanceSheet(
          branchId: branchId,
          asOf: to,
        ),
        'cash_flow' => await _api.cashFlow(
          branchId: branchId,
          from: from,
          to: to,
        ),
        _ => <String, dynamic>{
          'from': from,
          'to': to,
          'items': await _api.trialBalance(
            branchId: branchId,
            from: from,
            to: to,
          ),
        },
      };
      if (mounted) {
        setState(() {
          _result = value;
          _hasLoadedResult = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _rows {
    if (_report == 'balance_sheet') {
      final groups = _result['groups'];
      if (groups is! Map) return const [];
      return groups.entries
          .expand((entry) {
            final values = entry.value;
            if (values is! List) return const <Map<String, dynamic>>[];
            return values.whereType<Map>().map((row) {
              return <String, dynamic>{
                ...Map<String, dynamic>.from(row),
                'group_label': _classification(entry.key.toString()),
              };
            });
          })
          .toList(growable: false);
    }
    final items = _result['items'];
    return items is List
        ? items
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false)
        : const [];
  }

  String _classification(String value) =>
      const {
        'current_asset': 'الأصول المتداولة',
        'non_current_asset': 'الأصول غير المتداولة',
        'current_liability': 'الالتزامات المتداولة',
        'non_current_liability': 'الالتزامات غير المتداولة',
        'equity': 'حقوق الملكية',
        'revenue': 'الإيرادات',
        'cost_of_sales': 'تكلفة المبيعات',
        'operating_expense': 'المصروفات التشغيلية',
        'operating': 'تشغيلية',
        'investing': 'استثمارية',
        'financing': 'تمويلية',
      }[value] ??
      value;

  String _money(dynamic minor) {
    final value = int.tryParse(minor?.toString() ?? '');
    if (value == null) return '—';
    return '${(value / 100).toStringAsFixed(2)} YER';
  }

  List<(String, String)> get _summary => !_hasLoadedResult
      ? switch (_report) {
          'profit_loss' => const [
            ('الإيرادات', '—'),
            ('مجمل الربح', '—'),
            ('صافي الربح', '—'),
          ],
          'balance_sheet' => const [
            ('الأصول', '—'),
            ('الالتزامات', '—'),
            ('حقوق الملكية', '—'),
            ('فرق الاتزان', '—'),
          ],
          'cash_flow' => const [
            ('تشغيلية', '—'),
            ('استثمارية', '—'),
            ('تمويلية', '—'),
            ('النقدية الختامية', '—'),
          ],
          _ => const [
            ('الحسابات المتحركة', '—'),
            ('إجمالي المدين', '—'),
            ('إجمالي الدائن', '—'),
          ],
        }
      : switch (_report) {
          'profit_loss' => [
            ('الإيرادات', _money(_result['revenue_minor'])),
            ('مجمل الربح', _money(_result['gross_profit_minor'])),
            ('صافي الربح', _money(_result['net_profit_minor'])),
          ],
          'balance_sheet' => [
            ('الأصول', _money(_result['assets_minor'])),
            ('الالتزامات', _money(_result['liabilities_minor'])),
            ('حقوق الملكية', _money(_result['equity_minor'])),
            ('فرق الاتزان', _money(_result['difference_minor'])),
          ],
          'cash_flow' => [
            ('تشغيلية', _money(_result['operating_minor'])),
            ('استثمارية', _money(_result['investing_minor'])),
            ('تمويلية', _money(_result['financing_minor'])),
            ('النقدية الختامية', _money(_result['closing_cash_minor'])),
          ],
          _ => [
            ('الحسابات المتحركة', '${_rows.length}'),
            (
              'إجمالي المدين',
              _money(
                _rows.fold<int>(
                  0,
                  (sum, row) =>
                      sum + ((row['debit_minor'] as num?)?.toInt() ?? 0),
                ),
              ),
            ),
            (
              'إجمالي الدائن',
              _money(
                _rows.fold<int>(
                  0,
                  (sum, row) =>
                      sum + ((row['credit_minor'] as num?)?.toInt() ?? 0),
                ),
              ),
            ),
          ],
        };

  void _selectReport(String report) {
    if (report == _report) return;
    setState(() {
      _report = report;
      _result = const {};
      _hasLoadedResult = false;
    });
    _load();
  }

  List<String> get _headers => _report == 'cash_flow'
      ? const ['التاريخ', 'البيان', 'النشاط', 'المبلغ']
      : _report == 'profit_loss'
      ? const ['الحساب', 'الاسم', 'التصنيف', 'المبلغ']
      : _report == 'balance_sheet'
      ? const ['المجموعة', 'الحساب', 'الاسم', 'المبلغ']
      : const ['الحساب', 'الاسم', 'افتتاحي', 'مدين', 'دائن', 'ختامي'];

  List<String> _cells(Map<String, dynamic> row) => _report == 'cash_flow'
      ? [
          row['posted_at']?.toString().split('T').first ?? '',
          row['description']?.toString() ?? '',
          _classification(row['activity']?.toString() ?? ''),
          _money(row['amount_minor']),
        ]
      : _report == 'profit_loss'
      ? [
          row['account_code']?.toString() ?? '',
          row['name_ar']?.toString() ?? '',
          _classification(row['classification']?.toString() ?? ''),
          _money(row['amount_minor']),
        ]
      : _report == 'balance_sheet'
      ? [
          row['group_label']?.toString() ?? '',
          row['account_code']?.toString() ?? '',
          row['name_ar']?.toString() ?? '',
          _money(row['amount_minor']),
        ]
      : [
          row['account_code']?.toString() ?? '',
          row['name_ar']?.toString() ?? '',
          _money(row['opening_balance_minor']),
          _money(row['debit_minor']),
          _money(row['credit_minor']),
          _money(row['balance_minor']),
        ];

  Future<void> _pickDate(bool start) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: start ? _from : _to,
    );
    if (selected == null) return;
    setState(() => start ? _from = selected : _to = selected);
    await _load();
  }

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  Future<void> _exportCsv() async {
    final lines = <String>[
      _headers.map(_csvCell).join(','),
      ..._rows.map((row) => _cells(row).map(_csvCell).join(',')),
    ];
    final filename = '${_report}_${_date(_to)}.csv';
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel CSV', extensions: ['csv']),
      ],
    );
    if (location == null) return;
    await XFile.fromData(
      Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode(lines.join('\r\n')),
      ]),
      mimeType: 'text/csv',
      name: filename,
    ).saveTo(location.path);
  }

  Future<void> _exportPdf({bool print = false}) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final latin = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
    );
    final document = pw.Document(title: _reports[_report]);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
          fontFallback: [latin],
        ),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _reports[_report]!,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('الفترة: ${_date(_from)} — ${_date(_to)}'),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (_) => [
          pw.Wrap(
            spacing: 10,
            runSpacing: 6,
            children: _summary
                .map(
                  (item) => pw.Container(
                    padding: const pw.EdgeInsets.all(7),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                    ),
                    child: pw.Text('${item.$1}: ${item.$2}'),
                  ),
                )
                .toList(),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: _headers,
            data: _rows.map(_cells).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFE9F1FB),
            ),
            cellAlignment: pw.Alignment.centerRight,
          ),
        ],
      ),
    );
    final bytes = await document.save();
    final filename = '${_report}_${_date(_to)}.pdf';
    if (print) {
      await PdfExportService.print(bytes: bytes, filename: filename);
    } else {
      await PdfExportService.save(bytes: bytes, filename: filename);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      foregroundColor: Colors.white,
      title: Text(
        _reports[_report]!,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [Color(0xFF061C3D), Color(0xFF0A417D), Color(0xFF087D83)],
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: _rows.isEmpty ? null : _exportCsv,
          color: Colors.white,
          disabledColor: Colors.white38,
          tooltip: 'Excel / CSV',
          icon: const Icon(Icons.table_view_rounded),
        ),
        IconButton(
          onPressed: _rows.isEmpty ? null : () => _exportPdf(print: true),
          color: Colors.white,
          disabledColor: Colors.white38,
          tooltip: 'طباعة',
          icon: const Icon(Icons.print_rounded),
        ),
        IconButton(
          onPressed: _rows.isEmpty ? null : _exportPdf,
          color: Colors.white,
          disabledColor: Colors.white38,
          tooltip: 'PDF',
          icon: const Icon(Icons.picture_as_pdf_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: NineSoftResponsiveBody(
        child: ListView(
          children: [
            _ReportSelector(
              current: _report,
              reports: _reports,
              onSelected: _selectReport,
            ),
            const SizedBox(height: 10),
            Container(
              key: const Key('financial-report-filter-strip'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NizamiColors.border),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.branchIds.length > 1)
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _branchId,
                        decoration: const InputDecoration(labelText: 'الفرع'),
                        items: widget.branchIds
                            .map(
                              (id) => DropdownMenuItem(
                                value: id,
                                child: Text(
                                  id,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _branchId = value);
                          _load();
                        },
                      ),
                    ),
                  if (_report != 'balance_sheet')
                    OutlinedButton.icon(
                      onPressed: () => _pickDate(true),
                      icon: const Icon(Icons.date_range),
                      label: Text('من ${_date(_from)}'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.event_available),
                    label: Text(
                      _report == 'balance_sheet'
                          ? 'حتى ${_date(_to)}'
                          : 'إلى ${_date(_to)}',
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'تحديث',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _ReportKpiGrid(
              items: _summary,
              iconFor: _summaryIcon,
              colorFor: _summaryColor,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NizamiColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.table_chart_outlined,
                        color: NizamiColors.tealDark,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'بيانات التقرير',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  _reportResults(),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _reportResults() {
    if (_loading) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('لا توجد حركة ضمن الفترة المحددة.')),
      );
    }
    return NineSoftResponsiveFinancialTable(
      columns: [
        for (final header in _headers)
          NineSoftFinancialColumn(
            label: header,
            flex: const {'الاسم', 'البيان'}.contains(header) ? 3 : 2,
          ),
      ],
      rows: [
        for (var rowIndex = 0; rowIndex < _rows.length; rowIndex++)
          NineSoftFinancialRow(
            key: Key('financial-report-row-$rowIndex'),
            cells: [
              for (
                var cellIndex = 0;
                cellIndex < _cells(_rows[rowIndex]).length;
                cellIndex++
              )
                Text(
                  _cells(_rows[rowIndex])[cellIndex],
                  textDirection: _isNumericColumn(_headers[cellIndex])
                      ? TextDirection.ltr
                      : null,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _isNumericColumn(_headers[cellIndex])
                      ? const TextStyle(fontWeight: FontWeight.w700)
                      : null,
                ),
            ],
          ),
      ],
      emptyDescription: 'لا توجد حركة ضمن الفترة المحددة.',
    );
  }

  IconData _summaryIcon(int index) => const [
    Icons.analytics_rounded,
    Icons.trending_up_rounded,
    Icons.account_balance_wallet_rounded,
    Icons.verified_rounded,
  ][index < 0 ? 0 : (index > 3 ? 3 : index)];

  Color _summaryColor(int index) => const [
    NizamiColors.blue,
    NizamiColors.teal,
    NizamiColors.green,
    NizamiColors.amber,
  ][index < 0 ? 0 : (index > 3 ? 3 : index)];

  bool _isNumericColumn(String header) =>
      const {'افتتاحي', 'مدين', 'دائن', 'ختامي', 'المبلغ'}.contains(header);
}

class _ReportSelector extends StatelessWidget {
  const _ReportSelector({
    required this.current,
    required this.reports,
    required this.onSelected,
  });

  final String current;
  final Map<String, String> reports;
  final ValueChanged<String> onSelected;

  IconData _icon(String key) => switch (key) {
    'profit_loss' => Icons.trending_up_rounded,
    'balance_sheet' => Icons.account_balance_rounded,
    'cash_flow' => Icons.currency_exchange_rounded,
    _ => Icons.balance_rounded,
  };

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GridView.count(
      key: const Key('financial-report-selector-grid'),
      crossAxisCount: 4,
      crossAxisSpacing: 7,
      mainAxisSpacing: 7,
      childAspectRatio: constraints.maxWidth < 600 ? 1.08 : 3.1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final entry in reports.entries)
          Material(
            key: Key('financial-report-type-${entry.key}'),
            color: entry.key == current
                ? const Color(0xFF087D83)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelected(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: entry.key == current
                        ? const Color(0xFF087D83)
                        : NizamiColors.border,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _icon(entry.key),
                      size: 22,
                      color: entry.key == current
                          ? Colors.white
                          : NizamiColors.tealDark,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.value,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: entry.key == current ? Colors.white : null,
                        fontSize: 10,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _ReportKpiGrid extends StatelessWidget {
  const _ReportKpiGrid({
    required this.items,
    required this.iconFor,
    required this.colorFor,
  });

  final List<(String, String)> items;
  final IconData Function(int index) iconFor;
  final Color Function(int index) colorFor;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 800 ? 4 : 2;
      return GridView.count(
        key: const Key('financial-report-kpi-grid'),
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: constraints.maxWidth >= 800 ? 2.6 : 2.05,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var index = 0; index < items.length; index++)
            _ReportKpiCard(
              label: items[index].$1,
              value: items[index].$2,
              icon: iconFor(index),
              color: colorFor(index),
            ),
        ],
      );
    },
  );
}

class _ReportKpiCard extends StatelessWidget {
  const _ReportKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(10, 9, 10, 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: NizamiColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'ArialMTBlack',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
