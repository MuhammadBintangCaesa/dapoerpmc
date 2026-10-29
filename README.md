# Dapoer PMSCU

Flutter client and SQLite-backed Python API for account management, cashflow, and calendar events.

## Start the backend

Requires Python 3.10 or newer; the API uses only Python's standard library.

```sh
python3 backend/server.py create-owner --email owner@dapoer.id
python3 backend/server.py serve --host 0.0.0.0 --port 8765
```

Set a strong owner password when prompted. The database is created at `backend/data/dapoer.sqlite3` by default. Set `DAPOER_DB_PATH` to move it or `API_PORT` to change the port. Keep the database directory backed up and do not commit it.

## Connect the backend to TiDB Cloud

The backend can use TiDB Cloud through MySQL Connector/Python. SQLite remains the default for local development.

1. Create a TiDB Cloud cluster and database named `dapoer` (or choose another database name).
2. In the cluster's **Connect** dialog, get the host, port, username, password, and CA certificate details. TiDB Cloud public connections require TLS; keep certificate verification enabled.
3. Install the optional driver: `python3 -m pip install -r backend/requirements.txt`.
4. Copy `backend/.env.tidb.example` to `backend/.env.tidb` and fill in the cluster values. Keep this file private.
5. Load the values and migrate the existing local database, then start the API:

   ```sh
   set -a
   source backend/.env.tidb
   set +a
   python3 backend/server.py migrate-sqlite --source backend/data/dapoer.sqlite3
   python3 backend/server.py serve --host 0.0.0.0 --port 8765
   ```

   The migration copies accounts, transactions, calendar events, activity logs, webhook messages, and integration settings. Login sessions are intentionally not copied, so users sign in again. Migration stops if destination tables already contain data.

6. Keep the TiDB environment loaded for `create-owner` and every backend start. Do not commit `backend/.env.tidb` or share its password. The backend creates its tables automatically on first connection.

Open the app's **Atur koneksi backend** option on the login screen. Use `http://10.0.2.2:8765` in an Android emulator, or `http://<IP-LAN-LAPTOP>:8765` on a physical phone connected to the same Wi-Fi. For a deployed server use HTTPS. Android permits cleartext HTTP only in debug builds.

## WhatsApp Cloud API setup

1. Expose the backend through a public HTTPS URL and set `PUBLIC_WEBHOOK_URL`, for example `https://api.example.com/api/webhooks/whatsapp`.
2. Set `WHATSAPP_APP_SECRET` and `WHATSAPP_ACCESS_TOKEN` in the backend process environment. These secrets do not belong in the app.
3. Sign into the app as Owner, open **Pengaturan → Log Bot WhatsApp**, and save the Phone Number ID, the owner's WhatsApp number in international digits (for example `62812...`), and a random verify token of at least 16 characters.
4. In Meta's WhatsApp webhook settings, use the public webhook URL and the same verify token; subscribe to `messages`.

Messages from the configured owner number can use these commands:

```text
MASUK | 150000 | Penjualan | Nasi box | 2026-10-29
KELUAR | 50000 | Bahan baku | Beras | 2026-10-29
ACARA | 2026-10-30 | Pesanan rapat | 100 box
VERIFIKASI | <transaksi-id>
TOLAK | <transaksi-id>
```

WhatsApp transactions are recorded as **Perlu dicek** and count toward cashflow totals only after verification. Calendar events and payment status entered in the app are persisted in the backend.

## Notes

- Account creation, edits, password resets, and forced logout are Owner-only. Forced logout revokes the account's sessions; the default account view lists active sessions only. The offline toggle shows retained accounts.
- The API is a small single-host service intended for this project. Put it behind an HTTPS reverse proxy before exposing it publicly.
