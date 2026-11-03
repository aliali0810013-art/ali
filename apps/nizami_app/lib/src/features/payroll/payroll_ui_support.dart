import 'package:flutter/material.dart';

import '../../theme/ninesoft_ui.dart';
import '../../theme/nizami_theme.dart';
import '../sync/payroll_outbox.dart';

String formatPayrollMinor(int value, {String currency = 'ر.ي'}) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return '${negative ? '-' : ''}$buffer $currency';
}

bool hasPayrollPermission(
  String roleCode,
  Iterable<String> permissions,
  String permission,
) => roleCode == 'owner' || permissions.contains(permission);

class PayrollPageBody extends StatelessWidget {
  const PayrollPageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(
      child: SingleChildScrollView(
        primary: true,
        child: NineSoftResponsiveBody(child: child),
      ),
    ),
  );
}

class PayrollOperationBanner extends StatelessWidget {
  const PayrollOperationBanner({super.key, required this.entry});

  final PayrollOutboxEntry entry;

  @override
  Widget build(BuildContext context) {
    final review = entry.state == PayrollOutboxState.needsReview;
    final color = review ? const Color(0xFFB45309) : NizamiColors.blue;
    return Container(
      key: Key('payroll-status-${entry.operationId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        border: Border.all(color: color.withValues(alpha: .2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            review ? Icons.warning_amber_rounded : Icons.cloud_upload_outlined,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              review
                  ? 'يحتاج مراجعة${entry.rejectionMessage == null ? '' : ': ${entry.rejectionMessage}'}'
                  : 'محفوظ محليًا بانتظار الإرسال',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class PayrollStatusChip extends StatelessWidget {
  const PayrollStatusChip({super.key, required this.status, this.operationId});

  final String status;
  final String? operationId;

  @override
  Widget build(BuildContext context) {
    final reversed = status == 'reversed';
    final color = reversed ? const Color(0xFFB45309) : NizamiColors.tealDark;
    return Container(
      key: operationId == null ? null : Key('payroll-status-$operationId'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Text(
        reversed ? 'معكوس — للقراءة فقط' : 'مرحّل/معتمد — للقراءة فقط',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
