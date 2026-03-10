/**
 * Trading Simulation Dashboard - JavaScript
 * TradingView Lightweight Charts integration + Step Tracker + Playback
 */

// ── State ──────────────────────────────────────────────────
let sessionId = null;
let chart = null;
let candleSeries = null;
let volumeSeries = null;
let subChart = null;
let indicatorSeries = {};  // name -> series object
let indicatorLastTime = {}; // name -> last rendered timestamp
let overlayLines = [];     // price line references
let squeezeMarkers = [];    // last rendered squeeze markers
let squeezeIndexOffset = 0; // number of squeeze values consumed
let chartClickHandler = null;
let zoneRenderer = null;
let toolStates = {
    fvg: { enabled: false, strictness: 3, lookback_days: 2 },
    mean_rev: { enabled: false, strictness: 3, sma_period: 30, deviation: 2.0 },
    draw_fvg: { enabled: false, picks: [] },
};
let renderedToolId = null;
let indicatorVisibility = {
    trend: true,
    osc: true,
    volatility: true,
    overlays: true,
};
const SIM_PANELS = {
    steps: { panelId: 'step-tracker-panel', modalId: 'stepsPanelModal', bodyId: 'steps-panel-modal-body' },
    trade: { panelId: 'trade-exec-panel', modalId: 'tradeExecModal', bodyId: 'trade-exec-modal-body' },
    tools: { panelId: 'analysis-tools-panel', modalId: 'analysisToolsModal', bodyId: 'analysis-tools-modal-body' },
};
const panelHomeMarkers = {};
let fullscreenSimulation = false;

let isPlaying = false;
let playInterval = null;
let playSocket = null;
let liveFeedSocket = null;
let liveFeedActive = false;
let liveFeedRequested = false;
let liveFeedManualStop = false;
let liveFeedReconnectAttempts = 0;
let wsWatchdogTimer = null;
let playSpeed = 1;  // bars per tick
let tickMs = 500;   // ms between ticks
let transportMode = 'IDLE';
let adaptiveSpeedEnabled = true;
let adaptiveLastTuneMs = 0;
let wsReconnectRequested = false;
let isAdvancing = false;
let pendingAdvance = 0;
let lastAdvanceMs = 0;
let tickCounter = 0;
let tickWindowStartMs = 0;
let barsPerSecond = 0;
let lastPayloadAtMs = 0;
let droppedTickCount = 0;
let reconnectCount = 0;
let latencySamples = [];

let allBars = [];   // accumulated bars for chart
let currentBar = 0;
let totalBars = 0;
let initialBalance = 10000;

const STRATEGY_ID = document.getElementById('sim-strategy-id')?.value || '';
const API_BASE = '';  // Same origin (Flask proxy)
const WS_BACKEND_PORT = 8000;
const SESSION_STORAGE_KEY = `sim:lastSession:${STRATEGY_ID}`;
const SPEED_STEPS = [1, 2, 5, 10];
const ADAPTIVE_TUNE_INTERVAL_MS = 4000;
const WS_STALL_FACTOR = 8;
const LATENCY_SAMPLE_CAP = 200;

function getTickMsForSpeed(speed) {
    if (speed >= 10) return 80;
    if (speed >= 5) return 120;
    if (speed >= 2) return 220;
    return 350;
}

function setTransportMode(mode) {
    transportMode = mode || 'IDLE';
    const el = document.getElementById('stat-transport');
    if (el) el.textContent = adaptiveSpeedEnabled ? `${transportMode}+AUTO` : transportMode;
}

function updatePerfStats() {
    const el = document.getElementById('stat-barsps');
    if (!el) return;
    el.textContent = `${barsPerSecond.toFixed(1)} bars/s`;
}

function percentile(values, p) {
    if (!Array.isArray(values) || values.length === 0) return 0;
    const sorted = values.slice().sort((a, b) => a - b);
    const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
    return sorted[idx] || 0;
}

function updateReliabilityStats() {
    const p95El = document.getElementById('stat-p95-latency');
    const dropEl = document.getElementById('stat-dropped-ticks');
    const recEl = document.getElementById('stat-reconnects');
    if (p95El) p95El.textContent = `${Math.round(percentile(latencySamples, 95))} ms`;
    if (dropEl) dropEl.textContent = `${droppedTickCount}`;
    if (recEl) recEl.textContent = `${reconnectCount}`;
}

function recordLatencySample(ms) {
    if (!Number.isFinite(ms) || ms < 0) return;
    latencySamples.push(ms);
    if (latencySamples.length > LATENCY_SAMPLE_CAP) {
        latencySamples = latencySamples.slice(latencySamples.length - LATENCY_SAMPLE_CAP);
    }
    updateReliabilityStats();
}

function persistSessionId(id) {
    try {
        if (!id) return;
        localStorage.setItem(SESSION_STORAGE_KEY, String(id));
    } catch (_) { /* ignore */ }
}

function loadPersistedSessionId() {
    try {
        return localStorage.getItem(SESSION_STORAGE_KEY);
    } catch (_) {
        return null;
    }
}

function clearPersistedSessionId() {
    try {
        localStorage.removeItem(SESSION_STORAGE_KEY);
    } catch (_) { /* ignore */ }
}

function updateSpeedButtons() {
    document.querySelectorAll('.speed-btn[data-speed]').forEach(btn => {
        const s = parseInt(btn.dataset.speed, 10) || 1;
        btn.classList.toggle('active', s === playSpeed);
    });
    const autoBtn = document.getElementById('btn-auto-speed');
    if (autoBtn) autoBtn.classList.toggle('active', adaptiveSpeedEnabled);
}

function setPlaybackSpeed(nextSpeed) {
    const parsed = parseInt(nextSpeed, 10) || 1;
    if (!SPEED_STEPS.includes(parsed)) return false;
    if (playSpeed === parsed) return false;
    playSpeed = parsed;
    tickMs = getTickMsForSpeed(playSpeed);
    updateSpeedButtons();
    return true;
}

function getSelectedLiveSource() {
    return String(document.getElementById('live-source')?.value || 'mt5').toLowerCase();
}

function normalizeTimeframeLabel(tf, fallback = 'M15') {
    const s = String(tf || fallback).trim().toUpperCase();
    const allowed = new Set(['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1']);
    return allowed.has(s) ? s : String(fallback || 'M15').toUpperCase();
}

function timeframeToMinutes(tf) {
    const t = normalizeTimeframeLabel(tf, 'M15');
    if (t === 'M1') return 1;
    if (t === 'M5') return 5;
    if (t === 'M15') return 15;
    if (t === 'M30') return 30;
    if (t === 'H1') return 60;
    if (t === 'H4') return 240;
    if (t === 'D1') return 1440;
    return 15;
}

function getLiveHistoryDays() {
    const raw = Number(document.getElementById('live-history-days')?.value || 2);
    if (!Number.isFinite(raw)) return 2;
    return Math.max(0.1, Math.min(60, raw));
}

function historyBarsFor(timeframe, days) {
    const tfMins = Math.max(1, timeframeToMinutes(timeframe));
    const d = Math.max(0.1, Math.min(60, Number(days || 2)));
    const base = Math.ceil((d * 1440.0) / tfMins);
    const withBuffer = base + 3;
    return Math.max(2, Math.min(10000, withBuffer));
}

function getDatabentoApiKey() {
    return String(document.getElementById('live-databento-key')?.value || '').trim();
}

function getLiveSourceLabel(source) {
    return source === 'databento' ? 'Databento' : 'MT5';
}

function setLiveFeedButtonState(active, source) {
    const btn = document.getElementById('btn-live-feed');
    if (!btn) return;
    const label = getLiveSourceLabel(source || getSelectedLiveSource());
    if (active) {
        btn.classList.remove('btn-outline-success');
        btn.classList.add('btn-outline-danger');
        btn.innerHTML = `<i class="bi bi-stop-circle me-1"></i>Stop ${label} Live`;
    } else {
        btn.classList.remove('btn-outline-danger');
        btn.classList.add('btn-outline-success');
        btn.innerHTML = `<i class="bi bi-broadcast me-1"></i>Start ${label} Live`;
    }
}

function refreshChartViewport() {
    if (!chart) return;
    const el = document.getElementById('chart-main');
    if (!el) return;
    const width = Math.max(320, Math.round(el.clientWidth || 0));
    const height = Math.max(260, Math.round(el.clientHeight || 0));
    chart.applyOptions({ width, height });
}

function ensurePanelHomeMarkers() {
    Object.values(SIM_PANELS).forEach((cfg) => {
        if (panelHomeMarkers[cfg.panelId]) return;
        const node = document.getElementById(cfg.panelId);
        if (!node || !node.parentNode) return;
        const marker = document.createComment(`sim-panel-home:${cfg.panelId}`);
        node.parentNode.insertBefore(marker, node);
        panelHomeMarkers[cfg.panelId] = marker;
    });
}

function mountPanelToModal(kind) {
    const cfg = SIM_PANELS[kind];
    if (!cfg) return;
    const panel = document.getElementById(cfg.panelId);
    const body = document.getElementById(cfg.bodyId);
    if (!panel || !body) return;
    if (panel.parentNode !== body) body.appendChild(panel);
}

function restorePanelHome(kind) {
    const cfg = SIM_PANELS[kind];
    if (!cfg) return;
    const panel = document.getElementById(cfg.panelId);
    const marker = panelHomeMarkers[cfg.panelId];
    if (!panel || !marker || !marker.parentNode) return;
    marker.parentNode.insertBefore(panel, marker.nextSibling);
}

function restoreAllPanelsHome() {
    Object.keys(SIM_PANELS).forEach((k) => restorePanelHome(k));
}

function closeAllPanelModals() {
    Object.values(SIM_PANELS).forEach((cfg) => {
        const el = document.getElementById(cfg.modalId);
        if (!el || typeof bootstrap === 'undefined') return;
        const inst = bootstrap.Modal.getInstance(el);
        if (inst) inst.hide();
    });
}

