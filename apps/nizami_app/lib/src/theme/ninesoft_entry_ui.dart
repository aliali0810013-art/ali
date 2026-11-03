import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'ninesoft_ui.dart';
import 'nizami_theme.dart';

bool _isEntryMobile(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= NineSoftBreakpoints.entryMobile;

class NineSoftDocumentCommandAction {
  const NineSoftDocumentCommandAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.shortcut,
  });

  final Key key;
  final String label;
  final String? shortcut;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
}

/// Visual-only command surface used by invoice and document editors.
class NineSoftDocumentCommandBar extends StatelessWidget {
  const NineSoftDocumentCommandBar({
    super.key,
    required this.actions,
    this.title = 'اختصارات سريعة',
  });

  final String title;
  final List<NineSoftDocumentCommandAction> actions;

  @override
  Widget build(BuildContext context) {
    final mobile = _isEntryMobile(context);
    final buttons = actions
        .map(
          (action) => SizedBox(
            width: mobile ? 90 : 108,
            height: mobile ? 90 : 96,
            child: Material(
              key: action.key,
              color: action.onPressed == null
                  ? action.color.withValues(alpha: .45)
                  : action.color,
              borderRadius: BorderRadius.circular(15),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: action.onPressed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 31,
                        height: 31,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .28),
                          ),
                        ),
                        child: Icon(action.icon, size: 19, color: Colors.white),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (action.shortcut case final shortcut?)
                        Text(
                          shortcut,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .78),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
        .toList(growable: false);
    return Container(
      key: const ValueKey('document-command-bar'),
      padding: EdgeInsets.all(mobile ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE8F5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A073B68),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bolt_rounded,
                size: 21,
                color: Color(0xFFF2A400),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0A2F57),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (mobile)
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: buttons.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) => buttons[index],
              ),
            )
          else
            Wrap(spacing: 9, runSpacing: 9, children: buttons),
        ],
      ),
    );
  }
}

/// Shared selector for the three real accounting document editors.
class NineSoftDocumentTypeSwitch extends StatelessWidget {
  const NineSoftDocumentTypeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (value: 'receipt', label: 'سند قبض', icon: Icons.wallet_rounded),
      (value: 'payment', label: 'سند صرف', icon: Icons.outbox_rounded),
      (value: 'journal', label: 'قيد بسيط', icon: Icons.menu_book_rounded),
    ];
    return Container(
      key: const ValueKey('document-type-switch'),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE7F3)),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  key: ValueKey('document-type-${item.value}'),
                  color: value == item.value
                      ? const Color(0xFF1554B8)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(item.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 10,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.icon,
                            size: 21,
                            color: value == item.value
                                ? Colors.white
                                : const Color(0xFF52667D),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: value == item.value
                                  ? Colors.white
                                  : const Color(0xFF26394F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// UI-only primitives for fast, consistent RTL document entry.
///
/// These widgets receive display values and callbacks only. They never own
/// persistence, API, accounting, inventory, or synchronization state.
class NineSoftEntryHeading extends StatelessWidget {
  const NineSoftEntryHeading({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.status = 'مستند جديد',
    this.accent = NizamiColors.teal,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String status;
  final Color accent;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = _isEntryMobile(context);
      final identity = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: mobile ? 44 : 53,
            height: mobile ? 44 : 53,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(mobile ? 12 : 15),
              border: Border.all(color: Colors.white.withValues(alpha: .24)),
            ),
            child: Icon(icon, color: Colors.white, size: mobile ? 23 : 28),
          ),
          SizedBox(width: mobile ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: mobile ? 9 : 11,
                    color: const Color(0xFFA6FFF0),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'GESS',
                    color: Colors.white,
                    fontSize: mobile ? 18 : 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: mobile ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: mobile ? 10 : 12,
                    color: const Color(0xFFD8EEEF),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (!mobile && actions.isEmpty) ...[
            const SizedBox(width: 8),
            Icon(Icons.fact_check_outlined, size: 26, color: accent),
          ],
        ],
      );
      return Container(
        key: const Key('ninesoft-entry-heading'),
        width: double.infinity,
        constraints: BoxConstraints(minHeight: mobile ? 0 : 112),
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 15 : 23,
          vertical: mobile ? 16 : 22,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [NizamiColors.navy, NizamiColors.navyDark, NizamiColors.navyLight],
            stops: [0, .56, 1],
          ),
          borderRadius: BorderRadius.circular(mobile ? 18 : 22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x240B356F),
              blurRadius: 27,
              offset: Offset(0, 13),
            ),
          ],
        ),
        child: actions.isEmpty
            ? identity
            : mobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              )
            : Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: actions,
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

