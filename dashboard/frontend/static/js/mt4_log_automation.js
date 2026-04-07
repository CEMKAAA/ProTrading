(function () {
    'use strict';

    const els = {
        alert: document.getElementById('mt4la-alert'),
        enabled: document.getElementById('mt4la-enabled'),
        dataPath: document.getElementById('mt4la-data-path'),
        pollSec: document.getElementById('mt4la-poll-sec'),
        backfillLines: document.getElementById('mt4la-backfill-lines'),
        saveBtn: document.getElementById('mt4la-save-btn'),
        refreshBtn: document.getElementById('mt4la-refresh-btn'),
        statusLine: document.getElementById('mt4la-status-line'),
        filesLine: document.getElementById('mt4la-files-line'),
        updated: document.getElementById('mt4la-updated'),
        running: document.getElementById('mt4la-running'),
        indicatorCount: document.getElementById('mt4la-indicator-count'),
        eventCount: document.getElementById('mt4la-event-count'),
        forward: document.getElementById('mt4la-forward'),
        forwardLine: document.getElementById('mt4la-forward-line'),
        indicatorBody: document.getElementById('mt4la-indicator-body'),
        logTitle: document.getElementById('mt4la-log-title'),
        logBody: document.getElementById('mt4la-log-body')
    };

    let pollTimer = null;
    let formDirty = false;
    let suppressDirty = false;
    let selectedIndicator = '';
    let latestState = null;

    function showAlert(message, kind) {
        const cls = kind === 'error' ? 'alert-danger' : (kind === 'success' ? 'alert-success' : 'alert-info');
        if (!els.alert) return;
        els.alert.innerHTML = `<div class="alert ${cls} alert-dismissible fade show" role="alert">${String(message || '')}<button type="button" class="btn-close" data-bs-dismiss="alert"></button></div>`;
    }

    async function req(url, opts) {
        const res = await fetch(url, Object.assign({
            headers: { 'Content-Type': 'application/json' },
            credentials: 'same-origin'
        }, opts || {}));
        let data = null;
        try { data = await res.json(); } catch (_) { data = null; }
        if (!res.ok) {
            const err = (data && (data.error || data.detail)) ? (data.error || data.detail) : `HTTP ${res.status}`;
            throw new Error(String(err));
        }
        return data || {};
    }

    function escapeHtml(v) {
        return String(v || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function formatTs(value) {
        const raw = String(value || '').trim();
        if (!raw) return '-';
        const dt = new Date(raw);
        if (Number.isNaN(dt.getTime())) return raw;
        return new Intl.DateTimeFormat('tr-TR', {
            day: '2-digit',
            month: '2-digit',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit',
            hour12: false
        }).format(dt);
    }

    function fillForm(cfg, force) {
        if (!force && formDirty) return;
        const c = cfg || {};
        suppressDirty = true;
        if (els.enabled) els.enabled.checked = !!c.enabled;
        if (els.dataPath) els.dataPath.value = String(c.data_path || '');
        if (els.pollSec) els.pollSec.value = String(Number(c.poll_sec || 2));
        if (els.backfillLines) els.backfillLines.value = String(parseInt(c.backfill_lines || 200, 10));
        suppressDirty = false;
    }

    function renderStatus(state) {
        const s = state || {};
        const run = !!s.running;
        if (els.running) {
            els.running.textContent = run ? 'RUNNING' : 'STOPPED';
            els.running.className = run ? 'fs-6 text-success' : 'fs-6 text-danger';
        }
        if (els.indicatorCount) els.indicatorCount.textContent = String(s.indicator_count || 0);
        if (els.eventCount) els.eventCount.textContent = String((Array.isArray(s.events) ? s.events.length : 0));
        if (els.forward) els.forward.textContent = `${Number(s.forward_ok || 0)} / ${Number(s.forward_fail || 0)}`;
        if (els.statusLine) {
            const err = String(s.last_error || '').trim();
            els.statusLine.textContent = `Status: ${run ? 'running' : 'stopped'}${err ? ` | err: ${err}` : ''}`;
        }
        if (els.filesLine) {
            els.filesLine.textContent = `Watched files: ${Number(s.watched_files_count || 0)}`;
        }
        if (els.forwardLine) {
            const lf = String(s.last_forward || '').trim();
            const ind = String(s.last_forward_indicator || '').trim();
            const err = String(s.last_forward_error || '').trim();
            const stale = Number(s.forward_skip_stale || 0);
            const dup = Number(s.forward_skip_duplicate || 0);
            els.forwardLine.textContent = `Forward: total ${Number(s.forward_total || 0)} | stale ${stale} | dup ${dup} | last ${lf || '-'}${ind ? ` | indicator: ${ind}` : ''}${err ? ` | err: ${err}` : ''}`;
        }
        if (els.updated) els.updated.textContent = `Updated: ${new Date().toLocaleTimeString()}`;
    }

    function renderIndicators(state) {
        const rows = Array.isArray((state || {}).indicators) ? state.indicators.slice() : [];
        if (!els.indicatorBody) return;
        if (!rows.length) {
            els.indicatorBody.innerHTML = '<tr><td colspan="8" class="text-muted text-center py-3">No indicator rows yet. Check MT4 path + active charts.</td></tr>';
            return;
        }
        els.indicatorBody.innerHTML = rows.map((r) => {
            const indicator = String(r.indicator || r.key || '').trim();
            const symbol = String(r.last_symbol || '').trim();
            const tf = String(r.last_timeframe || '').trim();
            const eventCount = Number(r.event_count || 0);
            const signalCount = Number(r.signal_hint_count || 0);
            const lastSignal = String(r.last_signal_hint || '').trim().toUpperCase();
            const lastProfile = String(r.last_signal_profile || '').trim();
            const lastSeen = formatTs(r.last_seen || '');
            const enabled = !!r.automation_enabled;
            const badgeCls = enabled ? 'text-bg-success' : 'text-bg-secondary';
            const toggleLabel = enabled ? 'Stop Automation' : 'Start Automation';
            const signalText = lastSignal ? `${lastSignal}${lastProfile ? ` (${lastProfile})` : ''}` : '-';
            return `
                <tr data-indicator="${escapeHtml(indicator)}">
                    <td>${escapeHtml(indicator)}</td>
                    <td>${escapeHtml((symbol && tf) ? `${symbol} ${tf}` : (symbol || tf || '-'))}</td>
                    <td>${eventCount}</td>
                    <td>${signalCount}</td>
                    <td>${escapeHtml(signalText)}</td>
                    <td class="small text-muted">${escapeHtml(lastSeen)}</td>
                    <td><span class="badge ${badgeCls}">${enabled ? 'ON' : 'OFF'}</span></td>
                    <td>
                        <button class="btn btn-outline-primary btn-sm me-1 mt4la-view-btn">Logs</button>
                        <button class="btn btn-outline-${enabled ? 'danger' : 'success'} btn-sm mt4la-toggle-btn">${toggleLabel}</button>
                    </td>
                </tr>
            `;
        }).join('');
    }

    function renderIndicatorLogs(indicator, rows) {
        const name = String(indicator || '').trim();
        if (els.logTitle) els.logTitle.textContent = name ? `Indicator Logs: ${name}` : 'Indicator Logs';
        if (!els.logBody) return;
        const items = Array.isArray(rows) ? rows.slice() : [];
        items.sort((a, b) => {
            const ta = Date.parse(String(a.event_ts || '')) || 0;
            const tb = Date.parse(String(b.event_ts || '')) || 0;
            return tb - ta;
        });
        if (!items.length) {
            els.logBody.innerHTML = '<tr><td colspan="3" class="text-muted text-center py-3">No rows for this indicator.</td></tr>';
            return;
        }
        els.logBody.innerHTML = items.map((r) => {
            const ts = formatTs(r.event_ts || '');
            const kind = String(r.kind || 'log');
            const msg = escapeHtml(String(r.message || r.raw || ''));
            return `<tr><td class="small text-muted">${ts}</td><td><span class="badge text-bg-secondary">${escapeHtml(kind)}</span></td><td style="white-space: pre-wrap;">${msg}</td></tr>`;
        }).join('');
    }

    async function loadIndicatorLogs(indicator) {
        const name = String(indicator || '').trim();
        if (!name) return;
        const data = await req(`/api/mt4/log-automation/indicator-logs?indicator=${encodeURIComponent(name)}&limit=400&alerts_only=1`);
        renderIndicatorLogs(data.indicator || name, data.rows || []);
    }

    async function loadState(force) {
        const data = await req('/api/mt4/log-automation/state?limit=500');
        latestState = data || {};
        fillForm((data || {}).config || {}, !!force);
        renderStatus(data || {});
        renderIndicators(data || {});
        if (selectedIndicator) {
            await loadIndicatorLogs(selectedIndicator);
        }
    }

    function collectPayload() {
        return {
            enabled: !!(els.enabled && els.enabled.checked),
            data_path: String((els.dataPath && els.dataPath.value) || '').trim(),
            poll_sec: parseFloat((els.pollSec && els.pollSec.value) || '2'),
            backfill_lines: parseInt((els.backfillLines && els.backfillLines.value) || '200', 10)
        };
    }

    async function saveConfig() {
        const payload = collectPayload();
        const data = await req('/api/mt4/log-automation/config', {
            method: 'POST',
            body: JSON.stringify(payload)
        });
        formDirty = false;
        fillForm((data || {}).config || {}, true);
        renderStatus(data || {});
        renderIndicators(data || {});
        showAlert('MT4 log automation config saved.', 'success');
    }

    async function toggleIndicator(indicator, enabledNext) {
        const data = await req('/api/mt4/log-automation/indicator-automation', {
            method: 'POST',
            body: JSON.stringify({ indicator: String(indicator || ''), enabled: !!enabledNext })
        });
        latestState = data || latestState || {};
        renderStatus(latestState || {});
        renderIndicators(latestState || {});
        showAlert(`${enabledNext ? 'Started' : 'Stopped'} automation for ${indicator}.`, 'success');
    }

    async function init() {
        const formInputs = [els.enabled, els.dataPath, els.pollSec, els.backfillLines].filter(Boolean);
        for (const el of formInputs) {
            el.addEventListener('input', () => {
                if (!suppressDirty) formDirty = true;
            });
            el.addEventListener('change', () => {
                if (!suppressDirty) formDirty = true;
            });
        }

        if (els.saveBtn) {
            els.saveBtn.addEventListener('click', async () => {
                els.saveBtn.disabled = true;
                try {
                    await saveConfig();
                } catch (err) {
                    showAlert(`Save failed: ${String(err.message || err)}`, 'error');
                } finally {
                    els.saveBtn.disabled = false;
                }
            });
        }
        if (els.refreshBtn) {
            els.refreshBtn.addEventListener('click', async () => {
                try {
                    formDirty = false;
                    await loadState(true);
                    showAlert('Refreshed.', 'info');
                } catch (err) {
                    showAlert(`Refresh failed: ${String(err.message || err)}`, 'error');
                }
            });
        }

        if (els.indicatorBody) {
            els.indicatorBody.addEventListener('click', async (ev) => {
                const target = ev.target;
                if (!target || !(target instanceof HTMLElement)) return;
                const row = target.closest('tr[data-indicator]');
                if (!row) return;
                const indicator = String(row.getAttribute('data-indicator') || '').trim();
                if (!indicator) return;
                if (target.classList.contains('mt4la-view-btn')) {
                    selectedIndicator = indicator;
                    try {
                        await loadIndicatorLogs(indicator);
                    } catch (err) {
                        showAlert(`Load logs failed: ${String(err.message || err)}`, 'error');
                    }
                    return;
                }
                if (target.classList.contains('mt4la-toggle-btn')) {
                    const all = Array.isArray((latestState || {}).indicators) ? latestState.indicators : [];
                    const current = all.find((x) => String((x || {}).indicator || '').trim().toLowerCase() === indicator.toLowerCase());
                    const enabledNow = !!(current && current.automation_enabled);
                    try {
                        await toggleIndicator(indicator, !enabledNow);
                    } catch (err) {
                        showAlert(`Toggle failed: ${String(err.message || err)}`, 'error');
                    }
                }
            });
        }

        try {
            await loadState(true);
        } catch (err) {
            showAlert(`Load failed: ${String(err.message || err)}`, 'error');
        }

        if (pollTimer) clearInterval(pollTimer);
        pollTimer = setInterval(async () => {
            try {
                await loadState(false);
            } catch (_) {
                // keep silent in poll loop
            }
        }, 5000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
