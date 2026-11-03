import 'package:flutter/material.dart';

import '../../core/formatters/latin_digit_formatter.dart';
import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/ninesoft_ui.dart';
import '../../theme/nizami_theme.dart';
import 'accounting_api.dart';
import 'chart_accounts_api.dart';

class AccountTransferPage extends StatefulWidget {
  const AccountTransferPage({
    required this.token,
    required this.branchIds,
    super.key,
  });

  final String token;
  final List<String> branchIds;

  @override
  State<AccountTransferPage> createState() => _AccountTransferPageState();
}

class _AccountTransferPageState extends State<AccountTransferPage> {
  late final AccountingApi _accounting = AccountingApi(token: widget.token);
  late final ChartAccountsApi _chart = ChartAccountsApi(widget.token);
  final _amount = TextEditingController();
  final _description = TextEditingController(
    text: 'تحويل بين الحسابات النقدية',
  );
  String? _branchId;
  List<ChartAccount> _accounts = const [];
  List<Map<String, dynamic>> _transfers = const [];
  String? _fromCode;
  String? _toCode;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _branchId = widget.branchIds.firstOrNull;
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final branchId = _branchId;
    if (branchId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _chart.list(branchId),
        _accounting.listAccountTransfers(branchId: branchId),
      ]);
      final accounts = (values[0] as List<ChartAccount>)
          .where(
            (item) => item.active && item.allowPosting && item.isCashEquivalent,
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _transfers = values[1] as List<Map<String, dynamic>>;
        _fromCode = accounts.any((item) => item.code == _fromCode)
            ? _fromCode
            : accounts.firstOrNull?.code;
        _toCode =
            accounts.any(
              (item) => item.code == _toCode && item.code != _fromCode,
            )
            ? _toCode
            : accounts
                  .where((item) => item.code != _fromCode)
                  .firstOrNull
                  ?.code;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (_branchId == null ||
        _fromCode == null ||
        _toCode == null ||
        _fromCode == _toCode ||
        amount <= 0 ||
        _description.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أكمل حسابي التحويل والمبلغ والبيان بشكل صحيح.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _accounting.storeAccountTransfer(
        branchId: _branchId!,
        fromAccountCode: _fromCode!,
        toAccountCode: _toCode!,
        amount: amount,
        description: _description.text,
      );
      _amount.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم ترحيل التحويل بقيد متوازن.')),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر ترحيل التحويل: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _accountLabel(String? code) {
    final account = _accounts.where((item) => item.code == code).firstOrNull;
    return account == null ? code ?? '' : '${account.code} — ${account.nameAr}';
  }

  String _money(dynamic minor) =>
      '${((int.tryParse(minor?.toString() ?? '') ?? 0) / 100).toStringAsFixed(2)} YER';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(toolbarHeight: 0),
    body: SafeArea(
      child: NineSoftResponsiveBody(
        child: ListView(
          children: [
            NineSoftEntryHeading(
              title: 'تحويل نقدي داخلي',
              subtitle:
                  'من صندوق أو بنك أو محفظة إلى حساب نقدي آخر بقيد محاسبي متوازن',
              icon: Icons.swap_horiz_rounded,
              accent: NizamiColors.green,
              actions: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('تحديث'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            NineSoftEntrySection(
              title: 'بيانات التحويل',
              subtitle: 'حدد الحساب المصدر والوجهة ثم راجع المبلغ والبيان',
              icon: Icons.account_balance_wallet_outlined,
              child: Column(
                children: [
                  if (widget.branchIds.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: _branchId,
                      decoration: const InputDecoration(labelText: 'الفرع'),
                      items: widget.branchIds
                          .map(
                            (id) =>
                                DropdownMenuItem(value: id, child: Text(id)),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => _branchId = value);
                        _load();
                      },
                    ),
                  const SizedBox(height: 10),
                  NineSoftEntryFieldGrid(
                    maxColumns: 3,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _fromCode,
                        decoration: const InputDecoration(labelText: 'من حساب'),
                        items: _accounts
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.code,
                                child: Text('${item.code} — ${item.nameAr}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() {
                          _fromCode = value;
                          if (_toCode == value) _toCode = null;
                        }),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _toCode,
                        decoration: const InputDecoration(
                          labelText: 'إلى حساب',
                        ),
                        items: _accounts
                            .where((item) => item.code != _fromCode)
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.code,
                                child: Text('${item.code} — ${item.nameAr}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _toCode = value),
                      ),
                      TextField(
                        controller: _amount,
                        textDirection: TextDirection.ltr,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [latinDigitFormatter],
                        decoration: const InputDecoration(
                          labelText: 'المبلغ',
                          suffixText: 'YER',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'البيان'),
                  ),
                  const SizedBox(height: 12),
                  NineSoftEntryFooter(
                    label: _saving ? 'جارٍ الترحيل...' : 'ترحيل التحويل',
                    enabled: !_saving,
                    onSave: _saving ? null : _submit,
                    note:
                        'ينشئ التحويل قيدًا محاسبيًا متوازنًا دون تغيير صافي النقد',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            NineSoftEntrySection(
              title: 'التحويلات السابقة',
              subtitle: 'سجل التحويلات النقدية المرحلة بين الحسابات',
              icon: Icons.history_rounded,
              padding: const EdgeInsets.all(12),
              child: _loading
                  ? const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  : _accounts.length < 2
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'أضف حسابين نقديين على الأقل من شجرة الحسابات.',
                        ),
                      ),
                    )
                  : _transfers.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('لا توجد تحويلات سابقة.')),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _transfers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, index) {
                        final row = _transfers[index];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.swap_horiz_rounded),
                            ),
                            title: Text(
                              '${_accountLabel(row['from_account_code']?.toString())} ← ${_accountLabel(row['to_account_code']?.toString())}',
                            ),
                            subtitle: Text(
                              '${row['description'] ?? ''}\n${row['posted_at'] ?? ''}',
                            ),
                            isThreeLine: true,
                            trailing: Text(
                              _money(row['amount_minor']),
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
