(function () {
    'use strict';

    const els = {
        alert: document.getElementById('bridge-alert'),
        refreshBtn: document.getElementById('bridge-refresh-btn'),
        updated: document.getElementById('bridge-updated'),
        mt4Count: document.getElementById('bridge-mt4-count'),
        mt5Count: document.getElementById('bridge-mt5-count'),
        openCount: document.getElementById('bridge-open-count'),
        auditCount: document.getElementById('bridge-audit-count'),
        mt4Body: document.getElementById('bridge-mt4-body'),
        mt5Body: document.getElementById('bridge-mt5-body'),
        auditBody: document.getElementById('bridge-audit-body'),
        mt4StartAll: document.getElementById('bridge-mt4-start-all'),
        mt4StopAll: document.getElementById('bridge-mt4-stop-all'),
        mt5StartAll: document.getElementById('bridge-mt5-start-all'),
        mt5StopAll: document.getElementById('bridge-mt5-stop-all')
    };

    let latestState = null;
    let pollTimer = null;

    function showAlert(message, kind) {
        if (!els.alert) return;
        const cls = kind === 'error' ? 'alert-danger' : (kind === 'success' ? 'alert-success' : 'alert-info');
        els.alert.innerHTML = `<div class="alert ${cls} alert-dismissible fade show" role="alert">${escapeHtml(String(message || ''))}<button type="button" class="btn-close" data-bs-dismiss="alert"></button></div>`;
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
            second: '2-digit',
            hour12: false
        }).format(dt);
    }

    function formatNum(value, digits = 2) {
        const num = Number(value);
        if (!Number.isFinite(num)) return '-';
        return num.toFixed(digits);
    }

    function parseLotInput(rawValue) {
        const txt = String(rawValue || '').trim().replace(',', '.');
        const val = Number(txt);
        if (!Number.isFinite(val) || val <= 0) return null;
        return val;
    }

    function monitorRows(family) {
        const key = String(family || '').toLowerCase() === 'mt5' ? 'mt5_monitor' : 'mt4_monitor';
        const monitor = (latestState && latestState[key] && typeof latestState[key] === 'object') ? latestState[key] : {};
        return Array.isArray(monitor.bot_rows) ? monitor.bot_rows.slice() : [];
    }

    function auditRows() {
        const audit = (latestState && latestState.execution_logs && typeof latestState.execution_logs === 'object') ? latestState.execution_logs : {};
        return Array.isArray(audit.rows) ? audit.rows.slice() : [];
    }

    function refreshSummary() {
        const mt4Monitor = (latestState && latestState.mt4_monitor) || {};
        const mt5Monitor = (latestState && latestState.mt5_monitor) || {};
        const audit = (latestState && latestState.execution_logs) || {};
        const openCount = Number(mt4Monitor.bot_open_count || 0) + Number(mt5Monitor.bot_open_count || 0);
        if (els.mt4Count) els.mt4Count.textContent = String((monitorRows('mt4')).length);
        if (els.mt5Count) els.mt5Count.textContent = String((monitorRows('mt5')).length);
        if (els.openCount) els.openCount.textContent = String(openCount);
        if (els.auditCount) els.auditCount.textContent = String(Number(audit.count || 0));
        if (els.updated) els.updated.textContent = `Updated: ${formatTs((latestState || {}).updated_at)}`;
    }

    function renderMonitor(family) {
        const rows = monitorRows(family);
        const body = String(family).toLowerCase() === 'mt5' ? els.mt5Body : els.mt4Body;
        if (!body) return;
        if (!rows.length) {
            body.innerHTML = '<tr><td colspan="13" class="text-muted text-center py-3">No active bridge charts registered yet.</td></tr>';
            return;
        }
        body.innerHTML = rows.map((row) => {
            const indicator = String(row.indicator || '').trim() || '-';
            const symbol = String(row.symbol || '').trim().toUpperCase() || '-';
            const timeframe = String(row.timeframe || '').trim().toUpperCase() || '-';
            const enabled = !!row.effective_automation_enabled;
            const state = String(row.state || (row.has_open_ladder ? 'OPEN' : 'IDLE')).toUpperCase() || 'IDLE';
            const badgeCls = state === 'OPEN' ? 'bg-success' : 'bg-secondary';
            const autoCls = enabled ? 'bg-success' : 'bg-secondary';
            const lotValue = Number(row.lot_size || 0);
            const modeAdvanced = !!row.mode_advanced_enabled;
            const modeNormal = !!row.mode_normal_enabled;
            const instanceKey = String(row.instance_key || '').trim();
            return `
                <tr data-family="${escapeHtml(String(family).toLowerCase())}" data-instance-key="${escapeHtml(instanceKey)}" data-indicator="${escapeHtml(indicator)}" data-symbol="${escapeHtml(symbol)}" data-timeframe="${escapeHtml(timeframe)}">
                    <td>${escapeHtml(formatTs(row.last_seen))}</td>
                    <td>${escapeHtml(indicator)}</td>
                    <td>${escapeHtml(symbol)} ${escapeHtml(timeframe)}</td>
                    <td>${escapeHtml(String(row.direction || '-').toUpperCase() || '-')}</td>
                    <td>${row.ticket ? escapeHtml(String(row.ticket)) : '-'}</td>
                    <td><span class="badge ${badgeCls}">${escapeHtml(state)}</span></td>
                    <td><span class="badge ${autoCls}">${enabled ? 'ON' : 'OFF'}</span></td>
                    <td>
                        <div class="d-flex flex-column gap-1">
                            <label class="form-check-label small">
                                <input type="checkbox" class="form-check-input me-1 bridge-mode-toggle" data-mode="advanced" ${modeAdvanced ? 'checked' : ''}>
                                Advanced
                            </label>
                            <label class="form-check-label small">
                                <input type="checkbox" class="form-check-input me-1 bridge-mode-toggle" data-mode="normal" ${modeNormal ? 'checked' : ''}>
                                Normal
                            </label>
                        </div>
                    </td>
                    <td>
                        <div class="input-group input-group-sm" style="min-width:150px;">
                            <input type="number" class="form-control bridge-lot-input" min="0.01" step="0.01" value="${Number.isFinite(lotValue) && lotValue > 0 ? escapeHtml(lotValue.toFixed(2)) : '0.05'}">
                            <button type="button" class="btn btn-outline-secondary bridge-save-lot-btn">Save</button>
                        </div>
                    </td>
                    <td>${escapeHtml(formatNum(row.max_profit, 2))}</td>
                    <td>${escapeHtml(formatNum(row.max_loss, 2))}</td>
                    <td>${escapeHtml(formatNum(row.current_profit, 2))}</td>
                    <td>
                        <button type="button" class="btn btn-sm ${enabled ? 'btn-outline-danger' : 'btn-outline-success'} bridge-toggle-btn">${enabled ? 'Stop' : 'Start'}</button>
                    </td>
                </tr>
            `;
        }).join('');
    }

    function renderAudit() {
        const rows = auditRows();
        if (!els.auditBody) return;
        if (!rows.length) {
            els.auditBody.innerHTML = '<tr><td colspan="17" class="text-muted text-center py-3">No indicator execution rows yet.</td></tr>';
            return;
        }
        els.auditBody.innerHTML = rows.map((row) => `
            <tr>
                <td>${escapeHtml(formatTs(row.event_ts))}</td>
                <td>${escapeHtml(formatTs(row.opened_at))}</td>
                <td>${escapeHtml(formatTs(row.closed_at))}</td>
                <td>${escapeHtml(String(row.terminal_family || '-'))}</td>
                <td>${escapeHtml(String(row.indicator || row.source_name || '-'))}</td>
                <td>${escapeHtml(String(row.symbol || '-'))} ${escapeHtml(String(row.timeframe || '-'))}</td>
                <td>${escapeHtml(String(row.direction || '-'))}</td>
                <td>${escapeHtml(formatNum(row.lot, 2))}</td>
                <td>${escapeHtml(String(row.status || '-').toUpperCase())}</td>
                <td>${escapeHtml(String(row.execution_mode || '-').toUpperCase())}</td>
                <td>${row.ticket ? escapeHtml(String(row.ticket)) : '-'}</td>
                <td>${escapeHtml(String(row.session_name || '-'))}</td>
                <td>${escapeHtml(formatNum(row.max_profit, 2))}</td>
                <td>${escapeHtml(formatNum(row.max_loss, 2))}</td>
                <td>${escapeHtml(formatNum(row.realized_pnl, 2))}</td>
                <td>${escapeHtml(String(row.close_reason || '-'))}</td>
                <td>${escapeHtml(String(row.message || '-'))}</td>
            </tr>
        `).join('');
    }

    function renderAll() {
        refreshSummary();
        renderMonitor('mt4');
        renderMonitor('mt5');
        renderAudit();
    }

    async function loadState(showToastOnError = false) {
        try {
            latestState = await req('/api/indicator-bridge/state?limit=500');
            renderAll();
        } catch (err) {
            if (showToastOnError) showAlert(`Load failed: ${String(err.message || err)}`, 'error');
            throw err;
        }
    }

    async function updateInstance(family, indicator, symbol, timeframe, options) {
        const payload = Object.assign({
            terminal_family: String(family || 'mt4').toLowerCase(),
            indicator: String(indicator || '').trim(),
            symbol: String(symbol || '').trim().toUpperCase(),
            timeframe: String(timeframe || '').trim().toUpperCase()
        }, options || {});
        latestState = await req('/api/indicator-bridge/instance-automation', {
            method: 'POST',
            body: JSON.stringify(payload)
        });
        renderAll();
        return latestState;
    }

    async function bulkSetFamily(family, enabled) {
        const rows = monitorRows(family);
        for (const row of rows) {
            const current = !!row.effective_automation_enabled;
            if (current === !!enabled) continue;
            await updateInstance(family, row.indicator, row.symbol, row.timeframe, { enabled: !!enabled });
        }
        showAlert(`${String(family).toUpperCase()} bots ${enabled ? 'started' : 'stopped'}.`, 'success');
    }

    function handleMonitorClick(ev) {
        const target = ev.target;
        if (!(target instanceof HTMLElement)) return;
        const row = target.closest('tr[data-instance-key]');
        if (!(row instanceof HTMLElement)) return;
        const family = String(row.getAttribute('data-family') || 'mt4').toLowerCase();
        const indicator = String(row.getAttribute('data-indicator') || '').trim();
        const symbol = String(row.getAttribute('data-symbol') || '').trim().toUpperCase();
        const timeframe = String(row.getAttribute('data-timeframe') || '').trim().toUpperCase();
        if (!indicator || !symbol || !timeframe) return;
        if (target.classList.contains('bridge-toggle-btn')) {
            const rows = monitorRows(family);
            const current = rows.find((x) => String(x.instance_key || '').trim().toLowerCase() === String(row.getAttribute('data-instance-key') || '').trim().toLowerCase());
            const enabledNow = !!(current && current.effective_automation_enabled);
            updateInstance(family, indicator, symbol, timeframe, { enabled: !enabledNow })
                .then(() => showAlert(`${!enabledNow ? 'Started' : 'Stopped'} automation for ${indicator} ${symbol} ${timeframe}.`, 'success'))
                .catch((err) => showAlert(`Toggle failed: ${String(err.message || err)}`, 'error'));
            return;
        }
        if (target.classList.contains('bridge-save-lot-btn')) {
            const input = row.querySelector('.bridge-lot-input');
            const lot = parseLotInput(input && input.value);
            if (lot === null) {
                showAlert('Invalid lot size. Use a value > 0.', 'error');
                return;
            }
            updateInstance(family, indicator, symbol, timeframe, { lot_size: lot })
                .then(() => showAlert(`Lot updated for ${indicator} ${symbol} ${timeframe}.`, 'success'))
                .catch((err) => showAlert(`Lot update failed: ${String(err.message || err)}`, 'error'));
            return;
        }
        if (target.classList.contains('bridge-mode-toggle')) {
            const mode = String(target.getAttribute('data-mode') || '').trim().toLowerCase();
            const checked = !!target.checked;
            if (mode !== 'advanced' && mode !== 'normal') return;
            const payload = (mode === 'advanced')
                ? { mode_advanced_enabled: checked }
                : { mode_normal_enabled: checked };
            updateInstance(family, indicator, symbol, timeframe, payload)
                .then(() => showAlert(`Mode updated (${mode}) for ${indicator} ${symbol} ${timeframe}.`, 'success'))
                .catch((err) => {
                    showAlert(`Mode update failed: ${String(err.message || err)}`, 'error');
                    loadState(false).catch(() => {});
                });
        }
    }

    async function init() {
        if (els.refreshBtn) {
            els.refreshBtn.addEventListener('click', async () => {
                try {
                    await loadState(true);
                    showAlert('Refreshed.', 'info');
                } catch (_) { /* already handled */ }
            });
        }
        if (els.mt4Body) els.mt4Body.addEventListener('click', handleMonitorClick);
        if (els.mt5Body) els.mt5Body.addEventListener('click', handleMonitorClick);
        if (els.mt4StartAll) els.mt4StartAll.addEventListener('click', () => bulkSetFamily('mt4', true).catch((err) => showAlert(`MT4 start failed: ${String(err.message || err)}`, 'error')));
        if (els.mt4StopAll) els.mt4StopAll.addEventListener('click', () => bulkSetFamily('mt4', false).catch((err) => showAlert(`MT4 stop failed: ${String(err.message || err)}`, 'error')));
        if (els.mt5StartAll) els.mt5StartAll.addEventListener('click', () => bulkSetFamily('mt5', true).catch((err) => showAlert(`MT5 start failed: ${String(err.message || err)}`, 'error')));
        if (els.mt5StopAll) els.mt5StopAll.addEventListener('click', () => bulkSetFamily('mt5', false).catch((err) => showAlert(`MT5 stop failed: ${String(err.message || err)}`, 'error')));

        try {
            await loadState(true);
        } catch (_) {
            return;
        }

        if (pollTimer) clearInterval(pollTimer);
        pollTimer = setInterval(() => {
            loadState(false).catch(() => {});
        }, 5000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
