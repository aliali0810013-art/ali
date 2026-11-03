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
    this.lineEntryControls,
    required this.linesTable,
    required this.notesField,
    required this.settlementField,
    required this.deliveryBanner,
    this.lockedControls,
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
  final Widget? lineEntryControls;
  final Widget linesTable;
  final Widget notesField;
  final Widget settlementField;
  final Widget deliveryBanner;
  final Widget? lockedControls;
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
      key: const Key('ninesoft-document-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          phone: phone,
          onNewInvoice: onNewInvoice,
          onHistory: onHistory,
        ),
        if (locked) ...[
          const SizedBox(height: 6),
          deliveryBanner,
        ],
        const SizedBox(height: 5),
        const _SectionTitle(
          title: 'تحرير فاتورة مبيعات',
          icon: Icons.receipt_long_rounded,
        ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: const Key('invoice-section-document'),
          child: _DocumentGrid(
          customerField: customerField,
          invoiceNumberField: invoiceNumberField,
          branchField: branchField,
          dateField: dateField,
          employeeField: employeeField,
          paymentModeField: paymentModeField,
          ),
        ),
        const SizedBox(height: 9),
        _SearchStrip(
          productSearchField: KeyedSubtree(
            key: const Key('invoice-shortcut-f3'),
            child: productSearchField,
          ),
          barcodeField: KeyedSubtree(
            key: const Key('invoice-shortcut-f4'),
            child: barcodeField,
          ),
          onScanBarcode: locked ? null : onScanBarcode,
        ),
        const SizedBox(height: 7),
        if (lineEntryControls != null) ...[
          _Panel(child: lineEntryControls!),
          const SizedBox(height: 7),
        ],
        KeyedSubtree(
          key: const Key('invoice-section-lines'),
          child: _Panel(padding: EdgeInsets.zero, child: linesTable),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: const Key('invoice-shortcut-f2'),
                child: _SoftAction(
                buttonKey: const Key('invoice-add-line'),
                label: 'إضافة صنف',
                icon: Icons.add_circle_rounded,
                color: const Color(0xFF11A83B),
                onPressed: locked ? null : onAddLine,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SoftAction(
                buttonKey: const Key('invoice-reference-scan'),
                label: 'مسح باركود',
                icon: Icons.qr_code_scanner_rounded,
                color: const Color(0xFF5C35C8),
                onPressed: locked ? null : onScanBarcode,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _SummaryCard(document: document)),
                const SizedBox(width: 12),
                Expanded(
                  child: KeyedSubtree(
                    key: const Key('invoice-section-notes'),
                    child: _DetailsCard(
                    notesField: notesField,
                    settlementField: settlementField,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (lockedControls != null) ...[
          const SizedBox(height: 8),
          lockedControls!,
        ],
        const SizedBox(height: 8),
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
          horizontal: phone ? 2 : 6,
          vertical: phone ? 4 : 8,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: SalesInvoiceReferenceView.border),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: phone ? 42 : 48,
              height: phone ? 42 : 48,
              decoration: BoxDecoration(
                color: SalesInvoiceReferenceView.paleBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.shopping_cart_checkout_rounded,
                color: SalesInvoiceReferenceView.blue,
                size: 25,
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
            Container(
              height: phone ? 42 : 46,
              constraints: BoxConstraints(
                minWidth: phone ? 150 : 180,
                maxWidth: phone ? 178 : 220,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SalesInvoiceReferenceView.border,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A0B3676),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('invoice-shortcut-new'),
                      onTap: onNewInvoice,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.note_add_outlined, size: 19),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'فاتورة مبيعات جديدة',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xFF071D47),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 36,
                    decoration: const BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: SalesInvoiceReferenceView.border,
                        ),
                      ),
                    ),
                    child: IconButton(
                      key: const Key('invoice-history-open-primary'),
                      tooltip: 'الفواتير السابقة',
                      onPressed: onHistory,
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 21,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final label = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: SalesInvoiceReferenceView.navy, size: 22),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF071D47),
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 520) {
            return Align(
              alignment: AlignmentDirectional.center,
              child: label,
            );
          }
          return Row(
            children: [
              Expanded(child: Divider(color: Colors.blueGrey.shade100)),
              const SizedBox(width: 12),
              Flexible(flex: 3, child: label),
              const SizedBox(width: 12),
              Expanded(child: Divider(color: Colors.blueGrey.shade100)),
            ],
          );
        },
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
                child: field,
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final mobile = MediaQuery.sizeOf(context).width < 700;
          final scan = SizedBox(
            height: mobile ? 40 : 50,
            child: FilledButton.icon(
              onPressed: onScanBarcode,
              style: FilledButton.styleFrom(
                backgroundColor: SalesInvoiceReferenceView.navy,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: const Text(
                'مسح باركود',
                maxLines: 1,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          );
          return Row(
            children: [
              Expanded(flex: 5, child: productSearchField),
              const SizedBox(width: 8),
              if (constraints.maxWidth >= 620) ...[
                Expanded(flex: 2, child: barcodeField),
                const SizedBox(width: 8),
              ],
              scan,
            ],
          );
        },
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
            currency: document.currency,
            icon: Icons.layers_outlined,
          ),
          _MoneyRow(
            label: 'إجمالي الخصم',
            value: -document.discountAmount,
            currency: document.currency,
            icon: Icons.local_offer_outlined,
            valueColor: const Color(0xFFD92E3D),
          ),
          _MoneyRow(
            label: 'الضريبة',
            value: 0,
            currency: document.currency,
            icon: Icons.percent_rounded,
            muted: true,
          ),
          KeyedSubtree(
            key: const Key('ninesoft-summary-total'),
            child: _MoneyRow(
            label: 'الإجمالي النهائي',
            value: document.total,
            currency: document.currency,
            icon: Icons.calculate_outlined,
            emphasized: true,
            ),
          ),
          _MoneyRow(
            label: 'المبلغ المدفوع',
            value: paid,
            currency: document.currency,
            icon: Icons.account_balance_wallet_outlined,
            valueColor: const Color(0xFF138A2E),
          ),
          _MoneyRow(
            label: 'المبلغ المتبقي',
            value: due,
            currency: document.currency,
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
    required this.currency,
    this.valueColor,
    this.emphasized = false,
    this.muted = false,
  });

  final String label;
  final double value;
  final IconData icon;
  final String currency;
  final Color? valueColor;
  final bool emphasized;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = valueColor ??
        (emphasized
            ? SalesInvoiceReferenceView.navy
            : const Color(0xFF17233D));
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            MediaQuery.sizeOf(context).width < 700 || constraints.maxWidth < 170;
        final title = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 16 : 20, color: muted ? Colors.blueGrey : color),
            SizedBox(width: compact ? 4 : 8),
            Flexible(
              child: Text(
                label,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 10.5 : 13,
                  color: muted ? Colors.blueGrey : const Color(0xFF17233D),
                  fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
          ],
        );
        final amount = Text(
          '${value.toStringAsFixed(2)} ${currency == 'YER' ? 'ر.ي' : currency}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: muted ? Colors.blueGrey : color,
            fontFamily: 'ArialMTBlack',
            fontWeight: FontWeight.w900,
            fontSize: compact ? (emphasized ? 13 : 11.5) : (emphasized ? 18 : 15),
          ),
        );
        return Container(
          margin: const EdgeInsets.only(bottom: 5),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 10,
            vertical: compact ? 6 : 9,
          ),
          decoration: BoxDecoration(
            color: emphasized
                ? const Color(0xFFE9F3FF)
                : muted
                    ? const Color(0xFFF7F8FA)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    title,
                    const SizedBox(height: 3),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: amount,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 6),
                    Flexible(child: amount),
                  ],
                ),
        );
      },
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
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    final gap = mobile ? 4.0 : 8.0;
    return _Panel(
      padding: EdgeInsets.all(mobile ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _MiniHeading(
            icon: Icons.edit_note_rounded,
            label: 'ملاحظات',
          ),
          SizedBox(height: gap),
          notesField,
          SizedBox(height: gap),
          const Divider(height: 1),
          SizedBox(height: gap),
          const _MiniHeading(
            icon: Icons.payments_outlined,
            label: 'التسوية والدفع',
          ),
          SizedBox(height: gap),
          settlementField,
        ],
      ),
    );
  }
}

class _MiniHeading extends StatelessWidget {
  const _MiniHeading({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: SalesInvoiceReferenceView.navy, size: 18),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
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
              buttonKey: const Key('ninesoft-summary-primary'),
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
    this.buttonKey,
    required this.label,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onPressed,
  });

  final Key? buttonKey;
  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return SizedBox(
        height: mobile ? 42 : 54,
        child: FilledButton.icon(
          key: buttonKey,
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: foreground,
            disabledBackgroundColor: color.withValues(alpha: .45),
            disabledForegroundColor: foreground.withValues(alpha: .55),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: Icon(icon, size: 20),
          label: Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      );
  }
}

class _SoftAction extends StatelessWidget {
  const _SoftAction({
    this.buttonKey,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final Key? buttonKey;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return SizedBox(
        height: mobile ? 40 : 52,
        child: FilledButton.icon(
          key: buttonKey,
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SalesInvoiceReferenceView.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0B0B3676),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}
