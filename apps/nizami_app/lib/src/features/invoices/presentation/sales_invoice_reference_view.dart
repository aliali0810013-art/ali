import 'package:flutter/material.dart';

import 'sales_invoice_view_model.dart';

class SalesInvoiceReferenceView extends StatelessWidget {
  const SalesInvoiceReferenceView({
    required this.document,
    required this.customerField,
    required this.invoiceNumberField,
    required this.branchField,
    required this.dateField,
    required this.employeeField,
    required this.paymentModeField,
    required this.productSearchField,
    required this.barcodeField,
    required this.linesTable,
    required this.notesField,
    required this.settlementField,
    required this.deliveryBanner,
    required this.onAddLine,
    required this.onScanBarcode,
    required this.onSave,
    required this.onPrint,
    required this.onPdf,
    required this.onWhatsapp,
    required this.onNewInvoice,
    required this.onHistory,
    required this.busy,
    required this.locked,
    super.key,
  });

  final SalesInvoiceViewModel document;
  final Widget customerField;
  final Widget invoiceNumberField;
  final Widget branchField;
  final Widget dateField;
  final Widget employeeField;
  final Widget paymentModeField;
  final Widget productSearchField;
  final Widget barcodeField;
  final Widget linesTable;
  final Widget notesField;
  final Widget settlementField;
  final Widget deliveryBanner;
  final VoidCallback? onAddLine;
  final VoidCallback? onScanBarcode;
  final VoidCallback? onSave;
  final VoidCallback? onPrint;
  final VoidCallback? onPdf;
  final VoidCallback? onWhatsapp;
  final VoidCallback? onNewInvoice;
  final VoidCallback? onHistory;
  final bool busy;
  final bool locked;

  static const navy = Color(0xFF0B3676);
  static const blue = Color(0xFF147BE0);
  static const paleBlue = Color(0xFFEAF3FF);
  static const border = Color(0xFFD8E1EF);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          phone: phone,
          onNewInvoice: onNewInvoice,
          onHistory: onHistory,
        ),
        const SizedBox(height: 10),
        deliveryBanner,
        const _SectionTitle(
          title: 'تحرير فاتورة مبيعات',
          icon: Icons.receipt_long_rounded,
        ),
        const SizedBox(height: 10),
        _DocumentGrid(
          customerField: customerField,
          invoiceNumberField: invoiceNumberField,
          branchField: branchField,
          dateField: dateField,
          employeeField: employeeField,
          paymentModeField: paymentModeField,
        ),
        const SizedBox(height: 12),
        _SearchStrip(
          productSearchField: productSearchField,
          barcodeField: barcodeField,
          onScanBarcode: locked ? null : onScanBarcode,
        ),
        const SizedBox(height: 10),
        _Panel(padding: EdgeInsets.zero, child: linesTable),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SoftAction(
                label: 'إضافة صنف',
                icon: Icons.add_circle_rounded,
                color: const Color(0xFF11A83B),
                onPressed: locked ? null : onAddLine,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SoftAction(
                label: 'مسح باركود',
                icon: Icons.qr_code_scanner_rounded,
                color: const Color(0xFF5C35C8),
                onPressed: locked ? null : onScanBarcode,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 760) {
              return Column(
                children: [
                  _SummaryCard(document: document),
                  const SizedBox(height: 10),
                  _DetailsCard(
                    notesField: notesField,
                    settlementField: settlementField,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _SummaryCard(document: document)),
                const SizedBox(width: 12),
                Expanded(
                  child: _DetailsCard(
                    notesField: notesField,
                    settlementField: settlementField,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _FooterActions(
          busy: busy,
          locked: locked,
          onSave: onSave,
          onPrint: onPrint,
          onPdf: onPdf,
          onWhatsapp: onWhatsapp,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.phone,
    required this.onNewInvoice,
    required this.onHistory,
  });

  final bool phone;
  final VoidCallback? onNewInvoice;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: phone ? 12 : 18,
          vertical: phone ? 10 : 14,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: SalesInvoiceReferenceView.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120B3676),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: phone ? 48 : 56,
              height: phone ? 48 : 56,
              decoration: BoxDecoration(
                color: SalesInvoiceReferenceView.paleBlue,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.shopping_cart_checkout_rounded,
                color: SalesInvoiceReferenceView.blue,
                size: 29,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'المبيعات',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: const Color(0xFF071D47),
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'إجراءات الفاتورة',
              onSelected: (value) {
                if (value == 'new') onNewInvoice?.call();
                if (value == 'history') onHistory?.call();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'new', child: Text('فاتورة مبيعات جديدة')),
                PopupMenuItem(value: 'history', child: Text('الفواتير السابقة')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: SalesInvoiceReferenceView.border),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.note_add_outlined, size: 20),
                    SizedBox(width: 7),
                    Text(
                      'فاتورة مبيعات جديدة',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Divider(color: Colors.blueGrey.shade100)),
          const SizedBox(width: 12),
          Icon(icon, color: SalesInvoiceReferenceView.navy, size: 24),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF071D47),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: Colors.blueGrey.shade100)),
        ],
      );
}

class _DocumentGrid extends StatelessWidget {
  const _DocumentGrid({
    required this.customerField,
    required this.invoiceNumberField,
    required this.branchField,
    required this.dateField,
    required this.employeeField,
    required this.paymentModeField,
  });

  final Widget customerField;
  final Widget invoiceNumberField;
  final Widget branchField;
  final Widget dateField;
  final Widget employeeField;
  final Widget paymentModeField;