class NineSoftEntrySection extends StatelessWidget {
  const NineSoftEntrySection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.step,
    this.action,
    this.accent = NizamiColors.blue,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final String? step;
  final IconData icon;
  final Widget child;
  final Widget? action;
  final Color accent;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = _isEntryMobile(context);
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        key: const Key('ninesoft-entry-section'),
        width: double.infinity,
        padding: padding ?? EdgeInsets.all(mobile ? 15 : 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: .12)
                : NizamiColors.border,
          ),
          boxShadow: dark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x0B0D4B72),
                    blurRadius: 23,
                    offset: Offset(0, 7),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 13),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEDF3F7))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEAF3FF), Color(0xFFF4F7FB)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: NizamiColors.blue, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontFamily: 'GESS',
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: NizamiColors.ink,
                              ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: NizamiColors.muted,
                                  height: 1.4,
                                ),
                          ),
                      ],
                    ),
                  ),
                  ?action,
                  if (step != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        step!,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: accent,
                          fontFamily: 'ArialMTBlack',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              type: MaterialType.transparency,
              child: child,
            ),
          ],
        ),
      );
    },
  );
}

class NineSoftEntryStepData {
  const NineSoftEntryStepData({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

class NineSoftEntrySteps extends StatelessWidget {
  const NineSoftEntrySteps({
    super.key,
    required this.steps,
    this.activeIndex = 0,
  });

  final List<NineSoftEntryStepData> steps;
  final int activeIndex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = _isEntryMobile(context);
      final columns = mobile ? 2 : 4;
      final gap = mobile ? 7.0 : 9.0;
      final itemWidth = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Padding(
        key: const Key('ninesoft-entry-steps'),
        padding: EdgeInsets.only(top: 10, bottom: mobile ? 12 : 17),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < steps.length; index++)
              SizedBox(
                width: itemWidth,
                child: _NineSoftEntryStep(
                  index: index,
                  data: steps[index],
                  active: index == activeIndex,
                  mobile: mobile,
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _NineSoftEntryStep extends StatelessWidget {
  const _NineSoftEntryStep({
    required this.index,
    required this.data,
    required this.active,
    required this.mobile,
  });

  final int index;
  final NineSoftEntryStepData data;
  final bool active;
  final bool mobile;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('ninesoft-entry-step-$index'),
    padding: EdgeInsets.symmetric(
      horizontal: mobile ? 9 : 13,
      vertical: mobile ? 9 : 12,
    ),
    decoration: BoxDecoration(
      color: active ? null : Colors.white,
      gradient: active
          ? const LinearGradient(colors: [Color(0xFFEAF3FF), Color(0xFFFFFFFF)])
          : null,
      borderRadius: BorderRadius.circular(mobile ? 12 : 15),
      border: Border.all(
        color: active ? const Color(0xFFBBD5FA) : const Color(0xFFE3EAF3),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x090A3E66),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          key: Key('ninesoft-entry-step-number-$index'),
          width: mobile ? 25 : 29,
          height: mobile ? 25 : 29,
          decoration: BoxDecoration(
            color: active ? NizamiColors.blue : const Color(0xFFE7F0FC),
            borderRadius: BorderRadius.circular(mobile ? 8 : 10),
          ),
          alignment: Alignment.center,
          child: Text(
            '${index + 1}',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF256794),
              fontSize: mobile ? 10 : 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        SizedBox(width: mobile ? 8 : 11),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: NizamiColors.ink,
                  fontFamily: 'GESS',
                  fontSize: mobile ? 10 : 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                data.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: NizamiColors.muted,
                  fontSize: mobile ? 8 : 9,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Deterministic reference grid: 4 columns wide, 2 columns down through 361,
/// and a single column at 360 and below. Existing callers may still cap the
/// count or override spacing.
class NineSoftEntryFieldGrid extends StatelessWidget {
  const NineSoftEntryFieldGrid({
    super.key,
    required this.children,
    this.minFieldWidth,
    this.gap,
    this.maxColumns = 4,
  }) : assert(maxColumns > 0);

  final List<Widget> children;
  final double? minFieldWidth;
  final double? gap;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (children.isEmpty) return const SizedBox.shrink();
      final available = constraints.maxWidth;
      final mobile = _isEntryMobile(context);
      final resolvedGap = gap ?? (mobile ? 10.0 : 14.0);
      final referenceColumns = available <= 360
          ? 1
          : available <= 1270
          ? 2
          : 4;
      var columns = referenceColumns > maxColumns
          ? maxColumns
          : referenceColumns;
      if (minFieldWidth != null) {
        final calculated =
            ((available + resolvedGap) / (minFieldWidth! + resolvedGap))
                .floor()
                .clamp(1, maxColumns);
        columns = calculated;
      }
      if (columns > children.length) columns = children.length;
      final columnWidth = (available - resolvedGap * (columns - 1)) / columns;
      final inputHeight = mobile ? 43.0 : 45.0;

      Widget sizedInput(Widget field) {
        final isInput =
            field is TextField ||
            field is TextFormField ||
            field is DropdownButtonFormField;
        return isInput
            ? _NineSoftEntryInputScope(
                height: inputHeight,
                radius: 12,
                horizontalPadding: mobile ? 9 : 12,
                child: field,
              )
            : field;
      }

      return Wrap(
        spacing: resolvedGap,
        runSpacing: resolvedGap,
        children: [
          for (final field in children)
            SizedBox(width: columnWidth, child: sizedInput(field)),
        ],
      );
    },
  );
}

class _NineSoftEntryInputScope extends StatelessWidget {
  const _NineSoftEntryInputScope({
    required this.height,
    required this.radius,
    required this.horizontalPadding,
    required this.child,
  });

  final double height;
  final double radius;
  final double horizontalPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inputBorder = WidgetStateInputBorder.resolveWith((states) {
      final Color color;
      final double width;
      if (states.contains(WidgetState.error)) {
        color = NizamiColors.red;
        width = 1.5;
      } else if (states.contains(WidgetState.focused)) {
        color = const Color(0xFF06A98F);
        width = 1.5;
      } else if (states.contains(WidgetState.hovered)) {
        color = const Color(0xFFB9D9EA);
        width = 1;
      } else {
        color = const Color(0xFFDCE9F1);
        width = 1;
      }
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: color, width: width),
      );
    });
    final fillColor = WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? const Color(0xFFF4F7FA)
          : Colors.white,
    );
    final hintStyle = WidgetStateTextStyle.resolveWith(
      (states) => TextStyle(
        color: states.contains(WidgetState.disabled)
            ? const Color(0xFF71869B)
            : const Color(0xFF548E8B),
      ),
    );
    final scopedTheme = InputDecorationThemeData(
      filled: true,
      isDense: true,
      fillColor: fillColor,
      contentPadding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 10,
      ),
      constraints: BoxConstraints.tightFor(height: height),
      border: inputBorder,
      hintStyle: hintStyle,
      labelStyle: hintStyle,
      prefixIconConstraints: BoxConstraints(
        minWidth: height - 3,
        minHeight: height - 3,
        maxHeight: height,
      ),
      suffixIconConstraints: BoxConstraints(
        minWidth: height - 3,
        minHeight: height - 3,
        maxHeight: height,
      ),
    );
    return SizedBox(
      height: height,
      child: Theme(
        data: Theme.of(context).copyWith(
          disabledColor: const Color(0xFF71869B),
          inputDecorationTheme: scopedTheme,
        ),
        child: child,
      ),
    );
  }
}

class _NineSoftCompactEntryCell extends StatelessWidget {
  const _NineSoftCompactEntryCell({
    required this.child,
    this.dense = false,
  });