function openSimulationPanel(kind) {
    const cfg = SIM_PANELS[kind];
    if (!cfg || typeof bootstrap === 'undefined') return;
    mountPanelToModal(kind);
    const modalEl = document.getElementById(cfg.modalId);
    if (!modalEl) return;
    bootstrap.Modal.getOrCreateInstance(modalEl).show();
}

function syncFullscreenMarketControlsFromMain() {
    const fsSymbol = document.getElementById('fs-market-symbol');
    const fsTf = document.getElementById('fs-market-timeframe');
    const fsSource = document.getElementById('fs-market-source');
    const fsDays = document.getElementById('fs-market-days');
    if (fsSymbol) fsSymbol.value = String(document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    if (fsTf) fsTf.value = normalizeTimeframeLabel(document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
    if (fsSource) fsSource.value = getSelectedLiveSource() === 'databento' ? 'databento' : 'mt5';
    if (fsDays) fsDays.value = String(getLiveHistoryDays());
}

async function applyFullscreenMarketSwitch() {
    const nextSymbol = String(document.getElementById('fs-market-symbol')?.value || document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    const nextTf = normalizeTimeframeLabel(document.getElementById('fs-market-timeframe')?.value || document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
    const nextSource = String(document.getElementById('fs-market-source')?.value || document.getElementById('live-source')?.value || 'mt5').toLowerCase() === 'databento' ? 'databento' : 'mt5';
    const rawDays = Number(document.getElementById('fs-market-days')?.value || document.getElementById('live-history-days')?.value || 2);
    const nextDays = Math.max(0.1, Math.min(60, Number.isFinite(rawDays) ? rawDays : 2));

    const symEl = document.getElementById('sim-symbol');
    const tfEl = document.getElementById('sim-timeframe');
    const srcEl = document.getElementById('live-source');
    const daysEl = document.getElementById('live-history-days');
    if (symEl) symEl.value = nextSymbol;
    if (tfEl) tfEl.value = nextTf;
    if (srcEl) srcEl.value = nextSource;
    if (daysEl) daysEl.value = String(nextDays);

    if (!(liveFeedActive || liveFeedRequested)) {
        showStatus(`Context set: ${nextSymbol} ${nextTf} (${getLiveSourceLabel(nextSource)}).`, 'info');
        return;
    }
    try {
        showStatus(`Switching live feed to ${nextSymbol} ${nextTf} (${getLiveSourceLabel(nextSource)})...`, 'info');
        stopLiveFeed();
        await startLiveFeed(false);
    } catch (err) {
        showStatus(`Live context switch failed: ${err?.message || err}`, 'danger');
    }
}

function setSimulationFullscreenUI(active) {
    fullscreenSimulation = !!active;
    document.body.classList.toggle('simulation-fullscreen', fullscreenSimulation);
    const dock = document.getElementById('simulation-fs-dock');
    if (dock) dock.classList.toggle('d-none', !fullscreenSimulation);
    const btn = document.getElementById('btn-toggle-fullscreen');
    if (btn) {
        btn.innerHTML = fullscreenSimulation
            ? '<i class="bi bi-fullscreen-exit me-1"></i>Exit Focus'
            : '<i class="bi bi-arrows-fullscreen me-1"></i>Focus Mode';
    }
    if (!fullscreenSimulation) {
        closeAllPanelModals();
        restoreAllPanelsHome();
    } else {
        syncFullscreenMarketControlsFromMain();
    }
    requestAnimationFrame(() => setTimeout(refreshChartViewport, 60));
}

async function toggleSimulationFullscreen() {
    try {
        if (document.fullscreenElement) {
            await document.exitFullscreen();
            return;
        }
        const root = document.documentElement;
        if (root.requestFullscreen) {
            await root.requestFullscreen();
            return;
        }
        setSimulationFullscreenUI(!fullscreenSimulation);
    } catch (_) {
        setSimulationFullscreenUI(!fullscreenSimulation);
    }
}

function readIndicatorVisibilityFromUI() {
    const read = (id, def = true) => {
        const el = document.getElementById(id);
        if (!el) return def;
        return !!el.checked;
    };
    indicatorVisibility = {
        trend: read('ind-vis-trend', true),
        osc: read('ind-vis-osc', true),
        volatility: read('ind-vis-volatility', true),
        overlays: read('ind-vis-overlays', true),
    };
}

function resetIndicatorVisibilityUI() {
    ['ind-vis-trend', 'ind-vis-osc', 'ind-vis-volatility', 'ind-vis-overlays'].forEach((id) => {
        const el = document.getElementById(id);
        if (el) el.checked = true;
    });
    readIndicatorVisibilityFromUI();
    showStatus('Indicator visibility reset', 'info');
}

function upsertLiveBar(bar) {
    if (!bar || !Number.isFinite(Number(bar.time))) return;
    const t = Number(bar.time);
    if (allBars.length > 0 && Number(allBars[allBars.length - 1].time) === t) {
        allBars[allBars.length - 1] = bar;
    } else {
        allBars.push(bar);
    }
    currentBar = Math.max(0, allBars.length - 1);
    totalBars = allBars.length;
}

function _resolveUnixFromChartTime(t) {
    if (typeof t === 'number' && Number.isFinite(t)) return Math.floor(t);
    if (t && typeof t === 'object' && Number.isFinite(Number(t.year)) && Number.isFinite(Number(t.month)) && Number.isFinite(Number(t.day))) {
        return Math.floor(Date.UTC(Number(t.year), Number(t.month) - 1, Number(t.day)) / 1000);
    }
    return null;
}

function _findBarIndexByTime(ts) {
    if (!Number.isFinite(Number(ts)) || !Array.isArray(allBars) || allBars.length === 0) return -1;
    const t = Number(ts);
    for (let i = allBars.length - 1; i >= 0; i -= 1) {
        if (Number(allBars[i]?.time) === t) return i;
    }
    const tfSec = Math.max(60, timeframeToMinutes(document.getElementById('sim-timeframe')?.value || 'M15') * 60);
    let bestIdx = -1;
    let bestDiff = Number.POSITIVE_INFINITY;
    for (let i = 0; i < allBars.length; i += 1) {
        const bt = Number(allBars[i]?.time);
        if (!Number.isFinite(bt)) continue;
        const d = Math.abs(bt - t);
        if (d < bestDiff) {
            bestDiff = d;
            bestIdx = i;
        }
    }
    return bestDiff <= (tfSec * 2) ? bestIdx : -1;
}

function _updateDrawFvgStatus(msg) {
    const el = document.getElementById('draw-fvg-status');
    if (el) el.textContent = String(msg || '');
}

function _syncDrawFvgStatusFromPicks() {
    const picks = Array.isArray(toolStates?.draw_fvg?.picks) ? toolStates.draw_fvg.picks : [];
    if (picks.length === 0) {
        _updateDrawFvgStatus('Pick two bars on chart to begin.');
        return;
    }
    if (picks.length === 1) {
        const idx = picks[0];
        const bar = allBars[idx];
        _updateDrawFvgStatus(`1/2 selected: bar #${idx + 1} @ ${bar?.time || 'n/a'}. Pick one more.`);
        return;
    }
    const a = Math.min(picks[0], picks[1]);
    const b = Math.max(picks[0], picks[1]);
    _updateDrawFvgStatus(`Selected range: bar #${a + 1} to #${b + 1} (${b - a + 1} bars).`);
}

function resetDrawFvgPicks() {
    if (!toolStates.draw_fvg) toolStates.draw_fvg = { enabled: false, picks: [] };
    toolStates.draw_fvg.picks = [];
    _syncDrawFvgStatusFromPicks();
}

async function scanDrawFvgSelection() {
    if (!sessionId) {
        showStatus('Start a session first', 'warning');
        return;
    }
    const picks = Array.isArray(toolStates?.draw_fvg?.picks) ? toolStates.draw_fvg.picks : [];
    if (picks.length < 2) {
        showStatus('Pick two bars first', 'warning');
        return;
    }
    const start = Math.min(picks[0], picks[1]);
    const end = Math.max(picks[0], picks[1]);
    const selected = Array.isArray(allBars) ? allBars.slice(start, end + 1) : [];
    if (selected.length < 3) {
        showStatus('Selection must include at least 3 bars', 'warning');
        return;
    }

    const strictness = Math.max(1, Math.min(5, Number(document.getElementById('tool-fvg-strictness')?.value || 3)));
    const lookbackDays = Math.max(0.1, Math.min(30, Number(document.getElementById('fvg-lookback-days')?.value || 2)));
    const config = {
        strictness,
        lookback_days: lookbackDays,
        scan_scope: 'visible',
        trend_filter_enabled: false,
        trend_alignment_mode: 'prefer',
        trend_multiplier: 3,
    };

    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/tools/fvg/scan`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                config,
                bars: selected.map((b) => ({
                    time: Number(b.time || 0),
                    open: Number(b.open || 0),
                    high: Number(b.high || 0),
                    low: Number(b.low || 0),
                    close: Number(b.close || 0),
                    volume: Number(b.volume || 0),
                })),
            }),
        });
        const data = await res.json();
        if (!res.ok || data?.error) {
            showStatus(`manual FVG scan error: ${data?.error || res.status}`, 'danger');
            return;
        }
        const zones = Array.isArray(data?.zones) ? data.zones : [];
        if (zoneRenderer) {
            zoneRenderer.clearAll();
            renderedToolId = 'fvg';
            for (const z of zones) zoneRenderer.addZone(z);
        }
        showStatus(`Manual FVG scan: ${zones.length} zone(s) in selected range`, zones.length > 0 ? 'success' : 'info');
    } catch (err) {
        showStatus(`manual FVG scan error: ${err.message}`, 'danger');
    }
}

async function handleDrawFvgChartClick(param) {
    if (!toolStates?.draw_fvg?.enabled) return;
    const ts = _resolveUnixFromChartTime(param?.time);
    const idx = _findBarIndexByTime(ts);
    if (idx < 0) {
        showStatus('Could not map click to a candle. Zoom in and try again.', 'warning');
        return;
    }
    if (!Array.isArray(toolStates.draw_fvg.picks)) toolStates.draw_fvg.picks = [];
    const picks = toolStates.draw_fvg.picks;
    if (picks.length >= 2) {
        toolStates.draw_fvg.picks = [idx];
    } else if (picks.length === 1 && picks[0] === idx) {
        return;
    } else {
        picks.push(idx);
    }
    _syncDrawFvgStatusFromPicks();
    if (toolStates.draw_fvg.picks.length >= 2) {
        await scanDrawFvgSelection();
    }
}

async function toggleLiveFeed() {
    if (liveFeedActive || liveFeedRequested) {
        stopLiveFeed();
        return;
    }
    await startLiveFeed(false);
}

function stopLiveFeed() {
    liveFeedRequested = false;
    liveFeedManualStop = true;
    liveFeedActive = false;
    liveFeedReconnectAttempts = 0;
    if (liveFeedSocket) {
        const s = liveFeedSocket;
        liveFeedSocket = null;
        try { s.close(); } catch (_) { /* ignore */ }
    }
    setLiveFeedButtonState(false);
    if (sessionId) {
        document.getElementById('playback-controls')?.classList.remove('d-none');
        setTransportMode('READY');
    } else {
        document.getElementById('playback-controls')?.classList.add('d-none');
        setTransportMode('IDLE');
    }
}

async function autoSwitchLiveContextFromInputs(reasonLabel = 'context change') {
    if (!(liveFeedActive || liveFeedRequested)) return;
    const symbol = String(document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    const tf = normalizeTimeframeLabel(document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
    const src = getSelectedLiveSource() === 'databento' ? 'databento' : 'mt5';
    showStatus(`Switching ${reasonLabel}: ${symbol} ${tf} (${getLiveSourceLabel(src)})...`, 'info');
    stopLiveFeed();
    await startLiveFeed(false);
}

function _buildLiveWsUrl(source, symbol, timeframe, historyBars) {
    const wsProtocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const wsHost = `${window.location.hostname}:${WS_BACKEND_PORT}`;
    const params = new URLSearchParams();
    params.set('symbol', symbol);
    params.set('timeframe', timeframe);
    params.set('history', String(Math.max(2, Math.min(10000, Number(historyBars || 300)))));
    params.set('poll_ms', source === 'databento' ? '15000' : '1000');

    if (source === 'databento') {
        return `${wsProtocol}://${wsHost}/api/v1/simulation/ws/databento/live?${params.toString()}`;
    }
    return `${wsProtocol}://${wsHost}/api/v1/simulation/ws/mt5/live?${params.toString()}`;
}

async function _checkLiveSourceReady(source, symbol, timeframe) {
    const params = new URLSearchParams({ symbol, timeframe });
    if (source === 'databento') {
        const payload = {
            symbol,
            timeframe,
            api_key: getDatabentoApiKey() || null,
            dataset: 'GLBX.MDP3',
            stype_in: 'continuous',
        };
        const statusRes = await fetch(`${API_BASE}/api/simulation/databento/status`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const status = await statusRes.json().catch(() => ({}));
        return {
            ok: !!statusRes.ok && status?.ok !== false && !!status?.databento_connected,
            error: status?.error || status?.status?.error || 'databento unavailable',
        };
    }
    const statusRes = await fetch(`${API_BASE}/api/simulation/mt5/status?${params.toString()}`);
    const status = await statusRes.json().catch(() => ({}));
    return {
        ok: !!statusRes.ok && status?.ok !== false && !!status?.mt5_connected,
        error: status?.error || 'mt5 unavailable',
    };
}

async function startLiveFeed(isReconnect = false) {
    stopPlay();
    const symbol = document.getElementById('sim-symbol')?.value || 'XAUUSD';
    const timeframe = normalizeTimeframeLabel(document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
    const historyDays = getLiveHistoryDays();
    const historyBars = historyBarsFor(timeframe, historyDays);
    const source = getSelectedLiveSource();
    const sourceLabel = getLiveSourceLabel(source);

    if (!isReconnect) {
        liveFeedRequested = true;
        liveFeedManualStop = false;
        liveFeedReconnectAttempts = 0;
    }

    const hasSession = await ensureSessionForLive(symbol, timeframe);
    if (!hasSession) {
        if (!isReconnect) liveFeedRequested = false;
        return;
    }

    try {
        const chk = await _checkLiveSourceReady(source, symbol, timeframe);
        if (!chk.ok) {
            showStatus(`${sourceLabel} not ready: ${chk.error}`, 'warning');
            if (!isReconnect) liveFeedRequested = false;
            return;
        }
    } catch (err) {
        showStatus(`${sourceLabel} status check failed: ${err.message}`, 'warning');
        if (!isReconnect) liveFeedRequested = false;
        return;
    }

    const wsUrl = _buildLiveWsUrl(source, symbol, timeframe, historyBars);
    try {
        const ws = new WebSocket(wsUrl);
        liveFeedSocket = ws;
        ws.onopen = () => {
            if (source === 'databento') {
                const apiKey = getDatabentoApiKey();
                if (apiKey) {
                    try { ws.send(JSON.stringify({ type: 'auth', api_key: apiKey })); } catch (_) { /* ignore */ }
                }
            }
            liveFeedActive = true;
            liveFeedManualStop = false;
            setLiveFeedButtonState(true, source);
            setTransportMode(source === 'databento' ? 'DATABENTO' : 'MT5');
            showStatus(`${sourceLabel} live feed started: ${symbol} ${timeframe} (${historyDays} day window)`, 'success');
            document.getElementById('playback-controls')?.classList.add('d-none');
            clearIndicators();
            updateSteps([]);
            updateSuggestion(null);
        };
        ws.onmessage = (event) => {
            let msg = null;
            try { msg = JSON.parse(event.data); } catch (_) { return; }
            if (!msg || !msg.type) return;

            if (msg.type === 'snapshot') {
                const bars = Array.isArray(msg.bars) ? msg.bars : [];
                allBars = bars.slice();
                currentBar = Math.max(0, allBars.length - 1);
                totalBars = allBars.length;
                candleSeries.setData(allBars);
                volumeSeries.setData(allBars.map(b => ({
                    time: b.time,
                    value: b.volume || 0,
                    color: b.close >= b.open ? '#26a69a44' : '#ef535044',
                })));
                updateBarCounter();
                return;
            }

            if (msg.type === 'tick') {
                const bars = Array.isArray(msg.bars) ? msg.bars : [];
                for (const b of bars) {
                    upsertLiveBar(b);
                    candleSeries.update(b);
                    volumeSeries.update({
                        time: b.time,
                        value: b.volume || 0,
                        color: b.close >= b.open ? '#26a69a44' : '#ef535044',
                    });
                }
                updateBarCounter();
                return;
            }

            if (msg.type === 'warning') {
                showStatus(String(msg.message || `${sourceLabel} warning`), 'warning');
                return;
            }
            if (msg.type === 'error') {
                showStatus(String(msg.message || `${sourceLabel} stream error`), 'danger');
            }
        };
        ws.onclose = () => {
            const wasRequested = liveFeedRequested && !liveFeedManualStop;
            liveFeedActive = false;
            if (liveFeedSocket === ws) liveFeedSocket = null;
            setLiveFeedButtonState(false, source);
            if (wasRequested) {
                const backoffMs = Math.min(8000, 500 * Math.pow(2, liveFeedReconnectAttempts));
                liveFeedReconnectAttempts += 1;
                showStatus(`${sourceLabel} live feed disconnected, reconnecting...`, 'warning');
                setTimeout(() => {
                    if (liveFeedRequested && !liveFeedActive) void startLiveFeed(true);
                }, backoffMs);
                return;
            }
            if (!isPlaying) setTransportMode(sessionId ? 'READY' : 'IDLE');
            showStatus(`${sourceLabel} live feed stopped`, 'info');
        };
        ws.onerror = () => {
            showStatus(`${sourceLabel} live feed socket error`, 'danger');
        };
    } catch (err) {
        if (!isReconnect) liveFeedRequested = false;
        showStatus(`Failed to start ${sourceLabel} live feed: ${err.message}`, 'danger');
    }
}

async function ensureSessionForLive(symbol, timeframe) {
    if (sessionId) return true;
    const dataFile = document.getElementById('sim-datafile')?.value || '';
    const balance = parseFloat(document.getElementById('sim-balance')?.value) || 10000;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                strategy_id: STRATEGY_ID,
                symbol,
                timeframe,
                data_file: dataFile || null,
                initial_balance: balance,
                allow_empty_replay: true,
            }),
        });
        const data = await res.json();
        if (!res.ok || data?.error || !data?.id) {
            showStatus(`Session init failed: ${data?.error || 'backend error'}`, 'danger');
            return false;
        }
        sessionId = data.id;
        persistSessionId(sessionId);
        totalBars = Number(data.total_bars || 0);
        currentBar = 0;
        initialBalance = Number(data.initial_balance || balance || 10000);
        updateStats({ balance: initialBalance, total_pnl: 0, trades_count: 0, wins: 0 });
        return true;
    } catch (err) {
        showStatus(`Session init failed: ${err.message}`, 'danger');
        return false;
    }
}

