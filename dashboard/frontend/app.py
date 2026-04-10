"""
ProTrading Dashboard - Flask Frontend Application
Enterprise-level trading dashboard with backtesting capabilities
"""

from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, make_response
import requests
from datetime import datetime
import os
import re
import json
import subprocess
import sys
import threading
import uuid
from pathlib import Path

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'protrading-dashboard-secret-key-2024')

# Backend API URL
API_BASE_URL = os.environ.get('API_URL', 'http://localhost:8000')

# Simple cache to avoid repeated API calls
_cache = {}
_cache_timeout = 5  # seconds

# Databento download tasks (frontend-managed background jobs)
_databento_tasks = {}
_databento_tasks_lock = threading.Lock()
_PROJECT_ROOT = Path(__file__).resolve().parents[2]
_DATABENTO_TASKS_DIR = _PROJECT_ROOT / 'dashboard' / 'data' / 'databento_tasks'
_DATABENTO_TASKS_DIR.mkdir(parents=True, exist_ok=True)


def _databento_task_file(task_id: str) -> Path:
    """Return persistent task state file path."""
    safe_id = re.sub(r'[^a-zA-Z0-9_\-]', '', str(task_id))
    return _DATABENTO_TASKS_DIR / f'{safe_id}.json'


def _save_databento_task_to_disk(task_id: str, task: dict):
    """Persist task snapshot to disk for cross-process polling resilience."""
    try:
        p = _databento_task_file(task_id)
        tmp = p.with_suffix('.json.tmp')
        tmp.write_text(json.dumps(task, ensure_ascii=True, indent=2), encoding='utf-8')
        tmp.replace(p)
    except Exception as e:
        print(f"[Databento] Failed to persist task {task_id}: {e}")


def _load_databento_task_from_disk(task_id: str):
    """Load a persisted task snapshot from disk, if present."""
    try:
        p = _databento_task_file(task_id)
        if not p.exists():
            return None
        data = json.loads(p.read_text(encoding='utf-8'))
        if isinstance(data, dict):
            return data
    except Exception as e:
        print(f"[Databento] Failed to load task {task_id}: {e}")
    return None


def _set_databento_task(task_id: str, **updates):
    """Thread-safe task state updates."""
    with _databento_tasks_lock:
        if task_id not in _databento_tasks:
            return
        _databento_tasks[task_id].update(updates)
        _save_databento_task_to_disk(task_id, _databento_tasks[task_id])


def _append_databento_log(task_id: str, line: str):
    """Append a line to task logs while keeping only a bounded tail."""
    with _databento_tasks_lock:
        task = _databento_tasks.get(task_id)
        if not task:
            return
        logs = task.setdefault('logs', [])
        logs.append(line)
        if len(logs) > 300:
            task['logs'] = logs[-300:]
        _save_databento_task_to_disk(task_id, task)


def _parse_databento_progress(line: str) -> int:
    """Best-effort progress mapping from script output lines."""
    s = (line or "").strip().lower()
    if "fetching" in s and "ohlcv" in s:
        return 15
    if "fetching earnings calendar" in s:
        return 35
    if "adding earnings schedule features" in s:
        return 55
    if "calculating deterministic iv proxy metrics" in s:
        return 72
    if "saved:" in s:
        return 90
    if s == "success":
        return 98
    return -1


def _run_databento_task(task_id: str, cmd: list, cwd: Path):
    """Run Databento fetch script as a background subprocess."""
    try:
        _set_databento_task(
            task_id,
            status='running',
            progress=5,
            message='Starting Databento fetch task...',
            started_at=datetime.now().isoformat(),
        )
        proc = subprocess.Popen(
            cmd,
            cwd=str(cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        _set_databento_task(task_id, pid=proc.pid)

        output_file = None
        ready_file = None
        for raw in iter(proc.stdout.readline, ''):
            line = raw.strip()
            if not line:
                continue
            _append_databento_log(task_id, line)

            pct = _parse_databento_progress(line)
            if pct >= 0:
                _set_databento_task(task_id, progress=pct, message=line)
            else:
                _set_databento_task(task_id, message=line)

            m_saved = re.search(r"Saved:\s*(.+)$", line)
            if m_saved:
                output_file = m_saved.group(1).strip()
            m_ready = re.search(r"Dataset ready for backtesting:\s*(.+)$", line)
            if m_ready:
                ready_file = m_ready.group(1).strip()

        rc = proc.wait()
        if rc == 0:
            out = ready_file or output_file
            _set_databento_task(
                task_id,
                status='completed',
                progress=100,
                message='Databento download completed successfully.',
                completed_at=datetime.now().isoformat(),
                result={'output_file': out},
            )
        else:
            with _databento_tasks_lock:
                logs = (_databento_tasks.get(task_id, {}).get('logs') or [])
            err_msg = "Databento fetch failed."
            # Pick the most informative line, not generic docs/traceback tails.
            for line in reversed(logs):
                s = (line or "").strip()
                if not s:
                    continue
                lower = s.lower()
                if lower.startswith("documentation:"):
                    continue
                if lower.startswith("traceback"):
                    continue
                if lower.startswith("file \"") or lower.startswith("line "):
                    continue
                if s.startswith("Error:"):
                    err_msg = s
                    break
                if "BentoClientError" in s or "422 " in s or "400 " in s:
                    err_msg = s
                    break
                if err_msg == "Databento fetch failed.":
                    err_msg = s
            _set_databento_task(
                task_id,
                status='error',
                progress=100,
                message=err_msg,
                error=err_msg,
                completed_at=datetime.now().isoformat(),
            )
    except Exception as e:
        _set_databento_task(
            task_id,
            status='error',
            progress=100,
            message=f'Databento task exception: {str(e)}',
            error=str(e),
            completed_at=datetime.now().isoformat(),
        )


def api_request(method, endpoint, data=None, params=None, use_cache=False, return_error=False, timeout_sec=None):
    """Make request to backend API"""
    url = f"{API_BASE_URL}{endpoint}"
    print(f"[API] {method} {url}")

    # Check cache for GET requests
    if use_cache and method == 'GET':
        cache_key = f"{url}:{str(params)}"
        if cache_key in _cache:
            cached_time, cached_data = _cache[cache_key]
            if (datetime.now() - cached_time).seconds < _cache_timeout:
                if return_error:
                    return cached_data, None
                return cached_data

    try:
        if method == 'GET':
            response = requests.get(url, params=params, timeout=timeout_sec or 60)
        elif method == 'POST':
            response = requests.post(url, json=data, timeout=timeout_sec or 60)
        elif method == 'DELETE':
            response = requests.delete(url, params=params, timeout=timeout_sec or 10)
        elif method == 'PUT':
            response = requests.put(url, json=data, timeout=timeout_sec or 10)
        elif method == 'PATCH':
            response = requests.patch(url, json=data, timeout=timeout_sec or 10)
        else:
            return None

        # Handle successful responses (200 OK, 201 Created)
        if response.status_code in (200, 201):
            result = response.json()
            # Cache GET results
            if use_cache and method == 'GET':
                _cache[f"{url}:{str(params)}"] = (datetime.now(), result)
            if return_error:
                return result, None
            return result
        elif response.status_code == 404:
            if return_error:
                return None, "Not found (404)"
            return None
        elif response.status_code == 422:
            # Validation error - log the details
            print(f"Validation Error: {response.text}")
            if return_error:
                return None, f"Validation error (422): {response.text[:400]}"
            return None
        else:
            print(f"API Error: {response.status_code} - {response.text}")
            if return_error:
                msg = response.text[:500]
                try:
                    js = response.json()
                    if isinstance(js, dict):
                        msg = str(js.get('detail') or js.get('message') or msg)
                except Exception:
                    pass
                return None, f"API error ({response.status_code}): {msg}"
            return None
    except requests.exceptions.ConnectionError:
        print(f"Connection error: Could not connect to {url}")
        if return_error:
            return None, f"Connection error: could not connect to backend at {API_BASE_URL}"
        return None
    except requests.exceptions.Timeout:
        print(f"Timeout error: Request to {url} timed out")
        if return_error:
            return None, f"Timeout: backend did not respond in time ({url})"
        return None
    except Exception as e:
        print(f"API request error: {e}")
        if return_error:
            return None, f"Request error: {str(e)}"
        return None


def _http_status_from_api_error(err_text, default_status=500):
    """Map api_request(return_error=True) text to HTTP status for proxy passthrough."""
    text = str(err_text or "").strip()
    if not text:
        return int(default_status)
    m = re.search(r"API error \((\d{3})\):", text)
    if m:
        try:
            return int(m.group(1))
        except Exception:
            return int(default_status)
    if "Not found (404)" in text:
        return 404
    if "Validation error (422)" in text:
        return 422
    return int(default_status)


def _to_int(v, default):
    try:
        return int(v)
    except Exception:
        return default


def _to_float(v, default):
    try:
        return float(v)
    except Exception:
        return default


@app.route('/')
def dashboard():
    """Main dashboard page"""
    # Get recent backtests
    backtests = api_request('GET', '/api/v1/backtests/results', params={'limit': 5}, use_cache=True)

    # Get dashboard stats
    stats_data = api_request('GET', '/api/v1/dashboard/stats', use_cache=True)

    # Calculate summary stats
    stats = {
        'total_backtests': 0,
        'avg_profit': 0,
        'best_profit': 0,
        'total_trades': 0
    }

    if stats_data:
        stats['total_backtests'] = stats_data.get('total_backtests', 0)
        stats['best_profit'] = stats_data.get('best_win_rate', 0)

    if backtests:
        profits = [b.get('net_profit', 0) for b in backtests]
        if profits:
            stats['avg_profit'] = sum(profits) / len(profits)
            stats['best_profit'] = max(profits)
        stats['total_trades'] = sum(b.get('total_trades', 0) for b in backtests)

    # Get live status (don't cache - need real-time data)
    live_status = api_request('GET', '/api/v1/dashboard/live-status')

    return render_template('dashboard.html',
                         backtests=backtests or [],
                         live_status=live_status,
                         stats=stats)


@app.route('/backtests')
def backtests_list():
    """List all backtests"""
    backtests = api_request('GET', '/api/v1/backtests/results', params={'limit': 50})
    return render_template('backtests.html', backtests=backtests or [])


@app.route('/backtests/<int:backtest_id>')
def backtest_detail(backtest_id):
    """View detailed backtest results"""
    backtest = api_request('GET', f'/api/v1/backtests/results/{backtest_id}')
    if not backtest:
        flash('Backtest not found', 'error')
        return redirect(url_for('backtests_list'))

    # Get trades for this backtest
    trades = api_request('GET', f'/api/v1/backtests/results/{backtest_id}/trades')
    backtest['trades'] = trades or []

    return render_template('backtest_detail.html', backtest=backtest)


@app.route('/backtests/<int:backtest_id>/delete', methods=['POST'])
def delete_backtest(backtest_id):
    """Delete a backtest"""
    result = api_request('DELETE', f'/api/v1/backtests/results/{backtest_id}')
    if result:
        flash('Backtest deleted successfully', 'success')
    else:
        flash('Failed to delete backtest', 'error')
    return redirect(url_for('backtests_list'))


@app.route('/options-edge')
def options_edge_dashboard():
    """Options-edge scanner/backtest dashboard."""
    provider_status = api_request('GET', '/api/v1/options-edge/providers/polygon/status')
    scans = api_request('GET', '/api/v1/options-edge/scans', params={'limit': 30})
    backtests = api_request('GET', '/api/v1/options-edge/backtests', params={'limit': 30})
    journal_stats = api_request('GET', '/api/v1/options-edge/journal/stats')
    return render_template(
        'options_edge.html',
        provider_status=provider_status or {},
        scans=scans or [],
        backtests=backtests or [],
        journal_stats=journal_stats or {},
    )


@app.route('/options-edge/csp')
def options_edge_csp_dashboard():
    """CSP strategy dashboard (screening + lifecycle backtest)."""
    provider_status = api_request('GET', '/api/v1/options-edge/providers/polygon/status')
    screens = api_request('GET', '/api/v1/options-edge/csp/screens', params={'limit': 30})
    backtests = api_request('GET', '/api/v1/options-edge/csp/backtests', params={'limit': 30})
    return render_template(
        'options_edge_csp.html',
        provider_status=provider_status or {},
        screens=screens or [],
        backtests=backtests or [],
    )


@app.route('/options-edge/csp/run-screen', methods=['POST'])
def options_edge_csp_run_screen():
    symbols_raw = (request.form.get('symbols') or '').strip().upper()
    symbols = [s.strip() for s in re.split(r'[\s,;]+', symbols_raw) if s.strip()]
    use_sp500 = bool(request.form.get('use_sp500'))
    if len(symbols) == 0 and not use_sp500:
        flash('Please provide at least one symbol or enable S&P500 auto-load.', 'error')
        return redirect(url_for('options_edge_csp_dashboard'))

    excluded_raw = (request.form.get('excluded_industries') or '').strip()
    excluded_industries = [s.strip() for s in re.split(r'[\n,;]+', excluded_raw) if s.strip()]

    payload = {
        'provider': 'polygon',
        'symbols': symbols,
        'use_sp500': use_sp500,
        'sp500_limit': _to_int(request.form.get('sp500_limit'), 475),
        'min_revenue_growth_pct': _to_float(request.form.get('min_revenue_growth_pct'), 10.0),
        'min_eps_growth_5y_pct': _to_float(request.form.get('min_eps_growth_5y_pct'), 10.0),
        'min_eps_growth_fwd_pct': _to_float(request.form.get('min_eps_growth_fwd_pct'), 5.0),
        'min_profit_margin_pct': _to_float(request.form.get('min_profit_margin_pct'), 15.0),
        'min_iv_rank': _to_float(request.form.get('min_iv_rank'), 0.30),
        'min_option_volume_30d': _to_float(request.form.get('min_option_volume_30d'), 5000000.0),
        'excluded_industries': excluded_industries,
        'vix_value': _to_float(request.form.get('vix_value'), 0.0) if (request.form.get('vix_value') or '').strip() else None,
        'vix_aggressive_threshold': _to_float(request.form.get('vix_aggressive_threshold'), 30.0),
        'sma200_touch_pct': _to_float(request.form.get('sma200_touch_pct'), 2.0),
        'fetch_fundamentals': bool(request.form.get('fetch_fundamentals')),
        'include_price_vs_sma200': bool(request.form.get('include_price_vs_sma200')),
    }

    res, err = api_request(
        'POST',
        '/api/v1/options-edge/csp/screen',
        data=payload,
        return_error=True,
        timeout_sec=900,
    )
    if not res or not res.get('id'):
        flash(f'CSP screening failed: {err or "unknown backend error"}', 'error')
        return redirect(url_for('options_edge_csp_dashboard'))

    flash(f'CSP screening completed: run #{res.get("id")}', 'success')
    return redirect(url_for('options_edge_csp_screen_detail', screen_id=int(res['id'])))


@app.route('/options-edge/csp/screen/<int:screen_id>')
def options_edge_csp_screen_detail(screen_id):
    screen = api_request('GET', f'/api/v1/options-edge/csp/screen/{screen_id}')
    if not screen:
        flash('CSP screen run not found.', 'error')
        return redirect(url_for('options_edge_csp_dashboard'))
    return render_template('options_edge_csp_screen_detail.html', screen=screen)


@app.route('/options-edge/csp/run-backtest', methods=['POST'])
def options_edge_csp_run_backtest():
    symbols_raw = (request.form.get('symbols') or '').strip().upper()
    symbols = [s.strip() for s in re.split(r'[\s,;]+', symbols_raw) if s.strip()]
    payload = {
        'symbol': (request.form.get('symbol') or '').strip().upper() or None,
        'symbols': symbols,
        'screen_run_id': _to_int(request.form.get('screen_run_id'), 0) or None,
        'portfolio_mode': bool(request.form.get('portfolio_mode')),
        'max_symbols': _to_int(request.form.get('max_symbols'), 10),
        'start_date': (request.form.get('start_date') or '').strip(),
        'end_date': (request.form.get('end_date') or '').strip(),
        'initial_capital': _to_float(request.form.get('initial_capital'), 100000.0),
        'max_concurrent_csps': _to_int(request.form.get('max_concurrent_csps'), 2),
        'max_portfolio_allocation_pct': _to_float(request.form.get('max_portfolio_allocation_pct'), 100.0),
        'max_sector_concentration': _to_int(request.form.get('max_sector_concentration'), 2),
        'max_single_stock_pct': _to_float(request.form.get('max_single_stock_pct'), 50.0),
        'target_dte_min': _to_int(request.form.get('target_dte_min'), 30),
        'target_dte_max': _to_int(request.form.get('target_dte_max'), 45),
        'normal_pop_min': _to_float(request.form.get('normal_pop_min'), 0.70),
        'normal_pop_max': _to_float(request.form.get('normal_pop_max'), 0.80),
        'normal_yield_min_pct': _to_float(request.form.get('normal_yield_min_pct'), 0.8),
        'normal_yield_max_pct': _to_float(request.form.get('normal_yield_max_pct'), 4.0),
        'hard_min_yield_pct': _to_float(request.form.get('hard_min_yield_pct'), 1.0),
        'aggressive_yield_min_pct': _to_float(request.form.get('aggressive_yield_min_pct'), 4.0),
        'aggressive_yield_max_pct': _to_float(request.form.get('aggressive_yield_max_pct'), 6.0),
        'vix_aggressive_threshold': _to_float(request.form.get('vix_aggressive_threshold'), 30.0),
        'sma200_touch_pct': _to_float(request.form.get('sma200_touch_pct'), 2.0),
        'iv_premium_factor': _to_float(request.form.get('iv_premium_factor'), 1.2),
        'iv_floor': _to_float(request.form.get('iv_floor'), 0.40),
        'risk_free_rate': _to_float(request.form.get('risk_free_rate'), 0.03),
    }

    if not payload['start_date'] or not payload['end_date']:
        flash('Please provide both start and end dates for CSP backtest.', 'error')
        return redirect(request.referrer or url_for('options_edge_csp_dashboard'))

    res, err = api_request(
        'POST',
        '/api/v1/options-edge/csp/backtest',
        data=payload,
        return_error=True,
        timeout_sec=240,
    )
    if not res or not res.get('id'):
        flash(f'CSP backtest failed: {err or "unknown backend error"}', 'error')
        return redirect(request.referrer or url_for('options_edge_csp_dashboard'))

    flash(f'CSP backtest completed: run #{res.get("id")}', 'success')
    return redirect(url_for('options_edge_csp_backtest_detail', run_id=int(res['id'])))


@app.route('/options-edge/csp/backtest/<int:run_id>')
def options_edge_csp_backtest_detail(run_id):
    run = api_request('GET', f'/api/v1/options-edge/csp/backtest/{run_id}')
    if not run:
        flash('CSP backtest run not found.', 'error')
        return redirect(url_for('options_edge_csp_dashboard'))
    return render_template('options_edge_csp_backtest_detail.html', run=run)


@app.route('/options-edge/csp/backtest/<int:run_id>/execution-preview')
def options_edge_csp_execution_preview(run_id):
    provider = (request.args.get('provider') or 'nautilus_ib').strip().lower()
    res, err = api_request(
        'POST',
        '/api/v1/options-edge/csp/execution/preview',
        data={'backtest_run_id': int(run_id), 'provider': provider},
        return_error=True,
        timeout_sec=90,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'preview failed'}), 502
    return jsonify(res)


@app.route('/options-edge/csp/execution-dispatch', methods=['POST'])
def options_edge_csp_execution_dispatch():
    body = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        '/api/v1/options-edge/csp/execution/dispatch',
        data=body,
        return_error=True,
        timeout_sec=90,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'dispatch failed'}), 502
    return jsonify(res)


