import 'package:flutter/material.dart';

import 'chart_accounts_api.dart';

class SearchableChartAccountField extends StatelessWidget {
  const SearchableChartAccountField({
    super.key,
    required this.accounts,
    required this.value,
    required this.label,
    required this.onChanged,
    this.hint = 'اختر الحساب',
    this.helperText,
  });

  final List<ChartAccount> accounts;
  final String? value;
  final String label;
  final String hint;
  final String? helperText;
  final ValueChanged<String?>? onChanged;

  ChartAccount? get _selected {
    for (final account in accounts) {
      if (account.code == value) return account;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context) async {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final picker = _ChartAccountSearchPanel(
      accounts: accounts,
      selectedCode: value,
    );
    final selected = mobile
        ? await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (context) =>
                FractionallySizedBox(heightFactor: .88, child: picker),
          )
        : await showDialog<String>(
            context: context,
            builder: (context) => Dialog(
              insetPadding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 680,
                  maxHeight: 720,
                ),
                child: picker,
              ),
            ),
          );
    if (selected != null && context.mounted) onChanged?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Semantics(
      button: onChanged != null,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onChanged == null ? null : () => _openPicker(context),
        child: InputDecorator(
          isEmpty: selected == null,
          decoration: InputDecoration(
            labelText: label,
            helperText: helperText,
            enabled: onChanged != null,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: selected == null || onChanged == null
                ? null
                : IconButton(
                    tooltip: 'مسح الاختيار',
                    onPressed: () => onChanged?.call(null),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
          child: selected == null
              ? Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selected.nameAr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ChartAccountSearchPanel extends StatefulWidget {
  const _ChartAccountSearchPanel({
    required this.accounts,
    required this.selectedCode,
  });

  final List<ChartAccount> accounts;
  final String? selectedCode;

  @override
  State<_ChartAccountSearchPanel> createState() =>
      _ChartAccountSearchPanelState();
}

class _ChartAccountSearchPanelState extends State<_ChartAccountSearchPanel> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ChartAccount> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.accounts;
    return widget.accounts
        .where(
          (account) =>
              account.code.toLowerCase().contains(query) ||
              account.nameAr.toLowerCase().contains(query) ||
              account.nameEn.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _filtered;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'اختيار الحساب',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'اغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                labelText: 'ابحث باسم الحساب او رقمه',
                hintText: 'مثال الصندوق الرئيسي او 1060',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: accounts.isEmpty
                  ? const Center(child: Text('لا توجد حسابات مطابقة'))
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: accounts.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final account = accounts[index];
                        final selected = account.code == widget.selectedCode;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          selected: selected,
                          leading: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.account_balance_wallet_outlined,
                          ),
                          title: Text(
                            account.nameAr,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            account.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                          ),
                          onTap: () => Navigator.pop(context, account.code),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
