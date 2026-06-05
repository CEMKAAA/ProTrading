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
        spreadGovToggle: document.getElementById('v2-spread-gov-toggle'),
        spreadGovStatus: document.getElementById('v2-spread-gov-status'),
        spreadGovContext: document.getElementById('v2-spread-gov-context'),
        liqGovToggle: document.getElementById('v2-liq-gov-toggle'),
        liqGovStatus: document.getElementById('v2-liq-gov-status'),
        liqGovTf: document.getElementById('v2-liq-gov-tf'),
        liqGovLookback: document.getElementById('v2-liq-gov-lookback'),
        liqGovFreshness: document.getElementById('v2-liq-gov-freshness'),
        liqGovRejection: document.getElementById('v2-liq-gov-rejection'),
        liqGovContinuation: document.getElementById('v2-liq-gov-continuation'),
        liqGovBlockNoSetup: document.getElementById('v2-liq-gov-block-no-setup'),
        liqGovSave: document.getElementById('v2-liq-gov-save'),
        liqGovContext: document.getElementById('v2-liq-gov-context'),
        liqScanSymbols: document.getElementById('v2-liq-scan-symbols'),
        liqScanTf: document.getElementById('v2-liq-scan-tf'),
        liqScanRun: document.getElementById('v2-liq-scan-run'),
        liqWatchAdd: document.getElementById('v2-liq-watch-add'),
        liqWatchClear: document.getElementById('v2-liq-watch-clear'),
        liqScanStatus: document.getElementById('v2-liq-scan-status'),
        liqScanResults: document.getElementById('v2-liq-scan-results'),
        telemetryBody: document.getElementById('v2-telemetry-body'),
        telemetryFilter: document.getElementById('v2-telemetry-filter'),
        symbolSessionBody: document.getElementById('v2-symbol-session-body'),
        symbolSessionSave: document.getElementById('v2-symbol-session-save'),
        symbolSessionPreset: document.getElementById('v2-symbol-session-preset'),
        symbolSessionStatus: document.getElementById('v2-symbol-session-status'),
        entryExitPanel: document.getElementById('v2-entry-exit-panel'),
        entryExitBody: document.getElementById('v2-entry-exit-body'),
        openBody: document.getElementById('v2-open-body'),
        instanceBody: document.getElementById('v2-instance-body'),
        auditBody: document.getElementById('v2-audit-body'),
        liqAuditBody: document.getElementById('v2-liq-audit-body'),
        liqAuditCount: document.getElementById('v2-liq-audit-count'),
        openFilter: document.getElementById('v2-open-filter'),
        instanceFilter: document.getElementById('v2-instance-filter'),
        instanceFilterAtomic: document.getElementById('v2-instance-filter-atomic'),
        instanceFilterAtomicRegime: document.getElementById('v2-instance-filter-atomic-regime'),
        instanceFilterSignatics: document.getElementById('v2-instance-filter-signatics'),
        instanceStartAll: document.getElementById('v2-instance-start-all'),
        instanceAllNormal: document.getElementById('v2-instance-all-normal'),
        instanceResetRegistry: document.getElementById('v2-instance-reset-registry'),
        auditOpen: document.getElementById('v2-audit-open'),
        auditReload: document.getElementById('v2-audit-reload'),
        auditCleanOld: document.getElementById('v2-audit-clean-old'),
        auditModal: document.getElementById('v2-audit-modal'),
        auditModalStatus: document.getElementById('v2-audit-modal-status'),
        auditFilter: document.getElementById('v2-audit-filter'),
        auditSymbolFilter: document.getElementById('v2-audit-symbol-filter'),
        auditStrategyFilter: document.getElementById('v2-audit-strategy-filter'),
        auditModeFilter: document.getElementById('v2-audit-mode-filter'),
        liqAuditFilter: document.getElementById('v2-liq-audit-filter')
    };

    let state = null;
    let timer = null;
    let uiTimer = null;
    let stateLoadInFlight = false;
    let stateLoadController = null;
    let stateRefreshPausedUntil = 0;
    let priceTimer = null;
    let priceLoadInFlight = false;
    let priceLoadController = null;
    let priceWs = null;
    let priceWsConnected = false;
    let priceWsReconnectTimer = null;
    let priceWsLastTicketsKey = '';
    let priceWsLastMessageAtMs = 0;
    let priceSmoothRaf = null;
    let priceSmoothLastMs = 0;
    let priceSmoothLastDomMs = 0;
    let auditTimer = null;
    let auditLoadInFlight = false;
    let auditLoadController = null;
    let spreadTimer = null;
    let spreadLoadInFlight = false;
    let spreadLoadController = null;
    let tradeRailOverlay = null;
    let tradeRailOverlayTicket = '';
    let liquidityScanRows = [];
    const priceVisuals = new Map();
    const spreadSnapshotBySymbol = new Map();
    const SPREAD_SNAPSHOT_FIELDS = [
        'mt4_bid',
        'mt4_ask',
        'mt4_point',
        'mt4_spread_points',
        'spread_source',
        'spread_resolved_symbol',
        'spread_tick_time',
        'spread_status',
        'spread_label',
        'spread_guard'
    ];
    const PRICE_SMOOTH_DEFAULT_MS = 260;
    const PRICE_SMOOTH_MIN_MS = 50;
    const PRICE_SMOOTH_MAX_MS = 650;
    const PRICE_SMOOTH_DOM_MS = 16;
    const PRICE_WS_INTERVAL_MS = 200;

    function esc(v) {
        return String(v == null ? '' : v)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function cssEsc(v) {
        const raw = String(v == null ? '' : v);
        if (window.CSS && typeof window.CSS.escape === 'function') return window.CSS.escape(raw);
        return raw.replace(/["\\]/g, '\\$&');
    }

    let apiBase = '/api';

    function apiPath(path) {
        const clean = String(path || '');
        return `${apiBase}${clean.startsWith('/') ? clean : `/${clean}`}`;
    }

    async function apiFetch(path, options) {
        const clean = String(path || '');
        const primary = apiPath(clean);
        let res = await fetch(primary, options || {});
        if (res.status === 404 && apiBase === '/api') {
            const fallback = `/api/v1${clean.startsWith('/') ? clean : `/${clean}`}`;
            const retry = await fetch(fallback, options || {});
            if (retry.ok || retry.status !== 404) {
                apiBase = '/api/v1';
                return retry;
            }
        }
        return res;
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

    function parsePositiveInt(raw, fallback) {
        const n = Number(String(raw == null ? '' : raw).trim().replace(',', '.'));
        if (!Number.isFinite(n)) return fallback == null ? null : fallback;
        return Math.max(0, Math.round(n));
    }

    function parseUnitFloat(raw, fallback) {
        const n = Number(String(raw == null ? '' : raw).trim().replace(',', '.'));
        if (!Number.isFinite(n)) return fallback == null ? null : fallback;
        return Math.max(0, Math.min(1, n));
    }

    function parsePercentInput(raw, fallback) {
        const n = Number(String(raw == null ? '' : raw).trim().replace(',', '.'));
        if (!Number.isFinite(n)) return fallback == null ? null : fallback;
        const unit = n > 1 ? n / 100 : n;
        return Math.max(0, Math.min(2, Number(unit.toFixed(4))));
    }

    function pctDisplay(value, fallback) {
        const n = Number(value);
        const unit = Number.isFinite(n) ? n : Number(fallback || 0);
        return String(Math.round(Math.max(0, unit) * 1000) / 10);
    }

    function normalizeWindowsText(raw) {
        return String(raw || '')
            .split(/[\n,;|]+/)
            .map(x => x.trim())
            .filter(Boolean)
            .join('\n');
    }

    function normalizeSymbolFamily(symbol) {
        const s = String(symbol || '').trim().toUpperCase();
        if (s.includes('USTEC')) return 'USTEC';
        if (s.startsWith('US30')) return 'US30';
        if (s.startsWith('DE30')) return 'DE30';
        if (s.startsWith('JP225')) return 'JP225';
        if (s.startsWith('AUS200')) return 'AUS200';
        const compact = s.replace(/[^A-Z0-9]/g, '');
        if (compact.endsWith('M')) return compact.slice(0, -1);
        return compact;
    }

    function defaultTradeAllowedWindowsForScope(scope) {
        const profile = String((scope || {}).profile || '').trim().toLowerCase();
        if (profile !== 'atomic' && profile !== 'atomic_regime') return [];
        switch (normalizeSymbolFamily((scope || {}).symbol)) {
            case 'USTEC':
            case 'US30':
                return ['13:30-18:00', '07:00-10:30'];
            case 'DE30':
                return ['07:00-11:30', '13:30-16:00'];
            case 'JP225':
            case 'AUS200':
                return ['00:00-02:30', '03:30-05:30'];
            case 'EURUSD':
                return ['12:30-16:30', '07:00-10:30'];
            case 'USDJPY':
                return ['12:30-16:30', '00:00-04:00'];
            case 'USDCAD':
                return ['12:30-16:30'];
            case 'EURJPY':
            case 'GBPJPY':
                return ['07:00-11:30', '00:00-04:00'];
            default:
                return [];
        }
    }

    function isAtomicTradeWindowScope(scope) {
        const p = String((scope || {}).profile || '').trim().toLowerCase();
        return p === 'atomic' || p === 'atomic_regime';
    }

    async function loadState() {
        if (stateLoadInFlight || Date.now() < stateRefreshPausedUntil) return;
        stateLoadInFlight = true;
        stateLoadController = new AbortController();
        const timeoutId = window.setTimeout(() => {
            try { stateLoadController.abort(); } catch (_) {}
        }, 30000);
        try {
            const stateQuery = [
                'limit=120',
                'include_audit=false',
                'include_liquidity=false',
                'include_rsi=false',
                'include_ohlc=false',
                'include_execution_report=false',
                'include_live_positions=true',
                'include_spreads=false'
            ].join('&');
            const res = await apiFetch(`/indicator-bridge/state?${stateQuery}`, {
                credentials: 'same-origin',
                signal: stateLoadController.signal
            });
            const data = await res.json();
            if (!res.ok || !data || data.ok === false) {
                throw new Error((data && (data.error || data.detail)) || `HTTP ${res.status}`);
            }
            if (state) {
                if (data.execution_logs && data.execution_logs.disabled) {
                    data.execution_logs = (state || {}).execution_logs || data.execution_logs;
                }
                if (data.liquidity_audit_logs && data.liquidity_audit_logs.disabled) {
                    data.liquidity_audit_logs = (state || {}).liquidity_audit_logs || data.liquidity_audit_logs;
                }
            }
            state = data;
            state._client_loaded_at_ms = Date.now();
            applyCachedSpreadSnapshotsToState();
            if (els.alert) els.alert.innerHTML = '';
            render();
            ensurePriceWebSocket();
            sendPriceWsSubscription(false);
            loadFastPrices().catch(() => {});
        } catch (err) {
            if (err && err.name === 'AbortError') return;
            throw err;
        } finally {
            window.clearTimeout(timeoutId);
            stateLoadInFlight = false;
            stateLoadController = null;
        }
    }

    async function loadAuditLogs() {
        if (auditLoadInFlight) return;
        auditLoadInFlight = true;
        auditLoadController = new AbortController();
        const timeoutId = window.setTimeout(() => {
            try { auditLoadController.abort(); } catch (_) {}
        }, 10000);
        try {
            if (els.auditModalStatus) els.auditModalStatus.textContent = "Loading today's audit rows...";
            const res = await apiFetch('/indicator-bridge/execution-log?limit=1000&today_only=true', {
                credentials: 'same-origin',
                cache: 'no-store',
                signal: auditLoadController.signal
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || !data || data.ok === false) return;
            if (!state) state = {};
            state.execution_logs = data.execution_logs || { ok: true, rows: [], count: 0 };
            state.liquidity_audit_logs = data.liquidity_audit_logs || { ok: true, rows: [], count: 0 };
            renderAudit();
            renderLiquidityAudit();
            if (els.auditModalStatus) {
                const tradeCount = Number((state.execution_logs || {}).count || ((state.execution_logs || {}).rows || []).length || 0);
                const liqCount = Number((state.liquidity_audit_logs || {}).count || ((state.liquidity_audit_logs || {}).rows || []).length || 0);
                els.auditModalStatus.textContent = `Today audit loaded: ${tradeCount} trade / ${liqCount} liquidity row.`;
            }
        } catch (err) {
            if (!err || err.name !== 'AbortError') throw err;
        } finally {
            window.clearTimeout(timeoutId);
            auditLoadController = null;
            auditLoadInFlight = false;
        }
    }

    function clearAuditState() {
        if (!state) state = {};
        state.execution_logs = { ok: true, rows: [], count: 0, disabled: true };
        state.liquidity_audit_logs = { ok: true, rows: [], count: 0, disabled: true };
        if (els.auditCount) els.auditCount.textContent = '-';
        if (els.liqAuditCount) els.liqAuditCount.textContent = '-';
        if (els.auditBody) els.auditBody.innerHTML = '<tr><td colspan="10" class="text-center text-muted py-3">Loaded only when audit modal is opened.</td></tr>';
        if (els.liqAuditBody) els.liqAuditBody.innerHTML = '<tr><td colspan="10" class="text-center text-muted py-3">Loaded only when audit modal is opened.</td></tr>';
        if (els.auditModalStatus) els.auditModalStatus.textContent = 'Audit modal closed; rows were dropped from page state.';
    }

    async function cleanupOldAuditLogs() {
        if (!window.confirm('Delete indicator audit rows before today? This cannot be undone.')) return;
        if (els.auditCleanOld) {
            els.auditCleanOld.disabled = true;
            els.auditCleanOld.textContent = 'Deleting...';
        }
        try {
            const res = await apiFetch('/indicator-bridge/execution-log/cleanup-old', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || !data || data.ok === false) {
                throw new Error((data && (data.error || data.detail)) || `HTTP ${res.status}`);
            }
            if (els.auditModalStatus) els.auditModalStatus.textContent = `Old audit rows deleted: ${Number(data.deleted || 0)} row(s).`;
            await loadAuditLogs();
        } finally {
            if (els.auditCleanOld) {
                els.auditCleanOld.disabled = false;
                els.auditCleanOld.textContent = 'Delete Before Today';
            }
        }
    }

    async function loadSpreadSnapshot() {
        if (spreadLoadInFlight || !state) return;
        const symbols = Array.from(new Set(allInstances().map(row => String((row || {}).symbol || '').trim().toUpperCase()).filter(Boolean))).slice(0, 80);
        if (!symbols.length) return;
        spreadLoadInFlight = true;
        spreadLoadController = new AbortController();
        const timeoutId = window.setTimeout(() => {
            try { spreadLoadController.abort(); } catch (_) {}
        }, 5000);
        try {
            const res = await apiFetch(`/indicator-bridge/spreads?symbols=${encodeURIComponent(symbols.join(','))}`, {
                credentials: 'same-origin',
                cache: 'no-store',
                signal: spreadLoadController.signal
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || !data || data.ok === false || !Array.isArray(data.rows)) return;
            data.rows.forEach(row => {
                const sym = spreadSymbolKey((row || {}).symbol);
                if (sym) spreadSnapshotBySymbol.set(sym, row);
            });
            ['mt4_monitor', 'mt5_monitor'].forEach(section => {
                const rows = (((state || {})[section] || {}).bot_rows || []);
                if (!Array.isArray(rows)) return;
                rows.forEach(row => {
                    applyCachedSpreadSnapshot(row);
                });
            });
            if (!instanceControlActive()) renderInstances();
        } catch (err) {
            if (!err || err.name !== 'AbortError') throw err;
        } finally {
            window.clearTimeout(timeoutId);
            spreadLoadController = null;
            spreadLoadInFlight = false;
        }
    }

    function collectOpenTradeTickets() {
        const tickets = [];
        const seen = new Set();
        openTrades().forEach(row => {
            const ticket = Number((row || {}).ticket || 0);
            if (!Number.isFinite(ticket) || ticket <= 0) return;
            const key = String(Math.trunc(ticket));
            if (seen.has(key)) return;
            seen.add(key);
            tickets.push(key);
        });
        return tickets;
    }

    function openTradeTicketsKey() {
        return collectOpenTradeTickets().join(',');
    }

    function indicatorPriceWsUrl() {
        const loc = window.location;
        const proto = loc.protocol === 'https:' ? 'wss' : 'ws';
        const host = loc.hostname || '127.0.0.1';
        const directPort = loc.port === '8000' ? loc.port : '8000';
        return `${proto}://${host}:${directPort}/ws/indicator-open-prices`;
    }

    function sendPriceWsSubscription(force) {
        if (!priceWs || priceWs.readyState !== WebSocket.OPEN) return;
        const tickets = collectOpenTradeTickets();
        const key = tickets.join(',');
        if (!force && key === priceWsLastTicketsKey) return;
        priceWsLastTicketsKey = key;
        try {
            priceWs.send(JSON.stringify({
                type: 'subscribe',
                tickets,
                interval_ms: PRICE_WS_INTERVAL_MS
            }));
        } catch (_) {}
    }

    function schedulePriceWsReconnect() {
        priceWsConnected = false;
        if (priceWsReconnectTimer) return;
        priceWsReconnectTimer = window.setTimeout(() => {
            priceWsReconnectTimer = null;
            ensurePriceWebSocket();
        }, 1500);
    }

    function ensurePriceWebSocket() {
        if (!('WebSocket' in window)) return;
        if (priceWs && (priceWs.readyState === WebSocket.OPEN || priceWs.readyState === WebSocket.CONNECTING)) {
            sendPriceWsSubscription(false);
            return;
        }
        try {
            priceWs = new WebSocket(indicatorPriceWsUrl());
        } catch (_) {
            schedulePriceWsReconnect();
            return;
        }
        priceWs.onopen = () => {
            priceWsConnected = true;
            priceWsLastTicketsKey = '';
            sendPriceWsSubscription(true);
        };
        priceWs.onmessage = ev => {
            let msg = null;
            try { msg = JSON.parse(ev.data); } catch (_) { return; }
            const typ = String((msg || {}).type || '').trim();
            if (typ === 'indicator_open_prices') {
                const data = (msg || {}).data || {};
                priceWsLastMessageAtMs = Date.now();
                if (applyPriceSnapshot(data)) {
                    patchLiveTradeTelemetry();
                    updateTradeRailOverlay();
                }
            } else if (typ === 'indicator_open_prices_ready' || typ === 'indicator_open_prices_subscribed') {
                priceWsConnected = true;
            }
        };
        priceWs.onerror = () => {
            priceWsConnected = false;
        };
        priceWs.onclose = () => {
            priceWsConnected = false;
            priceWs = null;
            schedulePriceWsReconnect();
        };
    }

    function ticketKey(rowOrTicket) {
        const raw = (rowOrTicket && typeof rowOrTicket === 'object') ? rowOrTicket.ticket : rowOrTicket;
        const ticket = Number(raw || 0);
        if (!Number.isFinite(ticket) || ticket <= 0) return '';
        return String(Math.trunc(ticket));
    }

    function visualCurrentPrice(row) {
        const key = ticketKey(row);
        const visual = key ? priceVisuals.get(key) : null;
        const visualPrice = Number((visual || {}).current);
        if (Number.isFinite(visualPrice) && visualPrice > 0) return visualPrice;
        const rawPrice = Number((row || {}).current_price);
        return Number.isFinite(rawPrice) ? rawPrice : NaN;
    }

    function syncPriceVisualTarget(ticket, price) {
        const key = ticketKey(ticket);
        const target = Number(price);
        if (!key || !Number.isFinite(target) || target <= 0) return NaN;
        const nowWall = Date.now();
        const nowPerf = performance.now();
        const existing = priceVisuals.get(key) || {};
        const current = advancePriceVisual(existing, nowPerf);
        const lastTargetAtMs = Number(existing.lastTargetAtMs || 0);
        const observedIntervalMs = lastTargetAtMs > 0 ? Math.max(1, nowWall - lastTargetAtMs) : PRICE_SMOOTH_DEFAULT_MS;
        const durationMs = Math.max(
            PRICE_SMOOTH_MIN_MS,
            Math.min(PRICE_SMOOTH_MAX_MS, observedIntervalMs * 0.90)
        );
        const next = {
            current: Number.isFinite(current) && current > 0 ? current : target,
            from: Number.isFinite(current) && current > 0 ? current : target,
            target,
            lastRaw: target,
            startedAtMs: nowPerf,
            durationMs,
            updatedAtMs: nowWall,
            lastTargetAtMs: nowWall,
        };
        priceVisuals.set(key, next);
        ensurePriceSmoothingLoop();
        return next.current;
    }

    function easeDisplayPrice(t) {
        const x = Math.max(0, Math.min(1, Number(t || 0)));
        return x;
    }

    function advancePriceVisual(visual, nowPerf) {
        if (!visual || typeof visual !== 'object') return NaN;
        const from = Number(Object.prototype.hasOwnProperty.call(visual, 'from') ? visual.from : visual.current);
        const target = Number(visual.target);
        if (!Number.isFinite(from) || !Number.isFinite(target) || target <= 0) {
            const fallback = Number(visual.current);
            return Number.isFinite(fallback) ? fallback : NaN;
        }
        const startedAtMs = Number(visual.startedAtMs || 0);
        const durationMs = Math.max(PRICE_SMOOTH_MIN_MS, Number(visual.durationMs || PRICE_SMOOTH_DEFAULT_MS));
        if (!startedAtMs || durationMs <= 0) {
            visual.current = target;
            return target;
        }
        const progress = Math.max(0, Math.min(1, (Number(nowPerf || performance.now()) - startedAtMs) / durationMs));
        const current = from + ((target - from) * easeDisplayPrice(progress));
        visual.current = Number.isFinite(current) ? current : target;
        return visual.current;
    }

    function patchLiveCurrentPrice(row) {
        const ticket = ticketKey(row);
        if (!ticket) return;
        const price = visualCurrentPrice(row);
        document.querySelectorAll(`[data-live-ticket="${cssEsc(ticket)}"][data-live-field="current_price"]`).forEach(el => {
            el.textContent = fmtNum(price, Number(el.getAttribute('data-live-digits') || 5));
        });
    }

    function runPriceSmoothingFrame(ts) {
        if (!state) {
            priceSmoothRaf = null;
            priceSmoothLastMs = 0;
            return;
        }
        const now = Number(ts || performance.now());
        priceSmoothLastMs = now;
        const liveTickets = new Set(collectOpenTradeTickets());
        let active = false;
        priceVisuals.forEach((visual, key) => {
            if (!liveTickets.has(key) && Date.now() - Number(visual.updatedAtMs || 0) > 10000) {
                priceVisuals.delete(key);
                return;
            }
            const target = Number(visual.target);
            if (!Number.isFinite(target) || target <= 0) return;
            const current = advancePriceVisual(visual, now);
            const progress = (now - Number(visual.startedAtMs || 0)) / Math.max(PRICE_SMOOTH_MIN_MS, Number(visual.durationMs || PRICE_SMOOTH_DEFAULT_MS));
            if (progress >= 1) {
                visual.current = target;
                return;
            }
            if (Number.isFinite(current)) active = true;
        });
        if (now - priceSmoothLastDomMs >= PRICE_SMOOTH_DOM_MS) {
            priceSmoothLastDomMs = now;
            openTrades().forEach(row => {
                const key = ticketKey(row);
                const visual = key ? priceVisuals.get(key) : null;
                if (!visual) return;
                row._visual_current_price = visual.current;
                patchLiveCurrentPrice(row);
                patchTradeRailDom(row);
            });
        }
        if (active) {
            priceSmoothRaf = window.requestAnimationFrame(runPriceSmoothingFrame);
        } else {
            priceSmoothRaf = null;
            priceSmoothLastMs = 0;
        }
    }

    function ensurePriceSmoothingLoop() {
        if (priceSmoothRaf) return;
        priceSmoothRaf = window.requestAnimationFrame(runPriceSmoothingFrame);
    }

    function patchRowsByTicket(rows, byTicket) {
        if (!Array.isArray(rows) || !byTicket || typeof byTicket !== 'object') return false;
        let changed = false;
        rows.forEach(row => {
            if (!row || typeof row !== 'object') return;
            const ticket = String(Math.trunc(Number(row.ticket || 0)));
            if (!ticket || ticket === '0') return;
            const snap = byTicket[ticket];
            if (!snap) return;
            [
                'current_price',
                'current_profit',
                'entry_price',
                'stop_loss',
                'take_profit',
                'final_tp',
                'lot_size',
                'max_profit',
                'max_loss',
                'tps',
                'total_tps',
                'highest_tp_reached',
                'highest_tp_price',
                'highest_tp_updated_at',
                'half_be_enabled',
                'half_be_tp_index',
                'half_be_done',
                'half_be_done_at',
                'half_be_secured_profit',
                'half_be_realized_pnl',
                'half_be_close_lot',
                'half_be_sl',
                'current_price_source',
                'current_price_tick_time'
            ].forEach(key => {
                if (Object.prototype.hasOwnProperty.call(snap, key) && snap[key] != null) {
                    row[key] = snap[key];
                    changed = true;
                }
            });
            if (Object.prototype.hasOwnProperty.call(snap, 'current_price') && snap.current_price != null) {
                row._visual_current_price = syncPriceVisualTarget(ticket, snap.current_price);
            }
            row._price_snapshot_at = snap.updated_at || '';
        });
        return changed;
    }

    function applyPriceSnapshot(data) {
        if (!state || !data || data.ok === false || !Array.isArray(data.rows)) return false;
        const byTicket = {};
        data.rows.forEach(row => {
            const ticket = String(Math.trunc(Number((row || {}).ticket || 0)));
            if (ticket && ticket !== '0') byTicket[ticket] = row;
        });
        if (!Object.keys(byTicket).length) return false;
        let changed = false;
        changed = patchRowsByTicket((((state || {}).open_trades || {}).rows || []), byTicket) || changed;
        changed = patchRowsByTicket((((state || {}).mt4_monitor || {}).rows || []), byTicket) || changed;
        changed = patchRowsByTicket((((state || {}).mt5_monitor || {}).rows || []), byTicket) || changed;
        changed = patchRowsByTicket((((state || {}).mt4_monitor || {}).bot_rows || []), byTicket) || changed;
        changed = patchRowsByTicket((((state || {}).mt5_monitor || {}).bot_rows || []), byTicket) || changed;
        if (changed) state._price_snapshot_loaded_at_ms = Date.now();
        return changed;
    }

    async function loadFastPrices() {
        if (!state || priceLoadInFlight) return;
        if (priceWsConnected && Date.now() - Number(priceWsLastMessageAtMs || 0) < 1500) return;
        const tickets = collectOpenTradeTickets();
        if (!tickets.length) return;
        priceLoadInFlight = true;
        priceLoadController = new AbortController();
        const timeoutId = window.setTimeout(() => {
            try { priceLoadController.abort(); } catch (_) {}
        }, 1200);
        try {
            const res = await apiFetch(`/indicator-bridge/open-trade/prices?tickets=${encodeURIComponent(tickets.join(','))}`, {
                credentials: 'same-origin',
                cache: 'no-store',
                signal: priceLoadController.signal
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) return;
            if (applyPriceSnapshot(data)) {
                patchLiveTradeTelemetry();
                updateTradeRailOverlay();
            }
        } catch (err) {
            if (!err || err.name !== 'AbortError') throw err;
        } finally {
            window.clearTimeout(timeoutId);
            priceLoadController = null;
            priceLoadInFlight = false;
        }
    }

    function pauseStateRefresh(ms) {
        stateRefreshPausedUntil = Math.max(stateRefreshPausedUntil, Date.now() + Math.max(0, Number(ms || 0)));
        if (stateLoadController) {
            try { stateLoadController.abort(); } catch (_) {}
        }
    }

    function mergeStatePatch(data) {
        if (!data || typeof data !== 'object') return;
        state = Object.assign({}, state || {}, data);
        state._client_loaded_at_ms = Date.now();
    }

    function refreshStateSoon(delayMs) {
        window.setTimeout(() => {
            loadState().catch(showError);
        }, Math.max(0, Number(delayMs || 0)));
    }

    function applyInstancePatch(row, options) {
        if (!row || !options || typeof options !== 'object') return;
        if (Object.prototype.hasOwnProperty.call(options, 'enabled')) {
            row.automation_enabled = !!options.enabled;
            row.effective_automation_enabled = !!options.enabled;
        }
        if (Object.prototype.hasOwnProperty.call(options, 'lot_size')) row.lot_size = Number(options.lot_size);
        ['mode_advanced_enabled', 'mode_advanced_v2_enabled', 'mode_normal_enabled', 'mode_sync_enabled'].forEach(key => {
            if (Object.prototype.hasOwnProperty.call(options, key)) row[key] = !!options[key];
        });
        if (options.advanced_v2_policies && typeof options.advanced_v2_policies === 'object') {
            row.advanced_v2_policies = Object.assign({}, options.advanced_v2_policies);
        }
        if (Object.prototype.hasOwnProperty.call(options, 'half_be_enabled')) row.half_be_enabled = !!options.half_be_enabled;
        if (Object.prototype.hasOwnProperty.call(options, 'half_be_tp_index')) row.half_be_tp_index = Number(options.half_be_tp_index || 0);
        const widenKeys = ['atomic_sl_widen_enabled', 'atomic_sl_widen_tight_pct', 'atomic_sl_widen_normal_pct', 'atomic_sl_widen_wide_pct'];
        widenKeys.forEach(key => {
            if (Object.prototype.hasOwnProperty.call(options, key)) row[key] = key.endsWith('_enabled') ? !!options[key] : Number(options[key]);
        });
        if (widenKeys.some(key => Object.prototype.hasOwnProperty.call(options, key))) {
            row.atomic_sl_widen = Object.assign({}, row.atomic_sl_widen || {}, {
                enabled: !!row.atomic_sl_widen_enabled,
                tight_pct: Number(row.atomic_sl_widen_tight_pct || 0),
                normal_pct: Number(row.atomic_sl_widen_normal_pct || 0),
                wide_pct: Number(row.atomic_sl_widen_wide_pct || 0)
            });
        }
    }

    function patchInstanceState(row, options) {
        const key = String((row || {}).instance_key || '').trim();
        if (!key || !state || !options || typeof options !== 'object') return;
        ['mt4_monitor', 'mt5_monitor'].forEach(section => {
            const rows = (((state || {})[section] || {}).bot_rows || []);
            if (!Array.isArray(rows)) return;
            rows.forEach(item => {
                if (String((item || {}).instance_key || '').trim() === key) {
                    applyInstancePatch(item, options);
                    item._client_pending_patch_ms = Date.now();
                }
            });
        });
    }

    async function updateInstanceSettings(row, options, uiOptions) {
        const ui = uiOptions && typeof uiOptions === 'object' ? uiOptions : {};
        pauseStateRefresh(2000);
        patchInstanceState(row, options || {});
        applyInstancePatch(row, options || {});
        renderInstances();
        renderEntryExitPanel();
        const payload = Object.assign({
            terminal_family: String(row.terminal_family || '').toLowerCase(),
            indicator: row.indicator || '',
            symbol: row.symbol || '',
            timeframe: row.timeframe || ''
        }, options || {});
        const res = await apiFetch('/indicator-bridge/instance-automation', {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data.ok === false) {
            throw new Error(data.error || data.detail || `HTTP ${res.status}`);
        }
        mergeStatePatch(data);
        patchInstanceState(row, options || {});
        renderInstances();
        renderEntryExitPanel();
        if (!ui.suppressRefresh) {
            refreshStateSoon(150);
        }
    }

    async function saveRiskSettings() {
        pauseStateRefresh(2000);
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
            const res = await apiFetch('/indicator-bridge/risk-settings', {
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
            mergeStatePatch(data);
            showNotice('Risk settings saved. New trades will use the updated daily guard and catastrophe SL.', 'success');
            render();
            refreshStateSoon(1000);
        } finally {
            if (els.riskSave) {
                els.riskSave.disabled = false;
                els.riskSave.textContent = 'Save Risk Settings';
            }
        }
    }

    async function setDailyTargetOverride(enabled) {
        pauseStateRefresh(2000);
        if (els.riskTargetOverride) {
            els.riskTargetOverride.disabled = true;
            els.riskTargetOverride.textContent = enabled ? 'Enabling...' : 'Disabling...';
        }
        try {
            const res = await apiFetch('/indicator-bridge/risk-settings', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ daily_target_guard_bypass_today: !!enabled })
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) {
                throw new Error(data.error || data.detail || `HTTP ${res.status}`);
            }
            mergeStatePatch(data);
            showNotice(enabled
                ? 'Daily target guard bypassed for today. Max daily loss guard is still active.'
                : 'Daily target guard restored for today.',
                enabled ? 'warning' : 'success');
            render();
            refreshStateSoon(1000);
        } finally {
            if (els.riskTargetOverride) {
                els.riskTargetOverride.disabled = false;
            }
        }
    }

    async function updateInstanceAutomation(row, enabled) {
        return updateInstanceSettings(row, { enabled: !!enabled });
    }

    async function updateInstanceAutomationQuiet(row, enabled) {
        return updateInstanceSettings(row, { enabled: !!enabled }, { suppressRefresh: true });
    }

    async function saveDualGateSettings(enabled) {
        pauseStateRefresh(2000);
        const res = await apiFetch('/indicator-bridge/dual-gate-settings', {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ none_close_enabled: !!enabled })
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data.ok === false) {
            throw new Error(data.error || data.detail || `HTTP ${res.status}`);
        }
        mergeStatePatch(data);
        showNotice(`Dual NONE timeout close ${enabled ? 'enabled' : 'disabled'}.`, 'success');
        render();
        refreshStateSoon(250);
    }

    async function saveSpreadGovernorSettings(enabled) {
        pauseStateRefresh(2000);
        const res = await apiFetch('/indicator-bridge/spread-governor-settings', {
            method: 'POST',
            credentials: 'same-origin',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ enabled: !!enabled })
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data.ok === false) {
            throw new Error(data.error || data.detail || `HTTP ${res.status}`);
        }
        mergeStatePatch(data);
        showNotice(`Spread governor ${enabled ? 'enabled' : 'disabled'}.`, enabled ? 'warning' : 'success');
        render();
        refreshStateSoon(250);
    }

    async function saveLiquidityGovernorSettings() {
        pauseStateRefresh(2000);
        const payload = {
            enabled: !!(els.liqGovToggle && els.liqGovToggle.checked),
            context_timeframe: els.liqGovTf ? els.liqGovTf.value : 'M15',
            lookback_bars: parsePositiveInt(els.liqGovLookback ? els.liqGovLookback.value : '', 500),
            freshness_bars: parsePositiveInt(els.liqGovFreshness ? els.liqGovFreshness.value : '', 96),
            min_rejection_ratio: parseUnitFloat(els.liqGovRejection ? els.liqGovRejection.value : '', 0.30),
            allow_continuation: !!(els.liqGovContinuation && els.liqGovContinuation.checked),
            block_on_no_setup: !!(els.liqGovBlockNoSetup && els.liqGovBlockNoSetup.checked)
        };
        if (els.liqGovSave) {
            els.liqGovSave.disabled = true;
            els.liqGovSave.textContent = 'Saving...';
        }
        try {
            const res = await apiFetch('/indicator-bridge/liquidity-governor-settings', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) {
                throw new Error(data.error || data.detail || `HTTP ${res.status}`);
            }
            mergeStatePatch(data);
            showNotice(`Liquidity context governor ${payload.enabled ? 'enabled' : 'disabled'}.`, 'success');
            render();
            refreshStateSoon(250);
        } finally {
            if (els.liqGovSave) {
                els.liqGovSave.disabled = false;
                els.liqGovSave.textContent = 'Save Governor';
            }
        }
    }

    async function runLiquidityOpportunityScan() {
        pauseStateRefresh(5000);
        const raw = els.liqScanSymbols ? els.liqScanSymbols.value : '';
        const symbols = String(raw || '').split(/[\s,;]+/).map(x => x.trim()).filter(Boolean).slice(0, 12);
        if (!symbols.length) {
            throw new Error('Enter at least one symbol for liquidity scan');
        }
        if (els.liqScanRun) {
            els.liqScanRun.disabled = true;
            els.liqScanRun.textContent = 'Scanning...';
        }
        if (els.liqScanStatus) els.liqScanStatus.textContent = `Scanning ${symbols.length} symbol(s)...`;
        try {
            const res = await apiFetch('/indicator-bridge/liquidity-opportunity-scan', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    symbols,
                    context_timeframe: els.liqScanTf ? els.liqScanTf.value : '',
                    max_symbols: 12
                })
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) {
                throw new Error(data.error || data.detail || `HTTP ${res.status}`);
            }
            liquidityScanRows = Array.isArray(data.rows) ? data.rows : [];
            if (els.liqScanStatus) els.liqScanStatus.textContent = `${liquidityScanRows.length} report(s) @ ${fmtTs(data.generated_at)}`;
            renderLiquidityScanResults();
        } finally {
            if (els.liqScanRun) {
                els.liqScanRun.disabled = false;
                els.liqScanRun.textContent = 'Scan Opportunities';
            }
        }
    }

    async function updateLiquidityWatchlist(action) {
        pauseStateRefresh(3000);
        const act = String(action || 'add').toLowerCase();
        const rows = Array.isArray(liquidityScanRows) ? liquidityScanRows : [];
        const symbols = rows.map(row => String((row || {}).symbol || '').trim()).filter(Boolean);
        if (act !== 'clear' && !symbols.length) {
            throw new Error('Run a liquidity scan first, then track the results');
        }
        const contextTf = act === 'clear'
            ? ''
            : String((rows[0] || {}).context_timeframe || (els.liqScanTf ? els.liqScanTf.value : '') || (els.liqGovTf ? els.liqGovTf.value : 'M15') || 'M15').toUpperCase();
        const btn = act === 'clear' ? els.liqWatchClear : els.liqWatchAdd;
        if (btn) {
            btn.disabled = true;
            btn.textContent = act === 'clear' ? 'Clearing...' : 'Tracking...';
        }
        try {
            const res = await apiFetch('/indicator-bridge/liquidity-watchlist', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    action: act,
                    symbols,
                    context_timeframe: contextTf
                })
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) {
                throw new Error(data.error || data.detail || `HTTP ${res.status}`);
            }
            mergeStatePatch(data);
            const count = Array.isArray((data || {}).liquidity_context_watchlist) ? data.liquidity_context_watchlist.length : 0;
            showNotice(act === 'clear' ? 'Liquidity watchlist cleared.' : `Liquidity watchlist updated (${count} tracked).`, 'success');
            render();
            refreshStateSoon(250);
        } finally {
            if (btn) {
                btn.disabled = false;
                btn.textContent = act === 'clear' ? 'Clear Tracked' : 'Track Results';
            }
        }
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

    function spreadSymbolKey(value) {
        return String(value == null ? '' : value).trim().toUpperCase();
    }

    function copySpreadSnapshotFields(target, source) {
        if (!target || !source) return target;
        SPREAD_SNAPSHOT_FIELDS.forEach(key => {
            if (Object.prototype.hasOwnProperty.call(source, key)) target[key] = source[key];
        });
        return target;
    }

    function applyCachedSpreadSnapshot(row) {
        const sym = spreadSymbolKey((row || {}).symbol);
        const cached = sym ? spreadSnapshotBySymbol.get(sym) : null;
        return cached ? copySpreadSnapshotFields(row, cached) : row;
    }

    function applyCachedSpreadSnapshotsToState() {
        ['mt4_monitor', 'mt5_monitor'].forEach(section => {
            const rows = (((state || {})[section] || {}).bot_rows || []);
            if (!Array.isArray(rows)) return;
            rows.forEach(applyCachedSpreadSnapshot);
        });
    }

    function allInstances() {
        const mt4 = (((state || {}).mt4_monitor || {}).bot_rows || []).map(r => applyCachedSpreadSnapshot(Object.assign({}, r, { terminal_family: 'MT4' })));
        const mt5 = (((state || {}).mt5_monitor || {}).bot_rows || []).map(r => applyCachedSpreadSnapshot(Object.assign({}, r, { terminal_family: 'MT5' })));
        return mt4.concat(mt5).filter(isV2Instance);
    }

    function boolish(v) {
        if (v === true || v === 1) return true;
        const s = String(v == null ? '' : v).trim().toLowerCase();
        return ['1', 'true', 'yes', 'on'].includes(s);
    }

    function hasDisplayableBridgeConnection(row) {
        // Operator view must show known/configured V2 instances even when the
        // bridge heartbeat is intentionally sparse or the backend just restarted.
        // State badges still distinguish LIVE/STALE/CONFIGURED; visibility should
        // not depend on a fresh heartbeat.
        return !!row && typeof row === 'object';
    }

    function displayInstances() {
        return allInstances().filter(hasDisplayableBridgeConnection);
    }

    function normalizeIndicatorScopeKey(v) {
        let raw = String(v == null ? '' : v).trim().replace(/\//g, '\\');
        if (raw.includes('\\')) {
            const parts = raw.split('\\').filter(Boolean);
            raw = parts.length ? parts[parts.length - 1] : raw;
        }
        return raw.toLowerCase().replace(/[^a-z0-9]+/g, ' ').replace(/\s+/g, ' ').trim();
    }

    function tradeBlockScopeFromRow(row) {
        const tag = String((row || {}).source_tag || '').trim().toLowerCase();
        const parts = tag.split('|').map(x => String(x || '').trim()).filter(Boolean);
        const family = (parts.length >= 1 && ['mt4', 'mt5'].includes(parts[0]))
            ? parts[0]
            : String((row || {}).terminal_family || 'mt4').trim().toLowerCase();
        const profile = (parts.length >= 2 ? parts[1] : instanceProfile(row)) || 'generic';
        const indicatorRaw = (parts.length >= 3 ? parts[2] : ((row || {}).indicator || (row || {}).source_name || ''));
        const indicator = normalizeIndicatorScopeKey(indicatorRaw);
        const symbol = String((parts.length >= 4 ? parts[3] : ((row || {}).symbol || '')) || '').trim().toUpperCase();
        if (!family || !profile || !indicator || !symbol) return null;
        return {
            key: `${family}|${profile}|${indicator}|${symbol}`,
            family,
            profile,
            indicator,
            indicatorLabel: String((row || {}).indicator || indicatorRaw || indicator).trim() || indicator,
            symbol,
            timeframe: String((row || {}).timeframe || '').trim().toUpperCase()
        };
    }

    function tradeBlockScopeFromKey(keyRaw) {
        const parts = String(keyRaw || '').trim().toLowerCase().split('|').map(x => x.trim()).filter(Boolean);
        if (parts.length !== 4) return null;
        const symbol = String(parts[3] || '').trim().toUpperCase();
        if (!parts[0] || !parts[1] || !parts[2] || !symbol) return null;
        return {
            key: `${parts[0]}|${parts[1]}|${parts[2]}|${symbol}`,
            family: parts[0],
            profile: parts[1],
            indicator: parts[2],
            indicatorLabel: parts[2],
            symbol,
            timeframe: ''
        };
    }

    function uniqueSessionScopes() {
        const map = new Map();
        displayInstances().forEach(row => {
            const scope = tradeBlockScopeFromRow(row);
            if (!scope) return;
            const prev = map.get(scope.key) || {
                key: scope.key,
                family: scope.family,
                profile: scope.profile,
                indicator: scope.indicator,
                indicatorLabel: scope.indicatorLabel,
                symbol: scope.symbol,
                count: 0,
                instances: []
            };
            prev.count += 1;
            prev.instances.push(`${scope.family.toUpperCase()} ${scope.profile} ${scope.indicatorLabel} ${scope.timeframe}`.trim());
            map.set(scope.key, prev);
        });
        Object.keys((state || {}).trade_block_windows || {}).forEach(keyRaw => {
            const scope = tradeBlockScopeFromKey(keyRaw);
            if (!scope || map.has(scope.key)) return;
            map.set(scope.key, Object.assign({}, scope, { count: 0, instances: [] }));
        });
        return Array.from(map.values()).sort((a, b) => {
            const ak = `${a.symbol}|${a.indicator}|${a.profile}`;
            const bk = `${b.symbol}|${b.indicator}|${b.profile}`;
            return ak.localeCompare(bk);
        });
    }

    function instanceProfile(row) {
        return String((row || {}).profile || '').trim().toLowerCase();
    }

    function selectedInstanceProfiles() {
        const out = new Set();
        if (!els.instanceFilterAtomic || els.instanceFilterAtomic.checked) out.add('atomic');
        if (!els.instanceFilterAtomicRegime || els.instanceFilterAtomicRegime.checked) out.add('atomic_regime');
        if (!els.instanceFilterSignatics || els.instanceFilterSignatics.checked) out.add('signatics');
        return out;
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
        return rows.filter(row => !isLiquidityAuditRow(row) && keys.has(auditMatchKey(row)));
    }

    function liquidityAuditRows() {
        const preferred = (((state || {}).liquidity_audit_logs || {}).rows || []);
        if (Array.isArray(preferred) && preferred.length) return preferred;
        const rows = (((state || {}).execution_logs || {}).rows || []);
        if (!Array.isArray(rows)) return [];
        return rows.filter(isLiquidityAuditRow);
    }

    function isLiquidityAuditRow(row) {
        const stage = String((row || {}).stage || '').trim().toLowerCase();
        const sourceTag = String((row || {}).source_tag || '').trim().toLowerCase();
        const indicator = String((row || {}).indicator || (row || {}).source_name || '').trim().toLowerCase();
        return stage.startsWith('liquidity_context')
            || sourceTag.includes('|liquidity_governor|')
            || indicator === 'liquiditygovernor';
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
        const stage = String((row || {}).stage || '').trim().toLowerCase();
        const ticket = Number((row || {}).ticket || 0);
        const lot = Number((row || {}).lot || 0);
        const mode = String((row || {}).execution_mode || '').trim().toLowerCase();
        const hasTradeIdentity = Number.isFinite(ticket) && ticket > 0 && Number.isFinite(lot) && lot > 0;
        if (msg.includes('_orphan') || msg.includes('orphan')) return false;
        if (status === 'skipped' && (stage === 'symbol_session_guard' || msg.includes('symbol_session_guard_blocked'))) {
            return true;
        }
        if (status === 'opened') {
            return hasTradeIdentity && (msg.includes('order_opened') || msg.includes('opened'));
        }
        if (status === 'closed') {
            return hasTradeIdentity && !!mode && mode !== '-' && !msg.includes('skipped');
        }
        return false;
    }

    function auditStrategyKey(row) {
        const indicator = String((row || {}).indicator || (row || {}).source_name || '').trim();
        const profile = String((row || {}).profile || '').trim();
        if (profile && indicator) return `${indicator} / ${profile}`;
        return indicator || profile || '-';
    }

    function auditModeKey(row) {
        return String((row || {}).execution_mode || '-').trim().toLowerCase() || '-';
    }

    function setSelectOptions(select, values, allLabel) {
        if (!select) return;
        const current = String(select.value || '');
        const opts = [''].concat(Array.from(values || []).filter(Boolean).sort((a, b) => String(a).localeCompare(String(b))));
        select.innerHTML = opts.map(value => {
            const label = value ? value : allLabel;
            return `<option value="${esc(value)}">${esc(label)}</option>`;
        }).join('');
        if (opts.includes(current)) select.value = current;
    }

    function renderAuditFilterOptions(rows) {
        const symbols = new Set();
        const strategies = new Set();
        const modes = new Set();
        (rows || []).forEach(row => {
            const symbol = String((row || {}).symbol || '').trim().toUpperCase();
            if (symbol) symbols.add(symbol);
            const strategy = auditStrategyKey(row);
            if (strategy && strategy !== '-') strategies.add(strategy);
            const mode = auditModeKey(row);
            if (mode && mode !== '-') modes.add(mode);
        });
        setSelectOptions(els.auditSymbolFilter, symbols, 'All pairs');
        setSelectOptions(els.auditStrategyFilter, strategies, 'All strategies');
        setSelectOptions(els.auditModeFilter, modes, 'All modes');
    }

    function auditDropdownMatch(row) {
        const symbol = String(els.auditSymbolFilter ? els.auditSymbolFilter.value : '').trim().toUpperCase();
        const strategy = String(els.auditStrategyFilter ? els.auditStrategyFilter.value : '').trim();
        const mode = String(els.auditModeFilter ? els.auditModeFilter.value : '').trim().toLowerCase();
        if (symbol && String((row || {}).symbol || '').trim().toUpperCase() !== symbol) return false;
        if (strategy && auditStrategyKey(row) !== strategy) return false;
        if (mode && auditModeKey(row) !== mode) return false;
        return true;
    }

    function symbolSessionAuditDetail(row) {
        const stage = String((row || {}).stage || '').trim().toLowerCase();
        const msg = String((row || {}).message || '').trim().toLowerCase();
        if (stage !== 'symbol_session_guard' && !msg.includes('symbol_session_guard_blocked')) return '';
        const payload = ((row || {}).stage_payload || {});
        if (!payload || typeof payload !== 'object') return '';
        const bits = [];
        const reason = String(payload.reason || '').trim();
        const matched = String(payload.matched_allowed_range || payload.matched_range || '').trim();
        const allowed = Array.isArray(payload.allowed_ranges)
            ? payload.allowed_ranges.map(x => String(x || '').trim()).filter(Boolean).join(',')
            : '';
        const local = String(payload.local_time || '').trim();
        const scope = String(payload.scope_key || payload.scope || '').trim();
        if (reason) bits.push(`reason=${reason}`);
        if (matched) bits.push(`allowed=${matched}`);
        if (allowed) bits.push(`allowed=${allowed}`);
        if (local) bits.push(`time=${local}`);
        if (scope) bits.push(`scope=${scope}`);
        return bits.length ? `<div class="small text-warning">time guard: ${esc(bits.join(' | '))}</div>` : '';
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

    function liquidityAuditDetail(row) {
        if (!isLiquidityAuditRow(row)) return '';
        const payload = ((row || {}).stage_payload || {});
        const setup = payload && typeof payload === 'object' ? (payload.setup || {}) : {};
        const bits = [];
        const status = String(setup.status || payload.status || '').trim();
        const reason = String(setup.reason || payload.reason || '').trim();
        const dir = String(setup.direction || payload.signal_direction || row.direction || '').trim();
        const price = Number(setup.current_price || payload.current_price);
        const zone = setup.entry_zone || {};
        const invalidation = Number(setup.invalidation);
        const target = Number(setup.target_price);
        const rr = Number(setup.rr_to_target);
        if (status) bits.push(`status=${status}`);
        if (reason) bits.push(`reason=${reason}`);
        if (dir) bits.push(`dir=${dir}`);
        if (Number.isFinite(price)) bits.push(`px=${fmtNum(price, 2)}`);
        if (zone && zone.low != null && zone.high != null) bits.push(`zone=${fmtNum(zone.low, 2)}-${fmtNum(zone.high, 2)}`);
        if (Number.isFinite(invalidation)) bits.push(`inv=${fmtNum(invalidation, 2)}`);
        if (Number.isFinite(target)) bits.push(`target=${fmtNum(target, 2)}`);
        if (Number.isFinite(rr)) bits.push(`rr=${fmtNum(rr, 2)}`);
        return bits.length ? `<div class="small text-warning">liq audit: ${esc(bits.join(' | '))}</div>` : '';
    }

    async function closeOpenTrade(row) {
        const ticket = Number((row || {}).ticket || 0);
        const symbol = String((row || {}).symbol || '').trim();
        if (!Number.isFinite(ticket) || ticket <= 0 || !symbol) {
            throw new Error('Invalid ticket/symbol for close action');
        }
        const res = await apiFetch('/indicator-bridge/open-trade/close', {
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
        const res = await apiFetch('/indicator-bridge/open-trade/sl-be', {
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
        const widen = instanceProfile(row) === 'atomic' && row.atomic_sl_widen_enabled
            ? `SL+ ${pctDisplay(row.atomic_sl_widen_tight_pct, 0.30)}/${pctDisplay(row.atomic_sl_widen_normal_pct, 0.25)}/${pctDisplay(row.atomic_sl_widen_wide_pct, 0.20)}%`
            : '';
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
            row.mode_sync_enabled ? 'SYNC' : '',
            row.half_be_enabled ? halfBeModeLabel(row) : '',
            widen
        ].filter(Boolean).join(' | ') || '-';
    }

    function halfBeOptionsForRow(row) {
        const profile = instanceProfile(row);
        if (profile === 'atomic_regime') {
            return [
                { value: 0, label: 'Half BE: Off' },
                { value: 150, label: 'Half BE: 1.5R' }
            ];
        }
        const maxTp = profile === 'signatics' ? 3 : 5;
        const out = [{ value: 0, label: 'Half BE: Off' }];
        for (let i = 1; i <= maxTp; i += 1) {
            out.push({ value: i, label: `Half BE: TP${i}` });
        }
        return out;
    }

    function normalizeHalfBeValueForRow(row, raw) {
        const val = Number(raw || 0);
        const allowed = halfBeOptionsForRow(row).map(x => Number(x.value));
        if (allowed.includes(val)) return val;
        return 0;
    }

    function halfBeModeLabel(row) {
        const idx = Number(row.half_be_tp_index || 0);
        if (instanceProfile(row) === 'atomic_regime' && idx === 150) return 'HBE@1.5R';
        return idx > 0 ? `HBE@TP${idx}` : '';
    }

    function renderAtomicSlWidenControls(row) {
        if (instanceProfile(row) !== 'atomic') return '';
        const key = esc(row.instance_key || '');
        const enabled = row.atomic_sl_widen_enabled !== false;
        const tight = pctDisplay(row.atomic_sl_widen_tight_pct, 0.30);
        const normal = pctDisplay(row.atomic_sl_widen_normal_pct, 0.25);
        const wide = pctDisplay(row.atomic_sl_widen_wide_pct, 0.20);
        return `<div class="small mt-2 border-top pt-1">
            <label class="me-2"><input type="checkbox" class="form-check-input me-1 v2-sl-widen-enabled" data-instance="${key}" ${enabled ? 'checked' : ''}>Atomic SL widen</label>
            <div class="d-flex flex-wrap gap-1 mt-1">
                <input type="number" class="form-control form-control-sm v2-sl-widen-input" data-bucket="tight" data-instance="${key}" min="0" max="200" step="0.1" value="${esc(tight)}" title="Tight SL widening %">
                <input type="number" class="form-control form-control-sm v2-sl-widen-input" data-bucket="normal" data-instance="${key}" min="0" max="200" step="0.1" value="${esc(normal)}" title="Normal SL widening %">
                <input type="number" class="form-control form-control-sm v2-sl-widen-input" data-bucket="wide" data-instance="${key}" min="0" max="200" step="0.1" value="${esc(wide)}" title="Wide SL widening %">
            </div>
            <div class="text-muted">tight / normal / wide %</div>
        </div>`;
    }

    function renderModeControls(row) {
        const p = row.mode_advanced_v2_enabled ? (row.advanced_v2_policies || {}) : {};
        const key = esc(row.instance_key || '');
        const halfTp = normalizeHalfBeValueForRow(row, row.half_be_enabled ? row.half_be_tp_index : 0);
        const halfOptions = halfBeOptionsForRow(row).map(opt => {
            const n = Number(opt.value);
            return `<option value="${n}" ${halfTp === n ? 'selected' : ''}>${esc(opt.label)}</option>`;
        }).join('');
        return `<div class="v2-mode-box">
            <label class="me-2 small"><input type="checkbox" class="form-check-input me-1 v2-mode-toggle" data-mode="advanced" data-instance="${key}" ${row.mode_advanced_enabled ? 'checked' : ''}>ADV</label>
            <label class="me-2 small"><input type="checkbox" class="form-check-input me-1 v2-mode-toggle" data-mode="normal" data-instance="${key}" ${row.mode_normal_enabled ? 'checked' : ''}>NORM</label>
            <select class="form-select form-select-sm mt-1 v2-half-be-select" data-instance="${key}" title="Selected TP leg triggers half close + SL to BE">
                ${halfOptions}
            </select>
            <div class="small mt-1">
                <span class="text-muted me-1">ADV_V2</span>
                <label class="me-1"><input type="checkbox" class="form-check-input me-1 v2-policy-toggle" data-policy="conservative" data-instance="${key}" ${p.conservative ? 'checked' : ''}>Con</label>
                <label class="me-1"><input type="checkbox" class="form-check-input me-1 v2-policy-toggle" data-policy="balanced" data-instance="${key}" ${p.balanced ? 'checked' : ''}>Bal</label>
                <label class="me-1"><input type="checkbox" class="form-check-input me-1 v2-policy-toggle" data-policy="advanced" data-instance="${key}" ${p.advanced ? 'checked' : ''}>Adv</label>
            </div>
            ${renderAtomicSlWidenControls(row)}
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
            els.openBody.innerHTML = '<tr><td colspan="12" class="text-center text-muted py-3">No open indicator trades.</td></tr>';
            return;
        }
        els.openBody.innerHTML = rows.map(row => {
            const pnl = Number(row.current_profit);
            const pnlCls = Number.isFinite(pnl) ? (pnl >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            const ticket = Number(row.ticket || 0);
            const canClose = Number.isFinite(ticket) && ticket > 0 && String(row.symbol || '').trim();
            const sl = row.stop_loss != null ? row.stop_loss : ((row.stage_payload || {}).post_open_stop_loss || (row.stage_payload || {}).requested_stop_loss);
            const tp = row.take_profit != null ? row.take_profit : (row.final_tp != null ? row.final_tp : ((row.stage_payload || {}).post_open_take_profit || (row.stage_payload || {}).requested_take_profit));
            const maxP = Number(row.max_profit);
            const maxL = Number(row.max_loss);
            const maxCls = Number.isFinite(maxP) ? (maxP >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            const minCls = Number.isFinite(maxL) ? (maxL >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            return `<tr>
                <td class="v2-mono">${esc(row.ticket || '-')}</td>
                <td>${esc(String(row.terminal_family || '').toUpperCase())}</td>
                <td>${esc(row.indicator || row.source_name || '-')}</td>
                <td>${esc(row.symbol || '-')} ${esc(row.timeframe || '')}</td>
                <td>${esc(row.execution_mode || '-')}</td>
                <td class="${String(row.direction).toUpperCase() === 'BUY' ? 'trade-buy' : 'trade-sell'}">${esc(row.direction || '-')}</td>
                <td class="${pnlCls}" data-live-ticket="${esc(row.ticket || '')}" data-live-field="current_profit">${fmtNum(row.current_profit, 2)}</td>
                <td class="v2-mono small">
                    <div>SL ${esc(fmtNum(sl, 5))}</div>
                    <div>TP ${esc(fmtNum(tp, 5))}</div>
                    <div class="small text-info">Px <span data-live-ticket="${esc(row.ticket || '')}" data-live-field="current_price" data-live-digits="5">${esc(fmtNum(visualCurrentPrice(row), 5))}</span></div>
                </td>
                <td class="v2-mono small">
                    <div class="${maxCls}">max <span data-live-ticket="${esc(row.ticket || '')}" data-live-field="max_profit">${esc(fmtNum(row.max_profit, 2))}</span></div>
                    <div class="${minCls}">min <span data-live-ticket="${esc(row.ticket || '')}" data-live-field="max_loss">${esc(fmtNum(row.max_loss, 2))}</span></div>
                </td>
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

    function tpLegText(row) {
        const total = Number((row || {}).total_tps || 0);
        const hit = Math.max(0, Number((row || {}).highest_tp_reached || 0));
        if (Number.isFinite(total) && total > 0) return `TP${Math.min(hit, total)} / TP${total}`;
        return hit > 0 ? `TP${hit}` : 'TP0';
    }

    function tpProgressPct(row) {
        const total = Number((row || {}).total_tps || 0);
        const hit = Math.max(0, Number((row || {}).highest_tp_reached || 0));
        if (!Number.isFinite(total) || total <= 0) return 0;
        return Math.max(0, Math.min(100, (hit / total) * 100));
    }

    function ohlcTpLegText(row) {
        const total = Number((row || {}).total_tps || 0);
        const hit = Math.max(0, Number((row || {}).ohlc_max_tp_reached || 0));
        if (Number.isFinite(total) && total > 0) return `TP${Math.min(hit, total)} / TP${total}`;
        return hit > 0 ? `TP${hit}` : 'TP0';
    }

    function clampPct(v) {
        const n = Number(v);
        if (!Number.isFinite(n)) return 0;
        return Math.max(0, Math.min(100, n));
    }

    function tradeRailLegProgress(row) {
        const side = String((row || {}).direction || '').toUpperCase();
        const entry = Number((row || {}).entry_price);
        const current = visualCurrentPrice(row);
        const tps = Array.isArray((row || {}).tps) ? row.tps : [];
        if (!['BUY', 'SELL'].includes(side) || !Number.isFinite(entry) || !Number.isFinite(current) || !tps.length) {
            return { pct: 0, label: 'leg n/a' };
        }
        const targets = tps
            .map((tp, i) => ({ index: Number(tp.index || i + 1), price: Number(tp.price) }))
            .filter(tp => Number.isFinite(tp.price))
            .sort((a, b) => a.index - b.index);
        if (!targets.length) return { pct: 0, label: 'leg n/a' };
        const favorable = px => side === 'BUY' ? Number(px) >= entry : Number(px) <= entry;
        if (!favorable(current)) return { pct: 0, label: `to TP${targets[0].index}` };
        let prev = entry;
        for (const tp of targets) {
            const reached = side === 'BUY' ? current >= tp.price : current <= tp.price;
            if (!reached) {
                const span = Math.abs(tp.price - prev);
                const done = Math.abs(current - prev);
                const pct = span > 0 ? clampPct((done / span) * 100) : 0;
                return { pct, label: `to TP${tp.index}` };
            }
            prev = tp.price;
        }
        return { pct: 100, label: `TP${targets[targets.length - 1].index} reached` };
    }

    function tradeRailRuntime(row) {
        const side = String((row || {}).direction || '').toUpperCase();
        const entry = Number((row || {}).entry_price);
        const current = visualCurrentPrice(row);
        const sl = Number((row || {}).stop_loss);
        const tps = Array.isArray((row || {}).tps) ? row.tps : [];
        const points = [];
        if (Number.isFinite(sl) && sl > 0) points.push({ key: 'sl', label: 'SL', price: sl, cls: 'v2-rail-sl' });
        if (Number.isFinite(entry) && entry > 0) {
            points.push({ key: 'entry', label: (row.half_be_done ? 'BE' : 'Entry'), price: entry, cls: row.half_be_done ? 'v2-rail-be' : 'v2-rail-entry' });
        }
        tps.forEach((tp, i) => {
            const price = Number((tp || {}).price);
            if (!Number.isFinite(price) || price <= 0) return;
            const label = String((tp || {}).label || `TP${Number((tp || {}).index || i + 1)}`);
            points.push({ key: `tp${i}`, label, price, cls: 'v2-rail-tp' });
        });
        if (Number.isFinite(current) && current > 0) points.push({ key: 'current-ref', label: 'Px', price: current, cls: 'v2-rail-entry', hidden: true });
        if (points.length < 2 || !Number.isFinite(entry) || !Number.isFinite(current)) {
            return { ok: false, points };
        }
        let minPx = Math.min(...points.map(p => p.price));
        let maxPx = Math.max(...points.map(p => p.price));
        const span0 = Math.max(1e-12, maxPx - minPx);
        const pad = span0 * 0.07;
        minPx -= pad;
        maxPx += pad;
        const span = Math.max(1e-12, maxPx - minPx);
        const pos = price => clampPct(((Number(price) - minPx) / span) * 100);
        const entryPct = pos(entry);
        const currentPct = pos(current);
        const fillLeft = Math.min(entryPct, currentPct);
        const fillWidth = Math.abs(currentPct - entryPct);
        const favorableNow = side === 'BUY' ? current >= entry : current <= entry;
        return {
            ok: true,
            side,
            entry,
            current,
            points,
            pos,
            currentPct,
            fillLeft,
            fillWidth,
            favorableNow,
            leg: tradeRailLegProgress(row),
        };
    }

    function patchTradeRailDom(row) {
        const ticket = String((row || {}).ticket || '').trim();
        if (!ticket) return;
        const runtime = tradeRailRuntime(row);
        if (!runtime.ok) return;
        document.querySelectorAll(`.v2-trade-rail[data-ticket="${cssEsc(ticket)}"]`).forEach(rail => {
            const fill = rail.querySelector('.v2-rail-fill');
            if (fill) {
                fill.style.left = `${fmtNum(runtime.fillLeft, 2)}%`;
                fill.style.width = `${fmtNum(runtime.fillWidth, 2)}%`;
                fill.classList.toggle('neg', !runtime.favorableNow);
            }
            const current = rail.querySelector('.v2-rail-current');
            if (current) {
                current.style.left = `${fmtNum(runtime.currentPct, 2)}%`;
                current.setAttribute('title', `Current ${fmtNum(runtime.current, 5)}`);
            }
            const pxChip = rail.querySelector('[data-rail-chip="px"]');
            if (pxChip) pxChip.textContent = `Px ${fmtNum(runtime.current, 5)}`;
            const legChip = rail.querySelector('[data-rail-chip="leg"]');
            if (legChip) legChip.textContent = `${runtime.leg.label} ${fmtNum(runtime.leg.pct, 0)}%`;
        });
        patchTpLegProgressDom(ticket, runtime.leg);
    }

    function patchTpLegProgressDom(ticket, leg) {
        const key = String(ticket || '').trim();
        if (!key || !leg) return;
        const pct = clampPct(Number(leg.pct || 0));
        const label = String(leg.label || 'TP progress');
        document.querySelectorAll(`[data-live-ticket="${cssEsc(key)}"][data-live-field="tp_leg_progress"]`).forEach(el => {
            el.style.width = `${fmtNum(pct, 1)}%`;
            el.setAttribute('aria-valuenow', `${fmtNum(pct, 1)}`);
            el.setAttribute('title', `${label} ${fmtNum(pct, 1)}%`);
        });
        document.querySelectorAll(`[data-live-ticket="${cssEsc(key)}"][data-live-field="tp_leg_label"]`).forEach(el => {
            el.textContent = `${label} ${fmtNum(pct, 0)}%`;
        });
    }

    function patchLiveTradeTelemetry() {
        openTrades().forEach(row => {
            const ticket = String((row || {}).ticket || '').trim();
            if (!ticket) return;
            const runtime = tradeRailRuntime(row);
            const pnl = Number(row.current_profit);
            const maxP = Number(row.max_profit);
            const maxL = Number(row.max_loss);
            document.querySelectorAll(`[data-live-ticket="${cssEsc(ticket)}"][data-live-field="current_profit"]`).forEach(el => {
                el.textContent = fmtNum(row.current_profit, 2);
                el.classList.toggle('text-success', Number.isFinite(pnl) && pnl >= 0);
                el.classList.toggle('text-danger', Number.isFinite(pnl) && pnl < 0);
                el.classList.toggle('text-muted', !Number.isFinite(pnl));
            });
            document.querySelectorAll(`[data-live-ticket="${cssEsc(ticket)}"][data-live-field="max_profit"]`).forEach(el => {
                el.textContent = fmtNum(row.max_profit, 2);
                el.classList.toggle('text-success', Number.isFinite(maxP) && maxP >= 0);
                el.classList.toggle('text-danger', Number.isFinite(maxP) && maxP < 0);
                el.classList.toggle('text-muted', !Number.isFinite(maxP));
            });
            document.querySelectorAll(`[data-live-ticket="${cssEsc(ticket)}"][data-live-field="max_loss"]`).forEach(el => {
                el.textContent = fmtNum(row.max_loss, 2);
                el.classList.toggle('text-success', Number.isFinite(maxL) && maxL >= 0);
                el.classList.toggle('text-danger', Number.isFinite(maxL) && maxL < 0);
                el.classList.toggle('text-muted', !Number.isFinite(maxL));
            });
            patchLiveCurrentPrice(row);
            patchTradeRailDom(row);
            if (runtime.ok) {
                patchTpLegProgressDom(ticket, runtime.leg);
            }
        });
    }

    function renderTradeRail(row, options) {
        const opts = options && typeof options === 'object' ? options : {};
        const runtime = tradeRailRuntime(row);
        if (!runtime.ok) {
            return '<div class="small text-muted">Rail unavailable</div>';
        }
        const secured = Number(row.half_be_secured_profit != null ? row.half_be_secured_profit : row.half_be_realized_pnl);
        const securedText = Number.isFinite(secured) ? `$${fmtNum(secured, 2)}` : '-';
        const halfBeStatus = row.half_be_done
            ? `Half-BE done ${securedText}`
            : (row.half_be_enabled ? `Half-BE armed ${row.half_be_tp_index === 150 ? '1.5R' : `TP${row.half_be_tp_index || ''}`}` : 'Half-BE off');
        const markers = runtime.points
            .filter(p => !p.hidden)
            .map(p => `<div class="v2-rail-point ${esc(p.cls)}" style="left:${fmtNum(runtime.pos(p.price), 2)}%" title="${esc(p.label)} ${esc(fmtNum(p.price, 5))}">
                <span>${esc(p.label)}</span><span class="v2-rail-dot"></span><span class="v2-mono">${esc(fmtNum(p.price, 5))}</span>
            </div>`)
            .join('');
        const ticketAttr = String((row || {}).ticket || '').trim();
        return `<div class="v2-trade-rail ${opts.large ? 'v2-rail-large' : ''}" data-ticket="${esc(ticketAttr)}" tabindex="0">
            <div class="v2-rail-track">
                <div class="v2-rail-base"></div>
                <div class="v2-rail-fill ${runtime.favorableNow ? '' : 'neg'}" style="left:${fmtNum(runtime.fillLeft, 2)}%;width:${fmtNum(runtime.fillWidth, 2)}%"></div>
                ${markers}
                <div class="v2-rail-current" style="left:${fmtNum(runtime.currentPct, 2)}%" title="Current ${esc(fmtNum(runtime.current, 5))}"></div>
            </div>
            <div class="v2-rail-meta">
                <span class="v2-rail-chip" data-rail-chip="px">Px ${esc(fmtNum(runtime.current, 5))}</span>
                <span class="v2-rail-chip" data-rail-chip="leg">${esc(runtime.leg.label)} ${esc(fmtNum(runtime.leg.pct, 0))}%</span>
                <span class="v2-rail-chip ${row.half_be_done ? 'v2-secured-chip' : ''}">${esc(halfBeStatus)}</span>
            </div>
        </div>`;
    }

    function ensureTradeRailOverlay() {
        if (tradeRailOverlay) return tradeRailOverlay;
        const overlay = document.createElement('div');
        overlay.id = 'v2-rail-hover-overlay';
        overlay.className = 'v2-rail-hover-overlay';
        overlay.innerHTML = '<div class="v2-rail-hover-card"></div>';
        document.body.appendChild(overlay);
        const card = overlay.querySelector('.v2-rail-hover-card');
        if (card) {
            card.addEventListener('mouseleave', hideTradeRailOverlay);
        }
        overlay.addEventListener('click', ev => {
            if (ev.target === overlay) hideTradeRailOverlay();
        });
        tradeRailOverlay = overlay;
        return overlay;
    }

    function renderTradeRailOverlayContent(row) {
        if (!row) return '';
        const dir = String((row || {}).direction || '').toUpperCase();
        const pnl = Number((row || {}).current_profit);
        const pnlCls = Number.isFinite(pnl) ? (pnl >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
        return `<div class="v2-rail-hover-title">
            <div>
                <strong>${esc(row.symbol || '-')} ${esc(row.timeframe || '')}</strong>
                <span class="${dir === 'BUY' ? 'trade-buy' : 'trade-sell'} fw-bold ms-2">${esc(dir || '-')}</span>
                <span class="small text-muted ms-2">#${esc(row.ticket || '-')} / ${esc(row.indicator || row.source_name || '-')}</span>
            </div>
            <div class="v2-mono ${pnlCls} fw-bold">PnL <span data-live-ticket="${esc(row.ticket || '')}" data-live-field="current_profit">${esc(fmtNum(row.current_profit, 2))}</span></div>
        </div>
        ${renderTradeRail(row, { large: true })}`;
    }

    function showTradeRailOverlay(row) {
        if (!row) return;
        const overlay = ensureTradeRailOverlay();
        const card = overlay.querySelector('.v2-rail-hover-card');
        tradeRailOverlayTicket = String((row || {}).ticket || '').trim();
        if (card) card.innerHTML = renderTradeRailOverlayContent(row);
        overlay.classList.add('active');
    }

    function updateTradeRailOverlay() {
        if (!tradeRailOverlay || !tradeRailOverlay.classList.contains('active') || !tradeRailOverlayTicket) return;
        const row = openTrades().find(r => String((r || {}).ticket || '') === tradeRailOverlayTicket);
        if (!row) {
            hideTradeRailOverlay();
            return;
        }
        const card = tradeRailOverlay.querySelector('.v2-rail-hover-card');
        if (card) card.innerHTML = renderTradeRailOverlayContent(row);
    }

    function hideTradeRailOverlay() {
        if (!tradeRailOverlay) return;
        tradeRailOverlay.classList.remove('active');
        tradeRailOverlayTicket = '';
    }

    function renderTradeTelemetry() {
        const q = els.telemetryFilter ? els.telemetryFilter.value : '';
        const rows = openTrades()
            .filter(r => textMatch(r, q))
            .sort((a, b) => Number(b.max_profit || 0) - Number(a.max_profit || 0));
        if (!els.telemetryBody) return;
        if (!rows.length) {
            els.telemetryBody.innerHTML = '<tr><td colspan="12" class="text-center text-muted py-3">No open trade telemetry yet.</td></tr>';
            return;
        }
        els.telemetryBody.innerHTML = rows.map(row => {
            const pnl = Number(row.current_profit);
            const maxP = Number(row.max_profit);
            const maxL = Number(row.max_loss);
            const hit = Number(row.highest_tp_reached || 0);
            const total = Number(row.total_tps || 0);
            const ohlcHit = Number(row.ohlc_max_tp_reached || 0);
            const runtime = tradeRailRuntime(row);
            const liveLeg = runtime.ok ? runtime.leg : { pct: tpProgressPct(row), label: 'TP progress' };
            const pct = liveLeg.pct;
            const pnlCls = Number.isFinite(pnl) ? (pnl >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            const maxCls = Number.isFinite(maxP) ? (maxP >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            const minCls = Number.isFinite(maxL) ? (maxL >= 0 ? 'text-success' : 'text-danger') : 'text-muted';
            const tpTone = hit > 0 ? 'bg-success' : 'bg-secondary';
            const slText = row.stop_loss != null ? fmtNum(row.stop_loss, 5) : '-';
            const entryText = row.entry_price != null ? fmtNum(row.entry_price, 5) : '-';
            const rr = Number(row.rr_to_final_tp);
            const rrText = Number.isFinite(rr) ? `${fmtNum(rr, 2)}R` : '-';
            const ohlcTone = ohlcHit > 0 ? 'bg-info text-dark' : 'bg-secondary';
            const ohlcPrice = row.ohlc_max_tp_price != null ? fmtNum(row.ohlc_max_tp_price, 5) : '-';
            const secured = Number(row.half_be_secured_profit != null ? row.half_be_secured_profit : row.half_be_realized_pnl);
            const securedLine = row.half_be_done
                ? `<div class="small text-success">secured ${esc(Number.isFinite(secured) ? `$${fmtNum(secured, 2)}` : 'BE')}</div>`
                : (row.half_be_enabled ? '<div class="small text-warning">half-BE armed</div>' : '');
            const ohlcMeta = [
                row.ohlc_bars_scanned != null ? `${Number(row.ohlc_bars_scanned || 0)} bars` : '',
                row.ohlc_replay_open_bar_skipped ? 'open bar skipped' : ''
            ].filter(Boolean).join(' / ');
            return `<tr>
                <td class="v2-mono">${esc(row.ticket || '-')}</td>
                <td>${esc(row.symbol || '-')} ${esc(row.timeframe || '')}<div class="small text-muted">${esc(String(row.terminal_family || '').toUpperCase())}</div></td>
                <td>${esc(row.indicator || row.source_name || '-')}<div class="small text-muted">${esc(row.execution_mode || '-')}</div></td>
                <td class="${String(row.direction).toUpperCase() === 'BUY' ? 'trade-buy' : 'trade-sell'}">${esc(row.direction || '-')}</td>
                <td class="v2-mono">
                    <div>SL ${esc(slText)}</div>
                    <div class="small text-muted">Entry ${esc(entryText)} / ${esc(rrText)}</div>
                    <div class="small text-info">Px <span data-live-ticket="${esc(row.ticket || '')}" data-live-field="current_price" data-live-digits="5">${esc(fmtNum(visualCurrentPrice(row), 5))}</span></div>
                </td>
                <td class="${pnlCls} fw-semibold" data-live-ticket="${esc(row.ticket || '')}" data-live-field="current_profit">${fmtNum(row.current_profit, 2)}</td>
                <td class="${maxCls} fw-semibold" data-live-ticket="${esc(row.ticket || '')}" data-live-field="max_profit">${fmtNum(row.max_profit, 2)}</td>
                <td class="${minCls} fw-semibold" data-live-ticket="${esc(row.ticket || '')}" data-live-field="max_loss">${fmtNum(row.max_loss, 2)}</td>
                <td>
                    <div class="d-flex align-items-center gap-2">
                        <span class="badge ${tpTone}">${esc(tpLegText(row))}</span>
                        <span class="small text-muted">${Number.isFinite(total) && total > 0 ? `${Math.max(0, Math.min(hit, total))}/${total}` : 'n/a'}</span>
                    </div>
                    <div class="progress mt-1" style="height: 5px;">
                        <div class="progress-bar ${tpTone}" data-live-ticket="${esc(row.ticket || '')}" data-live-field="tp_leg_progress" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${esc(fmtNum(pct, 1))}" title="${esc(liveLeg.label)} ${esc(fmtNum(pct, 1))}%" style="width: ${fmtNum(pct, 1)}%"></div>
                    </div>
                    <div class="small text-muted" data-live-ticket="${esc(row.ticket || '')}" data-live-field="tp_leg_label">${esc(liveLeg.label)} ${esc(fmtNum(pct, 0))}%</div>
                    ${securedLine}
                </td>
                <td>
                    <span class="badge ${ohlcTone}">${esc(ohlcTpLegText(row))}</span>
                    <div class="small text-muted">${esc(ohlcPrice)} ${ohlcMeta ? `/${esc(ohlcMeta)}` : ''}</div>
                    <div class="small text-muted">${row.ohlc_max_tp_time ? esc(fmtTs(row.ohlc_max_tp_time)) : esc(row.ohlc_replay_status || '')}</div>
                </td>
                <td>${renderTradeRail(row)}</td>
                <td>${esc(fmtTs(row.opened_at))}<div class="small text-muted">${row.highest_tp_updated_at ? `TP @ ${esc(fmtTs(row.highest_tp_updated_at))}` : ''}</div></td>
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

    function renderSpreadGovernorSettings() {
        const cfg = (state || {}).spread_governor || {};
        const enabled = boolish(cfg.enabled);
        if (els.spreadGovToggle) els.spreadGovToggle.checked = enabled;
        if (els.spreadGovStatus) {
            els.spreadGovStatus.className = enabled ? 'badge text-bg-danger' : 'badge text-bg-secondary';
            els.spreadGovStatus.textContent = enabled ? 'SPREAD BLOCK ON' : 'OFF';
        }
        if (els.spreadGovContext) {
            const symbolLimits = cfg.symbol_limits && typeof cfg.symbol_limits === 'object' ? cfg.symbol_limits : {};
            const items = Object.keys(symbolLimits).sort().slice(0, 8).map(sym => {
                const limits = symbolLimits[sym] || {};
                return `${sym}: block ${fmtNum(limits.block, 0)}pt`;
            });
            els.spreadGovContext.innerHTML = enabled
                ? `Spread governor is active. ${items.length ? `<span class="v2-mono">${esc(items.join(' / '))}</span>` : 'Current symbol limits are active.'}`
                : 'Spread governor disabled. Dashboard spread labels remain informational only; execution will not be blocked by spread.';
        }
    }

    function renderLiquidityGovernorSettings() {
        const cfg = (state || {}).liquidity_context_governor || {};
        const enabled = boolish(cfg.enabled);
        if (els.liqGovToggle) els.liqGovToggle.checked = enabled;
        if (els.liqGovStatus) {
            els.liqGovStatus.className = enabled ? 'badge text-bg-success' : 'badge text-bg-secondary';
            els.liqGovStatus.textContent = enabled ? 'LIQ GATE ON' : 'OFF';
        }
        if (els.liqGovTf && document.activeElement !== els.liqGovTf) {
            els.liqGovTf.value = String(cfg.context_timeframe || 'M15').toUpperCase();
        }
        if (els.liqGovLookback && document.activeElement !== els.liqGovLookback) {
            els.liqGovLookback.value = String(cfg.lookback_bars || 500);
        }
        if (els.liqGovFreshness && document.activeElement !== els.liqGovFreshness) {
            els.liqGovFreshness.value = String(cfg.freshness_bars || 96);
        }
        if (els.liqGovRejection && document.activeElement !== els.liqGovRejection) {
            els.liqGovRejection.value = Number(cfg.min_rejection_ratio == null ? 0.30 : cfg.min_rejection_ratio).toFixed(2);
        }
        if (els.liqGovContinuation) els.liqGovContinuation.checked = boolish(cfg.allow_continuation);
        if (els.liqGovBlockNoSetup) els.liqGovBlockNoSetup.checked = boolish(cfg.block_on_no_setup);
        if (els.liqGovContext) {
            const rows = Array.isArray((state || {}).liquidity_context_cache) ? state.liquidity_context_cache : [];
            const channels = Array.isArray((state || {}).liquidity_context_channels) ? state.liquidity_context_channels : [];
            const contextBySymbol = {};
            rows.forEach(row => {
                const sym = String((row || {}).symbol || '').toUpperCase();
                if (sym && !contextBySymbol[sym]) contextBySymbol[sym] = row;
            });
            if (!channels.length) {
                els.liqGovContext.innerHTML = '<div class="text-muted">No active indicator channels detected yet.</div>';
            } else {
                els.liqGovContext.innerHTML = channels.slice(0, 8).map(ch => {
                    const row = (ch && typeof ch.liquidity_context === 'object' ? ch.liquidity_context : null)
                        || contextBySymbol[String(ch.symbol || '').toUpperCase()]
                        || {};
                    const setup = (ch && typeof ch.liquidity_setup === 'object' ? ch.liquidity_setup : null)
                        || row.setup
                        || {};
                    const dir = normDirection(setup.direction);
                    const active = boolish(setup.active);
                    const reason = setup.reason || row.error || '';
                    const probe = (ch && typeof ch.liquidity_live_probe === 'object' ? ch.liquidity_live_probe : null)
                        || row.live_probe
                        || {};
                    const dirCls = dir === 'BUY' ? 'text-success' : (dir === 'SELL' ? 'text-danger' : 'text-muted');
                    const zone = setup.entry_zone
                        ? `${fmtNum(setup.entry_zone.low, 2)} - ${fmtNum(setup.entry_zone.high, 2)}`
                        : (setup.entry_zone_low != null && setup.entry_zone_high != null ? `${fmtNum(setup.entry_zone_low, 2)} - ${fmtNum(setup.entry_zone_high, 2)}` : '-');
                    const condition = setup.invalidated
                        ? 'invalidated'
                        : (setup.target_reached
                            ? 'target reached'
                            : (setup.in_entry_zone
                            ? 'inside entry zone'
                            : (setup.continuation_ok ? `continuation ok (${fmtNum(setup.extension_atr, 2)} ATR)` : 'waiting / blocked')));
                    const invalidation = setup.invalidation == null ? '-' : fmtNum(setup.invalidation, 2);
                    const target = setup.target_price == null ? '-' : fmtNum(setup.target_price, 2);
                    const rr = setup.rr_to_target == null ? '-' : fmtNum(setup.rr_to_target, 2);
                    const indicators = Array.isArray(ch.indicators) && ch.indicators.length
                        ? ch.indicators.slice(0, 3).join(', ')
                        : '-';
                    const watchBadge = boolish(ch.watchlist) ? ' <span class="badge text-bg-info">TRACKED</span>' : '';
                    const livePx = probe.price != null ? fmtNum(probe.price, 2) : (row.current_price != null ? fmtNum(row.current_price, 2) : '-');
                    const liveRange = probe.m1_low != null && probe.m1_high != null
                        ? `${fmtNum(probe.m1_low, 2)} - ${fmtNum(probe.m1_high, 2)}`
                        : '-';
                    return `<div class="mb-2 pb-2 border-bottom">
                        <div class="d-flex flex-wrap justify-content-between gap-2">
                            <span><strong>${esc(ch.symbol || '-')} ${esc(ch.timeframe || '')}</strong>${watchBadge} <span class="text-muted">context ${esc(row.context_timeframe || cfg.context_timeframe || '-')}</span></span>
                            <span>${active ? '<span class="badge text-bg-success">SETUP ACTIVE</span>' : (String(setup.status || '').toLowerCase() === 'waiting' ? '<span class="badge text-bg-warning">WAITING</span>' : '<span class="badge text-bg-secondary">NO SETUP</span>')}</span>
                        </div>
                        <div class="row g-2 mt-1">
                            <div class="col-md-2"><span class="text-muted">Bias</span><br><span class="${dirCls} fw-bold">${esc(dir || 'NONE')}</span></div>
                            <div class="col-md-3"><span class="text-muted">Entry zone</span><br><span class="v2-mono">${esc(zone)}</span></div>
                            <div class="col-md-2"><span class="text-muted">Condition</span><br>${esc(condition)}</div>
                            <div class="col-md-2"><span class="text-muted">Invalidation</span><br><span class="v2-mono">${esc(invalidation)}</span></div>
                            <div class="col-md-2"><span class="text-muted">Target / RR</span><br><span class="v2-mono">${esc(target)} / ${esc(rr)}</span></div>
                            <div class="col-md-1"><span class="text-muted">Inst</span><br>${esc(ch.instances || 0)}</div>
                        </div>
                        <div class="small text-muted mt-1">Live px: <span class="v2-mono">${esc(livePx)}</span> / M1 range: <span class="v2-mono">${esc(liveRange)}</span> / Indicators: ${esc(indicators)}${reason ? ` / ${esc(reason)}` : ''}</div>
                    </div>`;
                }).join('');
            }
        }
    }

    function liquidityStatusBadge(status) {
        const s = String(status || '').toLowerCase();
        if (s === 'active') return '<span class="badge text-bg-success">ACTIVE</span>';
        if (s === 'waiting') return '<span class="badge text-bg-warning">WAITING</span>';
        if (s === 'watching') return '<span class="badge text-bg-warning">WATCHING</span>';
        if (s === 'invalidated') return '<span class="badge text-bg-secondary">INVALIDATED</span>';
        if (s === 'error') return '<span class="badge text-bg-danger">ERROR</span>';
        return '<span class="badge text-bg-light text-dark">NO SETUP</span>';
    }

    function liquidityConditionText(row) {
        if (!row || row.ok === false) return row && row.reason ? row.reason : 'scan_error';
        if (boolish(row.invalidated)) return 'invalidated';
        if (boolish(row.target_reached)) return 'target reached';
        if (boolish(row.in_entry_zone)) return 'inside entry zone';
        if (boolish(row.continuation_ok)) return `continuation ok (${fmtNum(row.extension_atr, 2)} ATR)`;
        return row.reason || 'waiting / blocked';
    }

    function renderLiquidityScanResults() {
        if (!els.liqScanResults) return;
        if (!liquidityScanRows.length) {
            els.liqScanResults.innerHTML = 'No scan yet.';
            return;
        }
        els.liqScanResults.innerHTML = `<div class="table-responsive">
            <table class="table table-sm table-hover align-middle mb-0">
                <thead>
                    <tr>
                        <th>Symbol</th><th>Status</th><th>Bias</th><th>Price</th><th>Entry Zone</th><th>Condition</th><th>Invalidation</th><th>Target / RR</th><th>Sweep</th>
                    </tr>
                </thead>
                <tbody>
                    ${liquidityScanRows.map(row => {
                        const dir = normDirection(row.bias);
                        const dirCls = dir === 'BUY' ? 'text-success' : (dir === 'SELL' ? 'text-danger' : 'text-muted');
                        const zoneLow = row.entry_zone && row.entry_zone.low != null ? row.entry_zone.low : row.entry_zone_low;
                        const zoneHigh = row.entry_zone && row.entry_zone.high != null ? row.entry_zone.high : row.entry_zone_high;
                        const zone = zoneLow != null && zoneHigh != null ? `${fmtNum(zoneLow, 2)} - ${fmtNum(zoneHigh, 2)}` : '-';
                        const sweep = row.sweep_quality
                            ? `${esc(row.sweep_quality)} / rej ${fmtNum(row.rejection_ratio, 2)} / age ${esc(row.age_bars)}`
                            : '-';
                        return `<tr>
                            <td><strong>${esc(row.symbol || '-')}</strong><div class="small text-muted">${esc(row.context_timeframe || '')}</div></td>
                            <td>${liquidityStatusBadge(row.status)}</td>
                            <td class="${dirCls} fw-bold">${esc(dir || 'NONE')}</td>
                            <td class="v2-mono">${fmtNum(row.current_price, 2)}</td>
                            <td class="v2-mono">${esc(zone)}</td>
                            <td>${esc(liquidityConditionText(row))}</td>
                            <td class="v2-mono">${row.invalidation == null ? '-' : fmtNum(row.invalidation, 2)}</td>
                            <td class="v2-mono">${row.target_price == null ? '-' : fmtNum(row.target_price, 2)} / ${row.rr_to_target == null ? '-' : fmtNum(row.rr_to_target, 2)}</td>
                            <td>${sweep}<div class="small text-muted">zones ${esc(row.zones_count || 0)} pools ${esc(row.pools_count || 0)} sweeps ${esc(row.sweeps_count || 0)}</div></td>
                        </tr>`;
                    }).join('')}
                </tbody>
            </table>
        </div>`;
    }

    function instanceControlActive() {
        if (!els.instanceBody || !document.activeElement) return false;
        if (!els.instanceBody.contains(document.activeElement)) return false;
        return !!document.activeElement.closest(
            '.v2-half-be-select, .v2-lot-input, .v2-mode-toggle, .v2-policy-toggle, .v2-instance-toggle, .v2-sl-widen-input, .v2-sl-widen-enabled'
        );
    }

    function symbolSessionControlActive() {
        if (!els.symbolSessionBody || !document.activeElement) return false;
        return els.symbolSessionBody.contains(document.activeElement);
    }

    function renderSymbolSessions() {
        if (!els.symbolSessionBody) return;
        const scopes = uniqueSessionScopes();
        const cfgMap = (state || {}).trade_block_windows || {};
        if (!scopes.length) {
            els.symbolSessionBody.innerHTML = '<tr><td colspan="6" class="text-center text-muted py-3">No bridge instances yet.</td></tr>';
            if (els.symbolSessionStatus) {
                els.symbolSessionStatus.className = 'badge text-bg-secondary';
                els.symbolSessionStatus.textContent = 'no scopes';
            }
            return;
        }
        els.symbolSessionBody.innerHTML = scopes.map(row => {
            const cfg = cfgMap[String(row.key || '').toLowerCase()] || {};
            const offset = Number(cfg.timezone_offset_minutes || 0);
            const allow = Array.isArray(cfg.allow) ? cfg.allow.join('\n') : '';
            const block = Array.isArray(cfg.block) ? cfg.block.join('\n') : '';
            const instances = Array.from(new Set(row.instances || [])).slice(0, 8).join(', ');
            return `<tr>
                <td><strong>${esc(row.indicatorLabel || row.indicator)}</strong><div class="small text-muted">${esc(String(row.family || '').toUpperCase())} / ${esc(row.profile || 'generic')}</div></td>
                <td><strong>${esc(row.symbol)}</strong></td>
                <td><input type="number" class="form-control form-control-sm v2-symbol-session-offset" data-scope="${esc(row.key)}" step="1" min="-720" max="840" value="${esc(offset)}"></td>
                <td><textarea class="form-control form-control-sm v2-symbol-session-allow" data-scope="${esc(row.key)}" rows="2" placeholder="13:30-18:00&#10;07:00-10:30">${esc(allow)}</textarea></td>
                <td><textarea class="form-control form-control-sm v2-symbol-session-block" data-scope="${esc(row.key)}" rows="2" placeholder="19:30-20:30">${esc(block)}</textarea></td>
                <td class="small text-muted">${esc(row.count)} instance${row.count === 1 ? '' : 's'}${instances ? `<div>${esc(instances)}</div>` : ''}</td>
            </tr>`;
        }).join('');
        if (els.symbolSessionStatus) {
            els.symbolSessionStatus.className = 'badge text-bg-info';
            els.symbolSessionStatus.textContent = `${scopes.length} scopes`;
        }
    }

    function collectSymbolSessions() {
        const sessions = {};
        if (!els.symbolSessionBody) return sessions;
        Array.from(els.symbolSessionBody.querySelectorAll('tr')).forEach(tr => {
            const offsetEl = tr.querySelector('.v2-symbol-session-offset');
            if (!offsetEl) return;
            const scope = String(offsetEl.getAttribute('data-scope') || '').trim().toLowerCase();
            if (!scope) return;
            const allowEl = tr.querySelector('.v2-symbol-session-allow');
            const blockEl = tr.querySelector('.v2-symbol-session-block');
            const offsetRaw = Number(String(offsetEl.value || '0').trim().replace(',', '.'));
            const offset = Number.isFinite(offsetRaw) ? Math.max(-720, Math.min(840, Math.round(offsetRaw))) : 0;
            const allow = normalizeWindowsText(allowEl ? allowEl.value : '').split('\n').filter(Boolean);
            const block = normalizeWindowsText(blockEl ? blockEl.value : '').split('\n').filter(Boolean);
            if (offset !== 0 || allow.length || block.length) {
                sessions[scope] = { timezone_offset_minutes: offset, allow, block };
            }
        });
        return sessions;
    }

    async function saveSymbolSessions() {
        pauseStateRefresh(2000);
        const sessions = collectSymbolSessions();
        if (els.symbolSessionSave) {
            els.symbolSessionSave.disabled = true;
            els.symbolSessionSave.textContent = 'Saving...';
        }
        try {
            const res = await apiFetch('/indicator-bridge/symbol-sessions', {
                method: 'POST',
                credentials: 'same-origin',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ sessions })
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) {
                throw new Error(data.error || data.detail || `HTTP ${res.status}`);
            }
            mergeStatePatch({ trade_block_windows: data.trade_block_windows || sessions });
            renderSymbolSessions();
            refreshStateSoon(150);
        } finally {
            if (els.symbolSessionSave) {
                els.symbolSessionSave.disabled = false;
                els.symbolSessionSave.textContent = 'Save Sessions';
            }
        }
    }

    async function applyDefaultTradeBlockWindows() {
        const sessions = collectSymbolSessions();
        uniqueSessionScopes().forEach(scope => {
            const key = String((scope || {}).key || '').trim().toLowerCase();
            if (!key) return;
            if (isAtomicTradeWindowScope(scope)) {
                const allow = defaultTradeAllowedWindowsForScope(scope);
                const block = ['19:30-20:30'];
                if (allow.length) {
                    sessions[key] = { timezone_offset_minutes: 0, allow, block };
                } else {
                    sessions[key] = { timezone_offset_minutes: 0, block };
                }
                return;
            }
            if (String((scope || {}).profile || '').trim().toLowerCase() === 'signatics') {
                sessions[key] = { timezone_offset_minutes: 0, block: ['19:30-20:30'] };
            }
        });
        mergeStatePatch({ trade_block_windows: sessions });
        renderSymbolSessions();
        if (els.symbolSessionPreset) {
            els.symbolSessionPreset.disabled = true;
            els.symbolSessionPreset.textContent = 'Saving...';
        }
        try {
            await saveSymbolSessions();
            showNotice('Default allowed/block windows applied. GMT 19:30-20:30 blocks new entries.', 'success');
        } finally {
            if (els.symbolSessionPreset) {
                els.symbolSessionPreset.disabled = false;
                els.symbolSessionPreset.textContent = 'Apply Atomic Allowed Preset';
            }
        }
    }

    function visibleBridgeInstanceRows() {
        const q = els.instanceFilter ? els.instanceFilter.value : '';
        const selectedProfiles = selectedInstanceProfiles();
        return displayInstances()
            .filter(isBridgeInstancesTableRow)
            .filter(r => selectedProfiles.has(instanceProfile(r)))
            .filter(r => textMatch(r, q))
            .sort((a, b) => instanceSortKey(a).localeCompare(instanceSortKey(b)));
    }

    function allBridgeInstanceRows() {
        return displayInstances()
            .filter(isBridgeInstancesTableRow)
            .sort((a, b) => instanceSortKey(a).localeCompare(instanceSortKey(b)));
    }

    function renderSpreadBadge(row) {
        const spread = Number(row.mt4_spread_points);
        const guard = row.spread_guard && typeof row.spread_guard === 'object' ? row.spread_guard : {};
        const status = String(row.spread_status || guard.status || '').trim().toLowerCase();
        const label = String(row.spread_label || guard.label || '').trim().toLowerCase();
        const cls = status === 'good'
            ? 'text-bg-success'
            : (status === 'normal' ? 'text-bg-info' : (status === 'wide' ? 'text-bg-warning' : (status === 'blocked' ? 'text-bg-danger' : 'text-bg-secondary')));
        const text = Number.isFinite(spread) ? `${fmtNum(spread, 0)} pt` : (status === 'no_tick' ? 'no tick' : '-');
        const human = label || (status || 'unknown');
        const source = String(row.spread_source || '').trim();
        const sourceLabel = source === 'mt5_live_fallback'
            ? 'MT5 live'
            : (source === 'mt5_live_refresh' ? 'MT5 live refresh' : (source === 'mt5_live_no_tick' ? 'MT5 no tick' : (source ? source : 'bridge')));
        return `<span class="badge ${cls}">${esc(text)}</span><div class="small text-muted">${esc(human)} / ${esc(sourceLabel)}</div>`;
    }

    async function startAllInstances() {
        const rows = allBridgeInstanceRows().filter(row => !boolish(row.effective_automation_enabled));
        if (!rows.length) {
            showNotice('No stopped bridge instances to start.', 'info');
            return;
        }
        pauseStateRefresh(30000);
        if (els.instanceStartAll) {
            els.instanceStartAll.disabled = true;
            els.instanceStartAll.textContent = `Starting ${rows.length}...`;
        }
        let ok = 0;
        try {
            for (const row of rows) {
                await updateInstanceAutomationQuiet(row, true);
                ok += 1;
            }
            showNotice(`Started ${ok} bridge instance${ok === 1 ? '' : 's'}.`, 'success');
            refreshStateSoon(2500);
        } finally {
            if (els.instanceStartAll) {
                els.instanceStartAll.disabled = false;
                els.instanceStartAll.textContent = 'Start All';
            }
        }
    }

    async function setAllInstancesNormal() {
        const rows = allBridgeInstanceRows();
        if (!rows.length) {
            showNotice('No bridge instances to update.', 'info');
            return;
        }
        const normalPatch = {
            mode_advanced_enabled: false,
            mode_advanced_v2_enabled: false,
            mode_normal_enabled: true,
            mode_sync_enabled: false
        };
        pauseStateRefresh(30000);
        if (els.instanceAllNormal) {
            els.instanceAllNormal.disabled = true;
            els.instanceAllNormal.textContent = `Normalizing ${rows.length}...`;
        }
        let ok = 0;
        try {
            for (const row of rows) {
                await updateInstanceSettings(row, normalPatch, { suppressRefresh: true });
                ok += 1;
            }
            showNotice(`Set ${ok} bridge instance${ok === 1 ? '' : 's'} to normal mode.`, 'success');
            refreshStateSoon(2500);
        } finally {
            if (els.instanceAllNormal) {
                els.instanceAllNormal.disabled = false;
                els.instanceAllNormal.textContent = 'All Normal';
            }
        }
    }

    async function resetBridgeRegistry() {
        if (!window.confirm('Clear transient Bridge Instances registry? This does not close trades or delete automation settings. Reattach/reregister bridges to repopulate.')) {
            return;
        }
        pauseStateRefresh(6000);
        if (els.instanceResetRegistry) {
            els.instanceResetRegistry.disabled = true;
            els.instanceResetRegistry.textContent = 'Resetting...';
        }
        try {
            const res = await apiFetch('/indicator-bridge/reset-registry', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({})
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data.ok === false) {
                throw new Error(data.error || data.detail || `HTTP ${res.status}`);
            }
            showNotice(`Bridge registry cleared (${Number(data.cleared || 0)} row${Number(data.cleared || 0) === 1 ? '' : 's'}).`, 'success');
            refreshStateSoon(200);
        } finally {
            if (els.instanceResetRegistry) {
                els.instanceResetRegistry.disabled = false;
                els.instanceResetRegistry.textContent = 'Reset Registry';
            }
        }
    }

    function renderInstances() {
        const rows = visibleBridgeInstanceRows();
        if (!els.instanceBody) return;
        if (!rows.length) {
            els.instanceBody.innerHTML = '<tr><td colspan="13" class="text-center text-muted py-3">No bridge instances yet.</td></tr>';
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
                <td>${renderSpreadBadge(row)}</td>
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

    function renderLiquidityAudit() {
        if (((state || {}).liquidity_audit_logs || {}).disabled) {
            if (els.liqAuditCount) els.liqAuditCount.textContent = '-';
            if (els.liqAuditBody) els.liqAuditBody.innerHTML = '<tr><td colspan="10" class="text-center text-muted py-3">Loaded only when audit modal is opened.</td></tr>';
            return;
        }
        const q = els.liqAuditFilter ? els.liqAuditFilter.value : '';
        const rows = liquidityAuditRows().filter(r => textMatch(r, q)).slice(0, 1000);
        if (els.liqAuditCount) els.liqAuditCount.textContent = String(rows.length);
        if (!els.liqAuditBody) return;
        if (!rows.length) {
            els.liqAuditBody.innerHTML = '<tr><td colspan="10" class="text-center text-muted py-3">No liquidity governor audit rows yet.</td></tr>';
            return;
        }
        els.liqAuditBody.innerHTML = rows.map(row => {
            const payload = ((row || {}).stage_payload || {});
            const setup = payload && typeof payload === 'object' ? (payload.setup || {}) : {};
            const event = String(row.status || row.trigger || row.message || row.stage || '-').trim();
            const stage = String(row.stage || '').trim();
            const status = String(setup.status || payload.status || row.stage_status || '-').trim();
            const reason = String(setup.reason || payload.reason || row.message || row.close_reason || '-').trim();
            const direction = String(setup.direction || payload.signal_direction || row.direction || '-').trim();
            const price = Number(setup.current_price || payload.current_price);
            const zone = setup.entry_zone || {};
            const low = Number(zone.low);
            const high = Number(zone.high);
            const invalidation = Number(setup.invalidation);
            const target = Number(setup.target_price);
            const rr = Number(setup.rr_to_target);
            const setupId = String(payload.setup_id || setup.setup_id || '').trim();
            const decision = String(payload.decision || payload.guard_decision || '').trim();
            const detail = liquidityAuditDetail(row);
            const statusCls = status.toUpperCase() === 'ACTIVE'
                ? 'text-success'
                : (status.toUpperCase() === 'WAITING' ? 'text-warning' : 'text-muted');
            return `<tr>
                <td>${esc(event || '-')}<div class="small text-muted">${esc(fmtTs(row.event_ts || row.opened_at))}</div></td>
                <td>${esc(row.symbol || '-')} ${esc(row.timeframe || '')}<div class="small text-muted">${esc(stage || '-')}</div></td>
                <td class="${statusCls} fw-semibold">${esc(status || '-')}</td>
                <td>${esc(direction || '-')}</td>
                <td>${Number.isFinite(price) ? fmtNum(price, 2) : '-'}</td>
                <td>${Number.isFinite(low) && Number.isFinite(high) ? `${fmtNum(low, 2)} - ${fmtNum(high, 2)}` : '-'}</td>
                <td>${Number.isFinite(invalidation) ? fmtNum(invalidation, 2) : '-'}</td>
                <td>${Number.isFinite(target) ? fmtNum(target, 2) : '-'}${Number.isFinite(rr) ? `<div class="small text-muted">RR ${fmtNum(rr, 2)}</div>` : ''}</td>
                <td>${esc(decision || reason || '-')}${detail}</td>
                <td class="v2-mono small">${esc(setupId || row.source_tag || '-')}</td>
            </tr>`;
        }).join('');
    }

    function renderAudit() {
        if (((state || {}).execution_logs || {}).disabled) {
            if (els.auditCount) els.auditCount.textContent = '-';
            if (els.auditBody) els.auditBody.innerHTML = '<tr><td colspan="10" class="text-center text-muted py-3">Loaded only when audit modal is opened.</td></tr>';
            return;
        }
        const q = els.auditFilter ? els.auditFilter.value : '';
        const baseRows = auditRows()
            .filter(row => !isZeroPnlBreakEvenOperation(row))
            .filter(isReadableTradeAuditRow);
        renderAuditFilterOptions(baseRows);
        const meaningfulRaw = baseRows
            .filter(auditDropdownMatch)
            .filter(r => textMatch(r, q));
        const meaningful = groupAuditRows(meaningfulRaw).slice(0, 1000);
        if (els.auditCount) els.auditCount.textContent = String(meaningfulRaw.length);
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
            const sessionDetail = symbolSessionAuditDetail(row);
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
                <td>${esc(row.message || row.close_reason || '-')}${sessionDetail}${entryExitDetail}${grouped}${shadow}</td>
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
        if (els.auditCount) {
            const logs = (state || {}).execution_logs || {};
            els.auditCount.textContent = logs.disabled ? '-' : String(auditRows().filter(row => !isZeroPnlBreakEvenOperation(row)).filter(isReadableTradeAuditRow).length);
        }
        if (els.liqAuditCount) {
            const liqLogs = (state || {}).liquidity_audit_logs || {};
            els.liqAuditCount.textContent = liqLogs.disabled ? '-' : String(liquidityAuditRows().length);
        }
        renderRiskSettings();
        renderDualGateSettings();
        renderSpreadGovernorSettings();
        renderLiquidityGovernorSettings();
        renderLiquidityScanResults();
        renderDualGatePanel();
        renderEntryExitPanel();
        renderOpenTrades();
        renderTradeTelemetry();
        if (!symbolSessionControlActive()) {
            renderSymbolSessions();
        }
        renderInstances();
        renderLiquidityAudit();
        renderAudit();
        ensurePriceWebSocket();
        sendPriceWsSubscription(false);
    }

    function schedule() {
        if (timer) clearInterval(timer);
        timer = setInterval(() => loadState().catch(showError), 12000);
        if (priceTimer) clearInterval(priceTimer);
        ensurePriceWebSocket();
        priceTimer = setInterval(() => {
            ensurePriceWebSocket();
            sendPriceWsSubscription(false);
            loadFastPrices().catch(() => {});
        }, 500);
        if (auditTimer) clearInterval(auditTimer);
        auditTimer = null;
        if (spreadTimer) clearInterval(spreadTimer);
        spreadTimer = setInterval(() => loadSpreadSnapshot().catch(() => {}), 3000);
        if (uiTimer) clearInterval(uiTimer);
        uiTimer = setInterval(() => {
            if (!state) return;
            renderDualGatePanel();
            if (!els.entryExitBody || !els.entryExitBody.contains(document.activeElement)) {
                renderEntryExitPanel();
            }
            if (!instanceControlActive()) {
                renderInstances();
            }
            if (!symbolSessionControlActive()) {
                renderSymbolSessions();
            }
        }, 3000);
    }

    [els.openFilter, els.telemetryFilter, els.instanceFilter, els.instanceFilterAtomic, els.instanceFilterAtomicRegime, els.instanceFilterSignatics, els.auditFilter, els.auditSymbolFilter, els.auditStrategyFilter, els.auditModeFilter, els.liqAuditFilter].forEach(el => {
        if (el) el.addEventListener('input', render);
        if (el) el.addEventListener('change', render);
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
    if (els.symbolSessionSave) {
        els.symbolSessionSave.addEventListener('click', () => saveSymbolSessions().catch(showError));
    }
    if (els.symbolSessionPreset) {
        els.symbolSessionPreset.addEventListener('click', () => applyDefaultTradeBlockWindows().catch(showError));
    }
    if (els.instanceStartAll) {
        els.instanceStartAll.addEventListener('click', () => startAllInstances().catch(showError));
    }
    if (els.instanceAllNormal) {
        els.instanceAllNormal.addEventListener('click', () => setAllInstancesNormal().catch(showError));
    }
    if (els.instanceResetRegistry) {
        els.instanceResetRegistry.addEventListener('click', () => resetBridgeRegistry().catch(showError));
    }
    if (els.auditOpen) {
        els.auditOpen.addEventListener('click', () => {
            const modalEl = els.auditModal;
            if (modalEl && window.bootstrap && window.bootstrap.Modal) {
                window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
            }
            loadAuditLogs().catch(showError);
        });
    }
    if (els.auditReload) {
        els.auditReload.addEventListener('click', () => loadAuditLogs().catch(showError));
    }
    if (els.auditCleanOld) {
        els.auditCleanOld.addEventListener('click', () => cleanupOldAuditLogs().catch(showError));
    }
    if (els.auditModal) {
        els.auditModal.addEventListener('hidden.bs.modal', clearAuditState);
    }
    if (els.symbolSessionBody) {
        els.symbolSessionBody.addEventListener('input', () => {
            pauseStateRefresh(3000);
            if (els.symbolSessionStatus) {
                els.symbolSessionStatus.className = 'badge text-bg-warning';
                els.symbolSessionStatus.textContent = 'unsaved';
            }
        });
        els.symbolSessionBody.addEventListener('keydown', ev => {
            const input = ev.target.closest('.v2-symbol-session-offset');
            if (input && ev.key === 'Enter') saveSymbolSessions().catch(showError);
            if ((ev.ctrlKey || ev.metaKey) && ev.key === 'Enter') saveSymbolSessions().catch(showError);
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
    if (els.spreadGovToggle) {
        els.spreadGovToggle.addEventListener('change', ev => {
            const input = ev.target;
            input.disabled = true;
            saveSpreadGovernorSettings(!!input.checked).catch(err => {
                showError(err);
                input.checked = !input.checked;
                renderSpreadGovernorSettings();
            }).finally(() => {
                input.disabled = false;
            });
        });
    }
    if (els.liqGovSave) {
        els.liqGovSave.addEventListener('click', () => saveLiquidityGovernorSettings().catch(showError));
    }
    if (els.liqGovToggle) {
        els.liqGovToggle.addEventListener('change', () => saveLiquidityGovernorSettings().catch(showError));
    }
    if (els.liqScanRun) {
        els.liqScanRun.addEventListener('click', () => runLiquidityOpportunityScan().catch(showError));
    }
    if (els.liqWatchAdd) {
        els.liqWatchAdd.addEventListener('click', () => updateLiquidityWatchlist('add').catch(showError));
    }
    if (els.liqWatchClear) {
        els.liqWatchClear.addEventListener('click', () => updateLiquidityWatchlist('clear').catch(showError));
    }
    if (els.liqScanSymbols) {
        els.liqScanSymbols.addEventListener('keydown', ev => {
            if (ev.key === 'Enter') runLiquidityOpportunityScan().catch(showError);
        });
    }
    if (els.instanceBody) {
        els.instanceBody.addEventListener('pointerdown', ev => {
            if (ev.target.closest('.v2-half-be-select, .v2-lot-input, .v2-mode-toggle, .v2-policy-toggle, .v2-sl-widen-input, .v2-sl-widen-enabled')) {
                pauseStateRefresh(5000);
            }
        });
        els.instanceBody.addEventListener('focusin', ev => {
            if (ev.target.closest('.v2-half-be-select, .v2-lot-input, .v2-mode-toggle, .v2-policy-toggle, .v2-sl-widen-input, .v2-sl-widen-enabled')) {
                pauseStateRefresh(5000);
            }
        });
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
            const halfBeSelect = ev.target.closest('.v2-half-be-select');
            const slWidenInput = ev.target.closest('.v2-sl-widen-input');
            const slWidenEnabled = ev.target.closest('.v2-sl-widen-enabled');
            if (!input && !modeToggle && !policyToggle && !halfBeSelect && !slWidenInput && !slWidenEnabled) return;
            if (slWidenInput || slWidenEnabled) {
                const el = slWidenInput || slWidenEnabled;
                const key = el.getAttribute('data-instance') || '';
                const row = allInstances().find(r => String(r.instance_key || '') === key);
                if (!row) return;
                const scope = el.closest('.v2-mode-box') || els.instanceBody;
                const enabledEl = scope.querySelector(`.v2-sl-widen-enabled[data-instance="${CSS.escape(key)}"]`);
                const tightEl = scope.querySelector(`.v2-sl-widen-input[data-instance="${CSS.escape(key)}"][data-bucket="tight"]`);
                const normalEl = scope.querySelector(`.v2-sl-widen-input[data-instance="${CSS.escape(key)}"][data-bucket="normal"]`);
                const wideEl = scope.querySelector(`.v2-sl-widen-input[data-instance="${CSS.escape(key)}"][data-bucket="wide"]`);
                const opts = {
                    atomic_sl_widen_enabled: enabledEl ? !!enabledEl.checked : true,
                    atomic_sl_widen_tight_pct: parsePercentInput(tightEl ? tightEl.value : '', 0.30),
                    atomic_sl_widen_normal_pct: parsePercentInput(normalEl ? normalEl.value : '', 0.25),
                    atomic_sl_widen_wide_pct: parsePercentInput(wideEl ? wideEl.value : '', 0.20)
                };
                [enabledEl, tightEl, normalEl, wideEl].filter(Boolean).forEach(x => { x.disabled = true; });
                updateInstanceSettings(row, opts).catch(err => {
                    showError(err);
                    renderInstances();
                });
                return;
            }
            if (halfBeSelect) {
                const key = halfBeSelect.getAttribute('data-instance') || '';
                const row = allInstances().find(r => String(r.instance_key || '') === key);
                if (!row) return;
                const tpIndex = normalizeHalfBeValueForRow(row, halfBeSelect.value);
                halfBeSelect.disabled = true;
                patchInstanceState(row, {
                    half_be_enabled: tpIndex > 0,
                    half_be_tp_index: tpIndex
                });
                renderInstances();
                updateInstanceSettings(row, {
                    half_be_enabled: tpIndex > 0,
                    half_be_tp_index: tpIndex
                }).then(() => {
                    const fresh = document.querySelector(`.v2-half-be-select[data-instance="${CSS.escape(key)}"]`);
                    if (fresh) fresh.disabled = false;
                }).catch(err => {
                    showError(err);
                    renderInstances();
                });
                return;
            }
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
            const input = ev.target.closest('.v2-lot-input, .v2-sl-widen-input');
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
    if (els.telemetryBody) {
        els.telemetryBody.addEventListener('mouseover', ev => {
            const rail = ev.target.closest('.v2-trade-rail');
            if (!rail || !els.telemetryBody.contains(rail)) return;
            const ticket = String(rail.getAttribute('data-ticket') || '').trim();
            if (!ticket) return;
            if (tradeRailOverlay && tradeRailOverlay.classList.contains('active') && tradeRailOverlayTicket === ticket) return;
            const row = openTrades().find(r => String((r || {}).ticket || '') === ticket);
            if (row) showTradeRailOverlay(row);
        });
        els.telemetryBody.addEventListener('focusin', ev => {
            const rail = ev.target.closest('.v2-trade-rail');
            if (!rail || !els.telemetryBody.contains(rail)) return;
            const ticket = String(rail.getAttribute('data-ticket') || '').trim();
            const row = openTrades().find(r => String((r || {}).ticket || '') === ticket);
            if (row) showTradeRailOverlay(row);
        });
    }
    document.addEventListener('keydown', ev => {
        if (ev.key === 'Escape') hideTradeRailOverlay();
    });
    if (els.refresh) els.refresh.addEventListener('click', () => {
        loadState().catch(showError);
        loadSpreadSnapshot().catch(() => {});
    });
    loadState().catch(showError);
    window.setTimeout(() => loadSpreadSnapshot().catch(() => {}), 1500);
    clearAuditState();
    schedule();
})();

