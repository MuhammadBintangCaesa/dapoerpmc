import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'dapoer_header.dart';

import 'cashflow_page.dart';
import 'grafik_page.dart';
import 'kalender_page.dart';
import 'setting_page.dart';

const _catColors = [
  Color(0xff3155e7),
  Color(0xffff9862),
  Color(0xffffd09f),
  Color(0xff209e77),
  Color(0xff9b79d0),
  Color(0xffe56b75),
  Color(0xff53a9c7),
];

class CatatanPage extends StatefulWidget {
  const CatatanPage({super.key});
  @override
  State<CatatanPage> createState() => _CatatanPageState();
}

class _CatatanPageState extends State<CatatanPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _type = 'Pengeluaran';
  String _chart = 'Pie chart';

  @override
  void initState() {
    super.initState();
    loadSharedCashflowTransactions()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((_) {});
  }

  static const _months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  List<_Category> get _categories {
    final totals = <String, int>{};
    for (final item in sharedCashflowTransactions) {
      if (!item.verified ||
          item.type != _type ||
          item.date.year != _month.year ||
          item.date.month != _month.month)
        continue;
      final category = item.category.trim().isEmpty
          ? 'Tanpa kategori'
          : item.category.trim();
      totals.update(
        category,
        (value) => value + item.amount,
        ifAbsent: () => item.amount,
      );
    }
    return totals.entries
        .map((entry) => _Category(entry.key, entry.value))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
  }

  String _money(int value) =>
      'Rp${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final total = categories.fold(0, (sum, item) => sum + item.amount);
    return Scaffold(
      backgroundColor: const Color(0xfffaf9f6),
      body: SafeArea(
        child: Row(
          children: [
            _CatatanNavigation(),
            Expanded(
              child: Column(
                children: [
                  const DapoerHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1080),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'CATATAN DAPOER PMCSU',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 34),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 14,
                                runSpacing: 12,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Bulan:  ${_months[_month.month - 1]}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Bulan sebelumnya',
                                        onPressed: () => setState(
                                          () => _month = DateTime(
                                            _month.year,
                                            _month.month - 1,
                                          ),
                                        ),
                                        icon: const Icon(Icons.chevron_left),
                                      ),
                                      IconButton(
                                        tooltip: 'Bulan berikutnya',
                                        onPressed: () => setState(
                                          () => _month = DateTime(
                                            _month.year,
                                            _month.month + 1,
                                          ),
                                        ),
                                        icon: const Icon(Icons.chevron_right),
                                      ),
                                    ],
                                  ),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 'Pemasukan',
                                        label: Text('Pemasukan'),
                                      ),
                                      ButtonSegment(
                                        value: 'Pengeluaran',
                                        label: Text('Pengeluaran'),
                                      ),
                                    ],
                                    selected: {_type},
                                    onSelectionChanged: (value) =>
                                        setState(() => _type = value.first),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              if (categories.isEmpty)
                                _EmptyCategory(
                                  type: _type,
                                  month: _months[_month.month - 1],
                                )
                              else
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final legend = _CategoryLegend(
                                      categories: categories,
                                      total: total,
                                      money: _money,
                                    );
                                    if (constraints.maxWidth < 660)
                                      return Column(
                                        children: [
                                          _CategoryChart(
                                            categories: categories,
                                            total: total,
                                            type: _chart,
                                          ),
                                          const SizedBox(height: 20),
                                          legend,
                                        ],
                                      );
                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: _CategoryChart(
                                            categories: categories,
                                            total: total,
                                            type: _chart,
                                          ),
                                        ),
                                        const SizedBox(width: 26),
                                        Expanded(flex: 6, child: legend),
                                      ],
                                    );
                                  },
                                ),
                              const SizedBox(height: 22),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  _ToggleButton(
                                    label: 'PIE CHART',
                                    selected: _chart == 'Pie chart',
                                    onPressed: () =>
                                        setState(() => _chart = 'Pie chart'),
                                  ),
                                  _ToggleButton(
                                    label: 'BAR CHART',
                                    selected: _chart == 'Bar chart',
                                    onPressed: () =>
                                        setState(() => _chart = 'Bar chart'),
                                  ),
                                ],
                              ),
                              if (categories.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Text(
                                    'Total $_type: ${_money(0)}',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                              if (categories.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 20),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Total $_type',
                                          style: TextStyle(
                                            color: Colors.black54,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _money(total),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Category {
  const _Category(this.name, this.amount);
  final String name;
  final int amount;
}

class _CategoryChart extends StatelessWidget {
  const _CategoryChart({
    required this.categories,
    required this.total,
    required this.type,
  });
  final List<_Category> categories;
  final int total;
  final String type;
  @override
  Widget build(BuildContext context) {
    if (type == 'Bar chart') {
      final maximum = categories
          .map((item) => item.amount)
          .reduce((a, b) => a > b ? a : b);
      return Column(
        children: [
          for (var i = 0; i < categories.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(categories[i].name)),
                      Text('${(categories[i].amount * 100 / total).round()}%'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: categories[i].amount / maximum,
                      minHeight: 20,
                      backgroundColor: const Color(0xfff1f1f1),
                      valueColor: AlwaysStoppedAnimation(
                        _catColors[i % _catColors.length],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return SizedBox(
      width: 300,
      height: 300,
      child: CustomPaint(
        painter: _DonutPainter(categories, total),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'TOTAL',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Text(
                '${categories.length} kategori',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.categories, this.total);
  final List<_Category> categories;
  final int total;
  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: math.min(size.width, size.height) - 42,
      height: math.min(size.width, size.height) - 42,
    );
    var start = -math.pi / 2;
    for (var index = 0; index < categories.length; index++) {
      final sweep = math.pi * 2 * categories[index].amount / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = _catColors[index % _catColors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 38,
      );
      final middle = start + sweep / 2;
      final radius = rect.width / 2 + 23;
      final center = Offset(
        rect.center.dx + math.cos(middle) * radius,
        rect.center.dy + math.sin(middle) * radius,
      );
      final percent = '${(categories[index].amount * 100 / total).round()}%';
      final painter = TextPainter(
        text: TextSpan(
          text: percent,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: Colors.black,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final badge = Rect.fromCenter(
        center: center,
        width: painter.width + 16,
        height: painter.height + 14,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badge, const Radius.circular(24)),
        Paint()..color = Colors.white,
      );
      painter.paint(
        canvas,
        Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.categories != categories || oldDelegate.total != total;
}

class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend({
    required this.categories,
    required this.total,
    required this.money,
  });
  final List<_Category> categories;
  final int total;
  final String Function(int) money;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < categories.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color: _catColors[i % _catColors.length],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  categories[i].name,
                  style: const TextStyle(color: Colors.black54, fontSize: 16),
                ),
              ),
              Text(
                money(categories[i].amount),
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
    ],
  );
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.black,
      backgroundColor: selected ? const Color(0xfff3f3f3) : Colors.white,
      side: BorderSide(color: selected ? Colors.black : Colors.black45),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      overlayColor: const Color(0xffcda64d).withAlpha(30),
    ),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({required this.type, required this.month});
  final String type, month;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
    decoration: BoxDecoration(
      color: const Color(0xfffaf9f6),
      border: Border.all(color: const Color(0xffece9e2)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      children: [
        const Icon(Icons.pie_chart_outline, size: 42, color: Colors.black38),
        const SizedBox(height: 10),
        Text(
          'Belum ada data $type pada $month',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        const Text(
          'Transaksi yang belum diverifikasi tidak ditampilkan.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    ),
  );
}

class _CatatanNavigation extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 82,
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: Color(0xffe8e5df))),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _nav(
          context,
          'assets/icons/kalender-icon.jpg',
          Icons.calendar_month,
          () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const KalenderPage()),
          ),
        ),
        _nav(
          context,
          'assets/icons/cashflow-icon.jpg',
          Icons.payments_outlined,
          () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CashflowPage()),
          ),
        ),
        _nav(
          context,
          'assets/icons/chart-icon.jpg',
          Icons.pie_chart_outline,
          () {},
          selected: true,
        ),
        _nav(
          context,
          'assets/icons/track-icon.png',
          Icons.query_stats,
          () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GrafikPage()),
          ),
        ),
        _nav(
          context,
          'assets/icons/settings-icon.png',
          Icons.settings_outlined,
          () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SettingPage()),
          ),
        ),
      ],
    ),
  );

  Widget _nav(
    BuildContext context,
    String asset,
    IconData fallback,
    VoidCallback action, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: IconButton(
      tooltip: selected ? 'Catatan' : null,
      onPressed: action,
      style: IconButton.styleFrom(
        backgroundColor: selected ? const Color(0xffeeeeee) : null,
        overlayColor: const Color(0xffcda64d).withAlpha(30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Image.asset(
        asset,
        width: 28,
        height: 28,
        errorBuilder: (_, __, ___) => Icon(fallback, size: 27),
      ),
    ),
  );
}