@app.route('/options-edge/run-live-scan', methods=['POST'])
def options_edge_run_live_scan():
    symbols_raw = (request.form.get('symbols') or '').strip().upper()
    symbols = [s.strip() for s in re.split(r'[\s,;]+', symbols_raw) if s.strip()]
    use_sp500 = bool(request.form.get('use_sp500'))
    if len(symbols) == 0 and not use_sp500:
        flash('Please provide at least one symbol or enable S&P500 auto-load.', 'error')
        return redirect(url_for('options_edge_dashboard'))

    llm_provider = (request.form.get('llm_provider') or 'deterministic').strip().lower()
    llm_model_label = (request.form.get('llm_model_label') or 'gpt-oss-20b').strip()
    if llm_provider == 'deterministic':
        llm_model = 'deterministic'
    else:
        llm_model = f'{llm_provider}:{llm_model_label}'
    bounded_risk_only = bool(request.form.get('bounded_risk_only'))

    payload = {
        'provider': 'polygon',
        'symbols': symbols,
        'use_sp500': use_sp500,
        'sp500_limit': _to_int(request.form.get('sp500_limit'), 475),
        'min_dte': _to_int(request.form.get('min_dte'), 21),
        'max_dte': _to_int(request.form.get('max_dte'), 55),
        'lookback_days': _to_int(request.form.get('lookback_days'), 45),
        'default_days_to_earnings': _to_float(request.form.get('default_days_to_earnings'), 999.0),
        'include_news': bool(request.form.get('include_news')),
        'include_analyst': bool(request.form.get('include_analyst')),
        'news_limit': _to_int(request.form.get('news_limit'), 3),
        'build_strategies': True,
        'builder_config': {
            'allow_unbounded_structures': (not bounded_risk_only),
        },
        'llm_model': llm_model,
        'top_n': _to_int(request.form.get('top_n'), 8),
        'max_sector_fraction': _to_float(request.form.get('max_sector_fraction'), 0.35),
        'gate_config': {
            'min_iv_rank': _to_float(request.form.get('min_iv_rank'), 0.40),
            'min_iv_hv_spread': _to_float(request.form.get('min_iv_hv_spread'), 0.03),
            'min_option_volume_30d': _to_float(request.form.get('min_option_volume_30d'), 1000.0),
            'min_option_oi_30d': _to_float(request.form.get('min_option_oi_30d'), 2000.0),
            'max_bid_ask_pct': _to_float(request.form.get('max_bid_ask_pct'), 0.015),
            'min_days_to_earnings': _to_float(request.form.get('min_days_to_earnings'), 10.0),
            'max_borrow_rate': _to_float(request.form.get('max_borrow_rate'), 0.08),
        },
    }

    # Live options chain fetch can be slow on retail Polygon plans (multiple symbols/pages).
    res, err = api_request(
        'POST',
        '/api/v1/options-edge/scan/run-live',
        data=payload,
        return_error=True,
        timeout_sec=600,
    )
    if not res or not res.get('scan_id'):
        detail = err or 'Unknown backend error'
        flash(f'Options-edge live scan failed: {detail}', 'error')
        return redirect(url_for('options_edge_dashboard'))

    flash(f'Options-edge scan completed: {res.get("scan_id")}', 'success')
    return redirect(url_for('options_edge_scan_detail', scan_id=res['scan_id']))


@app.route('/options-edge/scan/<scan_id>')
def options_edge_scan_detail(scan_id):
    scan = api_request('GET', f'/api/v1/options-edge/scan/{scan_id}')
    if not scan:
        flash('Options-edge scan not found.', 'error')
        return redirect(url_for('options_edge_dashboard'))
    candidates = api_request('GET', f'/api/v1/options-edge/scan/{scan_id}/candidates', params={'selected_only': True})
    trades = api_request('GET', f'/api/v1/options-edge/scan/{scan_id}/trades')
    # Keep detail page responsive: load report asynchronously in browser.
    llm_provider = (request.args.get('llm_provider') or 'deterministic').strip().lower()
    if llm_provider not in {'deterministic', 'local_gptoss_http', 'anthropic_claude'}:
        llm_provider = 'deterministic'
    ai_run_id = (request.args.get('ai_run_id') or '').strip()
    ai_run = None
    if ai_run_id:
        ai_run = api_request('GET', f'/api/v1/ai-bots/runs/{ai_run_id}')
    if not ai_run:
        runs = api_request(
            'GET',
            '/api/v1/ai-bots/runs',
            params={'strategy_id': 'options_edge', 'context_id': scan_id, 'limit': 1},
        ) or []
        ai_run = runs[0] if runs else None
    return render_template(
        'options_edge_scan_detail.html',
        scan=scan,
        candidates=candidates or [],
        trades=trades or [],
        report={},
        ai_run=ai_run or {},
        llm_provider=llm_provider,
    )


