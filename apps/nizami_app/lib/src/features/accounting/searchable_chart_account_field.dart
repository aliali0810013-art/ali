import 'package:flutter/material.dart';

import 'chart_accounts_api.dart';

/// Searchable account selector that expands inside the current page.
///
/// Keeping the picker inline avoids modal/bottom-sheet editors and makes long
/// accounting lists usable with keyboard, mouse and touch on the same surface.
class SearchableChartAccountField extends StatefulWidget {
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

  @override
  State<SearchableChartAccountField> createState() =>
      _SearchableChartAccountFieldState();
}

class _SearchableChartAccountFieldState
    extends State<SearchableChartAccountField> {
  final _search = TextEditingController();
  final _focusNode = FocusNode();
  bool _expanded = false;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  ChartAccount? get _selected {
    for (final account in widget.accounts) {
      if (account.code == widget.value) return account;
    }
    return null;
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

  void _toggle() {
    if (widget.onChanged == null) return;
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _select(ChartAccount account) {
    widget.onChanged?.call(account.code);
    setState(() {
      _expanded = false;
      _query = '';
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final accounts = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: widget.onChanged != null,
          label: widget.label,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _toggle,
            child: InputDecorator(
              isEmpty: selected == null,
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: widget.helperText,
                enabled: widget.onChanged != null,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: widget.onChanged == null
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (selected != null)
                            IconButton(
                              tooltip: 'مسح الاختيار',
                              onPressed: () {
                                widget.onChanged?.call(null);
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
              ),
              child: selected == null
                  ? Text(
                      widget.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selected.nameAr,
                          maxLines: 1,
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
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: !_expanded
              ? const SizedBox.shrink()
              : Container(
                  key: const Key('inline-account-search'),
                  margin: const EdgeInsets.only(top: 7),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0D0B356F),
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _search,
                        focusNode: _focusNode,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(
                          labelText: 'ابحث باسم الحساب او رقمه',
                          hintText: 'مثال: الصندوق الرئيسي أو 1060',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: accounts.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: Center(
                                  child: Text('لا توجد حسابات مطابقة'),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                itemCount: accounts.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final account = accounts[index];
                                  final active =
                                      account.code == widget.value;
                                  return ListTile(
                                    dense: true,
                                    selected: active,
                                    leading: Icon(
                                      active
                                          ? Icons.check_circle_rounded
                                          : Icons
                                                .account_balance_wallet_outlined,
                                    ),
                                    title: Text(
                                      account.nameAr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      account.code,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textDirection: TextDirection.ltr,
                                    ),
                                    onTap: () => _select(account),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