  final Widget child;
  final bool dense;

  @override
  Widget build(BuildContext context) => _NineSoftEntryInputScope(
    height: dense ? 36 : 43,
    radius: dense ? 8 : 10,
    horizontalPadding: dense ? 5 : 9,
    child: child,
  );
}

class NineSoftDocumentEditorScaffold extends StatelessWidget {
  const NineSoftDocumentEditorScaffold({
    super.key,
    required this.main,
    required this.summary,
  });

  final Widget main;
  final Widget summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width <= NineSoftBreakpoints.entryMobile) {
        return SizedBox(
          key: const Key('ninesoft-document-editor'),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: const Key('ninesoft-editor-main'),
                constraints: const BoxConstraints(minWidth: 0),
                child: main,
              ),
              const SizedBox(height: 12),
              Container(
                key: const Key('ninesoft-editor-summary'),
                constraints: const BoxConstraints(minWidth: 0),
                child: summary,
              ),
            ],
          ),
        );
      }

      final summaryWidth = width > 1270
          ? 304.0
          : width > 1000
          ? 268.0
          : 265.0;
      return _NineSoftDesktopEditorLayout(
        key: const Key('ninesoft-document-editor'),
        summaryWidth: summaryWidth,
        gap: 15,
        stickyTopOffset: 102,
        scrollPosition: Scrollable.maybeOf(context)?.position,
        textDirection: Directionality.of(context),
        main: Container(
          key: const Key('ninesoft-editor-main'),
          constraints: const BoxConstraints(minWidth: 0),
          child: main,
        ),
        summary: SizedBox(
          key: const Key('ninesoft-editor-summary'),
          child: summary,
        ),
      );
    },
  );
}