function maybeTunePlayback() {
    if (!isPlaying || !adaptiveSpeedEnabled) return;
    if (!barsPerSecond || barsPerSecond <= 0) return;
    const now = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
    if (now - adaptiveLastTuneMs < ADAPTIVE_TUNE_INTERVAL_MS) return;

    const expectedBarsPerSec = (playSpeed * 1000.0) / Math.max(20, tickMs);
    const idx = SPEED_STEPS.indexOf(playSpeed);
    let nextIdx = idx;

    // If achieved throughput is much lower than expected, step down.
    if (barsPerSecond < expectedBarsPerSec * 0.60 && idx > 0) {
        nextIdx = idx - 1;
    }
    // If throughput is near expected and stable, step up.
    if (barsPerSecond > expectedBarsPerSec * 0.92 && idx < SPEED_STEPS.length - 1) {
        nextIdx = idx + 1;
    }

    if (nextIdx === idx) return;
    const oldSpeed = playSpeed;
    const changed = setPlaybackSpeed(SPEED_STEPS[nextIdx]);
    if (!changed) return;

    adaptiveLastTuneMs = now;
    showStatus(`Adaptive speed: ${oldSpeed}x -> ${playSpeed}x`, 'info');

    // WS speed/tick are query params; reconnect so backend applies new values.
    if (playSocket) {
        wsReconnectRequested = true;
        try { playSocket.close(); } catch (_) { /* ignore */ }
    }
}


