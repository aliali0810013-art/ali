import 'package:flutter/material.dart';

import '../../theme/ninesoft_entry_ui.dart';
import '../../theme/nizami_theme.dart';
import 'payroll_models.dart';
import 'payroll_ui_support.dart';

class EmployeeLedgerPage extends StatelessWidget {
  const EmployeeLedgerPage({
    super.key,
    required this.employee,
    required this.envelope,
  });

  final Employee employee;
  final PayrollEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final employeeJson = employee.toJson();
    final rows = _rows();
    return PayrollPageBody(
      child: Column(
        key: Key('payroll-ledger-${employee.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NineSoftEntryHeading(
            title: 'كشف الموظف',
            subtitle: '${employee.name} • ${employee.phone ?? 'لا يوجد هاتف'}',
            icon: Icons.receipt_long_rounded,
            status: employee.active ? 'موظف نشط' : 'موظف غير نشط — سجل تاريخي',
            actions: [
              OutlinedButton.icon(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('العودة للموظفين'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          NineSoftEntrySection(
            title: 'ملخص الذمة',
            subtitle: 'أرصدة 1250 و2250 القانونية من اللقطة المعتمدة',
            icon: Icons.account_balance_wallet_outlined,
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Balance(
                  label: 'رصيد السلف',
                  value: _amount(employeeJson['advance_balance_minor']),
                ),
                _Balance(
                  label: 'مستحق الرواتب',
                  value: _amount(employeeJson['payable_balance_minor']),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NineSoftEntrySection(
            title: 'حركة الموظف',
            subtitle:
                'السلف ومستحقات المسير والمدفوعات فقط؛ مصروف الراتب والنقد ليسا سطور ذمة موظف',
            icon: Icons.timeline_rounded,
            child: rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text('لا توجد حركات في الكشف حتى الآن'),
                    ),
                  )
                : Column(
                    children: [for (final row in rows) _LedgerRow(row: row)],
                  ),
          ),
        ],
      ),
    );
  }

  List<_EmployeeLedgerRow> _rows() {
    final values = <_EmployeeLedgerRow>[];
    for (final advance in envelope.employeeAdvances.where(
      (row) => row.employeeId == employee.id,
    )) {
      final json = advance.toJson();
      final occurredAt = _date(json['occurred_at']);
      values.add(
        _EmployeeLedgerRow(
          sourceId: advance.id,
          occurredAt: occurredAt,
          date: _dateText(json['occurred_at']),
          source: advance.documentKind == 'employee_advance'
              ? 'سلفة/سحب ${advance.id}'
              : 'عكس سلفة ${advance.reversalOfId ?? advance.id}',
          debit: advance.documentKind == 'employee_advance'
              ? advance.amountMinor
              : null,
          credit: advance.documentKind == 'employee_advance'
              ? null
              : advance.amountMinor,
          status: advance.status,
          metadata: [
            'التصنيف: ${json['category'] ?? '—'}',
            'الحساب: ${json['account_code'] ?? '—'}',
            'الملاحظة: ${json['note'] ?? json['reason'] ?? '—'}',
          ],
          detail: json,
        ),
      );
    }
    final runs = {for (final run in envelope.payrollRuns) run.id: run};
    for (final item in envelope.payrollRunItems.where(
      (row) => row.employeeId == employee.id,
    )) {
      final run = runs[item.payrollRunId];
      if (run == null || run.documentKind != 'payroll_run') continue;
      final runJson = run.toJson();
      values.add(
        _EmployeeLedgerRow(
          sourceId: item.id,
          occurredAt: _date(runJson['occurred_at']),
          date: _dateText(runJson['occurred_at']),
          source: 'مستحق مسير ${item.payrollRunId}',
          credit: item.netMinor,
          remaining: item.remainingMinor,
          status: run.status,
          metadata: [
            'الموظف: ${item.toJson()['employee_name_snapshot'] ?? employee.name}',
            'الفترة: ${runJson['period_month'] ?? '—'}',
          ],
          detail: {...runJson, 'item': item.toJson()},
        ),
      );
    }
    for (final reversal in envelope.payrollRuns.where(
      (run) => run.documentKind == 'payroll_run_reversal',
    )) {
      final originalId = reversal.reversalOfId;
      if (originalId == null) continue;
      final originalItems = envelope.payrollRunItems.where(
        (item) =>
            item.payrollRunId == originalId && item.employeeId == employee.id,
      );
      for (final item in originalItems) {
        final json = reversal.toJson();
        values.add(
          _EmployeeLedgerRow(
            sourceId: '${reversal.id}:${item.id}',
            occurredAt: _date(json['occurred_at']),
            date: _dateText(json['occurred_at']),
            source: 'عكس مستحق مسير $originalId',
            debit: item.netMinor,
            status: reversal.status,
            metadata: ['السبب: ${json['reason'] ?? '—'}'],
            detail: {...json, 'original_item': item.toJson()},
          ),
        );
      }
    }
    final payments = {
      for (final payment in envelope.payrollPayments) payment.id: payment,
    };
    for (final item in envelope.payrollPaymentItems.where(
      (row) => row.employeeId == employee.id,
    )) {
      final json = item.toJson();
      final payment = payments[item.payrollPaymentId];
      if (payment == null) continue;
      final paymentJson = payment.toJson();
      final reversal = payment.documentKind == 'payroll_payment_reversal';
      values.add(
        _EmployeeLedgerRow(
          sourceId: item.id,
          occurredAt: _date(paymentJson['occurred_at']),
          date: _dateText(paymentJson['occurred_at']),
          source: reversal
              ? 'عكس دفعة راتب ${payment.reversalOfId ?? payment.id}'
              : 'دفعة راتب ${item.payrollPaymentId}',
          debit: reversal ? null : json['amount_minor'] as int?,
          credit: reversal ? json['amount_minor'] as int? : null,
          status: payment.status,
          metadata: [
            'الموظف: ${json['employee_name_snapshot'] ?? employee.name}',
            'الحساب: ${paymentJson['account_code'] ?? '—'}',
            if (reversal) 'السبب: ${paymentJson['reason'] ?? '—'}',
          ],
          detail: {...paymentJson, 'item': json},
        ),
      );
    }
    values.sort((a, b) {
      final byDate = b.occurredAt.compareTo(a.occurredAt);
      return byDate != 0 ? byDate : b.sourceId.compareTo(a.sourceId);
    });
    return values;
  }

  static DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static String _dateText(Object? value) => value?.toString() ?? '—';

  static String _amount(Object? value) =>
      formatPayrollMinor(value is int ? value : 0);
}

class _Balance extends StatelessWidget {
  const _Balance({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 180),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: NizamiColors.blueSoft,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _EmployeeLedgerRow {
  const _EmployeeLedgerRow({
    required this.sourceId,
    required this.occurredAt,
    required this.date,
    required this.source,
    this.debit,
    this.credit,
    this.remaining,
    required this.status,
    required this.metadata,
    required this.detail,
  });

  final String sourceId;
  final DateTime occurredAt;
  final String date;
  final String source;
  final int? debit;
  final int? credit;
  final int? remaining;
  final String status;
  final List<String> metadata;
  final Map<String, dynamic> detail;
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.row});

  final _EmployeeLedgerRow row;

  void _showDetail(BuildContext context) {
    final entries = row.detail.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: Key('payroll-ledger-detail-${row.sourceId}'),
        title: Text(row.source),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('تفاصيل قانونية للقراءة فقط'),
                const SizedBox(height: 10),
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SelectableText('${entry.key}: ${entry.value}'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    key: Key('payroll-ledger-row-${row.sourceId}'),
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: NizamiColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 260,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.source,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(row.date, textDirection: TextDirection.ltr),
              for (final value in row.metadata)
                Text(value, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (row.debit != null) Text('مدين ${formatPayrollMinor(row.debit!)}'),
        if (row.credit != null) Text('دائن ${formatPayrollMinor(row.credit!)}'),
        if (row.remaining != null)
          Text('المتبقي ${formatPayrollMinor(row.remaining!)}'),
        PayrollStatusChip(status: row.status),
        IconButton(
          key: Key('payroll-ledger-open-${row.sourceId}'),
          tooltip: 'فتح التفاصيل القانونية',
          onPressed: () => _showDetail(context),
          icon: const Icon(Icons.open_in_new_rounded),
        ),
      ],
    ),
  );
}