  @override
  Widget build(BuildContext context) {
    final fields = [
      customerField,
      invoiceNumberField,
      dateField,
      branchField,
      employeeField,
      paymentModeField,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 2;
        const gap = 10.0;
        final fieldWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final field in fields)
              SizedBox(
                width: fieldWidth,
                child: _Panel(
                  padding: const EdgeInsets.all(8),
                  child: field,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SearchStrip extends StatelessWidget {
  const _SearchStrip({
    required this.productSearchField,
    required this.barcodeField,
    required this.onScanBarcode,
  });

  final Widget productSearchField;
  final Widget barcodeField;
  final VoidCallback? onScanBarcode;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(flex: 3, child: productSearchField),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: barcodeField),
          const SizedBox(width: 8),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: onScanBarcode,
              style: FilledButton.styleFrom(
                backgroundColor: SalesInvoiceReferenceView.navy,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text(
                'مسح باركود',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.document});
  final SalesInvoiceViewModel document;

  @override
  Widget build(BuildContext context) {
    final paid = document.paidAmount;
    final due = document.dueAmount;
    return _Panel(
      child: Column(
        children: [
          _MoneyRow(
            label: 'إجمالي الأصناف',
            value: document.subtotal,
            icon: Icons.layers_outlined,
          ),
          _MoneyRow(
            label: 'إجمالي الخصم',
            value: -document.discountAmount,
            icon: Icons.local_offer_outlined,
            valueColor: const Color(0xFFD92E3D),
          ),
          const _MoneyRow(
            label: 'الضريبة',
            value: 0,
            icon: Icons.percent_rounded,
            muted: true,
          ),
          _MoneyRow(
            label: 'الإجمالي النهائي',
            value: document.total,
            icon: Icons.calculate_outlined,
            emphasized: true,
          ),
          _MoneyRow(
            label: 'المبلغ المدفوع',
            value: paid,
            icon: Icons.account_balance_wallet_outlined,
            valueColor: const Color(0xFF138A2E),
          ),
          _MoneyRow(
            label: 'المبلغ المتبقي',
            value: due,
            icon: Icons.schedule_rounded,
            valueColor: const Color(0xFFA55300),
          ),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
    this.emphasized = false,
    this.muted = false,
  });

  final String label;
  final double value;
  final IconData icon;
  final Color? valueColor;
  final bool emphasized;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = valueColor ??
        (emphasized
            ? SalesInvoiceReferenceView.navy
            : const Color(0xFF17233D));
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: emphasized
            ? const Color(0xFFE9F3FF)
            : muted
                ? const Color(0xFFF7F8FA)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: muted ? Colors.blueGrey : color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: muted ? Colors.blueGrey : const Color(0xFF17233D),
                fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
          Text(
            '${value.toStringAsFixed(2)} ر.س',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: muted ? Colors.blueGrey : color,
              fontWeight: FontWeight.w900,
              fontSize: emphasized ? 18 : 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({
    required this.notesField,
    required this.settlementField,
  });

  final Widget notesField;
  final Widget settlementField;

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _MiniHeading(
              icon: Icons.edit_note_rounded,
              label: 'ملاحظات',
            ),
            const SizedBox(height: 8),
            notesField,
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            const _MiniHeading(
              icon: Icons.payments_outlined,
              label: 'التسوية والدفع',
            ),
            const SizedBox(height: 8),
            settlementField,
          ],
        ),
      );
}

class _MiniHeading extends StatelessWidget {
  const _MiniHeading({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: SalesInvoiceReferenceView.navy, size: 20),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ],
      );
}

class _FooterActions extends StatelessWidget {
  const _FooterActions({
    required this.busy,
    required this.locked,
    required this.onSave,
    required this.onPrint,
    required this.onPdf,
    required this.onWhatsapp,
  });

  final bool busy;
  final bool locked;
  final VoidCallback? onSave;
  final VoidCallback? onPrint;
  final VoidCallback? onPdf;
  final VoidCallback? onWhatsapp;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            flex: 3,
            child: _FooterButton(
              label: busy ? 'جارٍ الحفظ...' : 'حفظ',
              icon: Icons.save_outlined,
              color: SalesInvoiceReferenceView.navy,
              foreground: Colors.white,
              onPressed: locked || busy ? null : onSave,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _FooterButton(
              label: 'طباعة',
              icon: Icons.print_outlined,
              color: const Color(0xFFE8F1FF),
              foreground: const Color(0xFF164FA3),
              onPressed: onPrint,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _FooterButton(
              label: 'PDF',
              icon: Icons.picture_as_pdf_outlined,
              color: const Color(0xFFFFECEF),
              foreground: const Color(0xFFC62838),
              onPressed: onPdf,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _FooterButton(
              label: 'واتساب',
              icon: Icons.chat_outlined,
              color: const Color(0xFFEAF9EC),
              foreground: const Color(0xFF168A35),
              onPressed: onWhatsapp,
            ),
          ),
        ],
      );
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 54,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: foreground,
            disabledBackgroundColor: color.withValues(alpha: .45),
            disabledForegroundColor: foreground.withValues(alpha: .55),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: Icon(icon),
          label: Text(
            label,
            maxLines: 1,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
}

class _SoftAction extends StatelessWidget {
  const _SoftAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color.withValues(alpha: .10),
            foregroundColor: color,
            elevation: 0,
            side: BorderSide(color: color.withValues(alpha: .20)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: Icon(icon),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SalesInvoiceReferenceView.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0B0B3676),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: child,
      );
}