// ── Initialization ──────────────────────────────────────────

class ChartZoneRenderer {
    constructor(chartObj, series) {
        this.chart = chartObj;
        this.series = series;
        this.container = chartObj.chartElement();
        this.overlayContainer = document.createElement('div');
        this.overlayContainer.className = 'chart-zones-overlay';
        this.container.style.position = 'relative';
        this.container.appendChild(this.overlayContainer);
        this.zones = [];
        this.chart.timeScale().subscribeVisibleLogicalRangeChange(() => this._repositionAll());
        this.series.subscribeDataChanged(() => this._repositionAll());
    }

    addZone(zone) {
        const div = document.createElement('div');
        div.className = `fvg-zone ${zone.type || ''}`;
        this.overlayContainer.appendChild(div);
        this.zones.push({ data: zone, el: div });
        this._positionZone(zone, div);
    }

    _positionZone(zone, div) {
        const timeScale = this.chart.timeScale();
        const x1 = timeScale.timeToCoordinate(Number(zone.start_time_unix || zone.end_time_unix || 0));
        const x2 = timeScale.timeToCoordinate(Number(zone.end_time_unix || zone.start_time_unix || 0));
        const y1 = this.series.priceToCoordinate(Number(zone.top));
        const y2 = this.series.priceToCoordinate(Number(zone.bottom));
        if (x1 === null || x2 === null || y1 === null || y2 === null) {
            div.style.display = 'none';
            return;
        }
        div.style.display = 'block';
        div.style.left = `${Math.min(x1, x2)}px`;
        div.style.top = `${Math.min(y1, y2)}px`;
        div.style.width = `${Math.abs(x2 - x1) + 20}px`;
        div.style.height = `${Math.max(Math.abs(y2 - y1), 2)}px`;
    }

    _repositionAll() {
        for (const z of this.zones) this._positionZone(z.data, z.el);
    }

    clearAll() {
        for (const z of this.zones) z.el.remove();
        this.zones = [];
    }
}

document.addEventListener('DOMContentLoaded', () => {
    tickMs = getTickMsForSpeed(playSpeed);
    setTransportMode('IDLE');
    updateSpeedButtons();
    updatePerfStats();
    updateReliabilityStats();
    setLiveFeedButtonState(false);
    readIndicatorVisibilityFromUI();
    initChart();
    bindEvents();
    ensurePanelHomeMarkers();
    setSimulationFullscreenUI(!!document.fullscreenElement);
    void restoreLastSession();
});


function initChart() {
    const container = document.getElementById('chart-main');
    if (!container || typeof LightweightCharts === 'undefined') {
        console.error('Chart container or LightweightCharts not found');
        return;
    }

    chart = LightweightCharts.createChart(container, {
        width: container.clientWidth,
        height: 400,
        layout: {
            background: { type: 'solid', color: '#131722' },
            textColor: '#d1d4dc',
            fontSize: 12,
        },
        grid: {
            vertLines: { color: '#1e222d' },
            horzLines: { color: '#1e222d' },
        },
        crosshair: {
            mode: LightweightCharts.CrosshairMode.Normal,
        },
        rightPriceScale: {
            borderColor: '#2a2e39',
        },
        timeScale: {
            borderColor: '#2a2e39',
            timeVisible: true,
            secondsVisible: false,
        },
    });

    candleSeries = chart.addCandlestickSeries({
        upColor: '#26a69a',
        downColor: '#ef5350',
        borderDownColor: '#ef5350',
        borderUpColor: '#26a69a',
        wickDownColor: '#ef5350',
        wickUpColor: '#26a69a',
    });

    // Volume as histogram at bottom of main chart
    volumeSeries = chart.addHistogramSeries({
        color: '#385263',
        priceFormat: { type: 'volume' },
        priceScaleId: 'volume',
    });

    chart.priceScale('volume').applyOptions({
        scaleMargins: { top: 0.85, bottom: 0 },
    });

    // Handle resize
    const resizeObserver = new ResizeObserver(entries => {
        for (const entry of entries) {
            chart.applyOptions({ width: entry.contentRect.width });
        }
    });
    resizeObserver.observe(container);

    zoneRenderer = new ChartZoneRenderer(chart, candleSeries);
    if (chartClickHandler) {
        try { chart.unsubscribeClick(chartClickHandler); } catch (_) { /* ignore */ }
    }
    chartClickHandler = (param) => { void handleDrawFvgChartClick(param); };
    chart.subscribeClick(chartClickHandler);

    // Sub-chart for indicators (MACD, RSI, ADX)
    initSubChart();
}


function initSubChart() {
    const container = document.getElementById('chart-sub');
    if (!container) return;

    subChart = LightweightCharts.createChart(container, {
        width: container.clientWidth,
        height: 120,
        layout: {
            background: { type: 'solid', color: '#131722' },
            textColor: '#d1d4dc',
            fontSize: 10,
        },
        grid: {
            vertLines: { color: '#1e222d' },
            horzLines: { color: '#1e222d' },
        },
        rightPriceScale: { borderColor: '#2a2e39' },
        timeScale: { borderColor: '#2a2e39', visible: false },
    });

    const resizeObserver = new ResizeObserver(entries => {
        for (const entry of entries) {
            subChart.applyOptions({ width: entry.contentRect.width });
        }
    });
    resizeObserver.observe(container);
}