@app.route('/options-edge/scan/<scan_id>/report-json')
def options_edge_scan_report_json(scan_id):
    llm_provider = (request.args.get('llm_provider') or 'deterministic').strip().lower()
    if llm_provider not in {'deterministic', 'local_gptoss_http', 'anthropic_claude'}:
        llm_provider = 'deterministic'

    if llm_provider == 'deterministic':
        timeout_sec = 20
    elif llm_provider == 'local_gptoss_http':
        timeout_sec = 450
    else:
        timeout_sec = 120
    report, err = api_request(
        'GET',
        f'/api/v1/options-edge/scan/{scan_id}/report',
        params={'llm_provider': llm_provider},
        return_error=True,
        timeout_sec=timeout_sec,
    )

    fallback_used = False
    warning_msg = None
    if not report and llm_provider != 'deterministic':
        fallback_used = True
        provider_label = 'GPT-OSS' if llm_provider == 'local_gptoss_http' else 'Claude'
        warning_msg = f"{provider_label} report timed out/unavailable: {err or 'unknown error'}. Showing deterministic report."
        llm_provider = 'deterministic'
        report, err = api_request(
            'GET',
            f'/api/v1/options-edge/scan/{scan_id}/report',
            params={'llm_provider': llm_provider},
            return_error=True,
            timeout_sec=20,
        )

    if not report:
        return jsonify({
            'ok': False,
            'llm_provider': llm_provider,
            'error': err or 'report unavailable',
            'fallback_used': fallback_used,
            'warning': warning_msg,
        }), 502

    return jsonify({
        'ok': True,
        'llm_provider': llm_provider,
        'report': report,
        'fallback_used': fallback_used,
        'warning': warning_msg,
    })


@app.route('/options-edge/scan/<scan_id>/ai-plan', methods=['POST'])
def options_edge_run_ai_plan(scan_id):
    provider = (request.form.get('provider') or 'deterministic').strip().lower()
    payload = {
        'provider': provider,
        'llm_model_label': (request.form.get('llm_model_label') or '').strip() or None,
        'llm_url': (request.form.get('llm_url') or '').strip() or None,
        'api_key': (request.form.get('api_key') or '').strip() or None,
        'account_balance': _to_float(request.form.get('account_balance'), 10000.0),
        'risk_pct': _to_float(request.form.get('risk_pct'), 1.0),
        'max_contracts_cap': _to_int(request.form.get('max_contracts_cap'), 5),
        'dry_run': bool(request.form.get('dry_run')),
    }
    res, err = api_request(
        'POST',
        f'/api/v1/ai-bots/options-edge/plan/{scan_id}',
        data=payload,
        return_error=True,
        timeout_sec=240,
    )
    if not res:
        flash(f'AI bot planning failed: {err or "unknown error"}', 'error')
        return redirect(url_for('options_edge_scan_detail', scan_id=scan_id))
    flash(f'AI bot plan generated ({res.get("provider", "deterministic")})', 'success')
    return redirect(url_for('options_edge_scan_detail', scan_id=scan_id, ai_run_id=res.get('run_id')))


@app.route('/api/options-edge/position-size', methods=['POST'])
def options_edge_position_size_proxy():
    req = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        '/api/v1/options-edge/position-size',
        data=req,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'position sizing failed'}), 400
    return jsonify(res)


@app.route('/options-edge/journal')
def options_edge_journal():
    status = (request.args.get('status') or '').strip().upper()
    params = {'limit': 500}
    if status:
        params['status'] = status
    rows = api_request('GET', '/api/v1/options-edge/journal', params=params) or []
    stats = api_request('GET', '/api/v1/options-edge/journal/stats') or {}
    return render_template('options_edge_journal.html', entries=rows, stats=stats, status=status)


@app.route('/options-edge/journal/track', methods=['POST'])
def options_edge_journal_track():
    scan_id = (request.form.get('scan_id') or '').strip()
    trade_candidate_id = _to_int(request.form.get('trade_candidate_id'), 0)
    if not scan_id or trade_candidate_id <= 0:
        flash('Missing scan_id or trade_candidate_id for journal tracking.', 'error')
        return redirect(request.referrer or url_for('options_edge_dashboard'))

    payload = {
        'scan_id': scan_id,
        'trade_candidate_id': trade_candidate_id,
        'contracts': _to_int(request.form.get('contracts'), 1),
        'account_balance_at_entry': _to_float(request.form.get('account_balance_at_entry'), 0.0) or None,
        'risk_pct_at_entry': _to_float(request.form.get('risk_pct_at_entry'), 0.0) or None,
        'notes': (request.form.get('notes') or '').strip() or None,
    }
    res, err = api_request('POST', '/api/v1/options-edge/journal/track', data=payload, return_error=True, timeout_sec=30)
    if not res:
        flash(f'Failed to track trade: {err or "unknown error"}', 'error')
    else:
        flash(f"Trade tracked in journal: {res.get('journal_id')}", 'success')
    return redirect(request.referrer or url_for('options_edge_journal'))


