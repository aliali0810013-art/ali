import 'package:flutter/material.dart';

import 'ninesoft_ui.dart';
import 'nizami_theme.dart';

/// Returns a compact display reference while callers retain the original
/// document number for a [Tooltip].
String compactDocumentNumber(String documentNumber) {
  final normalized = documentNumber.trim();
  final numericSuffix = RegExp(r'(?:^|-)(\d+)$').firstMatch(normalized);
  if (numericSuffix != null) {
    return '#${BigInt.parse(numericSuffix.group(1)!)}';
  }

  if (normalized.isEmpty) return '#—';
  final segments = normalized.split('-').where((part) => part.isNotEmpty);
  final reference = segments.isEmpty ? normalized : segments.last;
  if (reference.length <= 9 && normalized.length <= 24) return '#$reference';
  if (reference.length <= 9) return '#…$reference';
  return '#…${reference.substring(reference.length - 9)}';
}

/// A single display-only financial metric.
///
/// [value] is rendered verbatim. It is expected to be preformatted from an
/// integer minor-unit value by the caller.
class NineSoftFinancialSummaryItem extends StatelessWidget {
  const NineSoftFinancialSummaryItem({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = NizamiColors.tealDark,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 94),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: .10)
              : NizamiColors.border,
        ),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0B113F5B),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: color,
                        fontFamily: 'ArialMTBlack',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A responsive summary: four columns on wide surfaces and two otherwise.
class NineSoftFinancialSummaryStrip extends StatelessWidget {
  const NineSoftFinancialSummaryStrip({
    super.key,
    required this.items,
    this.spacing = 10,
  });

  final List<NineSoftFinancialSummaryItem> items;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (items.isEmpty) return const SizedBox.shrink();
      final columns = constraints.maxWidth >= 800 ? 4 : 2;
      final itemWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final item in items) SizedBox(width: itemWidth, child: item),
        ],
      );
    },
  );
}

class NineSoftFinancialColumn {
  const NineSoftFinancialColumn({
    required this.label,
    this.flex = 1,
    this.alignment = AlignmentDirectional.centerStart,
  }) : assert(flex > 0);

  final String label;
  final int flex;
  final AlignmentGeometry alignment;
}

/// Display-only cells for one financial table row.
class NineSoftFinancialRow {
  const NineSoftFinancialRow({this.key, required this.cells, this.onTap});

  final Key? key;
  final List<Widget> cells;
  final VoidCallback? onTap;
}

/// A flex-based financial table on desktop and a card list on phones.
///
/// Cells are rendered as supplied. This widget never parses or recomputes
/// their values and deliberately does not use [DataTable] or horizontal
/// scrolling.
class NineSoftResponsiveFinancialTable extends StatelessWidget {
  const NineSoftResponsiveFinancialTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyDescription = 'لا توجد بيانات مالية لعرضها.',
    this.emptyIcon = Icons.receipt_long_outlined,
    this.mobileBreakpoint = NineSoftBreakpoints.entryMobile,
  }) : assert(mobileBreakpoint > 0);

  final List<NineSoftFinancialColumn> columns;
  final List<NineSoftFinancialRow> rows;
  final String emptyDescription;
  final IconData emptyIcon;
  final double mobileBreakpoint;

  @override
  Widget build(BuildContext context) {
    assert(
      rows.every((row) => row.cells.length == columns.length),
      'Every financial row must have exactly one cell per column.',
    );
    if (rows.isEmpty) return _buildEmpty(context);
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < mobileBreakpoint
          ? _buildMobile(context)
          : _buildDesktop(context),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NizamiColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(emptyIcon, size: 34, color: NizamiColors.muted),
          const SizedBox(height: 10),
          Text(
            emptyDescription,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('ninesoft-financial-table-desktop'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NizamiColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: NizamiColors.navy,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final column in columns)
                  Expanded(
                    flex: column.flex,
                    child: Align(
                      alignment: column.alignment,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          13,
                          12,
                          13,
                          12,
                        ),
                        child: Text(
                          column.label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            _FinancialDesktopRow(row: rows[index], columns: columns),
          ],
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context) => Column(
    key: const Key('ninesoft-financial-table-mobile'),
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var index = 0; index < rows.length; index++) ...[
        if (index > 0) const SizedBox(height: 10),
        _FinancialMobileCard(row: rows[index], columns: columns),
      ],
    ],
  );
}

class _FinancialDesktopRow extends StatelessWidget {
  const _FinancialDesktopRow({required this.row, required this.columns});

  final NineSoftFinancialRow row;
  final List<NineSoftFinancialColumn> columns;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: row.key,
      onTap: row.onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < columns.length; index++)
              Expanded(
                flex: columns[index].flex,
                child: Align(
                  alignment: columns[index].alignment,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      13,
                      12,
                      13,
                      12,
                    ),
                    child: row.cells[index],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _FinancialMobileCard extends StatelessWidget {
  const _FinancialMobileCard({required this.row, required this.columns});

  final NineSoftFinancialRow row;
  final List<NineSoftFinancialColumn> columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: NizamiColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: row.key,
        onTap: row.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < columns.length; index++) ...[
                if (index > 0) const Divider(height: 19),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        columns[index].label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Align(
                        alignment: columns[index].alignment,
                        child: row.cells[index],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
