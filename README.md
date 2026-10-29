# Dapoer PMSCU

Aplikasi Flutter untuk catat cashflow, jadwal, dan kelola akun.

## Jalanin backend

Butuh Python 3.10+.

```sh
python3 backend/server.py create-owner --email owner@dapoer.id
python3 backend/server.py serve --host 0.0.0.0 --port 8765
```

Password Owner dibuat saat perintah pertama dijalankan. Data lokal ada di `backend/data/dapoer.sqlite3`.

## Pakai TiDB

Pasang driver dan salin file konfigurasi:

```sh
python3 -m pip install -r backend/requirements.txt
cp backend/.env.tidb.example backend/.env.tidb
```

Isi `backend/.env.tidb` dari detail koneksi TiDB Cloud. Jangan upload file ini ke GitHub.

Kalau mau pindahkan data SQLite ke TiDB, jalankan migrasi sekali ke database TiDB yang masih kosong:

```sh
set -a
source backend/.env.tidb
set +a
python3 backend/server.py migrate-sqlite --source backend/data/dapoer.sqlite3
python3 backend/server.py serve --host 0.0.0.0 --port 8765
```

Kalau mulai dari database kosong, jalankan `create-owner` setelah `source`, lalu jalankan `serve`. Data akun, transaksi, kalender, dan pengaturan ikut dimigrasikan. Sesi login tidak ikut, jadi login lagi setelah migrasi.

## Sambungkan aplikasi

Di halaman login, buka **Atur koneksi backend**. Untuk emulator Android pakai `http://10.0.2.2:8765`. Untuk HP, pakai IP laptop dan sambungkan keduanya ke Wi-Fi yang sama.

Kalau aplikasi mau dibagikan ke client, backend harus punya alamat HTTPS. Build APK dengan:

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://alamat-api-kamu
```

Aplikasi nyambung ke backend, lalu backend yang nyambung ke TiDB. Password TiDB jangan dimasukkan ke aplikasi.

## Sambungkan bot WhatsApp

Bot perlu nomor WhatsApp Business yang sudah disiapkan lewat Meta Cloud API.

1. Pasang `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_APP_SECRET`, dan URL webhook HTTPS di backend.
2. Di aplikasi buka **Pengaturan → Log Bot WhatsApp**. Isi Phone Number ID, nomor Owner, dan verify token.
3. Masukkan URL webhook dan verify token yang sama di pengaturan webhook Meta, lalu aktifkan `messages`.

Nomor Owner dan Admin aktif yang diisi di Kelola Akun bisa kirim perintah ke bot:

```text
MASUK | 150000 | Penjualan | Nasi box | 2026-10-29
KELUAR | 50000 | Bahan baku | Beras | 2026-10-29
ACARA | 2026-10-30 | Pesanan rapat | 100 box
VERIFIKASI | <id-transaksi>
TOLAK | <id-transaksi>
```

Transaksi dari WhatsApp perlu diverifikasi dulu sebelum masuk hitungan cashflow. Akun hanya bisa dikelola Owner.
