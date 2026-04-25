(function () {
    'use strict';

    const els = {
        alert: document.getElementById('v2-alert'),
        refresh: document.getElementById('v2-refresh'),
        updated: document.getElementById('v2-updated'),
        mt4Count: document.getElementById('v2-mt4-count'),
        mt5Count: document.getElementById('v2-mt5-count'),
        openCount: document.getElementById('v2-open-count'),
        auditCount: document.getElementById('v2-audit-count'),
        openBody: document.getElementById('v2-open-body'),
        instanceBody: document.getElementById('v2-instance-body'),
        auditBody: document.getElementById('v2-audit-body'),
        openFilter: document.getElementById('v2-open-filter'),
        instanceFilter: document.getElementById('v2-instance-filter'),
        auditFilter: document.getElementById('v2-audit-filter')
    };

    let state = null;
    let timer = null;

    function esc(v) {
        return String(v == null ? '' : v)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function fmtTs(v) {
        const raw = String(v || '').trim();
        if (!raw) return '-';
        const dt = new Date(raw);
        if (Number.isNaN(dt.getTime())) return raw;
        return new Intl.DateTimeFormat('tr-TR', {
            day: '2-digit', month: '2-digit', year: 'numeric',
            hour: '2-digit', minute: '2-digit', second: '2-digit',
            hour12: false
        }).format(dt);
    }

    function fmtNum(v, digits) {
        const n = Number(v);
        return Number.isFinite(n) ? n.toFixed(digits == null ? 2 : digits) : '-';
    }

    function textMatch(row, query) {
        const q = String(query || '').trim().toLowerCase();
        if (!q) return true;
        return JSON.stringify(row || {}).toLowerCase().includes(q);
    }

    function parseLot(raw) {
        const n = Number(String(raw || '').trim().replace(',', '.'));
        return Number.isFinite(n) && n > 0 ? Number(n.toFixed(2)) : null;
    }

    async function loadState() {
        const res = await fetch('/api/indicator-bridge/state?limit=700', { credentials: 'same-origin' });
        const data = await res.json();
        if (!res.ok || !data || data.ok === false) {
            throw new Error((data && (data.error || data.detail)) || `HTTP ${res.status}`);
        }
        state = data;
        if (els.alert) els.alert.innerHTML = '';
        render();
    }

    async function updateInstanceSettings(row, options) {
        const payload = Object.assign({
            terminal_family: String(row.terminal_family || '').toLowerCase(),
            indicator: row.indicator || '',
            symbol: row.symbol || '',
            timeframe: row.timeframe || ''
        }, options || {});
        const res = await fetch('/api/indicator-bridge/instance-automation', {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data.ok === false) {
            throw new Error(data.error || data.detail || `HTTP ${res.status}`);
        }
        await loadState();
    }

    async function updateInstanceAutomation(row, enabled) {
        return updateInstanceSettings(row, { enabled: !!enabled });
    }

    function showError(err) {
        if (!els.alert) return;
        els.alert.innerHTML = `<div class="alert alert-danger">Indicator V2 state load failed: ${esc(err && err.message ? err.message : err)}</div>`;
    }

    function isV2Instance(row) {
        return String((row || {}).bridge_version || '').trim().toLowerCase() === 'v2';
    }

    function instanceMatchKey(row) {
        return [
            String((row || {}).terminal_family || '').trim().toUpperCase(),
            String((row || {}).indicator || (row || {}).source_name || '').trim().toLowerCase(),
            String((row || {}).symbol || '').trim().toUpperCase(),
            String((row || {}).timeframe || '').trim().toUpperCase()
        ].join('|');
    }

    function sourceTagMatchKey(row) {
        const tag = String((row || {}).source_tag || '').trim().toLowerCase();
        if (!tag) return '';
        const parts = tag.split('|').map(x => String(x || '').trim()).filter(Boolean);
        if (parts.length < 5 || !['mt4', 'mt5'].includes(parts[0])) return '';
        return [
            parts[0].toUpperCase(),
            parts[2],
            parts[3].toUpperCase(),
            parts[4].toUpperCase()
        ].join('|');
    }

    function auditMatchKey(row) {
        return sourceTagMatchKey(row) || instanceMatchKey(row);
    }

    function allInstances() {
        const mt4 = (((state || {}).mt4_monitor || {}).bot_rows || []).map(r => Object.assign({}, r, { terminal_family: 'MT4' }));
        const mt5 = (((state || {}).mt5_monitor || {}).bot_rows || []).map(r => Object.assign({}, r, { terminal_family: 'MT5' }));
        return mt4.concat(mt5).filter(isV2Instance);
    }

    function v2InstanceKeys() {
        const keys = new Set();
        allInstances().forEach(row => {
            const direct = instanceMatchKey(row);
            const tagged = sourceTagMatchKey(row);
            if (direct) keys.add(direct);
            if (tagged) keys.add(tagged);
        });
        return keys;
    }

    function openTrades() {
        const rows = (((state || {}).open_trades || {}).rows || []);
        if (!Array.isArray(rows)) return [];
        const keys = v2InstanceKeys();
        return rows.filter(row => keys.has(auditMatchKey(row)));
    }

    function auditRows() {
        const rows = (((state || {}).execution_logs || {}).rows || []);
        if (!Array.isArray(rows)) return [];
        const keys = v2InstanceKeys();
        return rows.filter(row => keys.has(auditMatchKey(row)));
    }

    function modeText(row) {
        const p = row.mode_advanced_v2_enabled ? (row.advanced_v2_policies || {}) : {};
        const adv2 = row.mode_advanced_v2_enabled
            ? `ADV_V2(${[
                p.conservative ? 'C' : '',
                p.balanced ? 'B' : '',
                p.advanced ? 'A' : ''
            ].filter(Boolean).join('') || 'B'})`
            : '';
        return [
            row.mode_advanced_enabled ? 'ADV' : '',
            adv2,
            row.mode_normal_enabled ? 'NORM' : '',
            row.mode_sync_enabled ? 'SYNC' : ''
        ].filter(Boolean).join(' | ') || '-';
    }

    function renderModeControls(row) {
        const p = row.mode_advanced_v2_enabled ? (row.advanced_v2_policies || {}) : {};
        const key = esc(row.instance_key || '');
        return `<div class="v2-mode-box">
            <label class="me-2 small"><input type="checkbox" class="form-check-input me-1 v2-mode-toggle" data-mode="advanced" data-instance="${key}" ${row.mode_advanced_enabled ? 'checked' : ''}>ADV</label>
            <label class="me-2 small"><input type="checkbox" class="form-check-input me-1 v2-mode-toggle" data-mode="normal" data-instance="${key}" ${row.mode_normal_enabled ? 'checked' : ''}>NORM</label>
            <div class="small mt-1">
                <span class="text-muted me-1">ADV_V2</span>
                <label class="me-1"><input type="checkbox" class="form-check-input me-1 v2-policy-toggle" data-policy="conservative" data-instance="${key}" ${p.conservative ? 'checked' : ''}>Con</label>
                <label class="me-1"><input type="checkbox" class="form-check-input me-1 v2-policy-toggle" data-policy="balanced" data-instance="${key}" ${p.balanced ? 'checked' : ''}>Bal</label>
                <label class="me-1"><input type="checkbox" class="form-check-input me-1 v2-policy-toggle" data-policy="advanced" data-instance="${key}" ${p.advanced ? 'checked' : ''}>Adv</label>
            </div>
        </div>`;
    }

    function stateClass(row) {
        const stateText = String((row || {}).state || '').toUpperCase();
        if (stateText === 'OPEN') return 'v2-state-open';
        if (stateText === 'STALE') return 'v2-state-stale';
        if (stateText === 'CONFLICT') return 'v2-state-conflict';
        return 'v2-state-idle';
    }

    function renderOpenTrades() {
        const q = els.openFilter ? els.openFilter.value : '';
        const rows = openTrades().filter(r => textMatch(r, q));
        if (!els.openBody) return;
        if (!rows.length) {
            els.openBody.innerHTML = '<tr><td colspan="9" class="text-center text-muted py-3">No open indicator trades.</td></tr>';
            return;
        }
        els.openBody.innerHTML = rows.map(row => {
            const pnl = Number(row.current_profit);
            const pnlCls = Number.isFinite(pnl) ? (pnl >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            return `<tr>
                <td class="v2-mono">${esc(row.ticket || '-')}</td>
                <td>${esc(String(row.terminal_family || '').toUpperCase())}</td>
                <td>${esc(row.indicator || row.source_name || '-')}</td>
                <td>${esc(row.symbol || '-')} ${esc(row.timeframe || '')}</td>
                <td>${esc(row.execution_mode || '-')}</td>
                <td class="${String(row.direction).toUpperCase() === 'BUY' ? 'trade-buy' : 'trade-sell'}">${esc(row.direction || '-')}</td>
                <td class="${pnlCls}">${fmtNum(row.current_profit, 2)}</td>
                <td>${esc(fmtTs(row.opened_at))}</td>
                <td class="v2-mono small">${esc(row.source_tag || '-')}</td>
            </tr>`;
        }).join('');
    }

    function renderInstances() {
        const q = els.instanceFilter ? els.instanceFilter.value : '';
        const rows = allInstances().filter(r => textMatch(r, q));
        if (!els.instanceBody) return;
        if (!rows.length) {
            els.instanceBody.innerHTML = '<tr><td colspan="12" class="text-center text-muted py-3">No bridge instances yet.</td></tr>';
            return;
        }
        els.instanceBody.innerHTML = rows.map(row => {
            const auto = row.effective_automation_enabled ? '<span class="badge text-bg-success">ON</span>' : '<span class="badge text-bg-secondary">OFF</span>';
            const isOn = !!row.effective_automation_enabled;
            const actionClass = isOn ? 'btn-outline-danger' : 'btn-outline-success';
            const actionText = isOn ? 'Stop' : 'Start';
            return `<tr>
                <td>${esc(fmtTs(row.last_seen))}</td>
                <td>${esc(String(row.terminal_family || '').toUpperCase())}</td>
                <td>${esc(row.indicator || '-')}<div class="small text-muted">${esc(row.bridge_version || '')}</div></td>
                <td>${esc(row.symbol || '-')} ${esc(row.timeframe || '')}</td>
                <td class="${stateClass(row)}">${esc(row.state || '-')}</td>
                <td>${auto}</td>
                <td>${renderModeControls(row)}<div class="small text-muted">${esc(modeText(row))}</div></td>
                <td>${esc(row.resolved_signal || '-')}</td>
                <td>${esc(row.confirmed_direction || '-')}</td>
                <td>${esc(row.pending_direction || '-')} ${row.pending_age_sec != null ? `<span class="small text-muted">${fmtNum(row.pending_age_sec, 0)}s</span>` : ''}</td>
                <td><input type="number" class="form-control form-control-sm v2-lot-input" min="0.01" step="0.01" data-instance="${esc(row.instance_key || '')}" value="${esc(fmtNum(row.lot_size || 0.1, 2))}" title="Lot size"></td>
                <td><button type="button" class="btn btn-sm ${actionClass} v2-instance-toggle" data-instance="${esc(row.instance_key || '')}" data-enabled="${isOn ? '0' : '1'}">${actionText}</button></td>
            </tr>`;
        }).join('');
    }

    function renderAudit() {
        const q = els.auditFilter ? els.auditFilter.value : '';
        const meaningful = auditRows().filter(row => {
            const status = String(row.status || '').toLowerCase();
            const msg = String(row.message || '').toLowerCase();
            return ['opened', 'closed', 'failed', 'partial'].some(x => status.includes(x) || msg.includes(x))
                || msg.includes('reconcile')
                || msg.includes('sl -> be')
                || msg.includes('tp');
        }).filter(r => textMatch(r, q)).slice(0, 300);
        if (!els.auditBody) return;
        if (!meaningful.length) {
            els.auditBody.innerHTML = '<tr><td colspan="10" class="text-center text-muted py-3">No meaningful audit rows yet.</td></tr>';
            return;
        }
        els.auditBody.innerHTML = meaningful.map(row => {
            const pnl = Number(row.realized_pnl);
            const pnlCls = Number.isFinite(pnl) ? (pnl >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            return `<tr>
                <td>${esc(row.status || row.trigger || '-')}<div class="small text-muted">${esc(fmtTs(row.event_ts || row.opened_at))}</div></td>
                <td>${esc(row.terminal_family || '-')}</td>
                <td>${esc(row.indicator || row.source_name || '-')}</td>
                <td>${esc(row.symbol || '-')} ${esc(row.timeframe || '')}</td>
                <td>${esc(row.execution_mode || '-')}</td>
                <td>${esc(row.direction || '-')}</td>
                <td>${fmtNum(row.lot, 2)}</td>
                <td class="v2-mono">${esc(row.ticket || '-')}</td>
                <td class="${pnlCls}">${fmtNum(row.realized_pnl, 2)}</td>
                <td>${esc(row.message || row.close_reason || '-')}</td>
            </tr>`;
        }).join('');
    }

    function render() {
        if (!state) return;
        const mt4Rows = allInstances().filter(row => String(row.terminal_family || '').toUpperCase() === 'MT4');
        const mt5Rows = allInstances().filter(row => String(row.terminal_family || '').toUpperCase() === 'MT5');
        if (els.updated) els.updated.textContent = `Updated: ${fmtTs(state.updated_at)}`;
        if (els.mt4Count) els.mt4Count.textContent = String(mt4Rows.length);
        if (els.mt5Count) els.mt5Count.textContent = String(mt5Rows.length);
        if (els.openCount) els.openCount.textContent = String(openTrades().length);
        if (els.auditCount) els.auditCount.textContent = String(auditRows().length);
        renderOpenTrades();
        renderInstances();
        renderAudit();
    }

    function schedule() {
        if (timer) clearInterval(timer);
        timer = setInterval(() => loadState().catch(showError), 5000);
    }

    [els.openFilter, els.instanceFilter, els.auditFilter].forEach(el => {
        if (el) el.addEventListener('input', render);
    });
    if (els.instanceBody) {
        els.instanceBody.addEventListener('click', ev => {
            const btn = ev.target.closest('.v2-instance-toggle');
            if (!btn) return;
            const key = btn.getAttribute('data-instance') || '';
            const row = allInstances().find(r => String(r.instance_key || '') === key);
            if (!row) return;
            btn.disabled = true;
            btn.textContent = '...';
            updateInstanceAutomation(row, btn.getAttribute('data-enabled') === '1').catch(err => {
                showError(err);
                btn.disabled = false;
                renderInstances();
            });
        });
        els.instanceBody.addEventListener('change', ev => {
            const input = ev.target.closest('.v2-lot-input');
            const modeToggle = ev.target.closest('.v2-mode-toggle');
            const policyToggle = ev.target.closest('.v2-policy-toggle');
            if (!input && !modeToggle && !policyToggle) return;
            if (modeToggle || policyToggle) {
                const el = modeToggle || policyToggle;
                const key = el.getAttribute('data-instance') || '';
                const row = allInstances().find(r => String(r.instance_key || '') === key);
                if (!row) return;
                const policies = row.mode_advanced_v2_enabled
                    ? Object.assign({ conservative: false, balanced: true, advanced: false }, row.advanced_v2_policies || {})
                    : { conservative: false, balanced: false, advanced: false };
                if (policyToggle) {
                    policies[policyToggle.getAttribute('data-policy') || 'balanced'] = !!policyToggle.checked;
                }
                const anyPolicy = !!(policies.conservative || policies.balanced || policies.advanced);
                const opts = {
                    mode_advanced_enabled: !!row.mode_advanced_enabled,
                    mode_normal_enabled: !!row.mode_normal_enabled,
                    mode_sync_enabled: !!row.mode_sync_enabled,
                    mode_advanced_v2_enabled: anyPolicy,
                    advanced_v2_policies: policies
                };
                if (modeToggle) {
                    const mode = modeToggle.getAttribute('data-mode') || '';
                    if (mode === 'advanced') opts.mode_advanced_enabled = !!modeToggle.checked;
                    if (mode === 'normal') opts.mode_normal_enabled = !!modeToggle.checked;
                    if (mode === 'sync') opts.mode_sync_enabled = !!modeToggle.checked;
                }
                el.disabled = true;
                updateInstanceSettings(row, opts).catch(err => {
                    showError(err);
                    el.disabled = false;
                    renderInstances();
                });
                return;
            }
            const key = input.getAttribute('data-instance') || '';
            const row = allInstances().find(r => String(r.instance_key || '') === key);
            const lot = parseLot(input.value);
            if (!row || lot == null) {
                showError(new Error('Invalid lot size'));
                renderInstances();
                return;
            }
            input.disabled = true;
            updateInstanceSettings(row, { lot_size: lot }).catch(err => {
                showError(err);
                input.disabled = false;
                renderInstances();
            });
        });
        els.instanceBody.addEventListener('keydown', ev => {
            const input = ev.target.closest('.v2-lot-input');
            if (input && ev.key === 'Enter') input.blur();
        });
    }
    if (els.refresh) els.refresh.addEventListener('click', () => loadState().catch(showError));
    loadState().catch(showError);
    schedule();
})();