@app.route('/options-edge/journal/<journal_id>/close', methods=['POST'])
def options_edge_journal_close(journal_id):
    payload = {
        'exit_credit': _to_float(request.form.get('exit_credit'), 0.0) if (request.form.get('exit_credit') or '').strip() else None,
        'actual_pnl': _to_float(request.form.get('actual_pnl'), 0.0),
        'exit_reason': (request.form.get('exit_reason') or 'manual').strip(),
        'notes': (request.form.get('notes') or '').strip() or None,
    }
    res, err = api_request(
        'POST',
        f'/api/v1/options-edge/journal/{journal_id}/close',
        data=payload,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        flash(f'Failed to close journal trade: {err or "unknown error"}', 'error')
    else:
        flash(f"Journal trade closed: {journal_id}", 'success')
    return redirect(request.referrer or url_for('options_edge_journal'))


@app.route('/options-edge/journal/<journal_id>/delete', methods=['POST'])
def options_edge_journal_delete(journal_id):
    res, err = api_request(
        'DELETE',
        f'/api/v1/options-edge/journal/{journal_id}',
        return_error=True,
        timeout_sec=15,
    )
    if not res:
        flash(f'Failed to delete journal entry: {err or "unknown error"}', 'error')
    else:
        flash(f"Journal entry deleted: {journal_id}", 'success')
    return redirect(request.referrer or url_for('options_edge_journal'))


@app.route('/options-edge/run-backtest', methods=['POST'])
def options_edge_run_backtest():
    scan_ids = [s.strip() for s in request.form.getlist('scan_ids') if s.strip()]
    payload = {
        'scan_ids': scan_ids if len(scan_ids) > 0 else None,
        'initial_balance': _to_float(request.form.get('initial_balance'), 10000.0),
        'allocation_per_trade_usd': _to_float(request.form.get('allocation_per_trade_usd'), 1000.0),
        'max_contracts_per_trade': _to_int(request.form.get('max_contracts_per_trade'), 3),
        'max_trades_per_scan': _to_int(request.form.get('max_trades_per_scan'), 8),
        'min_selected_symbols': _to_int(request.form.get('min_selected_symbols'), 1),
        'min_pop': _to_float(request.form.get('min_pop'), 0.0),
        'take_profit_frac': _to_float(request.form.get('take_profit_frac'), 0.50),
        'stop_loss_credit_mult': _to_float(request.form.get('stop_loss_credit_mult'), 1.75),
        'commission_per_leg': _to_float(request.form.get('commission_per_leg'), 0.65),
        'slippage_pct': _to_float(request.form.get('slippage_pct'), 0.01),
        'spread_pct': _to_float(request.form.get('spread_pct'), 0.005),
        'min_fill_ratio': _to_float(request.form.get('min_fill_ratio'), 0.70),
        'max_fill_ratio': _to_float(request.form.get('max_fill_ratio'), 1.00),
        'walk_forward_folds': _to_int(request.form.get('walk_forward_folds'), 4),
        'stress_slippage_mult': _to_float(request.form.get('stress_slippage_mult'), 1.25),
        'stress_spread_mult': _to_float(request.form.get('stress_spread_mult'), 1.50),
        'stress_pop_penalty': _to_float(request.form.get('stress_pop_penalty'), 0.05),
        'stress_fill_probability': _to_float(request.form.get('stress_fill_probability'), 0.90),
        'random_seed': _to_int(request.form.get('random_seed'), 42),
    }

    res = api_request('POST', '/api/v1/options-edge/backtest/run', data=payload)
    if not res or not res.get('run_id'):
        flash('Options-edge backtest failed. Check backend logs for details.', 'error')
        return redirect(url_for('options_edge_dashboard'))

    flash(f'Options-edge backtest completed: {res.get("run_id")}', 'success')
    return redirect(url_for('options_edge_backtest_detail', run_id=res['run_id']))


@app.route('/options-edge/backtest/<run_id>')
def options_edge_backtest_detail(run_id):
    run = api_request('GET', f'/api/v1/options-edge/backtest/{run_id}')
    if not run:
        flash('Options-edge backtest run not found.', 'error')
        return redirect(url_for('options_edge_dashboard'))
    return render_template('options_edge_backtest_detail.html', run=run)


@app.route('/configurations')
def configurations():
    """Strategy preset matrix — all strategies x presets x instruments"""
    matrix = api_request('GET', '/api/v1/preset-matrix')
    return render_template('configurations.html', matrix=matrix or [])


@app.route('/configurations/new', methods=['GET', 'POST'])
def new_configuration():
    """Create new backtest configuration"""
    if request.method == 'POST':
        try:
            config = build_config_from_form(request.form)
            result = api_request('POST', '/api/v1/configs', data=config)
            if result:
                flash('Configuration saved successfully', 'success')
                return redirect(url_for('configurations'))
            else:
                flash('Failed to save configuration', 'error')
        except Exception as e:
            flash(f'Error: {str(e)}', 'error')

    # Get default preset
    default_config = api_request('GET', '/api/v1/presets/default-config', use_cache=True)
    return render_template('new_configuration.html', default_config=default_config or {})


@app.route('/configurations/<int:config_id>')
def view_configuration(config_id):
    """View configuration details"""
    config = api_request('GET', f'/api/v1/configs/{config_id}')
    if not config:
        flash('Configuration not found', 'error')
        return redirect(url_for('configurations'))
    return render_template('view_configuration.html', config=config)


@app.route('/configurations/<int:config_id>/delete', methods=['POST'])
def delete_configuration(config_id):
    """Delete a configuration"""
    result = api_request('DELETE', f'/api/v1/configs/{config_id}')
    if result:
        flash('Configuration deleted successfully', 'success')
    else:
        flash('Failed to delete configuration', 'error')
    return redirect(url_for('configurations'))


@app.route('/run-backtest', methods=['GET', 'POST'])
def run_backtest():
    """Run a new backtest"""
    if request.method == 'POST':
        try:
            config = build_config_from_form(request.form)
            loaded_config_id = request.form.get('loaded_config_id', '').strip()

            if loaded_config_id:
                # Reuse existing config selected by user - update full payload
                update_data = dict(config)
                saved_config = api_request('PUT', f'/api/v1/configs/{loaded_config_id}', data=update_data)
            else:
                # Create new config
                saved_config = api_request('POST', '/api/v1/configs', data=config)

            if saved_config:
                # Always use the legacy BacktestEngine for reproducibility.
                # The advanced event-driven engine is kept in codebase but not
                # exposed in the UI to avoid divergence between batch and UI.
                result = api_request('POST', f'/api/v1/backtests/run/{saved_config["id"]}')
                if result:
                    flash('Backtest started! Check the results page.', 'success')
                    return redirect(url_for('backtests_list'))
                else:
                    flash('Failed to start backtest', 'error')
            else:
                flash('Failed to save configuration. Check that the backend API is running.', 'error')
        except Exception as e:
            import traceback
            print(f"[ERROR] Exception in run_backtest: {traceback.format_exc()}")
            flash(f'Error running backtest: {str(e)}', 'error')

    # Get saved configs and default preset
    configs = api_request('GET', '/api/v1/configs', use_cache=True)
    default_config = api_request('GET', '/api/v1/presets/default-config', use_cache=True)

    return render_template('run_backtest.html',
                         configs=configs or [],
                         default_config=default_config or {})


@app.route('/live-trading')
def live_trading():
    """Live trading monitor"""
    status = api_request('GET', '/api/v1/dashboard/live-status')
    return render_template('live_trading.html', status=status)


@app.route('/trading-systems')
def trading_systems():
    """Trading systems management page"""
    strategies = api_request('GET', '/api/v1/strategies')
    return render_template('trading_systems.html', strategies=strategies or [])


@app.route('/simulations')
def simulations_dashboard():
    """Simulation hub page."""
    strategies = api_request('GET', '/api/v1/strategies')
    return render_template('simulations.html', strategies=strategies or [])


@app.route('/simulation/<strategy_id>')
def simulation(strategy_id):
    """Interactive trading simulation dashboard"""
    # Fetch strategy info from backend
    strategy = api_request('GET', f'/api/v1/strategies/{strategy_id}', use_cache=True)
    # Fetch available data files
    data_files = api_request('GET', '/api/v1/simulation/data-files', use_cache=True)
    # Fetch step definitions
    steps = api_request('GET', f'/api/v1/simulation/strategies/{strategy_id}/steps', use_cache=True)
    return render_template(
        'simulation.html',
        strategy_id=strategy_id,
        strategy=strategy or {},
        data_files=data_files or [],
        steps=steps or {},
    )


@app.route('/workbench')
def trader_workbench():
    """Strategy-free chart analysis workbench"""
    data_files = api_request('GET', '/api/v1/simulation/data-files', use_cache=True)
    return render_template('workbench.html', data_files=data_files or [])


@app.route('/telegram-automation')
def telegram_automation():
    """Telegram signal automation control panel."""
    return render_template('telegram_automation.html')


@app.route('/mt4-log-automation')
def mt4_log_automation():
    """MT4 log-based indicator automation control panel."""
    return render_template('mt4_log_automation.html')


# Guided trading simulation workspace (control-plane UX)
@app.route('/trading-simulation/<strategy_id>')
def trading_simulation_workspace(strategy_id):
    strategy = api_request('GET', f'/api/v1/strategies/{strategy_id}', use_cache=True)
    guide = api_request('GET', f'/api/v1/trading-simulation/strategies/{strategy_id}/guide', use_cache=True)
    playbook = api_request('GET', f'/api/v1/trading-simulation/strategies/{strategy_id}/playbook', use_cache=True)
    return render_template(
        'trading_simulation_workspace.html',
        strategy_id=strategy_id,
        strategy=strategy or {},
        guide=guide or {},
        playbook=playbook or {},
    )


# Simulation API proxy routes
@app.route('/api/simulation/sessions', methods=['GET', 'POST'])
def sim_sessions():
    if request.method == 'GET':
        params = {}
        if request.args.get('strategy_id') is not None:
            params['strategy_id'] = request.args.get('strategy_id')
        if request.args.get('status') is not None:
            params['status'] = request.args.get('status')
        if request.args.get('limit') is not None:
            params['limit'] = request.args.get('limit')
        if request.args.get('include_automation_children') is not None:
            params['include_automation_children'] = request.args.get('include_automation_children')
        res, err = api_request('GET', '/api/v1/simulation/sessions', params=params, return_error=True, timeout_sec=30)
        if not res:
            return jsonify({'error': err or 'Failed to load sessions'}), 500
        return jsonify(res)

    data = request.get_json(silent=True) or {}
    res, err = api_request('POST', '/api/v1/simulation/sessions', data=data, return_error=True, timeout_sec=30)
    if not res:
        return jsonify({'error': err or 'Failed to create session'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>')
def sim_get_session(session_id):
    res = api_request('GET', f'/api/v1/simulation/sessions/{session_id}')
    return jsonify(res or {})


@app.route('/api/simulation/sessions/<int:session_id>/open-positions')
def sim_get_open_positions(session_id):
    params = {}
    if request.args.get('limit') is not None:
        params['limit'] = request.args.get('limit')
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/open-positions',
        params=params,
        return_error=True,
        timeout_sec=15,
    )
    if not res:
        return jsonify({'ok': False, 'open_positions': [], 'open_count': 0, 'error': err or 'Open positions unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/advance', methods=['POST'])
def sim_advance(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request('POST', f'/api/v1/simulation/sessions/{session_id}/advance', data=data, return_error=True, timeout_sec=30)
    if not res:
        return jsonify({'error': err or 'Advance failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/trade', methods=['POST'])
def sim_trade(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request('POST', f'/api/v1/simulation/sessions/{session_id}/trade', data=data, return_error=True, timeout_sec=15)
    if not res:
        return jsonify({'error': err or 'Trade failed'}), _http_status_from_api_error(err, 500)
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/close-trade/<int:trade_id>', methods=['POST'])
def sim_close_trade(session_id, trade_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/close-trade/{trade_id}',
        data=data,
        return_error=True,
    )
    if not res:
        return jsonify({'error': err or 'Close failed'}), _http_status_from_api_error(err, 500)
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/close-broker-position', methods=['POST'])
def sim_close_broker_position(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/close-broker-position',
        data=data,
        return_error=True,
        timeout_sec=15,
    )
    if not res:
        return jsonify({'error': err or 'Broker close failed'}), _http_status_from_api_error(err, 500)
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/cost-model', methods=['POST'])
def sim_update_cost_model(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/cost-model',
        data=data,
        return_error=True,
        timeout_sec=15,
    )
    if not res:
        return jsonify({'error': err or 'Cost model update failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/live-control', methods=['POST'])
def sim_update_live_control(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/live-control',
        data=data,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'error': err or 'Live control update failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/context', methods=['POST'])
def sim_update_session_context(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/context',
        data=data,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'error': err or 'Session context update failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/seek', methods=['POST'])
def sim_seek(session_id):
    bar = request.args.get('bar', 0)
    include_bars = request.args.get('include_bars', '0')
    bars_limit = request.args.get('bars_limit', '1500')
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/seek?bar={bar}&include_bars={include_bars}&bars_limit={bars_limit}',
        return_error=True
    )
    if not res:
        return jsonify({'error': err or 'Seek failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/reset', methods=['POST'])
def sim_reset(session_id):
    res, err = api_request('POST', f'/api/v1/simulation/sessions/{session_id}/reset', return_error=True)
    if not res:
        return jsonify({'error': err or 'Reset failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/performance')
def sim_performance(session_id):
    res = api_request('GET', f'/api/v1/simulation/sessions/{session_id}/performance')
    return jsonify(res or {})


@app.route('/api/simulation/sessions/<int:session_id>', methods=['DELETE'])
def sim_delete_session(session_id):
    res, err = api_request('DELETE', f'/api/v1/simulation/sessions/{session_id}', return_error=True)
    if not res:
        return jsonify({'error': err or 'Delete failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/strategies')
def sim_strategies():
    res = api_request('GET', '/api/v1/simulation/strategies')
    return jsonify(res or [])


@app.route('/api/simulation/strategies/<strategy_id>/steps')
def sim_strategy_steps(strategy_id):
    res = api_request('GET', f'/api/v1/simulation/strategies/{strategy_id}/steps')
    return jsonify(res or {})


@app.route('/api/simulation/data-files')
def sim_data_files():
    params = {}
    if request.args.get('symbol'):
        params['symbol'] = request.args['symbol']
    if request.args.get('timeframe'):
        params['timeframe'] = request.args['timeframe']
    res = api_request('GET', '/api/v1/simulation/data-files', params=params)
    return jsonify(res or [])


@app.route('/api/simulation/mt5/status')
def sim_mt5_status():
    params = {}
    if request.args.get('symbol'):
        params['symbol'] = request.args['symbol']
    if request.args.get('timeframe'):
        params['timeframe'] = request.args['timeframe']
    res, err = api_request('GET', '/api/v1/simulation/mt5/status', params=params, return_error=True, timeout_sec=15)
    if not res:
        return jsonify({'ok': False, 'mt5_connected': False, 'error': err or 'MT5 status unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/mt5/symbols')
def sim_mt5_symbols():
    params = {}
    if request.args.get('search') is not None:
        params['search'] = request.args.get('search', '')
    if request.args.get('limit'):
        params['limit'] = request.args.get('limit')
    if request.args.get('include_hidden') is not None:
        params['include_hidden'] = request.args.get('include_hidden')
    res, err = api_request(
        'GET',
        '/api/v1/simulation/mt5/symbols',
        params=params,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'count': 0, 'symbols': [], 'error': err or 'MT5 symbols unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/databento/status', methods=['GET', 'POST'])
def sim_databento_status():
    if request.method == 'POST':
        payload = request.get_json(silent=True) or {}
        res, err = api_request(
            'POST',
            '/api/v1/simulation/databento/status',
            data=payload,
            return_error=True,
            timeout_sec=20,
        )
    else:
        params = {}
        for key in ('symbol', 'timeframe', 'dataset', 'stype_in', 'db_symbol'):
            val = request.args.get(key)
            if val:
                params[key] = val
        res, err = api_request(
            'GET',
            '/api/v1/simulation/databento/status',
            params=params,
            return_error=True,
            timeout_sec=20,
        )
    if not res:
        return jsonify({'ok': False, 'databento_connected': False, 'error': err or 'Databento status unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/live/history', methods=['POST'])
def sim_live_history():
    payload = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        '/api/v1/simulation/live/history',
        data=payload,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'bars': [], 'count': 0, 'error': err or 'Live history unavailable'}), 500
    return jsonify(res)


# Workbench tool proxy routes
@app.route('/api/simulation/workbench/tools')
def sim_workbench_tools():
    res = api_request('GET', '/api/v1/simulation/workbench/tools')
    return jsonify(res or [])


@app.route('/api/telegram/automation/state')
def telegram_automation_state_proxy():
    params = {}
    if request.args.get('limit') is not None:
        params['limit'] = request.args.get('limit')
    res, err = api_request(
        'GET',
        '/api/v1/telegram/automation/state',
        params=params,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to load telegram automation state'}), 500
    return jsonify(res)


@app.route('/api/telegram/automation/config', methods=['POST'])
def telegram_automation_config_proxy():
    payload = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        '/api/v1/telegram/automation/config',
        data=payload,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to update telegram automation config'}), 500
    return jsonify(res)


@app.route('/api/telegram/user-listener/state')
def telegram_user_listener_state_proxy():
    res, err = api_request(
        'GET',
        '/api/v1/telegram/user-listener/state',
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to load telegram user listener state'}), 500
    return jsonify(res)


@app.route('/api/telegram/user-listener/config', methods=['POST'])
def telegram_user_listener_config_proxy():
    payload = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        '/api/v1/telegram/user-listener/config',
        data=payload,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to update telegram user listener config'}), 500
    return jsonify(res)


@app.route('/api/telegram/user-listener/start', methods=['POST'])
def telegram_user_listener_start_proxy():
    res, err = api_request(
        'POST',
        '/api/v1/telegram/user-listener/start',
        data={},
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to start telegram user listener'}), 500
    return jsonify(res)


@app.route('/api/telegram/user-listener/stop', methods=['POST'])
def telegram_user_listener_stop_proxy():
    res, err = api_request(
        'POST',
        '/api/v1/telegram/user-listener/stop',
        data={},
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to stop telegram user listener'}), 500
    return jsonify(res)


@app.route('/api/telegram/user-listener/send-code', methods=['POST'])
def telegram_user_listener_send_code_proxy():
    payload = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        '/api/v1/telegram/user-listener/send-code',
        data=payload,
        return_error=True,
        timeout_sec=40,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to send telegram login code'}), 500
    return jsonify(res)


@app.route('/api/telegram/user-listener/verify-code', methods=['POST'])
def telegram_user_listener_verify_code_proxy():
    payload = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        '/api/v1/telegram/user-listener/verify-code',
        data=payload,
        return_error=True,
        timeout_sec=40,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to verify telegram login code'}), 500
    return jsonify(res)


@app.route('/api/mt4/log-automation/state')
def mt4_log_automation_state_proxy():
    params = {}
    if request.args.get('limit') is not None:
        params['limit'] = request.args.get('limit')
    res, err = api_request(
        'GET',
        '/api/v1/mt4/log-automation/state',
        params=params,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to load MT4 log automation state'}), 500
    return jsonify(res)


@app.route('/api/mt4/log-automation/config', methods=['POST'])
def mt4_log_automation_config_proxy():
    payload = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        '/api/v1/mt4/log-automation/config',
        data=payload,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to update MT4 log automation config'}), 500
    return jsonify(res)


@app.route('/api/mt4/log-automation/indicator-automation', methods=['POST'])
def mt4_log_indicator_automation_proxy():
    payload = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        '/api/v1/mt4/log-automation/indicator-automation',
        data=payload,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to update indicator automation state'}), 500
    return jsonify(res)


@app.route('/api/mt4/log-automation/indicator-logs')
def mt4_log_indicator_logs_proxy():
    params = {}
    if request.args.get('indicator') is not None:
        params['indicator'] = request.args.get('indicator')
    if request.args.get('limit') is not None:
        params['limit'] = request.args.get('limit')
    if request.args.get('alerts_only') is not None:
        params['alerts_only'] = request.args.get('alerts_only')
    res, err = api_request(
        'GET',
        '/api/v1/mt4/log-automation/indicator-logs',
        params=params,
        return_error=True,
        timeout_sec=20,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to load indicator logs'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/tools/<tool_id>/scan', methods=['POST'])
def sim_tool_scan(session_id, tool_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/tools/{tool_id}/scan',
        data=data,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'error': err or 'Tool scan failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/tools/research/optimize', methods=['POST'])
def sim_research_optimize(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/tools/research/optimize',
        data=data,
        return_error=True,
        timeout_sec=120,
    )
    if not res:
        return jsonify({'error': err or 'Research optimization failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/tools/research/ml-diagnostic', methods=['POST'])
def sim_research_ml_diagnostic(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/tools/research/ml-diagnostic',
        data=data,
        return_error=True,
        timeout_sec=120,
    )
    if not res:
        return jsonify({'error': err or 'ML diagnostic failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/tools/strategy/backtest-overlay', methods=['POST'])
def sim_strategy_backtest_overlay(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/tools/strategy/backtest-overlay',
        data=data,
        return_error=True,
        timeout_sec=180,
    )
    if not res:
        status = _http_status_from_api_error(err, default_status=500)
        return jsonify({'error': err or 'Strategy backtest overlay failed'}), status
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/tools/strategy/trigger-map', methods=['POST'])
def sim_strategy_trigger_map(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/tools/strategy/trigger-map',
        data=data,
        return_error=True,
        timeout_sec=60,
    )
    if not res:
        status = _http_status_from_api_error(err, default_status=500)
        return jsonify({'error': err or 'Strategy trigger map failed'}), status
    return jsonify(res)


def _legacy_copilot_start_to_agent_payload(data):
    src = data if isinstance(data, dict) else {}
    mode = str(src.get('mode') or 'ADVISE').strip().upper()
    cfg = src.get('config') if isinstance(src.get('config'), dict) else {}
    runtime = src.get('runtime') if isinstance(src.get('runtime'), dict) else {}
    provider = str(src.get('provider') or 'deterministic').strip().lower()
    model_label = str(src.get('model_label') or '').strip() or None
    timeout_sec_raw = runtime.get('llm_timeout_sec')
    if timeout_sec_raw is None:
        timeout_sec_raw = cfg.get('llm_timeout_sec')
    try:
        timeout_sec = int(timeout_sec_raw if timeout_sec_raw is not None else 45)
    except Exception:
        timeout_sec = 45
    timeout_sec = max(10, min(600, timeout_sec))

    auto_exec = mode == 'AUTO_PAPER'
    perms = {
        'can_chat': True,
        'can_scan_tools': True,
        'can_use_research': False,
        'can_manage_indicators': True,
        'can_place_trades': bool(auto_exec),
        'can_close_trades': bool(auto_exec),
        'can_auto_execute': bool(auto_exec),
        'requires_user_confirm_for_trade': not bool(auto_exec),
    }
    cfg_perms = cfg.get('agent_permissions') if isinstance(cfg.get('agent_permissions'), dict) else {}
    if cfg_perms:
        perms.update({
            'can_chat': bool(cfg_perms.get('can_chat', perms['can_chat'])),
            'can_scan_tools': bool(cfg_perms.get('can_scan_tools', perms['can_scan_tools'])),
            'can_use_research': bool(cfg_perms.get('can_use_research', perms['can_use_research'])),
            'can_manage_indicators': bool(cfg_perms.get('can_manage_indicators', perms['can_manage_indicators'])),
            'can_place_trades': bool(cfg_perms.get('can_place_trades', perms['can_place_trades'])),
            'can_close_trades': bool(cfg_perms.get('can_close_trades', perms['can_close_trades'])),
            'can_auto_execute': bool(cfg_perms.get('can_auto_execute', perms['can_auto_execute'])),
            'requires_user_confirm_for_trade': bool(cfg_perms.get('requires_user_confirm_for_trade', perms['requires_user_confirm_for_trade'])),
        })

    loop_interval_raw = cfg.get('agent_loop_interval_sec')
    try:
        loop_interval_sec = float(loop_interval_raw if loop_interval_raw is not None else 5.0)
    except Exception:
        loop_interval_sec = 5.0
    loop_interval_sec = max(0.5, min(120.0, loop_interval_sec))

    return {
        'provider': {
            'provider': provider,
            'model_label': model_label,
            'llm_url': runtime.get('llm_url'),
            'api_key': runtime.get('api_key'),
            'timeout_sec': timeout_sec,
        },
        'permissions': perms,
        'loop_interval_sec': loop_interval_sec,
        'mode': 'LOOP',
        'config': cfg,
        'runtime': runtime,
    }


def _legacy_copilot_action_to_agent_payload(data):
    src = data if isinstance(data, dict) else {}
    raw_type = str(src.get('action_type') or '').strip().upper()
    mapped_action = 'REVIEW_NOTE'
    mapped_status = 'APPROVED'
    if raw_type in {'REJECT', 'REJECTED'}:
        mapped_status = 'REJECTED'
    elif 'ENTRY' in raw_type:
        mapped_action = 'EXECUTE_TRADE_ENTRY'
        mapped_status = 'EXECUTED'
    elif 'EXIT' in raw_type or 'CLOSE' in raw_type:
        mapped_action = 'EXECUTE_TRADE_EXIT'
        mapped_status = 'EXECUTED'
    elif 'SCAN' in raw_type:
        mapped_action = 'SCAN_TOOL'
        mapped_status = 'EXECUTED'
    elif 'INDICATOR' in raw_type:
        mapped_action = 'SET_INDICATOR_VISIBILITY'
        mapped_status = 'EXECUTED'
    elif 'RESEARCH' in raw_type:
        mapped_action = 'RUN_RESEARCH_OPTIMIZER'
        mapped_status = 'EXECUTED'
    elif raw_type in {'ACCEPT', 'ACCEPTED', 'ACK', 'ACKNOWLEDGE', 'ACKNOWLEDGED'}:
        mapped_status = 'APPROVED'

    payload = src.get('payload') if isinstance(src.get('payload'), dict) else {}
    merged_payload = dict(payload)
    if raw_type:
        merged_payload['source_action_type'] = raw_type

    return {
        'action_id': src.get('advice_id'),
        'requested_by': 'USER',
        'action_type': mapped_action,
        'status': mapped_status,
        'reason': src.get('note'),
        'payload': merged_payload,
    }


@app.route('/api/simulation/sessions/<int:session_id>/copilot/start', methods=['POST'])
def sim_copilot_start(session_id):
    data = request.get_json(silent=True) or {}
    mapped = _legacy_copilot_start_to_agent_payload(data)
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/start',
        data=mapped,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'error': err or 'Failed to start copilot (legacy wrapper)'}), 500
    out = dict(res) if isinstance(res, dict) else {'result': res}
    out['deprecated'] = True
    out['deprecated_route'] = 'copilot/start'
    return jsonify(out)


@app.route('/api/simulation/sessions/<int:session_id>/copilot/stop', methods=['POST'])
def sim_copilot_stop(session_id):
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/stop',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'error': err or 'Failed to stop copilot (legacy wrapper)'}), 500
    out = dict(res) if isinstance(res, dict) else {'result': res}
    out['deprecated'] = True
    out['deprecated_route'] = 'copilot/stop'
    return jsonify(out)


@app.route('/api/simulation/sessions/<int:session_id>/copilot/pause-auto', methods=['POST'])
def sim_copilot_pause_auto(session_id):
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/pause',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'error': err or 'Failed to pause auto-pilot (legacy wrapper)'}), 500
    out = dict(res) if isinstance(res, dict) else {'result': res}
    out['deprecated'] = True
    out['deprecated_route'] = 'copilot/pause-auto'
    return jsonify(out)


@app.route('/api/simulation/sessions/<int:session_id>/copilot/resume-auto', methods=['POST'])
def sim_copilot_resume_auto(session_id):
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/resume',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'error': err or 'Failed to resume auto-pilot (legacy wrapper)'}), 500
    out = dict(res) if isinstance(res, dict) else {'result': res}
    out['deprecated'] = True
    out['deprecated_route'] = 'copilot/resume-auto'
    return jsonify(out)


@app.route('/api/simulation/sessions/<int:session_id>/copilot/state')
def sim_copilot_state(session_id):
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/agent/state',
        params={'include_legacy_aliases': 'true'},
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'error': err or 'Copilot state unavailable (legacy wrapper)'}), 500
    if isinstance(res, dict):
        legacy = res.get('copilot_state')
        if isinstance(legacy, dict):
            return jsonify(legacy)
        state = res.get('state')
        if isinstance(state, dict):
            return jsonify(state)
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/copilot/action', methods=['POST'])
def sim_copilot_action(session_id):
    data = request.get_json(silent=True) or {}
    mapped = _legacy_copilot_action_to_agent_payload(data)
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/action',
        data=mapped,
        return_error=True,
        timeout_sec=60,
    )
    if not res:
        return jsonify({'error': err or 'Copilot action failed (legacy wrapper)'}), 500
    out = dict(res) if isinstance(res, dict) else {'result': res}
    out['deprecated'] = True
    out['deprecated_route'] = 'copilot/action'
    return jsonify(out)


@app.route('/api/simulation/sessions/<int:session_id>/copilot/tool-state', methods=['POST'])
def sim_copilot_tool_state(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/tool-state',
        data=data,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'error': err or 'Copilot tool-state push failed (legacy wrapper)'}), 500
    out = dict(res) if isinstance(res, dict) else {'result': res}
    out['deprecated'] = True
    out['deprecated_route'] = 'copilot/tool-state'
    return jsonify(out)


@app.route('/api/simulation/sessions/<int:session_id>/coach/evaluate', methods=['POST'])
def sim_coach_evaluate(session_id):
    data = request.get_json(silent=True) or {}
    try:
        timeout_sec = int(data.get('timeout_sec') or 45)
    except Exception:
        timeout_sec = 45
    timeout_sec = max(10, min(600, timeout_sec))
    mapped = {
        'provider': {
            'provider': str(data.get('provider') or 'deterministic'),
            'model_label': data.get('model_label'),
            'llm_url': data.get('llm_url'),
            'api_key': data.get('api_key'),
            'timeout_sec': timeout_sec,
        },
        'permissions': {
            'can_chat': True,
            'can_scan_tools': True,
            'can_use_research': False,
            'can_manage_indicators': True,
            'can_place_trades': False,
            'can_close_trades': False,
            'can_auto_execute': False,
            'requires_user_confirm_for_trade': True,
        },
        'context_snapshot': {
            'tool_state': data.get('tool_state') if isinstance(data.get('tool_state'), dict) else {},
            'metadata': {
                'legacy_route': 'coach/evaluate',
                'notes': data.get('notes'),
            },
        },
        'objective': str(data.get('notes') or '').strip() or 'Review current context and propose the next best action.',
        'allow_tools': True,
        'max_tool_steps': 4,
    }
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/run-once',
        data=mapped,
        return_error=True,
        timeout_sec=180,
    )
    if not res:
        return jsonify({'error': err or 'Coach evaluation failed'}), 500
    out = dict(res) if isinstance(res, dict) else {'result': res}
    out['deprecated'] = True
    out['deprecated_route'] = 'coach/evaluate'
    out['replacement'] = '/api/simulation/sessions/<id>/agent/run-once'
    return jsonify(out)


@app.route('/api/simulation/sessions/<int:session_id>/consultant/chat', methods=['POST'])
def sim_consultant_chat(session_id):
    data = request.get_json(silent=True) or {}
    try:
        timeout_sec = int(data.get('timeout_sec') or 180)
    except Exception:
        timeout_sec = 180
    timeout_sec = max(10, min(600, timeout_sec))
    mapped = {
        'provider': {
            'provider': str(data.get('provider') or 'deterministic'),
            'model_label': data.get('model_label'),
            'llm_url': data.get('llm_url'),
            'api_key': data.get('api_key'),
            'timeout_sec': timeout_sec,
        },
        'permissions': {
            'can_chat': True,
            'can_scan_tools': True,
            'can_use_research': False,
            'can_manage_indicators': True,
            'can_place_trades': False,
            'can_close_trades': False,
            'can_auto_execute': False,
            'requires_user_confirm_for_trade': True,
        },
        'message': data.get('message') or '',
        'conversation_history': data.get('conversation_history') if isinstance(data.get('conversation_history'), list) else [],
        'context_snapshot': data.get('context_snapshot') if isinstance(data.get('context_snapshot'), dict) else {},
        'allow_tools': True,
        'max_tool_steps': 4,
    }
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/chat',
        data=mapped,
        return_error=True,
        timeout_sec=180,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Consultant chat failed'}), 500
    out = dict(res) if isinstance(res, dict) else {'result': res}
    out['deprecated'] = True
    out['deprecated_route'] = 'consultant/chat'
    out['replacement'] = '/api/simulation/sessions/<id>/agent/chat'
    return jsonify(out)


def _normalize_agent_permissions_payload(data: dict) -> dict:
    """Normalize agent permission payload to avoid contradictory combos."""
    if not isinstance(data, dict):
        return {}
    out = dict(data)
    perms = out.get('permissions') if isinstance(out.get('permissions'), dict) else {}
    if not perms:
        return out
    p = dict(perms)
    can_auto = bool(p.get('can_auto_execute', False))
    requires_confirm = bool(p.get('requires_user_confirm_for_trade', True))
    if can_auto:
        p['can_place_trades'] = True
        p['can_close_trades'] = True
        p['requires_user_confirm_for_trade'] = False
    elif requires_confirm:
        p['can_auto_execute'] = False
    out['permissions'] = p
    return out


@app.route('/api/simulation/sessions/<int:session_id>/agent/chat', methods=['POST'])
def sim_agent_chat(session_id):
    data = _normalize_agent_permissions_payload(request.get_json(silent=True) or {})
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/chat',
        data=data,
        return_error=True,
        timeout_sec=180,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent chat failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/run-once', methods=['POST'])
def sim_agent_run_once(session_id):
    data = _normalize_agent_permissions_payload(request.get_json(silent=True) or {})
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/run-once',
        data=data,
        return_error=True,
        timeout_sec=180,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent run-once failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/trendilo-opportunities', methods=['POST'])
def sim_agent_trendilo_opportunities(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/trendilo-opportunities',
        data=data,
        return_error=True,
        timeout_sec=180,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Trendilo opportunities scan failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/strategy-opportunities', methods=['POST'])
def sim_agent_strategy_opportunities(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/strategy-opportunities',
        data=data,
        return_error=True,
        timeout_sec=180,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Strategy opportunities scan failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/strategy-automation/start', methods=['POST'])
def sim_agent_strategy_automation_start(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/strategy-automation/start',
        data=data,
        return_error=True,
        timeout_sec=180,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Strategy automation start failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/strategy-automation/stop', methods=['POST'])
def sim_agent_strategy_automation_stop(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/strategy-automation/stop',
        data=data,
        return_error=True,
        timeout_sec=60,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Strategy automation stop failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/strategy-automation/jobs')
def sim_agent_strategy_automation_jobs(session_id):
    params = {}
    if request.args.get('include_disabled') is not None:
        params['include_disabled'] = request.args.get('include_disabled')
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/agent/strategy-automation/jobs',
        params=params,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Strategy automation jobs unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/strategy-automation/logs')
def sim_agent_strategy_automation_logs(session_id):
    params = {}
    if request.args.get('child_session_id') is not None:
        params['child_session_id'] = request.args.get('child_session_id')
    if request.args.get('job_id') is not None:
        params['job_id'] = request.args.get('job_id')
    if request.args.get('sort_by') is not None:
        params['sort_by'] = request.args.get('sort_by')
    if request.args.get('sort_order') is not None:
        params['sort_order'] = request.args.get('sort_order')
    if request.args.get('direction') is not None:
        params['direction'] = request.args.get('direction')
    if request.args.get('log_scope') is not None:
        params['log_scope'] = request.args.get('log_scope')
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/agent/strategy-automation/logs',
        params=params,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Strategy automation logs unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/agent/strategy-automation/jobs')
def sim_agent_strategy_automation_jobs_global():
    params = {}
    if request.args.get('include_disabled') is not None:
        params['include_disabled'] = request.args.get('include_disabled')
    res, err = api_request(
        'GET',
        '/api/v1/simulation/agent/strategy-automation/jobs',
        params=params,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Global strategy automation jobs unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/start', methods=['POST'])
def sim_agent_start(session_id):
    data = _normalize_agent_permissions_payload(request.get_json(silent=True) or {})
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/start',
        data=data,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to start agent'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/stop', methods=['POST'])
def sim_agent_stop(session_id):
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/stop',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to stop agent'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/pause', methods=['POST'])
def sim_agent_pause(session_id):
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/pause',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to pause agent'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/resume', methods=['POST'])
def sim_agent_resume(session_id):
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/resume',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Failed to resume agent'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/state')
def sim_agent_state(session_id):
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/agent/state',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent state unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/triggers')
def sim_agent_triggers_list(session_id):
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/agent/triggers',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent triggers unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/triggers', methods=['DELETE'])
def sim_agent_triggers_cancel_all(session_id):
    params = {'all': '1'} if str(request.args.get('all') or '').strip() in {'1', 'true', 'True', 'yes'} else {}
    res, err = api_request(
        'DELETE',
        f'/api/v1/simulation/sessions/{session_id}/agent/triggers',
        params=params,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent trigger cancel-all failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/triggers/<string:trigger_id>', methods=['DELETE'])
def sim_agent_trigger_cancel(session_id, trigger_id):
    res, err = api_request(
        'DELETE',
        f'/api/v1/simulation/sessions/{session_id}/agent/triggers/{trigger_id}',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent trigger cancel failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/memory')
def sim_agent_memory_list(session_id):
    params = {}
    if request.args.get('query'):
        params['query'] = request.args['query']
    if request.args.get('limit'):
        params['limit'] = request.args['limit']
    if request.args.get('memory_type'):
        params['memory_type'] = request.args['memory_type']
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/agent/memory',
        params=params,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent memory unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/memory', methods=['POST'])
def sim_agent_memory_add(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/memory',
        data=data,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent memory add failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/memory-policy')
def sim_agent_memory_policy_get(session_id):
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/agent/memory-policy',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent memory policy unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/memory-policy', methods=['POST'])
def sim_agent_memory_policy_set(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/memory-policy',
        data=data,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent memory policy update failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/identity')
def sim_agent_identity_get(session_id):
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/agent/identity',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent identity unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/identity', methods=['POST'])
def sim_agent_identity_set(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/identity',
        data=data,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent identity update failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/admin')
def sim_agent_admin_get(session_id):
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/agent/admin',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent admin status unavailable'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/memory/<int:memory_id>', methods=['DELETE'])
def sim_agent_memory_delete(session_id, memory_id):
    res, err = api_request(
        'DELETE',
        f'/api/v1/simulation/sessions/{session_id}/agent/memory/{memory_id}',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent memory delete failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/memory/<int:memory_id>', methods=['PATCH'])
def sim_agent_memory_update(session_id, memory_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'PATCH',
        f'/api/v1/simulation/sessions/{session_id}/agent/memory/{memory_id}',
        data=data,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent memory update failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/action', methods=['POST'])
def sim_agent_action(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/action',
        data=data,
        return_error=True,
        timeout_sec=60,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent action failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/agent/tool-state', methods=['POST'])
def sim_agent_tool_state(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request(
        'POST',
        f'/api/v1/simulation/sessions/{session_id}/agent/tool-state',
        data=data,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'ok': False, 'error': err or 'Agent tool-state push failed'}), 500
    return jsonify(res)


@app.route('/api/simulation/sessions/<int:session_id>/coach/evaluations')
def sim_coach_list(session_id):
    params = {}
    if request.args.get('limit'):
        params['limit'] = request.args['limit']
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/coach/evaluations',
        params=params,
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'error': err or 'Coach evaluations unavailable'}), 500
    response = make_response(jsonify(res))
    response.headers['X-Deprecated-Route'] = 'coach/evaluations'
    response.headers['X-Replacement-Route'] = '/api/simulation/sessions/<id>/agent/state'
    return response


@app.route('/api/simulation/sessions/<int:session_id>/coach/evaluations/<run_id>')
def sim_coach_get(session_id, run_id):
    res, err = api_request(
        'GET',
        f'/api/v1/simulation/sessions/{session_id}/coach/evaluations/{run_id}',
        return_error=True,
        timeout_sec=30,
    )
    if not res:
        return jsonify({'error': err or 'Coach evaluation run not found'}), 404
    out = dict(res) if isinstance(res, dict) else {'result': res}
    out['deprecated'] = True
    out['deprecated_route'] = 'coach/evaluations/<run_id>'
    out['replacement'] = '/api/simulation/sessions/<id>/agent/state'
    return jsonify(out)


# Guided trading simulation proxy routes
@app.route('/api/trading-simulation/capabilities')
def trading_sim_capabilities():
    res = api_request('GET', '/api/v1/trading-simulation/capabilities', use_cache=True)
    return jsonify(res or [])


@app.route('/api/trading-simulation/sessions', methods=['POST'])
def trading_sim_create_session_proxy():
    data = request.get_json(silent=True) or {}
    res, err = api_request('POST', '/api/v1/trading-simulation/sessions', data=data, return_error=True, timeout_sec=30)
    if not res:
        return jsonify({'error': err or 'Failed to create guided simulation session'}), 500
    return jsonify(res)


@app.route('/api/trading-simulation/sessions/<int:session_id>')
def trading_sim_get_session_proxy(session_id):
    res, err = api_request('GET', f'/api/v1/trading-simulation/sessions/{session_id}', return_error=True)
    if not res:
        return jsonify({'error': err or 'Session not found'}), 404
    return jsonify(res)


@app.route('/api/trading-simulation/sessions/<int:session_id>/state')
def trading_sim_get_state_proxy(session_id):
    res, err = api_request('GET', f'/api/v1/trading-simulation/sessions/{session_id}/state', return_error=True, timeout_sec=30)
    if not res:
        return jsonify({'error': err or 'State unavailable'}), 404
    return jsonify(res)


@app.route('/api/trading-simulation/sessions/<int:session_id>/action', methods=['POST'])
def trading_sim_action_proxy(session_id):
    data = request.get_json(silent=True) or {}
    res, err = api_request('POST', f'/api/v1/trading-simulation/sessions/{session_id}/action', data=data, return_error=True, timeout_sec=30)
    if not res:
        return jsonify({'error': err or 'Action failed'}), 500
    return jsonify(res)


@app.route('/api/trading-simulation/strategies/<strategy_id>/guide')
def trading_sim_guide_proxy(strategy_id):
    res, err = api_request('GET', f'/api/v1/trading-simulation/strategies/{strategy_id}/guide', return_error=True, use_cache=True)
    if not res:
        return jsonify({'error': err or 'Guide not found'}), 404
    return jsonify(res)


@app.route('/api/trading-simulation/strategies/<strategy_id>/playbook')
def trading_sim_playbook_proxy(strategy_id):
    res, err = api_request('GET', f'/api/v1/trading-simulation/strategies/{strategy_id}/playbook', return_error=True, use_cache=True)
    if not res:
        return jsonify({'error': err or 'Playbook not found'}), 404
    return jsonify(res)


@app.route('/api/preset/<preset_name>')
def get_preset(preset_name):
    """Get preset configuration as JSON"""
    preset = api_request('GET', f'/api/v1/presets/{preset_name}', use_cache=True)
    if preset:
        return jsonify(preset)
    return jsonify({})


@app.route('/api/config/<int:config_id>')
def get_config(config_id):
    """Get saved configuration as JSON"""
    config = api_request('GET', f'/api/v1/configs/{config_id}')
    if config:
        return jsonify(config)
    return jsonify({})


@app.route('/api/preset-matrix')
def get_preset_matrix():
    """Proxy: full strategy preset matrix"""
    result = api_request('GET', '/api/v1/preset-matrix')
    return jsonify(result or [])


@app.route('/api/strategies/list')
def get_strategy_list():
    """Get list of available strategies"""
    strategies = api_request('GET', '/api/v1/strategy-definitions/list', use_cache=True)
    if strategies:
        return jsonify(strategies)
    return jsonify([])


@app.route('/api/strategies/<strategy_id>/definition')
def get_strategy_definition(strategy_id):
    """Get full strategy definition with parameters"""
    definition = api_request('GET', f'/api/v1/strategy-definitions/{strategy_id}', use_cache=True)
    if definition:
        return jsonify(definition)
    return jsonify({}), 404


@app.route('/api/data/files')
def get_data_files():
    """Get list of available CSV data files (proxy to backend)"""
    files = api_request('GET', '/api/v1/data/files', use_cache=True)
    if files:
        return jsonify(files)
    return jsonify([])


@app.route('/api/strategies/<strategy_id>/defaults')
def get_strategy_defaults(strategy_id):
    """Get default parameter values for a strategy"""
    defaults = api_request('GET', f'/api/v1/strategy-definitions/{strategy_id}/defaults', use_cache=True)
    if defaults:
        return jsonify(defaults)
    return jsonify({})


@app.route('/api/strategies/<strategy_id>/preset/<preset_id>')
def get_strategy_preset(strategy_id, preset_id):
    """Get full configuration for a strategy preset (instrument-aware)"""
    symbol = request.args.get('symbol')
    url = f'/api/v1/strategy-definitions/{strategy_id}/preset/{preset_id}'
    if symbol:
        url += f'?symbol={symbol}'
    preset = api_request('GET', url, use_cache=True)
    if preset:
        return jsonify(preset)
    return jsonify({})


@app.route('/api/strategies/<strategy_id>/ml-base')
def get_strategy_ml_base(strategy_id):
    """Get the ML base strategy ID for an ML strategy"""
    result = api_request('GET', f'/api/v1/strategy-definitions/{strategy_id}/ml-base', use_cache=True)
    if result:
        return jsonify(result)
    return jsonify({'ml_base_strategy_id': None})


@app.route('/api/ml/models/matching')
def get_matching_ml_models():
    """Get ML models matching strategy + symbol + timeframe"""
    params = {
        'strategy_id': request.args.get('strategy_id', ''),
        'symbol': request.args.get('symbol', 'XAUUSD'),
        'timeframe': request.args.get('timeframe', 'M1'),
    }
    result = api_request('GET', '/api/v1/ml/models/matching', params=params)
    if result:
        return jsonify(result)
    return jsonify([])


def build_config_from_form(form):
    """Build configuration dictionary from form data dynamically"""
    # Get strategy definition to know parameter types
    strategy_id = form.get('strategy_id', 'orb_strategy')
    preset_id = form.get('preset_name') or form.get('preset', 'default')

    # Start with required fields
    start_date = form.get('start_date')
    end_date = form.get('end_date')

    # Collect selected CSV files (multiple checkboxes with name="csv_files")
    csv_files_selected = form.getlist('csv_files') if hasattr(form, 'getlist') else None
    if csv_files_selected is not None and len(csv_files_selected) == 0:
        csv_files_selected = None

    config = {
        'name': form.get('name', 'Unnamed Config'),
        'description': form.get('description', ''),
        'strategy_id': strategy_id,
        'preset_name': form.get('preset_name') or form.get('preset') or None,
        'start_date': f"{start_date}T00:00:00" if start_date else None,
        'end_date': f"{end_date}T23:59:59" if end_date else None,
        'data_source': form.get('data_source', 'auto'),
        'csv_files': csv_files_selected,
    }

    # Load preset configuration (includes optimal parameters + preset overrides)
    # Pass symbol for instrument-aware preset values
    symbol = form.get('symbol', 'XAUUSD')
    # Save user-set fields that must not be overwritten by preset
    preserved_fields = {k: v for k, v in config.items()}
    preset_url = f'/api/v1/strategy-definitions/{strategy_id}/preset/{preset_id}?symbol={symbol}'
    preset_config = api_request('GET', preset_url, use_cache=True)
    if preset_config:
        config.update(preset_config)
    # Restore user-set fields (name, dates, data_source, csv_files, etc.)
    config.update(preserved_fields)

    # Get strategy definition to parse user-provided form values
    strategy_def = api_request('GET', f'/api/v1/strategy-definitions/{strategy_id}', use_cache=True)

    # Override with user-provided values from form
    if strategy_def and 'parameters' in strategy_def:
        for param in strategy_def['parameters']:
            name = param['name']
            param_type = param['type']

            # Skip preset field - already handled
            if name == 'preset':
                continue

            # Get value from form
            value = form.get(name)

            # Only override if user provided a value
            if value is not None and value != '':
                if param_type == 'boolean':
                    # Checkbox: 'on' means True
                    config[name] = value == 'on'
                elif param_type == 'integer':
                    config[name] = int(value)
                elif param_type == 'number':
                    config[name] = float(value)
                elif param_type in ('string', 'time', 'select'):
                    config[name] = value
                else:
                    config[name] = value
            elif param_type == 'boolean' and value is None:
                # Unchecked checkbox - set to False
                config[name] = False

    # Per-run simulation/risk/ICT overrides rendered in Run Backtest page.
    # These allow changing key backtest knobs without editing saved presets.
    manual_field_types = {
        'risk_percent': float,
        'max_spread_usd': float,
        'max_daily_loss_usd': float,
        'max_total_risk_usd': float,
        'min_sl_usd': float,
        'max_sl_usd': float,
        'gold_rr_threshold': float,
        'min_fvg_gap': float,
        'fvg_lookback': int,
        'displacement_percentile': int,
        'displacement_lookback': int,
        'max_opposing_wick_ratio': float,
        'ob_lookback': int,
        'ob_min_body_percent': int,
        'ob_validation_bars': int,
        'liquidity_wick_ratio': float,
        'sweep_tolerance_usd': float,
        'bias_min_strength': int,
        'max_daily_trades': int,
        'min_adr_for_trend': float,
        'adr_period': int,
        'trailing_atr_period': int,
        'trailing_atr_multiplier': float,
        'slippage_atr_factor': float,
        'commission_per_lot': float,
        'swap_long_per_lot': float,
        'swap_short_per_lot': float,
        'friday_close_hour': int,
        'friday_close_minute': int,
        'orb_start_time': str,
        'orb_end_time': str,
        'trade_start_time': str,
        'trade_end_time': str,
        'asian_start': str,
        'asian_end': str,
        'london_start': str,
        'london_end': str,
        'use_trailing': bool,
        'stop_after_first_win': bool,
        'enable_cross_asset_filter': bool,
        'regime_signal_threshold': float,
        'regime_strong_threshold': float,
        'regime_tailwind_risk_multiplier': float,
        'regime_headwind_risk_multiplier': float,
        'regime_neutral_risk_multiplier': float,
    }

    for name, cast in manual_field_types.items():
        raw = form.get(name)
        if raw is None or raw == '':
            continue
        try:
            if cast is bool:
                config[name] = str(raw).strip().lower() in ('1', 'true', 'yes', 'on')
            elif cast is int:
                config[name] = int(raw)
            elif cast is float:
                config[name] = float(raw)
            else:
                config[name] = str(raw)
        except (TypeError, ValueError):
            # Ignore invalid manual values and keep preset/default value.
            continue

    # Handle ml_model_id (special field, not part of strategy definition params)
    ml_model_id = form.get('ml_model_id')
    if ml_model_id and ml_model_id.strip():
        config['ml_model_id'] = int(ml_model_id)

    return config


@app.route('/live-performance')
def live_performance():
    """Live execution quality dashboard"""
    return render_template('live_performance.html')


@app.route('/monitoring')
def monitoring():
    """Enterprise monitoring dashboard"""
    return render_template('monitoring.html')


@app.route('/api/monitoring/snapshot')
def get_monitoring_snapshot():
    """Proxy: aggregated monitoring snapshot"""
    result = api_request('GET', '/api/v1/monitoring/snapshot')
    return jsonify(result or {})


# ========================================================================
# ML Retrain from Live Data Proxy Routes
# ========================================================================

@app.route('/api/ml/retrain-live/<int:model_id>', methods=['POST'])
def retrain_with_live_data(model_id):
    """Proxy: retrain ML model with live trade data"""
    result = api_request('POST', f'/api/v1/ml/retrain-live/{model_id}')
    if result:
        return jsonify(result)
    return jsonify({'error': 'Retrain failed'}), 500


@app.route('/api/ml/live-trade-count')
def get_live_trade_count():
    """Proxy: count live trades with ML features"""
    params = {
        'strategy_id': request.args.get('strategy_id', 'orb_strategy'),
        'symbol': request.args.get('symbol', 'XAUUSD'),
        'timeframe': request.args.get('timeframe', 'M1'),
    }
    result = api_request('GET', '/api/v1/ml/live-trade-count', params=params)
    return jsonify(result or {})


# ========================================================================
# RL Online Learning Proxy Routes
# ========================================================================

@app.route('/api/rl/online-status')
def get_rl_online_status():
    """Proxy: RL online learning buffer status"""
    result = api_request('GET', '/api/v1/rl/online-status')
    return jsonify(result or {})


@app.route('/api/rl/online-config', methods=['POST'])
def update_rl_online_config():
    """Proxy: enable/disable RL online learning"""
    data = request.get_json() or {}
    result = api_request('POST', '/api/v1/rl/online-config', data=data)
    return jsonify(result or {})


@app.route('/api/rl/online-logs')
def get_rl_online_logs():
    """Proxy: RL online update history"""
    params = {'limit': request.args.get('limit', 50, type=int)}
    result = api_request('GET', '/api/v1/rl/online-logs', params=params)
    return jsonify(result or [])


# ========================================================================
# Adaptive Filter Proxy Routes
# ========================================================================

@app.route('/api/adaptive-filter/state')
def get_adaptive_filter_state():
    """Proxy: adaptive filter state"""
    result = api_request('GET', '/api/v1/adaptive-filter/state')
    return jsonify(result or {})


@app.route('/api/adaptive-filter/config', methods=['POST'])
def update_adaptive_filter_config():
    """Proxy: update adaptive filter config"""
    data = request.get_json() or {}
    result = api_request('POST', '/api/v1/adaptive-filter/config', data=data)
    return jsonify(result or {})


@app.route('/api/adaptive-filter/reset', methods=['POST'])
def reset_adaptive_filter():
    """Proxy: reset adaptive filter"""
    data = request.get_json() or {}
    result = api_request('POST', '/api/v1/adaptive-filter/reset', data=data)
    return jsonify(result or {})


@app.route('/api/live/execution-quality')
def get_execution_quality():
    """Proxy execution quality stats"""
    params = {'days': request.args.get('days', 30, type=int)}
    strategy_id = request.args.get('strategy_id')
    if strategy_id:
        params['strategy_id'] = strategy_id
    result = api_request('GET', '/api/v1/live/execution-quality', params=params)
    return jsonify(result or {})


@app.route('/api/live/execution-quality/trades')
def get_execution_quality_trades():
    """Proxy per-trade cost breakdown"""
    params = {
        'days': request.args.get('days', 30, type=int),
        'limit': request.args.get('limit', 50, type=int),
    }
    result = api_request('GET', '/api/v1/live/execution-quality/trades', params=params)
    return jsonify(result or [])


@app.route('/api/live/cost-comparison')
def get_cost_comparison():
    """Proxy backtest vs live cost comparison"""
    params = {'days': request.args.get('days', 30, type=int)}
    result = api_request('GET', '/api/v1/live/cost-comparison', params=params)
    return jsonify(result or {})


@app.route('/api/ml/retrain/status')
def get_retrain_status():
    """Proxy retrain scheduler status"""
    result = api_request('GET', '/api/v1/ml/retrain/status')
    return jsonify(result or {})


@app.route('/api/ml/retrain/trigger/<int:model_id>', methods=['POST'])
def trigger_retrain(model_id):
    """Proxy manual retrain trigger"""
    result = api_request('POST', f'/api/v1/ml/retrain/trigger/{model_id}')
    if result:
        return jsonify(result)
    return jsonify({'error': 'Retrain failed'}), 500


@app.route('/api/ml/retrain/config', methods=['POST'])
def update_retrain_config():
    """Proxy retrain config update"""
    data = request.get_json() or {}
    result = api_request('POST', '/api/v1/ml/retrain/config', data=data)
    return jsonify(result or {})


@app.route('/api/ml/retrain/logs')
def get_retrain_logs():
    """Proxy retrain logs"""
    params = {'limit': request.args.get('limit', 50, type=int)}
    result = api_request('GET', '/api/v1/ml/retrain/logs', params=params)
    return jsonify(result or [])


@app.route('/ml-models')
def ml_models():
    """ML Models management page"""
    models = api_request('GET', '/api/v1/ml/models')
    # Get completed backtests for training dropdown
    backtests = api_request('GET', '/api/v1/backtests/results', params={'limit': 50})
    completed = [b for b in (backtests or []) if b.get('status') == 'COMPLETED' and b.get('total_trades', 0) >= 10]
    # Get all strategies for the strategy dropdown
    strategies = api_request('GET', '/api/v1/strategy-definitions/list') or []
    return render_template('ml_models.html', models=models or [], backtests=completed, strategies=strategies)


@app.route('/ml-models/train', methods=['POST'])
def train_ml_model():
    """Train ML model from a backtest result"""
    result_id = request.form.get('result_id')
    strategy_id = request.form.get('strategy_id')
    model_type = request.form.get('model_type', 'xgboost')
    use_hpo = request.form.get('use_hpo') == 'on'

    if not result_id or not strategy_id:
        flash('Please select a backtest and strategy', 'error')
        return redirect(url_for('ml_models'))

    # Build query params with model_type and use_hpo
    query_params = f'strategy_id={strategy_id}&model_type={model_type}&use_hpo={str(use_hpo).lower()}'
    url = f'{API_BASE_URL}/api/v1/ml/train/{result_id}?{query_params}'
    try:
        # HPO can take much longer; allow up to 10 minutes
        timeout = 600 if use_hpo else 300
        response = requests.post(url, timeout=timeout)
        result = response.json() if response.status_code in (200, 201) else {'detail': response.text}
    except Exception as e:
        result = {'detail': str(e)}
    if result and result.get('status') == 'completed':
        flash(f'ML model trained successfully! Type: {model_type.upper()}, '
              f'AUC: {result.get("avg_auc_roc", 0):.3f}, '
              f'Accuracy: {result.get("avg_accuracy", 0):.1%}', 'success')
    else:
        flash(f'Training failed: {result.get("detail", "Unknown error") if result else "API connection error"}', 'error')

    return redirect(url_for('ml_models'))


@app.route('/ml-models/<int:model_id>/delete', methods=['POST'])
def delete_ml_model(model_id):
    """Delete a trained ML model"""
    result = api_request('DELETE', f'/api/v1/ml/models/{model_id}')
    if result:
        flash('ML model deleted', 'success')
    else:
        flash('Failed to delete model', 'error')
    return redirect(url_for('ml_models'))


# ========================================================================
# Data Management Routes
# ========================================================================

@app.route('/data-management')
def data_management():
    """Data management page - upload/manage CSV historical data"""
    files = api_request('GET', '/api/v1/data/files')
    return render_template('data_management.html', files=files or [])


@app.route('/data-management/upload', methods=['POST'])
def upload_data_file():
    """Handle CSV file upload directly in Flask (save to data/historical/)"""
    from pathlib import Path
    import shutil

    if 'file' not in request.files:
        flash('No file selected', 'error')
        return redirect(url_for('data_management'))

    file = request.files['file']
    if file.filename == '':
        flash('No file selected', 'error')
        return redirect(url_for('data_management'))

    if not file.filename.lower().endswith('.csv'):
        flash('Only CSV files are supported', 'error')
        return redirect(url_for('data_management'))

    # Build filename from form data
    symbol = request.form.get('symbol', 'XAUUSD').upper()
    timeframe = request.form.get('timeframe', 'M1').upper()
    original_name = os.path.splitext(file.filename)[0]

    # Sanitize filename
    safe_name = "".join(c for c in original_name if c.isalnum() or c in '-_.')

    # Final filename: SYMBOL_TIMEFRAME_originalname.csv
    filename = f"{symbol}_{timeframe}_{safe_name}.csv"

    # Save to data/historical/
    data_dir = Path(__file__).parent.parent / 'data' / 'historical'
    data_dir.mkdir(parents=True, exist_ok=True)

    save_path = data_dir / filename
    file.save(str(save_path))

    # Verify the file can be parsed
    try:
        import sys
        sys.path.insert(0, str(Path(__file__).parent.parent))
        from backend.core.data_provider import HistoricalDataProvider
        provider = HistoricalDataProvider()
        info = provider._get_csv_file_info(save_path)

        if info and info.get('bars', 0) > 0:
            flash(f'Data uploaded: {filename} ({info["bars"]} bars, '
                  f'{info.get("trading_days", "?")} trading days)', 'success')
        elif info and info.get('error'):
            flash(f'File saved but parsing failed: {info["error"]}. '
                  f'Check the CSV format.', 'warning')
        else:
            flash(f'File saved: {filename}. Could not verify contents.', 'warning')
    except Exception as e:
        flash(f'File saved: {filename}. Verification skipped: {str(e)}', 'warning')

    return redirect(url_for('data_management'))


@app.route('/data-management/download-mt5', methods=['POST'])
def download_mt5_data():
    """Download all available data from MT5 and save as CSV"""
    symbol = request.form.get('symbol', 'XAUUSD').upper()
    timeframe = request.form.get('timeframe', 'M1').upper()

    try:
        result = api_request('POST', '/api/v1/data/download-mt5',
                           data={'symbol': symbol, 'timeframe': timeframe})
        if result and result.get('status') == 'success':
            flash(f'Downloaded {result.get("bars", 0):,} bars from MT5 '
                  f'({result.get("start_date", "?")} to {result.get("end_date", "?")}). '
                  f'Saved as {result.get("filename", "")}', 'success')
        else:
            detail = result.get('detail', 'Unknown error') if result else 'Backend not responding'
            flash(f'Download failed: {detail}', 'error')
    except Exception as e:
        flash(f'Error: {str(e)}', 'error')

    return redirect(url_for('data_management'))


@app.route('/data-management/<filename>/delete', methods=['POST'])
def delete_data_file(filename):
    """Delete a CSV data file"""
    result = api_request('DELETE', f'/api/v1/data/files/{filename}')
    if result:
        flash(f'Data file deleted: {filename}', 'success')
    else:
        flash('Failed to delete file', 'error')
    return redirect(url_for('data_management'))


@app.route('/data-management/download-ibkr', methods=['POST'])
def download_ibkr_data():
    """Start IBKR data download (AJAX endpoint, returns JSON)"""
    data = {
        'symbol': request.form.get('symbol', 'XAUUSD').upper(),
        'timeframe': request.form.get('timeframe', 'M1').upper(),
        'start_date': request.form.get('start_date'),
        'end_date': request.form.get('end_date'),
        'port': int(request.form.get('port', 7497)),
    }

    result = api_request('POST', '/api/v1/data/download-ibkr', data=data)
    if result and result.get('task_id'):
        return jsonify(result)
    else:
        detail = result.get('detail', 'Backend not responding') if result else 'Backend not responding'
        return jsonify({'error': detail}), 500


@app.route('/api/ibkr/status/<task_id>')
def get_ibkr_status(task_id):
    """Proxy IBKR task status to backend"""
    result = api_request('GET', f'/api/v1/data/ibkr-status/{task_id}')
    if result:
        return jsonify(result)
    return jsonify({'error': 'Task not found'}), 404


@app.route('/api/ibkr/test-connection')
def test_ibkr_connection():
    """Proxy IBKR connection test to backend"""
    port = request.args.get('port', 7497, type=int)
    result = api_request('GET', f'/api/v1/data/ibkr-connection-test', params={'port': port})
    if result is not None:
        return jsonify(result)
    return jsonify({'connected': False, 'error': 'Backend not responding'}), 500


@app.route('/data-management/download-dukascopy', methods=['POST'])
def download_dukascopy_data():
    """Start Dukascopy data download (AJAX endpoint, returns JSON)"""
    data = {
        'symbol': request.form.get('symbol', 'XAUUSD').upper(),
        'start_date': request.form.get('start_date'),
        'end_date': request.form.get('end_date'),
    }

    result = api_request('POST', '/api/v1/data/download-dukascopy', data=data)
    if result and result.get('task_id'):
        return jsonify(result)
    else:
        detail = result.get('detail', 'Backend not responding') if result else 'Backend not responding'
        return jsonify({'error': detail}), 500


@app.route('/api/dukascopy/status/<task_id>')
def get_dukascopy_status(task_id):
    """Proxy Dukascopy task status to backend"""
    result = api_request('GET', f'/api/v1/data/dukascopy-status/{task_id}')
    if result:
        return jsonify(result)
    return jsonify({'error': 'Task not found'}), 404


@app.route('/api/dukascopy/test-connection')
def test_dukascopy_connection():
    """Proxy Dukascopy connection test to backend"""
    symbol = request.args.get('symbol', 'XAUUSD')
    result = api_request('GET', '/api/v1/data/dukascopy-connection-test', params={'symbol': symbol})
    if result is not None:
        return jsonify(result)
    return jsonify({'connected': False, 'error': 'Backend not responding'}), 500


@app.route('/data-management/download-databento', methods=['POST'])
def download_databento_data():
    """Start Databento earnings data download (AJAX endpoint)."""
    symbol = request.form.get('symbol', 'AAPL').upper().strip()
    timeframe = request.form.get('timeframe', 'M15').upper().strip()
    start_date = request.form.get('start_date')
    end_date = request.form.get('end_date')
    earnings_csv = (request.form.get('earnings_csv') or '').strip()
    api_key = (request.form.get('api_key') or '').strip()

    if not start_date or not end_date:
        return jsonify({'error': 'start_date and end_date are required'}), 400
    if timeframe not in {'M1', 'M5', 'M15', 'M30', 'H1', 'D1'}:
        return jsonify({'error': f'Invalid timeframe: {timeframe}'}), 400
    if earnings_csv:
        candidate = Path(earnings_csv)
        checked = []
        resolved = None
        if candidate.is_absolute():
            checked = [candidate]
        else:
            checked = [
                (_PROJECT_ROOT / candidate).resolve(),
                (_PROJECT_ROOT / 'dashboard' / candidate).resolve(),
            ]
        for p in checked:
            if p.exists():
                resolved = p
                break
        if resolved is None:
            paths_str = " | ".join(str(p) for p in checked)
            return jsonify({'error': f'earnings_csv not found. Checked: {paths_str}'}), 400
        earnings_csv = str(resolved)

    script_path = _PROJECT_ROOT / 'scripts' / 'fetch_earnings_strategy_data.py'
    if not script_path.exists():
        return jsonify({'error': f'Script not found: {script_path}'}), 500

    cmd = [
        sys.executable,
        str(script_path),
        '--symbol',
        symbol,
        '--start',
        start_date,
        '--end',
        end_date,
        '--timeframe',
        timeframe,
        '--output-dir',
        'data/historical',
    ]
    if earnings_csv:
        cmd.extend(['--earnings-csv', earnings_csv])
    if api_key:
        cmd.extend(['--api-key', api_key])

    task_id = uuid.uuid4().hex[:12]
    with _databento_tasks_lock:
        _databento_tasks[task_id] = {
            'task_id': task_id,
            'status': 'pending',
            'progress': 0,
            'message': 'Queued...',
            'symbol': symbol,
            'timeframe': timeframe,
            'start_date': start_date,
            'end_date': end_date,
            'logs': [],
            'created_at': datetime.now().isoformat(),
        }
        _save_databento_task_to_disk(task_id, _databento_tasks[task_id])

    thread = threading.Thread(
        target=_run_databento_task,
        args=(task_id, cmd, _PROJECT_ROOT),
        daemon=True,
    )
    thread.start()

    return jsonify({'task_id': task_id, 'status': 'started'})


@app.route('/api/databento/status/<task_id>')
def get_databento_status(task_id):
    """Poll Databento download task status."""
    with _databento_tasks_lock:
        task = _databento_tasks.get(task_id)
        if not task:
            # Fallback to persisted state for cross-process / reload resilience.
            task = _load_databento_task_from_disk(task_id)
            if task:
                _databento_tasks[task_id] = task
        if not task:
            return jsonify({'error': 'Task not found'}), 404
        payload = {
            'task_id': task.get('task_id'),
            'status': task.get('status'),
            'progress': task.get('progress', 0),
            'message': task.get('message', ''),
            'error': task.get('error'),
            'result': task.get('result'),
            'logs': (task.get('logs') or [])[-30:],
        }
    return jsonify(payload)


@app.template_filter('datetime')
def format_datetime(value):
    """Format datetime string"""
    if isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
            return dt.strftime('%Y-%m-%d %H:%M')
        except:
            return value
    return value


@app.template_filter('number')
def format_number(value, decimals=2):
    """Format number with decimals"""
    try:
        return f"{float(value):,.{decimals}f}"
    except:
        return value


@app.template_filter('percent')
def format_percent(value):
    """Format as percentage"""
    try:
        return f"{float(value):+.2f}%"
    except:
        return value


@app.context_processor
def inject_now():
    """Inject shared template globals."""
    return {
        'now': datetime.now,
        'api_base_url': str(API_BASE_URL or '').strip(),
    }


if __name__ == '__main__':
    # Create templates directory if it doesn't exist
    os.makedirs('templates', exist_ok=True)
    os.makedirs('static/css', exist_ok=True)
    os.makedirs('static/js', exist_ok=True)

    # Run the app
    app.run(debug=True, host='0.0.0.0', port=5000)
