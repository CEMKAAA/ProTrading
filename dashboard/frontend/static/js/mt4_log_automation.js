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
        chartGroup: document.getElementById('mt4la-chart-group'),
        chartInstance: document.getElementById('mt4la-chart-instance'),
        chartStats: document.getElementById('mt4la-chart-stats'),
        chartAutomationBtn: document.getElementById('mt4la-chart-automation-btn'),
        chartAutomationState: document.getElementById('mt4la-chart-automation-state'),
        chartLogBody: document.getElementById('mt4la-chart-log-body'),
        botStartBtn: document.getElementById('mt4la-bot-start-btn'),
        botStopBtn: document.getElementById('mt4la-bot-stop-btn'),
        botUpdated: document.getElementById('mt4la-bot-updated'),
        botEnabledCount: document.getElementById('mt4la-bot-enabled-count'),
        botActiveCount: document.getElementById('mt4la-bot-active-count'),
        botBody: document.getElementById('mt4la-bot-body'),
        logTitle: document.getElementById('mt4la-log-title'),
        logBody: document.getElementById('mt4la-log-body'),
        execBody: document.getElementById('mt4la-exec-body'),
        execReportBody: document.getElementById('mt4la-exec-report-body'),
        execReportMeta: document.getElementById('mt4la-exec-report-meta')
    };

    let pollTimer = null;
    let formDirty = false;
    let suppressDirty = false;
    let selectedIndicator = '';
    let latestState = null;
    let indicatorSearchText = '';
    let instanceSearchText = '';
    let selectedChartGroup = 'all';
    let selectedChartInstance = 'all';
    let latestExecLogs = [];
    let latestChartEvents = [];
    const latestChartEventKeys = new Map();
    let chartSocket = null;
    let chartSocketRetryMs = 1000;
    const lotDraftByIndicator = new Map();
    const lotDraftByInstance = new Map();
    const ALLOWED_INDICATOR_TOKENS = [
        'hydra signals indicator',
        'hydra',
        'forex uranus direction',
        'uranus',
        'fxnukeesc',
        'fxnuke',
        'forexcypersystem',
        'forexcyper',
        'alchemy pulse',
        'intrepid trend direction',
        'intrepid'
    ];

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

    function normalizeIndicatorName(v) {
        return String(v || '').trim().toLowerCase().replace(/\s+/g, ' ');
    }

    function isAllowedIndicator(v) {
        const key = normalizeIndicatorName(v);
        if (!key) return false;
        return ALLOWED_INDICATOR_TOKENS.some((tok) => key.includes(tok));
    }

    function prettySymbol(raw) {
        const sym = String(raw || '').trim().toUpperCase();
        if (!sym) return '-';
        if (sym.length >= 4 && sym.endsWith('M')) {
            const base = sym.slice(0, -1);
            if (base) return `${sym} (${base})`;
        }
        return sym;
    }

    function compactPath(raw) {
        const p = String(raw || '').trim();
        if (!p) return '-';
        const norm = p.replace(/\//g, '\\');
        const parts = norm.split('\\').filter(Boolean);
        if (parts.length <= 6) return norm;
        return `...\\${parts.slice(-6).join('\\')}`;
    }

    function isWithinLastHours(ts, hours) {
        const raw = String(ts || '').trim();
        if (!raw) return false;
        const dt = new Date(raw);
        if (Number.isNaN(dt.getTime())) return false;
        const maxAgeMs = Math.max(1, Number(hours || 24)) * 60 * 60 * 1000;
        return (Date.now() - dt.getTime()) <= maxAgeMs;
    }

    function eventIndicatorName(ev) {
        const parsed = parseLegacyChartFromEvent(ev);
        const indicator = String(parsed.indicator || ((ev && ev.indicator) || '')).trim();
        return indicator;
    }

    function isStrongIndicatorEvent(ev) {
        return isAllowedIndicator(eventIndicatorName(ev));
    }

    function isAlarmLikeEvent(ev) {
        if (!isStrongIndicatorEvent(ev)) return false;
        const signalHint = String((ev && ev.signal_hint) || '').trim().toUpperCase();
        if (signalHint === 'BUY' || signalHint === 'SELL') return true;

        const message = String((ev && ev.message) || '').trim();
        const msg = message.toLowerCase();
        const kind = String((ev && ev.kind) || '').trim().toLowerCase();
        const explicitAlert = kind === 'alert' || /\balert\s*[:\-]/i.test(message) || /\balarm\b/i.test(message);
        const obviousSignal =
            /\b(buy|sell|long|short)\b/i.test(message) ||
            /\bturned\s+up\b/i.test(message) ||
            /\bturned\s+down\b/i.test(message) ||
            /\bsignal\b/i.test(message);
        const noisyLifecycle =
            /^custom indicator /i.test(message) &&
            (/\b(loaded|removed|initialized|deinitialized|uninit)\b/i.test(message) || /\bsucces+fully\b/i.test(message));

        if (noisyLifecycle && !obviousSignal && !signalHint) return false;
        return explicitAlert || obviousSignal;
    }

    function chartEventKey(ev) {
        const e = ev || {};
        const src = String(e.source_path || e.source_file || '').trim();
        const t = String(e.time || '').trim();
        const raw = String(e.raw || e.message || '').trim();
        const ts = String(e.event_ts || '').trim();
        return `${src}|${t}|${raw}|${ts}`;
    }

    function rebuildChartEventKeyIndex(rows) {
        latestChartEventKeys.clear();
        const items = Array.isArray(rows) ? rows : [];
        for (const ev of items) {
            const key = chartEventKey(ev);
            if (key) latestChartEventKeys.set(key, Date.now());
        }
    }

    function compactChartEventKeyIndex() {
        if (latestChartEventKeys.size <= 10000) return;
        const cutoff = Date.now() - (6 * 60 * 60 * 1000);
        for (const [k, ts] of latestChartEventKeys.entries()) {
            if (Number(ts || 0) < cutoff) latestChartEventKeys.delete(k);
        }
    }

    function chartState(base) {
        const s = Object.assign({}, base || {});
        s.events_recent_24h = Array.isArray(latestChartEvents) ? latestChartEvents.slice() : [];
        return s;
    }

    function ingestRealtimeChartEvent(ev) {
        if (!ev || typeof ev !== 'object') return false;
        if (!isWithinLastHours(ev.event_ts || '', 24)) return false;
        if (!isAlarmLikeEvent(ev)) return false;
        const key = chartEventKey(ev);
        if (key && latestChartEventKeys.has(key)) return false;
        latestChartEvents.unshift(ev);
        if (latestChartEvents.length > 3000) latestChartEvents = latestChartEvents.slice(0, 3000);
        if (key) latestChartEventKeys.set(key, Date.now());
        compactChartEventKeyIndex();
        return true;
    }

    function chartGroupLabel(v) {
        const key = String(v || '').trim().toLowerCase();
        if (key === 'mt4') return 'MT4';
        if (key === 'mt5') return 'MT5';
        if (key === 'mt5_demo') return 'MT5-DEMO';
        if (key === 'unknown') return 'Unknown';
        return key ? key.toUpperCase() : 'Unknown';
    }

    function normalizeChartGroup(v) {
        const key = String(v || '').trim().toLowerCase();
        if (!key) return 'unknown';
        if (key === 'mt4' || key === 'mt5' || key === 'mt5_demo' || key === 'unknown') return key;
        if (key.includes('mql4') || key.includes('\\mt4\\')) return 'mt4';
        if (key.includes('demo') && (key.includes('mql5') || key.includes('\\mt5\\'))) return 'mt5_demo';
        if (key.includes('mql5') || key.includes('\\mt5\\')) return 'mt5';
        return 'unknown';
    }

    function eventChartGroup(ev) {
        const explicit = normalizeChartGroup((ev && ev.terminal_group) || '');
        if (explicit !== 'unknown') return explicit;
        const src = String((ev && (ev.source_path || ev.source_file)) || '');
        return normalizeChartGroup(src);
    }

    function eventInstanceKey(ev) {
        const raw = String((ev && ev.instance_key) || '').trim();
        if (raw) return raw.toLowerCase();
        const parsed = parseLegacyChartFromEvent(ev);
        const ind = normalizeIndicatorName(parsed.indicator || ((ev && ev.indicator) || ''));
        const sym = String(parsed.symbol || ((ev && ev.symbol) || '')).trim().toUpperCase();
        const tf = String(parsed.timeframe || ((ev && ev.timeframe) || '')).trim().toUpperCase();
        if (!ind || !sym || !tf) return '';
        return `${ind}|${sym}|${tf}`.toLowerCase();
    }

    function parseLegacyChartFromEvent(ev) {
        const out = { indicator: '', symbol: '', timeframe: '' };
        const indicatorRaw = String((ev && ev.indicator) || '').trim();
        const message = String((ev && ev.message) || '').trim();
        const needsParse = !indicatorRaw || /^indicators?$/i.test(indicatorRaw);
        if (!needsParse && String((ev && ev.symbol) || '').trim() && String((ev && ev.timeframe) || '').trim()) {
            return out;
        }
        const m = message.match(/(?:custom\s+indicator\s+)?(.+?)\s*\(([A-Z0-9._#-]{3,20}),([A-Z0-9]+)\)/i);
        if (!m) return out;
        const name = String(m[1] || '').trim();
        out.indicator = name;
        out.symbol = String(m[2] || '').trim().toUpperCase();
        out.timeframe = String(m[3] || '').trim().toUpperCase();
        return out;
    }

    function parseInstanceKeyParts(rawKey) {
        const key = String(rawKey || '').trim().toLowerCase();
        if (!key || key === 'all') return { indicator: '', symbol: '', timeframe: '' };
        const parts = key.split('|');
        if (parts.length < 3) return { indicator: '', symbol: '', timeframe: '' };
        return {
            indicator: String(parts[0] || '').trim(),
            symbol: String(parts[1] || '').trim().toUpperCase(),
            timeframe: String(parts[2] || '').trim().toUpperCase()
        };
    }

    function allInstanceRows(state) {
        const s = state || {};
        const rows = Array.isArray(s.chart_instances)
            ? s.chart_instances
            : (Array.isArray(s.instances) ? s.instances : []);
        return rows.slice();
    }

    function findInstanceRowByKey(state, key) {
        const k = String(key || '').trim().toLowerCase();
        if (!k || k === 'all') return null;
        const rows = allInstanceRows(state);
        const row = rows.find((x) => String((x || {}).instance_key || '').trim().toLowerCase() === k);
        return row || null;
    }

    function refreshChartAutomationActionState(state) {
        if (!els.chartAutomationBtn || !els.chartAutomationState) return;
        const targets = getVisibleChartAutomationTargets(state || latestState || {});
        if (!targets.length) {
            els.chartAutomationBtn.disabled = true;
            els.chartAutomationBtn.className = 'btn btn-sm btn-outline-success';
            els.chartAutomationBtn.textContent = 'Start Automation';
            els.chartAutomationState.textContent = 'No chart instance found in current table filter.';
            if (els.botStartBtn) els.botStartBtn.disabled = true;
            if (els.botStopBtn) els.botStopBtn.disabled = true;
            return;
        }
        const enabledCount = targets.filter((x) => !!x.enabled).length;
        const allEnabled = enabledCount === targets.length;
        els.chartAutomationBtn.disabled = false;
        els.chartAutomationBtn.className = `btn btn-sm btn-outline-${allEnabled ? 'danger' : 'success'}`;
        els.chartAutomationBtn.textContent = `${allEnabled ? 'Stop' : 'Start'} Automation (${targets.length})`;
        els.chartAutomationState.textContent = `${enabledCount}/${targets.length} charts running in current table filter.`;
        if (els.botStartBtn) els.botStartBtn.disabled = allEnabled;
        if (els.botStopBtn) els.botStopBtn.disabled = !enabledCount;
    }

    function rebuildChartSelectors(state) {
        if (!els.chartGroup || !els.chartInstance) return;
        const chartInstances = Array.isArray((state || {}).chart_instances)
            ? state.chart_instances
            : (Array.isArray((state || {}).instances) ? state.instances : []);
        const instances = chartInstances.slice();
        const events = Array.isArray((state || {}).events_recent_24h)
            ? state.events_recent_24h
            : (Array.isArray((state || {}).events) ? state.events : []);

        const groups = new Set(['mt4', 'mt5', 'mt5_demo']);
        for (const ev of events) groups.add(eventChartGroup(ev));
        for (const row of instances) groups.add(normalizeChartGroup((row && row.last_terminal_group) || ''));

        const groupOrder = ['mt4', 'mt5', 'mt5_demo', 'unknown'];
        const availableGroups = groupOrder.filter((g) => groups.has(g));

        const wantedGroup = String(selectedChartGroup || 'all').toLowerCase();
        const validGroup = (wantedGroup === 'all' || availableGroups.includes(wantedGroup)) ? wantedGroup : 'all';
        selectedChartGroup = validGroup;

        const groupOptions = [`<option value="all">All Groups</option>`];
        for (const g of availableGroups) {
            groupOptions.push(`<option value="${escapeHtml(g)}"${g === validGroup ? ' selected' : ''}>${escapeHtml(chartGroupLabel(g))}</option>`);
        }
        els.chartGroup.innerHTML = groupOptions.join('');

        const chartRowsBase = instances
            .map((r) => {
                const indicator = String((r && r.indicator) || '').trim();
                const symbol = String((r && r.symbol) || '').trim().toUpperCase();
                const timeframe = String((r && r.timeframe) || '').trim().toUpperCase();
                const key = String((r && r.instance_key) || '').trim().toLowerCase();
                const g = normalizeChartGroup((r && r.last_terminal_group) || '');
                return { indicator, symbol, timeframe, key, group: g };
            })
            .filter((r) => isAllowedIndicator(r.indicator))
            .filter((r) => r.key && r.indicator && r.symbol && r.timeframe);

        const chartRowsFromEvents = events
            .filter((ev) => isAlarmLikeEvent(ev))
            .filter((ev) => isWithinLastHours((ev && ev.event_ts) || '', 24))
            .map((ev) => {
                const parsed = parseLegacyChartFromEvent(ev);
                const indicator = String(parsed.indicator || (ev && ev.indicator) || '').trim();
                const symbol = String(parsed.symbol || (ev && ev.symbol) || '').trim().toUpperCase();
                const timeframe = String(parsed.timeframe || (ev && ev.timeframe) || '').trim().toUpperCase();
                const g = eventChartGroup(ev);
                const key = eventInstanceKey(ev);
                return { indicator, symbol, timeframe, key, group: g };
            })
            .filter((r) => r.key && r.indicator && r.symbol && r.timeframe);

        const chartRowsMap = new Map();
        for (const row of chartRowsBase) chartRowsMap.set(row.key, row);
        for (const row of chartRowsFromEvents) {
            if (!chartRowsMap.has(row.key)) chartRowsMap.set(row.key, row);
        }
        const chartRows = Array.from(chartRowsMap.values())
            .filter((r) => validGroup === 'all' || r.group === validGroup)
            .sort((a, b) => {
                const ka = `${a.indicator}|${a.symbol}|${a.timeframe}`.toLowerCase();
                const kb = `${b.indicator}|${b.symbol}|${b.timeframe}`.toLowerCase();
                if (ka < kb) return -1;
                if (ka > kb) return 1;
                return 0;
            });

        const wantedInst = String(selectedChartInstance || 'all').toLowerCase();
        const validInst = (wantedInst === 'all' || chartRows.some((r) => r.key === wantedInst)) ? wantedInst : 'all';
        selectedChartInstance = validInst;

        const chartOptions = [`<option value="all">All Charts</option>`];
        for (const row of chartRows) {
            const lbl = `${row.indicator} | ${prettySymbol(row.symbol)} ${row.timeframe} [${chartGroupLabel(row.group)}]`;
            chartOptions.push(`<option value="${escapeHtml(row.key)}"${row.key === validInst ? ' selected' : ''}>${escapeHtml(lbl)}</option>`);
        }
        els.chartInstance.innerHTML = chartOptions.join('');
    }

    function getFilteredChartAlarmEvents(state) {
        const rows = Array.isArray((state || {}).events_recent_24h)
            ? state.events_recent_24h.slice()
            : (Array.isArray((state || {}).events) ? state.events.slice() : []);
        const groupFilter = String(selectedChartGroup || 'all').toLowerCase();
        const instanceFilter = String(selectedChartInstance || 'all').toLowerCase();

        return rows
            .filter((ev) => isAlarmLikeEvent(ev))
            .filter((ev) => isWithinLastHours((ev && ev.event_ts) || '', 24))
            .filter((ev) => {
                if (groupFilter === 'all') return true;
                return eventChartGroup(ev) === groupFilter;
            })
            .filter((ev) => {
                if (instanceFilter === 'all') return true;
                return eventInstanceKey(ev) === instanceFilter;
            })
            .sort((a, b) => {
                const ta = Date.parse(String((a && a.event_ts) || '')) || 0;
                const tb = Date.parse(String((b && b.event_ts) || '')) || 0;
                return tb - ta;
            });
    }

    function getVisibleChartAutomationTargets(state) {
        const filtered = getFilteredChartAlarmEvents(state || {});
        const current = state || latestState || {};
        const byKey = new Map();
        for (const ev of filtered) {
            const key = String(eventInstanceKey(ev) || '').trim().toLowerCase();
            if (!key || byKey.has(key)) continue;
            const row = findInstanceRowByKey(current, key);
            const parsed = parseLegacyChartFromEvent(ev);
            const indicator = String((row && row.indicator) || parsed.indicator || (ev && ev.indicator) || '').trim();
            const symbol = String((row && row.symbol) || parsed.symbol || (ev && ev.symbol) || '').trim().toUpperCase();
            const timeframe = String((row && row.timeframe) || parsed.timeframe || (ev && ev.timeframe) || '').trim().toUpperCase();
            if (!indicator || !symbol || !timeframe || !isAllowedIndicator(indicator)) continue;
            byKey.set(key, {
                key,
                indicator,
                symbol,
                timeframe,
                enabled: !!(row && row.effective_automation_enabled),
            });
        }
        return Array.from(byKey.values());
    }

    function renderChartAlarmLogs(state) {
        if (!els.chartLogBody) return;
        const filtered = getFilteredChartAlarmEvents(state || {});

        if (els.chartStats) {
            els.chartStats.textContent = `Rows: ${filtered.length} | Last 24h | Latest first`;
        }

        if (!filtered.length) {
            els.chartLogBody.innerHTML = '<tr><td colspan="6" class="text-muted text-center py-3">No alarm rows in the last 24 hours for selected filter.</td></tr>';
            return;
        }

        els.chartLogBody.innerHTML = filtered.map((ev) => {
            const ts = formatTs((ev && ev.event_ts) || '');
            const group = chartGroupLabel(eventChartGroup(ev));
            const parsed = parseLegacyChartFromEvent(ev);
            const indicator = String(parsed.indicator || (ev && ev.indicator) || '').trim();
            const symbol = String(parsed.symbol || (ev && ev.symbol) || '').trim().toUpperCase();
            const tf = String(parsed.timeframe || (ev && ev.timeframe) || '').trim().toUpperCase();
            const chart = `${indicator || '-'}${(symbol || tf) ? ` | ${prettySymbol(symbol)}${tf ? ` ${tf}` : ''}` : ''}`;
            const kind = String((ev && ev.kind) || 'log').trim().toLowerCase();
            const msg = String((ev && ev.message) || (ev && ev.raw) || '').trim();
            const file = compactPath(String((ev && (ev.source_path || ev.source_file)) || '').trim());
            return `<tr>
                <td class="small text-muted">${escapeHtml(ts)}</td>
                <td><span class="badge text-bg-dark">${escapeHtml(group)}</span></td>
                <td>${escapeHtml(chart)}</td>
                <td><span class="badge text-bg-secondary">${escapeHtml(kind.toUpperCase())}</span></td>
                <td style="white-space: pre-wrap;">${escapeHtml(msg)}</td>
                <td class="small text-muted">${escapeHtml(file || '-')}</td>
            </tr>`;
        }).join('');
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
            const count = Number(s.watched_files_count || 0);
            const stale = Number(s.watched_files_stale_count || 0);
            const newestAge = Number(s.watched_files_newest_age_sec || 0);
            const newestTs = formatTs(s.watched_files_newest_ts || '');
            const newestPath = compactPath(s.watched_files_newest_path || '');
            els.filesLine.textContent = `Watched files: ${count} | stale: ${stale} | newest write: ${newestTs} (${Math.round(newestAge)}s ago) | ${newestPath}`;
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
        const allRows = Array.isArray((state || {}).indicators)
            ? state.indicators.slice().filter((r) => isAllowedIndicator(String((r || {}).indicator || (r || {}).key || '')))
            : [];
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
            const symbolPretty = prettySymbol(symbol);
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
                    <td>${escapeHtml((symbolPretty !== '-' && tf) ? `${symbolPretty} ${tf}` : ((symbolPretty !== '-' ? symbolPretty : (tf || '-'))))}</td>
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
        const allRows = Array.isArray((state || {}).instances)
            ? state.instances.slice().filter((r) => isAllowedIndicator(String((r || {}).indicator || (r || {}).indicator_key || '')))
            : [];
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
            const symbolPretty = prettySymbol(symbol);
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
                    <td>${escapeHtml(symbolPretty)}</td>
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
            els.execBody.innerHTML = '<tr><td colspan="10" class="text-muted text-center py-3">No execution logs yet.</td></tr>';
            return;
        }
        items.sort((a, b) => {
            const ta = Date.parse(String((a && (a.event_ts || a.ts)) || '')) || 0;
            const tb = Date.parse(String((b && (b.event_ts || b.ts)) || '')) || 0;
            return tb - ta;
        });
        els.execBody.innerHTML = items.map((r) => {
            const ts = formatTs((r && (r.event_ts || r.ts)) || '');
            const openedAt = formatTs((r && r.opened_at) || '');
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
            const baseMsg = String((r && r.message) || '').trim();
            const realized = Number((r && r.realized_pnl));
            const maxProfit = Number((r && r.max_profit));
            const maxLoss = Number((r && r.max_loss));
            const closeReason = String((r && r.close_reason) || '').trim();
            const extra = [];
            if (Number.isFinite(realized)) extra.push(`realized=${formatPnl(realized)}`);
            if (Number.isFinite(maxProfit)) extra.push(`max=${formatPnl(maxProfit)}`);
            if (Number.isFinite(maxLoss)) extra.push(`min=${formatPnl(maxLoss)}`);
            if (closeReason) extra.push(`reason=${closeReason}`);
            const msg = escapeHtml([baseMsg, extra.join(' | ')].filter(Boolean).join(' | '));
            return `<tr><td class="small text-muted">${ts}</td><td class="small text-muted">${openedAt}</td><td>${srcType}</td><td>${srcName}</td><td>${symTf}</td><td>${dir}</td><td>${lot}</td><td><span class="badge text-bg-secondary">${status}</span></td><td>${ticket}</td><td>${msg}</td></tr>`;
        }).join('');
    }

    function renderBotMonitor(monitor) {
        const m = monitor && typeof monitor === 'object' ? monitor : {};
        const ladderRows = Array.isArray(m.rows) ? m.rows.slice() : [];
        const botRows = Array.isArray(m.bot_rows) ? m.bot_rows.slice() : [];
        if (els.botUpdated) {
            els.botUpdated.textContent = `Updated: ${formatTs(m.updated_at || '')}`;
        }
        if (els.botEnabledCount) {
            const enabled = Number(m.bot_active_count || botRows.length || 0);
            els.botEnabledCount.textContent = String(enabled);
        }
        if (els.botActiveCount) {
            els.botActiveCount.textContent = String(Number(m.active_count || ladderRows.length || 0));
        }
        if (!els.botBody) return;

        const normalizeIndicator = (v) => String(v || '').trim().toLowerCase().replace(/\s+/g, ' ');
        const comboKey = (indicator, symbol, timeframe) =>
            `${normalizeIndicator(indicator)}|${String(symbol || '').trim().toUpperCase()}|${String(timeframe || '').trim().toUpperCase()}`;

        const ladderByCombo = new Map();
        for (const row of ladderRows) {
            const key = comboKey((row && (row.indicator || row.source_name)) || '', (row && row.symbol) || '', (row && row.timeframe) || '');
            if (!key) continue;
            ladderByCombo.set(key, row);
        }

        const displayRows = [];
        for (const row of ladderRows) {
            displayRows.push(Object.assign({}, row, { _state: 'OPEN' }));
        }
        for (const bot of botRows) {
            const key = comboKey((bot && bot.indicator) || '', (bot && bot.symbol) || '', (bot && bot.timeframe) || '');
            if (!key || ladderByCombo.has(key) || !bot || bot.has_open_ladder) continue;
            displayRows.push({
                opened_at: String((bot && bot.last_seen) || ''),
                indicator: String((bot && bot.indicator) || ''),
                symbol: String((bot && bot.symbol) || '').toUpperCase(),
                timeframe: String((bot && bot.timeframe) || '').toUpperCase(),
                direction: '-',
                ticket: 0,
                next_tp_index: 0,
                total_tps: 0,
                max_profit: null,
                max_loss: null,
                current_profit: null,
                _state: 'IDLE'
            });
        }

        if (!displayRows.length) {
            els.botBody.innerHTML = '<tr><td colspan="9" class="text-muted text-center py-3">No active MT4 bots.</td></tr>';
            return;
        }

        displayRows.sort((a, b) => {
            const ta = Date.parse(String((a && a.opened_at) || '')) || 0;
            const tb = Date.parse(String((b && b.opened_at) || '')) || 0;
            return tb - ta;
        });
        els.botBody.innerHTML = displayRows.map((r) => {
            const opened = formatTs((r && r.opened_at) || '');
            const indicator = String((r && (r.indicator || r.source_name)) || '-').trim();
            const sym = String((r && r.symbol) || '').trim().toUpperCase();
            const tf = String((r && r.timeframe) || '').trim().toUpperCase();
            const symTf = (sym || tf) ? `${sym}${tf ? ` ${tf}` : ''}` : '-';
            const dir = String((r && r.direction) || '-').trim().toUpperCase() || '-';
            const ticketRaw = Number((r && r.ticket) || 0);
            const ticket = ticketRaw > 0 ? String(ticketRaw) : '-';
            const nextTp = Number((r && r.next_tp_index) || 0);
            const totalTp = Number((r && r.total_tps) || 0);
            const rowState = String((r && r._state) || '').toUpperCase();
            const nextTpText = rowState === 'IDLE'
                ? 'IDLE'
                : (nextTp > 0 && totalTp > 0 ? `TP${nextTp}/${totalTp}` : 'OPEN');
            const maxP = formatPnl((r && r.max_profit));
            const maxL = formatPnl((r && r.max_loss));
            const live = formatPnl((r && r.current_profit));
            return `<tr>
                <td class="small text-muted">${escapeHtml(opened)}</td>
                <td>${escapeHtml(indicator)}</td>
                <td>${escapeHtml(symTf)}</td>
                <td>${escapeHtml(dir)}</td>
                <td>${escapeHtml(ticket)}</td>
                <td>${escapeHtml(nextTpText)}</td>
                <td>${escapeHtml(maxP)}</td>
                <td>${escapeHtml(maxL)}</td>
                <td>${escapeHtml(live)}</td>
            </tr>`;
        }).join('');
    }

    async function setVisibleChartAutomation(desiredEnabled) {
        const targets = getVisibleChartAutomationTargets(latestState || {});
        if (!targets.length) {
            showAlert('No chart found in current table filter.', 'error');
            return;
        }
        const desired = !!desiredEnabled;
        let okCount = 0;
        let failCount = 0;
        for (const t of targets) {
            try {
                await updateInstanceSettings(
                    t.indicator,
                    t.symbol,
                    t.timeframe,
                    { enabled: desired },
                    { render: false }
                );
                okCount += 1;
            } catch (_) {
                failCount += 1;
            }
        }
        await loadState(false);
        showAlert(
            `${desired ? 'Started' : 'Stopped'} automation for ${okCount}/${targets.length} charts.${failCount ? ` Failed: ${failCount}.` : ''}`,
            failCount ? 'info' : 'success'
        );
    }

    function formatPnl(v) {
        const n = Number(v);
        if (!Number.isFinite(n)) return '-';
        const sign = n > 0 ? '+' : '';
        return `${sign}${n.toFixed(2)}`;
    }

    function renderExecutionReport(report) {
        if (!els.execReportBody) return;
        const rows = Array.isArray((report && report.rows) ? report.rows : [])
            ? report.rows.slice()
            : [];
        if (els.execReportMeta) {
            const ts = formatTs((report && report.generated_at) || '');
            els.execReportMeta.textContent = `By source + symbol/timeframe (highest pnl first) | Updated: ${ts}`;
        }
        if (!rows.length) {
            els.execReportBody.innerHTML = '<tr><td colspan="8" class="text-muted text-center py-3">No performance rows yet.</td></tr>';
            return;
        }
        els.execReportBody.innerHTML = rows.map((r) => {
            const sourceType = String((r && r.source_type) || '').trim().toLowerCase();
            const baseName = String((r && (r.combo_name || r.source_name || r.indicator)) || '-').trim();
            const symbol = String((r && r.symbol) || '').trim().toUpperCase();
            const tf = String((r && r.timeframe) || '').trim().toUpperCase();
            const combo = `${baseName}${(symbol || tf) ? ` | ${symbol}${tf ? ` ${tf}` : ''}` : ''}`;
            const opened = Number((r && r.opened_count) || 0);
            const closed = Number((r && r.closed_count) || 0);
            const winRate = Number((r && r.win_rate_pct) || 0);
            const totalPnl = formatPnl((r && r.total_realized_pnl));
            const avgPnl = formatPnl((r && r.avg_realized_pnl));
            const best = formatPnl((r && r.best_trade_pnl));
            const worst = formatPnl((r && r.worst_trade_pnl));
            const srcBadge = sourceType === 'mt_indicator' ? 'text-bg-primary' : 'text-bg-dark';
            return `<tr>
                <td><span class="badge ${srcBadge} me-1">${escapeHtml(sourceType || 'unknown')}</span>${escapeHtml(combo)}</td>
                <td>${opened}</td>
                <td>${closed}</td>
                <td>${winRate.toFixed(1)}%</td>
                <td>${escapeHtml(totalPnl)}</td>
                <td>${escapeHtml(avgPnl)}</td>
                <td>${escapeHtml(best)}</td>
                <td>${escapeHtml(worst)}</td>
            </tr>`;
        }).join('');
    }

    function chartSocketUrl() {
        const configuredApiBase = String((window && window.PROTRADING_API_BASE_URL) || '').trim();
        if (configuredApiBase) {
            try {
                const apiUrl = new URL(configuredApiBase, window.location.origin);
                const wsProtocol = apiUrl.protocol === 'https:' ? 'wss' : 'ws';
                return `${wsProtocol}://${apiUrl.host}/ws/mt4-log-automation`;
            } catch (_) {
                // fallback below
            }
        }
        const wsProtocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
        const wsHost = window.location.host;
        return `${wsProtocol}://${wsHost}/ws/mt4-log-automation`;
    }

    function sendChartSocketFilter() {
        if (!chartSocket || chartSocket.readyState !== WebSocket.OPEN) return;
        chartSocket.send(JSON.stringify({
            type: 'set_filter',
            chart_group: String(selectedChartGroup || 'all').toLowerCase(),
            instance_key: String(selectedChartInstance || 'all').toLowerCase()
        }));
    }

    function connectChartSocket() {
        try {
            if (chartSocket) {
                try { chartSocket.close(); } catch (_) { /* ignore */ }
                chartSocket = null;
            }
            chartSocket = new WebSocket(chartSocketUrl());
        } catch (_) {
            chartSocket = null;
            return;
        }

        chartSocket.onopen = () => {
            chartSocketRetryMs = 1000;
            sendChartSocketFilter();
            if (els.chartStats) {
                const base = String(els.chartStats.textContent || 'Latest first');
                const clean = base.replace(/\s*\|\s*WS:\s*\w+/i, '').trim();
                els.chartStats.textContent = `${clean} | WS: LIVE`;
            }
        };

        chartSocket.onmessage = (evt) => {
            let payload = null;
            try { payload = JSON.parse(String(evt.data || '{}')); } catch (_) { payload = null; }
            if (!payload || typeof payload !== 'object') return;
            if (String(payload.type || '').trim() !== 'mt4la_alert_event') return;
            const ev = payload.event;
            if (!ingestRealtimeChartEvent(ev)) return;
            const s = chartState(latestState || {});
            rebuildChartSelectors(s);
            renderChartAlarmLogs(s);
        };

        chartSocket.onclose = () => {
            if (els.chartStats) {
                const base = String(els.chartStats.textContent || 'Latest first');
                const clean = base.replace(/\s*\|\s*WS:\s*\w+/i, '').trim();
                els.chartStats.textContent = `${clean} | WS: OFF`;
            }
            const nextMs = Math.min(15000, Math.max(1000, chartSocketRetryMs));
            chartSocketRetryMs = Math.min(15000, nextMs * 2);
            window.setTimeout(() => {
                connectChartSocket();
            }, nextMs);
        };

        chartSocket.onerror = () => {
            // rely on onclose reconnect
        };
    }

    async function loadIndicatorLogs(indicator) {
        const name = String(indicator || '').trim();
        if (!name) return;
        const data = await req(`/api/mt4/log-automation/indicator-logs?indicator=${encodeURIComponent(name)}&limit=400&alerts_only=1`);
        renderIndicatorLogs(data.indicator || name, data.rows || []);
    }

    async function loadState(force) {
        const data = await req('/api/mt4/log-automation/state?limit=1000');
        latestState = data || {};
        latestChartEvents = Array.isArray((data || {}).events_recent_24h) ? (data.events_recent_24h).slice() : [];
        rebuildChartEventKeyIndex(latestChartEvents);
        fillForm((data || {}).config || {}, !!force);
        renderStatus(data || {});
        renderIndicators(data || {});
        renderInstances(data || {});
        const s = chartState(data || {});
        rebuildChartSelectors(s);
        renderChartAlarmLogs(s);
        refreshChartAutomationActionState(data || {});
        latestExecLogs = Array.isArray((data || {}).execution_logs) ? (data.execution_logs).slice() : [];
        renderExecutionLogs(latestExecLogs);
        renderExecutionReport((data || {}).execution_report || {});
        renderBotMonitor((data || {}).mt4_bot_monitor || {});
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
        latestChartEvents = Array.isArray((data || {}).events_recent_24h) ? (data.events_recent_24h).slice() : latestChartEvents;
        rebuildChartEventKeyIndex(latestChartEvents);
        const s = chartState(data || {});
        rebuildChartSelectors(s);
        renderChartAlarmLogs(s);
        refreshChartAutomationActionState(data || {});
        latestExecLogs = Array.isArray((data || {}).execution_logs) ? (data.execution_logs).slice() : latestExecLogs;
        renderExecutionLogs(latestExecLogs);
        renderExecutionReport((data || {}).execution_report || {});
        renderBotMonitor((data || {}).mt4_bot_monitor || {});
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
        latestChartEvents = Array.isArray((latestState || {}).events_recent_24h) ? (latestState.events_recent_24h).slice() : latestChartEvents;
        rebuildChartEventKeyIndex(latestChartEvents);
        const s = chartState(latestState || {});
        rebuildChartSelectors(s);
        renderChartAlarmLogs(s);
        refreshChartAutomationActionState(latestState || {});
        latestExecLogs = Array.isArray((latestState || {}).execution_logs) ? (latestState.execution_logs).slice() : latestExecLogs;
        renderExecutionLogs(latestExecLogs);
        renderExecutionReport((latestState || {}).execution_report || {});
        renderBotMonitor((latestState || {}).mt4_bot_monitor || {});
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

    async function updateInstanceSettings(indicator, symbol, timeframe, options, uiOptions) {
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
        const render = !uiOptions || uiOptions.render !== false;
        latestState = data || latestState || {};
        if (render) {
            renderStatus(latestState || {});
            renderIndicators(latestState || {});
            renderInstances(latestState || {});
            latestChartEvents = Array.isArray((latestState || {}).events_recent_24h) ? (latestState.events_recent_24h).slice() : latestChartEvents;
            rebuildChartEventKeyIndex(latestChartEvents);
            const s = chartState(latestState || {});
            rebuildChartSelectors(s);
            renderChartAlarmLogs(s);
            refreshChartAutomationActionState(latestState || {});
            latestExecLogs = Array.isArray((latestState || {}).execution_logs) ? (latestState.execution_logs).slice() : latestExecLogs;
            renderExecutionLogs(latestExecLogs);
            renderExecutionReport((latestState || {}).execution_report || {});
        }
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

        if (els.chartGroup) {
            els.chartGroup.addEventListener('change', () => {
                selectedChartGroup = String((els.chartGroup && els.chartGroup.value) || 'all').toLowerCase();
                const s = chartState(latestState || {});
                rebuildChartSelectors(s);
                renderChartAlarmLogs(s);
                refreshChartAutomationActionState(latestState || {});
                sendChartSocketFilter();
            });
        }

        if (els.chartInstance) {
            els.chartInstance.addEventListener('change', () => {
                selectedChartInstance = String((els.chartInstance && els.chartInstance.value) || 'all').toLowerCase();
                const s = chartState(latestState || {});
                renderChartAlarmLogs(s);
                refreshChartAutomationActionState(latestState || {});
                sendChartSocketFilter();
            });
        }

        if (els.chartAutomationBtn) {
            els.chartAutomationBtn.addEventListener('click', async () => {
                els.chartAutomationBtn.disabled = true;
                try {
                    const targets = getVisibleChartAutomationTargets(latestState || {});
                    if (!targets.length) {
                        showAlert('No chart found in current table filter.', 'error');
                        return;
                    }
                    const allEnabled = targets.every((t) => !!t.enabled);
                    await setVisibleChartAutomation(!allEnabled);
                } catch (err) {
                    showAlert(`Chart automation toggle failed: ${String(err.message || err)}`, 'error');
                } finally {
                    els.chartAutomationBtn.disabled = false;
                    refreshChartAutomationActionState(latestState || {});
                }
            });
        }

        if (els.botStartBtn) {
            els.botStartBtn.addEventListener('click', async () => {
                els.botStartBtn.disabled = true;
                try {
                    await setVisibleChartAutomation(true);
                } catch (err) {
                    showAlert(`Start bots failed: ${String(err.message || err)}`, 'error');
                } finally {
                    refreshChartAutomationActionState(latestState || {});
                }
            });
        }
        if (els.botStopBtn) {
            els.botStopBtn.addEventListener('click', async () => {
                els.botStopBtn.disabled = true;
                try {
                    await setVisibleChartAutomation(false);
                } catch (err) {
                    showAlert(`Stop bots failed: ${String(err.message || err)}`, 'error');
                } finally {
                    refreshChartAutomationActionState(latestState || {});
                }
            });
        }

        try {
            await loadState(true);
        } catch (err) {
            showAlert(`Load failed: ${String(err.message || err)}`, 'error');
        }

        connectChartSocket();
        window.addEventListener('beforeunload', () => {
            try {
                if (chartSocket) chartSocket.close();
            } catch (_) { /* ignore */ }
        });

        if (pollTimer) clearInterval(pollTimer);
        pollTimer = setInterval(async () => {
            try {
                await loadState(false);
            } catch (_) {
                // keep silent in poll loop
            }
        }, 10000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();

