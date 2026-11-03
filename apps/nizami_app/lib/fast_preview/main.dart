import 'package:flutter/material.dart';
import 'fast_screens.dart';

/// Local visual preview only. No API, database, or accounting initialization.
void main() => runApp(const NineSoftLocalFastPreview());

class NineSoftLocalFastPreview extends StatefulWidget {
  const NineSoftLocalFastPreview({super.key});

  @override
  State<NineSoftLocalFastPreview> createState() => _NineSoftLocalFastPreviewState();
}

class _NineSoftLocalFastPreviewState extends State<NineSoftLocalFastPreview> {
  int selected = 0;

  void open(int index) {
    if (index < 0 || index >= fastPreviewScreens.length) return;
    setState(() => selected = index);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NineSoft Local UI Fast Preview',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar', 'YE'),
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'GESS',
      scaffoldBackgroundColor: const Color(0xFFF7F9FE),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0A3E91),
        surface: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    ),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 1000;
          return Scaffold(
            drawer: desktop ? null : Drawer(
              width: 300,
              child: SafeArea(child: _menu(context, closeOnSelect: true)),
            ),
            body: Row(children: [
              if (desktop) SizedBox(width: 260, child: _menu(context)),
              Expanded(child: Column(children: [
                _header(context, desktop: desktop),
                Expanded(child: FastPreviewScreen(
                  key: ValueKey('preview-' + selected.toString()),
                  index: selected,
                  onOpenScreen: open,
                )),
                if (!desktop) _bottomBar(),
              ])),
            ]),
          );
        },
      ),
    ),
  );

  Widget _menu(BuildContext context, {bool closeOnSelect = false}) => Container(
    color: Colors.white,
    child: Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(23),
        decoration: const BoxDecoration(gradient: LinearGradient(
          colors: [Color(0xFF0A2858), Color(0xFF144892)],
        )),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('NineSoft', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          Text('Local UI Fast Preview', style: TextStyle(color: Color(0xFFD7E4FA))),
          SizedBox(height: 9),
          Text('20 شاشة - عرض محلي فقط', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: fastPreviewScreens.length,
        itemBuilder: (context, i) {
          final spec = fastPreviewScreens[i];
          return ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
            selected: selected == i,
            selectedTileColor: const Color(0xFFE5EEFF),
            leading: Icon(spec.icon, size: 21, color: selected == i ? const Color(0xFF0860D2) : const Color(0xFF65738A)),
            title: Text(spec.title, style: TextStyle(fontSize: 13, fontWeight: selected == i ? FontWeight.bold : FontWeight.normal)),
            trailing: Text((i + 1).toString(), style: const TextStyle(color: Color(0xFF8390A7))),
            onTap: () {
              open(i);
              if (closeOnSelect) Navigator.of(context).pop();
            },
          );
        },
      )),
    ]),
  );

  Widget _header(BuildContext context, {required bool desktop}) => Container(
    height: desktop ? 78 : 104,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(gradient: LinearGradient(
      colors: [Color(0xFF071F4B), Color(0xFF104080)],
    )),
    child: Row(children: [
      if (!desktop)
        Builder(builder: (inner) => IconButton(
          tooltip: 'الأقسام',
          onPressed: () => Scaffold.of(inner).openDrawer(),
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
        ))
      else const Icon(Icons.apps_rounded, color: Colors.white),
      const Spacer(),
      const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('NineSoft', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold)),
        Text('نظام محاسبي متكامل', style: TextStyle(color: Color(0xFFD7E5FF), fontSize: 12)),
      ]),
      const Spacer(),
      IconButton(
        tooltip: 'عرض تجريبي',
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('معاينة محلية: البيانات والأزرار ليست متصلة بالإنتاج'))),
        icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
      ),
    ]),
  );

  Widget _bottomBar() => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 5, 8),
      decoration: const BoxDecoration(color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE1E8F3)))),
      child: Row(children: [
        _tab(Icons.home_rounded, 'الرئيسية', 0),
        _tab(Icons.layers_rounded, 'العمليات', 3),
        Expanded(child: Center(child: InkWell(
          onTap: () => open(0),
          child: const CircleAvatar(
            radius: 25,
            backgroundColor: Color(0xFF092C65),
            child: Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ))),
        _tab(Icons.bar_chart_rounded, 'التقارير', 10),
        _tab(Icons.settings_rounded, 'الإعدادات', 18),
      ]),
    ),
  );

  Widget _tab(IconData icon, String text, int index) => Expanded(
    child: InkWell(
      onTap: () => open(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected == index ? const Color(0xFFE5EEFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: const Color(0xFF17477E), size: 23),
          Text(text, style: const TextStyle(fontSize: 10)),
        ]),
      ),
    ),
  );
}