function bindEvents() {
    document.getElementById('btn-toggle-fullscreen')?.addEventListener('click', toggleSimulationFullscreen);
    document.addEventListener('fullscreenchange', () => {
        setSimulationFullscreenUI(!!document.fullscreenElement);
    });
    document.querySelectorAll('[data-panel-launch]').forEach((btn) => {
        btn.addEventListener('click', () => {
            const kind = String(btn.getAttribute('data-panel-launch') || '').trim().toLowerCase();
            openSimulationPanel(kind);
        });
    });
    document.getElementById('dock-open-indicators')?.addEventListener('click', () => {
        const m = document.getElementById('indicatorModal');
        if (!m || typeof bootstrap === 'undefined') return;
        bootstrap.Modal.getOrCreateInstance(m).show();
    });
    document.getElementById('dock-open-market')?.addEventListener('click', () => {
        const m = document.getElementById('marketSwitchModal');
        if (!m || typeof bootstrap === 'undefined') return;
        syncFullscreenMarketControlsFromMain();
        bootstrap.Modal.getOrCreateInstance(m).show();
    });
    document.getElementById('dock-exit-focus')?.addEventListener('click', () => {
        void toggleSimulationFullscreen();
    });
    document.getElementById('btn-fs-market-apply')?.addEventListener('click', async () => {
        await applyFullscreenMarketSwitch();
        const m = document.getElementById('marketSwitchModal');
        if (!m || typeof bootstrap === 'undefined') return;
        bootstrap.Modal.getOrCreateInstance(m).hide();
    });
    document.getElementById('marketSwitchModal')?.addEventListener('show.bs.modal', () => {
        syncFullscreenMarketControlsFromMain();
    });
    Object.entries(SIM_PANELS).forEach(([kind, cfg]) => {
        const modalEl = document.getElementById(cfg.modalId);
        if (!modalEl) return;
        modalEl.addEventListener('show.bs.modal', () => {
            mountPanelToModal(kind);
        });
        modalEl.addEventListener('hidden.bs.modal', () => {
            restorePanelHome(kind);
            requestAnimationFrame(() => setTimeout(refreshChartViewport, 40));
        });
    });
    document.getElementById('btn-open-tools')?.addEventListener('click', () => {
        mountPanelToModal('tools');
    });

    // Start session button
    document.getElementById('btn-start-session')?.addEventListener('click', startSession);
    document.getElementById('btn-live-feed')?.addEventListener('click', toggleLiveFeed);
    document.getElementById('sim-symbol')?.addEventListener('change', () => {
        void autoSwitchLiveContextFromInputs('symbol change');
    });
    document.getElementById('sim-timeframe')?.addEventListener('change', () => {
        void autoSwitchLiveContextFromInputs('timeframe change');
    });
    document.getElementById('live-source')?.addEventListener('change', () => {
        if (!liveFeedActive && !liveFeedRequested) setLiveFeedButtonState(false);
        void autoSwitchLiveContextFromInputs('source change');
    });
    document.getElementById('live-history-days')?.addEventListener('change', () => {
        const el = document.getElementById('live-history-days');
        const normalized = getLiveHistoryDays();
        if (el) el.value = String(normalized);
        if (fullscreenSimulation) {
            const fsDays = document.getElementById('fs-market-days');
            if (fsDays) fsDays.value = String(normalized);
        }
        void autoSwitchLiveContextFromInputs('window change');
    });

    // Playback controls
    document.getElementById('btn-rewind')?.addEventListener('click', () => advanceBars(-10));
    document.getElementById('btn-prev')?.addEventListener('click', () => advanceBars(-1));
    document.getElementById('btn-play')?.addEventListener('click', togglePlay);
    document.getElementById('btn-next')?.addEventListener('click', () => advanceBars(1));
    document.getElementById('btn-forward')?.addEventListener('click', () => advanceBars(10));

    // Speed buttons
    document.querySelectorAll('.speed-btn[data-speed]').forEach(btn => {
        btn.addEventListener('click', () => {
            const speed = parseInt(btn.dataset.speed, 10) || 1;
            const changed = setPlaybackSpeed(speed);
            if (changed && sessionId && isPlaying) {
                stopPlay();
                startPlay();
                return;
            }
            if (changed) showStatus(`Speed set to ${playSpeed}x`, 'info');
        });
    });

    document.getElementById('btn-auto-speed')?.addEventListener('click', () => {
        adaptiveSpeedEnabled = !adaptiveSpeedEnabled;
        updateSpeedButtons();
        setTransportMode(transportMode);
        showStatus(`Adaptive speed ${adaptiveSpeedEnabled ? 'enabled' : 'disabled'}`, 'info');
    });

    // Trade buttons
    document.getElementById('btn-buy')?.addEventListener('click', () => executeTrade('BUY'));
    document.getElementById('btn-sell')?.addEventListener('click', () => executeTrade('SELL'));
    document.getElementById('btn-close-pos')?.addEventListener('click', closePosition);

    // Reset button
    document.getElementById('btn-reset')?.addEventListener('click', resetSession);

    document.getElementById('tool-fvg-toggle')?.addEventListener('change', (e) => {
        const settings = document.getElementById('fvg-settings');
        if (settings) settings.classList.toggle('active', e.target.checked);
        toolStates.fvg.enabled = !!e.target.checked;
        if (e.target.checked && sessionId) {
            void scanTool('fvg');
        } else if (!e.target.checked) {
            clearToolZones('fvg');
        }
    });
    document.getElementById('tool-mean-rev-toggle')?.addEventListener('change', (e) => {
        const settings = document.getElementById('mean-rev-settings');
        if (settings) settings.classList.toggle('active', e.target.checked);
        toolStates.mean_rev.enabled = !!e.target.checked;
        if (e.target.checked && sessionId) {
            void scanTool('mean_rev');
        } else if (!e.target.checked) {
            clearToolZones('mean_rev');
        }
    });
    document.getElementById('btn-fvg-scan')?.addEventListener('click', () => scanTool('fvg'));
    document.getElementById('btn-fvg-clear')?.addEventListener('click', () => clearToolZones('fvg'));
    document.getElementById('btn-mean-rev-scan')?.addEventListener('click', () => scanTool('mean_rev'));
    document.getElementById('btn-mean-rev-clear')?.addEventListener('click', () => clearToolZones('mean_rev'));
    document.getElementById('tool-draw-fvg-toggle')?.addEventListener('change', (e) => {
        const settings = document.getElementById('draw-fvg-settings');
        if (settings) settings.classList.toggle('active', e.target.checked);
        if (!toolStates.draw_fvg) toolStates.draw_fvg = { enabled: false, picks: [] };
        toolStates.draw_fvg.enabled = !!e.target.checked;
        if (!toolStates.draw_fvg.enabled) {
            resetDrawFvgPicks();
            return;
        }
        _updateDrawFvgStatus('Drawing mode active. Click 2 bars on chart.');
    });
    document.getElementById('btn-draw-fvg-reset')?.addEventListener('click', () => {
        resetDrawFvgPicks();
        showStatus('Manual FVG picks reset', 'info');
    });
    document.getElementById('btn-draw-fvg-scan')?.addEventListener('click', () => {
        void scanDrawFvgSelection();
    });

    ['ind-vis-trend', 'ind-vis-osc', 'ind-vis-volatility', 'ind-vis-overlays'].forEach((id) => {
        document.getElementById(id)?.addEventListener('change', () => {
            readIndicatorVisibilityFromUI();
            // force full redraw of indicator series with visibility filters
            clearIndicators();
            if (allBars.length > 0 && sessionId) {
                void fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/seek?bar=${currentBar}`, { method: 'POST' })
                    .then(r => r.json())
                    .then(d => { if (!d?.error) applyAdvancePayload(d); });
            }
        });
    });
    document.getElementById('btn-indicators-reset')?.addEventListener('click', resetIndicatorVisibilityUI);

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT' || e.target.tagName === 'TEXTAREA') return;
        switch(e.code) {
            case 'Space': e.preventDefault(); togglePlay(); break;
            case 'ArrowRight': advanceBars(1); break;
            case 'ArrowLeft': advanceBars(-1); break;
        }
    });
}

function _buildToolScanConfig(toolId) {
    if (toolId === 'mean_rev') {
        return {
            strictness: Math.max(1, Math.min(5, Number(document.getElementById('tool-mean-rev-strictness')?.value || 3))),
            sma_period: Math.max(5, Math.min(400, Number(document.getElementById('mean-rev-sma-period')?.value || 30))),
            deviation: Math.max(0.5, Math.min(8, Number(document.getElementById('mean-rev-deviation')?.value || 2.0))),
            scan_scope: 'visible',
            lookback_days: 2,
        };
    }
    return {
        strictness: Math.max(1, Math.min(5, Number(document.getElementById('tool-fvg-strictness')?.value || 3))),
        lookback_days: Math.max(0.1, Math.min(30, Number(document.getElementById('fvg-lookback-days')?.value || 2))),
        scan_scope: 'last_n_days',
        trend_filter_enabled: true,
        trend_alignment_mode: 'prefer',
        trend_multiplier: 3,
    };
}

async function scanTool(toolId) {
    if (!sessionId) {
        showStatus('Start a session first', 'warning');
        return;
    }
    const config = _buildToolScanConfig(toolId);
    const barsPayload = Array.isArray(allBars) && allBars.length >= 3
        ? allBars.slice(-12000).map((b) => ({
            time: Number(b.time || 0),
            open: Number(b.open || 0),
            high: Number(b.high || 0),
            low: Number(b.low || 0),
            close: Number(b.close || 0),
            volume: Number(b.volume || 0),
        }))
        : [];
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/tools/${toolId}/scan`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ config, bars: barsPayload }),
        });
        const data = await res.json();
        if (!res.ok || data?.error) {
            showStatus(`${toolId} scan error: ${data?.error || res.status}`, 'danger');
            return;
        }
        if (zoneRenderer) {
            zoneRenderer.clearAll();
            renderedToolId = toolId;
            const zones = Array.isArray(data?.zones) ? data.zones : [];
            for (const z of zones) zoneRenderer.addZone(z);
            showStatus(`${toolId} scan: found ${zones.length} zone(s)`, 'success');
        }
    } catch (err) {
        showStatus(`${toolId} scan error: ${err.message}`, 'danger');
    }
}

function clearToolZones(toolId) {
    if (zoneRenderer && (!renderedToolId || renderedToolId === toolId)) {
        zoneRenderer.clearAll();
        renderedToolId = null;
    }
    showStatus(`${toolId} zones cleared`, 'info');
}


// ── Session Management ──────────────────────────────────────

async function restoreLastSession() {
    const persisted = loadPersistedSessionId();
    if (!persisted) return;

    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${persisted}`);
        const session = await res.json();
        if (!session || session.error || !session.id) {
            clearPersistedSessionId();
            return;
        }
        if (session.strategy_id && session.strategy_id !== STRATEGY_ID) {
            clearPersistedSessionId();
            return;
        }

        sessionId = session.id;
        currentBar = Number(session.current_bar || 0);
        totalBars = Number(session.total_bars || 0);
        initialBalance = Number(session.initial_balance || 10000);
        barsPerSecond = 0;
        tickCounter = 0;
        tickWindowStartMs = 0;
        lastPayloadAtMs = 0;
        droppedTickCount = 0;
        reconnectCount = 0;
        latencySamples = [];
        updatePerfStats();
        updateReliabilityStats();

        document.getElementById('playback-controls')?.classList.remove('d-none');
        document.getElementById('sim-config-panel')?.classList.add('d-none');
        document.getElementById('trade-panel-body')?.classList.remove('d-none');

        showStatus('Restoring previous session...', 'info');
        const seekRes = await fetch(
            `${API_BASE}/api/simulation/sessions/${sessionId}/seek?bar=${currentBar}&include_bars=1&bars_limit=1500`,
            { method: 'POST' }
        );
        const snapshot = await seekRes.json();
        if (snapshot && !snapshot.error) {
            if (Array.isArray(snapshot.bars)) {
                allBars = snapshot.bars.slice();
                candleSeries.setData(allBars);
                volumeSeries.setData(allBars.map(b => ({
                    time: b.time,
                    value: b.volume || 0,
                    color: b.close >= b.open ? '#26a69a44' : '#ef535044',
                })));
            }
            clearIndicators();
            const restorePayload = { ...snapshot, bars: [] };
            applyAdvancePayload(restorePayload);
            if (Array.isArray(session.trades)) {
                renderTradeLog(session.trades);
            }
            setTransportMode(session.status === 'active' ? 'READY' : 'COMPLETED');
            showStatus(
                session.status === 'active'
                    ? 'Session restored. You can continue replay.'
                    : 'Completed session restored.',
                'success'
            );
        }
    } catch (_) {
        clearPersistedSessionId();
    }
}

function renderTradeLog(trades) {
    const tbody = document.getElementById('trade-log-body');
    if (!tbody) return;
    tbody.innerHTML = '';
    const ordered = (trades || []).slice().reverse();
    for (const t of ordered) {
        if ((t.status || '').toLowerCase() === 'closed') {
            addTradeToLog(t);
        }
    }
}

async function startSession() {
    stopLiveFeed();
    stopPlay();
    const symbol = document.getElementById('sim-symbol')?.value || 'XAUUSD';
    const timeframe = document.getElementById('sim-timeframe')?.value || 'M1';
    const dataFile = document.getElementById('sim-datafile')?.value || '';
    const balance = parseFloat(document.getElementById('sim-balance')?.value) || 10000;

    try {
        showStatus('Creating session...');
        const res = await fetch(`${API_BASE}/api/simulation/sessions`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                strategy_id: STRATEGY_ID,
                symbol: symbol,
                timeframe: timeframe,
                data_file: dataFile || null,
                initial_balance: balance,
            }),
        });

        const data = await res.json();
        if (data.error) {
            showStatus(`Error: ${data.error}`, 'danger');
            return;
        }

        sessionId = data.id;
        persistSessionId(sessionId);
        totalBars = data.total_bars || 0;
        currentBar = 0;
        allBars = [];
        squeezeMarkers = [];
        squeezeIndexOffset = 0;
        pendingAdvance = 0;
        isAdvancing = false;
        initialBalance = Number(data.initial_balance || balance || 10000);
        tickCounter = 0;
        tickWindowStartMs = 0;
        barsPerSecond = 0;
        lastPayloadAtMs = 0;
        adaptiveLastTuneMs = 0;
        wsReconnectRequested = false;
        droppedTickCount = 0;
        reconnectCount = 0;
        latencySamples = [];
        updatePerfStats();
        updateReliabilityStats();
        setTransportMode('READY');

        // Clear chart
        candleSeries.setData([]);
        volumeSeries.setData([]);
        clearIndicators();
        if (zoneRenderer) zoneRenderer.clearAll();
        renderedToolId = null;
        resetDrawFvgPicks();

        // Enable controls
        document.getElementById('playback-controls')?.classList.remove('d-none');
        document.getElementById('sim-config-panel')?.classList.add('d-none');
        document.getElementById('trade-panel-body')?.classList.remove('d-none');

        updateBarCounter();
        showStatus(`Session started: ${symbol} ${timeframe} (${totalBars} bars)`, 'success');

        // Advance initial bars to show some data
        await advanceBars(50);

    } catch (err) {
        showStatus(`Connection error: ${err.message}`, 'danger');
    }
}


async function resetSession() {
    if (!sessionId) return;
    stopPlay();

    try {
        await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/reset`, { method: 'POST' });
        currentBar = 0;
        allBars = [];
        squeezeMarkers = [];
        squeezeIndexOffset = 0;
        pendingAdvance = 0;
        tickCounter = 0;
        tickWindowStartMs = 0;
        barsPerSecond = 0;
        lastPayloadAtMs = 0;
        adaptiveLastTuneMs = 0;
        wsReconnectRequested = false;
        droppedTickCount = 0;
        reconnectCount = 0;
        latencySamples = [];
        updatePerfStats();
        updateReliabilityStats();
        setTransportMode('READY');
        candleSeries.setData([]);
        volumeSeries.setData([]);
        clearIndicators();
        if (zoneRenderer) zoneRenderer.clearAll();
        renderedToolId = null;
        resetDrawFvgPicks();
        updateBarCounter();
        updateSteps([]);
        updateStats({ balance: initialBalance, total_pnl: 0, trades_count: 0, wins: 0 });
        updateOpenPosition(null);
        showStatus('Session reset', 'info');
        await advanceBars(50);
    } catch (err) {
        showStatus(`Reset error: ${err.message}`, 'danger');
    }
}