class _NineSoftDesktopEditorLayout extends MultiChildRenderObjectWidget {
  _NineSoftDesktopEditorLayout({
    super.key,
    required Widget main,
    required Widget summary,
    required this.summaryWidth,
    required this.gap,
    required this.stickyTopOffset,
    required this.scrollPosition,
    required this.textDirection,
  }) : super(children: [main, summary]);

  final double summaryWidth;
  final double gap;
  final double stickyTopOffset;
  final ScrollPosition? scrollPosition;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNineSoftDesktopEditorLayout(
        summaryWidth: summaryWidth,
        gap: gap,
        stickyTopOffset: stickyTopOffset,
        scrollPosition: scrollPosition,
        textDirection: textDirection,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderNineSoftDesktopEditorLayout renderObject,
  ) {
    renderObject
      ..summaryWidth = summaryWidth
      ..gap = gap
      ..stickyTopOffset = stickyTopOffset
      ..scrollPosition = scrollPosition
      ..textDirection = textDirection;
  }
}

class _EditorParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderNineSoftDesktopEditorLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EditorParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EditorParentData> {
  _RenderNineSoftDesktopEditorLayout({
    required this._summaryWidth,
    required this._gap,
    required this._stickyTopOffset,
    required this._scrollPosition,
    required this._textDirection,
  });

  double _summaryWidth;
  double get summaryWidth => _summaryWidth;
  set summaryWidth(double value) {
    if (_summaryWidth == value) return;
    _summaryWidth = value;
    markNeedsLayout();
  }

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  double _stickyTopOffset;
  double get stickyTopOffset => _stickyTopOffset;
  set stickyTopOffset(double value) {
    if (_stickyTopOffset == value) return;
    _stickyTopOffset = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  ScrollPosition? _scrollPosition;
  ScrollPosition? get scrollPosition => _scrollPosition;
  set scrollPosition(ScrollPosition? value) {
    if (identical(_scrollPosition, value)) return;
    if (attached) _scrollPosition?.removeListener(_handleScroll);
    _scrollPosition = value;
    if (attached) _scrollPosition?.addListener(_handleScroll);
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  void _handleScroll() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scrollPosition?.addListener(_handleScroll);
  }

  @override
  void detach() {
    _scrollPosition?.removeListener(_handleScroll);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EditorParentData) {
      child.parentData = _EditorParentData();
    }
  }

  RenderBox get _mainChild => firstChild!;
  RenderBox get _summaryChild => lastChild!;

  @override
  void performLayout() {
    assert(childCount == 2);
    final availableWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : constraints.minWidth;
    final mainWidth = (availableWidth - _summaryWidth - _gap).clamp(
      0.0,
      availableWidth,
    );
    final maxHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : double.infinity;

    _mainChild.layout(
      BoxConstraints(
        minWidth: mainWidth,
        maxWidth: mainWidth,
        maxHeight: maxHeight,
      ),
      parentUsesSize: true,
    );
    _summaryChild.layout(
      BoxConstraints(
        minWidth: _summaryWidth,
        maxWidth: _summaryWidth,
        maxHeight: maxHeight,
      ),
      parentUsesSize: true,
    );

    size = constraints.constrain(
      Size(
        availableWidth,
        _mainChild.size.height > _summaryChild.size.height
            ? _mainChild.size.height
            : _summaryChild.size.height,
      ),
    );

    final mainData = _mainChild.parentData! as _EditorParentData;
    final summaryData = _summaryChild.parentData! as _EditorParentData;
    if (_textDirection == TextDirection.rtl) {
      summaryData.offset = Offset.zero;
      mainData.offset = Offset(_summaryWidth + _gap, 0);
    } else {
      mainData.offset = Offset.zero;
      summaryData.offset = Offset(mainWidth + _gap, 0);
    }
  }

