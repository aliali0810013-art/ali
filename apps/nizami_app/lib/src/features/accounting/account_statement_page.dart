import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/pdf/pdf_export_service.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_financial_ui.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/nizami_theme.dart';
import 'accounting_api.dart';

class AccountStatementPage extends StatefulWidget {
  const AccountStatementPage({
    required this.token,
    required this.branchIds,
    this.accountingApi,
    this.initialBranchId,
    this.initialContactId,
    this.initialContactRole,
    this.initialContactName,
    this.lockContact = false,
    super.key,
  });

  final String token;
  final List<String> branchIds;
  final AccountingApi? accountingApi;
  final String? initialBranchId;
  final String? initialContactId;
  final String? initialContactRole;
  final String? initialContactName;
  final bool lockContact;

  @override
  State<AccountStatementPage> createState() => _AccountStatementPageState();
}

class _AccountStatementPageState extends State<AccountStatementPage> {
  late final AccountingApi _api;
  final _search = TextEditingController();
  String? _branchId;
  List<Map<String, dynamic>> _accounts = const [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic> _statement = const {};
  late DateTime _from = DateTime(DateTime.now().year, 1, 1);
  late DateTime _to = DateTime.now();
  bool _includeChildren = true;
  bool _loading = false;
  bool _sourceLoading = false;
  String? _error;
  Map<String, dynamic>? _sourceDocument;
  String _sourceTypeLabel = '';

  @override
  void initState() {
    super.initState();
    _api = widget.accountingApi ?? AccountingApi(token: widget.token);
    _branchId = widget.branchIds.contains(widget.initialBranchId)
        ? widget.initialBranchId
        : widget.branchIds.firstOrNull;
    final contactId = widget.initialContactId?.trim() ?? '';
    final role = widget.initialContactRole?.trim() ?? '';
    if (contactId.isNotEmpty && const {'customer', 'supplier'}.contains(role)) {
      _selected = <String, dynamic>{
        'id': '$contactId|$role',
        'kind': 'contact',
        'contact_id': contactId,
        'role': role,
        'name': widget.initialContactName?.trim() ?? '',
      };
      _loadStatement();
    } else {
      _loadDirectory();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _money(dynamic minor) {
    final value = int.tryParse(minor?.toString() ?? '') ?? 0;
    return '${(value / 100).toStringAsFixed(2)} YER';
  }

  List<Map<String, dynamic>> get _rows {
    final value = _statement['items'];
    return value is List
        ? value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : const [];
  }

  Future<void> _loadDirectory() async {
    final branchId = _branchId;
    if (branchId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await _api.accountDirectory(
        branchId: branchId,
        query: _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _accounts = values;
        if (_selected == null ||
            !values.any((item) => item['id'] == _selected?['id'])) {
          _selected = values.firstOrNull;
        }
      });
      if (_selected != null) await _loadStatement();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStatement() async {
    final branchId = _branchId;
    final selected = _selected;
    if (branchId == null || selected == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final contact = selected['kind'] == 'contact';
      final value = await _api.accountStatement(
        branchId: branchId,
        accountId: contact ? '' : selected['id']?.toString() ?? '',
        contactId: contact ? selected['contact_id']?.toString() ?? '' : '',
        role: contact ? selected['role']?.toString() ?? '' : '',
        from: _date(_from),
        to: _date(_to),
        includeChildren: !contact && _includeChildren,
      );
      if (mounted) setState(() => _statement = value);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(bool start) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: start ? _from : _to,
    );
    if (selected == null) return;
    setState(() => start ? _from = selected : _to = selected);
    await _loadStatement();
  }

  List<String> _cells(Map<String, dynamic> row) => [
    row['posted_at']?.toString().split('T').first ?? '',
    row['document_number']?.toString() ?? '',
    [
      row['document_type_label']?.toString() ?? '',
      row['description']?.toString() ?? '',
    ].where((value) => value.trim().isNotEmpty).join(' — '),
    row['account_code']?.toString() ?? '',
    _money(row['debit_minor']),
    _money(row['credit_minor']),
    _money(row['balance_minor']),
  ];

  bool _canOpen(Map<String, dynamic> row) =>
      row['can_open_document'] == true &&
      (row['reference_id']?.toString().trim().isNotEmpty ?? false);

  Future<void> _openSource(Map<String, dynamic> row) async {
    final branchId = _branchId;
    final referenceType = row['reference_type']?.toString().trim() ?? '';
    final referenceId = row['reference_id']?.toString().trim() ?? '';
    if (branchId == null || referenceType.isEmpty || referenceId.isEmpty) {
      return;
    }

    setState(() {
      _error = null;
      _sourceLoading = true;
    });
    try {
      final source = await _api.sourceDocument(
        branchId: branchId,
        referenceType: referenceType,
        referenceId: referenceId,
      );
      if (!mounted) return;
      setState(() {
        _sourceDocument = source;
        _sourceTypeLabel =
            row['document_type_label']?.toString() ?? 'مستند محاسبي';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sourceLoading = false);
    }
  }

  static const _headers = [
    'التاريخ',
    'المستند',
    'البيان',
    'الحساب',
    'مدين',
    'دائن',
    'الرصيد',
  ];

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  Future<void> _exportCsv() async {
    final name = _statement['account'] is Map
        ? (_statement['account'] as Map)['name']?.toString() ?? 'account'
        : 'account';
    final filename = 'account_statement_${_date(_to)}.csv';
    final location = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel CSV', extensions: ['csv']),
      ],
    );
    if (location == null) return;
    final lines = [
      _csv('كشف حساب: $name'),
      _headers.map(_csv).join(','),
      ..._rows.map((row) => _cells(row).map(_csv).join(',')),
    ];
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
    final account = _statement['account'] is Map
        ? Map<String, dynamic>.from(_statement['account'] as Map)
        : const <String, dynamic>{};
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final latin = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
    );
    final document = pw.Document(title: 'كشف حساب ${account['name'] ?? ''}');
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
          fontFallback: [latin],
        ),
        build: (_) => [
          pw.Text(
            'كشف حساب ${account['name'] ?? ''}',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'رقم الحساب: ${account['account_number'] ?? account['account_code'] ?? ''}',
          ),
          pw.Text('الفترة: ${_date(_from)} — ${_date(_to)}'),
          pw.SizedBox(height: 8),
          pw.Wrap(
            spacing: 10,
            children: [
              pw.Text(
                'رصيد افتتاحي: ${_money(_statement['opening_balance_minor'])}',
              ),
              pw.Text(
                'إجمالي مدين: ${_money(_statement['total_debit_minor'])}',
              ),
              pw.Text(
                'إجمالي دائن: ${_money(_statement['total_credit_minor'])}',
              ),
              pw.Text(
                'رصيد ختامي: ${_money(_statement['closing_balance_minor'])}',
              ),
            ],
          ),
          pw.SizedBox(height: 10),
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
    final filename = 'account_statement_${_date(_to)}.pdf';
    if (print) {
      await PdfExportService.print(bytes: bytes, filename: filename);
    } else {
      await PdfExportService.save(bytes: bytes, filename: filename);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIsContact = _selected?['kind'] == 'contact';
    final phone = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: AppBar(toolbarHeight: 0),
      body: SafeArea(
        child: NineSoftResponsiveBody(
          child: ListView(
            children: [
              NineSoftEntryHeading(
                title: widget.lockContact
                    ? 'كشف الحساب'
                    : (phone ? 'دفتر الأستاذ' : 'كشف الحساب الموحد'),
                subtitle: widget.lockContact
                    ? '${widget.initialContactName ?? 'الطرف'} — حركة ورصيد ومستندات مفصلة'
                    : (phone
                          ? 'حركة الحساب والمدين والدائن والرصيد'
                          : 'أي حساب أو عميل أو مورد — حركة ورصيد افتتاحي وختامي'),
                icon: widget.lockContact
                    ? Icons.manage_search_rounded
                    : Icons.menu_book_rounded,
                accent: NizamiColors.purple,
                actions: [
                  OutlinedButton.icon(
                    onPressed: _rows.isEmpty ? null : _exportCsv,
                    icon: const Icon(Icons.table_view_rounded),
                    label: const Text('Excel / CSV'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _rows.isEmpty
                        ? null
                        : () => _exportPdf(print: true),
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('طباعة'),
                  ),
                  FilledButton.icon(
                    onPressed: _rows.isEmpty ? null : _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_rounded),
                    label: const Text('PDF'),
                  ),
                ],
              ),
              SizedBox(height: phone ? 8 : 12),
              if (!widget.lockContact)
                NineSoftEntrySection(
                  title: phone ? 'الحساب والفترة' : 'معايير كشف الحساب',
                  subtitle: phone ? 'اختر الحساب ثم الفترة' : 'اختر الحساب والفترة لعرض الحركة والرصيد الفعلي',
                  icon: Icons.tune_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NineSoftEntryFieldGrid(
                        maxColumns: 3,
                        children: [
                          TextField(
                            controller: _search,
                            decoration: InputDecoration(
                              labelText: 'بحث برقم أو اسم الحساب / الطرف',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: IconButton(
                                onPressed: _loadDirectory,
                                icon: const Icon(Icons.arrow_forward_rounded),
                              ),
                            ),
                            onSubmitted: (_) => _loadDirectory(),
                          ),
                          if (widget.branchIds.length > 1)
                            DropdownButtonFormField<String>(
                              initialValue: _branchId,
                              decoration: const InputDecoration(
                                labelText: 'الفرع',
                              ),
                              items: widget.branchIds
                                  .map(
                                    (id) => DropdownMenuItem(
                                      value: id,
                                      child: Text(id),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _branchId = value);
                                _loadDirectory();
                              },
                            ),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _selected?['id']?.toString(),
                            decoration: const InputDecoration(
                              labelText: 'الحساب / العميل / المورد',
                            ),
                            items: _accounts
                                .map(
                                  (item) => DropdownMenuItem(
                                    value: item['id']?.toString(),
                                    child: Text(
                                      '${item['account_code'] ?? item['account_number'] ?? ''} — ${item['name'] ?? ''}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(
                                () => _selected = _accounts.firstWhere(
                                  (item) => item['id']?.toString() == value,
                                ),
                              );
                              _loadStatement();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _pickDate(true),
                            icon: const Icon(Icons.date_range),
                            label: Text('من ${_date(_from)}'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _pickDate(false),
                            icon: const Icon(Icons.event_available),
                            label: Text('إلى ${_date(_to)}'),
                          ),
                          if (!selectedIsContact)
                            FilterChip(
                              label: const Text('يشمل الحسابات الفرعية'),
                              selected: _includeChildren,
                              onSelected: (value) {
                                setState(() => _includeChildren = value);
                                _loadStatement();
                              },
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (!widget.lockContact) const SizedBox(height: 10),
              if (_statement.isNotEmpty) _statementSummary(),
              const SizedBox(height: 10),
              NineSoftEntrySection(
                title: widget.lockContact ? 'تفاصيل كشف الحساب' : (phone ? 'حركة الحساب' : 'تفاصيل كشف الحساب'),
                subtitle: phone
                    ? 'التاريخ والبيان والمدين والدائن والرصيد'
                    : 'بيان كل مستند مدين أو دائن مع الرصيد وإمكانية فتح المستند الأصلي',
                icon: Icons.table_rows_outlined,
                child: _statementResults(),
              ),
              if (_sourceLoading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (_sourceDocument != null) ...[
                const SizedBox(height: 10),
                _SourceDocumentPanel(
                  key: const Key('statement-inline-source'),
                  source: _sourceDocument!,
                  typeLabel: _sourceTypeLabel,
                  onClose: () => setState(() => _sourceDocument = null),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statementResults() {
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
        child: Center(child: Text('لا توجد مستندات للحساب ضمن الفترة.')),
      );
    }
    return NineSoftResponsiveFinancialTable(
      columns: const [
        NineSoftFinancialColumn(label: 'التاريخ', flex: 2),
        NineSoftFinancialColumn(label: 'المستند', flex: 1),
        NineSoftFinancialColumn(label: 'البيان', flex: 3),
        NineSoftFinancialColumn(label: 'عليه', flex: 2),
        NineSoftFinancialColumn(label: 'له', flex: 2),
        NineSoftFinancialColumn(label: 'الرصيد', flex: 2),
      ],
      rows: [for (final row in _rows) _financialRow(row)],
      emptyDescription: 'لا توجد مستندات للحساب ضمن الفترة.',
    );
  }

  Widget _statementSummary() {
    final contact = _selected?['kind'] == 'contact';
    final role = _selected?['role']?.toString();
    final closing =
        int.tryParse(_statement['closing_balance_minor']?.toString() ?? '') ??
        0;
    final closingCaption = !contact || closing == 0
        ? 'الرصيد بعد كل الحركات'
        : role == 'supplier'
        ? (closing > 0 ? 'له عند المنشأة' : 'عليه للمنشأة')
        : (closing > 0 ? 'عليه للمنشأة' : 'له عند المنشأة');
    return NineSoftFinancialSummaryStrip(
      items: [
        NineSoftFinancialSummaryItem(
          label: contact ? 'الرصيد السابق' : 'رصيد افتتاحي',
          value: _money(_statement['opening_balance_minor']),
          icon: Icons.history_rounded,
          color: NizamiColors.blue,
        ),
        NineSoftFinancialSummaryItem(
          label: contact ? 'عليه خلال الفترة' : 'إجمالي مدين',
          value: _money(_statement['total_debit_minor']),
          icon: Icons.arrow_downward_rounded,
          color: NizamiColors.red,
        ),
        NineSoftFinancialSummaryItem(
          label: contact ? 'له خلال الفترة' : 'إجمالي دائن',
          value: _money(_statement['total_credit_minor']),
          icon: Icons.arrow_upward_rounded,
          color: NizamiColors.green,
        ),
        NineSoftFinancialSummaryItem(
          label: 'الرصيد النهائي',
          value: _money(closing.abs()),
          icon: Icons.account_balance_wallet_rounded,
          color: closing == 0 ? NizamiColors.green : NizamiColors.amber,
          caption: closingCaption,
        ),
      ],
    );
  }

  NineSoftFinancialRow _financialRow(Map<String, dynamic> row) {
    final id = row['entry_id'] ?? row['id'];
    final number = row['document_number']?.toString().trim() ?? '';
    final type = row['document_type_label']?.toString().trim() ?? '';
    final description = row['description']?.toString().trim() ?? '';
    return NineSoftFinancialRow(
      key: Key('statement-row-$id'),
      onTap: _canOpen(row) ? () => _openSource(row) : null,
      cells: [
        Text(
          row['posted_at']?.toString().split('T').first ?? '',
          textDirection: TextDirection.ltr,
        ),
        Tooltip(
          message: number,
          child: Text(
            compactDocumentNumber(number),
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(type, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (description.isNotEmpty && description != type)
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        Text(_money(row['debit_minor']), textDirection: TextDirection.ltr),
        Text(_money(row['credit_minor']), textDirection: TextDirection.ltr),
        Text(
          _money(row['balance_minor']),
          key: Key('statement-balance-$id'),
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _SourceDocumentPanel extends StatelessWidget {
  const _SourceDocumentPanel({
    required this.source,
    required this.typeLabel,
    required this.onClose,
    super.key,
  });

  final Map<String, dynamic> source;
  final String typeLabel;
  final VoidCallback onClose;

  Future<void> _printSourceDocument() async {
    final rawDocument = source['document'];
    final document = rawDocument is Map
        ? Map<String, dynamic>.from(rawDocument)
        : const <String, dynamic>{};
    final items = source['items'] is List
        ? (source['items'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    final lines = source['lines'] is List
        ? (source['lines'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    final number =
        document['number']?.toString() ??
        document['invoice_number']?.toString() ??
        source['reference_id']?.toString() ??
        '';
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final latin = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Arial_MT_Black.ttf'),
    );
    final pdf = pw.Document(
      title: '$typeLabel ${compactDocumentNumber(number)}',
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: font,
          bold: font,
          fontFallback: [latin],
        ),
        build: (_) => [
          pw.Text(
            typeLabel,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          if (number.isNotEmpty)
            pw.Text('رقم المستند: ${compactDocumentNumber(number)}'),
          if ((document['party_name']?.toString() ?? '').isNotEmpty)
            pw.Text('الطرف: ${document['party_name']}'),
          if (document['total_minor'] != null)
            pw.Text('الإجمالي: ${_formatMinor(document['total_minor'])} YER'),
          if (document['amount_minor'] != null)
            pw.Text('المبلغ: ${_formatMinor(document['amount_minor'])} YER'),
          if (items.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: const ['الصنف', 'الكمية', 'الإجمالي'],
              data: [
                for (final item in items)
                  [
                    item['name']?.toString() ?? '',
                    item['quantity_milli']?.toString() ?? '',
                    '${_formatMinor(item['line_total_minor'])} YER',
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerRight,
            ),
          ],
          if (lines.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(
              'القيد المحاسبي',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TableHelper.fromTextArray(
              headers: const ['الحساب', 'مدين', 'دائن'],
              data: [
                for (final line in lines)
                  [
                    '${line['account_code'] ?? ''} — ${line['account_name'] ?? ''}',
                    _formatMinor(line['debit_minor']),
                    _formatMinor(line['credit_minor']),
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerRight,
            ),
          ],
        ],
      ),
    );
    await PdfExportService.print(
      bytes: await pdf.save(),
      filename:
          'document-${compactDocumentNumber(number).replaceFirst('#', '')}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawDocument = source['document'];
    final document = rawDocument is Map
        ? Map<String, dynamic>.from(rawDocument)
        : const <String, dynamic>{};
    final rawItems = source['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().toList(growable: false)
        : const <Map>[];
    final rawLines = source['lines'];
    final lines = rawLines is List
        ? rawLines.whereType<Map>().toList(growable: false)
        : const <Map>[];
    final number =
        document['number']?.toString() ??
        document['invoice_number']?.toString() ??
        source['reference_id']?.toString() ??
        '';

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
          unawaited(_printSourceDocument());
        },
      },
      child: Focus(
        autofocus: true,
        child: Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تفاصيل المستند',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق التفاصيل',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Divider(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      typeLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (number.isNotEmpty)
                      Tooltip(
                        message: number,
                        child: Text(
                          'رقم المستند: ${compactDocumentNumber(number)}',
                        ),
                      ),
                    if ((document['party_name']?.toString() ?? '').isNotEmpty)
                      Text('الطرف: ${document['party_name']}'),
                    if (document['total_minor'] != null)
                      Text(
                        'الإجمالي: ${_formatMinor(document['total_minor'])} YER',
                      ),
                    if (document['amount_minor'] != null)
                      Text(
                        'المبلغ: ${_formatMinor(document['amount_minor'])} YER',
                      ),
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'الأصناف',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (final item in items)
                        ListTile(
                          dense: true,
                          title: Text(item['name']?.toString() ?? ''),
                          subtitle: Text(
                            'الكمية: ${item['quantity_milli'] ?? ''}',
                          ),
                          trailing: Text(
                            '${_formatMinor(item['line_total_minor'])} YER',
                          ),
                        ),
                    ],
                    if (lines.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'القيد المحاسبي',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (final line in lines)
                        ListTile(
                          dense: true,
                          title: Text(
                            '${line['account_code'] ?? ''} — ${line['account_name'] ?? ''}',
                          ),
                          subtitle: Text(
                            'مدين ${_formatMinor(line['debit_minor'])} | '
                            'دائن ${_formatMinor(line['credit_minor'])}',
                          ),
                        ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton.tonalIcon(
                        onPressed: () => unawaited(_printSourceDocument()),
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('طباعة سريعة  Ctrl+P'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatMinor(dynamic minor) {
    final value = int.tryParse(minor?.toString() ?? '') ?? 0;
    return (value / 100).toStringAsFixed(2);
  }
}