// ── Bar Advancement ──────────────────────────────────────────

async function advanceBars(count) {
    if (liveFeedActive) return;
    if (!sessionId) return;
    if (playSocket && count > 0) return;
    if (isAdvancing) {
        if (count > 0) pendingAdvance += count;
        return;
    }

    // For negative count (rewind), re-render from accumulated bars + sync backend
    if (count < 0) {
        if (isPlaying) stopPlay();
        const newBar = Math.max(0, currentBar + count);
        if (newBar < currentBar) {
            currentBar = newBar;
            // Re-render chart with bars up to currentBar
            const visibleBars = allBars.slice(0, currentBar + 1);
            candleSeries.setData(visibleBars);
            volumeSeries.setData(visibleBars.map(b => ({
                time: b.time,
                value: b.volume || 0,
                color: b.close >= b.open ? '#26a69a44' : '#ef535044',
            })));
            updateBarCounter();

            // Sync backend engine position
            try {
                const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/seek?bar=${currentBar}`, {
                    method: 'POST',
                });
                const data = await res.json();
                applyAdvancePayload(data);
            } catch (e) { /* seek sync failed, non-critical */ }
        }
        return;
    }

    try {
        isAdvancing = true;
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/advance`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ count: count, indicators_mode: 'delta' }),
        });

        const data = await res.json();
        if (data.error) {
            if (String(data.error).toLowerCase().includes('session not found')) {
                clearPersistedSessionId();
                sessionId = null;
                document.getElementById('sim-config-panel')?.classList.remove('d-none');
            }
            showStatus(`Error: ${data.error}`, 'danger');
            stopPlay();
            return;
        }
        applyAdvancePayload(data);

    } catch (err) {
        console.error('Advance error:', err);
        stopPlay();
    } finally {
        isAdvancing = false;
        if (pendingAdvance > 0 && sessionId && (!isPlaying || currentBar < totalBars - 1)) {
            const queued = pendingAdvance;
            pendingAdvance = 0;
            // Avoid overly large jumps from queue buildup.
            const consume = Math.min(queued, 50);
            setTimeout(() => { advanceBars(consume); }, 0);
        }
    }
}


// ── Playback Controls ──────────────────────────────────────

function togglePlay() {
    if (isPlaying) {
        stopPlay();
    } else {
        startPlay();
    }
}

function startWsWatchdog() {
    stopWsWatchdog();
    wsWatchdogTimer = setInterval(() => {
        if (!isPlaying || !playSocket) return;
        const now = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
        if (!lastPayloadAtMs) return;
        const stallThreshold = Math.max(3000, tickMs * WS_STALL_FACTOR);
        if ((now - lastPayloadAtMs) > stallThreshold) {
            droppedTickCount += 1;
            updateReliabilityStats();
            showStatus('WS stream stalled, switching transport...', 'warning');
            wsReconnectRequested = false;
            try { playSocket.close(); } catch (_) { /* ignore */ }
        }
    }, 1000);
}

function stopWsWatchdog() {
    if (wsWatchdogTimer) {
        clearInterval(wsWatchdogTimer);
        wsWatchdogTimer = null;
    }
}

function startPlay() {
    if (liveFeedActive || liveFeedRequested) {
        showStatus('Stop live feed before replay playback.', 'warning');
        return;
    }
    if (!sessionId || isPlaying) return;
    isPlaying = true;
    document.getElementById('btn-play')?.querySelector('i')?.classList.replace('bi-play-fill', 'bi-pause-fill');
    tickCounter = 0;
    tickWindowStartMs = 0;
    barsPerSecond = 0;
    lastPayloadAtMs = 0;
    adaptiveLastTuneMs = 0;
    wsReconnectRequested = false;
    updatePerfStats();
    void startWebSocketPlayback();
}

async function startWebSocketPlayback() {
    if (!sessionId || !isPlaying) return;

    const wsProtocol = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const wsHost = `${window.location.hostname}:${WS_BACKEND_PORT}`;
    const wsUrl = `${wsProtocol}://${wsHost}/api/v1/simulation/ws/sessions/${sessionId}/play?speed=${playSpeed}&tick_ms=${tickMs}&indicators_mode=delta`;
    let connected = false;

    try {
        const ws = new WebSocket(wsUrl);
        playSocket = ws;

        const readyPromise = new Promise((resolve, reject) => {
            const timeout = setTimeout(() => reject(new Error('WS connect timeout')), 1500);

            ws.onopen = () => {
                connected = true;
                clearTimeout(timeout);
                resolve(true);
            };

            ws.onmessage = (event) => {
                let msg = null;
                try {
                    msg = JSON.parse(event.data);
                } catch (_) {
                    return;
                }
                if (!msg || !msg.type) return;

                if (msg.type === 'tick' && msg.data) {
                    applyAdvancePayload(msg.data);
                    return;
                }

                if (msg.type === 'completed') {
                    stopPlay();
                    showStatus(msg.message || 'Replay complete!', 'info');
                    return;
                }

                if (msg.type === 'error') {
                    showStatus(`WS error: ${msg.message || 'unknown'}`, 'warning');
                    try { ws.close(); } catch (_) { /* ignore */ }
                }
            };

            ws.onerror = () => {
                clearTimeout(timeout);
                if (!connected) reject(new Error('WS error'));
            };
        });

        ws.onclose = () => {
            if (playSocket === ws) playSocket = null;
            if (isPlaying) {
                reconnectCount += 1;
                updateReliabilityStats();
                if (wsReconnectRequested) {
                    wsReconnectRequested = false;
                    void startWebSocketPlayback();
                    return;
                }
                showStatus('WebSocket disconnected, using HTTP playback', 'warning');
                startHttpPlaybackLoop();
            }
        };

        await readyPromise;
        lastPayloadAtMs = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
        startWsWatchdog();
        setTransportMode('WS');
        showStatus('Live streaming playback enabled', 'info');
    } catch (err) {
        if (playSocket) {
            try { playSocket.close(); } catch (_) { /* ignore */ }
            playSocket = null;
        }
        if (isPlaying) {
            showStatus('WebSocket unavailable, using HTTP playback', 'warning');
            startHttpPlaybackLoop();
        }
    }
}

function startHttpPlaybackLoop() {
    if (!sessionId || !isPlaying || playSocket) return;
    stopWsWatchdog();
    setTransportMode('HTTP');
    if (playInterval) {
        clearTimeout(playInterval);
        playInterval = null;
    }
    const loop = async () => {
        if (!isPlaying || !sessionId) return;
        const t0 = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
        if (!isAdvancing) {
            await advanceBars(playSpeed);
        }
        const t1 = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
        lastAdvanceMs = Math.max(0, t1 - t0);
        recordLatencySample(lastAdvanceMs);
        if (!isPlaying || !sessionId) return;
        // Keep UI responsive on heavy strategies; never schedule tighter than 50ms.
        const delay = Math.max(50, tickMs - Math.min(lastAdvanceMs, tickMs));
        playInterval = setTimeout(loop, delay);
    };
    void loop();
}

