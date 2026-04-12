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
        mt5StopAll: document.getElementById('bridge-mt5-stop-all'),
        mt4ActiveOnly: document.getElementById('bridge-mt4-active-only'),
        mt5ActiveOnly: document.getElementById('bridge-mt5-active-only'),
        mt4FilterLastSeen: document.getElementById('bridge-mt4-filter-lastseen'),
        mt4FilterIndicator: document.getElementById('bridge-mt4-filter-indicator'),
        mt4FilterSymbolTf: document.getElementById('bridge-mt4-filter-symboltf'),
        mt4FilterDir: document.getElementById('bridge-mt4-filter-dir'),
        mt4FilterTicket: document.getElementById('bridge-mt4-filter-ticket'),
        mt4FilterState: document.getElementById('bridge-mt4-filter-state'),
        mt4FilterAuto: document.getElementById('bridge-mt4-filter-auto'),
        mt4FilterMode: document.getElementById('bridge-mt4-filter-mode'),
        mt4FilterLot: document.getElementById('bridge-mt4-filter-lot'),
        mt4FilterMaxP: document.getElementById('bridge-mt4-filter-maxp'),
        mt4FilterMaxL: document.getElementById('bridge-mt4-filter-maxl'),
        mt4FilterLive: document.getElementById('bridge-mt4-filter-live'),
        mt5FilterLastSeen: document.getElementById('bridge-mt5-filter-lastseen'),
        mt5FilterIndicator: document.getElementById('bridge-mt5-filter-indicator'),
        mt5FilterSymbolTf: document.getElementById('bridge-mt5-filter-symboltf'),
        mt5FilterDir: document.getElementById('bridge-mt5-filter-dir'),
        mt5FilterTicket: document.getElementById('bridge-mt5-filter-ticket'),
        mt5FilterState: document.getElementById('bridge-mt5-filter-state'),
        mt5FilterAuto: document.getElementById('bridge-mt5-filter-auto'),
        mt5FilterMode: document.getElementById('bridge-mt5-filter-mode'),
        mt5FilterLot: document.getElementById('bridge-mt5-filter-lot'),
        mt5FilterMaxP: document.getElementById('bridge-mt5-filter-maxp'),
        mt5FilterMaxL: document.getElementById('bridge-mt5-filter-maxl'),
        mt5FilterLive: document.getElementById('bridge-mt5-filter-live'),
        auditFilterEvent: document.getElementById('audit-filter-event'),
        auditFilterOpened: document.getElementById('audit-filter-opened'),
        auditFilterClosed: document.getElementById('audit-filter-closed'),
        auditFilterTerminal: document.getElementById('audit-filter-terminal'),
        auditFilterIndicator: document.getElementById('audit-filter-indicator'),
        auditFilterSymbolTf: document.getElementById('audit-filter-symboltf'),
        auditFilterDirection: document.getElementById('audit-filter-direction'),
        auditFilterLot: document.getElementById('audit-filter-lot'),
        auditFilterStatus: document.getElementById('audit-filter-status'),
        auditFilterMode: document.getElementById('audit-filter-mode'),
        auditFilterTicket: document.getElementById('audit-filter-ticket'),
        auditFilterOrder: document.getElementById('audit-filter-order'),
        auditFilterSession: document.getElementById('audit-filter-session'),
        auditFilterMaxP: document.getElementById('audit-filter-maxp'),
        auditFilterMaxL: document.getElementById('audit-filter-maxl'),
        auditFilterRealized: document.getElementById('audit-filter-realized'),
        auditFilterCloseReason: document.getElementById('audit-filter-close-reason'),
        auditFilterMessage: document.getElementById('audit-filter-message')
    };

    let latestState = null;
    let pollTimer = null;
    const monitorActiveOnly = { mt4: false, mt5: false };
    const modeUpdatePendingByInstance = {};
    const modePanelOpenByInstance = {};

    function isMonitorEditInProgress() {
        const active = document.activeElement;
        if (!(active instanceof HTMLElement)) return false;
        return active.classList.contains('bridge-lot-input')
            || active.classList.contains('bridge-mode-lot-advanced')
            || active.classList.contains('bridge-mode-lot-normal')
            || active.classList.contains('bridge-mode-lot-sync')
            || active.classList.contains('bridge-sync-direction')
            || active.classList.contains('bridge-sync-entry')
            || active.classList.contains('bridge-sync-exit');
    }

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
        const rows = Array.isArray(monitor.bot_rows) ? monitor.bot_rows.slice() : [];
        const fam = String(family || 'mt4').toLowerCase();
        if (!monitorActiveOnly[fam]) return rows;
        return rows.filter((r) => !!(r && r.effective_automation_enabled));
    }

    function monitorFilterValues(family) {
        const isMt5 = String(family || '').toLowerCase() === 'mt5';
        return {
            lastSeen: (isMt5 ? els.mt5FilterLastSeen : els.mt4FilterLastSeen)?.value || '',
            indicator: (isMt5 ? els.mt5FilterIndicator : els.mt4FilterIndicator)?.value || '',
            symbolTf: (isMt5 ? els.mt5FilterSymbolTf : els.mt4FilterSymbolTf)?.value || '',
            state: (isMt5 ? els.mt5FilterState : els.mt4FilterState)?.value || '',
            auto: (isMt5 ? els.mt5FilterAuto : els.mt4FilterAuto)?.value || '',
            mode: (isMt5 ? els.mt5FilterMode : els.mt4FilterMode)?.value || '',
            lot: (isMt5 ? els.mt5FilterLot : els.mt4FilterLot)?.value || ''
        };
    }

    function monitorFilteredRows(family) {
        const rows = monitorRows(family);
        const f = monitorFilterValues(family);
        return rows.filter((row) => {
            const indicator = String(row.indicator || '').trim();
            const symbolTf = `${String(row.symbol || '').trim().toUpperCase()} ${String(row.timeframe || '').trim().toUpperCase()}`.trim();
            const state = String(row.state || (row.has_open_ladder ? 'OPEN' : 'IDLE')).toUpperCase();
            const auto = !!row.effective_automation_enabled ? 'ON' : 'OFF';
            const mode = [
                row.mode_advanced_enabled ? 'ADVANCED' : '',
                row.mode_normal_enabled ? 'NORMAL' : '',
                row.mode_sync_enabled ? 'SYNC' : ''
            ].filter(Boolean).join('|');
            return textMatch(formatTs(row.last_seen), f.lastSeen)
                && textMatch(indicator, f.indicator)
                && textMatch(symbolTf, f.symbolTf)
                && textMatch(state, f.state)
                && textMatch(auto, f.auto)
                && textMatch(mode, f.mode)
                && textMatch(formatNum(row.lot_size, 2), f.lot);
        });
    }

    function auditRows() {
        const audit = (latestState && latestState.execution_logs && typeof latestState.execution_logs === 'object') ? latestState.execution_logs : {};
        return Array.isArray(audit.rows) ? audit.rows.slice() : [];
    }

    function textMatch(value, query) {
        const q = String(query || '').trim().toLowerCase();
        if (!q) return true;
        return String(value || '').toLowerCase().includes(q);
    }

    function auditFilteredRows() {
        const rows = auditRows();
        const filters = {
            event: (els.auditFilterEvent && els.auditFilterEvent.value) || '',
            opened: (els.auditFilterOpened && els.auditFilterOpened.value) || '',
            closed: (els.auditFilterClosed && els.auditFilterClosed.value) || '',
            terminal: (els.auditFilterTerminal && els.auditFilterTerminal.value) || '',
            indicator: (els.auditFilterIndicator && els.auditFilterIndicator.value) || '',
            symboltf: (els.auditFilterSymbolTf && els.auditFilterSymbolTf.value) || '',
            direction: (els.auditFilterDirection && els.auditFilterDirection.value) || '',
            lot: (els.auditFilterLot && els.auditFilterLot.value) || '',
            status: (els.auditFilterStatus && els.auditFilterStatus.value) || '',
            mode: (els.auditFilterMode && els.auditFilterMode.value) || '',
            ticket: (els.auditFilterTicket && els.auditFilterTicket.value) || '',
            order: (els.auditFilterOrder && els.auditFilterOrder.value) || '',
            session: (els.auditFilterSession && els.auditFilterSession.value) || '',
            maxp: (els.auditFilterMaxP && els.auditFilterMaxP.value) || '',
            maxl: (els.auditFilterMaxL && els.auditFilterMaxL.value) || '',
            realized: (els.auditFilterRealized && els.auditFilterRealized.value) || '',
            closeReason: (els.auditFilterCloseReason && els.auditFilterCloseReason.value) || '',
            message: (els.auditFilterMessage && els.auditFilterMessage.value) || ''
        };
        return rows.filter((row) => {
            const symbolTf = `${String(row.symbol || '')} ${String(row.timeframe || '')}`.trim();
            return textMatch(formatTs(row.event_ts), filters.event)
                && textMatch(formatTs(row.opened_at), filters.opened)
                && textMatch(formatTs(row.closed_at), filters.closed)
                && textMatch(row.terminal_family, filters.terminal)
                && textMatch(row.indicator || row.source_name, filters.indicator)
                && textMatch(symbolTf, filters.symboltf)
                && textMatch(row.direction, filters.direction)
                && textMatch(formatNum(row.lot, 2), filters.lot)
                && textMatch(String(row.status || '').toUpperCase(), filters.status)
                && textMatch(String(row.execution_mode || '').toUpperCase(), filters.mode)
                && textMatch(row.ticket, filters.ticket)
                && textMatch(row.order_number, filters.order)
                && textMatch(row.session_name, filters.session)
                && textMatch(formatNum(row.max_profit, 2), filters.maxp)
                && textMatch(formatNum(row.max_loss, 2), filters.maxl)
                && textMatch(formatNum(row.realized_pnl, 2), filters.realized)
                && textMatch(row.close_reason, filters.closeReason)
                && textMatch(row.message, filters.message);
        });
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
        if (els.mt4ActiveOnly) {
            els.mt4ActiveOnly.textContent = `Active Only: ${monitorActiveOnly.mt4 ? 'ON' : 'OFF'}`;
            els.mt4ActiveOnly.className = `btn btn-sm ${monitorActiveOnly.mt4 ? 'btn-primary' : 'btn-outline-primary'}`;
        }
        if (els.mt5ActiveOnly) {
            els.mt5ActiveOnly.textContent = `Active Only: ${monitorActiveOnly.mt5 ? 'ON' : 'OFF'}`;
            els.mt5ActiveOnly.className = `btn btn-sm ${monitorActiveOnly.mt5 ? 'btn-primary' : 'btn-outline-primary'}`;
        }
    }

    function renderMonitor(family) {
        const rows = monitorFilteredRows(family);
        const body = String(family).toLowerCase() === 'mt5' ? els.mt5Body : els.mt4Body;
        if (!body) return;
        if (!rows.length) {
            const fam = String(family).toLowerCase();
            const msg = monitorActiveOnly[fam]
                ? 'No active automation instances for current filter.'
                : 'No bridge charts registered yet.';
            body.innerHTML = `<tr><td colspan="8" class="text-muted text-center py-3">${escapeHtml(msg)}</td></tr>`;
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
            const modeSync = !!row.mode_sync_enabled;
            const modeSummary = [modeAdvanced ? 'ADV' : '', modeNormal ? 'NORM' : '', modeSync ? 'SYNC' : '']
                .filter(Boolean)
                .join(' | ') || 'NO MODE';
            const modeLots = (row.mode_lots && typeof row.mode_lots === 'object') ? row.mode_lots : {};
            const modeAdvancedLot = Number(modeLots.advanced || lotValue || 0);
            const modeNormalLot = Number(modeLots.normal || lotValue || 0);
            const modeSyncLot = Number(modeLots.sync || lotValue || 0);
            const syncCfg = (row.sync && typeof row.sync === 'object') ? row.sync : {};
            const syncDirectionTf = String(syncCfg.direction_tf || 'M5').toUpperCase();
            const syncEntryTf = String(syncCfg.entry_tf || 'M1').toUpperCase();
            const syncExitTf = String(syncCfg.exit_tf || 'M1').toUpperCase();
            const syncReentryEnabled = !!syncCfg.reentry_enabled;
            const instanceKey = String(row.instance_key || '').trim();
            const instanceDomKey = `${String(family).toLowerCase()}|${String(instanceKey).toLowerCase()}`;
            const isModePanelOpen = !!modePanelOpenByInstance[instanceDomKey];
            return `
                <tr data-family="${escapeHtml(String(family).toLowerCase())}" data-instance-key="${escapeHtml(instanceKey)}" data-indicator="${escapeHtml(indicator)}" data-symbol="${escapeHtml(symbol)}" data-timeframe="${escapeHtml(timeframe)}">
                    <td>${escapeHtml(formatTs(row.last_seen))}</td>
                    <td>${escapeHtml(indicator)}</td>
                    <td>${escapeHtml(symbol)} ${escapeHtml(timeframe)}</td>
                    <td><span class="badge ${badgeCls}">${escapeHtml(state)}</span></td>
                    <td><span class="badge ${autoCls}">${enabled ? 'ON' : 'OFF'}</span></td>
                    <td>
                        <details class="border rounded p-2 bg-light-subtle bridge-mode-panel" data-instance-dom-key="${escapeHtml(instanceDomKey)}" ${isModePanelOpen ? 'open' : ''}>
                            <summary class="small fw-semibold">${escapeHtml(modeSummary)}</summary>
                            <div class="d-flex flex-column gap-2 mt-2">
                                <label class="form-check-label small">
                                    <input type="checkbox" class="form-check-input me-1 bridge-mode-toggle" data-mode="advanced" ${modeAdvanced ? 'checked' : ''}>
                                    Advanced
                                </label>
                                <label class="form-check-label small">
                                    <input type="checkbox" class="form-check-input me-1 bridge-mode-toggle" data-mode="normal" ${modeNormal ? 'checked' : ''}>
                                    Normal
                                </label>
                                <label class="form-check-label small">
                                    <input type="checkbox" class="form-check-input me-1 bridge-mode-toggle" data-mode="sync" ${modeSync ? 'checked' : ''}>
                                    Sync
                                </label>
                                <div class="row g-1 align-items-center border-top pt-2 mt-1">
                                    <div class="col-12 small text-muted">Mode Lots</div>
                                    <div class="col-4 small text-muted">Adv</div>
                                    <div class="col-8">
                                        <input type="number" class="form-control form-control-sm bridge-mode-lot-advanced" min="0.01" step="0.01" value="${Number.isFinite(modeAdvancedLot) && modeAdvancedLot > 0 ? escapeHtml(modeAdvancedLot.toFixed(2)) : '0.05'}">
                                    </div>
                                    <div class="col-4 small text-muted">Norm</div>
                                    <div class="col-8">
                                        <input type="number" class="form-control form-control-sm bridge-mode-lot-normal" min="0.01" step="0.01" value="${Number.isFinite(modeNormalLot) && modeNormalLot > 0 ? escapeHtml(modeNormalLot.toFixed(2)) : '0.05'}">
                                    </div>
                                    <div class="col-4 small text-muted">Sync</div>
                                    <div class="col-8">
                                        <input type="number" class="form-control form-control-sm bridge-mode-lot-sync" min="0.01" step="0.01" value="${Number.isFinite(modeSyncLot) && modeSyncLot > 0 ? escapeHtml(modeSyncLot.toFixed(2)) : '0.05'}">
                                    </div>
                                    <div class="col-12 text-end">
                                        <button type="button" class="btn btn-outline-secondary btn-sm bridge-save-mode-lots-btn">Save Mode Lots</button>
                                    </div>
                                </div>
                                <div class="row g-1 align-items-center">
                                    <div class="col-4 small text-muted">Direction TF</div>
                                    <div class="col-8">
                                        <select class="form-select form-select-sm bridge-sync-direction">
                                            ${['M1','M5','M15','M30','H1','H4'].map((x)=>`<option value="${x}" ${x===syncDirectionTf?'selected':''}>${x}</option>`).join('')}
                                        </select>
                                    </div>
                                    <div class="col-4 small text-muted">Entry TF</div>
                                    <div class="col-8">
                                        <select class="form-select form-select-sm bridge-sync-entry">
                                            ${['M1','M5','M15','M30','H1'].map((x)=>`<option value="${x}" ${x===syncEntryTf?'selected':''}>${x}</option>`).join('')}
                                        </select>
                                    </div>
                                    <div class="col-4 small text-muted">Exit TF</div>
                                    <div class="col-8">
                                        <select class="form-select form-select-sm bridge-sync-exit">
                                            ${['M1','M5','M15','M30','H1'].map((x)=>`<option value="${x}" ${x===syncExitTf?'selected':''}>${x}</option>`).join('')}
                                        </select>
                                    </div>
                                    <div class="col-6">
                                        <label class="form-check-label small">
                                            <input type="checkbox" class="form-check-input me-1 bridge-sync-reentry" ${syncReentryEnabled ? 'checked' : ''}>
                                            Re-entry
                                        </label>
                                    </div>
                                    <div class="col-6 text-end">
                                        <button type="button" class="btn btn-outline-secondary btn-sm bridge-save-sync-btn">Save Sync</button>
                                    </div>
                                </div>
                            </div>
                        </details>
                    </td>
                    <td>
                        <div class="input-group input-group-sm" style="min-width:150px;">
                            <input type="number" class="form-control bridge-lot-input" min="0.01" step="0.01" value="${Number.isFinite(lotValue) && lotValue > 0 ? escapeHtml(lotValue.toFixed(2)) : '0.05'}">
                            <button type="button" class="btn btn-outline-secondary bridge-save-lot-btn">Save</button>
                        </div>
                    </td>
                    <td>
                        <button type="button" class="btn btn-sm ${enabled ? 'btn-outline-danger' : 'btn-outline-success'} bridge-toggle-btn">${enabled ? 'Stop' : 'Start'}</button>
                    </td>
                </tr>
            `;
        }).join('');
    }

    function renderAudit() {
        const rows = auditFilteredRows();
        if (!els.auditBody) return;
        if (!rows.length) {
            els.auditBody.innerHTML = '<tr><td colspan="18" class="text-muted text-center py-3">No indicator execution rows match current filters.</td></tr>';
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
                <td>${row.order_number ? escapeHtml(String(row.order_number)) : '-'}</td>
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

    async function loadState(showToastOnError = false, forceMonitorRender = false) {
        try {
            latestState = await req('/api/indicator-bridge/state?limit=500&active_only=0');
            if (!forceMonitorRender && isMonitorEditInProgress()) {
                refreshSummary();
                renderAudit();
            } else {
                renderAll();
            }
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

    function rowModeValues(rowEl) {
        const advancedEl = rowEl.querySelector('.bridge-mode-toggle[data-mode="advanced"]');
        const normalEl = rowEl.querySelector('.bridge-mode-toggle[data-mode="normal"]');
        const syncEl = rowEl.querySelector('.bridge-mode-toggle[data-mode="sync"]');
        return {
            advancedEl,
            normalEl,
            syncEl,
            advanced: !!(advancedEl && advancedEl.checked),
            normal: !!(normalEl && normalEl.checked),
            sync: !!(syncEl && syncEl.checked)
        };
    }

    function setModeInputsDisabled(rowEl, disabled) {
        const toggles = rowEl.querySelectorAll('.bridge-mode-toggle');
        toggles.forEach((el) => { el.disabled = !!disabled; });
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
        if (target.classList.contains('bridge-save-mode-lots-btn')) {
            const advancedInput = row.querySelector('.bridge-mode-lot-advanced');
            const normalInput = row.querySelector('.bridge-mode-lot-normal');
            const syncInput = row.querySelector('.bridge-mode-lot-sync');
            const advancedLot = parseLotInput(advancedInput && advancedInput.value);
            const normalLot = parseLotInput(normalInput && normalInput.value);
            const syncLot = parseLotInput(syncInput && syncInput.value);
            if (advancedLot === null || normalLot === null || syncLot === null) {
                showAlert('Invalid mode lots. Use values > 0.', 'error');
                return;
            }
            updateInstance(family, indicator, symbol, timeframe, {
                mode_advanced_lot: advancedLot,
                mode_normal_lot: normalLot,
                mode_sync_lot: syncLot
            })
                .then(() => showAlert(`Mode lots updated for ${indicator} ${symbol} ${timeframe}.`, 'success'))
                .catch((err) => showAlert(`Mode lot update failed: ${String(err.message || err)}`, 'error'));
            return;
        }
        if (target.classList.contains('bridge-mode-toggle')) {
            const mode = String(target.getAttribute('data-mode') || '').trim().toLowerCase();
            if (mode !== 'advanced' && mode !== 'normal' && mode !== 'sync') return;
            const instanceKey = String(row.getAttribute('data-instance-key') || '').trim().toLowerCase();
            if (modeUpdatePendingByInstance[instanceKey]) return;
            const finalState = rowModeValues(row); // keep multi-select; send all three each update
            const payload = {
                mode_advanced_enabled: !!finalState.advanced,
                mode_normal_enabled: !!finalState.normal,
                mode_sync_enabled: !!finalState.sync
            };
            modeUpdatePendingByInstance[instanceKey] = true;
            setModeInputsDisabled(row, true);
            updateInstance(family, indicator, symbol, timeframe, payload)
                .then(() => showAlert(`Mode updated (${mode.toUpperCase()}) for ${indicator} ${symbol} ${timeframe}.`, 'success'))
                .catch((err) => {
                    showAlert(`Mode update failed: ${String(err.message || err)}`, 'error');
                    loadState(false).catch(() => {});
                })
                .finally(() => {
                    modeUpdatePendingByInstance[instanceKey] = false;
                    setModeInputsDisabled(row, false);
                });
            return;
        }
        if (target.classList.contains('bridge-save-sync-btn')) {
            const directionEl = row.querySelector('.bridge-sync-direction');
            const entryEl = row.querySelector('.bridge-sync-entry');
            const exitEl = row.querySelector('.bridge-sync-exit');
            const reentryEl = row.querySelector('.bridge-sync-reentry');
            const payload = {
                sync_direction_tf: String(directionEl && directionEl.value || 'M5').toUpperCase(),
                sync_entry_tf: String(entryEl && entryEl.value || 'M1').toUpperCase(),
                sync_exit_tf: String(exitEl && exitEl.value || 'M1').toUpperCase(),
                sync_reentry_enabled: !!(reentryEl && reentryEl.checked)
            };
            updateInstance(family, indicator, symbol, timeframe, payload)
                .then(() => showAlert(`Sync config updated for ${indicator} ${symbol} ${timeframe}.`, 'success'))
                .catch((err) => {
                    showAlert(`Sync update failed: ${String(err.message || err)}`, 'error');
                    loadState(false).catch(() => {});
                });
        }
    }

    function handleMonitorToggle(ev) {
        const target = ev.target;
        if (!(target instanceof HTMLElement)) return;
        if (!(target instanceof HTMLDetailsElement)) return;
        if (!target.classList.contains('bridge-mode-panel')) return;
        const domKey = String(target.getAttribute('data-instance-dom-key') || '').trim().toLowerCase();
        if (!domKey) return;
        modePanelOpenByInstance[domKey] = !!target.open;
    }

    async function init() {
        if (els.refreshBtn) {
            els.refreshBtn.addEventListener('click', async () => {
                try {
                    await loadState(true, true);
                    showAlert('Refreshed.', 'info');
                } catch (_) { /* already handled */ }
            });
        }
        if (els.mt4Body) els.mt4Body.addEventListener('click', handleMonitorClick);
        if (els.mt5Body) els.mt5Body.addEventListener('click', handleMonitorClick);
        if (els.mt4Body) els.mt4Body.addEventListener('toggle', handleMonitorToggle, true);
        if (els.mt5Body) els.mt5Body.addEventListener('toggle', handleMonitorToggle, true);
        [
            els.mt4FilterLastSeen, els.mt4FilterIndicator, els.mt4FilterSymbolTf,
            els.mt4FilterState, els.mt4FilterAuto, els.mt4FilterMode, els.mt4FilterLot
        ].forEach((el) => {
            if (!el) return;
            el.addEventListener('input', () => renderMonitor('mt4'));
        });
        [
            els.mt5FilterLastSeen, els.mt5FilterIndicator, els.mt5FilterSymbolTf,
            els.mt5FilterState, els.mt5FilterAuto, els.mt5FilterMode, els.mt5FilterLot
        ].forEach((el) => {
            if (!el) return;
            el.addEventListener('input', () => renderMonitor('mt5'));
        });
        [
            els.auditFilterEvent, els.auditFilterOpened, els.auditFilterClosed, els.auditFilterTerminal,
            els.auditFilterIndicator, els.auditFilterSymbolTf, els.auditFilterDirection, els.auditFilterLot,
            els.auditFilterStatus, els.auditFilterMode, els.auditFilterTicket, els.auditFilterOrder,
            els.auditFilterSession, els.auditFilterMaxP, els.auditFilterMaxL, els.auditFilterRealized,
            els.auditFilterCloseReason, els.auditFilterMessage
        ].forEach((el) => {
            if (!el) return;
            el.addEventListener('input', () => renderAudit());
        });
        if (els.mt4StartAll) els.mt4StartAll.addEventListener('click', () => bulkSetFamily('mt4', true).catch((err) => showAlert(`MT4 start failed: ${String(err.message || err)}`, 'error')));
        if (els.mt4StopAll) els.mt4StopAll.addEventListener('click', () => bulkSetFamily('mt4', false).catch((err) => showAlert(`MT4 stop failed: ${String(err.message || err)}`, 'error')));
        if (els.mt5StartAll) els.mt5StartAll.addEventListener('click', () => bulkSetFamily('mt5', true).catch((err) => showAlert(`MT5 start failed: ${String(err.message || err)}`, 'error')));
        if (els.mt5StopAll) els.mt5StopAll.addEventListener('click', () => bulkSetFamily('mt5', false).catch((err) => showAlert(`MT5 stop failed: ${String(err.message || err)}`, 'error')));
        if (els.mt4ActiveOnly) els.mt4ActiveOnly.addEventListener('click', () => { monitorActiveOnly.mt4 = !monitorActiveOnly.mt4; renderAll(); });
        if (els.mt5ActiveOnly) els.mt5ActiveOnly.addEventListener('click', () => { monitorActiveOnly.mt5 = !monitorActiveOnly.mt5; renderAll(); });

        try {
            await loadState(true, true);
        } catch (_) {
            return;
        }

        if (pollTimer) clearInterval(pollTimer);
        pollTimer = setInterval(() => {
            loadState(false, false).catch(() => {});
        }, 5000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
