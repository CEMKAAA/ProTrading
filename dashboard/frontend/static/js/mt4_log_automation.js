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
        instanceCount: document.getElementById('mt4la-instance-count'),
        eventCount: document.getElementById('mt4la-event-count'),
        forward: document.getElementById('mt4la-forward'),
        forwardLine: document.getElementById('mt4la-forward-line'),
        indicatorBody: document.getElementById('mt4la-indicator-body'),
        indicatorSearch: document.getElementById('mt4la-indicator-search'),
        instanceBody: document.getElementById('mt4la-instance-body'),
        instanceSearch: document.getElementById('mt4la-instance-search'),
        logTitle: document.getElementById('mt4la-log-title'),
        logBody: document.getElementById('mt4la-log-body'),
        execBody: document.getElementById('mt4la-exec-body')
    };

    let pollTimer = null;
    let formDirty = false;
    let suppressDirty = false;
    let selectedIndicator = '';
    let latestState = null;
    let indicatorSearchText = '';
    let instanceSearchText = '';
    let latestExecLogs = [];
    const lotDraftByIndicator = new Map();
    const lotDraftByInstance = new Map();

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

    function parseLotInput(rawValue) {
        const txt = String(rawValue || '').trim().replace(',', '.');
        const val = Number(txt);
        if (!Number.isFinite(val) || val <= 0) return null;
        return val;
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
        if (els.instanceCount) els.instanceCount.textContent = String(s.instance_count || 0);
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
            const backfill = Number(s.forward_skip_backfill || 0);
            const disabled = Number(s.forward_skip_disabled || 0);
            const noHint = Number(s.forward_skip_no_hint || 0);
            const noCb = Number(s.forward_skip_no_callback || 0);
            els.forwardLine.textContent = `Forward: total ${Number(s.forward_total || 0)} | stale ${stale} | dup ${dup} | backfill ${backfill} | disabled ${disabled} | nohint ${noHint} | nocb ${noCb} | last ${lf || '-'}${ind ? ` | indicator: ${ind}` : ''}${err ? ` | err: ${err}` : ''}`;
        }
        if (els.updated) els.updated.textContent = `Updated: ${new Date().toLocaleTimeString()}`;
    }

    function renderIndicators(state) {
        const allRows = Array.isArray((state || {}).indicators) ? state.indicators.slice() : [];
        const filter = String(indicatorSearchText || '').trim().toLowerCase();
        const rows = filter
            ? allRows.filter((r) => String((r || {}).indicator || (r || {}).key || '').trim().toLowerCase().includes(filter))
            : allRows;
        if (!els.indicatorBody) return;
        if (!allRows.length) {
            els.indicatorBody.innerHTML = '<tr><td colspan="9" class="text-muted text-center py-3">No indicator rows yet. Check MT4/MT5 path(s) + active charts.</td></tr>';
            return;
        }
        if (!rows.length) {
            els.indicatorBody.innerHTML = '<tr><td colspan="9" class="text-muted text-center py-3">No indicators match your search.</td></tr>';
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
            const lotRaw = Number(r.lot_size || 0);
            const lotFromState = Number.isFinite(lotRaw) && lotRaw > 0 ? lotRaw.toFixed(2) : '0.05';
            const draft = lotDraftByIndicator.get(indicator);
            const lot = (typeof draft === 'string' && draft.length > 0) ? draft : lotFromState;
            return `
                <tr data-indicator="${escapeHtml(indicator)}">
                    <td>${escapeHtml(indicator)}</td>
                    <td>${escapeHtml((symbol && tf) ? `${symbol} ${tf}` : (symbol || tf || '-'))}</td>
                    <td>${eventCount}</td>
                    <td>${signalCount}</td>
                    <td>${escapeHtml(signalText)}</td>
                    <td class="small text-muted">${escapeHtml(lastSeen)}</td>
                    <td><span class="badge ${badgeCls}">${enabled ? 'ON' : 'OFF'}</span></td>
                    <td style="min-width: 170px;">
                        <div class="input-group input-group-sm">
                            <input type="number" class="form-control mt4la-lot-input" min="0.01" step="0.01" value="${escapeHtml(lot)}">
                            <button class="btn btn-outline-secondary mt4la-lot-save-btn" type="button">Apply</button>
                        </div>
                    </td>
                    <td>
                        <button class="btn btn-outline-primary btn-sm me-1 mt4la-view-btn">Logs</button>
                        <button class="btn btn-outline-${enabled ? 'danger' : 'success'} btn-sm mt4la-toggle-btn">${toggleLabel}</button>
                    </td>
                </tr>
            `;
        }).join('');
    }

    function renderInstances(state) {
        const allRows = Array.isArray((state || {}).instances) ? state.instances.slice() : [];
        const filter = String(instanceSearchText || '').trim().toLowerCase();
        const rows = filter
            ? allRows.filter((r) => {
                const ind = String((r || {}).indicator || '').toLowerCase();
                const sym = String((r || {}).symbol || '').toLowerCase();
                const tf = String((r || {}).timeframe || '').toLowerCase();
                return ind.includes(filter) || sym.includes(filter) || tf.includes(filter);
            })
            : allRows;
        if (!els.instanceBody) return;
        if (!allRows.length) {
            els.instanceBody.innerHTML = '<tr><td colspan="10" class="text-muted text-center py-3">No chart instance rows yet.</td></tr>';
            return;
        }
        if (!rows.length) {
            els.instanceBody.innerHTML = '<tr><td colspan="10" class="text-muted text-center py-3">No instances match your search.</td></tr>';
            return;
        }
        els.instanceBody.innerHTML = rows.map((r) => {
            const indicator = String(r.indicator || '').trim();
            const symbol = String(r.symbol || '').trim().toUpperCase();
            const timeframe = String(r.timeframe || '').trim().toUpperCase();
            const instanceKey = String(r.instance_key || '').trim();
            const eventCount = Number(r.event_count || 0);
            const signalCount = Number(r.signal_hint_count || 0);
            const lastSignal = String(r.last_signal_hint || '').trim().toUpperCase();
            const lastProfile = String(r.last_signal_profile || '').trim();
            const mode = String(r.automation_mode || 'inherit').trim().toLowerCase();
            const explicitEnabled = !!r.automation_enabled;
            const effectiveEnabled = !!r.effective_automation_enabled;
            const lastSeen = formatTs(r.last_seen || '');
            const signalText = lastSignal ? `${lastSignal}${lastProfile ? ` (${lastProfile})` : ''}` : '-';
            const lotRaw = Number(r.lot_size || 0);
            const lotFromState = Number.isFinite(lotRaw) && lotRaw > 0 ? lotRaw.toFixed(2) : '0.05';
            const draft = lotDraftByInstance.get(instanceKey);
            const lot = (typeof draft === 'string' && draft.length > 0) ? draft : lotFromState;
            const modeBadge = mode === 'explicit' ? 'text-bg-primary' : 'text-bg-light text-dark';
            const statusBadge = effectiveEnabled ? 'text-bg-success' : 'text-bg-secondary';
            const toggleLabel = effectiveEnabled ? 'Stop' : 'Start';
            return `
                <tr data-instance-key="${escapeHtml(instanceKey)}" data-indicator="${escapeHtml(indicator)}" data-symbol="${escapeHtml(symbol)}" data-timeframe="${escapeHtml(timeframe)}">
                    <td>${escapeHtml(indicator)}</td>
                    <td>${escapeHtml(symbol)}</td>
                    <td>${escapeHtml(timeframe)}</td>
                    <td>${eventCount}</td>
                    <td>${signalCount}</td>
                    <td>${escapeHtml(signalText)}</td>
                    <td class="small text-muted">${escapeHtml(lastSeen)}</td>
                    <td>
                        <span class="badge ${modeBadge} me-1">${mode === 'explicit' ? 'EXPLICIT' : 'INHERIT'}</span>
                        <span class="badge ${statusBadge}">${effectiveEnabled ? 'ON' : 'OFF'}</span>
                    </td>
                    <td style="min-width: 170px;">
                        <div class="input-group input-group-sm">
                            <input type="number" class="form-control mt4la-inst-lot-input" min="0.01" step="0.01" value="${escapeHtml(lot)}">
                            <button class="btn btn-outline-secondary mt4la-inst-lot-save-btn" type="button">Apply</button>
                        </div>
                    </td>
                    <td>
                        <button class="btn btn-outline-${effectiveEnabled ? 'danger' : 'success'} btn-sm mt4la-inst-toggle-btn">${toggleLabel}</button>
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

    function renderExecutionLogs(rows) {
        const items = Array.isArray(rows) ? rows.slice() : [];
        if (!els.execBody) return;
        if (!items.length) {
            els.execBody.innerHTML = '<tr><td colspan="9" class="text-muted text-center py-3">No execution logs yet.</td></tr>';
            return;
        }
        items.sort((a, b) => {
            const ta = Date.parse(String((a && (a.event_ts || a.ts)) || '')) || 0;
            const tb = Date.parse(String((b && (b.event_ts || b.ts)) || '')) || 0;
            return tb - ta;
        });
        els.execBody.innerHTML = items.map((r) => {
            const ts = formatTs((r && (r.event_ts || r.ts)) || '');
            const srcType = escapeHtml(String((r && r.source_type) || '-'));
            const srcName = escapeHtml(String((r && r.source_name) || '-'));
            const sym = String((r && r.symbol) || '').trim();
            const tf = String((r && r.timeframe) || '').trim();
            const symTf = escapeHtml((sym || tf) ? `${sym}${tf ? ` ${tf}` : ''}` : '-');
            const dir = escapeHtml(String((r && r.direction) || '-'));
            const lotRaw = Number((r && r.lot) || 0);
            const lot = Number.isFinite(lotRaw) && lotRaw > 0 ? lotRaw.toFixed(2) : '-';
            const status = escapeHtml(String((r && r.status) || '-'));
            const ticketRaw = Number((r && r.ticket) || 0);
            const ticket = ticketRaw > 0 ? String(ticketRaw) : '-';
            const msg = escapeHtml(String((r && r.message) || ''));
            return `<tr><td class="small text-muted">${ts}</td><td>${srcType}</td><td>${srcName}</td><td>${symTf}</td><td>${dir}</td><td>${lot}</td><td><span class="badge text-bg-secondary">${status}</span></td><td>${ticket}</td><td>${msg}</td></tr>`;
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
        renderInstances(data || {});
        latestExecLogs = Array.isArray((data || {}).execution_logs) ? (data.execution_logs).slice() : [];
        renderExecutionLogs(latestExecLogs);
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
        renderInstances(data || {});
        showAlert('MT4/MT5 log automation config saved.', 'success');
    }

    async function updateIndicatorSettings(indicator, options) {
        const payload = { indicator: String(indicator || '') };
        const opts = options || {};
        if (Object.prototype.hasOwnProperty.call(opts, 'enabled')) {
            payload.enabled = !!opts.enabled;
        }
        if (Object.prototype.hasOwnProperty.call(opts, 'lot_size')) {
            payload.lot_size = Number(opts.lot_size);
        }
        const data = await req('/api/mt4/log-automation/indicator-automation', {
            method: 'POST',
            body: JSON.stringify(payload)
        });
        if (data && data.ok === false) {
            throw new Error(String(data.error || 'indicator_settings_update_failed'));
        }
        latestState = data || latestState || {};
        renderStatus(latestState || {});
        renderIndicators(latestState || {});
        latestExecLogs = Array.isArray((latestState || {}).execution_logs) ? (latestState.execution_logs).slice() : latestExecLogs;
        renderExecutionLogs(latestExecLogs);
        return latestState;
    }

    async function toggleIndicator(indicator, enabledNext) {
        await updateIndicatorSettings(indicator, { enabled: !!enabledNext });
        showAlert(`${enabledNext ? 'Started' : 'Stopped'} automation for ${indicator}.`, 'success');
    }

    async function setIndicatorLot(indicator, lotValue) {
        await updateIndicatorSettings(indicator, { lot_size: Number(lotValue) });
        lotDraftByIndicator.delete(String(indicator || '').trim());
        showAlert(`Lot updated for ${indicator}.`, 'success');
    }

    async function updateInstanceSettings(indicator, symbol, timeframe, options) {
        const payload = {
            indicator: String(indicator || ''),
            symbol: String(symbol || '').toUpperCase(),
            timeframe: String(timeframe || '').toUpperCase()
        };
        const opts = options || {};
        if (Object.prototype.hasOwnProperty.call(opts, 'enabled')) {
            payload.enabled = !!opts.enabled;
        }
        if (Object.prototype.hasOwnProperty.call(opts, 'lot_size')) {
            payload.lot_size = Number(opts.lot_size);
        }
        const data = await req('/api/mt4/log-automation/instance-automation', {
            method: 'POST',
            body: JSON.stringify(payload)
        });
        if (data && data.ok === false) {
            throw new Error(String(data.error || 'instance_settings_update_failed'));
        }
        latestState = data || latestState || {};
        renderStatus(latestState || {});
        renderIndicators(latestState || {});
        renderInstances(latestState || {});
        latestExecLogs = Array.isArray((latestState || {}).execution_logs) ? (latestState.execution_logs).slice() : latestExecLogs;
        renderExecutionLogs(latestExecLogs);
        return latestState;
    }

    async function toggleInstance(indicator, symbol, timeframe, enabledNext) {
        await updateInstanceSettings(indicator, symbol, timeframe, { enabled: !!enabledNext });
        showAlert(`${enabledNext ? 'Started' : 'Stopped'} automation for ${indicator} ${symbol} ${timeframe}.`, 'success');
    }

    async function setInstanceLot(indicator, symbol, timeframe, lotValue, instanceKey) {
        await updateInstanceSettings(indicator, symbol, timeframe, { lot_size: Number(lotValue) });
        lotDraftByInstance.delete(String(instanceKey || '').trim());
        showAlert(`Instance lot updated for ${indicator} ${symbol} ${timeframe}.`, 'success');
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
                    return;
                }
                if (target.classList.contains('mt4la-lot-save-btn')) {
                    const lotInput = row.querySelector('.mt4la-lot-input');
                    const lotValue = parseLotInput(lotInput && lotInput.value);
                    if (lotValue === null) {
                        showAlert('Invalid lot size. Use a value > 0.', 'error');
                        return;
                    }
                    try {
                        await setIndicatorLot(indicator, lotValue);
                    } catch (err) {
                        showAlert(`Lot update failed: ${String(err.message || err)}`, 'error');
                    }
                }
            });
            els.indicatorBody.addEventListener('input', (ev) => {
                const target = ev.target;
                if (!target || !(target instanceof HTMLElement)) return;
                if (!target.classList.contains('mt4la-lot-input')) return;
                const row = target.closest('tr[data-indicator]');
                if (!row) return;
                const indicator = String(row.getAttribute('data-indicator') || '').trim();
                if (!indicator) return;
                lotDraftByIndicator.set(indicator, String(target.value || ''));
            });
        }

        if (els.instanceBody) {
            els.instanceBody.addEventListener('click', async (ev) => {
                const target = ev.target;
                if (!target || !(target instanceof HTMLElement)) return;
                const row = target.closest('tr[data-instance-key]');
                if (!row) return;
                const indicator = String(row.getAttribute('data-indicator') || '').trim();
                const symbol = String(row.getAttribute('data-symbol') || '').trim().toUpperCase();
                const timeframe = String(row.getAttribute('data-timeframe') || '').trim().toUpperCase();
                const instanceKey = String(row.getAttribute('data-instance-key') || '').trim();
                if (!indicator || !symbol || !timeframe) return;

                if (target.classList.contains('mt4la-inst-toggle-btn')) {
                    const all = Array.isArray((latestState || {}).instances) ? latestState.instances : [];
                    const current = all.find((x) => String((x || {}).instance_key || '').trim().toLowerCase() === instanceKey.toLowerCase());
                    const enabledNow = !!(current && current.effective_automation_enabled);
                    try {
                        await toggleInstance(indicator, symbol, timeframe, !enabledNow);
                    } catch (err) {
                        showAlert(`Instance toggle failed: ${String(err.message || err)}`, 'error');
                    }
                    return;
                }
                if (target.classList.contains('mt4la-inst-lot-save-btn')) {
                    const lotInput = row.querySelector('.mt4la-inst-lot-input');
                    const lotValue = parseLotInput(lotInput && lotInput.value);
                    if (lotValue === null) {
                        showAlert('Invalid lot size. Use a value > 0.', 'error');
                        return;
                    }
                    try {
                        await setInstanceLot(indicator, symbol, timeframe, lotValue, instanceKey);
                    } catch (err) {
                        showAlert(`Instance lot update failed: ${String(err.message || err)}`, 'error');
                    }
                }
            });
            els.instanceBody.addEventListener('input', (ev) => {
                const target = ev.target;
                if (!target || !(target instanceof HTMLElement)) return;
                if (!target.classList.contains('mt4la-inst-lot-input')) return;
                const row = target.closest('tr[data-instance-key]');
                if (!row) return;
                const instanceKey = String(row.getAttribute('data-instance-key') || '').trim();
                if (!instanceKey) return;
                lotDraftByInstance.set(instanceKey, String(target.value || ''));
            });
        }

        if (els.indicatorSearch) {
            els.indicatorSearch.addEventListener('input', () => {
                indicatorSearchText = String(els.indicatorSearch.value || '');
                renderIndicators(latestState || {});
            });
        }

        if (els.instanceSearch) {
            els.instanceSearch.addEventListener('input', () => {
                instanceSearchText = String(els.instanceSearch.value || '');
                renderInstances(latestState || {});
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
