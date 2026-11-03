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
            padding ?? const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 28),
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
              color: color.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: .18)),
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
                    fontSize: compact ? 22 : 27,
                    fontWeight: FontWeight.w700,
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
      borderRadius: BorderRadius.circular(23),
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
                blurRadius: 24,
                offset: Offset(0, 9),
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
      prefixIcon: const Icon(Icons.search_rounded),
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
  Widget build(BuildContext context) => NineSoftPanel(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: .72), color],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: .22),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 25),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'ArialMTBlack',
                  fontSize: 18,
                  color: color,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
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
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? centerAction;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
    child: BottomAppBar(
      height: 79,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      color: NizamiColors.navy,
      surfaceTintColor: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
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
              icon: Icons.inventory_2_rounded,
              label: 'المخزون',
              selected: currentIndex == 1,
              onTap: () => onSelected(1),
            ),
          ),
          Expanded(
            child: _DockButton(
              icon: Icons.shopping_bag_rounded,
              label: 'المبيعات',
              selected: false,
              onTap: centerAction ?? () {},
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
              icon: Icons.apps_rounded,
              label: 'ابدأ',
              selected: currentIndex == 3,
              onTap: () => onSelected(3),
            ),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) => Material(
    color: selected ? NizamiColors.tealDark : Colors.transparent,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23, color: selected ? Colors.white : Colors.white70),
            const SizedBox(height: 2),
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'GESS',
                fontSize: 9,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
