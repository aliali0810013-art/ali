import 'package:flutter/material.dart';

import 'nizami_theme.dart';

abstract final class NineSoftBreakpoints {
  static const compact = 620.0;
  static const entryMobile = 700.0;
  static const desktop = 980.0;
  static const wide = 1380.0;
}

class NineSoftResponsiveBody extends StatelessWidget {
  const NineSoftResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = 1480,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(
        padding:
            padding ??
            EdgeInsetsDirectional.fromSTEB(
              MediaQuery.sizeOf(context).width < NineSoftBreakpoints.compact ? 12 : 20,
              16,
              MediaQuery.sizeOf(context).width < NineSoftBreakpoints.compact ? 12 : 20,
              28,
            ),
        child: child,
      ),
    ),
  );
}

class NineSoftPageHeader extends StatelessWidget {
  const NineSoftPageHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    this.subtitle,
    this.actions = const [],
    this.helpText,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final List<Widget> actions;
  final String? helpText;

  String get _resolvedHelpText {
    if (helpText != null && helpText!.trim().isNotEmpty) return helpText!;
    final normalized = title.trim();
    if (normalized.contains('شجرة الحسابات')) {
      return 'تنظم الشجرة حسابات المؤسسة إلى أصول والتزامات وحقوق ملكية وإيرادات ومصروفات. افتح الحسابات التجميعية بالسهم، وأضف الحساب التفصيلي تحت المجموعة الصحيحة. الحساب الذي يسمح بالترحيل يمكن استخدامه في القيود، ولا يُحذف حساب له حركة مالية.';
    }
    if (normalized.contains('المبيعات') || normalized.contains('فاتورة بيع')) {
      return 'اختر العميل عند البيع الآجل، ثم أضف الأصناف والكميات والوحدات والأسعار. راجع الخصم والمدفوع والمتبقي قبل الحفظ. الفاتورة المرحّلة تؤثر في المخزون والحسابات، لذلك استخدم التعديل أو المرتجع وفق الصلاحية بدل حذف التاريخ المالي.';
    }
    if (normalized.contains('المشتريات')) {
      return 'اختر المورد وأضف الأصناف بكمياتها وتكلفتها. الحفظ يحدّث المخزون وذمة المورد والقيد المحاسبي بحسب طريقة السداد. راجع الإجمالي والمدفوع والمتبقي قبل الترحيل.';
    }
    if (normalized.contains('مرتجع')) {
      return 'ابدأ المرتجع من الفاتورة الأصلية حتى يحافظ النظام على الكميات والأسعار والقيود. المرتجع الجزئي يعيد الكمية المحددة فقط، ولا يسمح النظام بتجاوز الكمية القابلة للارتجاع أو تكرار العملية.';
    }
    if (normalized.contains('القيود') || normalized.contains('قيد')) {
      return 'كل قيد يجب أن يكون متوازنًا: مجموع المدين يساوي مجموع الدائن. الترحيل يثبت أثر القيد، والعكس ينشئ قيدًا مقابلًا يحافظ على سجل التدقيق بدل حذف الحركة التاريخية.';
    }
    if (normalized.contains('العملاء')) {
      return 'يعرض القسم العملاء وذممهم وحركاتهم. افتح كشف الحساب لمراجعة الفواتير الآجلة وسندات القبض والتسويات بالمعرّف الثابت للعميل، وليس بتشابه الاسم.';
    }
    if (normalized.contains('المورد')) {
      return 'يعرض القسم الموردين ومستحقاتهم وفواتير الشراء وسندات الصرف. ذمة المورد مستقلة عن ذمة العميل حتى لو كان الشخص نفسه يؤدي الدورين.';
    }
    if (normalized.contains('الأصناف') || normalized.contains('المخزون')) {
      return 'ابحث بالاسم أو الباركود، وراجع الوحدة وسعر البيع والتكلفة والرصيد. استخدم باركود المصنع إن وجد أو أنشئ باركودًا داخليًا فريدًا. حركات المخزون تُنشأ من المستندات المرحّلة ولا تُعدّل يدويًا بلا سند.';
    }
    if (normalized.contains('السند')) {
      return 'سند القبض يثبت استلام مبلغ ويخفض ذمة العميل عند ربطه به، وسند الصرف يثبت دفع مبلغ ويخفض مستحق المورد أو يسجل المصروف. راجع الطرف والحساب والمبلغ قبل الترحيل.';
    }
    if (normalized.contains('التقارير') || normalized.contains('كشف')) {
      return 'حدد النوع والفترة والفرع ثم اعرض التقرير داخل النظام أولًا. العرض للمعاينة فقط؛ الطباعة وPDF إجراءات مستقلة ولا تغيّر أي بيانات محاسبية.';
    }
    if (normalized.contains('المزامنة') || normalized.contains('النسخ')) {
      return 'المزامنة ترسل التغييرات التفاضلية وتحافظ على ترتيب الأحداث بين الأجهزة. النسخة الاحتياطية للاستعادة عند الحاجة؛ راجع العمليات المحجوزة بعد الاستعادة ولا تعِد ترحيل عملية مالية قديمة عشوائيًا.';
    }
    if (normalized.contains('واتساب')) {
      return 'اربط جلسة واتساب مستقلة لكل فرع. إرسال الفاتورة يمر بالخادم ويستخدم معرفًا يمنع تكرار الإرسال عند إعادة المحاولة. تحقق من حالة الاتصال قبل الإرسال.';
    }
    if (normalized.contains('التحويلات')) {
      return 'رسالة التحويل إشعار يحتاج مراجعة، وليست إثباتًا بنكيًا نهائيًا. اربطها بالفاتورة أو سند القبض بعد تحقق المستخدم المخوّل، ولا تغلق فاتورة تلقائيًا اعتمادًا على الرسالة وحدها.';
    }
    return 'استخدم البحث والتصفية للوصول السريع، وراجع البيانات قبل الحفظ. الإجراءات المالية المرحّلة تحفظ في سجل التدقيق، وتخضع لصلاحيات المستخدم والفرع.';
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.help_outline_rounded, color: color, size: 34),
        title: Text('دليل $title'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(_resolvedHelpText, style: const TextStyle(height: 1.7)),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < NineSoftBreakpoints.compact;
      final identity = Row(
        children: [
          Container(
            width: compact ? 46 : 54,
            height: compact ? 46 : 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withValues(alpha: .12)),
            ),
            child: Icon(icon, color: color, size: compact ? 25 : 29),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontFamily: 'GESS',
                    fontSize: compact ? 24 : 30,
                    fontWeight: FontWeight.w800,
                    color: NizamiColors.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'شرح هذا القسم',
            onPressed: () => _showHelp(context),
            icon: const Icon(Icons.help_outline_rounded),
            visualDensity: VisualDensity.compact,
          ),
        ],
      );
      if (compact || actions.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            identity,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 42,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var index = 0; index < actions.length; index++) ...[
                        if (index > 0) const SizedBox(width: 7),
                        actions[index],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: identity),
          const SizedBox(width: 20),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    },
  );
}

