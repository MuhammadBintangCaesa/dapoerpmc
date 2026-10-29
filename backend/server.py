#!/usr/bin/env python3
"""SQLite/TiDB-backed API for the Dapoer PMSCU Flutter app.

Run `python3 backend/server.py create-owner` once, then `python3 backend/server.py serve`.
WhatsApp app secret and access token are read from environment variables and never
returned by the API.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("DAPOER_DB_PATH", ROOT / "data" / "dapoer.sqlite3"))
DATABASE_BACKEND = os.environ.get("DATABASE_BACKEND", "sqlite").lower()
MAX_BODY = 1_000_000
ROLES = {"Owner", "Admin", "Staf"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class TiDBConnection:
    """Small adapter for the DB-API calls used by this app."""

    def __init__(self, connection: Any):
        self.connection = connection

    def __enter__(self) -> "TiDBConnection":
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        try:
            if exc_type is None:
                self.connection.commit()
            else:
                self.connection.rollback()
        finally:
            self.connection.close()

    def execute(self, sql: str, params: tuple[Any, ...] = ()) -> Any:
        cursor = self.connection.cursor(dictionary=True)
        cursor.execute(sql.replace("?", "%s"), params)
        return cursor

    def executescript(self, script: str) -> None:
        cursor = self.connection.cursor()
        try:
            for statement in script.split(";"):
                if statement.strip():
                    cursor.execute(statement)
        finally:
            cursor.close()


def get_db() -> Any:
    if DATABASE_BACKEND == "tidb":
        try:
            import mysql.connector
        except ImportError as exc:
            raise RuntimeError(
                "TiDB dipilih tetapi driver belum terpasang. Jalankan pip install -r backend/requirements.txt"
            ) from exc
        required = ["TIDB_HOST", "TIDB_USER", "TIDB_PASSWORD", "TIDB_DATABASE"]
        missing = [key for key in required if not os.environ.get(key)]
        if missing:
            raise RuntimeError(f"Environment TiDB belum lengkap: {', '.join(missing)}")
        options: dict[str, Any] = {
            "host": os.environ["TIDB_HOST"],
            "port": int(os.environ.get("TIDB_PORT", "4000")),
            "user": os.environ["TIDB_USER"],
            "password": os.environ["TIDB_PASSWORD"],
            "database": os.environ["TIDB_DATABASE"],
            "connection_timeout": 10,
            "autocommit": False,
        }
        ca_path = os.environ.get("TIDB_SSL_CA")
        tls_enabled = os.environ.get("TIDB_SSL", "true").lower() == "true"
        options["ssl_disabled"] = not tls_enabled
        if tls_enabled:
            options.update(ssl_verify_cert=True, ssl_verify_identity=True)
            if ca_path:
                options["ssl_ca"] = ca_path
        return TiDBConnection(mysql.connector.connect(**options))

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB_PATH, timeout=15)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA journal_mode = WAL")
    return db


def init_db() -> None:
    with get_db() as db:
        if DATABASE_BACKEND == "tidb":
            db.executescript("""
            CREATE TABLE IF NOT EXISTS accounts (
              id VARCHAR(64) PRIMARY KEY, name VARCHAR(255) NOT NULL,
              email VARCHAR(320) NOT NULL UNIQUE, role VARCHAR(20) NOT NULL,
              phone VARCHAR(32) NOT NULL DEFAULT '',
              password_hash VARCHAR(255) NOT NULL, active TINYINT NOT NULL DEFAULT 1,
              created_at VARCHAR(40) NOT NULL, last_active VARCHAR(40)
            ) ENGINE=InnoDB;
            CREATE TABLE IF NOT EXISTS sessions (
              token_hash VARCHAR(64) PRIMARY KEY, account_id VARCHAR(64) NOT NULL,
              created_at VARCHAR(40) NOT NULL, expires_at BIGINT NOT NULL,
              CONSTRAINT fk_sessions_account FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
              INDEX idx_sessions_account (account_id)
            ) ENGINE=InnoDB;
            CREATE TABLE IF NOT EXISTS transactions (
              id VARCHAR(64) PRIMARY KEY, type VARCHAR(20) NOT NULL,
              description TEXT NOT NULL, category VARCHAR(255) NOT NULL,
              amount BIGINT NOT NULL, transaction_date VARCHAR(10) NOT NULL,
              status VARCHAR(20) NOT NULL DEFAULT 'pending', source VARCHAR(100) NOT NULL DEFAULT 'Input aplikasi',
              created_by VARCHAR(64), created_at VARCHAR(40) NOT NULL, updated_at VARCHAR(40) NOT NULL,
              INDEX idx_transactions_date (transaction_date),
              CONSTRAINT fk_transactions_account FOREIGN KEY (created_by) REFERENCES accounts(id) ON DELETE SET NULL
            ) ENGINE=InnoDB;
            CREATE TABLE IF NOT EXISTS calendar_events (
              id VARCHAR(64) PRIMARY KEY, title VARCHAR(255) NOT NULL, event_date VARCHAR(10) NOT NULL,
              customer VARCHAR(255) NOT NULL DEFAULT '', status VARCHAR(40) NOT NULL DEFAULT 'Progress',
              amount BIGINT NULL, paid TINYINT NOT NULL DEFAULT 0, info TEXT NOT NULL,
              created_by VARCHAR(64), created_at VARCHAR(40) NOT NULL, updated_at VARCHAR(40) NOT NULL,
              INDEX idx_events_date (event_date),
              CONSTRAINT fk_events_account FOREIGN KEY (created_by) REFERENCES accounts(id) ON DELETE SET NULL
            ) ENGINE=InnoDB;
            CREATE TABLE IF NOT EXISTS activity_log (
              id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, actor VARCHAR(320) NOT NULL,
              action VARCHAR(255) NOT NULL, target VARCHAR(255) NOT NULL DEFAULT '', created_at VARCHAR(40) NOT NULL
            ) ENGINE=InnoDB;
            CREATE TABLE IF NOT EXISTS integration_settings (
              `key` VARCHAR(100) PRIMARY KEY, value TEXT NOT NULL
            ) ENGINE=InnoDB;
            CREATE TABLE IF NOT EXISTS webhook_messages (
              id VARCHAR(255) PRIMARY KEY, sender VARCHAR(32) NOT NULL, body TEXT NOT NULL,
              status VARCHAR(40) NOT NULL, transaction_id VARCHAR(64), received_at VARCHAR(40) NOT NULL
            ) ENGINE=InnoDB;
            """)
            if not db.execute("SHOW COLUMNS FROM accounts LIKE 'phone'").fetchone():
                db.execute("ALTER TABLE accounts ADD COLUMN phone VARCHAR(32) NOT NULL DEFAULT ''")
            return
        db.executescript("""
        CREATE TABLE IF NOT EXISTS accounts (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE,
          role TEXT NOT NULL CHECK(role IN ('Owner','Admin','Staf')),
          phone TEXT NOT NULL DEFAULT '',
          password_hash TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL, last_active TEXT
        );
        CREATE TABLE IF NOT EXISTS sessions (
          token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          created_at TEXT NOT NULL, expires_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS transactions (
          id TEXT PRIMARY KEY, type TEXT NOT NULL CHECK(type IN ('Pemasukan','Pengeluaran')),
          description TEXT NOT NULL, category TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0),
          transaction_date TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending'
            CHECK(status IN ('pending','verified','rejected')),
          source TEXT NOT NULL DEFAULT 'Input aplikasi', created_by TEXT REFERENCES accounts(id),
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS calendar_events (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, event_date TEXT NOT NULL,
          customer TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'Progress',
          amount INTEGER, paid INTEGER NOT NULL DEFAULT 0, info TEXT NOT NULL DEFAULT '',
          created_by TEXT REFERENCES accounts(id), created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS activity_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT, actor TEXT NOT NULL, action TEXT NOT NULL,
          target TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS integration_settings (
          key TEXT PRIMARY KEY, value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS webhook_messages (
          id TEXT PRIMARY KEY, sender TEXT NOT NULL, body TEXT NOT NULL,
          status TEXT NOT NULL, transaction_id TEXT, received_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(transaction_date);
        CREATE INDEX IF NOT EXISTS idx_events_date ON calendar_events(event_date);
        CREATE INDEX IF NOT EXISTS idx_sessions_account ON sessions(account_id);
        """)
        columns = {row[1] for row in db.execute("PRAGMA table_info(accounts)").fetchall()}
        if "phone" not in columns:
            db.execute("ALTER TABLE accounts ADD COLUMN phone TEXT NOT NULL DEFAULT ''")


def password_hash(password: str, salt: bytes | None = None) -> str:
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1)
    return f"scrypt${base64.urlsafe_b64encode(salt).decode()}${base64.urlsafe_b64encode(digest).decode()}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        kind, salt_text, digest_text = encoded.split("$", 2)
        if kind != "scrypt":
            return False
        salt = base64.urlsafe_b64decode(salt_text)
        expected = base64.urlsafe_b64decode(digest_text)
        actual = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1)
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def log_activity(db: sqlite3.Connection, actor: str, action: str, target: str = "") -> None:
    db.execute("INSERT INTO activity_log(actor, action, target, created_at) VALUES (?,?,?,?)",
               (actor, action, target, utc_now()))


def is_integrity_error(exc: Exception) -> bool:
    return isinstance(exc, sqlite3.IntegrityError) or getattr(exc, "errno", None) in {
        1062, 1451, 1452, 3819
    }


def normalize_phone(value: Any) -> str:
    digits = "".join(char for char in str(value or "") if char.isdigit())
    # Normalize Indonesian local notation so it matches WhatsApp's 62... sender ID.
    if digits.startswith("0"):
        return "62" + digits[1:]
    return digits


def safe_account(row: sqlite3.Row, online: bool = False) -> dict[str, Any]:
    return {"id": row["id"], "name": row["name"], "email": row["email"], "role": row["role"],
            "phone": row["phone"] or "", "active": bool(row["active"]), "online": online,
            "lastActive": row["last_active"] or "Belum pernah"}


def transaction_json(row: sqlite3.Row) -> dict[str, Any]:
    return {"id": row["id"], "type": row["type"], "description": row["description"],
            "category": row["category"], "amount": row["amount"], "date": row["transaction_date"],
            "status": row["status"], "verified": row["status"] == "verified", "source": row["source"]}


def event_json(row: sqlite3.Row) -> dict[str, Any]:
    return {"id": row["id"], "name": row["title"], "date": row["event_date"],
            "customer": row["customer"], "status": row["status"], "amount": row["amount"],
            "paid": bool(row["paid"]), "info": row["info"]}


def setting_get(db: sqlite3.Connection, key: str, default: str = "") -> str:
    row = db.execute("SELECT value FROM integration_settings WHERE `key`=?", (key,)).fetchone()
    return row["value"] if row else default


def parse_whatsapp_message(db: sqlite3.Connection, sender: str, body: str) -> tuple[str, str | None]:
    """Parse MASUK/KELUAR/ACARA/VERIFIKASI/TOLAK commands from the owner."""
    parts = [part.strip() for part in body.split("|")]
    upper = parts[0].upper() if parts else ""
    now = utc_now()
    if upper in {"MASUK", "KELUAR"} and len(parts) >= 4:
        amount_text = parts[1].replace("Rp", "").replace("rp", "").replace(".", "").replace(",", "").strip()
        try:
            amount = int(amount_text)
            if amount <= 0:
                raise ValueError
        except ValueError:
            return "Format nominal salah; contoh: MASUK | 150000 | Penjualan | Nasi box | 2026-10-29", None
        try:
            event_date = date.fromisoformat(parts[4]) if len(parts) > 4 and parts[4] else date.today()
        except ValueError:
            return "Format tanggal salah. Gunakan YYYY-MM-DD.", None
        item_id = secrets.token_urlsafe(12)
        kind = "Pemasukan" if upper == "MASUK" else "Pengeluaran"
        db.execute("""INSERT INTO transactions(id,type,description,category,amount,transaction_date,status,source,created_at,updated_at)
                      VALUES (?,?,?,?,?,?,'pending','WhatsApp',?,?)""",
                   (item_id, kind, parts[3], parts[2], amount, event_date.isoformat(), now, now))
        return f"Transaksi {item_id} dicatat sebagai Perlu dicek. Verifikasi dengan: VERIFIKASI | {item_id}", item_id
    if upper == "ACARA" and len(parts) >= 3:
        try:
            event_date = date.fromisoformat(parts[1])
        except ValueError:
            return "Format tanggal salah. Gunakan ACARA | YYYY-MM-DD | Nama acara | Info", None
        event_id = secrets.token_urlsafe(12)
        info = parts[3] if len(parts) > 3 else ""
        db.execute("""INSERT INTO calendar_events(id,title,event_date,info,status,created_at,updated_at)
                      VALUES (?,?,?,?,'Progress',?,?)""",
                   (event_id, parts[2], event_date.isoformat(), info, now, now))
        return f"Kegiatan '{parts[2]}' dicatat untuk {event_date.isoformat()}.", None
    if upper in {"VERIFIKASI", "TOLAK"} and len(parts) >= 2:
        target_id = parts[1]
        state = "verified" if upper == "VERIFIKASI" else "rejected"
        cursor = db.execute("UPDATE transactions SET status=?,updated_at=? WHERE id=? AND status='pending'",
                            (state, now, target_id))
        if cursor.rowcount:
            log_activity(db, sender, f"Transaksi {state} lewat WhatsApp", target_id)
            return f"Transaksi {target_id} berhasil {'diverifikasi' if state == 'verified' else 'ditolak'}.", target_id
        return "Transaksi tidak ditemukan atau sudah diproses.", None
    return "Format perintah tidak dikenali. Gunakan MASUK, KELUAR, ACARA, VERIFIKASI, atau TOLAK.", None


class ApiHandler(BaseHTTPRequestHandler):
    server_version = "DapoerAPI/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _cors(self) -> None:
        origin = os.environ.get("CORS_ORIGINS", "*")
        self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Hub-Signature-256")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        self.send_header("Vary", "Origin")

    def send_json(self, status: int, payload: Any) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode()
        self.send_response(status)
        self._cors()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_json(self) -> dict[str, Any]:
        size = int(self.headers.get("Content-Length", "0"))
        if size <= 0 or size > MAX_BODY:
            raise ValueError("Body kosong atau terlalu besar")
        value = json.loads(self.rfile.read(size))
        if not isinstance(value, dict):
            raise ValueError("Body harus berupa object JSON")
        return value

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.end_headers()

    def _current_account(self, db: sqlite3.Connection) -> sqlite3.Row | None:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return None
        raw = header[7:].strip()
        token_hash = hashlib.sha256(raw.encode()).hexdigest()
        row = db.execute("""SELECT a.* FROM sessions s JOIN accounts a ON a.id=s.account_id
                            WHERE s.token_hash=? AND s.expires_at>? AND a.active=1""",
                         (token_hash, int(time.time()))).fetchone()
        return row

    def _require(self, db: sqlite3.Connection, owner: bool = False) -> sqlite3.Row | None:
        account = self._current_account(db)
        if not account:
            self.send_json(401, {"error": "Sesi tidak valid atau sudah berakhir"})
            return None
        if owner and account["role"] != "Owner":
            self.send_json(403, {"error": "Hanya Owner yang boleh melakukan aksi ini"})
            return None
        return account

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path, query = parsed.path.rstrip("/"), parse_qs(parsed.query)
        with get_db() as db:
            if path == "/health":
                self.send_json(200, {"ok": True, "service": "dapoer-api"}); return
            if path == "/api/webhooks/whatsapp":
                self._whatsapp_challenge(query); return
            account = self._require(db)
            if not account: return
            if path == "/api/auth/me":
                self.send_json(200, safe_account(account, True)); return
            if path == "/api/accounts":
                if account["role"] != "Owner":
                    self.send_json(403, {"error": "Hanya Owner yang boleh melihat akun"}); return
                online_only = query.get("online_only", ["false"])[0].lower() == "true"
                account_order = "a.name" if DATABASE_BACKEND == "tidb" else "a.name COLLATE NOCASE"
                rows = db.execute(f"""SELECT a.*, EXISTS(SELECT 1 FROM sessions s WHERE s.account_id=a.id AND s.expires_at>?) AS online
                                    FROM accounts a WHERE (?=0 OR EXISTS(SELECT 1 FROM sessions s WHERE s.account_id=a.id AND s.expires_at>?))
                                    ORDER BY CASE a.role WHEN 'Owner' THEN 0 WHEN 'Admin' THEN 1 ELSE 2 END,{account_order}""",
                                  (int(time.time()), int(not online_only), int(time.time()))).fetchall()
                self.send_json(200, [safe_account(row, bool(row["online"])) for row in rows]); return
            if path == "/api/transactions":
                rows = db.execute("SELECT * FROM transactions ORDER BY transaction_date DESC,created_at DESC").fetchall()
                self.send_json(200, [transaction_json(row) for row in rows]); return
            if path == "/api/calendar/events":
                start = query.get("from", ["0001-01-01"])[0]
                end = query.get("to", ["9999-12-31"])[0]
                rows = db.execute("SELECT * FROM calendar_events WHERE event_date BETWEEN ? AND ? ORDER BY event_date", (start, end)).fetchall()
                self.send_json(200, [event_json(row) for row in rows]); return
            if path == "/api/activity":
                if account["role"] != "Owner":
                    self.send_json(403, {"error": "Hanya Owner yang boleh melihat log aktivitas"}); return
                rows = db.execute("SELECT * FROM activity_log ORDER BY id DESC LIMIT 300").fetchall()
                self.send_json(200, [dict(row) for row in rows]); return
            if path == "/api/integrations/whatsapp":
                if account["role"] != "Owner":
                    self.send_json(403, {"error": "Hanya Owner yang boleh mengatur WhatsApp"}); return
                self.send_json(200, {"phoneNumberId": setting_get(db, "wa_phone_number_id"),
                    "ownerPhone": setting_get(db, "wa_owner_phone"),
                    "verifyTokenConfigured": bool(setting_get(db, "wa_verify_token_hash")),
                    "appSecretConfigured": bool(os.environ.get("WHATSAPP_APP_SECRET")),
                    "accessTokenConfigured": bool(os.environ.get("WHATSAPP_ACCESS_TOKEN")),
                    "webhookPath": "/api/webhooks/whatsapp",
                    "webhookUrl": os.environ.get("PUBLIC_WEBHOOK_URL", "")}); return
            self.send_json(404, {"error": "Endpoint tidak ditemukan"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path.rstrip("/")
        if path == "/api/webhooks/whatsapp":
            self._whatsapp_message(); return
        try:
            body = self.read_json()
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_json(400, {"error": str(exc)}); return
        with get_db() as db:
            if path == "/api/auth/login":
                email = str(body.get("email", "")).strip().lower()
                password = str(body.get("password", ""))
                account = db.execute("SELECT * FROM accounts WHERE email=?", (email,)).fetchone()
                if not account or not account["active"] or not verify_password(password, account["password_hash"]):
                    self.send_json(401, {"error": "Email atau password salah"}); return
                token = secrets.token_urlsafe(36)
                db.execute("INSERT INTO sessions(token_hash,account_id,created_at,expires_at) VALUES (?,?,?,?)",
                           (hashlib.sha256(token.encode()).hexdigest(), account["id"], utc_now(), int(time.time()) + 60 * 60 * 24 * 14))
                db.execute("UPDATE accounts SET last_active=? WHERE id=?", (utc_now(), account["id"]))
                log_activity(db, account["email"], "Login", account["id"])
                self.send_json(200, {"token": token, "account": safe_account(account, True)}); return
            if path == "/api/auth/logout":
                account = self._require(db)
                if not account: return
                raw = self.headers.get("Authorization", "")[7:].strip()
                db.execute("DELETE FROM sessions WHERE token_hash=?", (hashlib.sha256(raw.encode()).hexdigest(),))
                log_activity(db, account["email"], "Logout", account["id"])
                self.send_json(200, {"ok": True}); return
            account = self._require(db, owner=(path == "/api/accounts" or path.startswith("/api/accounts/") or path == "/api/integrations/whatsapp"))
            if not account: return
            if path.startswith("/api/accounts/") and path.endswith("/logout"):
                target_id = path.split("/")[3]
                target = db.execute("SELECT * FROM accounts WHERE id=?", (target_id,)).fetchone()
                if not target:
                    self.send_json(404, {"error": "Akun tidak ditemukan"}); return
                if target["role"] == "Owner":
                    self.send_json(400, {"error": "Sesi Owner tidak dapat diputus dari sini"}); return
                db.execute("DELETE FROM sessions WHERE account_id=?", (target_id,))
                db.execute("UPDATE accounts SET last_active=? WHERE id=?", (utc_now(), target_id))
                log_activity(db, account["email"], "Sesi akun dipaksa keluar", target["email"])
                self.send_json(200, {"ok": True}); return
            if path.startswith("/api/accounts/") and path.endswith("/reset-password"):
                target_id = path.split("/")[3]
                target = db.execute("SELECT * FROM accounts WHERE id=?", (target_id,)).fetchone()
                new_password = str(body.get("password", ""))
                if not target:
                    self.send_json(404, {"error": "Akun tidak ditemukan"}); return
                if len(new_password) < 12:
                    self.send_json(400, {"error": "Password harus minimal 12 karakter"}); return
                db.execute("UPDATE accounts SET password_hash=? WHERE id=?", (password_hash(new_password), target_id))
                db.execute("DELETE FROM sessions WHERE account_id=?", (target_id,))
                log_activity(db, account["email"], "Password akun direset", target["email"])
                self.send_json(200, {"ok": True}); return
            if path == "/api/accounts":
                name, email, role, password = (str(body.get(key, "")).strip() for key in ("name", "email", "role", "password"))
                phone = normalize_phone(body.get("phone"))
                if not name or "@" not in email or role not in ROLES or len(password) < 8:
                    self.send_json(400, {"error": "Nama, email valid, role, dan password minimal 8 karakter wajib diisi"}); return
                if phone and not 8 <= len(phone) <= 15:
                    self.send_json(400, {"error": "Nomor WhatsApp harus 8–15 digit dengan kode negara"}); return
                if role == "Owner" and not body.get("active", True):
                    self.send_json(400, {"error": "Akun Owner tidak dapat dibuat nonaktif"}); return
                account_id = secrets.token_urlsafe(12)
                try:
                    db.execute("INSERT INTO accounts(id,name,email,role,phone,password_hash,active,created_at) VALUES (?,?,?,?,?,?,?,?)",
                               (account_id, name, email.lower(), role, phone, password_hash(password), int(bool(body.get("active", True))), utc_now()))
                except Exception as exc:
                    if not is_integrity_error(exc):
                        raise
                    self.send_json(409, {"error": "Email sudah dipakai"}); return
                log_activity(db, account["email"], "Akun dibuat", email)
                self.send_json(201, {"id": account_id}); return
            if path == "/api/transactions":
                self._create_transaction(db, account, body); return
            if path == "/api/calendar/events":
                self._create_event(db, account, body); return
            if path == "/api/integrations/whatsapp":
                phone_id = str(body.get("phoneNumberId", "")).strip()
                owner_phone = normalize_phone(body.get("ownerPhone", ""))
                verify_token = str(body.get("verifyToken", "")).strip()
                if not phone_id or len(owner_phone) < 8:
                    self.send_json(400, {"error": "Phone Number ID dan nomor owner wajib diisi"}); return
                if len(verify_token) < 16 and not setting_get(db, "wa_verify_token_hash"):
                    self.send_json(400, {"error": "Verify token pertama kali minimal 16 karakter"}); return
                values = [("wa_phone_number_id", phone_id), ("wa_owner_phone", owner_phone)]
                if verify_token:
                    if len(verify_token) < 16:
                        self.send_json(400, {"error": "Verify token minimal 16 karakter"}); return
                    values.append(("wa_verify_token_hash", hashlib.sha256(verify_token.encode()).hexdigest()))
                for key, value in values:
                    upsert = ("INSERT INTO integration_settings(`key`,value) VALUES (?,?) ON DUPLICATE KEY UPDATE value=VALUES(value)"
                              if DATABASE_BACKEND == "tidb" else
                              "INSERT INTO integration_settings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
                    db.execute(upsert, (key, value))
                log_activity(db, account["email"], "Konfigurasi WhatsApp diperbarui")
                self.send_json(200, {"ok": True}); return
            self.send_json(404, {"error": "Endpoint tidak ditemukan"})

    def do_PUT(self) -> None:
        self.do_POST()

    def do_PATCH(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        try:
            body = self.read_json()
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_json(400, {"error": str(exc)}); return
        with get_db() as db:
            account = self._require(db, owner=path.startswith("/api/accounts/"))
            if not account: return
            if path.startswith("/api/accounts/"):
                pieces = path.split("/")
                account_id = pieces[3]
                target = db.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
                if not target:
                    self.send_json(404, {"error": "Akun tidak ditemukan"}); return
                name = str(body.get("name", target["name"])).strip()
                email = str(body.get("email", target["email"])).strip().lower()
                role = str(body.get("role", target["role"]))
                phone = normalize_phone(body.get("phone", target["phone"]))
                active = bool(body.get("active", target["active"]))
                if not name or "@" not in email or role not in ROLES:
                    self.send_json(400, {"error": "Nama, email, atau role tidak valid"}); return
                if phone and not 8 <= len(phone) <= 15:
                    self.send_json(400, {"error": "Nomor WhatsApp harus 8–15 digit dengan kode negara"}); return
                if target["role"] == "Owner" and (role != "Owner" or not active):
                    self.send_json(400, {"error": "Akun Owner tidak boleh didemote atau dinonaktifkan lewat endpoint ini"}); return
                try:
                    db.execute("UPDATE accounts SET name=?,email=?,role=?,phone=?,active=? WHERE id=?", (name,email,role,phone,int(active),account_id))
                except Exception as exc:
                    if not is_integrity_error(exc):
                        raise
                    self.send_json(409, {"error": "Email sudah dipakai"}); return
                if not active:
                    db.execute("DELETE FROM sessions WHERE account_id=?", (account_id,))
                log_activity(db, account["email"], "Akun diperbarui", email)
                self.send_json(200, {"ok": True}); return
            if path.startswith("/api/transactions/"):
                transaction_id = path.split("/")[3]
                item = db.execute("SELECT * FROM transactions WHERE id=?", (transaction_id,)).fetchone()
                if not item:
                    self.send_json(404, {"error": "Transaksi tidak ditemukan"}); return
                if path.endswith("/verify"):
                    status = str(body.get("status", "verified"))
                    if status not in {"verified", "rejected"}:
                        self.send_json(400, {"error": "Status harus verified atau rejected"}); return
                    db.execute("UPDATE transactions SET status=?,updated_at=? WHERE id=?", (status,utc_now(),transaction_id))
                    log_activity(db, account["email"], f"Transaksi {status}", transaction_id)
                    self.send_json(200, {"ok": True}); return
                tx_type = str(body.get("type", item["type"]))
                amount = body.get("amount", item["amount"])
                if tx_type not in {"Pemasukan", "Pengeluaran"} or not isinstance(amount, int) or amount <= 0:
                    self.send_json(400, {"error": "Jenis atau nominal transaksi tidak valid"}); return
                db.execute("UPDATE transactions SET type=?,description=?,category=?,amount=?,transaction_date=?,updated_at=? WHERE id=?",
                           (tx_type,str(body.get("description",item["description"])).strip(),str(body.get("category",item["category"])).strip(),amount,str(body.get("date",item["transaction_date"])),utc_now(),transaction_id))
                log_activity(db, account["email"], "Transaksi diperbarui", transaction_id)
                self.send_json(200, {"ok": True}); return
            if path.startswith("/api/calendar/events/"):
                event_id = path.split("/")[4] if len(path.split("/")) > 4 else path.split("/")[3]
                event = db.execute("SELECT * FROM calendar_events WHERE id=?", (event_id,)).fetchone()
                if not event:
                    self.send_json(404, {"error": "Kegiatan tidak ditemukan"}); return
                title = str(body.get("name", event["title"])).strip()
                event_date = str(body.get("date", event["event_date"]))
                amount = body.get("amount", event["amount"])
                if not title:
                    self.send_json(400, {"error": "Nama kegiatan wajib diisi"}); return
                db.execute("UPDATE calendar_events SET title=?,event_date=?,customer=?,status=?,amount=?,paid=?,info=?,updated_at=? WHERE id=?",
                           (title,event_date,str(body.get("customer",event["customer"])),str(body.get("status",event["status"])),amount,int(bool(body.get("paid",event["paid"]))),str(body.get("info",event["info"])),utc_now(),event_id))
                log_activity(db, account["email"], "Kegiatan kalender diperbarui", event_id)
                self.send_json(200, {"ok": True}); return
            self.send_json(404, {"error": "Endpoint tidak ditemukan"})

    def do_DELETE(self) -> None:
        path = urlparse(self.path).path.rstrip("/")
        with get_db() as db:
            account = self._require(db)
            if not account: return
            if path.startswith("/api/accounts/"):
                if account["role"] != "Owner":
                    self.send_json(403, {"error": "Hanya Owner yang boleh mengelola akun"}); return
                account_id = path.split("/")[3]
                target = db.execute("SELECT * FROM accounts WHERE id=?", (account_id,)).fetchone()
                if not target:
                    self.send_json(404, {"error": "Akun tidak ditemukan"}); return
                if target["role"] == "Owner":
                    self.send_json(400, {"error": "Akun Owner tidak dapat dihapus"}); return
                db.execute("UPDATE accounts SET active=0 WHERE id=?", (account_id,))
                db.execute("DELETE FROM sessions WHERE account_id=?", (account_id,))
                log_activity(db, account["email"], "Akun dinonaktifkan", target["email"])
                self.send_json(200, {"ok": True}); return
            if path.startswith("/api/transactions/"):
                transaction_id = path.split("/")[3]
                db.execute("DELETE FROM transactions WHERE id=?", (transaction_id,))
                log_activity(db, account["email"], "Transaksi dihapus", transaction_id)
                self.send_json(200, {"ok": True}); return
            if path.startswith("/api/calendar/events/"):
                event_id = path.split("/")[-1]
                db.execute("DELETE FROM calendar_events WHERE id=?", (event_id,))
                log_activity(db, account["email"], "Kegiatan kalender dihapus", event_id)
                self.send_json(200, {"ok": True}); return
            self.send_json(404, {"error": "Endpoint tidak ditemukan"})

    def _create_transaction(self, db: sqlite3.Connection, account: sqlite3.Row, body: dict[str, Any]) -> None:
        tx_type = str(body.get("type", ""))
        amount = body.get("amount")
        try:
            date.fromisoformat(str(body.get("date", "")))
        except ValueError:
            self.send_json(400, {"error": "Tanggal harus berformat YYYY-MM-DD"}); return
        description = str(body.get("description", "")).strip()
        if tx_type not in {"Pemasukan", "Pengeluaran"} or not isinstance(amount, int) or amount <= 0 or not description:
            self.send_json(400, {"error": "Jenis, keterangan, dan nominal positif wajib diisi"}); return
        item_id, now = secrets.token_urlsafe(12), utc_now()
        db.execute("""INSERT INTO transactions(id,type,description,category,amount,transaction_date,status,source,created_by,created_at,updated_at)
                      VALUES (?,?,?,?,?,?,'pending',?,?,?,?)""",
                   (item_id,tx_type,description,str(body.get("category", "")).strip() or tx_type,amount,str(body["date"]),str(body.get("source","Input aplikasi")),account["id"],now,now))
        log_activity(db, account["email"], "Transaksi ditambahkan", item_id)
        self.send_json(201, {"id": item_id, "status": "pending"})

    def _create_event(self, db: sqlite3.Connection, account: sqlite3.Row, body: dict[str, Any]) -> None:
        title = str(body.get("name", "")).strip()
        event_date = str(body.get("date", ""))
        try:
            date.fromisoformat(event_date)
        except ValueError:
            self.send_json(400, {"error": "Tanggal harus berformat YYYY-MM-DD"}); return
        if not title:
            self.send_json(400, {"error": "Nama kegiatan wajib diisi"}); return
        event_id, now = secrets.token_urlsafe(12), utc_now()
        amount = body.get("amount")
        db.execute("""INSERT INTO calendar_events(id,title,event_date,customer,status,amount,paid,info,created_by,created_at,updated_at)
                      VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
                   (event_id,title,event_date,str(body.get("customer","")),str(body.get("status","Progress")),amount,int(bool(body.get("paid",False))),str(body.get("info","")),account["id"],now,now))
        log_activity(db, account["email"], "Kegiatan kalender ditambahkan", event_id)
        self.send_json(201, {"id": event_id})

    def _whatsapp_challenge(self, query: dict[str, list[str]]) -> None:
        mode = query.get("hub.mode", [""])[0]
        token = query.get("hub.verify_token", [""])[0]
        challenge = query.get("hub.challenge", [""])[0]
        with get_db() as db:
            expected = setting_get(db, "wa_verify_token_hash")
        valid = expected and hmac.compare_digest(hashlib.sha256(token.encode()).hexdigest(), expected)
        if mode == "subscribe" and valid:
            data = challenge.encode()
            self.send_response(200); self._cors(); self.send_header("Content-Type", "text/plain"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
        else:
            self.send_json(403, {"error": "WhatsApp webhook verify token tidak cocok"})

    def _whatsapp_message(self) -> None:
        raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        app_secret = os.environ.get("WHATSAPP_APP_SECRET", "")
        signature = self.headers.get("X-Hub-Signature-256", "")
        if not app_secret or not signature.startswith("sha256="):
            self.send_json(401, {"error": "Signature WhatsApp belum dapat divalidasi"}); return
        expected_signature = "sha256=" + hmac.new(app_secret.encode(), raw, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(signature, expected_signature):
            self.send_json(401, {"error": "Signature WhatsApp tidak valid"}); return
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            self.send_json(400, {"error": "JSON webhook tidak valid"}); return
        with get_db() as db:
            owner_phone = normalize_phone(setting_get(db, "wa_owner_phone"))
            allowed_senders = {owner_phone} if owner_phone else set()
            managed_numbers = db.execute(
                "SELECT phone FROM accounts WHERE active=1 AND role IN ('Owner','Admin')"
            ).fetchall()
            allowed_senders.update(
                number for number in (normalize_phone(row["phone"]) for row in managed_numbers) if number
            )
            replies: list[tuple[str, str]] = []
            for entry in payload.get("entry", []):
                for change in entry.get("changes", []):
                    for message in change.get("value", {}).get("messages", []):
                        sender = ''.join(ch for ch in str(message.get("from", "")) if ch.isdigit())
                        body = message.get("text", {}).get("body", "")
                        msg_id = str(message.get("id", secrets.token_urlsafe(12)))
                        if not body:
                            ignore = "INSERT IGNORE" if DATABASE_BACKEND == "tidb" else "INSERT OR IGNORE"
                            db.execute(f"{ignore} INTO webhook_messages VALUES (?,?,?,'ignored',NULL,?)", (msg_id,sender,"[non-text message]",utc_now())); continue
                        if sender not in allowed_senders:
                            ignore = "INSERT IGNORE" if DATABASE_BACKEND == "tidb" else "INSERT OR IGNORE"
                            db.execute(f"{ignore} INTO webhook_messages VALUES (?,?,?,'unauthorized',NULL,?)", (msg_id,sender,body[:2000],utc_now())); continue
                        reply, transaction_id = parse_whatsapp_message(db, sender, body)
                        ignore = "INSERT IGNORE" if DATABASE_BACKEND == "tidb" else "INSERT OR IGNORE"
                        db.execute(f"{ignore} INTO webhook_messages VALUES (?,?,?,'processed',?,?)", (msg_id,sender,body[:2000],transaction_id,utc_now()))
                        if transaction_id and body.split('|', 1)[0].strip().upper() in {"MASUK", "KELUAR"}:
                            log_activity(db, sender, "Transaksi masuk dari WhatsApp", transaction_id)
                        replies.append((sender, reply))
        for recipient, message in replies:
            self._send_whatsapp_reply(recipient, message)
        self.send_json(200, {"ok": True})

    def _send_whatsapp_reply(self, recipient: str, message: str) -> None:
        token = os.environ.get("WHATSAPP_ACCESS_TOKEN", "")
        with get_db() as db:
            phone_id = setting_get(db, "wa_phone_number_id")
        if not token or not phone_id:
            return
        endpoint = f"https://graph.facebook.com/v23.0/{phone_id}/messages"
        payload = json.dumps({"messaging_product":"whatsapp","to":recipient,"type":"text","text":{"body":message}}).encode()
        request = urllib.request.Request(endpoint, data=payload, headers={"Authorization":f"Bearer {token}","Content-Type":"application/json"}, method="POST")
        try:
            urllib.request.urlopen(request, timeout=8).read()
        except (urllib.error.URLError, TimeoutError) as exc:
            print(f"WhatsApp reply failed: {exc}", file=sys.stderr)


def create_owner(email: str) -> None:
    name = input("Owner name: ").strip() or "Owner"
    import getpass
    password = getpass.getpass("Owner password (min 12 chars): ")
    if len(password) < 12:
        raise SystemExit("Password harus minimal 12 karakter")
    with get_db() as db:
        if db.execute("SELECT 1 FROM accounts WHERE role='Owner'").fetchone():
            raise SystemExit("Owner sudah dibuat")
        db.execute("INSERT INTO accounts(id,name,email,role,password_hash,active,created_at) VALUES (?,?,?,'Owner',?,1,?)",
                   (secrets.token_urlsafe(12), name, email.lower(), password_hash(password), utc_now()))
        log_activity(db, email.lower(), "Owner awal dibuat")
    print("Owner created.")


def migrate_sqlite(source: Path) -> None:
    if DATABASE_BACKEND != "tidb":
        raise SystemExit("Set DATABASE_BACKEND=tidb sebelum migrasi.")
    if not source.is_file():
        raise SystemExit(f"File SQLite tidak ditemukan: {source}")
    tables = {
        "accounts": ["id", "name", "email", "role", "phone", "password_hash", "active", "created_at", "last_active"],
        "transactions": ["id", "type", "description", "category", "amount", "transaction_date", "status", "source", "created_by", "created_at", "updated_at"],
        "calendar_events": ["id", "title", "event_date", "customer", "status", "amount", "paid", "info", "created_by", "created_at", "updated_at"],
        "activity_log": ["id", "actor", "action", "target", "created_at"],
        "integration_settings": ["key", "value"],
        "webhook_messages": ["id", "sender", "body", "status", "transaction_id", "received_at"],
    }
    with sqlite3.connect(source) as old:
        old.row_factory = sqlite3.Row
        copied = {table: [dict(row) for row in old.execute(f"SELECT * FROM {table}").fetchall()] for table in tables}
    with get_db() as target:
        for table in tables:
            if target.execute(f"SELECT COUNT(*) AS row_count FROM {table}").fetchone()["row_count"]:
                raise SystemExit(f"Tabel {table} di TiDB sudah berisi data; migrasi dibatalkan agar tidak menimpa data.")
        for table, columns in tables.items():
            quoted = ",".join(f"`{column}`" for column in columns)
            placeholders = ",".join("?" for _ in columns)
            sql = f"INSERT INTO {table} ({quoted}) VALUES ({placeholders})"
            for row in copied[table]:
                target.execute(sql, tuple(row[column] for column in columns))
        # Session tokens are deliberately not copied; each user signs in again.
    print("SQLite data migrated to TiDB. Accounts, transactions, calendar, logs, and integration settings were copied.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Dapoer PMSCU API")
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("create-owner")
    create.add_argument("--email", required=True)
    migrate = sub.add_parser("migrate-sqlite")
    migrate.add_argument("--source", type=Path, default=DB_PATH)
    sub.add_parser("check-db")
    serve = sub.add_parser("serve")
    serve.add_argument("--host", default=os.environ.get("API_HOST", "127.0.0.1"))
    serve.add_argument("--port", type=int, default=int(os.environ.get("API_PORT", "8765")))
    args = parser.parse_args()
    init_db()
    if args.command == "create-owner":
        create_owner(args.email)
    elif args.command == "migrate-sqlite":
        migrate_sqlite(args.source)
    elif args.command == "check-db":
        print(f"Database connection OK ({DATABASE_BACKEND}).")
    else:
        httpd = ThreadingHTTPServer((args.host, args.port), ApiHandler)
        print(f"Dapoer API listening at http://{args.host}:{args.port}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopping API")
        finally:
            httpd.server_close()


if __name__ == "__main__":
    main()
