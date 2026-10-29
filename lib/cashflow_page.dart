import 'package:flutter/material.dart';
import 'dapoer_header.dart';
import 'backend_api.dart';

import 'catatan_page.dart';
import 'grafik_page.dart';
import 'kalender_page.dart';
import 'setting_page.dart';

const _gold = Color(0xffcda64d);
const _ink = Color(0xff202124);

/// Shared in-memory transactions used by the cashflow and chart screens.
final List<CashflowTransaction> sharedCashflowTransactions = [];
final List<String> sharedActivityLog = [];

Future<void> loadSharedCashflowTransactions() async {
  final rows = await BackendApi.instance.transactions();
  sharedCashflowTransactions
    ..clear()
    ..addAll(rows.map(CashflowTransaction.fromJson));
}

class CashflowPage extends StatefulWidget {
  const CashflowPage({super.key});

  @override
  State<CashflowPage> createState() => _CashflowPageState();
}

class _CashflowPageState extends State<CashflowPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final List<CashflowTransaction> _transactions = sharedCashflowTransactions;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);
    try {
      await loadSharedCashflowTransactions();
      if (!mounted) return;
    } catch (error) {
      if (mounted) _toast('Gagal memuat cashflow: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

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

  List<CashflowTransaction> get _visibleTransactions =>
      _transactions
          .where(
            (transaction) =>
                transaction.date.year == _month.year &&
                transaction.date.month == _month.month,
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  int get _income => _visibleTransactions
      .where((item) => item.type == 'Pemasukan' && item.verified)
      .fold(0, (total, item) => total + item.amount);
  int get _expense => _visibleTransactions
      .where((item) => item.type == 'Pengeluaran' && item.verified)
      .fold(0, (total, item) => total + item.amount);

  Future<void> _edit([CashflowTransaction? transaction]) async {
    final description = TextEditingController(
      text: transaction?.description ?? '',
    );
    final amount = TextEditingController(
      text: transaction == null ? '' : '${transaction.amount}',
    );
    final category = TextEditingController(text: transaction?.category ?? '');
    var type = transaction?.type ?? 'Pemasukan';
    var date = transaction?.date ?? DateTime.now();
    final result = await showDialog<CashflowTransaction>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            transaction == null ? 'Catat transaksi' : 'Edit transaksi',
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Jenis transaksi',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Pemasukan',
                        child: Text('Pemasukan'),
                      ),
                      DropdownMenuItem(
                        value: 'Pengeluaran',
                        child: Text('Pengeluaran'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: category,
                    decoration: const InputDecoration(
                      labelText: 'Kategori',
                      hintText: 'Contoh: bahan baku, penjualan, gaji',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nominal (Rp) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final chosen = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (chosen != null) setDialogState(() => date = chosen);
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        '${date.day} ${_months[date.month - 1]} ${date.year}',
                      ),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Transaksi baru akan berstatus Perlu dicek.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(
                  amount.text.replaceAll('.', '').replaceAll(',', ''),
                );
                if (description.text.trim().isEmpty ||
                    parsed == null ||
                    parsed <= 0)
                  return;
                Navigator.pop(
                  context,
                  CashflowTransaction(
                    id:
                        transaction?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    description: description.text.trim(),
                    category: category.text.trim().isEmpty
                        ? type
                        : category.text.trim(),
                    amount: parsed,
                    type: type,
                    date: date,
                    verified: transaction?.verified ?? false,
                    source: transaction?.source ?? 'Input aplikasi',
                  ),
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      try {
        final payload = result.toJson();
        if (transaction == null) {
          result.id = await BackendApi.instance.createTransaction(payload);
        } else {
          await BackendApi.instance.updateTransaction(transaction.id, payload);
        }
      } catch (error) {
        _toast('Transaksi gagal disimpan: $error');
        return;
      }
      sharedActivityLog.insert(
        0,
        '${DateTime.now()} · ${transaction == null ? 'Transaksi ditambahkan' : 'Transaksi diperbarui'}: ${result.description} (${_rupiah(result.amount)})',
      );
      setState(() {
        if (transaction != null)
          _transactions.removeWhere((item) => item.id == transaction.id);
        _transactions.add(result);
        _month = DateTime(result.date.year, result.date.month);
      });
    }
  }

  String _rupiah(int amount) =>
      'Rp ${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';

  Future<void> _verify(CashflowTransaction transaction) async {
    try {
      await BackendApi.instance.verifyTransaction(transaction.id);
    } catch (error) {
      _toast('Verifikasi gagal: $error');
      return;
    }
    setState(() {
      transaction.verified = true;
      sharedActivityLog.insert(
        0,
        '${DateTime.now()} · Transaksi diverifikasi: ${transaction.description}',
      );
    });
  }

  Future<void> _delete(CashflowTransaction transaction) async {
    try {
      await BackendApi.instance.deleteTransaction(transaction.id);
      setState(
        () => _transactions.removeWhere((item) => item.id == transaction.id),
      );
    } catch (error) {
      _toast('Transaksi gagal dihapus: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleTransactions;
    final pendingCount = entries.where((item) => !item.verified).length;
    return Scaffold(
      backgroundColor: const Color(0xfffaf9f6),
      body: SafeArea(
        child: Row(
          children: [
            _CashflowNavigation(),
            Expanded(
              child: Column(
                children: [
                  const DapoerHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1120),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'CASHFLOW DAPOER PMCSU',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 360,
                                  ),
                                  child: _SummaryCard(
                                    title: 'TOTAL MASUK',
                                    amount: _rupiah(_income),
                                    icon: Icons.south_west,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              LayoutBuilder(
                                builder: (context, box) => box.maxWidth < 600
                                    ? Column(
                                        children: [
                                          _SummaryCard(
                                            title: 'TOTAL KELUAR',
                                            amount: _rupiah(_expense),
                                            icon: Icons.north_east,
                                            color: Colors.red.shade700,
                                          ),
                                          const SizedBox(height: 12),
                                          _SummaryCard(
                                            title: 'SALDO',
                                            amount: _rupiah(_income - _expense),
                                            icon: Icons
                                                .account_balance_wallet_outlined,
                                            color: _ink,
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          Expanded(
                                            child: _SummaryCard(
                                              title: 'TOTAL KELUAR',
                                              amount: _rupiah(_expense),
                                              icon: Icons.north_east,
                                              color: Colors.red.shade700,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: _SummaryCard(
                                              title: 'SALDO',
                                              amount: _rupiah(
                                                _income - _expense,
                                              ),
                                              icon: Icons
                                                  .account_balance_wallet_outlined,
                                              color: _ink,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Text(
                                    '${_months[_month.month - 1]} ${_month.year}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(
                                      () => _month = DateTime(
                                        _month.year,
                                        _month.month - 1,
                                      ),
                                    ),
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(
                                      () => _month = DateTime(
                                        _month.year,
                                        _month.month + 1,
                                      ),
                                    ),
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                  const Spacer(),
                                  FilledButton.icon(
                                    onPressed: () => _edit(),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Catat transaksi'),
                                  ),
                                ],
                              ),
                              if (_loading) const LinearProgressIndicator(),
                              if (pendingCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xfffff3d7),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.pending_actions,
                                        color: _gold,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '$pendingCount transaksi perlu dicek. Verifikasi transaksi untuk memasukkannya ke total cashflow.',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              CashflowTransactionTable(
                                entries: entries,
                                rupiah: _rupiah,
                                onEdit: _edit,
                                onVerify: _verify,
                                onDelete: _delete,
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

class CashflowTransaction {
  CashflowTransaction({
    required this.id,
    required this.description,
    required this.category,
    required this.amount,
    required this.type,
    required this.date,
    required this.verified,
    required this.source,
  });
  String id;
  final String description, category, type, source;
  final int amount;
  final DateTime date;
  bool verified;

  factory CashflowTransaction.fromJson(Map<String, dynamic> json) =>
      CashflowTransaction(
        id: json['id'].toString(),
        description: json['description']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        amount: json['amount'] as int,
        type: json['type']?.toString() ?? 'Pemasukan',
        date: DateTime.parse(json['date'].toString()),
        verified: json['verified'] == true,
        source: json['source']?.toString() ?? 'Input aplikasi',
      );

  Map<String, dynamic> toJson() => {
    'type': type,
    'description': description,
    'category': category,
    'amount': amount,
    'date':
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
  };
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });
  final String title, amount;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xffdedbd4)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  amount,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class CashflowTransactionTable extends StatelessWidget {
  const CashflowTransactionTable({
    required this.entries,
    required this.rupiah,
    required this.onEdit,
    required this.onVerify,
    required this.onDelete,
  });
  final List<CashflowTransaction> entries;
  final String Function(int) rupiah;
  final void Function(CashflowTransaction) onEdit, onVerify, onDelete;
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty)
      return Container(
        padding: const EdgeInsets.all(34),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffdedbd4)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          children: [
            Icon(Icons.receipt_long_outlined, size: 34, color: Colors.black38),
            SizedBox(height: 8),
            Text(
              'Belum ada transaksi pada bulan ini.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xffdedbd4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          if (MediaQuery.sizeOf(context).width >= 720)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text('TANGGAL', style: _head)),
                  Expanded(flex: 4, child: Text('KETERANGAN', style: _head)),
                  Expanded(flex: 3, child: Text('KATEGORI', style: _head)),
                  Expanded(flex: 3, child: Text('NOMINAL', style: _head)),
                  Expanded(flex: 3, child: Text('STATUS', style: _head)),
                  Text('AKSI', style: _head),
                ],
              ),
            ),
          const Divider(height: 1),
          for (final item in entries)
            CashflowTransactionRow(
              item: item,
              rupiah: rupiah(item.amount),
              onEdit: () => onEdit(item),
              onVerify: () => onVerify(item),
              onDelete: () => onDelete(item),
            ),
        ],
      ),
    );
  }
}

const _head = TextStyle(fontWeight: FontWeight.w800, fontSize: 10, color: _ink);

class CashflowTransactionRow extends StatelessWidget {
  const CashflowTransactionRow({
    required this.item,
    required this.rupiah,
    required this.onEdit,
    required this.onVerify,
    required this.onDelete,
  });
  final CashflowTransaction item;
  final String rupiah;
  final VoidCallback onEdit, onVerify, onDelete;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0xffece9e2))),
    ),
    child: LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 720)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.date.day} ${_monthsShort[item.date.month - 1]} · ${item.type}',
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 5),
              Text(
                item.description,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('${item.category} · $rupiah'),
              _status(context),
              Align(alignment: Alignment.centerRight, child: _actions()),
            ],
          );
        return Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                '${item.date.day} ${_monthsShort[item.date.month - 1]}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.description,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    item.source,
                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(item.category, style: const TextStyle(fontSize: 11)),
            ),
            Expanded(
              flex: 3,
              child: Text(
                rupiah,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(flex: 3, child: _status(context)),
            _actions(),
          ],
        );
      },
    ),
  );
  Widget _status(BuildContext context) => item.verified
      ? const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 16, color: Colors.green),
            SizedBox(width: 4),
            Text(
              'Terverifikasi',
              style: TextStyle(
                fontSize: 11,
                color: Colors.green,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        )
      : TextButton.icon(
          onPressed: onVerify,
          icon: const Icon(Icons.fact_check_outlined, size: 16),
          label: const Text('Perlu dicek', style: TextStyle(fontSize: 11)),
        );
  Widget _actions() => PopupMenuButton<String>(
    tooltip: 'Aksi',
    onSelected: (action) {
      if (action == 'edit') onEdit();
      if (action == 'delete') onDelete();
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'edit', child: Text('Edit')),
      PopupMenuItem(value: 'delete', child: Text('Hapus')),
    ],
    child: const Padding(
      padding: EdgeInsets.all(8),
      child: Icon(Icons.edit_outlined, size: 19),
    ),
  );
}

const _monthsShort = [
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
];

class _CashflowNavigation extends StatelessWidget {
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
          () {},
          selected: true,
        ),
        _nav(
          context,
          'assets/icons/chart-icon.jpg',
          Icons.pie_chart_outline,
          () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CatatanPage()),
          ),
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
  }) => IconButton(
    tooltip: selected ? 'Cashflow' : null,
    onPressed: action,
    icon: Image.asset(
      asset,
      width: 28,
      height: 28,
      errorBuilder: (_, __, ___) => Icon(fallback, color: _ink, size: 27),
    ),
    style: IconButton.styleFrom(
      backgroundColor: selected ? const Color(0xffeeeeee) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    padding: const EdgeInsets.all(13),
  );
}
