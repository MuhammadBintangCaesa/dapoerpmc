import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backend_api.dart';
import 'dapoer_header.dart';
import 'cashflow_page.dart';
import 'catatan_page.dart';
import 'grafik_page.dart';
import 'kalender_page.dart';

const _settingGold = Color(0xffcda64d);
const _settingInk = Color(0xff202124);

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});
  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  String _businessName = 'Dapoer PMCSU';
  String _capital = '';
  int _onlineAccountCount = 0;
  bool _onlineCountAvailable = false;
  Timer? _adminRefreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshAdminCount();
    _adminRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshAdminCount(),
    );
  }

  @override
  void dispose() {
    _adminRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAdminCount() async {
    try {
      final accounts = await BackendApi.instance.accounts(onlineOnly: true);
      if (!mounted) return;
      setState(() {
        _onlineAccountCount = accounts
            .where((account) => account['online'] == true)
            .length;
        _onlineCountAvailable = true;
      });
    } catch (_) {
      if (mounted) setState(() => _onlineCountAvailable = false);
    }
  }

  String _money(int amount) =>
      'Rp ${amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}';

  Future<void> _backup() async {
    final rows = <String>['Tanggal,Jenis,Keterangan,Kategori,Nominal,Status'];
    for (final item in sharedCashflowTransactions) {
      rows.add(
        '${item.date.day}/${item.date.month}/${item.date.year},${item.type},"${item.description.replaceAll('"', '""')}","${item.category.replaceAll('"', '""')}",${item.amount},${item.verified ? 'Terverifikasi' : 'Perlu dicek'}',
      );
    }
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Data backup CSV disalin. Tempelkan ke spreadsheet untuk disimpan.',
        ),
      ),
    );
  }

  Future<void> _openPanel(_SettingItem item) async {
    if (item.id == 'bot') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WhatsAppSetupPage()),
      );
      return;
    }
    if (item.id == 'akun') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AccountManagementPage()),
      );
      if (mounted) {
        setState(() {});
        _refreshAdminCount();
      }
      return;
    }
    if (item.id == 'backup') {
      _backup();
      return;
    }
    if (item.id == 'umum') {
      _generalDialog();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item.title),
          content: SizedBox(
            width: 440,
            child: item.id == 'aktivitas' && sharedActivityLog.isNotEmpty
                ? SizedBox(
                    height: 300,
                    child: ListView.separated(
                      itemCount: sharedActivityLog.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.history, size: 18),
                        title: Text(
                          sharedActivityLog[index],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  )
                : _SettingEmptyState(
                    message: item.id == 'aktivitas'
                        ? 'Belum ada riwayat perubahan.'
                        : item.id == 'bot'
                        ? 'Log akan tersedia setelah bot WhatsApp terhubung.'
                        : 'Belum ada data customer dan pesanan.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generalDialog() async {
    final name = TextEditingController(text: _businessName);
    final capital = TextEditingController(text: _capital);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Umum'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Nama usaha',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: capital,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Modal awal (Rp)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved == true)
      setState(() {
        _businessName = name.text.trim().isEmpty
            ? 'Dapoer PMSCU'
            : name.text.trim();
        _capital = capital.text.trim();
      });
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _SettingItem(
        'akun',
        'Kelola Akun',
        'Kelola akun Owner, Admin, dan Staf',
        Icons.manage_accounts_outlined,
        badge: _onlineCountAvailable
            ? '$_onlineAccountCount Online'
            : 'Backend offline',
      ),
      _SettingItem(
        'aktivitas',
        'Log Aktivitas',
        'Riwayat siapa yang mengubah dan melakukan perubahan pada aplikasi',
        Icons.sync,
      ),
      _SettingItem(
        'bot',
        'Log Bot WhatsApp',
        'Melihat aktivitas bot dan monitoring bot',
        Icons.chat_bubble_outline,
      ),
      _SettingItem(
        'customer',
        'Customer',
        'Data customer dan riwayat pesanan',
        Icons.contact_page_outlined,
      ),
      _SettingItem(
        'backup',
        'Backup',
        'Menyalin data transaksi untuk disimpan',
        Icons.cloud_upload_outlined,
        badge: sharedCashflowTransactions.isEmpty
            ? 'Belum ada data'
            : '${sharedCashflowTransactions.length} transaksi',
      ),
      _SettingItem(
        'umum',
        'Umum',
        'Profil data perusahaan dan modal awal',
        Icons.settings_applications_outlined,
      ),
    ];
    return Scaffold(
      backgroundColor: const Color(0xfffaf9f6),
      body: SafeArea(
        child: Row(
          children: [
            _SettingNavigation(),
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
                            children: [
                              const Text(
                                'SETTING DAPOER PMSCU',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 48),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = constraints.maxWidth < 620
                                      ? 1
                                      : 2;
                                  return GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: items.length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          mainAxisExtent: 138,
                                          crossAxisSpacing: 22,
                                          mainAxisSpacing: 20,
                                        ),
                                    itemBuilder: (context, index) =>
                                        _SettingCard(
                                          item: items[index],
                                          onTap: () => _openPanel(items[index]),
                                        ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Profil usaha: $_businessName${_capital.isEmpty ? '' : ' · Modal awal ${_money(int.tryParse(_capital.replaceAll('.', '').replaceAll(',', '')) ?? 0)}'}',
                                style: const TextStyle(
                                  color: Colors.black45,
                                  fontSize: 12,
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

class _ManagedAccount {
  _ManagedAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone = '',
    this.active = true,
    this.online = false,
    required this.lastActive,
  });
  factory _ManagedAccount.fromJson(Map<String, dynamic> value) =>
      _ManagedAccount(
        id: value['id'].toString(),
        name: value['name']?.toString() ?? '',
        email: value['email']?.toString() ?? '',
        role: value['role']?.toString() ?? 'Staf',
        phone: value['phone']?.toString() ?? '',
        active: value['active'] == true,
        online: value['online'] == true,
        lastActive: value['lastActive']?.toString() ?? 'Belum pernah',
      );
  final String id;
  String name;
  String email;
  String role;
  String phone;
  bool active;
  bool online;
  String lastActive;
}

class AccountManagementPage extends StatefulWidget {
  const AccountManagementPage({super.key});
  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  final List<_ManagedAccount> _accounts = [];
  Map<String, dynamic>? _currentUser;
  bool _showOffline = false;
  bool _loading = false;
  Timer? _accountRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _accountRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_loading) _loadAccounts(showLoading: false);
    });
  }

  @override
  void dispose() {
    _accountRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAccounts({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      try {
        _currentUser = await BackendApi.instance.currentAccount();
      } catch (_) {
        _currentUser = BackendApi.instance.account;
      }
      final rows = await BackendApi.instance.accounts(
        onlineOnly: !_showOffline,
      );
      if (!mounted) return;
      setState(() {
        _accounts
          ..clear()
          ..addAll(rows.map(_ManagedAccount.fromJson));
      });
    } catch (error) {
      if (mounted && showLoading) _notice('Gagal memuat akun: $error');
    } finally {
      if (mounted && showLoading) setState(() => _loading = false);
    }
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _editAccount([_ManagedAccount? account]) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: account?.name ?? '');
    final email = TextEditingController(text: account?.email ?? '');
    final phone = TextEditingController(text: account?.phone ?? '');
    final password = TextEditingController();
    var role = account?.role ?? 'Admin';
    var active = account?.active ?? true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(account == null ? 'Buat akun' : 'Edit akun'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Nama',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Nama wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Username atau email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || !value.contains('@')
                          ? 'Masukkan email yang valid'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText:
                            'Nomor WhatsApp (kode negara, contoh 62812...)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final digits = (value ?? '').replaceAll(
                          RegExp(r'\D'),
                          '',
                        );
                        return digits.isNotEmpty &&
                                (digits.length < 8 || digits.length > 15)
                            ? 'Nomor harus 8–15 digit'
                            : null;
                      },
                    ),
                    if (account == null) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password awal (min. 8 karakter)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.length < 8
                            ? 'Password minimal 8 karakter'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Owner', child: Text('Owner')),
                        DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                        DropdownMenuItem(value: 'Staf', child: Text('Staf')),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => role = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<bool>(
                      initialValue: active,
                      decoration: const InputDecoration(
                        labelText: 'Status akun',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: true, child: Text('Aktif')),
                        DropdownMenuItem(value: false, child: Text('Nonaktif')),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => active = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Perubahan ini dicatat di Log Aktivitas.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                if ((account?.role == 'Owner' || role == 'Owner') && !active) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Akun Owner tidak dapat dinonaktifkan.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      final payload = {
        'name': name.text.trim(),
        'email': email.text.trim(),
        'role': role,
        'phone': phone.text.trim(),
        'active': active,
      };
      if (account == null) {
        await BackendApi.instance.createAccount({
          ...payload,
          'password': password.text,
        });
      } else {
        await BackendApi.instance.updateAccount(account.id, payload);
      }
      await _loadAccounts();
    } catch (error) {
      _notice('Akun gagal disimpan: $error');
    }
  }

  Future<void> _resetPassword(_ManagedAccount account) async {
    final formKey = GlobalKey<FormState>();
    final password = TextEditingController();
    final confirmation = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Atur password baru untuk ${account.name}.'),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password baru',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.length < 12
                      ? 'Password minimal 12 karakter'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmation,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Ulangi password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value != password.text ? 'Password tidak sama' : null,
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Perubahan ini dicatat di Log Aktivitas.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate())
                Navigator.pop(context, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      try {
        await BackendApi.instance.resetAccountPassword(
          account.id,
          password.text,
        );
        _notice('Password berhasil direset. Sesi akun sudah dikeluarkan.');
        await _loadAccounts();
      } catch (error) {
        _notice('Reset password gagal: $error');
      }
    }
  }

  Future<void> _forceLogout(_ManagedAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paksa keluar'),
        content: Text('Keluarkan ${account.name} dari sesi aktif?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await BackendApi.instance.forceLogout(account.id);
        setState(() => _showOffline = false);
        await _loadAccounts();
        _notice(
          '${account.name} sudah logout dan hilang dari daftar sesi aktif.',
        );
      } catch (error) {
        _notice('Logout gagal: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfffaf9f6),
    body: SafeArea(
      child: Row(
        children: [
          _SettingNavigation(),
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
                              'KELOLA AKUN DAPOER PMSCU',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (_currentUser != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xffe0f5ef),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.circle,
                                      color: Color(0xff21856c),
                                      size: 11,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Anda login sebagai ${_currentUser!['name']} (${_currentUser!['role']})',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if ((_currentUser!['phone']
                                                      ?.toString() ??
                                                  '')
                                              .isNotEmpty)
                                            Text(
                                              'WhatsApp +${_currentUser!['phone']}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const _AccountPill(
                                      text: 'Online',
                                      color: Color(0xffc8eee3),
                                      textColor: Color(0xff21856c),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 46),
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.chevron_left),
                                  label: const Text('Pengaturan'),
                                ),
                                const Text(
                                  'Akun',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                FilledButton.icon(
                                  onPressed: () => _editAccount(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Buat akun'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'Hanya Owner yang bisa mengakses halaman ini',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                            Row(
                              children: [
                                const Expanded(child: Text('Sesi aktif')),
                                const Text('Tampilkan akun offline'),
                                Switch(
                                  value: _showOffline,
                                  onChanged: (value) {
                                    setState(() => _showOffline = value);
                                    _loadAccounts();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else
                              LayoutBuilder(
                                builder: (context, constraints) =>
                                    constraints.maxWidth < 760
                                    ? _accountCards()
                                    : SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: SizedBox(
                                          width: math
                                              .max(constraints.maxWidth, 850)
                                              .toDouble(),
                                          child: _accountsTable(),
                                        ),
                                      ),
                              ),
                            const SizedBox(height: 14),
                            const Text(
                              'Ikon kunci: reset password. Ikon logout: paksa keluar. Akun lebih baik dinonaktifkan daripada dihapus.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
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

  Widget _accountsTable() => Container(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xffdddddd)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(Color(0xfff3f3f3)),
        dataRowMinHeight: 72,
        dataRowMaxHeight: 86,
        columns: const [
          DataColumn(label: Text('Nama')),
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Terakhir aktif')),
          DataColumn(label: Text('Aksi')),
        ],
        rows: [
          for (final account in _accounts)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 170,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account.name),
                        Text(
                          account.email,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                        Text(
                          account.phone.isEmpty
                              ? 'WhatsApp belum diisi'
                              : 'WhatsApp +${account.phone}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  _AccountPill(
                    text: account.role,
                    color: const Color(0xffeeeeee),
                  ),
                ),
                DataCell(
                  _AccountPill(
                    text: !account.active
                        ? 'Nonaktif'
                        : account.online
                        ? 'Online'
                        : 'Offline',
                    color: !account.active
                        ? const Color(0xffffeaea)
                        : account.online
                        ? const Color(0xffe0f5ef)
                        : const Color(0xffeeeeee),
                    textColor: !account.active
                        ? Colors.red
                        : account.online
                        ? const Color(0xff21856c)
                        : Colors.black54,
                  ),
                ),
                DataCell(
                  Text(account.online ? 'Sekarang' : account.lastActive),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit akun',
                        onPressed: () => _editAccount(account),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Reset password',
                        onPressed: () => _resetPassword(account),
                        icon: const Icon(Icons.key_outlined),
                      ),
                      if (account.role != 'Owner' &&
                          account.active &&
                          account.online)
                        IconButton(
                          tooltip: 'Paksa logout',
                          onPressed: () => _forceLogout(account),
                          icon: const Icon(Icons.logout),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _accountCards() => Column(
    children: [
      for (final account in _accounts)
        Card(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xffdddddd)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  account.email,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                Text(
                  account.phone.isEmpty
                      ? 'WhatsApp belum diisi'
                      : 'WhatsApp +${account.phone}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AccountPill(
                      text: account.role,
                      color: const Color(0xffeeeeee),
                    ),
                    _AccountPill(
                      text: !account.active
                          ? 'Nonaktif'
                          : account.online
                          ? 'Online'
                          : 'Offline',
                      color: !account.active
                          ? const Color(0xffffeaea)
                          : account.online
                          ? const Color(0xffe0f5ef)
                          : const Color(0xffeeeeee),
                      textColor: account.online
                          ? const Color(0xff21856c)
                          : Colors.black54,
                    ),
                    Text(
                      account.online ? 'Sekarang' : account.lastActive,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _editAccount(account),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _resetPassword(account),
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('Reset password'),
                    ),
                    if (account.role != 'Owner' &&
                        account.active &&
                        account.online)
                      OutlinedButton.icon(
                        onPressed: () => _forceLogout(account),
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      if (_accounts.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _showOffline ? 'Belum ada akun.' : 'Tidak ada sesi akun aktif.',
          ),
        ),
    ],
  );
}

class WhatsAppSetupPage extends StatefulWidget {
  const WhatsAppSetupPage({super.key});
  @override
  State<WhatsAppSetupPage> createState() => _WhatsAppSetupPageState();
}

class _WhatsAppSetupPageState extends State<WhatsAppSetupPage> {
  final _phoneId = TextEditingController();
  final _ownerPhone = TextEditingController();
  final _verifyToken = TextEditingController();
  Map<String, dynamic> _config = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await BackendApi.instance.whatsappSettings();
      if (!mounted) return;
      setState(() {
        _config = config;
        _phoneId.text = config['phoneNumberId']?.toString() ?? '';
        final savedOwnerPhone = config['ownerPhone']?.toString() ?? '';
        final activeAccountPhone =
            BackendApi.instance.account?['phone']?.toString() ?? '';
        _ownerPhone.text = savedOwnerPhone.isNotEmpty
            ? savedOwnerPhone
            : activeAccountPhone.replaceAll(RegExp(r'\D'), '');
      });
    } catch (error) {
      if (mounted) _message('Gagal memuat konfigurasi: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await BackendApi.instance.saveWhatsappSettings(
        phoneNumberId: _phoneId.text.trim(),
        ownerPhone: _ownerPhone.text.trim(),
        verifyToken: _verifyToken.text.trim(),
      );
      _verifyToken.clear();
      await _load();
      _message('Konfigurasi WhatsApp berhasil disimpan.');
    } catch (error) {
      _message('Konfigurasi gagal disimpan: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _phoneId.dispose();
    _ownerPhone.dispose();
    _verifyToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Koneksi Bot WhatsApp')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Setup WhatsApp Cloud API',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Transaksi MASUK/KELUAR dari nomor owner akan masuk sebagai Perlu dicek. Perintah ACARA akan masuk ke kalender.',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          margin: EdgeInsets.zero,
                          color: const Color(0xfffaf8f2),
                          child: ExpansionTile(
                            leading: const Icon(Icons.menu_book_outlined),
                            title: const Text(
                              'Cara membuat dan menghubungkan bot',
                            ),
                            subtitle: const Text(
                              'Panduan Meta WhatsApp Cloud API',
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            children: [
                              const _SetupStep(
                                number: '1',
                                title: 'Buat app WhatsApp di Meta',
                                detail:
                                    'Buka Meta for Developers, buat app untuk WhatsApp Business Platform, lalu tambahkan akun bisnis dan nomor WhatsApp Business client yang akan menjadi nomor bot.',
                              ),
                              const _SetupStep(
                                number: '2',
                                title: 'Ambil ID dan token API',
                                detail:
                                    'Dari konfigurasi nomor di dashboard Meta, salin Phone Number ID. Simpan access token dan App Secret sebagai environment backend: WHATSAPP_ACCESS_TOKEN dan WHATSAPP_APP_SECRET.',
                              ),
                              const _SetupStep(
                                number: '3',
                                title: 'Siapkan webhook publik HTTPS',
                                detail:
                                    'Deploy backend ke server dengan HTTPS. Isi PUBLIC_WEBHOOK_URL di server, lalu pakai URL /api/webhooks/whatsapp dan verify token yang sama di Meta. Subscribe webhook ke pesan masuk (messages).',
                              ),
                              const _SetupStep(
                                number: '4',
                                title: 'Isi konfigurasi aplikasi ini',
                                detail:
                                    'Masukkan Phone Number ID, nomor WhatsApp owner dan verify token. Nomor WhatsApp Owner/Admin aktif yang diisi di Kelola Akun juga diizinkan mengirim instruksi. Access token dan App Secret jangan dimasukkan di sini.',
                              ),
                              const _SetupStep(
                                number: '5',
                                title: 'Kirim pesan uji',
                                detail:
                                    'Kirim: MASUK | 150000 | Penjualan | Nasi box | 2026-10-29. Transaksi masuk sebagai Perlu dicek dan perlu diverifikasi di Cashflow.',
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    const ClipboardData(
                                      text:
                                          'https://whatsappbusiness.com/developers/developer-hub/',
                                    ),
                                  );
                                  if (mounted)
                                    _message(
                                      'Link panduan resmi Meta disalin.',
                                    );
                                },
                                icon: const Icon(Icons.copy),
                                label: const Text(
                                  'Salin link Meta Developer Hub',
                                ),
                              ),
                              const Text(
                                'Catatan: integrasi ini memakai WhatsApp Business Cloud API untuk satu nomor bot. Nomor Owner yang diisi di sini dan nomor akun Owner/Admin aktif yang terdaftar di Kelola Akun dapat mengirim perintah.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _phoneId,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number ID',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _ownerPhone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Nomor WhatsApp owner',
                            hintText: '62812...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _verifyToken,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Verify token (minimal 16 karakter)',
                            helperText:
                                'Wajib saat setup pertama. Kosongkan untuk tetap memakai token yang sudah tersimpan.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Webhook: ${_config['webhookUrl'] ?? 'Belum disetel di server'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'Verify token: ${_config['verifyTokenConfigured'] == true ? 'sudah disetel' : 'belum disetel'} · App secret: ${_config['appSecretConfigured'] == true ? 'siap' : 'belum di server'} · Access token: ${_config['accessTokenConfigured'] == true ? 'siap' : 'belum di server'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(
                            _saving ? 'Menyimpan…' : 'Simpan konfigurasi',
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Token akses dan App Secret disimpan di environment server, jangan masukkan ke aplikasi. Format pesan: MASUK | 150000 | Penjualan | Nasi box | 2026-10-29',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: const Color(0xffe0f5ef),
          child: Text(
            number,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AccountPill extends StatelessWidget {
  const _AccountPill({
    required this.text,
    required this.color,
    this.textColor = Colors.black54,
  });
  final String text;
  final Color color, textColor;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 76),
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: textColor)),
    ),
  );
}

class _SettingItem {
  const _SettingItem(
    this.id,
    this.title,
    this.description,
    this.icon, {
    this.badge,
  });
  final String id, title, description;
  final String? badge;
  final IconData icon;
}

class _SettingCard extends StatefulWidget {
  const _SettingCard({required this.item, required this.onTap});
  final _SettingItem item;
  final VoidCallback onTap;
  @override
  State<_SettingCard> createState() => _SettingCardState();
}

class _SettingCardState extends State<_SettingCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: _hovered ? _settingGold : _settingInk,
          width: _hovered ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _hovered
            ? [
                BoxShadow(
                  color: Colors.black.withAlpha(15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  color: const Color(0xfff1f1f1),
                  child: Icon(widget.item.icon, size: 38, color: Colors.black),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                      if (widget.item.badge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xff78f0d0),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              widget.item.badge!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 23),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SettingEmptyState extends StatelessWidget {
  const _SettingEmptyState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 26),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inbox_outlined, size: 36, color: Colors.black38),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    ),
  );
}

class _SettingNavigation extends StatelessWidget {
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
          () {},
          selected: true,
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
      tooltip: selected ? 'Setting' : null,
      onPressed: action,
      style: IconButton.styleFrom(
        backgroundColor: selected ? const Color(0xffeeeeee) : null,
        overlayColor: _settingGold.withAlpha(30),
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