function stopPlay() {
    isPlaying = false;
    wsReconnectRequested = false;
    stopWsWatchdog();
    document.getElementById('btn-play')?.querySelector('i')?.classList.replace('bi-pause-fill', 'bi-play-fill');
    if (playInterval) {
        clearTimeout(playInterval);
        playInterval = null;
    }
    if (playSocket) {
        const socket = playSocket;
        playSocket = null;
        try { socket.close(); } catch (_) { /* ignore */ }
    }
    setTransportMode('PAUSED');
}

function applyAdvancePayload(data) {
    if (!data) return;

    currentBar = data.current_bar ?? currentBar;
    totalBars = data.total_bars ?? totalBars;
    const barsAdded = Array.isArray(data.bars) ? data.bars.length : 0;
    const nowMs = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
    if (lastPayloadAtMs > 0) {
        // Approximate network+backend cadence per tick for adaptive tuning.
        lastAdvanceMs = Math.max(0, nowMs - lastPayloadAtMs);
        if (playSocket) recordLatencySample(lastAdvanceMs);
    }
    lastPayloadAtMs = nowMs;
    if (tickWindowStartMs <= 0) tickWindowStartMs = nowMs;
    tickCounter += barsAdded;
    const elapsed = nowMs - tickWindowStartMs;
    if (elapsed >= 1000) {
        barsPerSecond = (tickCounter * 1000.0) / Math.max(1, elapsed);
        tickCounter = 0;
        tickWindowStartMs = nowMs;
        updatePerfStats();
    }

    if (Array.isArray(data.bars) && data.bars.length > 0) {
        for (const bar of data.bars) {
            allBars.push(bar);
            candleSeries.update(bar);
            volumeSeries.update({
                time: bar.time,
                value: bar.volume || 0,
                color: bar.close >= bar.open ? '#26a69a44' : '#ef535044',
            });
        }
    }

    if (data.indicators) {
        renderIndicators(data.indicators, data.indicators_mode || 'full');
    }
    if (data.overlays) {
        renderOverlays(data.overlays);
    }
    if (data.steps) {
        updateSteps(data.steps);
    }

    updateSuggestion(data.suggestion);

    if (data.day_context) {
        updateBias(data.day_context);
    }

    if (Array.isArray(data.closed_trades) && data.closed_trades.length > 0) {
        for (const ct of data.closed_trades) {
            addTradeToLog(ct);
            showTradeResult(ct);
        }
    }

    if (Array.isArray(data.open_positions) && data.open_positions.length > 0) {
        updateOpenPosition(data.open_positions[0], data.open_pnl);
    } else {
        updateOpenPosition(null);
    }

    updateStats(data);
    updateBarCounter();
    maybeTunePlayback();

    if (currentBar >= totalBars - 1) {
        stopPlay();
        setTransportMode('COMPLETED');
        showStatus('Replay complete!', 'info');
    }
}


// ── Trade Execution ──────────────────────────────────────────

async function executeTrade(direction) {
    if (!sessionId) return;

    const sl = parseFloat(document.getElementById('trade-sl')?.value);
    const tpLong = parseFloat(document.getElementById('trade-tp-long')?.value);
    const tpShort = parseFloat(document.getElementById('trade-tp-short')?.value);
    const tpRaw = direction === 'BUY' ? tpLong : tpShort;
    const tp = Number.isFinite(tpRaw) ? tpRaw : null;
    const lots = parseFloat(document.getElementById('trade-lots')?.value) || 0.01;

    if (!sl || isNaN(sl)) {
        showStatus('Please set a Stop Loss', 'warning');
        return;
    }

    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/trade`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                direction: direction,
                stop_loss: sl,
                take_profit: tp,
                lot_size: lots,
            }),
        });

        const data = await res.json();
        if (data.error) {
            showStatus(`Trade error: ${data.error}`, 'danger');
            return;
        }

        updateOpenPosition(data, 0);
        showStatus(`${direction} @ ${data.entry_price?.toFixed(2)}`, 'success');

        // Add entry marker
        if (allBars.length > 0) {
            const lastBar = allBars[allBars.length - 1];
            candleSeries.setMarkers([{
                time: lastBar.time,
                position: direction === 'BUY' ? 'belowBar' : 'aboveBar',
                color: direction === 'BUY' ? '#26a69a' : '#ef5350',
                shape: direction === 'BUY' ? 'arrowUp' : 'arrowDown',
                text: direction,
            }]);
        }

    } catch (err) {
        showStatus(`Trade error: ${err.message}`, 'danger');
    }
}


async function closePosition() {
    if (!sessionId) return;

    const posEl = document.getElementById('open-pos-id');
    const tradeId = posEl?.dataset.tradeId;
    if (!tradeId) return;

    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/close-trade/${tradeId}`, {
            method: 'POST',
        });
        const data = await res.json();
        if (data.error) {
            showStatus(`Close error: ${data.error}`, 'danger');
            return;
        }

        updateOpenPosition(null);
        addTradeToLog(data);
        showTradeResult(data);

    } catch (err) {
        showStatus(`Close error: ${err.message}`, 'danger');
    }
}


// ── Indicator Rendering ──────────────────────────────────────

function clearIndicators() {
    for (const [name, series] of Object.entries(indicatorSeries)) {
        try {
            if (name.startsWith('sub_') && subChart) {
                subChart.removeSeries(series);
            } else if (chart) {
                chart.removeSeries(series);
            }
        } catch (e) { /* ignore */ }
    }
    indicatorSeries = {};
    indicatorLastTime = {};
    squeezeMarkers = [];
    squeezeIndexOffset = 0;
    clearOverlayLines();
}


function clearOverlayLines() {
    for (const line of overlayLines) {
        try { candleSeries.removePriceLine(line); } catch(e) { /* ignore */ }
    }
    overlayLines = [];
}

function indicatorCategory(name) {
    const n = String(name || '').toLowerCase();
    if (['macd_line', 'macd_signal', 'macd_histogram', 'adx', 'rsi', 'roc', 'bandwidth'].includes(n)) return 'osc';
    if (n.includes('upper') || n.includes('lower') || n.includes('band') || n.startsWith('bb_') || n.startsWith('kc_') || n.startsWith('vwap_')) return 'volatility';
    return 'trend';
}

function indicatorAllowed(name) {
    const cat = indicatorCategory(name);
    if (cat === 'osc') return !!indicatorVisibility.osc;
    if (cat === 'volatility') return !!indicatorVisibility.volatility;
    return !!indicatorVisibility.trend;
}


function renderIndicators(indicators, mode = 'full') {
    const lineColors = {
        ema_9: '#26c6da',
        ema_21: '#42a5f5',
        ema_50: '#ffa726',
        ema_200: '#ab47bc',
        sma_20: '#42a5f5',
        vwap: '#2196F3',
        vwap_upper_2: 'rgba(33,150,243,0.3)',
        vwap_lower_2: 'rgba(33,150,243,0.3)',
        vwap_upper_3: 'rgba(33,150,243,0.15)',
        vwap_lower_3: 'rgba(33,150,243,0.15)',
        upper_band: 'rgba(255,152,0,0.3)',
        lower_band: 'rgba(255,152,0,0.3)',
        kc_upper: '#26a69a',
        kc_lower: '#26a69a',
        kc_mid: '#26a69a55',
        bb_upper: '#ef535088',
        bb_lower: '#ef535088',
        bb_mid: '#ef535044',
        linreg_slope: '#ff9800',
    };

    // Sub-chart indicators
    const subIndicators = ['macd_line', 'macd_signal', 'macd_histogram', 'adx', 'rsi', 'roc', 'bandwidth'];
    const isDelta = mode === 'delta';

    for (const [name, data] of Object.entries(indicators)) {
        if (!data || !Array.isArray(data) || data.length === 0) continue;

        // Skip non-chartable data
        if (name === 'session_levels' || name === 'squeeze' || name === 'volume') continue;
        if (!indicatorAllowed(name)) continue;

        const isSubIndicator = subIndicators.includes(name);
        const targetChart = isSubIndicator ? subChart : chart;
        if (!targetChart) continue;

        const seriesKey = isSubIndicator ? `sub_${name}` : name;
        let points = data;

        if (isDelta) {
            const lastTime = indicatorLastTime[seriesKey];
            if (typeof lastTime === 'number' && data.length > 0) {
                points = data.filter(d => d && d.time > lastTime);
            }
            if (points.length === 0) continue;
        }

        // Create series if not exists
        if (!indicatorSeries[seriesKey]) {
            if (name === 'macd_histogram') {
                indicatorSeries[seriesKey] = targetChart.addHistogramSeries({
                    color: '#26a69a',
                    priceFormat: { type: 'price', precision: 4 },
                    priceScaleId: 'macd',
                });
            } else {
                const color = lineColors[name] || '#888';
                indicatorSeries[seriesKey] = targetChart.addLineSeries({
                    color: color,
                    lineWidth: name.includes('upper') || name.includes('lower') ? 1 : 2,
                    lineStyle: name.includes('bb_') ? 2 : 0,  // dashed for BB
                    priceScaleId: isSubIndicator ? name : '',
                });
            }
        }

        if (!isDelta) {
            try {
                indicatorSeries[seriesKey].setData(data);
                const last = data[data.length - 1];
                if (last && typeof last.time === 'number') indicatorLastTime[seriesKey] = last.time;
            } catch (e) {
                // Data format issue, try converting
                const converted = data.map(d => ({
                    time: d.time,
                    value: name === 'macd_histogram' ? undefined : d.value,
                    ...(name === 'macd_histogram' ? {
                        value: d.value,
                        color: d.value >= 0 ? '#26a69a' : '#ef5350',
                    } : {}),
                }));
                try {
                    indicatorSeries[seriesKey].setData(converted);
                    const last = converted[converted.length - 1];
                    if (last && typeof last.time === 'number') indicatorLastTime[seriesKey] = last.time;
                } catch(e2) { /* skip */ }
            }
            continue;
        }

        // Delta mode: append/update only new points
        for (const d of points) {
            const pt = (name === 'macd_histogram')
                ? {
                    time: d.time,
                    value: d.value,
                    color: d.value >= 0 ? '#26a69a' : '#ef5350',
                }
                : { time: d.time, value: d.value };
            try {
                indicatorSeries[seriesKey].update(pt);
                if (typeof pt.time === 'number') indicatorLastTime[seriesKey] = pt.time;
            } catch (_) { /* skip */ }
        }
    }

    // Render squeeze dots as markers on main chart
    if (indicatorVisibility.osc && indicators.squeeze && Array.isArray(indicators.squeeze)) {
        if (isDelta) {
            for (let i = 0; i < indicators.squeeze.length; i++) {
                const idx = squeezeIndexOffset + i;
                if (!allBars[idx]) continue;
                squeezeMarkers.push({
                    time: allBars[idx].time,
                    position: 'belowBar',
                    color: indicators.squeeze[i] ? '#ef5350' : '#26a69a',
                    shape: 'circle',
                    text: '',
                });
            }
            squeezeIndexOffset += indicators.squeeze.length;
        } else {
            squeezeMarkers = [];
            squeezeIndexOffset = indicators.squeeze.length;
            const from = Math.max(1, indicators.squeeze.length - 120);
            for (let i = from; i < indicators.squeeze.length && i < allBars.length; i++) {
                squeezeMarkers.push({
                    time: allBars[i].time,
                    position: 'belowBar',
                    color: indicators.squeeze[i] ? '#ef5350' : '#26a69a',
                    shape: 'circle',
                    text: '',
                });
            }
        }
        if (squeezeMarkers.length > 120) {
            squeezeMarkers = squeezeMarkers.slice(-120);
        }
        if (squeezeMarkers.length > 0) {
            candleSeries.setMarkers(squeezeMarkers.slice(-50));
        }
    } else if (!indicatorVisibility.osc) {
        squeezeMarkers = [];
        candleSeries.setMarkers([]);
    }
}


