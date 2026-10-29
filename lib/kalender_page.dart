import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dapoer_header.dart';
import 'backend_api.dart';
import 'calendar_notifications.dart';

import 'catatan_page.dart';
import 'cashflow_page.dart';
import 'grafik_page.dart';
import 'setting_page.dart';

const _gold = Color(0xffcda64d);
const _ink = Color(0xff202124);

class KalenderPage extends StatefulWidget {
  const KalenderPage({super.key});

  @override
  State<KalenderPage> createState() => _KalenderPageState();
}

class _KalenderPageState extends State<KalenderPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateTime.now();
  final Map<DateTime, List<_Event>> _events = {};
  bool _notifications = false;
  bool _loadingEvents = false;

  @override
  void initState() {
    super.initState();
    _loadMonthEvents();
    _loadNotificationSetting();
  }

  Future<void> _loadNotificationSetting() async {
    try {
      var enabled = await CalendarNotifications.enabled();
      if (enabled && !await CalendarNotifications.requestPermission()) {
        enabled = false;
        await CalendarNotifications.setEnabled(false);
        await CalendarNotifications.cancelAll();
      }
      if (mounted) setState(() => _notifications = enabled);
      if (enabled) {
        try {
          await _syncNotifications();
        } catch (_) {
          if (mounted) {
            _message(
              'Pengingat tersimpan; kalender akan disinkronkan saat online.',
            );
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _notifications = false);
    }
  }

  int _notificationId(String id) => id.codeUnits.fold<int>(
    17,
    (value, unit) => (value * 31 + unit) & 0x7fffffff,
  );

  Future<void> _syncNotifications() async {
    if (!_notifications) return;
    final now = DateTime.now();
    final rows = await BackendApi.instance.calendarEvents(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year + 1, now.month, now.day),
    );
    await CalendarNotifications.cancelAll();
    for (final row in rows) {
      final event = _Event.fromJson(row);
      final at = DateTime(event.date.year, event.date.month, event.date.day, 9);
      if (at.isBefore(now) ||
          event.status == 'Dibatalkan' ||
          event.status == 'Selesai') {
        continue;
      }
      await CalendarNotifications.schedule(
        id: _notificationId(event.id),
        title: 'Kegiatan hari ini: ${event.name}',
        body: event.customer.isEmpty
            ? 'Buka kalender untuk melihat detail.'
            : 'Pelanggan: ${event.customer}',
        at: at,
      );
    }
  }

  Future<void> _setNotifications(bool enabled) async {
    if (enabled) {
      final allowed = await CalendarNotifications.requestPermission();
      if (!allowed) {
        await CalendarNotifications.setEnabled(false);
        await CalendarNotifications.cancelAll();
        if (mounted) {
          setState(() => _notifications = false);
          _message(
            'Izin notifikasi belum diberikan. Aktifkan dari Pengaturan HP.',
          );
        }
        return;
      }
    }
    try {
      await CalendarNotifications.setEnabled(enabled);
      if (mounted) setState(() => _notifications = enabled);
      await _syncNotifications();
      if (enabled && mounted)
        _message('Pengingat kegiatan dijadwalkan pukul 09.00.');
    } on PlatformException catch (error) {
      if (mounted)
        _message('Notifikasi gagal diperbarui: ${error.message ?? error.code}');
    } catch (error) {
      if (mounted) _message('Jadwal notifikasi gagal dimuat: $error');
    }
  }

  Future<void> _loadMonthEvents() async {
    setState(() => _loadingEvents = true);
    try {
      final rows = await BackendApi.instance.calendarEvents(
        _month,
        DateTime(_month.year, _month.month + 1, 0),
      );
      if (!mounted) return;
      _events.clear();
      for (final row in rows) {
        final item = _Event.fromJson(row);
        _events.putIfAbsent(item.date, () => []).add(item);
      }
    } catch (error) {
      if (mounted) _message('Gagal memuat kegiatan: $error');
    } finally {
      if (mounted) setState(() => _loadingEvents = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
  List<_Event> get _selectedEvents => _events[_day(_selected)] ?? [];

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
  static const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

  void _changeMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      _selected = DateTime(_month.year, _month.month, 1);
    });
    _loadMonthEvents();
  }

  Future<void> _editEvent([_Event? event]) async {
    final name = TextEditingController(text: event?.name ?? '');
    final customer = TextEditingController(text: event?.customer ?? '');
    final amount = TextEditingController(
      text: event?.amount == null ? '' : '${event!.amount}',
    );
    final info = TextEditingController(text: event?.info ?? '');
    var date = event?.date ?? _selected;
    var status = event?.status ?? 'Progress';
    var paid = event?.paid ?? false;
    final result = await showDialog<_Event>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(event == null ? 'Tambah kegiatan' : 'Update kegiatan'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Kegiatan *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Progress',
                        child: Text('Progress'),
                      ),
                      DropdownMenuItem(
                        value: 'Selesai',
                        child: Text('Selesai'),
                      ),
                      DropdownMenuItem(
                        value: 'Dibatalkan',
                        child: Text('Dibatalkan'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => status = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: customer,
                    decoration: const InputDecoration(
                      labelText: 'Nama pelanggan',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Nominal pembayaran (Rp)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pembayaran sudah diterima'),
                    value: paid,
                    onChanged: (v) => setDialogState(() => paid = v),
                  ),
                  TextField(
                    controller: info,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Informasi tambahan',
                      border: OutlineInputBorder(),
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
                if (name.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  _Event(
                    id:
                        event?.id ??
                        DateTime.now().microsecondsSinceEpoch.toString(),
                    name: name.text.trim(),
                    date: _day(date),
                    customer: customer.text.trim(),
                    amount: int.tryParse(
                      amount.text.replaceAll('.', '').replaceAll(',', ''),
                    ),
                    paid: paid,
                    status: status,
                    info: info.text.trim(),
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
        if (event == null) {
          result.id = await BackendApi.instance.createCalendarEvent(payload);
        } else {
          await BackendApi.instance.updateCalendarEvent(event.id, payload);
        }
      } catch (error) {
        _message('Kegiatan gagal disimpan: $error');
        return;
      }
      setState(() {
        if (event != null) {
          for (final list in _events.values) {
            list.removeWhere((item) => item.id == event.id);
          }
        }
        _events.putIfAbsent(result.date, () => []).add(result);
        _selected = result.date;
        _month = DateTime(result.date.year, result.date.month);
      });
      if (_notifications) {
        await CalendarNotifications.cancel(_notificationId(result.id));
        await _syncNotifications();
      }
    }
  }

  Future<void> _deleteEvent(_Event event) async {
    try {
      await BackendApi.instance.deleteCalendarEvent(event.id);
    } catch (error) {
      _message('Kegiatan gagal dihapus: $error');
      return;
    }
    setState(() {
      _events[event.date]?.removeWhere((item) => item.id == event.id);
      if (_events[event.date]?.isEmpty ?? false) _events.remove(event.date);
    });
    await CalendarNotifications.cancel(_notificationId(event.id));
  }

  String _money(int? value) => value == null
      ? 'Nominal belum diisi'
      : 'Rp ${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final count = ((firstWeekday - 1 + days + 6) ~/ 7) * 7;
    return Scaffold(
      backgroundColor: const Color(0xfffaf9f6),
      body: SafeArea(
        child: Row(
          children: [
            _NavigationRail(),
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
                                'KALENDER DAPUR PMCSU',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: .5,
                                ),
                              ),
                              if (_loadingEvents)
                                const LinearProgressIndicator(),
                              const SizedBox(height: 22),
                              LayoutBuilder(
                                builder: (context, box) {
                                  final cellHeight = box.maxWidth < 600
                                      ? 62.0
                                      : 88.0;
                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          for (final day in _weekdays)
                                            Expanded(
                                              child: Center(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                      ),
                                                  child: Text(
                                                    day,
                                                    style: const TextStyle(
                                                      color: Colors.black54,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: count,
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 7,
                                              mainAxisExtent: cellHeight,
                                            ),
                                        itemBuilder: (context, index) {
                                          final number =
                                              index - firstWeekday + 2;
                                          if (number < 1 || number > days)
                                            return const SizedBox();
                                          final date = DateTime(
                                            _month.year,
                                            _month.month,
                                            number,
                                          );
                                          final key = _day(date);
                                          final selected =
                                              key == _day(_selected);
                                          final isToday =
                                              key == _day(DateTime.now());
                                          final entries = _events[key] ?? [];
                                          return InkWell(
                                            onTap: () => setState(
                                              () => _selected = date,
                                            ),
                                            child: Container(
                                              margin: const EdgeInsets.all(2),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: selected
                                                    ? const Color(0xfffff3d7)
                                                    : Colors.white,
                                                border: Border.all(
                                                  color: selected
                                                      ? _gold
                                                      : const Color(0xffdedbd4),
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        '$number',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              isToday ||
                                                                  selected
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                    .normal,
                                                          color: isToday
                                                              ? const Color(
                                                                  0xffb43d36,
                                                                )
                                                              : _ink,
                                                        ),
                                                      ),
                                                      if (entries
                                                          .isNotEmpty) ...[
                                                        const Spacer(),
                                                        Icon(
                                                          Icons.circle,
                                                          size: 8,
                                                          color:
                                                              entries.any(
                                                                (e) => e.paid,
                                                              )
                                                              ? Colors.green
                                                              : _gold,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  if (entries.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      entries.first.name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (entries.any(
                                                      (e) => e.paid,
                                                    ))
                                                      const Text(
                                                        'Lunas',
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          color: Colors.green,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 16,
                                runSpacing: 10,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: () => _changeMonth(-1),
                                        icon: const Icon(Icons.chevron_left),
                                      ),
                                      Text(
                                        '${_months[_month.month - 1]} ${_month.year}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _changeMonth(1),
                                        icon: const Icon(Icons.chevron_right),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Notifikasi',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ChoiceChip(
                                        label: const Text('ON'),
                                        selected: _notifications,
                                        onSelected: (_) =>
                                            _setNotifications(true),
                                      ),
                                      const SizedBox(width: 6),
                                      ChoiceChip(
                                        label: const Text('OFF'),
                                        selected: !_notifications,
                                        onSelected: (_) =>
                                            _setNotifications(false),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Card(
                                color: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  side: const BorderSide(
                                    color: Color(0xffdedbd4),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'KEGIATAN · ${_selected.day} ${_months[_selected.month - 1]} ${_selected.year}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          FilledButton.icon(
                                            onPressed: () => _editEvent(),
                                            icon: const Icon(Icons.add),
                                            label: const Text('Tambah'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      if (_selectedEvents.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 18,
                                          ),
                                          child: Text(
                                            'Belum ada kegiatan pada tanggal ini.',
                                            style: TextStyle(
                                              color: Colors.black54,
                                            ),
                                          ),
                                        )
                                      else
                                        ..._selectedEvents.map(
                                          (event) => _EventTile(
                                            event: event,
                                            money: _money(event.amount),
                                            onEdit: () => _editEvent(event),
                                            onDelete: () => _deleteEvent(event),
                                          ),
                                        ),
                                    ],
                                  ),
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

class _Event {
  _Event({
    required this.id,
    required this.name,
    required this.date,
    required this.customer,
    required this.amount,
    required this.paid,
    required this.status,
    required this.info,
  });
  String id;
  final String name, customer, status, info;
  final DateTime date;
  final int? amount;
  final bool paid;

  factory _Event.fromJson(Map<String, dynamic> json) => _Event(
    id: json['id'].toString(),
    name: json['name']?.toString() ?? '',
    date: DateTime.parse(json['date'].toString()),
    customer: json['customer']?.toString() ?? '',
    amount: json['amount'] as int?,
    paid: json['paid'] == true,
    status: json['status']?.toString() ?? 'Progress',
    info: json['info']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'date':
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'customer': customer,
    'amount': amount,
    'paid': paid,
    'status': status,
    'info': info,
  };
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.money,
    required this.onEdit,
    required this.onDelete,
  });
  final _Event event;
  final String money;
  final VoidCallback onEdit, onDelete;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfffaf9f6),
      border: Border.all(color: const Color(0xffece9e2)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(
          event.paid ? Icons.check_circle : Icons.event_note,
          color: event.paid ? Colors.green : _gold,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${event.customer.isEmpty ? 'Pelanggan belum diisi' : event.customer} · ${event.status} · $money',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              if (event.info.isNotEmpty)
                Text(event.info, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        if (event.paid)
          const Chip(label: Text('LUNAS'), backgroundColor: Color(0xffe4f4e7)),
        IconButton(
          tooltip: 'Edit',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Hapus',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  );
}

class _NavigationRail extends StatelessWidget {
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
        _assetIcon(
          context,
          'assets/icons/kalender-icon.jpg',
          Icons.calendar_month,
          () {},
        ),
        _assetIcon(
          context,
          'assets/icons/cashflow-icon.jpg',
          Icons.payments_outlined,
          () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CashflowPage()),
          ),
        ),
        _assetIcon(
          context,
          'assets/icons/chart-icon.jpg',
          Icons.pie_chart_outline,
          () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const CatatanPage()),
          ),
        ),
        _assetIcon(
          context,
          'assets/icons/track-icon.png',
          Icons.query_stats,
          () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GrafikPage()),
          ),
        ),
        _assetIcon(
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

  Widget _assetIcon(
    BuildContext context,
    String path,
    IconData fallback,
    VoidCallback onPressed,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: IconButton(
      onPressed: onPressed,
      tooltip: fallback == Icons.payments_outlined ? 'Cashflow' : null,
      icon: Image.asset(
        path,
        width: 28,
        height: 28,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(fallback, color: _ink, size: 27),
      ),
      style: IconButton.styleFrom(
        backgroundColor: fallback == Icons.calendar_month
            ? const Color(0xffeeeeee)
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}
