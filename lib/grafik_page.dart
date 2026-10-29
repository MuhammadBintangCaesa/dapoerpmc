import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dapoer_header.dart';
import 'catatan_page.dart';
import 'cashflow_page.dart';
import 'kalender_page.dart';
import 'setting_page.dart';

const _ink = Color(0xff202124);
const _green = Color(0xff209e77);
const _orange = Color(0xffde5b32);
const _gold = Color(0xffcda64d);

class GrafikPage extends StatefulWidget {
  const GrafikPage({super.key});

  @override
  State<GrafikPage> createState() => _GrafikPageState();
}

class _GrafikPageState extends State<GrafikPage> {
  int _range = 6;
  String _chartType = 'Batang';
  final DateTime _endMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  @override
  void initState() {
    super.initState();
    loadSharedCashflowTransactions()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((_) {});
  }

  List<_MonthPoint> get _points => List.generate(_range, (index) {
    final month = DateTime(
      _endMonth.year,
      _endMonth.month - _range + index + 1,
    );
    var income = 0;
    var expense = 0;
    for (final item in sharedCashflowTransactions) {
      if (!item.verified ||
          item.date.year != month.year ||
          item.date.month != month.month)
        continue;
      if (item.type == 'Pemasukan') income += item.amount;
      if (item.type == 'Pengeluaran') expense += item.amount;
    }
    return _MonthPoint(month, income, expense);
  });

  int get _income => _points.fold(0, (sum, point) => sum + point.income);
  int get _expense => _points.fold(0, (sum, point) => sum + point.expense);
  int get _monthIncome => _points.last.income;
  int get _monthExpense => _points.last.expense;