  double get _summaryTranslation {
    final position = _scrollPosition;
    if (position == null || !position.hasPixels || !hasSize) return 0;
    if (axisDirectionToAxis(position.axisDirection) != Axis.vertical) return 0;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport == null) return 0;
    final editorTopOffset = viewport
        .getOffsetToReveal(this, 0, axis: Axis.vertical)
        .offset;
    final requested = position.pixels - (editorTopOffset - _stickyTopOffset);
    final maximum = size.height - _summaryChild.size.height;
    return requested.clamp(0.0, maximum < 0 ? 0.0 : maximum);
  }

  Offset _paintOffsetFor(RenderBox child) {
    final data = child.parentData! as _EditorParentData;
    if (identical(child, _summaryChild)) {
      return data.offset + Offset(0, _summaryTranslation);
    }
    return data.offset;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(_mainChild, offset + _paintOffsetFor(_mainChild));
    context.paintChild(_summaryChild, offset + _paintOffsetFor(_summaryChild));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in [_summaryChild, _mainChild]) {
      final hit = result.addWithPaintOffset(
        offset: _paintOffsetFor(child),
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(
      _paintOffsetFor(child).dx,
      _paintOffsetFor(child).dy,
      0,
      1,
    );
  }
}

class NineSoftScannerStrip extends StatelessWidget {
  const NineSoftScannerStrip({
    super.key,
    required this.input,
    this.shortcutHint = 'Enter للإضافة • F4 للتركيز',
    this.icon = Icons.qr_code_scanner_rounded,
  });