function renderOverlays(overlays) {
    clearOverlayLines();
    if (!indicatorVisibility.overlays) return;

    if (overlays.lines) {
        for (const line of overlays.lines) {
            try {
                const pl = candleSeries.createPriceLine({
                    price: line.price,
                    color: line.color || '#666',
                    lineWidth: 1,
                    lineStyle: line.style === 'dashed' ? 2 : (line.style === 'dotted' ? 3 : 0),
                    axisLabelVisible: true,
                    title: line.label || '',
                });
                overlayLines.push(pl);
            } catch (e) { /* skip */ }
        }
    }
}


// ── UI Updates ──────────────────────────────────────────────

function updateSteps(steps) {
    const container = document.getElementById('step-list');
    if (!container) return;

    let firstPending = true;
    container.innerHTML = steps.map((step, idx) => {
        let cls = 'pending';
        if (step.completed) {
            cls = 'completed';
        } else if (firstPending) {
            cls = 'active';
            firstPending = false;
        }

        return `
            <div class="step-item ${cls}">
                <div class="step-icon">
                    ${step.completed ? '<i class="bi bi-check-lg"></i>' : `<i class="${step.icon || 'bi-circle'}"></i>`}
                </div>
                <div class="step-content">
                    <div class="step-title">${step.title || `Step ${idx + 1}`}</div>
                    <div class="step-desc">${step.description || ''}</div>
                    ${step.detail ? `<div class="step-detail">${step.detail}</div>` : ''}
                </div>
            </div>
        `;
    }).join('');
}


function updateSuggestion(suggestion) {
    const badge = document.getElementById('suggestion-badge');
    if (!badge) return;

    if (suggestion) {
        badge.className = `suggestion-badge ${suggestion.direction?.toLowerCase() || ''}`;
        badge.textContent = `Bot: ${suggestion.direction} (${suggestion.setup_type || 'Setup detected'})`;
        badge.style.display = 'block';

        // Pre-fill trade inputs
        if (suggestion.stop_loss) {
            document.getElementById('trade-sl').value = suggestion.stop_loss.toFixed(2);
        }
        if (suggestion.take_profit) {
            const dir = String(suggestion.direction || '').toUpperCase();
            if (dir === 'SELL') {
                const el = document.getElementById('trade-tp-short');
                if (el) el.value = suggestion.take_profit.toFixed(2);
            } else {
                const el = document.getElementById('trade-tp-long');
                if (el) el.value = suggestion.take_profit.toFixed(2);
            }
        }
    } else {
        badge.style.display = 'none';
    }
}


function updateBias(ctx) {
    const el = document.getElementById('bias-display');
    if (!el) return;

    const bias = ctx.bias || 'neutral';
    const strength = ctx.bias_strength || 0;
    el.className = `bias-badge ${bias}`;
    el.innerHTML = `<i class="bi bi-${bias === 'bullish' ? 'arrow-up' : bias === 'bearish' ? 'arrow-down' : 'dash'}"></i> ${bias} (${strength})`;
}


function updateOpenPosition(pos, pnl) {
    const container = document.getElementById('open-position-display');
    const idEl = document.getElementById('open-pos-id');
    const closeBtn = document.getElementById('btn-close-pos');
    const tradeButtons = document.getElementById('trade-buttons');

    if (!container) return;

    if (pos) {
        const pnlValue = pnl || 0;
        const pnlClass = pnlValue >= 0 ? 'positive' : 'negative';
        container.innerHTML = `
            <div class="open-position">
                <div class="d-flex justify-content-between align-items-center">
                    <span class="pos-direction ${pos.direction?.toLowerCase()}">${pos.direction} @ ${pos.entry_price?.toFixed(2)}</span>
                    <span class="pos-pnl ${pnlClass}">$${pnlValue.toFixed(2)}</span>
                </div>
                <div class="mt-1" style="font-size: 0.72rem; color: #94a3b8;">
                    SL: ${pos.stop_loss?.toFixed(2)} | TP: ${pos.take_profit?.toFixed(2) || 'None'} | Lots: ${pos.lot_size}
                </div>
            </div>
        `;
        container.classList.remove('d-none');
        if (idEl) idEl.dataset.tradeId = pos.id;
        if (closeBtn) closeBtn.classList.remove('d-none');
        if (tradeButtons) tradeButtons.classList.add('d-none');
    } else {
        container.innerHTML = '';
        container.classList.add('d-none');
        if (closeBtn) closeBtn.classList.add('d-none');
        if (tradeButtons) tradeButtons.classList.remove('d-none');
    }
}


function updateStats(data) {
    const setVal = (id, val, cls) => {
        const el = document.getElementById(id);
        if (el) {
            el.textContent = val;
            if (cls) el.className = `stat-value ${cls}`;
        }
    };

    const balance = Number(data.balance ?? data.current_balance ?? 0);
    const hasTotalPnl = Number.isFinite(Number(data.total_pnl));
    const pnl = hasTotalPnl ? Number(data.total_pnl) : (balance - initialBalance);
    const pnlClass = pnl >= 0 ? 'positive' : 'negative';

    setVal('stat-balance', `$${balance.toFixed(0)}`);
    setVal('stat-pnl', `${pnl >= 0 ? '+' : ''}$${pnl.toFixed(0)}`, pnlClass);

    // From session data if available
    const tradesCount = data.trades_count ?? data.total_trades;
    if (tradesCount !== undefined) {
        setVal('stat-trades', tradesCount);
    }
    if (data.wins !== undefined && tradesCount !== undefined) {
        const wr = tradesCount > 0 ? ((data.wins / tradesCount) * 100).toFixed(0) : '0';
        setVal('stat-winrate', `${wr}%`);
    }
}


function updateBarCounter() {
    const el = document.getElementById('bar-counter');
    if (el) el.textContent = `Bar ${currentBar} / ${totalBars}`;

    const fill = document.getElementById('progress-fill');
    if (fill && totalBars > 0) {
        fill.style.width = `${(currentBar / totalBars) * 100}%`;
    }
}


function addTradeToLog(trade) {
    const tbody = document.getElementById('trade-log-body');
    if (!tbody) return;

    const pnl = trade.pnl || 0;
    const pnlClass = pnl >= 0 ? 'text-success' : 'text-danger';

    const row = document.createElement('tr');
    row.innerHTML = `
        <td>${trade.direction}</td>
        <td>${trade.entry_price?.toFixed(2)}</td>
        <td>${trade.exit_price?.toFixed(2) || '-'}</td>
        <td>${trade.stop_loss?.toFixed(2) || '-'}</td>
        <td>${trade.take_profit?.toFixed(2) || '-'}</td>
        <td class="${pnlClass} fw-bold">$${pnl.toFixed(2)}</td>
        <td>${trade.r_multiple?.toFixed(1) || '-'}R</td>
        <td><small>${trade.exit_reason || '-'}</small></td>
    `;
    tbody.insertBefore(row, tbody.firstChild);
}


function showTradeResult(trade) {
    const pnl = trade.pnl || 0;
    const type = pnl >= 0 ? 'success' : 'danger';
    const emoji = pnl >= 0 ? 'WIN' : 'LOSS';
    showStatus(`${emoji}: ${trade.direction} closed @ ${trade.exit_price?.toFixed(2)} | P&L: $${pnl.toFixed(2)} (${trade.r_multiple?.toFixed(1)}R) | ${trade.exit_reason}`, type);
}


function showStatus(msg, type) {
    const el = document.getElementById('sim-status');
    if (!el) return;

    const colors = {
        success: '#16a34a',
        danger: '#dc2626',
        warning: '#d97706',
        info: '#2563eb',
    };

    el.textContent = msg;
    el.style.color = colors[type] || '#64748b';

    // Auto-clear after 5 seconds
    setTimeout(() => {
        if (el.textContent === msg) el.textContent = '';
    }, 5000);
}