  List<_MenuTotal> get _topMenus {
    final totals = <String, int>{};
    final visibleMonths = _points
        .map((point) => '${point.date.year}-${point.date.month}')
        .toSet();
    for (final item in sharedCashflowTransactions) {
      if (!item.verified ||
          item.type != 'Pemasukan' ||
          !visibleMonths.contains('${item.date.year}-${item.date.month}'))
        continue;
      final name = item.description.trim().isEmpty
          ? 'Tanpa keterangan'
          : item.description.trim();
      totals.update(
        name,
        (value) => value + item.amount,
        ifAbsent: () => item.amount,
      );
    }
    final result =
        totals.entries
            .map((entry) => _MenuTotal(entry.key, entry.value))
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));
    return result.take(3).toList();
  }

  String _rupiah(int amount) =>
      'Rp${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';
  Future<void> _exportExcel() async {
    final rows = <String>['Bulan,Pemasukan,Pengeluaran,Laba bersih'];
    for (final point in _points) {
      rows.add(
        '${_monthName(point.date.month)},${point.income},${point.expense},${point.income - point.expense}',
      );
    }
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Data CSV disalin. Tempelkan ke Excel atau simpan sebagai .csv.',
        ),
      ),
    );
  }

  void _showPdfPreview() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ringkasan laporan'),
        content: Text(
          'Periode: ${_periodLabel()}\nPemasukan: ${_rupiah(_income)}\nPengeluaran: ${_rupiah(_expense)}\nLaba bersih: ${_rupiah(_income - _expense)}\n\nUntuk membuat file PDF yang dapat diunduh, aplikasi perlu modul ekspor PDF.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  String _periodLabel() =>
      '${_monthName(_points.first.date.month)} – ${_monthName(_points.last.date.month)} ${_points.last.date.year}';
  String _monthName(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ][month - 1];

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final maxValue = points.fold<int>(
      0,
      (max, point) => math.max(max, math.max(point.income, point.expense)),
    );
    final hasData = maxValue > 0;
    final menus = _topMenus;
    return Scaffold(
      backgroundColor: const Color(0xfffaf9f6),
      body: SafeArea(
        child: Row(
          children: [
            _GraphNavigation(),
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
                                'GRAFIK DAPOER PMCSU',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 28),
                              LayoutBuilder(
                                builder: (context, box) {
                                  final cards = [
                                    _Summary(
                                      title:
                                          'Pemasukan (${_monthName(_endMonth.month)})',
                                      value: _rupiah(_monthIncome),
                                      color: _ink,
                                    ),
                                    _Summary(
                                      title:
                                          'Pengeluaran (${_monthName(_endMonth.month)})',
                                      value: _rupiah(_monthExpense),
                                      color: _ink,
                                    ),
                                    _Summary(
                                      title:
                                          'Laba bersih (${_monthName(_endMonth.month)})',
                                      value:
                                          '${_monthIncome - _monthExpense >= 0 ? '+' : '−'}${_rupiah((_monthIncome - _monthExpense).abs())}',
                                      color: _monthIncome >= _monthExpense
                                          ? _green
                                          : _orange,
                                    ),
                                  ];
                                  if (box.maxWidth < 680)
                                    return Column(
                                      children: [
                                        for (var i = 0; i < cards.length; i++)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              bottom: i == cards.length - 1
                                                  ? 0
                                                  : 10,
                                            ),
                                            child: cards[i],
                                          ),
                                      ],
                                    );
                                  return Row(
                                    children: [
                                      for (var i = 0; i < cards.length; i++)
                                        Expanded(
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              right: i == cards.length - 1
                                                  ? 0
                                                  : 12,
                                            ),
                                            child: cards[i],
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 20),
                              LayoutBuilder(
                                builder: (context, box) => Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 10,
                                  children: [
                                    SegmentedButton<int>(
                                      segments: const [
                                        ButtonSegment(
                                          value: 3,
                                          label: Text('3 bulan'),
                                        ),
                                        ButtonSegment(
                                          value: 6,
                                          label: Text('6 bulan'),
                                        ),
                                      ],
                                      selected: {_range},
                                      onSelectionChanged: (value) =>
                                          setState(() => _range = value.first),
                                    ),
                                    SegmentedButton<String>(
                                      segments: const [
                                        ButtonSegment(
                                          value: 'Batang',
                                          label: Text('Batang'),
                                        ),
                                        ButtonSegment(
                                          value: 'Garis',
                                          label: Text('Garis'),
                                        ),
                                        ButtonSegment(
                                          value: 'Pie',
                                          label: Text('Pie'),
                                        ),
                                      ],
                                      selected: {_chartType},
                                      onSelectionChanged: (value) => setState(
                                        () => _chartType = value.first,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: const Color(0xffe5e5e5),
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: _green,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text('Pemasukan'),
                                            const SizedBox(width: 20),
                                            Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: _orange,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text('Pengeluaran'),
                                          ],
                                        ),
                                        Text(
                                          _periodLabel(),
                                          style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    if (!hasData)
                                      _GraphEmpty(range: _range)
                                    else
                                      SizedBox(
                                        height: 270,
                                        child: CustomPaint(
                                          size: const Size(
                                            double.infinity,
                                            270,
                                          ),
                                          painter: _FinanceChartPainter(
                                            points: points,
                                            type: _chartType,
                                            maxValue: maxValue,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              LayoutBuilder(
                                builder: (context, box) => box.maxWidth < 650
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _TopMenus(
                                            menus: menus,
                                            money: _rupiah,
                                          ),
                                          const SizedBox(height: 12),
                                          _ExportButtons(
                                            onPdf: _showPdfPreview,
                                            onExcel: _exportExcel,
                                          ),
                                        ],
                                      )
                                    : Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Expanded(
                                            child: _TopMenus(
                                              menus: menus,
                                              money: _rupiah,
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          _ExportButtons(
                                            onPdf: _showPdfPreview,
                                            onExcel: _exportExcel,
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

class _MonthPoint {
  const _MonthPoint(this.date, this.income, this.expense);
  final DateTime date;
  final int income;
  final int expense;
}

class _MenuTotal {
  const _MenuTotal(this.name, this.amount);
  final String name;
  final int amount;
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.title,
    required this.value,
    required this.color,
  });
  final String title, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
    decoration: BoxDecoration(
      color: const Color(0xfff3f3f3),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class _FinanceChartPainter extends CustomPainter {
  const _FinanceChartPainter({
    required this.points,
    required this.type,
    required this.maxValue,
  });
  final List<_MonthPoint> points;
  final String type;
  final int maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (type == 'Pie') {
      _drawPie(canvas, size);
      return;
    }
    const left = 48.0, right = 8.0, top = 10.0, bottom = 28.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final grid = Paint()
      ..color = const Color(0xffe8e8e8)
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(color: Colors.black45, fontSize: 10);
    final double step = maxValue == 0 ? 1 : (maxValue / 3).ceilToDouble();
    final upper = step * 3;
    for (var i = 0; i <= 3; i++) {
      final y = chart.bottom - chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      _text(
        canvas,
        i == 0 ? '0' : _axisLabel((step * i).toInt()),
        Offset(0, y - 7),
        labelStyle,
      );
    }
    if (type == 'Batang') {
      final groupWidth = chart.width / points.length;
      final barWidth = math.min(27.0, groupWidth * .34);
      for (var i = 0; i < points.length; i++) {
        final center = chart.left + groupWidth * (i + .5);
        final incomeHeight = chart.height * points[i].income / upper;
        final expenseHeight = chart.height * points[i].expense / upper;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              center - barWidth - 1,
              chart.bottom - incomeHeight,
              barWidth,
              incomeHeight,
            ),
            const Radius.circular(4),
          ),
          Paint()..color = _green,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              center + 1,
              chart.bottom - expenseHeight,
              barWidth,
              expenseHeight,
            ),
            const Radius.circular(4),
          ),
          Paint()..color = _orange,
        );
        _text(
          canvas,
          _monthShort(points[i].date.month),
          Offset(center - 13, chart.bottom + 8),
          labelStyle,
        );
      }
    } else {
      _drawLine(
        canvas,
        chart,
        points.map((point) => point.income).toList(),
        upper,
        _green,
      );
      _drawLine(
        canvas,
        chart,
        points.map((point) => point.expense).toList(),
        upper,
        _orange,
      );
      for (var i = 0; i < points.length; i++) {
        final x = chart.left + chart.width * (i + .5) / points.length;
        _text(
          canvas,
          _monthShort(points[i].date.month),
          Offset(x - 13, chart.bottom + 8),
          labelStyle,
        );
      }
    }
  }

  void _drawLine(
    Canvas canvas,
    Rect chart,
    List<int> values,
    double upper,
    Color color,
  ) {
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = chart.left + chart.width * (i + .5) / values.length;
      final y = chart.bottom - chart.height * values[i] / upper;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = color);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawPie(Canvas canvas, Size size) {
    final income = points.fold<int>(0, (sum, point) => sum + point.income);
    final expense = points.fold<int>(0, (sum, point) => sum + point.expense);
    final total = income + expense;
    if (total <= 0) return;
    final diameter = math.min(size.height - 54, size.width - 30);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: diameter,
      height: diameter,
    );
    var start = -math.pi / 2;
    for (final segment in [(income, _green), (expense, _orange)]) {
      final sweep = math.pi * 2 * segment.$1 / total;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = segment.$2);
      start += sweep;
    }
    final hole = Rect.fromCenter(
      center: rect.center,
      width: diameter * .52,
      height: diameter * .52,
    );
    canvas.drawOval(hole, Paint()..color = Colors.white);
    _text(
      canvas,
      'Masuk ${_compact(income)}',
      Offset(rect.left, rect.bottom + 4),
      const TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w700),
    );
    _text(
      canvas,
      'Keluar ${_compact(expense)}',
      Offset(rect.right - 105, rect.bottom + 4),
      const TextStyle(
        color: _orange,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  String _axisLabel(int value) => value >= 1000000
      ? '${(value / 1000000).round()} jt'
      : '${(value / 1000).round()} rb';
  String _compact(int value) => value >= 1000000
      ? '${(value / 1000000).toStringAsFixed(1)}jt'
      : '${(value / 1000).round()}rb';
  String _monthShort(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ][month - 1];

  void _text(Canvas canvas, String value, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _FinanceChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.type != type ||
      oldDelegate.maxValue != maxValue;
}

class _GraphEmpty extends StatelessWidget {
  const _GraphEmpty({required this.range});
  final int range;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 270,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.insert_chart_outlined,
            size: 40,
            color: Colors.black38,
          ),
          const SizedBox(height: 8),
          Text(
            'Belum ada transaksi terverifikasi untuk periode $range bulan.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ringkasan dan grafik akan terisi setelah transaksi diverifikasi.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    ),
  );
}

class _TopMenus extends StatelessWidget {
  const _TopMenus({required this.menus, required this.money});
  final List<_MenuTotal> menus;
  final String Function(int) money;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Menu terlaris pada periode ini',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      const SizedBox(height: 6),
      if (menus.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            'Belum ada data menu terlaris.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        )
      else
        for (var i = 0; i < menus.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Text(
                  '${i + 1}. ',
                  style: const TextStyle(color: Colors.black54),
                ),
                Expanded(
                  child: Text(
                    menus[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  money(menus[i].amount),
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
    ],
  );
}

class _ExportButtons extends StatelessWidget {
  const _ExportButtons({required this.onPdf, required this.onExcel});
  final VoidCallback onPdf, onExcel;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      OutlinedButton(onPressed: onPdf, child: const Text('Export PDF')),
      OutlinedButton(onPressed: onExcel, child: const Text('Export Excel')),
    ],
  );
}

class _GraphNavigation extends StatelessWidget {
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
          Icons.insert_chart_outlined,
          () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CatatanPage()),
          ),
        ),
        _nav(
          context,
          'assets/icons/track-icon.png',
          Icons.query_stats,
          () => _notReady(context, 'Tracking'),
          selected: true,
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

  void _notReady(BuildContext context, String name) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Halaman $name belum tersedia.')));

  Widget _nav(
    BuildContext context,
    String asset,
    IconData fallback,
    VoidCallback action, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: IconButton(
      tooltip: selected ? 'Grafik' : null,
      onPressed: action,
      style: IconButton.styleFrom(
        backgroundColor: selected ? const Color(0xffeeeeee) : null,
        foregroundColor: _ink,
        overlayColor: _gold.withAlpha(30),
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