  final Widget input;
  final String shortcutHint;
  final IconData icon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = _isEntryMobile(context);
      return Container(
        key: const Key('ninesoft-scanner-strip'),
        width: double.infinity,
        constraints: BoxConstraints(minHeight: mobile ? 46 : 53),
        margin: const EdgeInsets.only(bottom: 17),
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 10 : 14,
          vertical: mobile ? 8 : 5,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F8FF),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFCFE0F7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D1769E8),
              blurRadius: 11,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: NizamiColors.blue, size: 23),
            const SizedBox(width: 9),
            Expanded(
              child: _NineSoftEntryInputScope(
                height: 43,
                radius: 10,
                horizontalPadding: 9,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: NizamiColors.ink),
                  child: input,
                ),
              ),
            ),
            if (!mobile) ...[
              const SizedBox(width: 9),
              Text(
                shortcutHint,
                key: const Key('ninesoft-scanner-shortcut'),
                maxLines: 1,
                style: const TextStyle(
                  color: NizamiColors.blue,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class NineSoftEntryLineCells {
  const NineSoftEntryLineCells({
    required this.product,
    required this.unit,
    required this.quantity,
    required this.price,
    required this.total,
    this.discount,
    this.onDelete,
    this.semanticsLabel,
  });

  final Widget product;
  final Widget unit;
  final Widget quantity;
  final Widget price;
  final Widget total;
  final Widget? discount;
  final VoidCallback? onDelete;
  final String? semanticsLabel;
}

class NineSoftEntryLineTable extends StatelessWidget {
  const NineSoftEntryLineTable({
    super.key,
    required this.lines,
    this.priceLabel = 'السعر',
    this.forceTableOnMobile = false,
    this.showDiscount = false,
    this.denseReference = false,
  });

  final List<NineSoftEntryLineCells> lines;
  final String priceLabel;
  final bool forceTableOnMobile;
  final bool showDiscount;
  final bool denseReference;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compactTable = forceTableOnMobile && _isEntryMobile(context);
      if (_isEntryMobile(context) && !forceTableOnMobile) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < lines.length; index++) ...[
              NineSoftEntryLineCard(
                index: index,
                line: lines[index],
                priceLabel: priceLabel,
              ),
              if (index != lines.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      }

      return SizedBox(
        key: const Key('ninesoft-entry-line-table'),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('ninesoft-entry-line-header'),
              padding: EdgeInsets.only(
                top: denseReference ? 6 : 9,
                bottom: denseReference ? 5 : 6,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFEAF2FF),
                border: Border(bottom: BorderSide(color: Color(0xFFE6F0F6))),
              ),
              child: _EntryTableRow(
                header: true,
                number: const Text('#'),
                product: const Text('الصنف'),
                unit: const Text('الوحدة'),
                quantity: const Text('الكمية'),
                price: Text(priceLabel),
                discount: showDiscount ? const Text('الخصم') : null,
                total: const Text('الإجمالي'),
                delete: const SizedBox.shrink(),
                showDiscount: showDiscount,
                compact: compactTable,
                hideNumber: denseReference,
              ),
            ),
            const SizedBox(height: 9),
            for (var index = 0; index < lines.length; index++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == lines.length - 1
                      ? 0
                      : (denseReference ? 0 : 9),
                ),
                child: Container(
                  key: Key('ninesoft-entry-line-row-$index'),
                  padding: EdgeInsets.symmetric(
                    vertical: denseReference ? 4 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(denseReference ? 0 : 11),
                    border: denseReference
                        ? const Border(
                            bottom: BorderSide(color: Color(0xFFE5EBF3)),
                          )
                        : Border.all(color: NizamiColors.border),
                  ),
                  child: _EntryTableRow(
                    number: _LineNumber(index: index, mobile: false),
                    product: _NineSoftCompactEntryCell(
                      dense: denseReference,
                      child: lines[index].product,
                    ),
                    unit: _NineSoftCompactEntryCell(
                      dense: denseReference,
                      child: lines[index].unit,
                    ),
                    quantity: _NineSoftCompactEntryCell(
                      dense: denseReference,
                      child: lines[index].quantity,
                    ),
                    price: _NineSoftCompactEntryCell(
                      dense: denseReference,
                      child: lines[index].price,
                    ),
                    discount: showDiscount
                        ? _NineSoftCompactEntryCell(
                            dense: denseReference,
                            child: lines[index].discount ?? const Text('0%'),
                          )
                        : null,
                    total: DefaultTextStyle.merge(
                      style: const TextStyle(
                        color: NizamiColors.navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                      child: lines[index].total,
                    ),
                    delete: _DeleteLineButton(
                      index: index,
                      onDelete: lines[index].onDelete,
                      semanticsLabel: lines[index].semanticsLabel,
                      referenceStyle: denseReference,
                    ),
                    showDiscount: showDiscount,
                    compact: compactTable,
                    hideNumber: denseReference,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _EntryTableRow extends StatelessWidget {
  const _EntryTableRow({
    required this.number,
    required this.product,
    required this.unit,
    required this.quantity,
    required this.price,
    this.discount,
    required this.total,
    required this.delete,
    this.showDiscount = false,
    this.header = false,
    this.compact = false,
    this.hideNumber = false,
  });

  final Widget number;
  final Widget product;
  final Widget unit;
  final Widget quantity;
  final Widget price;
  final Widget? discount;
  final Widget total;
  final Widget delete;
  final bool showDiscount;
  final bool header;
  final bool compact;
  final bool hideNumber;

  @override
  Widget build(BuildContext context) {
    Widget cell(Widget child, int flex) => Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 5),
        child: child,
      ),
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (!hideNumber)
          SizedBox(width: compact ? 24 : 28, child: Center(child: number)),
        cell(product, showDiscount ? 30 : 35),
        cell(unit, showDiscount ? 11 : 13),
        cell(quantity, showDiscount ? 12 : 11),
        cell(price, showDiscount ? 13 : 16),
        if (showDiscount) cell(discount ?? const SizedBox.shrink(), 10),
        cell(total, showDiscount ? 15 : 16),
        SizedBox(width: showDiscount ? 30 : 35, child: Center(child: delete)),
      ],
    );
    if (!header) return row;
    return DefaultTextStyle.merge(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: const Color(0xFF4C7893),
        fontSize: compact ? 9.5 : 10.5,
        fontWeight: FontWeight.w900,
      ),
      child: row,
    );
  }
}

class NineSoftEntryLineCard extends StatelessWidget {
  const NineSoftEntryLineCard({
    super.key,
    required this.index,
    required this.line,
    this.priceLabel = 'السعر',
  });

  final int index;
  final NineSoftEntryLineCells line;
  final String priceLabel;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('ninesoft-entry-line-card-$index'),
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFDCE9F3)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x09083D65),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final track = (constraints.maxWidth - 24) / 4;
        final doubleTrack = track * 2 + 8;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: track,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _LineNumber(index: index, mobile: true),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: doubleTrack,
                  child: ClipRect(
                    child: DefaultTextStyle.merge(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: NizamiColors.ink,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                      child: _NineSoftCompactEntryCell(child: line.product),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: track,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _DeleteLineButton(
                      index: index,
                      onDelete: line.onDelete,
                      semanticsLabel: line.semanticsLabel,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: doubleTrack,
                  child: _MobileEntryCell(
                    label: 'الوحدة',
                    child: _NineSoftCompactEntryCell(child: line.unit),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: doubleTrack,
                  child: _MobileEntryCell(
                    label: 'الكمية',
                    child: _NineSoftCompactEntryCell(child: line.quantity),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: doubleTrack,
                  child: _MobileEntryCell(
                    label: priceLabel,
                    child: _NineSoftCompactEntryCell(child: line.price),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: doubleTrack,
                  child: _MobileEntryCell(
                    label: 'الإجمالي',
                    total: true,
                    child: line.total,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _LineNumber extends StatelessWidget {
  const _LineNumber({required this.index, required this.mobile});

  final int index;
  final bool mobile;

  @override
  Widget build(BuildContext context) => Container(
    width: mobile ? 32 : 27,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE6F3FF),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      '${index + 1}',
      textDirection: TextDirection.ltr,
      style: const TextStyle(
        color: Color(0xFF12588B),
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _DeleteLineButton extends StatelessWidget {
  const _DeleteLineButton({
    required this.index,
    required this.onDelete,
    required this.semanticsLabel,
    this.referenceStyle = false,
  });

  final int index;
  final VoidCallback? onDelete;
  final String? semanticsLabel;
  final bool referenceStyle;

  @override
  Widget build(BuildContext context) => IconButton(
    key: Key('ninesoft-entry-line-delete-$index'),
    tooltip: semanticsLabel ?? 'حذف البند',
    onPressed: onDelete,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    style: IconButton.styleFrom(
      backgroundColor:
          referenceStyle ? const Color(0xFFFFE8EC) : Colors.transparent,
      foregroundColor:
          referenceStyle ? const Color(0xFFE33B4D) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    icon: const Icon(Icons.delete_outline_rounded, size: 19),
  );
}

class _MobileEntryCell extends StatelessWidget {
  const _MobileEntryCell({
    required this.label,
    required this.child,
    this.total = false,
  });

  final String label;
  final Widget child;
  final bool total;

  @override
  Widget build(BuildContext context) {
    if (total) {
      return Container(
        constraints: const BoxConstraints(minHeight: 41),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFECFBF7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: NizamiColors.muted, fontSize: 9),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: NizamiColors.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
                child: child,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: NizamiColors.muted, fontSize: 9),
        ),
        const SizedBox(height: 4),
        ClipRect(child: child),
      ],
    );
  }
}

class NineSoftEntrySummaryRow {
  const NineSoftEntrySummaryRow({
    required this.id,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String id;
  final String label;
  final String value;
  final bool emphasized;
}

class NineSoftEntrySummary extends StatelessWidget {
  const NineSoftEntrySummary({
    super.key,
    required this.rows,
    this.controls,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.helpText,
    this.busy = false,
    this.primaryKey,
  });

  final List<NineSoftEntrySummaryRow> rows;
  final Widget? controls;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? helpText;
  final bool busy;
  final Key? primaryKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = _isEntryMobile(context);
      return Container(
        key: const Key('ninesoft-entry-summary'),
        width: double.infinity,
        padding: EdgeInsets.all(mobile ? 15 : 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: NizamiColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D0B356F),
              blurRadius: 27,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: NizamiColors.border)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.summarize_outlined,
                    color: NizamiColors.blue,
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ملخص الفاتورة',
                          style: TextStyle(
                            color: NizamiColors.ink,
                            fontFamily: 'GESS',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'تفاصيل المبالغ والحفظ',
                          style: TextStyle(
                            color: NizamiColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (controls != null) ...[const SizedBox(height: 14), controls!],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F9FE),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: NizamiColors.border),
              ),
              child: Column(
                children: [for (final row in rows) _SummaryAmountRow(row: row)],
              ),
            ),
            const SizedBox(height: 14),
            _SummaryPrimaryButton(
              buttonKey: primaryKey,
              label: primaryLabel,
              busy: busy,
              onPressed: busy ? null : onPrimary,
            ),
            if (secondaryLabel != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  key: const Key('ninesoft-summary-secondary'),
                  onPressed: busy ? null : onSecondary,
                  child: Text(secondaryLabel!),
                ),
              ),
            ],
            if (helpText != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('ninesoft-summary-help'),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F8FC),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFE0EDF6)),
                ),
                child: Text(
                  helpText!,
                  style: const TextStyle(
                    color: Color(0xFF548295),
                    fontSize: 10,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _SummaryAmountRow extends StatelessWidget {
  const _SummaryAmountRow({required this.row});

  final NineSoftEntrySummaryRow row;

  @override
  Widget build(BuildContext context) => Container(
    key: Key('ninesoft-summary-${row.id}'),
    width: double.infinity,
    margin: EdgeInsets.only(top: row.emphasized ? 14 : 0),
    padding: row.emphasized
        ? const EdgeInsets.fromLTRB(10, 17, 10, 12)
        : const EdgeInsets.symmetric(vertical: 11),
    decoration: row.emphasized
        ? BoxDecoration(
            color: const Color(0xFFDFF7EE),
            borderRadius: BorderRadius.circular(13),
          )
        : null,
    child: Row(
      children: [
        Expanded(
          child: Text(
            row.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: row.emphasized
                  ? const Color(0xFF017A70)
                  : const Color(0xFF718294),
              fontSize: row.emphasized ? 14 : 11,
              fontWeight: row.emphasized ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 2,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              row.value,
              maxLines: 1,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: row.emphasized
                    ? const Color(0xFF017A70)
                    : NizamiColors.ink,
                fontFamily: 'ArialMTBlack',
                fontSize: row.emphasized ? 24 : 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SummaryPrimaryButton extends StatelessWidget {
  const _SummaryPrimaryButton({
    this.buttonKey,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final Key? buttonKey;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    decoration: BoxDecoration(
      gradient: onPressed == null
          ? const LinearGradient(colors: [Color(0xFF9DBDB8), Color(0xFFB7D0CC)])
          : const LinearGradient(
              colors: [Color(0xFF069B87), Color(0xFF00B99F)],
            ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: TextButton(
      key: buttonKey ?? const Key('ninesoft-summary-primary'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(
                fontFamily: 'GESS',
                fontWeight: FontWeight.w800,
              ),
            ),
    ),
  );
}

class NineSoftEntryHint extends StatelessWidget {
  const NineSoftEntryHint({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.accent = NizamiColors.blue,
  });

  final String text;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .075),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withValues(alpha: .13)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
          ),
        ),
      ],
    ),
  );
}

/// Legacy display-only amount primitive retained for existing callers.
/// New document summaries receive preformatted integer/fixed-point strings.
class NineSoftEntryTotalPreview extends StatelessWidget {
  const NineSoftEntryTotalPreview({
    super.key,
    required this.label,
    required this.amount,
    this.subtitle,
    this.currency = 'ر.ي',
    this.accent = NizamiColors.blue,
  });

  final String label;
  final double amount;
  final String? subtitle;
  final String currency;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [accent.withValues(alpha: .1), accent.withValues(alpha: .045)],
      ),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: accent.withValues(alpha: .18)),
    ),
    child: Row(
      children: [
        Icon(Icons.calculate_outlined, color: accent, size: 28),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              '${(amount.isFinite ? amount : 0).toStringAsFixed(2)} $currency',
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: 'ArialMTBlack',
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class NineSoftEntryFooter extends StatelessWidget {
  const NineSoftEntryFooter({
    super.key,
    required this.label,
    required this.onSave,
    this.enabled = true,
    this.icon = Icons.check_circle_outline_rounded,
    this.note = 'راجع الحقول والمبالغ قبل الترحيل',
  });

  final String label;
  final VoidCallback? onSave;
  final bool enabled;
  final IconData icon;
  final String note;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(18),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 440;
        final help = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(note, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        );
        final button = FilledButton.icon(
          onPressed: enabled ? onSave : null,
          icon: Icon(icon),
          label: Text(label),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [help, const SizedBox(height: 11), button],
          );
        }
        return Row(
          children: [
            Expanded(child: help),
            const SizedBox(width: 12),
            button,
          ],
        );
      },
    ),
  );
}