class NineSoftPanel extends StatelessWidget {
  const NineSoftPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: .08)
            : NizamiColors.border,
      ),
      boxShadow: Theme.of(context).brightness == Brightness.dark
          ? null
          : const [
              BoxShadow(
                color: Color(0x0B113F5B),
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
    ),
    child: child,
  );
}

class NineSoftWorkspaceBanner extends StatelessWidget {
  const NineSoftWorkspaceBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 118),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
        colors: [NizamiColors.navy, NizamiColors.tealDark],
      ),
      borderRadius: BorderRadius.circular(23),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .17),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 570;
        final copy = Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'GESS',
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 22 : 27,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        );
        final iconBox = Container(
          width: compact ? 54 : 68,
          height: compact ? 54 : 68,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .17),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: Colors.white, size: compact ? 28 : 36),
        );
        final action = actionLabel == null
            ? null
            : FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: color,
                ),
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(actionLabel!),
              );
        return Row(
          children: [
            iconBox,
            const SizedBox(width: 14),
            copy,
            if (!compact && action != null) ...[
              const SizedBox(width: 16),
              action,
            ],
          ],
        );
      },
    ),
  );
}

class NineSoftSearchField extends StatelessWidget {
  const NineSoftSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hintText,
      fillColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF142238)
          : Colors.white,
      prefixIcon: const Icon(Icons.search_rounded, color: NizamiColors.ink),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'مسح البحث',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
    ),
  );
}

class NineSoftMetricCard extends StatelessWidget {
  const NineSoftMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.caption,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? Theme.of(context).colorScheme.surface : color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: dark ? Colors.white.withValues(alpha: .08) : color.withValues(alpha: .10),
        ),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0A0E2A47),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: dark ? Colors.white70 : NizamiColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: 'ArialMTBlack',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: dark ? Colors.white : NizamiColors.ink,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class NineSoftEmptyState extends StatelessWidget {
  const NineSoftEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: NizamiColors.blueSoft,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 38, color: NizamiColors.blue),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: 'GESS',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    ),
  );
}

/// Navy quick access dock, compatible with the existing workspace index map.
/// Index: 0 home, 1 products, 2 reports, 3 more; centerAction opens sales.
class NineSoftMobileDock extends StatelessWidget {
  const NineSoftMobileDock({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.centerAction,
    this.contextLabel = 'العمليات',
    this.contextIcon = Icons.layers_outlined,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? centerAction;
  final String contextLabel;
  final IconData contextIcon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF101B2D) : Colors.white;
    return SafeArea(
      top: false,
      child: Container(
        height: 82,
        padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 7),
        decoration: BoxDecoration(
          color: background,
          border: Border(
            top: BorderSide(
              color: dark ? Colors.white.withValues(alpha: .08) : NizamiColors.border,
            ),
          ),
          boxShadow: dark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x100A2545),
                    blurRadius: 20,
                    offset: Offset(0, -6),
                  ),
                ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _DockButton(
                icon: Icons.home_rounded,
                label: 'الرئيسية',
                selected: currentIndex == 0,
                onTap: () => onSelected(0),
              ),
            ),
            Expanded(
              child: _DockButton(
                icon: contextIcon,
                label: contextLabel,
                selected: currentIndex == 1,
                onTap: () => onSelected(1),
              ),
            ),
            SizedBox(
              width: 66,
              child: Center(
                child: Material(
                  color: NizamiColors.navy,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: centerAction,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.add_rounded, color: Colors.white, size: 29),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _DockButton(
                icon: Icons.bar_chart_rounded,
                label: 'التقارير',
                selected: currentIndex == 2,
                onTap: () => onSelected(2),
              ),
            ),
            Expanded(
              child: _DockButton(
                icon: Icons.settings_outlined,
                label: 'الإعدادات',
                selected: currentIndex == 3,
                onTap: () => onSelected(3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = selected
        ? (dark ? const Color(0xFF9BC0FF) : NizamiColors.navy)
        : (dark ? Colors.white60 : const Color(0xFF4E5E73));
    return Material(
      color: selected
          ? (dark ? const Color(0xFF213653) : const Color(0xFFE4EEFF))
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 25, color: foreground),
              const SizedBox(height: 3),
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'GESS',
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
