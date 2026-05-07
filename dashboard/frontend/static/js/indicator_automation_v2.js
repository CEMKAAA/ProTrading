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
        riskDailyTarget: document.getElementById('v2-risk-daily-target'),
        riskDailyMaxLoss: document.getElementById('v2-risk-daily-max-loss'),
        riskCatastrophe: document.getElementById('v2-risk-catastrophe'),
        riskDailyStatus: document.getElementById('v2-risk-daily-status'),
        riskSave: document.getElementById('v2-risk-save'),
        riskTargetOverride: document.getElementById('v2-risk-target-override'),
        riskStatus: document.getElementById('v2-risk-status'),
        dualNoneCloseToggle: document.getElementById('v2-dual-none-close-toggle'),
        dualNoneCloseStatus: document.getElementById('v2-dual-none-close-status'),
        dualGatePanel: document.getElementById('v2-dual-gate-panel'),
        dualGateBody: document.getElementById('v2-dual-gate-body'),
        entryExitPanel: document.getElementById('v2-entry-exit-panel'),
        entryExitBody: document.getElementById('v2-entry-exit-body'),
        openBody: document.getElementById('v2-open-body'),
        instanceBody: document.getElementById('v2-instance-body'),
        auditBody: document.getElementById('v2-audit-body'),
        openFilter: document.getElementById('v2-open-filter'),
        instanceFilter: document.getElementById('v2-instance-filter'),
        auditFilter: document.getElementById('v2-audit-filter')
    };

    let state = null;
    let timer = null;
    let uiTimer = null;

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

    function parseMoney(raw) {
        const n = Number(String(raw == null ? '' : raw).trim().replace(',', '.'));
        return Number.isFinite(n) && n >= 0 ? Number(n.toFixed(2)) : null;
    }

    async function loadState() {
        const res = await fetch('/api/indicator-bridge/state?limit=700', { credentials: 'same-origin' });
        const data = await res.json();
        if (!res.ok || !data || data.ok === false) {
            throw new Error((data && (data.error || data.detail)) || `HTTP ${res.status}`);
        }
        state = data;
        state._client_loaded_at_ms = Date.now();
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

    async function saveRiskSettings() {
        const dailyTarget = parseMoney(els.riskDailyTarget ? els.riskDailyTarget.value : '');
        const dailyMaxLoss = parseMoney(els.riskDailyMaxLoss ? els.riskDailyMaxLoss.value : '');
        if (dailyTarget == null || dailyMaxLoss == null) {
            throw new Error('Invalid daily target or max loss');
        }
        if (els.riskSave) {
            els.riskSave.disabled = true;
            els.riskSave.textContent = 'Saving...';
        }
        try {
            const res = await fetch('/api/indicator-bridge/risk-settings', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    daily_target_usd: dailyTarget,
                    daily_max_loss_usd: dailyMaxLoss
                })
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) {
                throw new Error(data.error || data.detail || `HTTP ${res.status}`);
            }
            state = data;
            showNotice('Risk settings saved. New trades will use the updated daily guard and catastrophe SL.', 'success');
            render();
        } finally {
            if (els.riskSave) {
                els.riskSave.disabled = false;
                els.riskSave.textContent = 'Save Risk Settings';
            }
        }
    }

    async function setDailyTargetOverride(enabled) {
        if (els.riskTargetOverride) {
            els.riskTargetOverride.disabled = true;
            els.riskTargetOverride.textContent = enabled ? 'Enabling...' : 'Disabling...';
        }
        try {
            const res = await fetch('/api/indicator-bridge/risk-settings', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ daily_target_guard_bypass_today: !!enabled })
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) {
                throw new Error(data.error || data.detail || `HTTP ${res.status}`);
            }
            state = data;
            showNotice(enabled
                ? 'Daily target guard bypassed for today. Max daily loss guard is still active.'
                : 'Daily target guard restored for today.',
                enabled ? 'warning' : 'success');
            render();
        } finally {
            if (els.riskTargetOverride) {
                els.riskTargetOverride.disabled = false;
            }
        }
    }

    async function updateInstanceAutomation(row, enabled) {
        return updateInstanceSettings(row, { enabled: !!enabled });
    }

    async function saveDualGateSettings(enabled) {
        const res = await fetch('/api/indicator-bridge/dual-gate-settings', {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ none_close_enabled: !!enabled })
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data.ok === false) {
            throw new Error(data.error || data.detail || `HTTP ${res.status}`);
        }
        state = data;
        state._client_loaded_at_ms = Date.now();
        showNotice(`Dual NONE timeout close ${enabled ? 'enabled' : 'disabled'}.`, 'success');
        render();
    }

    function showError(err) {
        if (!els.alert) return;
        els.alert.innerHTML = `<div class="alert alert-danger">Indicator V2 state load failed: ${esc(err && err.message ? err.message : err)}</div>`;
    }

    function showNotice(message, kind) {
        if (!els.alert) return;
        const cls = kind === 'success' ? 'alert-success' : (kind === 'warning' ? 'alert-warning' : 'alert-info');
        els.alert.innerHTML = `<div class="alert ${cls}">${esc(message)}</div>`;
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

    function boolish(v) {
        if (v === true || v === 1) return true;
        const s = String(v == null ? '' : v).trim().toLowerCase();
        return ['1', 'true', 'yes', 'on'].includes(s);
    }

    function hasDisplayableBridgeConnection(row) {
        const stateText = String((row || {}).state || '').trim().toUpperCase();
        return boolish((row || {}).has_live_heartbeat)
            || boolish((row || {}).has_open_ladder)
            || stateText === 'OPEN'
            || stateText === 'IDLE';
    }

    function displayInstances() {
        return allInstances().filter(hasDisplayableBridgeConnection);
    }

    function normDirection(v) {
        const s = String(v == null ? '' : v).trim().toUpperCase();
        if (['BUY', 'SELL', 'NONE', 'AMBIGUOUS', 'WAIT'].includes(s)) return s;
        return '';
    }

    function isDirectional(v) {
        const s = normDirection(v);
        return s === 'BUY' || s === 'SELL';
    }

    function signalChipClass(dir) {
        const s = normDirection(dir);
        if (s === 'BUY') return 'v2-signal-buy';
        if (s === 'SELL') return 'v2-signal-sell';
        if (s === 'AMBIGUOUS') return 'v2-signal-ambiguous';
        if (s === 'WAIT') return 'v2-signal-wait';
        return 'v2-signal-idle';
    }

    function displaySignal(dir) {
        const s = normDirection(dir);
        return s || 'NONE';
    }

    function tfRank(tf) {
        const order = { M1: 1, M5: 5, M15: 15, M30: 30, H1: 60, H4: 240, D1: 1440, W1: 10080, MN1: 43200 };
        const key = String(tf || '').trim().toUpperCase();
        return order[key] || 999999;
    }

    function instanceSortKey(row) {
        return [
            String((row || {}).terminal_family || '').trim().toUpperCase(),
            String((row || {}).symbol || '').trim().toUpperCase(),
            String(tfRank((row || {}).timeframe)).padStart(6, '0'),
            String((row || {}).indicator || (row || {}).source_name || '').trim().toLowerCase(),
            String((row || {}).secondary_indicator || '').trim().toLowerCase(),
            String((row || {}).instance_key || '').trim().toLowerCase()
        ].join('|');
    }

    function livePendingAgeSec(row) {
        const base = Number((row || {}).pending_age_sec);
        if (!Number.isFinite(base)) return null;
        const loaded = Number((state || {})._client_loaded_at_ms || 0);
        const extra = loaded > 0 ? Math.max(0, (Date.now() - loaded) / 1000) : 0;
        return Math.max(0, base + extra);
    }

    function dualSoloIndicatorName(indicator, role) {
        const base = String(indicator || '').trim() || (role === 'main' ? 'Main' : 'Secondary');
        const suffix = role === 'main' ? 'Main Solo' : 'Secondary Solo';
        return base.includes(`(${suffix})`) ? base : `${base} (${suffix})`;
    }

    function findInstanceByIdentity(terminalFamily, indicator, symbol, timeframe) {
        const fam = String(terminalFamily || '').trim().toLowerCase();
        const ind = String(indicator || '').trim().toLowerCase();
        const sym = String(symbol || '').trim().toUpperCase();
        const tf = String(timeframe || '').trim().toUpperCase();
        return allInstances().find(r =>
            String((r || {}).terminal_family || '').trim().toLowerCase() === fam
            && String((r || {}).indicator || '').trim().toLowerCase() === ind
            && String((r || {}).symbol || '').trim().toUpperCase() === sym
            && String((r || {}).timeframe || '').trim().toUpperCase() === tf
        ) || null;
    }

    function dualSoloRow(parent, role) {
        const indicator = dualSoloIndicatorName(
            role === 'main' ? (parent || {}).indicator : (parent || {}).secondary_indicator,
            role
        );
        const found = findInstanceByIdentity(
            (parent || {}).terminal_family,
            indicator,
            (parent || {}).symbol,
            (parent || {}).timeframe
        );
        if (found) return found;
        return Object.assign({}, parent || {}, {
            indicator,
            secondary_enabled: false,
            effective_automation_enabled: false,
            automation_enabled: false,
            automation_mode: 'explicit'
        });
    }

    function renderDualSoloButton(parent, role) {
        const row = dualSoloRow(parent, role);
        const isOn = boolish(row.effective_automation_enabled);
        const cls = isOn ? 'btn-outline-danger' : 'btn-outline-success';
        const text = isOn ? 'Stop Solo' : 'Start Solo';
        const badge = isOn ? '<span class="badge text-bg-success">ON</span>' : '<span class="badge text-bg-secondary">OFF</span>';
        return `<div class="v2-dual-solo-control">
            <div class="small text-nowrap">
                <span class="text-muted">Individual automation</span>
                <span class="ms-1">${badge}</span>
            </div>
            <button type="button" class="btn btn-sm ${cls} v2-dual-solo-toggle"
                data-role="${esc(role)}"
                data-parent="${esc((parent || {}).instance_key || '')}"
                data-enabled="${isOn ? '0' : '1'}">${text}</button>
        </div>`;
    }

    function isDualGateInstance(row) {
        return boolish((row || {}).secondary_enabled)
            && (boolish((row || {}).secondary_entry_gate_enabled) || boolish((row || {}).secondary_governor_enabled));
    }

    function isEntryExitInstance(row) {
        const profile = String((row || {}).profile || '').trim().toLowerCase();
        const indicator = String((row || {}).indicator || '').trim().toLowerCase();
        const buyExit = (row || {}).buy_exit_buffer;
        const sellExit = (row || {}).sell_exit_buffer;
        return boolish((row || {}).entry_exit_enabled)
            || profile === 'entryexit'
            || (buyExit != null && String(buyExit).trim() !== '' && Number.isFinite(Number(buyExit)) && Number(buyExit) >= 0)
            || (sellExit != null && String(sellExit).trim() !== '' && Number.isFinite(Number(sellExit)) && Number(sellExit) >= 0)
            || indicator.includes('royal entry');
    }

    function entryExitExitMode(row) {
        const raw = String((row || {}).entry_exit_exit_mode || ((row || {}).entry_exit || {}).exit_mode || '').trim().toLowerCase().replace(/[-\s]+/g, '_');
        if (['instant', 'immediate', 'current_bar', 'active_bar', 'on_signal'].includes(raw)) return 'instant';
        if (['on_candle_close', 'candle_close', 'closed_bar', 'on_close'].includes(raw)) return 'on_candle_close';
        if (['after_blank', 'blank', 'blank_candle', 'wait_blank', 'wait_for_blank'].includes(raw)) return 'after_blank';
        return boolish((row || {}).entry_exit_exit_wait_for_blank == null ? true : (row || {}).entry_exit_exit_wait_for_blank)
            ? 'after_blank'
            : 'on_candle_close';
    }

    function entryExitExitModes(row) {
        const raw = (row || {}).entry_exit_exit_modes || ((row || {}).entry_exit || {}).exit_modes;
        let values = [];
        if (Array.isArray(raw)) {
            values = raw;
        } else {
            const csv = String((row || {}).entry_exit_exit_modes_csv || ((row || {}).entry_exit || {}).exit_modes_csv || '').trim();
            values = csv ? csv.split(/[,;|]+/) : [entryExitExitMode(row)];
        }
        const out = [];
        values.forEach(v => {
            const m = String(v || '').trim().toLowerCase().replace(/[-\s]+/g, '_');
            const mode = ['instant', 'immediate', 'current_bar', 'active_bar', 'on_signal'].includes(m)
                ? 'instant'
                : (['on_candle_close', 'candle_close', 'closed_bar', 'on_close'].includes(m) ? 'on_candle_close' : (['after_blank', 'blank', 'blank_candle', 'wait_blank', 'wait_for_blank'].includes(m) ? 'after_blank' : ''));
            if (mode && !out.includes(mode)) out.push(mode);
        });
        return out.length ? out : ['after_blank'];
    }

    function entryExitExitModeLabel(mode) {
        if (mode === 'instant') return 'instant stop';
        if (mode === 'on_candle_close') return 'stop candle close';
        return 'stop + blank close';
    }

    function entryExitLifecycleModes(row) {
        const raw = (row || {}).entry_exit_lifecycle_modes || ((row || {}).entry_exit || {}).lifecycle_modes;
        let values = [];
        if (Array.isArray(raw)) {
            values = raw;
        } else {
            const csv = String((row || {}).entry_exit_lifecycle_modes_csv || ((row || {}).entry_exit || {}).lifecycle_modes_csv || '').trim();
            values = csv ? csv.split(/[,;|]+/) : [((row || {}).entry_exit_lifecycle_mode || ((row || {}).entry_exit || {}).lifecycle_mode || 'coexist')];
        }
        const out = [];
        values.forEach(v => {
            const m = String(v || '').trim().toLowerCase().replace(/[-\s]+/g, '_');
            const mode = ['exclusive', 'exclusive_until_stop', 'single', 'single_active', 'one_trade', 'lock_until_stop', 'production'].includes(m)
                ? 'exclusive_until_stop'
                : (['coexist', 'parallel', 'hedge', 'normal', 'current'].includes(m) ? 'coexist' : '');
            if (mode && !out.includes(mode)) out.push(mode);
        });
        return out.length ? out : ['coexist'];
    }

    function entryExitLifecycleModeLabel(mode) {
        if (mode === 'exclusive_until_stop') return 'exclusive until stop';
        return 'coexist';
    }

    function fmtExitBufferIndex(v) {
        const n = Number(v);
        return Number.isFinite(n) && n >= 0 ? String(Math.trunc(n)) : '-';
    }

    function isBridgeInstancesTableRow(row) {
        return !isDualGateInstance(row) && !isEntryExitInstance(row) && !boolish((row || {}).dual_solo_virtual);
    }

    function dualGateMode(row) {
        if (boolish((row || {}).secondary_entry_gate_enabled)) return 'ENTRY GATE';
        if (boolish((row || {}).secondary_governor_enabled)) return 'GOVERNOR';
        return 'SECONDARY';
    }

    function dualGateDecision(row) {
        const pending = normDirection((row || {}).pending_direction);
        const main = normDirection((row || {}).resolved_signal || (row || {}).confirmed_direction);
        const secondary = normDirection((row || {}).secondary_resolved_signal || (row || {}).secondary_signal);
        const age = livePendingAgeSec(row);
        const confirm = (row || {}).confirm_seconds;

        if (isDirectional(pending)) {
            return {
                label: 'WAIT',
                cls: 'v2-signal-wait',
                detail: `main pending ${pending}${age != null ? ` ${fmtNum(age, 0)}s` : ''}${confirm != null ? ` / ${fmtNum(confirm, 0)}s` : ''}`
            };
        }
        if (!isDirectional(main)) {
            return { label: 'WAIT', cls: 'v2-signal-wait', detail: 'main direction not confirmed' };
        }
        if (!isDirectional(secondary)) {
            return { label: 'WAIT', cls: 'v2-signal-wait', detail: `secondary ${displaySignal(secondary)}` };
        }
        if (main !== secondary) {
            return { label: 'WAIT', cls: 'v2-signal-wait', detail: `${main} / ${secondary} mismatch` };
        }
        return { label: main, cls: signalChipClass(main), detail: 'both signals approved' };
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

    function isZeroPnlBreakEvenOperation(row) {
        const pnl = Number((row || {}).realized_pnl);
        if (!Number.isFinite(pnl) || Math.abs(pnl) > 0.000001) return false;
        const text = [
            (row || {}).message,
            (row || {}).close_reason,
            (row || {}).trigger,
            (row || {}).stage,
            (row || {}).stage_status
        ].map(v => String(v || '').toLowerCase()).join(' ');
        return text.includes('sl->be')
            || text.includes('sl -> be')
            || text.includes('sl_be')
            || text.includes('sl moved')
            || text.includes('sl_moved')
            || text.includes('break_even')
            || text.includes('break even');
    }

    function isReadableTradeAuditRow(row) {
        const status = String((row || {}).status || '').trim().toLowerCase();
        const msg = String((row || {}).message || (row || {}).close_reason || '').trim().toLowerCase();
        const ticket = Number((row || {}).ticket || 0);
        const lot = Number((row || {}).lot || 0);
        const mode = String((row || {}).execution_mode || '').trim().toLowerCase();
        const hasTradeIdentity = Number.isFinite(ticket) && ticket > 0 && Number.isFinite(lot) && lot > 0;
        if (msg.includes('_orphan') || msg.includes('orphan')) return false;
        if (status === 'opened') {
            return hasTradeIdentity && (msg.includes('order_opened') || msg.includes('opened'));
        }
        if (status === 'closed') {
            return hasTradeIdentity && !!mode && mode !== '-' && !msg.includes('skipped');
        }
        return false;
    }

    function rowMode(row) {
        return String((row || {}).execution_mode || '-').trim() || '-';
    }

    function exitModeFromSourceTag(row) {
        const tag = String((row || {}).source_tag || '').trim().toLowerCase();
        if (tag.includes('|exit_instant')) return 'instant';
        if (tag.includes('|exit_on_candle_close')) return 'close';
        if (tag.includes('|exit_after_blank')) return 'blank';
        return '';
    }

    function lifecycleModeFromSourceTag(row) {
        const tag = String((row || {}).source_tag || '').trim().toLowerCase();
        if (tag.includes('|life_exclusive')) return 'exclusive';
        return '';
    }

    function entryExitAuditDetail(row) {
        const payload = ((row || {}).stage_payload || {});
        const detail = payload && typeof payload === 'object' ? (payload.entry_exit_payload || {}) : {};
        if (!detail || typeof detail !== 'object') return '';
        const bits = [];
        const mode = String(detail.exit_mode || detail.entry_exit_exit_mode || '').trim();
        const lifecycle = String(detail.lifecycle_mode || detail.entry_exit_lifecycle_mode || lifecycleModeFromSourceTag(row)).trim();
        const kind = String(detail.exit_resolved_kind || '').trim();
        const dir = String(detail.exit_direction || detail.raw_exit_direction || '').trim();
        const bar = String(detail.exit_resolved_bar_time || detail.bar_time || '').trim();
        const value = Number(detail.exit_signal_value);
        const buyBuf = Number(detail.buy_exit_buffer);
        const sellBuf = Number(detail.sell_exit_buffer);
        if (mode) bits.push(`mode=${mode}`);
        if (lifecycle) bits.push(`life=${lifecycle}`);
        if (kind) bits.push(`kind=${kind}`);
        if (dir) bits.push(`dir=${dir}`);
        if (bar) bits.push(`bar=${bar}`);
        if (Number.isFinite(value)) bits.push(`value=${fmtNum(value, 5)}`);
        if (Number.isFinite(buyBuf) && buyBuf >= 0) bits.push(`buy_exit=${buyBuf}`);
        if (Number.isFinite(sellBuf) && sellBuf >= 0) bits.push(`sell_exit=${sellBuf}`);
        return bits.length ? `<div class="small text-info">exit audit: ${esc(bits.join(' | '))}</div>` : '';
    }

    async function closeOpenTrade(row) {
        const ticket = Number((row || {}).ticket || 0);
        const symbol = String((row || {}).symbol || '').trim();
        if (!Number.isFinite(ticket) || ticket <= 0 || !symbol) {
            throw new Error('Invalid ticket/symbol for close action');
        }
        const res = await fetch('/api/indicator-bridge/open-trade/close', {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                ticket: Math.trunc(ticket),
                symbol,
                terminal_family: String((row || {}).terminal_family || '').toLowerCase(),
                source_tag: String((row || {}).source_tag || '')
            })
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data.ok === false) {
            throw new Error(data.error || data.detail || `HTTP ${res.status}`);
        }
        showNotice(`Position close sent: ${symbol} #${Math.trunc(ticket)}`, 'success');
        await loadState();
    }

    async function moveOpenTradeSlToBe(row) {
        const ticket = Number((row || {}).ticket || 0);
        const symbol = String((row || {}).symbol || '').trim();
        if (!Number.isFinite(ticket) || ticket <= 0 || !symbol) {
            throw new Error('Invalid ticket/symbol for SL->BE action');
        }
        const res = await fetch('/api/indicator-bridge/open-trade/sl-be', {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                ticket: Math.trunc(ticket),
                symbol,
                terminal_family: String((row || {}).terminal_family || '').toLowerCase(),
                source_tag: String((row || {}).source_tag || '')
            })
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data.ok === false) {
            throw new Error(data.error || data.detail || `HTTP ${res.status}`);
        }
        const reason = data.reason ? ` (${data.reason})` : '';
        showNotice(`SL->BE sent: ${symbol} #${Math.trunc(ticket)}${reason}`, 'success');
        await loadState();
    }

    function auditTimeMs(row) {
        const raw = String((row || {}).event_ts || (row || {}).opened_at || '').trim();
        const dt = raw ? new Date(raw) : null;
        return dt && !Number.isNaN(dt.getTime()) ? dt.getTime() : 0;
    }

    function chopGuardReason(row) {
        const msg = String((row || {}).message || '').trim();
        if (!msg.toLowerCase().startsWith('chop_guard_blocked')) return '';
        const idx = msg.indexOf(':');
        return idx >= 0 ? msg.slice(idx + 1).trim() : 'chop_guard_blocked';
    }

    function isChopGuardRow(row) {
        return String((row || {}).status || '').toLowerCase() === 'skipped'
            && String((row || {}).message || '').toLowerCase().startsWith('chop_guard_blocked:');
    }

    function groupAuditRows(rows) {
        const out = [];
        const groups = new Map();
        const order = [];
        rows.forEach(row => {
            if (!isChopGuardRow(row)) {
                out.push(row);
                return;
            }
            // Backend still stores one row per mode. UI groups only near-identical guard decisions.
            const bucket = Math.floor((auditTimeMs(row) || Date.now()) / 5000) * 5000;
            const key = [
                'chop',
                bucket,
                String(row.terminal_family || '').toUpperCase(),
                String(row.indicator || row.source_name || '').toLowerCase(),
                String(row.symbol || '').toUpperCase(),
                String(row.timeframe || '').toUpperCase(),
                String(row.direction || '').toUpperCase(),
                chopGuardReason(row)
            ].join('|');
            if (!groups.has(key)) {
                groups.set(key, {
                    base: Object.assign({}, row),
                    modes: [],
                    count: 0,
                    rows: [],
                    key
                });
                order.push(key);
            }
            const g = groups.get(key);
            const mode = rowMode(row);
            if (!g.modes.includes(mode)) g.modes.push(mode);
            g.count += 1;
            g.rows.push(row);
        });
        order.forEach(key => {
            const g = groups.get(key);
            if (!g) return;
            if (g.count <= 1) {
                out.push(g.base);
                return;
            }
            const base = g.base;
            out.push(Object.assign({}, base, {
                status: `${base.status || 'skipped'} x${g.count}`,
                execution_mode: `${g.count} modes`,
                grouped_modes: g.modes.join(', '),
                message: `${base.message || 'chop_guard_blocked'} (grouped ${g.count} mode rows)`,
                _audit_grouped: true,
                _audit_group_count: g.count,
                _audit_group_rows: g.rows
            }));
        });
        return out.sort((a, b) => auditTimeMs(b) - auditTimeMs(a));
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

    function renderDualSignalTile(label, indicator, dir, meta, resolved, actionHtml, extraHtml) {
        const shown = displaySignal(dir);
        const resolvedShown = displaySignal(resolved);
        return `<div class="v2-dual-tile">
            <div class="d-flex justify-content-between align-items-start gap-2">
                <div class="min-w-0">
                    <div class="small text-muted">${esc(label)}</div>
                    <div class="fw-bold text-truncate" title="${esc(indicator || '-')}">${esc(indicator || '-')}</div>
                </div>
                ${actionHtml || ''}
            </div>
            <div class="mt-2"><span class="v2-signal-chip ${signalChipClass(shown)}">${esc(shown)}</span></div>
            <div class="small mt-2">
                <span class="text-muted">resolved:</span>
                <span class="fw-bold ${resolvedShown === 'BUY' ? 'text-success' : (resolvedShown === 'SELL' ? 'text-danger' : 'text-secondary')}">${esc(resolvedShown)}</span>
            </div>
            <div class="small text-muted mt-2">${esc(meta || '')}</div>
            ${extraHtml || ''}
        </div>`;
    }

    function renderDualGatePanel() {
        if (!els.dualGatePanel || !els.dualGateBody) return;
        const rows = displayInstances().filter(isDualGateInstance).sort((a, b) => instanceSortKey(a).localeCompare(instanceSortKey(b)));
        if (!rows.length) {
            els.dualGatePanel.classList.add('d-none');
            els.dualGateBody.innerHTML = '';
            return;
        }
        els.dualGatePanel.classList.remove('d-none');
        els.dualGateBody.innerHTML = rows.map(row => {
            const decision = dualGateDecision(row);
            const mainDir = normDirection(row.resolved_signal || row.confirmed_direction || row.pending_direction);
            const secondaryDir = normDirection(row.secondary_raw_signal || row.secondary_signal);
            const mainResolved = normDirection(row.resolved_signal);
            const secondaryResolved = normDirection(row.secondary_resolved_signal || row.secondary_signal);
            const pending = normDirection(row.pending_direction);
            const liveAge = livePendingAgeSec(row);
            const total = row.confirm_seconds != null ? Number(row.confirm_seconds) : null;
            const pendingProgress = pending && liveAge != null
                ? `${fmtNum(liveAge, 0)}s${Number.isFinite(total) ? `/${fmtNum(total, 0)}s` : ''}`
                : '';
            const mainMeta = pending
                ? `pending ${pending}${pendingProgress ? ` ${pendingProgress}` : ''}`
                : `resolved shift=${row.resolved_signal_shift != null ? row.resolved_signal_shift : '-'}`;
            const secondaryMeta = `shift=${row.secondary_signal_shift != null ? row.secondary_signal_shift : '-'} bar=${row.secondary_bar_time || '-'} resolved_bar=${row.secondary_resolved_bar_time || '-'}`;
            const key = esc(row.instance_key || '');
            const isOn = boolish(row.effective_automation_enabled);
            const auto = boolish(row.effective_automation_enabled)
                ? '<span class="badge text-bg-success">ON</span>'
                : '<span class="badge text-bg-secondary">OFF</span>';
            const actionClass = isOn ? 'btn-outline-danger' : 'btn-outline-success';
            const actionText = isOn ? 'Stop' : 'Start';
            return `<div class="v2-dual-instance">
                <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 mb-2">
                    <div>
                        <span class="badge text-bg-primary">${esc(dualGateMode(row))}</span>
                        <span class="ms-2 fw-semibold">${esc(String(row.terminal_family || '').toUpperCase())} ${esc(row.symbol || '-')} ${esc(row.timeframe || '')}</span>
                        <span class="ms-2">${auto}</span>
                    </div>
                    <div class="d-flex flex-wrap align-items-center gap-2">
                        <div class="small text-muted">last seen ${esc(fmtTs(row.last_seen))}</div>
                        <button type="button" class="btn btn-sm ${actionClass} v2-dual-instance-toggle" data-instance="${key}" data-enabled="${isOn ? '0' : '1'}">${actionText}</button>
                    </div>
                </div>
                <div class="v2-dual-grid">
                    ${renderDualSignalTile('Main', row.indicator || row.source_name || '-', mainDir, mainMeta, mainResolved, renderDualSoloButton(row, 'main'))}
                    <div class="v2-dual-decision">
                        <span class="v2-signal-chip ${decision.cls}">${esc(decision.label)}</span>
                        <div class="small mt-2">${esc(decision.detail)}</div>
                    </div>
                    ${renderDualSignalTile('Secondary', row.secondary_indicator || '-', secondaryDir, secondaryMeta, secondaryResolved, renderDualSoloButton(row, 'secondary'))}
                </div>
            </div>`;
        }).join('');
    }

    function renderEntryExitPanel() {
        if (!els.entryExitPanel || !els.entryExitBody) return;
        const rows = displayInstances().filter(isEntryExitInstance).sort((a, b) => instanceSortKey(a).localeCompare(instanceSortKey(b)));
        if (!rows.length) {
            els.entryExitPanel.classList.add('d-none');
            els.entryExitBody.innerHTML = '';
            return;
        }
        els.entryExitPanel.classList.remove('d-none');
        els.entryExitBody.innerHTML = rows.map(row => {
            const entryResolved = normDirection(row.entry_resolved_signal || row.resolved_signal || row.confirmed_direction);
            const entryRaw = normDirection(row.resolved_signal || row.confirmed_direction || row.pending_direction);
            const lastEntryResolved = normDirection(row.last_entry_resolved_signal);
            const lastEntrySignal = normDirection(row.last_entry_signal_direction);
            const exitResolved = normDirection(row.exit_resolved_signal || row.exit_direction);
            const exitKindRaw = String(row.exit_resolved_kind || '').trim().toUpperCase();
            const exitKind = exitKindRaw || (exitResolved === 'BUY' ? 'BUY_STOP' : (exitResolved === 'SELL' ? 'SELL_STOP' : ''));
            const lastExitResolved = normDirection(row.last_exit_resolved_signal);
            const lastExitKindRaw = String(row.last_exit_resolved_kind || '').trim().toUpperCase();
            const lastExitKind = lastExitKindRaw || (lastExitResolved === 'BUY' ? 'BUY_STOP' : (lastExitResolved === 'SELL' ? 'SELL_STOP' : ''));
            const pending = normDirection(row.pending_direction);
            const liveAge = livePendingAgeSec(row);
            const total = row.confirm_seconds != null ? Number(row.confirm_seconds) : null;
            const entryMeta = pending
                ? `pending ${pending}${liveAge != null ? ` ${fmtNum(liveAge, 0)}s` : ''}${Number.isFinite(total) ? `/${fmtNum(total, 0)}s` : ''}`
                : `state event=${row.bridge_event_type || '-'} shift=${row.resolved_signal_shift != null ? row.resolved_signal_shift : '-'} bar=${row.resolved_signal_bar_time || '-'}`;
            const exitMeta = `${exitKind ? `last ${exitKind} ` : ''}exit bar=${row.exit_resolved_bar_time || '-'} buffers buy_exit=${fmtExitBufferIndex(row.buy_exit_buffer)} sell_exit=${fmtExitBufferIndex(row.sell_exit_buffer)}`;
            const key = esc(row.instance_key || '');
            const isOn = boolish(row.effective_automation_enabled);
            const exitModes = entryExitExitModes(row);
            const exitMode = exitModes[0] || entryExitExitMode(row);
            const lifecycleModes = entryExitLifecycleModes(row);
            const auto = isOn ? '<span class="badge text-bg-success">ON</span>' : '<span class="badge text-bg-secondary">OFF</span>';
            const actionClass = isOn ? 'btn-outline-danger' : 'btn-outline-success';
            const actionText = isOn ? 'Stop' : 'Start';
            const decisionDir = entryResolved || entryRaw;
            const decisionLabel = isDirectional(decisionDir) ? decisionDir : 'WAIT';
            const decisionDetail = isDirectional(exitResolved)
                ? `exit/stop state ${exitResolved}${exitKind ? ` (${exitKind})` : ''}`
                : (isDirectional(lastExitResolved)
                    ? `current NONE / last resolved ${lastExitResolved}${lastExitKind ? ` (${lastExitKind})` : ''}`
                    : 'no resolved exit/stop yet');
            const exitLastMeta = isDirectional(lastExitResolved)
                ? `<div class="small mt-2"><span class="text-muted">last resolved:</span> <span class="fw-bold ${lastExitResolved === 'BUY' ? 'text-success' : 'text-danger'}">${esc(lastExitResolved)}</span>${lastExitKind ? ` <span class="text-muted">(${esc(lastExitKind)})</span>` : ''}${row.last_exit_resolved_bar_time ? ` <span class="text-muted">${esc(row.last_exit_resolved_bar_time)}</span>` : ''}</div>`
                : '';
            const entryLastMeta = isDirectional(lastEntryResolved)
                ? `<div class="small mt-2"><span class="text-muted">last resolved state:</span> <span class="fw-bold ${lastEntryResolved === 'BUY' ? 'text-success' : 'text-danger'}">${esc(lastEntryResolved)}</span>${row.last_entry_resolved_bar_time ? ` <span class="text-muted">${esc(row.last_entry_resolved_bar_time)}</span>` : ''}</div>`
                : '';
            const entrySignalMeta = isDirectional(lastEntrySignal)
                ? `<div class="small mt-1"><span class="text-muted">last entry signal:</span> <span class="fw-bold ${lastEntrySignal === 'BUY' ? 'text-success' : 'text-danger'}">${esc(lastEntrySignal)}</span>${row.last_entry_signal_bar_time ? ` <span class="text-muted">${esc(row.last_entry_signal_bar_time)}</span>` : ''}</div>`
                : '<div class="small mt-1 text-muted">no executable entry signal yet</div>';
            return `<div class="v2-dual-instance">
                <div class="d-flex flex-wrap justify-content-between align-items-center gap-2 mb-2">
                    <div>
                        <span class="badge text-bg-info">ENTRY / EXIT</span>
                        <span class="ms-2 fw-semibold">${esc(String(row.terminal_family || '').toUpperCase())} ${esc(row.symbol || '-')} ${esc(row.timeframe || '')}</span>
                        <span class="ms-2">${auto}</span>
                        <span class="ms-2 small text-muted">${esc(modeText(row))}</span>
                    </div>
                    <div class="d-flex flex-wrap align-items-center gap-2">
                        <div class="small text-muted">last seen ${esc(fmtTs(row.last_seen))}</div>
                        ${renderModeControls(row)}
                        <div class="btn-group btn-group-sm v2-entry-exit-mode-group" role="group" data-instance="${key}">
                            <input type="checkbox" class="btn-check v2-entry-exit-mode-check" id="eem-after-${key}" data-instance="${key}" value="after_blank" ${exitModes.includes('after_blank') ? 'checked' : ''}>
                            <label class="btn btn-outline-secondary" for="eem-after-${key}">blank</label>
                            <input type="checkbox" class="btn-check v2-entry-exit-mode-check" id="eem-close-${key}" data-instance="${key}" value="on_candle_close" ${exitModes.includes('on_candle_close') ? 'checked' : ''}>
                            <label class="btn btn-outline-secondary" for="eem-close-${key}">close</label>
                            <input type="checkbox" class="btn-check v2-entry-exit-mode-check" id="eem-instant-${key}" data-instance="${key}" value="instant" ${exitModes.includes('instant') ? 'checked' : ''}>
                            <label class="btn btn-outline-secondary" for="eem-instant-${key}">instant</label>
                        </div>
                        <div class="btn-group btn-group-sm v2-entry-exit-life-group" role="group" data-instance="${key}">
                            <input type="checkbox" class="btn-check v2-entry-exit-life-check" id="eel-coexist-${key}" data-instance="${key}" value="coexist" ${lifecycleModes.includes('coexist') ? 'checked' : ''}>
                            <label class="btn btn-outline-secondary" for="eel-coexist-${key}">coexist</label>
                            <input type="checkbox" class="btn-check v2-entry-exit-life-check" id="eel-exclusive-${key}" data-instance="${key}" value="exclusive_until_stop" ${lifecycleModes.includes('exclusive_until_stop') ? 'checked' : ''}>
                            <label class="btn btn-outline-secondary" for="eel-exclusive-${key}">exclusive</label>
                        </div>
                        <span class="badge text-bg-light">${esc(exitModes.map(entryExitExitModeLabel).join(' + '))}</span>
                        <span class="badge text-bg-light">${esc(lifecycleModes.map(entryExitLifecycleModeLabel).join(' + '))}</span>
                        <input type="number" class="form-control form-control-sm v2-lot-input" min="0.01" step="0.01" data-instance="${key}" value="${esc(fmtNum(row.lot_size || 0.1, 2))}" title="Lot size">
                        <button type="button" class="btn btn-sm ${actionClass} v2-entry-exit-toggle" data-instance="${key}" data-enabled="${isOn ? '0' : '1'}">${actionText}</button>
                    </div>
                </div>
                <div class="v2-dual-grid">
                    ${renderDualSignalTile('Entry', row.indicator || row.source_name || '-', entryRaw, entryMeta, entryResolved, '', `${entryLastMeta}${entrySignalMeta}`)}
                    <div class="v2-dual-decision">
                        <span class="v2-signal-chip ${signalChipClass(decisionLabel)}">${esc(decisionLabel)}</span>
                        <div class="small mt-2">${esc(decisionDetail)}</div>
                    </div>
                    ${renderDualSignalTile('Exit / Stop', row.indicator || row.source_name || '-', exitResolved, exitMeta, exitResolved, '', exitLastMeta)}
                </div>
            </div>`;
        }).join('');
    }

    function renderOpenTrades() {
        const q = els.openFilter ? els.openFilter.value : '';
        const rows = openTrades().filter(r => textMatch(r, q));
        if (!els.openBody) return;
        if (!rows.length) {
            els.openBody.innerHTML = '<tr><td colspan="10" class="text-center text-muted py-3">No open indicator trades.</td></tr>';
            return;
        }
        els.openBody.innerHTML = rows.map(row => {
            const pnl = Number(row.current_profit);
            const pnlCls = Number.isFinite(pnl) ? (pnl >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            const ticket = Number(row.ticket || 0);
            const canClose = Number.isFinite(ticket) && ticket > 0 && String(row.symbol || '').trim();
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
                <td>
                    <div class="btn-group btn-group-sm" role="group">
                        <button type="button" class="btn btn-outline-warning v2-sl-be-trade" data-ticket="${esc(row.ticket || '')}" ${canClose ? '' : 'disabled'}>SL-&gt;BE</button>
                        <button type="button" class="btn btn-outline-danger v2-close-trade" data-ticket="${esc(row.ticket || '')}" ${canClose ? '' : 'disabled'}>Close</button>
                    </div>
                </td>
            </tr>`;
        }).join('');
    }

    function renderRiskSettings() {
        const risk = (state || {}).risk_settings || {};
        const daily = (state || {}).daily_risk || {};
        const dailyTarget = Number(risk.daily_target_usd || 0);
        const dailyMaxLoss = Number(risk.daily_max_loss_usd || 0);
        const catastrophe = Number(risk.catastrophe_loss_usd || (dailyMaxLoss / 4));
        const targetFocused = els.riskDailyTarget && document.activeElement === els.riskDailyTarget;
        const maxFocused = els.riskDailyMaxLoss && document.activeElement === els.riskDailyMaxLoss;
        if (els.riskDailyTarget && !targetFocused) els.riskDailyTarget.value = Number.isFinite(dailyTarget) ? dailyTarget.toFixed(2) : '0.00';
        if (els.riskDailyMaxLoss && !maxFocused) els.riskDailyMaxLoss.value = Number.isFinite(dailyMaxLoss) ? dailyMaxLoss.toFixed(2) : '0.00';
        const liveMax = parseMoney(els.riskDailyMaxLoss ? els.riskDailyMaxLoss.value : dailyMaxLoss);
        const liveCat = liveMax == null ? catastrophe : liveMax / 4;
        if (els.riskCatastrophe) els.riskCatastrophe.textContent = `$${fmtNum(liveCat, 2)}`;
        if (els.riskDailyStatus) {
            const pnl = Number(daily.realized_pnl || 0);
            const blocked = !!daily.blocked;
            const reason = daily.block_reason ? ` / ${daily.block_reason}` : '';
            const targetBypassed = !!(daily.daily_target_guard_bypassed_today || risk.daily_target_guard_bypassed_today);
            els.riskDailyStatus.className = `fw-bold ${blocked ? 'text-danger' : (targetBypassed ? 'text-warning' : (pnl >= 0 ? 'text-success' : 'text-danger'))}`;
            els.riskDailyStatus.textContent = `$${fmtNum(pnl, 2)}${blocked ? ` BLOCKED${reason}` : (targetBypassed ? ' TARGET BYPASSED' : '')}`;
        }
        if (els.riskTargetOverride) {
            const targetBypassed = !!(daily.daily_target_guard_bypassed_today || risk.daily_target_guard_bypassed_today);
            els.riskTargetOverride.className = targetBypassed ? 'btn btn-sm btn-warning mt-2' : 'btn btn-sm btn-outline-warning mt-2';
            els.riskTargetOverride.textContent = targetBypassed ? 'Stop Extra Trades Today' : 'Allow More Today';
            els.riskTargetOverride.setAttribute('data-enabled', targetBypassed ? '1' : '0');
        }
        if (els.riskStatus) {
            const enabled = !!risk.catastrophe_enabled || (Number.isFinite(liveCat) && liveCat > 0);
            els.riskStatus.className = enabled ? 'badge text-bg-success' : 'badge text-bg-secondary';
            els.riskStatus.textContent = enabled ? 'catastrophe SL ON' : 'catastrophe SL OFF';
        }
    }

    function renderDualGateSettings() {
        const cfg = (state || {}).dual_gate_settings || {};
        const enabled = boolish(cfg.none_close_enabled);
        if (els.dualNoneCloseToggle) els.dualNoneCloseToggle.checked = enabled;
        if (els.dualNoneCloseStatus) {
            els.dualNoneCloseStatus.className = enabled ? 'badge text-bg-warning' : 'badge text-bg-secondary';
            els.dualNoneCloseStatus.textContent = enabled ? 'NONE timeout close ON' : 'NONE timeout close OFF';
        }
    }

    function renderInstances() {
        const q = els.instanceFilter ? els.instanceFilter.value : '';
        const rows = displayInstances()
            .filter(isBridgeInstancesTableRow)
            .filter(r => textMatch(r, q))
            .sort((a, b) => instanceSortKey(a).localeCompare(instanceSortKey(b)));
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
            const pending = normDirection(row.pending_direction);
            const liveAge = livePendingAgeSec(row);
            const total = row.confirm_seconds != null ? Number(row.confirm_seconds) : null;
            const pendingText = pending
                ? `${esc(pending)} ${liveAge != null ? `<span class="small text-muted">${fmtNum(liveAge, 0)}s${Number.isFinite(total) ? `/${fmtNum(total, 0)}s` : ''}</span>` : ''}`
                : '-';
            const lastSignal = normDirection(row.last_signal_direction);
            const lastSignalHtml = isDirectional(lastSignal)
                ? `<div class="small text-muted">last signal: <span class="${lastSignal === 'BUY' ? 'text-success' : 'text-danger'} fw-semibold">${esc(lastSignal)}</span>${row.last_signal_bar_time ? ` ${esc(row.last_signal_bar_time)}` : ''}</div>`
                : '';
            const resolvedHtml = `${esc(row.resolved_signal || '-')}${lastSignalHtml}`;
            return `<tr>
                <td>${esc(fmtTs(row.last_seen))}</td>
                <td>${esc(String(row.terminal_family || '').toUpperCase())}</td>
                <td>${esc(row.indicator || '-')}<div class="small text-muted">${esc(row.bridge_version || '')}</div></td>
                <td>${esc(row.symbol || '-')} ${esc(row.timeframe || '')}</td>
                <td class="${stateClass(row)}">${esc(row.state || '-')}</td>
                <td>${auto}</td>
                <td>${renderModeControls(row)}<div class="small text-muted">${esc(modeText(row))}</div></td>
                <td>${resolvedHtml}</td>
                <td>${esc(row.confirmed_direction || '-')}</td>
                <td>${pendingText}</td>
                <td><input type="number" class="form-control form-control-sm v2-lot-input" min="0.01" step="0.01" data-instance="${esc(row.instance_key || '')}" value="${esc(fmtNum(row.lot_size || 0.1, 2))}" title="Lot size"></td>
                <td><button type="button" class="btn btn-sm ${actionClass} v2-instance-toggle" data-instance="${esc(row.instance_key || '')}" data-enabled="${isOn ? '0' : '1'}">${actionText}</button></td>
            </tr>`;
        }).join('');
    }

    function renderAudit() {
        const q = els.auditFilter ? els.auditFilter.value : '';
        const meaningfulRaw = auditRows()
            .filter(row => !isZeroPnlBreakEvenOperation(row))
            .filter(isReadableTradeAuditRow)
            .filter(r => textMatch(r, q));
        const meaningful = groupAuditRows(meaningfulRaw).slice(0, 1000);
        if (!els.auditBody) return;
        if (!meaningful.length) {
            els.auditBody.innerHTML = '<tr><td colspan="10" class="text-center text-muted py-3">No meaningful audit rows yet.</td></tr>';
            return;
        }
        els.auditBody.innerHTML = meaningful.map(row => {
            const pnl = Number(row.realized_pnl);
            const pnlCls = Number.isFinite(pnl) ? (pnl >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            const modeDisabled = row.mode_currently_enabled === false;
            const groupedModes = row._audit_grouped && row.grouped_modes
                ? `<div class="small text-info">${esc(row.grouped_modes)}</div>`
                : '';
            const exitMode = exitModeFromSourceTag(row);
            const exitModeHtml = exitMode ? `<div class="small text-info">exit: ${esc(exitMode)}</div>` : '';
            const lifecycleMode = lifecycleModeFromSourceTag(row);
            const lifecycleHtml = lifecycleMode ? `<div class="small text-info">life: ${esc(lifecycleMode)}</div>` : '';
            const modeLabel = `${esc(row.execution_mode || '-')}${exitModeHtml}${lifecycleHtml}${modeDisabled ? '<div class="small text-warning">disabled now</div>' : ''}${groupedModes}`;
            const shadow = row.shadow_outcome ? `<div class="small text-info">shadow: ${esc(row.shadow_outcome)}${row.shadow_reason ? ` / ${esc(row.shadow_reason)}` : ''}</div>` : '';
            const grouped = row._audit_grouped ? `<div class="small text-muted">grouped ${esc(row._audit_group_count || '')} guard rows</div>` : '';
            const entryExitDetail = entryExitAuditDetail(row);
            return `<tr>
                <td>${esc(row.status || row.trigger || '-')}<div class="small text-muted">${esc(fmtTs(row.event_ts || row.opened_at))}</div></td>
                <td>${esc(row.terminal_family || '-')}</td>
                <td>${esc(row.indicator || row.source_name || '-')}</td>
                <td>${esc(row.symbol || '-')} ${esc(row.timeframe || '')}</td>
                <td>${modeLabel}</td>
                <td>${esc(row.direction || '-')}</td>
                <td>${fmtNum(row.lot, 2)}</td>
                <td class="v2-mono">${esc(row.ticket || '-')}</td>
                <td class="${pnlCls}">${fmtNum(row.realized_pnl, 2)}</td>
                <td>${esc(row.message || row.close_reason || '-')}${entryExitDetail}${grouped}${shadow}</td>
            </tr>`;
        }).join('');
    }

    function render() {
        if (!state) return;
        const visibleInstances = displayInstances();
        const mt4Rows = visibleInstances.filter(row => String(row.terminal_family || '').toUpperCase() === 'MT4');
        const mt5Rows = visibleInstances.filter(row => String(row.terminal_family || '').toUpperCase() === 'MT5');
        if (els.updated) els.updated.textContent = `Updated: ${fmtTs(state.updated_at)}`;
        if (els.mt4Count) els.mt4Count.textContent = String(mt4Rows.length);
        if (els.mt5Count) els.mt5Count.textContent = String(mt5Rows.length);
        if (els.openCount) els.openCount.textContent = String(openTrades().length);
        if (els.auditCount) els.auditCount.textContent = String(auditRows().filter(row => !isZeroPnlBreakEvenOperation(row)).filter(isReadableTradeAuditRow).length);
        renderRiskSettings();
        renderDualGateSettings();
        renderDualGatePanel();
        renderEntryExitPanel();
        renderOpenTrades();
        renderInstances();
        renderAudit();
    }

    function schedule() {
        if (timer) clearInterval(timer);
        timer = setInterval(() => loadState().catch(showError), 5000);
        if (uiTimer) clearInterval(uiTimer);
        uiTimer = setInterval(() => {
            if (!state) return;
            renderDualGatePanel();
            if (!els.entryExitBody || !els.entryExitBody.contains(document.activeElement)) {
                renderEntryExitPanel();
            }
            renderInstances();
        }, 1000);
    }

    [els.openFilter, els.instanceFilter, els.auditFilter].forEach(el => {
        if (el) el.addEventListener('input', render);
    });
    [els.riskDailyTarget, els.riskDailyMaxLoss].forEach(el => {
        if (el) el.addEventListener('input', renderRiskSettings);
        if (el) el.addEventListener('keydown', ev => {
            if (ev.key === 'Enter') saveRiskSettings().catch(showError);
        });
    });
    if (els.riskSave) {
        els.riskSave.addEventListener('click', () => saveRiskSettings().catch(showError));
    }
    if (els.riskTargetOverride) {
        els.riskTargetOverride.addEventListener('click', () => {
            const enabled = els.riskTargetOverride.getAttribute('data-enabled') === '1';
            setDailyTargetOverride(!enabled).catch(showError);
        });
    }
    if (els.dualNoneCloseToggle) {
        els.dualNoneCloseToggle.addEventListener('change', ev => {
            const input = ev.target;
            input.disabled = true;
            saveDualGateSettings(!!input.checked).catch(err => {
                showError(err);
                input.checked = !input.checked;
                renderDualGateSettings();
            }).finally(() => {
                input.disabled = false;
            });
        });
    }
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
    if (els.dualGateBody) {
        els.dualGateBody.addEventListener('click', ev => {
            const soloBtn = ev.target.closest('.v2-dual-solo-toggle');
            if (soloBtn) {
                const parentKey = soloBtn.getAttribute('data-parent') || '';
                const role = soloBtn.getAttribute('data-role') || '';
                const parent = allInstances().find(r => String(r.instance_key || '') === parentKey);
                if (!parent) return;
                const row = dualSoloRow(parent, role);
                soloBtn.disabled = true;
                soloBtn.textContent = '...';
                updateInstanceAutomation(row, soloBtn.getAttribute('data-enabled') === '1').catch(err => {
                    showError(err);
                    soloBtn.disabled = false;
                    renderDualGatePanel();
                });
                return;
            }

            const btn = ev.target.closest('.v2-dual-instance-toggle');
            if (!btn) return;
            const key = btn.getAttribute('data-instance') || '';
            const row = allInstances().find(r => String(r.instance_key || '') === key);
            if (!row) return;
            btn.disabled = true;
            btn.textContent = '...';
            updateInstanceAutomation(row, btn.getAttribute('data-enabled') === '1').catch(err => {
                showError(err);
                btn.disabled = false;
                renderDualGatePanel();
            });
        });
    }
    if (els.entryExitBody) {
        els.entryExitBody.addEventListener('click', ev => {
            const btn = ev.target.closest('.v2-entry-exit-toggle');
            if (!btn) return;
            const key = btn.getAttribute('data-instance') || '';
            const row = allInstances().find(r => String(r.instance_key || '') === key);
            if (!row) return;
            btn.disabled = true;
            btn.textContent = '...';
            updateInstanceAutomation(row, btn.getAttribute('data-enabled') === '1').catch(err => {
                showError(err);
                btn.disabled = false;
                renderEntryExitPanel();
            });
        });
        els.entryExitBody.addEventListener('change', ev => {
            const modeCheck = ev.target.closest('.v2-entry-exit-mode-check');
            const lifeCheck = ev.target.closest('.v2-entry-exit-life-check');
            const modeToggle = ev.target.closest('.v2-mode-toggle');
            const policyToggle = ev.target.closest('.v2-policy-toggle');
            const input = ev.target.closest('.v2-lot-input');
            if (!input && !modeCheck && !lifeCheck && !modeToggle && !policyToggle) return;
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
                    renderEntryExitPanel();
                });
                return;
            }
            if (modeCheck) {
                const key = modeCheck.getAttribute('data-instance') || '';
                const row = allInstances().find(r => String(r.instance_key || '') === key);
                if (!row) return;
                const checks = Array.from(els.entryExitBody.querySelectorAll('.v2-entry-exit-mode-check'))
                    .filter(x => String(x.getAttribute('data-instance') || '') === key);
                let modes = checks.filter(x => x.checked).map(x => String(x.value || '').trim()).filter(Boolean);
                if (!modes.length) {
                    modeCheck.checked = true;
                    modes = [String(modeCheck.value || 'after_blank').trim()];
                }
                checks.forEach(x => { x.disabled = true; });
                updateInstanceSettings(row, {
                    entry_exit_exit_modes: modes,
                    entry_exit_exit_mode: modes[0],
                    entry_exit_exit_wait_for_blank: modes.includes('after_blank')
                }).catch(err => {
                    showError(err);
                    checks.forEach(x => { x.disabled = false; });
                    renderEntryExitPanel();
                });
                return;
            }
            if (lifeCheck) {
                const key = lifeCheck.getAttribute('data-instance') || '';
                const row = allInstances().find(r => String(r.instance_key || '') === key);
                if (!row) return;
                const checks = Array.from(els.entryExitBody.querySelectorAll('.v2-entry-exit-life-check'))
                    .filter(x => String(x.getAttribute('data-instance') || '') === key);
                let modes = checks.filter(x => x.checked).map(x => String(x.value || '').trim()).filter(Boolean);
                if (!modes.length) {
                    lifeCheck.checked = true;
                    modes = [String(lifeCheck.value || 'coexist').trim()];
                }
                checks.forEach(x => { x.disabled = true; });
                updateInstanceSettings(row, {
                    entry_exit_lifecycle_modes: modes,
                    entry_exit_lifecycle_mode: modes[0]
                }).catch(err => {
                    showError(err);
                    checks.forEach(x => { x.disabled = false; });
                    renderEntryExitPanel();
                });
                return;
            }
            const key = input.getAttribute('data-instance') || '';
            const row = allInstances().find(r => String(r.instance_key || '') === key);
            const lot = parseLot(input.value);
            if (!row || lot == null) {
                showError(new Error('Invalid lot size'));
                renderEntryExitPanel();
                return;
            }
            input.disabled = true;
            updateInstanceSettings(row, { lot_size: lot }).catch(err => {
                showError(err);
                input.disabled = false;
                renderEntryExitPanel();
            });
        });
        els.entryExitBody.addEventListener('keydown', ev => {
            const input = ev.target.closest('.v2-lot-input');
            if (input && ev.key === 'Enter') input.blur();
        });
    }
    if (els.openBody) {
        els.openBody.addEventListener('click', ev => {
            const beBtn = ev.target.closest('.v2-sl-be-trade');
            if (beBtn) {
                const ticket = String(beBtn.getAttribute('data-ticket') || '');
                const row = openTrades().find(r => String((r || {}).ticket || '') === ticket);
                if (!row) return;
                beBtn.disabled = true;
                beBtn.textContent = 'BE...';
                moveOpenTradeSlToBe(row).catch(err => {
                    showError(err);
                    beBtn.disabled = false;
                    beBtn.textContent = 'SL->BE';
                });
                return;
            }

            const btn = ev.target.closest('.v2-close-trade');
            if (!btn) return;
            const ticket = String(btn.getAttribute('data-ticket') || '');
            const row = openTrades().find(r => String((r || {}).ticket || '') === ticket);
            if (!row) return;
            const symbol = String(row.symbol || '').trim();
            const ok = window.confirm(`Close ${symbol} #${ticket}?`);
            if (!ok) return;
            btn.disabled = true;
            btn.textContent = 'Closing...';
            closeOpenTrade(row).catch(err => {
                showError(err);
                btn.disabled = false;
                btn.textContent = 'Close';
            });
        });
    }
    if (els.refresh) els.refresh.addEventListener('click', () => loadState().catch(showError));
    loadState().catch(showError);
    schedule();
})();
