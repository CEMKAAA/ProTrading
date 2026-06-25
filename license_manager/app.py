from __future__ import annotations

import csv
import json
import os
import secrets
from datetime import datetime, timezone
from functools import wraps
from pathlib import Path
from typing import Any, Dict

from flask import Flask, jsonify, redirect, render_template, request, session, url_for


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = Path(os.getenv("LICENSE_MANAGER_DATA_DIR", BASE_DIR / "data"))
DB_PATH = DATA_DIR / "licenses.json"
AUDIT_PATH = DATA_DIR / "license_audit.csv"

APP_PORT = int(os.getenv("LICENSE_MANAGER_PORT", "8765"))
ADMIN_TOKEN = os.getenv("LICENSE_ADMIN_TOKEN", "change-me-now")
SECRET_KEY = os.getenv("LICENSE_MANAGER_SECRET_KEY", secrets.token_hex(32))
AUDIT_ALLOWED_VALIDATIONS = os.getenv("LICENSE_AUDIT_ALLOWED_VALIDATIONS", "0").strip().lower() in {"1", "true", "yes", "on"}


app = Flask(__name__)
app.secret_key = SECRET_KEY


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def utc_now_iso() -> str:
    return utc_now().isoformat()


def load_db() -> Dict[str, Any]:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if not DB_PATH.exists():
        return {"licenses": {}, "updated_at": utc_now_iso()}
    try:
        data = json.loads(DB_PATH.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return {"licenses": {}, "updated_at": utc_now_iso()}
        if not isinstance(data.get("licenses"), dict):
            data["licenses"] = {}
        return data
    except Exception:
        return {"licenses": {}, "updated_at": utc_now_iso()}


def save_db(data: Dict[str, Any]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    data["updated_at"] = utc_now_iso()
    tmp = DB_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(DB_PATH)


def append_audit(event: str, license_key: str = "", detail: str = "", payload: Dict[str, Any] | None = None) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    write_header = not AUDIT_PATH.exists()
    row = {
        "time_utc": utc_now_iso(),
        "event": event,
        "license_key": license_key,
        "remote_addr": request.headers.get("x-forwarded-for", request.remote_addr or ""),
        "detail": detail,
        "payload": json.dumps(payload or {}, ensure_ascii=False, sort_keys=True)[:4000],
    }
    with AUDIT_PATH.open("a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(row.keys()))
        if write_header:
            writer.writeheader()
        writer.writerow(row)


def is_admin_request() -> bool:
    if session.get("license_admin") is True:
        return True
    supplied = (request.headers.get("x-admin-token") or request.args.get("admin_token") or "").strip()
    return bool(supplied) and secrets.compare_digest(supplied, ADMIN_TOKEN)


def require_admin(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not is_admin_request():
            if request.path.startswith("/api/"):
                return jsonify({"ok": False, "error": "unauthorized"}), 401
            return redirect(url_for("login"))
        return fn(*args, **kwargs)

    return wrapper


def split_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    return [part.strip() for part in str(value).split(",") if part.strip()]


def match_field(config_value: Any, requested: str) -> bool:
    requested = str(requested or "").strip().lower()
    values = split_list(config_value)
    if not values:
        return True
    return requested in {v.lower() for v in values}


def normalize_record(payload: Dict[str, Any], existing: Dict[str, Any] | None = None) -> Dict[str, Any]:
    rec = dict(existing or {})
    rec["active"] = bool(payload.get("active", rec.get("active", True)))
    rec["product"] = split_list(payload.get("product", rec.get("product", [])))
    rec["account"] = split_list(payload.get("account", rec.get("account", [])))
    rec["terminal"] = split_list(payload.get("terminal", rec.get("terminal", [])))
    rec["expires_at"] = str(payload.get("expires_at", rec.get("expires_at", "")) or "").strip()
    rec["customer"] = str(payload.get("customer", rec.get("customer", "")) or "").strip()
    rec["note"] = str(payload.get("note", rec.get("note", "")) or "").strip()
    rec["reason"] = str(payload.get("reason", rec.get("reason", "active")) or "active").strip()
    rec["updated_at"] = utc_now_iso()
    rec.setdefault("created_at", rec["updated_at"])
    return rec


def validate_license_record(license_key: str, args: Dict[str, Any]) -> Dict[str, Any]:
    product = str(args.get("product", "") or "").strip()
    account = str(args.get("account", "") or "").strip()
    terminal = str(args.get("terminal", "MT5") or "MT5").strip()
    symbol = str(args.get("symbol", "") or "").strip()
    timeframe = str(args.get("timeframe", "") or "").strip()
    build = str(args.get("build", "") or "").strip()
    db = load_db()
    rec = db.get("licenses", {}).get(license_key)
    now = utc_now()
    base = {
        "ok": True,
        "active": False,
        "reason": "license_not_found",
        "license_key": license_key,
        "product": product,
        "account": account,
        "terminal": terminal,
        "symbol": symbol,
        "timeframe": timeframe,
        "build": build,
        "server_time": now.isoformat(),
    }
    if not isinstance(rec, dict):
        append_audit("validate_denied", license_key, "license_not_found", base)
        return base
    if not bool(rec.get("active", False)):
        out = {**base, "reason": rec.get("reason") or "license_inactive"}
        append_audit("validate_denied", license_key, out["reason"], out)
        return out
    if not match_field(rec.get("product"), product):
        out = {**base, "reason": "product_mismatch"}
        append_audit("validate_denied", license_key, "product_mismatch", out)
        return out
    if not match_field(rec.get("account"), account):
        out = {**base, "reason": "account_mismatch"}
        append_audit("validate_denied", license_key, "account_mismatch", out)
        return out
    if not match_field(rec.get("terminal"), terminal):
        out = {**base, "reason": "terminal_mismatch"}
        append_audit("validate_denied", license_key, "terminal_mismatch", out)
        return out
    expires_at = str(rec.get("expires_at") or "").strip()
    if expires_at:
        try:
            exp = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
            if exp.tzinfo is None:
                exp = exp.replace(tzinfo=timezone.utc)
            if now >= exp:
                out = {**base, "reason": "license_expired", "expires_at": expires_at}
                append_audit("validate_denied", license_key, "license_expired", out)
                return out
        except Exception:
            out = {**base, "reason": "invalid_expiry", "expires_at": expires_at}
            append_audit("validate_denied", license_key, "invalid_expiry", out)
            return out
    out = {
        **base,
        "active": True,
        "reason": "active",
        "expires_at": expires_at,
        "customer": rec.get("customer", ""),
        "note": rec.get("note", ""),
    }
    if AUDIT_ALLOWED_VALIDATIONS:
        append_audit("validate_allowed", license_key, "active", out)
    return out


@app.get("/")
@require_admin
def index():
    return render_template("index.html", admin_token_set=ADMIN_TOKEN != "change-me-now")


@app.route("/login", methods=["GET", "POST"])
def login():
    error = ""
    if request.method == "POST":
        token = str(request.form.get("token", "")).strip()
        if token and secrets.compare_digest(token, ADMIN_TOKEN):
            session["license_admin"] = True
            return redirect(url_for("index"))
        error = "Invalid admin token"
    return render_template("login.html", error=error)


@app.post("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.get("/health")
def health():
    return jsonify({"ok": True, "service": "ea-license-manager", "time": utc_now_iso()})


@app.get("/api/license/validate")
@app.get("/api/v1/ea-license/validate")
def validate_license():
    key = str(request.args.get("license_key", "") or "").strip()
    if not key:
        return jsonify({"ok": True, "active": False, "reason": "license_key_missing", "server_time": utc_now_iso()})
    return jsonify(validate_license_record(key, request.args))


@app.get("/api/licenses")
@require_admin
def list_licenses():
    db = load_db()
    return jsonify({"ok": True, "licenses": db.get("licenses", {}), "updated_at": db.get("updated_at", "")})


@app.post("/api/licenses")
@require_admin
def upsert_license():
    payload = request.get_json(force=True, silent=True) or {}
    key = str(payload.get("license_key", "") or "").strip()
    if not key:
        return jsonify({"ok": False, "error": "license_key_required"}), 400
    db = load_db()
    existing = db.setdefault("licenses", {}).get(key, {})
    rec = normalize_record(payload, existing if isinstance(existing, dict) else {})
    db["licenses"][key] = rec
    save_db(db)
    append_audit("license_upsert", key, "saved", rec)
    return jsonify({"ok": True, "license_key": key, "record": rec})


@app.post("/api/licenses/<license_key>/activate")
@require_admin
def activate_license(license_key: str):
    db = load_db()
    rec = normalize_record({"active": True, "reason": "active"}, db.setdefault("licenses", {}).get(license_key, {}))
    db["licenses"][license_key] = rec
    save_db(db)
    append_audit("license_activate", license_key, "active", rec)
    return jsonify({"ok": True, "license_key": license_key, "record": rec})


@app.post("/api/licenses/<license_key>/deactivate")
@require_admin
def deactivate_license(license_key: str):
    payload = request.get_json(silent=True) or {}
    reason = str(payload.get("reason") or request.args.get("reason") or "deactivated_by_admin").strip()
    db = load_db()
    rec = normalize_record({"active": False, "reason": reason}, db.setdefault("licenses", {}).get(license_key, {}))
    db["licenses"][license_key] = rec
    save_db(db)
    append_audit("license_deactivate", license_key, reason, rec)
    return jsonify({"ok": True, "license_key": license_key, "record": rec})


@app.delete("/api/licenses/<license_key>")
@require_admin
def delete_license(license_key: str):
    db = load_db()
    removed = db.setdefault("licenses", {}).pop(license_key, None)
    save_db(db)
    append_audit("license_delete", license_key, "deleted", {"removed": removed})
    return jsonify({"ok": True, "license_key": license_key})


@app.get("/api/audit")
@require_admin
def audit_tail():
    limit = max(1, min(1000, int(request.args.get("limit", "250") or 250)))
    if not AUDIT_PATH.exists():
        return jsonify({"ok": True, "rows": []})
    with AUDIT_PATH.open("r", encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    return jsonify({"ok": True, "rows": rows[-limit:]})


if __name__ == "__main__":
    print(f"EA License Manager running on http://127.0.0.1:{APP_PORT}")
    if ADMIN_TOKEN == "change-me-now":
        print("WARNING: LICENSE_ADMIN_TOKEN is still the default. Change it before exposing this server.")
    app.run(host="0.0.0.0", port=APP_PORT, debug=False, use_reloader=False, threaded=True)
