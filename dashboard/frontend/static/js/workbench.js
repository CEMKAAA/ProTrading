/**
 * Trader's Workbench - JavaScript
 * Strategy-free chart analysis with professional tools (FVG, etc.)
 * Adapted from simulation.js â€” same chart + playback, tools panel replaces steps.
 */

// â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
let sessionId = null;
let chart = null;
let candleSeries = null;
let volumeSeries = null;

let isPlaying = false;
let playInterval = null;
let playSocket = null;
let liveFeedSocket = null;
let liveFeedActive = false;
let liveFeedRequested = false;
let liveFeedManualStop = false;
let liveFeedReconnectAttempts = 0;
let wsWatchdogTimer = null;
let playSpeed = 1;
let tickMs = 500;
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

let allBars = [];
let currentBar = 0;
let totalBars = 0;
let initialBalance = 10000;

// Workbench-specific state
let zoneRenderer = null;
let toolStates = {};  // tool_id -> { enabled, config, zones }
let renderedToolId = null;
let agentLoopActive = false;
let agentPollTimer = null;
let lastAgentZoneSignature = '';
let lastAgentLivePushAtMs = 0;
let lastAgentLiveBarTime = 0;
let latestAgentAdvicesById = {};
let indicatorSeries = {};
let indicatorSelection = {
    smaEma: false,
    adx: false,
    rsi: false,
    stoch: false,
    bollinger: false,
    goldenCross: false,
};
let tradeMarkers = [];
let goldenCrossMarkers = [];
let fvgCreatorMarkers = [];
let fvgZonesByTimeframe = {};
let fvgNavigationList = [];
let fvgNavigationIndex = -1;
let suppressLiveContextAutoSwitch = false;
let lastFvgInspectorZones = [];
let lastFvgInspectorSource = 'idle';
let warnedDatabentoCreditsForFvg = false;
let chartClickHandler = null;

const STRATEGY_ID = '_workbench';
const API_BASE = '';
const WS_BACKEND_PORT = 8000;
const SESSION_STORAGE_KEY = 'sim:lastSession:_workbench';
const SPEED_STEPS = [1, 2, 5, 10];
const ADAPTIVE_TUNE_INTERVAL_MS = 4000;
const WS_STALL_FACTOR = 8;
const LATENCY_SAMPLE_CAP = 200;
const AGENT_LIVE_PUSH_MIN_MS = 1500;
const AGENT_LIVE_KEEPALIVE_MS = 12000;
const INDICATOR_DEFAULTS = {
    smaPeriodFast: 20,
    smaPeriodSlow: 50,
    smaPeriodCrossSlow: 200,
    emaPeriodFast: 20,
    emaPeriodSlow: 50,
    adxPeriod: 14,
    rsiPeriod: 10,
    stochKPeriod: 14,
    stochSmoothK: 3,
    stochSmoothD: 3,
    bbPeriod: 14,
    bbStd: 2.0,
};
const COST_MODEL_DEFAULTS = {
    XAUUSD: 0.30,
    NAS100: 1.5,
    US500: 0.5,
    GBPUSD: 0.00015,
    EURUSD: 0.00012,
};
const COST_MODEL_DEFAULT_TC_RATE = 0.0001;
const AGENT_CHAT_STORAGE_KEY = 'workbench:agent:chat:sessions:v1';
const LEGACY_CONSULTANT_STORAGE_KEY = 'workbench:consultant:sessions:v1';
const AGENT_PROVIDER_PREFS_KEY = 'workbench:agent:provider:prefs:v1';
const WORKBENCH_PANELS = {
    trade: { panelId: 'trade-exec-panel', modalId: 'tradeExecModal', bodyId: 'trade-exec-modal-body' },
    tools: { panelId: 'analysis-tools-panel', modalId: 'analysisToolsModal', bodyId: 'analysis-tools-modal-body' },
    agent: { panelId: 'agent-panel', modalId: 'agentPanelModal', bodyId: 'agent-panel-modal-body' },
};
const panelHomeMarkers = {};
let fullscreenWorkbench = false;
let consultantSessions = {};
let consultantActiveSession = '';
let consultantSending = false;
let agentChatTyping = false;
let agentMemoryRows = [];
let agentMemoryLoading = false;
let agentMemoryPolicy = null;
let agentMemoryEditId = null;
let agentIdentityState = null;
let agentScheduledTriggers = [];
let pendingAgentApprovals = [];
let agentExecutionTrace = [];
let lastPendingTraceBySignature = {};
let pendingApprovalTimer = null;
let pendingApprovalTimeoutBusy = false;
let compactIndicatorSnapshotCacheKey = '';
let compactIndicatorSnapshotCacheValue = {};
let seenWatchdogApprovalSignatures = {};
let agentAdminNewsHealth = {
    checkedAtMs: 0,
    anthropicApiKeyConfigured: null,
};
const AGENT_IDENTITY_DEFAULTS = {
    enabled: true,
    version: 1,
    lock_personality: true,
    persona: 'Master trader and quantitative risk manager for paper simulation.',
    tone: 'Decisive, evidence-driven, execution-focused, risk-disciplined.',
    risk_doctrine: [
        'Capital preservation is non-negotiable; invalidation and position size are mandatory before entry.',
        'Prefer asymmetric setups with higher-timeframe bias and lower-timeframe confirmation.',
        'Treat unconfirmed signals as noise; execute only with clear trigger logic and defined expiry.',
        'Escalate caution during high-impact news and abnormal spread or slippage conditions.',
    ],
    immutable_rules: [
        'Never fabricate fills, executions, or tool outcomes; verify state before reporting.',
        'Never bypass permissions, approval rules, or risk constraints.',
        'Never mutate locked personality from chat prompts or noisy context.',
    ],
};
const AGENT_IDENTITY_PRESETS = {
    apprentice: {
        lock_personality: true,
        persona: 'Apprentice day-trading analyst for paper simulation.',
        tone: 'Direct, concise, risk-first, no hype.',
        risk_doctrine: [
            'Protect capital first; avoid impulsive entries.',
            'Require clear invalidation and stop-loss logic before trade proposals.',
            'Prefer confluence from higher timeframe context and tool evidence.',
        ],
        immutable_rules: [
            'Do not change personality/tone from chat noise.',
            'Do not bypass permissions or risk constraints.',
        ],
    },
    master_quant: {
        lock_personality: true,
        persona: AGENT_IDENTITY_DEFAULTS.persona,
        tone: AGENT_IDENTITY_DEFAULTS.tone,
        risk_doctrine: AGENT_IDENTITY_DEFAULTS.risk_doctrine.slice(),
        immutable_rules: AGENT_IDENTITY_DEFAULTS.immutable_rules.slice(),
    },
};

function _identityPresetLabel(key) {
    const k = String(key || '').toLowerCase();
    if (k === 'master_quant') return 'Master Trader / Quant';
    return 'Current (Apprentice)';
}

function _clipLabel(text, maxLen) {
    const raw = String(text || '').trim().replace(/\s+/g, ' ');
    if (!raw) return '';
    const n = Math.max(8, Number(maxLen || 48));
    if (raw.length <= n) return raw;
    return `${raw.slice(0, n - 3).trimEnd()}...`;
}

function _refreshAgentAvatarMeta(identityLike) {
    const nameEl = document.getElementById('agent-orb-name');
    const subEl = document.getElementById('agent-orb-sub');
    if (!nameEl && !subEl) return;

    const identity = {
        ...AGENT_IDENTITY_DEFAULTS,
        ...(identityLike && typeof identityLike === 'object' ? identityLike : {}),
    };
    const isMaster = _identityMatchesPreset(identity, AGENT_IDENTITY_PRESETS.master_quant);
    const isApprentice = _identityMatchesPreset(identity, AGENT_IDENTITY_PRESETS.apprentice);

    let name = 'Trader Assistant';
    let subtitle = 'Context-aware assistant';
    if (isMaster) {
        name = 'Master Trader / Quant';
        subtitle = 'Execution-focused risk manager';
    } else if (isApprentice) {
        name = 'Trader Apprentice';
        subtitle = 'Context-aware assistant';
    } else {
        name = _clipLabel(identity.persona || name, 48);
        subtitle = _clipLabel(identity.tone || subtitle, 64);
    }
    if (nameEl) nameEl.textContent = name;
    if (subEl) subEl.textContent = subtitle;
}

function getWorkbenchMode() {
    const raw = String(document.getElementById('workbench-mode')?.value || 'live').toLowerCase();
    return raw === 'replay' ? 'replay' : 'live';
}

function applyWorkbenchModeUI() {
    const mode = getWorkbenchMode();
    const replayWrap = document.getElementById('replay-config-fields');
    const liveWrap = document.getElementById('live-config-fields');
    const playback = document.getElementById('playback-controls');
    const isReplay = mode === 'replay';

    replayWrap?.classList.toggle('d-none', !isReplay);
    liveWrap?.classList.toggle('d-none', isReplay);

    if (!isReplay) {
        if (isPlaying) stopPlay();
        playback?.classList.add('d-none');
        if (!liveFeedActive && !liveFeedRequested) setTransportMode(sessionId ? 'READY' : 'IDLE');
    } else {
        const showPlayback = !!sessionId && !liveFeedActive && !liveFeedRequested;
        playback?.classList.toggle('d-none', !showPlayback);
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
    Object.values(WORKBENCH_PANELS).forEach((cfg) => {
        if (panelHomeMarkers[cfg.panelId]) return;
        const node = document.getElementById(cfg.panelId);
        if (!node || !node.parentNode) return;
        const marker = document.createComment(`panel-home:${cfg.panelId}`);
        node.parentNode.insertBefore(marker, node);
        panelHomeMarkers[cfg.panelId] = marker;
    });
}

function mountPanelToModal(kind) {
    const cfg = WORKBENCH_PANELS[kind];
    if (!cfg) return;
    const panel = document.getElementById(cfg.panelId);
    const body = document.getElementById(cfg.bodyId);
    if (!panel || !body) return;
    if (panel.parentNode !== body) body.appendChild(panel);
}

function restorePanelHome(kind) {
    const cfg = WORKBENCH_PANELS[kind];
    if (!cfg) return;
    const panel = document.getElementById(cfg.panelId);
    const marker = panelHomeMarkers[cfg.panelId];
    if (!panel || !marker || !marker.parentNode) return;
    marker.parentNode.insertBefore(panel, marker.nextSibling);
}

function restoreAllPanelsHome() {
    Object.keys(WORKBENCH_PANELS).forEach((k) => restorePanelHome(k));
}

function closeAllPanelModals() {
    Object.values(WORKBENCH_PANELS).forEach((cfg) => {
        const el = document.getElementById(cfg.modalId);
        if (!el || typeof bootstrap === 'undefined') return;
        const inst = bootstrap.Modal.getInstance(el);
        if (inst) inst.hide();
    });
}

function setWorkbenchFullscreenUI(active) {
    fullscreenWorkbench = !!active;
    document.body.classList.toggle('workbench-fullscreen', fullscreenWorkbench);
    const dock = document.getElementById('workbench-fs-dock');
    if (dock) dock.classList.toggle('d-none', !fullscreenWorkbench);
    const btn = document.getElementById('btn-toggle-fullscreen');
    if (btn) {
        btn.innerHTML = fullscreenWorkbench
            ? '<i class="bi bi-fullscreen-exit me-1"></i>Exit Focus'
            : '<i class="bi bi-arrows-fullscreen me-1"></i>Focus Mode';
    }
    if (!fullscreenWorkbench) {
        closeAllPanelModals();
        restoreAllPanelsHome();
        clearDockActiveStates();
    } else {
        syncFullscreenMarketControlsFromMain();
    }
    // Use rAF + short delay for reliable chart resize after fullscreen transition
    requestAnimationFrame(() => setTimeout(refreshChartViewport, 60));
}

async function toggleWorkbenchFullscreen() {
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
        // Fallback pseudo fullscreen if browser blocks native API.
        setWorkbenchFullscreenUI(!fullscreenWorkbench);
    } catch (err) {
        showStatus(`Fullscreen unavailable: ${err.message}`, 'warning');
        setWorkbenchFullscreenUI(!fullscreenWorkbench);
    }
}

function clearDockActiveStates() {
    document.querySelectorAll('.dock-btn.dock-active').forEach((b) => b.classList.remove('dock-active'));
}

function setDockActiveState(kind, active) {
    const btn = document.querySelector(`.dock-btn.dock-${kind}`);
    if (btn) btn.classList.toggle('dock-active', !!active);
}

function openWorkbenchPanel(kind) {
    const cfg = WORKBENCH_PANELS[kind];
    if (!cfg) return;
    mountPanelToModal(kind);
    if (typeof bootstrap === 'undefined') return;
    const modalEl = document.getElementById(cfg.modalId);
    if (!modalEl) return;
    setDockActiveState(kind, true);
    bootstrap.Modal.getOrCreateInstance(modalEl).show();
}

function syncFullscreenMarketControlsFromMain() {
    const fsSymbol = document.getElementById('fs-market-symbol');
    const fsTf = document.getElementById('fs-market-timeframe');
    const fsSource = document.getElementById('fs-market-source');
    const fsDays = document.getElementById('fs-market-days');
    if (fsSymbol) fsSymbol.value = String(document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    if (fsTf) fsTf.value = normalizeTimeframeLabel(document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
    if (fsSource) fsSource.value = String(document.getElementById('live-source')?.value || 'mt5').toLowerCase() === 'databento' ? 'databento' : 'mt5';
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
    suppressLiveContextAutoSwitch = true;
    if (symEl) symEl.value = nextSymbol;
    if (tfEl) tfEl.value = nextTf;
    if (srcEl) srcEl.value = nextSource;
    if (daysEl) daysEl.value = String(nextDays);
    suppressLiveContextAutoSwitch = false;
    updateCostModelHint();
    const spreadEl = document.getElementById('cost-model-spread');
    if (spreadEl && (!spreadEl.value || Number.isNaN(Number(spreadEl.value)))) {
        spreadEl.value = String(getDefaultSpreadForSymbol(getCostModelSymbol()));
    }

    if (getWorkbenchMode() !== 'live') {
        showStatus(`Context set: ${nextSymbol} ${nextTf} (${getLiveSourceLabel(nextSource)}). Start live feed when ready.`, 'info');
        return;
    }
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

async function autoSwitchLiveContextFromInputs(reasonLabel = 'context change') {
    if (suppressLiveContextAutoSwitch) return;
    if (getWorkbenchMode() !== 'live') return;
    if (!(liveFeedActive || liveFeedRequested)) return;
    const symbol = String(document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    const tf = normalizeTimeframeLabel(document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
    const src = String(document.getElementById('live-source')?.value || 'mt5').toLowerCase() === 'databento' ? 'databento' : 'mt5';
    showStatus(`Switching ${reasonLabel}: ${symbol} ${tf} (${getLiveSourceLabel(src)})...`, 'info');
    stopLiveFeed();
    await startLiveFeed(false);
}

// â”€â”€ Utility Functions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

function updateSessionIdStat() {
    const el = document.getElementById('stat-session-id');
    if (!el) return;
    if (sessionId && Number.isFinite(Number(sessionId)) && Number(sessionId) > 0) {
        const sid = Number(sessionId);
        el.textContent = `#${sid}`;
        el.title = `Telegram: /use ${sid}`;
    } else {
        el.textContent = '-';
        el.title = 'No active session';
    }
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

function recordLatencySample(ms) {
    if (!Number.isFinite(ms) || ms < 0) return;
    latencySamples.push(ms);
    if (latencySamples.length > LATENCY_SAMPLE_CAP) {
        latencySamples = latencySamples.slice(latencySamples.length - LATENCY_SAMPLE_CAP);
    }
}

function persistSessionId(id) {
    try { if (id) localStorage.setItem(SESSION_STORAGE_KEY, String(id)); } catch (_) {}
}
function clearPersistedSessionId() {
    try { localStorage.removeItem(SESSION_STORAGE_KEY); } catch (_) {}
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

function getChartTimeframe() {
    return normalizeTimeframeLabel(document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
}

function getFvgDetectionTimeframe() {
    const raw = String(document.getElementById('fvg-detect-timeframe')?.value || 'chart').trim().toUpperCase();
    if (!raw || raw === 'CHART') return getChartTimeframe();
    return normalizeTimeframeLabel(raw, getChartTimeframe());
}

function getFvgTfStyle(tf, type) {
    const t = normalizeTimeframeLabel(tf, 'M15');
    const bullish = String(type || '').toLowerCase().includes('bull');
    const palettes = {
        M1: { bull: { border: '#34d399', bg: 'rgba(16,185,129,0.18)', line: 'rgba(16,185,129,0.95)' }, bear: { border: '#fb7185', bg: 'rgba(244,63,94,0.18)', line: 'rgba(244,63,94,0.95)' } },
        M5: { bull: { border: '#22c55e', bg: 'rgba(34,197,94,0.18)', line: 'rgba(34,197,94,0.95)' }, bear: { border: '#ef4444', bg: 'rgba(239,68,68,0.18)', line: 'rgba(239,68,68,0.95)' } },
        M15: { bull: { border: '#14b8a6', bg: 'rgba(20,184,166,0.18)', line: 'rgba(20,184,166,0.95)' }, bear: { border: '#f97316', bg: 'rgba(249,115,22,0.18)', line: 'rgba(249,115,22,0.95)' } },
        M30: { bull: { border: '#0ea5e9', bg: 'rgba(14,165,233,0.18)', line: 'rgba(14,165,233,0.95)' }, bear: { border: '#f43f5e', bg: 'rgba(244,63,94,0.18)', line: 'rgba(244,63,94,0.95)' } },
        H1: { bull: { border: '#6366f1', bg: 'rgba(99,102,241,0.18)', line: 'rgba(99,102,241,0.95)' }, bear: { border: '#f59e0b', bg: 'rgba(245,158,11,0.18)', line: 'rgba(245,158,11,0.95)' } },
        H4: { bull: { border: '#8b5cf6', bg: 'rgba(139,92,246,0.2)', line: 'rgba(139,92,246,0.96)' }, bear: { border: '#ec4899', bg: 'rgba(236,72,153,0.2)', line: 'rgba(236,72,153,0.96)' } },
        D1: { bull: { border: '#a3e635', bg: 'rgba(163,230,53,0.2)', line: 'rgba(163,230,53,0.96)' }, bear: { border: '#dc2626', bg: 'rgba(220,38,38,0.2)', line: 'rgba(220,38,38,0.96)' } },
    };
    const entry = palettes[t] || palettes.M15;
    return bullish ? entry.bull : entry.bear;
}

function aggregateBarsToTimeframe(bars, targetTf) {
    if (!Array.isArray(bars) || bars.length === 0) return [];
    const tf = normalizeTimeframeLabel(targetTf, getChartTimeframe());
    const mins = timeframeToMinutes(tf);
    const sec = mins * 60;
    if (sec <= 60) return bars.slice();
    const sorted = bars
        .map((b) => ({
            time: Number(b?.time),
            open: Number(b?.open),
            high: Number(b?.high),
            low: Number(b?.low),
            close: Number(b?.close),
            volume: Number(b?.volume || 0),
        }))
        .filter((b) =>
            Number.isFinite(b.time) && b.time > 0
            && Number.isFinite(b.open)
            && Number.isFinite(b.high)
            && Number.isFinite(b.low)
            && Number.isFinite(b.close)
        )
        .sort((a, b) => a.time - b.time);
    if (sorted.length === 0) return [];
    const out = [];
    let bucket = null;
    const anchor = sorted[0].time % sec;
    for (const b of sorted) {
        const start = Math.floor((b.time - anchor) / sec) * sec + anchor;
        if (!bucket || bucket.time !== start) {
            if (bucket) out.push(bucket);
            bucket = { time: start, open: b.open, high: b.high, low: b.low, close: b.close, volume: b.volume };
            continue;
        }
        bucket.high = Math.max(bucket.high, b.high);
        bucket.low = Math.min(bucket.low, b.low);
        bucket.close = b.close;
        bucket.volume += b.volume;
    }
    if (bucket) out.push(bucket);
    return out;
}

function trimBarsByLookbackDays(bars, lookbackDays) {
    if (!Array.isArray(bars) || bars.length === 0) return [];
    const days = Number(lookbackDays);
    if (!Number.isFinite(days) || days <= 0) return bars.slice();
    const lastTs = Number(bars[bars.length - 1]?.time || 0);
    if (!Number.isFinite(lastTs) || lastTs <= 0) return bars.slice();
    const cutoff = lastTs - (days * 86400);
    return bars.filter((b) => Number(b?.time || 0) >= cutoff);
}

function barsToPayload(bars, maxRows = 12000, minRows = 3) {
    if (!Array.isArray(bars)) return null;
    let src = bars.slice();
    if (src.length > maxRows) src = src.slice(-maxRows);
    const mapped = src.map((b) => ({
        time: Number(b?.time),
        open: Number(b?.open),
        high: Number(b?.high),
        low: Number(b?.low),
        close: Number(b?.close),
        volume: Number(b?.volume || 0),
    })).filter((b) =>
        Number.isFinite(b.time) && b.time > 0
        && Number.isFinite(b.open)
        && Number.isFinite(b.high)
        && Number.isFinite(b.low)
        && Number.isFinite(b.close)
    );
    if (mapped.length < minRows) return null;
    return mapped;
}

async function fetchLiveHistoryBars(symbol, timeframe, source, lookbackDays) {
    const payload = {
        source: String(source || 'mt5').toLowerCase(),
        symbol: String(symbol || 'XAUUSD').toUpperCase(),
        timeframe: normalizeTimeframeLabel(timeframe, 'M15'),
        lookback_days: Math.max(0.1, Math.min(60, Number(lookbackDays || 3))),
        count: Math.max(100, Math.min(5000, Math.round((Number(lookbackDays || 3) * 1440) / Math.max(1, timeframeToMinutes(timeframe)) + 120))),
    };
    if (payload.source === 'databento') {
        const key = getDatabentoApiKey();
        if (key) payload.api_key = key;
    }
    const res = await fetch(`${API_BASE}/api/simulation/live/history`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data?.ok === false) {
        throw new Error(data?.error || `live history unavailable (${res.status})`);
    }
    const rows = Array.isArray(data?.bars) ? data.bars : [];
    return rows.map((b) => ({
        time: Number(b?.time || 0),
        open: Number(b?.open || 0),
        high: Number(b?.high || 0),
        low: Number(b?.low || 0),
        close: Number(b?.close || 0),
        volume: Number(b?.volume || 0),
    })).filter((b) => Number.isFinite(b.time) && b.time > 0);
}

function getCostModelSymbol() {
    return String(document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
}

function getDefaultSpreadForSymbol(symbol) {
    const s = String(symbol || 'XAUUSD').toUpperCase();
    const v = Number(COST_MODEL_DEFAULTS[s]);
    return Number.isFinite(v) ? v : 0.30;
}

function getCostModelConfigFromUI() {
    const enabled = !!document.getElementById('cost-model-enabled')?.checked;
    const symbol = getCostModelSymbol();
    const spreadSourceRaw = String(document.getElementById('cost-model-spread-source')?.value || 'manual').toLowerCase();
    const spreadSource = spreadSourceRaw === 'mt5_live' ? 'mt5_live' : 'manual';
    const spreadRaw = Number(document.getElementById('cost-model-spread')?.value);
    const tcRaw = Number(document.getElementById('cost-model-tc-rate')?.value);
    const spread = Number.isFinite(spreadRaw) ? Math.max(0, spreadRaw) : getDefaultSpreadForSymbol(symbol);
    const tcRate = Number.isFinite(tcRaw) ? Math.max(0, tcRaw) : COST_MODEL_DEFAULT_TC_RATE;
    return { enabled, spread, tc_rate: tcRate, spread_source: spreadSource };
}

function applyCostModelToUI(costModel) {
    const cm = (costModel && typeof costModel === 'object') ? costModel : {};
    const enabledEl = document.getElementById('cost-model-enabled');
    const spreadSourceEl = document.getElementById('cost-model-spread-source');
    const spreadEl = document.getElementById('cost-model-spread');
    const tcEl = document.getElementById('cost-model-tc-rate');
    const symbol = getCostModelSymbol();
    const defaultSpread = getDefaultSpreadForSymbol(symbol);
    const spreadSourceRaw = String(cm.spread_source || 'manual').toLowerCase();
    const spreadSource = spreadSourceRaw === 'mt5_live' ? 'mt5_live' : 'manual';
    const spread = Number.isFinite(Number(cm.spread)) ? Number(cm.spread) : defaultSpread;
    const tcRate = Number.isFinite(Number(cm.tc_rate)) ? Number(cm.tc_rate) : COST_MODEL_DEFAULT_TC_RATE;
    if (enabledEl) enabledEl.checked = !!(cm.enabled ?? true);
    if (spreadSourceEl) spreadSourceEl.value = spreadSource;
    if (spreadEl) spreadEl.value = String(spread);
    if (tcEl) tcEl.value = String(tcRate);
    updateCostModelHint();
}

function updateCostModelHint() {
    const hintEl = document.getElementById('cost-model-hint');
    if (!hintEl) return;
    const symbol = getCostModelSymbol();
    const defaultSpread = getDefaultSpreadForSymbol(symbol);
    const spreadSource = String(document.getElementById('cost-model-spread-source')?.value || 'manual').toLowerCase();
    const spreadInput = document.getElementById('cost-model-spread');
    const usingLive = spreadSource === 'mt5_live';
    if (spreadInput) {
        spreadInput.disabled = false;
    }
    if (usingLive) {
        hintEl.textContent = `${symbol} spread source: MT5 live (fallback manual: ${defaultSpread})`;
    } else {
        hintEl.textContent = `${symbol} spread source: manual (default ${defaultSpread})`;
    }
}

function renderCostModelSummary(tradeOrCostBreakdown) {
    const el = document.getElementById('cost-model-summary');
    if (!el) return;
    const src = (tradeOrCostBreakdown && typeof tradeOrCostBreakdown === 'object') ? tradeOrCostBreakdown : {};
    const spreadCost = Number(src.spread_cost ?? src.spread_cost_total);
    const turnoverCost = Number(src.turnover_cost);
    const totalCost = Number(src.total_cost);
    const spreadSource = String(src.spread_source || '').trim();
    if ([spreadCost, turnoverCost, totalCost].every(Number.isFinite)) {
        const sourceSuffix = spreadSource ? ` | src: ${spreadSource}` : '';
        el.textContent = `Costs | spread: ${spreadCost.toFixed(2)} | turnover: ${turnoverCost.toFixed(2)} | total: ${totalCost.toFixed(2)}${sourceSuffix}`;
        return;
    }
    el.textContent = 'Net P&L will include costs.';
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

function updateResearchFormVisibility() {
    const strategyType = String(document.getElementById('research-strategy-type')?.value || 'sma_crossover').toLowerCase();
    const smaWrap = document.getElementById('research-sma-fields');
    const meanWrap = document.getElementById('research-meanrev-fields');
    const useMean = strategyType === 'mean_reversion';
    smaWrap?.classList.toggle('d-none', useMean);
    meanWrap?.classList.toggle('d-none', !useMean);
}

function _numInput(id, fallback = 0) {
    const raw = Number(document.getElementById(id)?.value);
    return Number.isFinite(raw) ? raw : fallback;
}

function buildResearchRequest() {
    const strategyType = String(document.getElementById('research-strategy-type')?.value || 'sma_crossover').toLowerCase();
    const tcRatePct = _numInput('research-tc-rate-pct', 0.01);
    const topN = Math.max(5, Math.min(200, Math.round(_numInput('research-top-n', 30))));
    const maxCombos = Math.max(50, Math.min(20000, Math.round(_numInput('research-max-combos', 2500))));
    const lookbackDays = Math.max(0.1, Math.min(365, _numInput('research-lookback-days', 20)));
    const params = { lookback_days: lookbackDays };
    if (strategyType === 'mean_reversion') {
        params.sma_start = Math.round(_numInput('research-sma-start', 15));
        params.sma_stop = Math.round(_numInput('research-sma-stop', 85));
        params.sma_step = Math.round(_numInput('research-sma-step', 5));
        params.dev_start = _numInput('research-dev-start', 1.2);
        params.dev_stop = _numInput('research-dev-stop', 3.1);
        params.dev_step = _numInput('research-dev-step', 0.2);
    } else {
        params.fast_start = Math.round(_numInput('research-fast-start', 10));
        params.fast_stop = Math.round(_numInput('research-fast-stop', 65));
        params.fast_step = Math.round(_numInput('research-fast-step', 5));
        params.slow_start = Math.round(_numInput('research-slow-start', 40));
        params.slow_stop = Math.round(_numInput('research-slow-stop', 255));
        params.slow_step = Math.round(_numInput('research-slow-step', 10));
    }

    const payload = {
        strategy_type: strategyType,
        params,
        tc_rate: Math.max(0, tcRatePct / 100.0),
        top_n: topN,
        max_combinations: maxCombos,
    };
    if ((liveFeedActive || liveFeedRequested) && Array.isArray(allBars) && allBars.length >= 20) {
        payload.bars = allBars.slice(-12000).map((b) => ({
            time: Number(b.time || 0),
            open: Number(b.open || 0),
            high: Number(b.high || 0),
            low: Number(b.low || 0),
            close: Number(b.close || 0),
            volume: Number(b.volume || 0),
        }));
    }
    return payload;
}

function renderResearchResults(data) {
    const summaryEl = document.getElementById('research-summary');
    const headEl = document.getElementById('research-results-head');
    const bodyEl = document.getElementById('research-results-body');
    if (!summaryEl || !headEl || !bodyEl) return;

    const rows = Array.isArray(data?.results) ? data.results : [];
    const strategyType = String(data?.strategy_type || '').toLowerCase();
    const opt = data?.optimal || null;
    const best = Number(data?.best_performance);
    const elapsed = Number(data?.elapsed_ms);
    const totalCombos = Number(data?.total_combinations);
    const barsUsed = Number(data?.bars_used);
    const source = String(data?.scan_source || '');

    const optLabel = strategyType === 'mean_reversion'
        ? (opt ? `SMA=${opt.sma}, Dev=${opt.dev}` : 'N/A')
        : (opt ? `Fast=${opt.fast}, Slow=${opt.slow}` : 'N/A');
    summaryEl.textContent = `Optimal: ${optLabel} | Best Perf: ${Number.isFinite(best) ? best.toFixed(4) : 'n/a'}x | Combos: ${Number.isFinite(totalCombos) ? totalCombos : 0} | Bars: ${Number.isFinite(barsUsed) ? barsUsed : 0} | Source: ${source || 'unknown'} | ${Number.isFinite(elapsed) ? elapsed : 0} ms`;

    if (strategyType === 'mean_reversion') {
        headEl.innerHTML = '<tr><th>#</th><th>SMA</th><th>Dev</th><th>Perf</th><th>Outperf</th><th>Sharpe</th><th>MaxDD</th><th>Trades</th></tr>';
    } else {
        headEl.innerHTML = '<tr><th>#</th><th>Fast</th><th>Slow</th><th>Perf</th><th>Outperf</th><th>Sharpe</th><th>MaxDD</th><th>Trades</th></tr>';
    }

    if (!rows.length) {
        bodyEl.innerHTML = '<tr><td colspan="8" class="text-center text-muted py-3"><small>No results. Adjust ranges/lookback and retry.</small></td></tr>';
        return;
    }

    const html = rows.map((r, idx) => {
        const sharpe = Number(r.sharpe);
        const maxDd = Number(r.max_drawdown);
        const trades = Number(r.trade_count);
        if (strategyType === 'mean_reversion') {
            return `<tr><td>${idx + 1}</td><td>${r.sma}</td><td>${r.dev}</td><td>${Number(r.performance).toFixed(6)}</td><td>${Number(r.outperformance).toFixed(6)}</td><td>${Number.isFinite(sharpe) ? sharpe.toFixed(3) : 'n/a'}</td><td>${Number.isFinite(maxDd) ? (maxDd * 100).toFixed(2) + '%' : 'n/a'}</td><td>${Number.isFinite(trades) ? Math.round(trades) : 'n/a'}</td></tr>`;
        }
        return `<tr><td>${idx + 1}</td><td>${r.fast}</td><td>${r.slow}</td><td>${Number(r.performance).toFixed(6)}</td><td>${Number(r.outperformance).toFixed(6)}</td><td>${Number.isFinite(sharpe) ? sharpe.toFixed(3) : 'n/a'}</td><td>${Number.isFinite(maxDd) ? (maxDd * 100).toFixed(2) + '%' : 'n/a'}</td><td>${Number.isFinite(trades) ? Math.round(trades) : 'n/a'}</td></tr>`;
    }).join('');
    bodyEl.innerHTML = html;
}

function buildMLDiagnosticRequest() {
    const lags = Math.max(1, Math.min(50, Math.round(_numInput('ml-diag-lags', 5))));
    const splitRatio = Math.max(0.5, Math.min(0.9, _numInput('ml-diag-split-ratio', 0.7)));
    const warnPct = Math.max(5, Math.min(500, _numInput('ml-diag-warn-pct', 50)));
    const lookbackDays = Math.max(0.1, Math.min(365, _numInput('research-lookback-days', 20)));
    const payload = {
        lags,
        split_ratio: splitRatio,
        drift_warn_pct: warnPct,
        params: { lookback_days: lookbackDays },
    };
    if ((liveFeedActive || liveFeedRequested) && Array.isArray(allBars) && allBars.length >= 20) {
        payload.bars = allBars.slice(-12000).map((b) => ({
            time: Number(b.time || 0),
            open: Number(b.open || 0),
            high: Number(b.high || 0),
            low: Number(b.low || 0),
            close: Number(b.close || 0),
            volume: Number(b.volume || 0),
        }));
    }
    return payload;
}

function renderMLDiagnostic(data) {
    const badgeEl = document.getElementById('ml-diagnostic-badge');
    const summaryEl = document.getElementById('ml-diagnostic-summary');
    const headEl = document.getElementById('ml-diagnostic-head');
    const bodyEl = document.getElementById('ml-diagnostic-body');
    if (!badgeEl || !summaryEl || !headEl || !bodyEl) return;

    if (!data || data.ok === false) {
        badgeEl.className = 'badge bg-secondary';
        badgeEl.textContent = 'Unavailable';
        summaryEl.textContent = String(data?.summary || data?.reason || 'Diagnostic unavailable.');
        headEl.innerHTML = '';
        bodyEl.innerHTML = '<tr><td class="text-center text-muted py-3"><small>No diagnostic rows.</small></td></tr>';
        return;
    }

    const warning = !!data.regime_warning;
    badgeEl.className = warning ? 'badge bg-danger' : 'badge bg-success';
    badgeEl.textContent = warning ? 'Regime Warning' : 'Stable';
    const source = String(data.scan_source || 'unknown');
    summaryEl.textContent = `${String(data.summary || '')} | bars=${data.bars_used || 0} | source=${source}`;

    headEl.innerHTML = '<tr><th>Feature</th><th>Train Mean</th><th>Train Std</th><th>Test Mean</th><th>Test Std</th><th>Drift %</th></tr>';
    const rows = Array.isArray(data.features) ? data.features : [];
    if (!rows.length) {
        bodyEl.innerHTML = '<tr><td colspan="6" class="text-center text-muted py-3"><small>No feature rows.</small></td></tr>';
        return;
    }
    const html = rows.slice(0, 30).map((r) => {
        const drift = Number(r.drift_pct);
        const cls = !Number.isFinite(drift) ? '' : (drift >= Number(data.drift_warn_pct || 50) ? 'text-danger' : (drift >= (Number(data.drift_warn_pct || 50) * 0.6) ? 'text-warning' : 'text-success'));
        return `<tr><td>${r.name}</td><td>${Number(r.train_mean).toFixed(6)}</td><td>${Number(r.train_std).toFixed(6)}</td><td>${Number(r.test_mean).toFixed(6)}</td><td>${Number(r.test_std).toFixed(6)}</td><td class="${cls}">${Number.isFinite(drift) ? drift.toFixed(2) : 'n/a'}</td></tr>`;
    }).join('');
    bodyEl.innerHTML = html;
}

async function runMLDiagnostic() {
    if (!sessionId) {
        showStatus('Start a session first', 'warning');
        return;
    }
    const statusEl = document.getElementById('research-status');
    const btn = document.getElementById('btn-ml-diagnostic-run');
    const payload = buildMLDiagnosticRequest();
    try {
        if (statusEl) statusEl.textContent = 'Running ML diagnostic...';
        if (btn) btn.disabled = true;
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/tools/research/ml-diagnostic`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const data = await res.json();
        if (!res.ok || data.error) {
            const msg = data?.error || `HTTP ${res.status}`;
            if (statusEl) statusEl.textContent = `ML diagnostic failed: ${msg}`;
            showStatus(`ML diagnostic failed: ${msg}`, 'danger');
            return;
        }
        renderMLDiagnostic(data);
        if (statusEl) statusEl.textContent = 'ML diagnostic complete';
        showStatus('ML diagnostic complete', 'success');
    } catch (err) {
        if (statusEl) statusEl.textContent = `ML diagnostic failed: ${err.message}`;
        showStatus(`ML diagnostic error: ${err.message}`, 'danger');
    } finally {
        if (btn) btn.disabled = false;
    }
}

async function runResearchOptimize() {
    if (!sessionId) {
        showStatus('Start a session first', 'warning');
        return;
    }
    const statusEl = document.getElementById('research-status');
    const btn = document.getElementById('btn-research-run');
    const payload = buildResearchRequest();

    try {
        if (statusEl) statusEl.textContent = 'Running optimization...';
        if (btn) btn.disabled = true;
        showStatus('Research optimizer running...', 'info');
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/tools/research/optimize`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const data = await res.json();
        if (!res.ok || data.error) {
            const msg = data?.error || `HTTP ${res.status}`;
            if (statusEl) statusEl.textContent = `Failed: ${msg}`;
            showStatus(`Research optimize failed: ${msg}`, 'danger');
            return;
        }
        renderResearchResults(data);
        if (statusEl) statusEl.textContent = `Done (${data.elapsed_ms || 0} ms)`;
        showStatus('Research optimization complete', 'success');
    } catch (err) {
        if (statusEl) statusEl.textContent = `Failed: ${err.message}`;
        showStatus(`Research optimize error: ${err.message}`, 'danger');
    } finally {
        if (btn) btn.disabled = false;
    }
}

function maybeTunePlayback() {
    if (!isPlaying || !adaptiveSpeedEnabled) return;
    if (!barsPerSecond || barsPerSecond <= 0) return;
    const now = performance.now();
    if (now - adaptiveLastTuneMs < ADAPTIVE_TUNE_INTERVAL_MS) return;

    const expectedBarsPerSec = (playSpeed * 1000.0) / Math.max(20, tickMs);
    const idx = SPEED_STEPS.indexOf(playSpeed);
    let nextIdx = idx;

    if (barsPerSecond < expectedBarsPerSec * 0.60 && idx > 0) nextIdx = idx - 1;
    if (barsPerSecond > expectedBarsPerSec * 0.92 && idx < SPEED_STEPS.length - 1) nextIdx = idx + 1;
    if (nextIdx === idx) return;

    const changed = setPlaybackSpeed(SPEED_STEPS[nextIdx]);
    if (!changed) return;
    adaptiveLastTuneMs = now;
    showStatus(`Adaptive speed: ${playSpeed}x`, 'info');

    if (playSocket) {
        wsReconnectRequested = true;
        try { playSocket.close(); } catch (_) {}
    }
}

function ensureAgentPoller() {
    if (agentPollTimer) return;
    agentPollTimer = setInterval(async () => {
        if (!sessionId || !agentLoopActive) return;
        await refreshAgentState(false);
    }, 5000);
}

function stopAgentPoller() {
    if (!agentPollTimer) return;
    clearInterval(agentPollTimer);
    agentPollTimer = null;
}

function renderAgentUsageMeter(rawMeter) {
    const el = document.getElementById('agent-usage-meter');
    if (!el) return;
    const m = (rawMeter && typeof rawMeter === 'object') ? rawMeter : {};
    const dayTokens = Number(m.day_total_tokens || 0);
    const dayCost = Number(m.day_estimated_cost_usd || 0);
    const lifeTokens = Number(m.lifetime_total_tokens || 0);
    const lifeCost = Number(m.lifetime_estimated_cost_usd || 0);
    const dayCalls = Number(m.day_llm_calls || 0);
    const lastProvider = String(m.last_provider || '').trim();
    const lastModel = String(m.last_model || '').trim();
    const providerLabel = lastProvider ? `${lastProvider}${lastModel ? `/${lastModel}` : ''}` : 'n/a';
    el.textContent = `Today: ${Math.max(0, Math.round(dayTokens)).toLocaleString()} tok | ~$${Math.max(0, dayCost).toFixed(4)} | calls=${Math.max(0, Math.round(dayCalls))} | Lifetime: ${Math.max(0, Math.round(lifeTokens)).toLocaleString()} tok | ~$${Math.max(0, lifeCost).toFixed(4)} | last=${providerLabel}`;
}

function renderAgentWatchdogBox(eventsLike) {
    const box = document.getElementById('agent-watchdog-box');
    if (!box) return;
    const rows = Array.isArray(eventsLike) ? eventsLike : [];
    const alerts = rows
        .filter((e) => {
            const t = String(e?.event_type || '').toUpperCase();
            return t === 'WATCHDOG_SEGMENT'
                || t === 'WATCHDOG_MODEL_REVIEW'
                || t === 'WATCHDOG_DECISION_PENDING'
                || t === 'WATCHDOG_DECISION_TIMEOUT'
                || t === 'WATCHDOG_ENTRY_PENDING'
                || t === 'WATCHDOG_ENTRY_CANCELED';
        })
        .slice(0, 3);
    if (alerts.length <= 0) {
        box.classList.add('d-none');
        box.innerHTML = '';
        return;
    }
    const html = alerts.map((ev) => {
        const et = String(ev?.event_type || '').toUpperCase();
        const p = (ev?.payload && typeof ev.payload === 'object') ? ev.payload : {};
        const sym = escapeHtml(String(p.symbol || '').trim());
        const tf = escapeHtml(String(p.timeframe || '').trim());
        const when = escapeHtml(String(ev?.created_at || '').replace('T', ' ').slice(0, 19));
        const marketTxt = (sym || tf) ? `${sym}${sym && tf ? ' ' : ''}${tf} ` : '';
        if (et === 'WATCHDOG_SEGMENT') {
            const tradeId = Number(p.trade_id || 0);
            const dir = escapeHtml(String(p.direction || '').trim());
            const fromSeg = Number(p.from_segment);
            const toSeg = Number(p.to_segment);
            const price = Number(p.price);
            const priceTxt = Number.isFinite(price) ? ` @ ${price.toFixed(2)}` : '';
            return `<div class="watchdog-item"><strong>${marketTxt}Trade #${tradeId}</strong> ${dir} segment ${Number.isFinite(fromSeg) ? fromSeg : '?'}->${Number.isFinite(toSeg) ? toSeg : '?'}${priceTxt} <span style="color:#fcd34d;">(${when})</span></div>`;
        }
        if (et === 'WATCHDOG_DECISION_PENDING') {
            const tradeId = Number(p.trade_id || 0);
            const rec = escapeHtml(String(p.recommendation || 'HOLD').toUpperCase());
            const win = Number(p.decision_window_sec || 90);
            return `<div class="watchdog-item"><strong>${marketTxt}Decision pending</strong> Trade #${tradeId} ${rec} | window ${Number.isFinite(win) ? Math.round(win) : 90}s <span style="color:#fcd34d;">(${when})</span></div>`;
        }
        if (et === 'WATCHDOG_DECISION_TIMEOUT') {
            const tradeId = Number(p.trade_id || 0);
            const st = escapeHtml(String(p.status || 'resolved'));
            return `<div class="watchdog-item"><strong>${marketTxt}Timeout decision</strong> Trade #${tradeId} ${st} <span style="color:#fcd34d;">(${when})</span></div>`;
        }
        if (et === 'WATCHDOG_ENTRY_PENDING') {
            const tid = escapeHtml(String(p.trigger_id || '').trim());
            const cond = escapeHtml(String(p.condition || '').trim());
            const lvl = Number(p.trigger_price);
            const dir = escapeHtml(String(p?.pending_action?.args?.direction || '').trim());
            const levelTxt = Number.isFinite(lvl) ? lvl.toFixed(2) : '?';
            return `<div class="watchdog-item"><strong>${marketTxt}Entry trigger hit</strong> ${dir} ${cond} ${levelTxt} <span style="color:#fcd34d;">(${when})</span>${tid ? ` <span style="color:#94a3b8;">[${tid}]</span>` : ''}</div>`;
        }
        if (et === 'WATCHDOG_ENTRY_CANCELED') {
            const tid = escapeHtml(String(p.trigger_id || '').trim());
            const cond = escapeHtml(String(p.condition || '').trim());
            const why = escapeHtml(String(p.cancel_reason || 'cancel_rule_hit').trim());
            return `<div class="watchdog-item"><strong>${marketTxt}Entry trigger canceled</strong> ${cond} (${why}) <span style="color:#fcd34d;">(${when})</span>${tid ? ` <span style="color:#94a3b8;">[${tid}]</span>` : ''}</div>`;
        }
        const rec = escapeHtml(String(p.recommendation || 'HOLD').toUpperCase());
        const mode = escapeHtml(String(p.mode || '').trim());
        const msg = escapeHtml(String(p.message || '').trim()).slice(0, 160);
        const sev = escapeHtml(String(ev?.severity || p.severity || 'info').toLowerCase());
        return `<div class="watchdog-item"><strong>${marketTxt}Model review</strong> [${mode}] ${rec} (${sev}) - ${msg} <span style="color:#fcd34d;">(${when})</span></div>`;
    }).join('');
    box.innerHTML = `<strong><i class="bi bi-broadcast-pin me-1"></i>Watchdog Alerts</strong><div>${html}</div>`;
    box.classList.remove('d-none');
}

function renderAgentState(state) {
    const rawState = state;
    state = _normalizeAgentStatePayload(state);
    const statusEl = document.getElementById('agent-status');
    const feedEl = document.getElementById('agent-feed');
    if (!statusEl || !feedEl) return;

    const active = !!state?.active;
    agentLoopActive = active;
    if (active) ensureAgentPoller();
    else stopAgentPoller();
    setAgentChatAvailability(!!sessionId);
    const mode = String(state?.mode || 'N/A');
    const provider = String(state?.provider || 'deterministic');
    const providerUsed = String(state?.provider_used || provider || 'deterministic');
    const providerAttempts = Array.isArray(state?.provider_attempts) ? state.provider_attempts : [];
    const providerFallbackReason = String(state?.provider_fallback_reason || '').trim();
    const runtime = state?.runtime || {};
    const guardrails = state?.guardrails || {};
    const counts = state?.counts || {};
    const jobsPending = Number(counts.jobs_pending || 0);
    const jobsRunning = Number(counts.jobs_running || 0);
    const autoExec = Number(
        counts.agent_actions_executed
        ?? counts.copilot_actions_executed
        ?? 0,
    );
    const autoScans = Number(
        counts.agent_tool_scans_executed
        ?? counts.auto_tool_scans_executed
        ?? 0,
    );
    const blocked = !!guardrails?.blocked;
    const blockedReason = String(guardrails?.blocked_reason || '').trim();
    statusEl.textContent = active
        ? `Status: ACTIVE | mode=${mode} | provider=${provider} | used=${providerUsed} | events=${counts.events || 0} | advices=${counts.advices || 0} | auto=${autoExec} | scans=${autoScans} | jobs=${jobsPending}/${jobsRunning}${blocked ? ` | blocked=${blockedReason || 'yes'}` : ''}`
        : `Status: ${String(state?.status || 'NOT_STARTED')}`;
    statusEl.style.color = active ? (blocked ? '#fca5a5' : '#86efac') : '#cbd5e1';
    renderAgentUsageMeter(state?.usage_meter || {});
    const recentAgentEvents = Array.isArray(state?.recent_agent_events) ? state.recent_agent_events : [];
    renderAgentWatchdogBox(recentAgentEvents);
    ingestPendingApprovalsFromWatchdogEvents(recentAgentEvents);
    const triggerRows = Array.isArray(state?.scheduled_triggers)
        ? state.scheduled_triggers
        : (Array.isArray(rawState?.scheduled_triggers) ? rawState.scheduled_triggers : []);
    renderAgentTriggerList(triggerRows);

    const recent = Array.isArray(state?.recent_advices) ? state.recent_advices : [];
    const recentActions = Array.isArray(state?.recent_actions) ? state.recent_actions : [];
    latestAgentAdvicesById = {};
    for (const adv of recent) {
        const id = Number(adv?.id || 0);
        if (id > 0) latestAgentAdvicesById[id] = adv;
    }
    // Reflect auto-scanned zones (if any) on chart so autonomous scans are visible.
    const snapshotToolState = state?.last_snapshot?.tool_state || {};
    const autoFvgZones = Array.isArray(snapshotToolState?.fvg_zones_preview) ? snapshotToolState.fvg_zones_preview : [];
    const movementSnapshot = snapshotToolState?.fvg_movement_strength || snapshotToolState?.movement_strength || {};
    if (!toolStates.fvg) toolStates.fvg = {};
    if (movementSnapshot && typeof movementSnapshot === 'object' && Object.keys(movementSnapshot).length > 0) {
        toolStates.fvg.movement_strength = movementSnapshot;
        updateFvgStrengthBadge(movementSnapshot);
    }
    const zoneSig = JSON.stringify(autoFvgZones.slice(0, 20));
    if (zoneRenderer && zoneSig !== lastAgentZoneSignature) {
        lastAgentZoneSignature = zoneSig;
        if (autoFvgZones.length > 0) {
            const fvgCfg = snapshotToolState?.fvg_config || {};
            const autoTf = normalizeTimeframeLabel(fvgCfg.timeframe || toolStates.fvg.detect_timeframe || getChartTimeframe(), getChartTimeframe());
            const adaptedZones = autoFvgZones.map((z) => ({
                ...z,
                scan_timeframe: autoTf,
                style: getFvgTfStyle(autoTf, z?.type),
            }));
            fvgZonesByTimeframe[autoTf] = adaptedZones;
            renderAllFvgOverlays();
            rebuildFvgNavigation();
            if (!toolStates.fvg) toolStates.fvg = {};
            const mergedZones = flattenFvgZonesAcrossTimeframes();
            toolStates.fvg.last_zone_count = mergedZones.length;
            toolStates.fvg.zones_sample = mergedZones.slice(0, 20);
            toolStates.fvg.detect_timeframe = normalizeTimeframeLabel(fvgCfg.timeframe || toolStates.fvg.detect_timeframe || getChartTimeframe(), getChartTimeframe());
            const detectTfEl = document.getElementById('fvg-detect-timeframe');
            if (detectTfEl) {
                const chartTf = getChartTimeframe();
                detectTfEl.value = toolStates.fvg.detect_timeframe === chartTf ? 'chart' : toolStates.fvg.detect_timeframe;
            }
            const scope = String(fvgCfg.scan_scope || toolStates.fvg.scan_scope || 'last_n_days').toLowerCase();
            toolStates.fvg.scan_scope = scope === 'visible' ? 'visible' : 'last_n_days';
            const scopeEl = document.getElementById('fvg-scan-scope');
            if (scopeEl && scopeEl.value !== toolStates.fvg.scan_scope) {
                scopeEl.value = toolStates.fvg.scan_scope;
            }
            const lookbackDays = Number(fvgCfg.lookback_days || toolStates.fvg.lookback_days || 2);
            if (Number.isFinite(lookbackDays)) {
                toolStates.fvg.lookback_days = Math.max(0.1, Math.min(30, lookbackDays));
                const lookbackEl = document.getElementById('fvg-lookback-days');
                if (lookbackEl && Number(lookbackEl.value) !== Number(toolStates.fvg.lookback_days)) {
                    lookbackEl.value = String(toolStates.fvg.lookback_days);
                }
            }
            toolStates.fvg.trend_filter_enabled = !!(fvgCfg.trend_filter_enabled ?? toolStates.fvg.trend_filter_enabled ?? true);
            const trendFilterEl = document.getElementById('fvg-trend-filter');
            if (trendFilterEl) trendFilterEl.checked = !!toolStates.fvg.trend_filter_enabled;
            const trendMultiplier = Number(fvgCfg.trend_multiplier || toolStates.fvg.trend_multiplier || 3);
            if (Number.isFinite(trendMultiplier)) {
                toolStates.fvg.trend_multiplier = Math.max(2, Math.min(12, Math.round(trendMultiplier)));
                const trendMultEl = document.getElementById('fvg-trend-multiplier');
                if (trendMultEl && Number(trendMultEl.value) !== Number(toolStates.fvg.trend_multiplier)) {
                    trendMultEl.value = String(toolStates.fvg.trend_multiplier);
                }
            }
            const trendMode = String(fvgCfg.trend_alignment_mode || toolStates.fvg.trend_alignment_mode || 'prefer').toLowerCase();
            toolStates.fvg.trend_alignment_mode = (trendMode === 'strict') ? 'strict' : 'prefer';
            const trendModeEl = document.getElementById('fvg-trend-alignment-mode');
            if (trendModeEl && trendModeEl.value !== toolStates.fvg.trend_alignment_mode) {
                trendModeEl.value = toolStates.fvg.trend_alignment_mode;
            }
            updateFvgScopeControls();
            const badge = document.getElementById('fvg-zone-count');
            if (badge) {
                const mergedCount = flattenFvgZonesAcrossTimeframes().length;
                badge.textContent = String(mergedCount);
                badge.classList.toggle('d-none', mergedCount === 0);
            }
            const trend = snapshotToolState?.fvg_trend || snapshotToolState?.trend || {};
            const movement = snapshotToolState?.fvg_movement_strength || snapshotToolState?.movement_strength || {};
            const trendLabel = (trend && trend.direction)
                ? `agent_auto ${autoTf} | ${String(trend.direction)} @ ${String(trend.trend_timeframe || '')}`.trim()
                : `agent_auto ${autoTf}`;
            renderFvgInspector(adaptedZones, trendLabel);
            toolStates.fvg.movement_strength = movement;
            updateFvgStrengthBadge(movement);
        }
    }
    feedEl.innerHTML = '';
    for (const adv of recent.slice(0, 6)) {
        const li = document.createElement('li');
        const conf = Number(adv?.confidence ?? 0);
        const delivery = String(adv?.action?.delivery || adv?.delivery || adv?.status || '').toUpperCase();
        const eventPriority = Number(adv?.evidence?._event_priority ?? adv?.source_event_priority ?? 0);
        const badgeColor = delivery.includes('ACTION') ? '#86efac' : (delivery.includes('WATCH') ? '#fde68a' : '#cbd5e1');
        const adviceId = Number(adv?.id || 0);
        const adviceStatus = String(adv?.status || 'NEW').toUpperCase();
        const canAct = adviceId > 0 && ['NEW', 'ACKNOWLEDGED'].includes(adviceStatus);
        const executeAction = escapeHtml(String(adv?.action?.action_type || adv?.advice_type || 'EXECUTE'));
        li.innerHTML = `
            <strong>${escapeHtml(adv?.advice_type || 'ADVICE')}</strong>
            <span style="color:#94a3b8;">(${(conf * 100).toFixed(0)}%)</span>
            <span style="color:${badgeColor}; margin-left:6px;">${escapeHtml(delivery || 'NEW')}</span>
            ${eventPriority ? `<span style=\"color:#94a3b8; margin-left:6px;\">P${eventPriority}</span>` : ''}<br>
            ${escapeHtml(adv?.summary || '')}
            ${canAct ? `
                <div class="mt-1 d-flex gap-1">
                    <button class="btn btn-sm btn-outline-success py-0 px-1" data-advice-id="${adviceId}" data-agent-action="ACCEPTED">Accept</button>
                    <button class="btn btn-sm btn-outline-danger py-0 px-1" data-advice-id="${adviceId}" data-agent-action="REJECTED">Reject</button>
                    <button class="btn btn-sm btn-outline-info py-0 px-1" data-advice-id="${adviceId}" data-agent-action="${executeAction}">Execute</button>
                </div>
            ` : ''}
        `;
        feedEl.appendChild(li);
    }
    if (providerAttempts.length > 0) {
        const warn = providerAttempts[0] || {};
        const li = document.createElement('li');
        li.style.color = '#fcd34d';
        const errType = String(warn.error_type || 'error');
        const errDetail = String(warn.error || '').trim();
        li.innerHTML = `<strong>Fallback:</strong> ${escapeHtml(String(warn.provider || 'provider'))} failed (${escapeHtml(errType)})${errDetail ? ` - ${escapeHtml(errDetail)}` : ''}`;
        feedEl.appendChild(li);
    } else if (active && provider !== 'deterministic' && providerUsed === 'deterministic') {
        const li = document.createElement('li');
        li.style.color = '#fcd34d';
        let reasonText = 'LLM provider did not run on this cycle.';
        if (providerFallbackReason === 'observe_mode') {
            reasonText = 'Mode is OBSERVE, so LLM is intentionally skipped.';
        } else if (providerFallbackReason === 'no_events') {
            reasonText = 'No new decision events yet, so LLM was skipped.';
        } else if (providerFallbackReason === 'no_llm_event_in_allowlist') {
            reasonText = 'Events occurred, but none matched LLM event allowlist.';
        } else if (providerFallbackReason === 'provider_forced_deterministic') {
            reasonText = 'Provider chain is configured to deterministic-first.';
        } else if (providerFallbackReason === 'provider_error_fallback') {
            reasonText = 'Provider failed and system fell back to deterministic.';
        }
        li.innerHTML = `<strong>Fallback:</strong> ${escapeHtml(reasonText)}`;
        feedEl.appendChild(li);
    }
    if (active && provider !== 'deterministic' && !runtime?.has_api_key && provider !== 'local_gptoss_http') {
        const li = document.createElement('li');
        li.style.color = '#fca5a5';
        li.innerHTML = '<strong>Runtime:</strong> API key not configured in current process; provider may fallback.';
        feedEl.appendChild(li);
    }
    if (blocked) {
        const li = document.createElement('li');
        li.style.color = '#fca5a5';
        li.innerHTML = `<strong>Guardrail:</strong> AUTO_PAPER blocked (${escapeHtml(blockedReason || 'unknown')})`;
        feedEl.appendChild(li);
    }
    if (recentActions.length > 0) {
        const a = recentActions[0] || {};
        const li = document.createElement('li');
        li.style.color = '#93c5fd';
        li.innerHTML = `<strong>Last action:</strong> ${escapeHtml(String(a.action_type || 'N/A'))} (${escapeHtml(String(a.status || 'N/A'))})`;
        feedEl.appendChild(li);
    }
    if (rawState && typeof rawState === 'object' && rawState.permissions && typeof rawState.permissions === 'object') {
        const perms = rawState.permissions;
        const setChk = (id, v) => {
            const el = document.getElementById(id);
            if (el && typeof v === 'boolean') el.checked = v;
        };
        setChk('agent-can-scan-tools', perms.can_scan_tools);
        setChk('agent-can-use-research', perms.can_use_research);
        setChk('agent-can-manage-indicators', perms.can_manage_indicators);
        setChk('agent-can-place-trades', perms.can_place_trades);
        setChk('agent-can-close-trades', perms.can_close_trades);
        setChk('agent-can-auto-execute', perms.can_auto_execute);
        setChk('agent-require-confirm', perms.requires_user_confirm_for_trade);
        syncAgentPermissionDependencies();
    }
    const cfg = (state && typeof state === 'object' && state.config && typeof state.config === 'object') ? state.config : {};
    const watchdogMode = String(cfg.watchdog_mode || '').trim().toLowerCase();
    const watchdogModeEl = document.getElementById('agent-watchdog-mode');
    if (watchdogModeEl && ['deterministic', 'local_gptoss_http', 'claude'].includes(watchdogMode)) {
        watchdogModeEl.value = watchdogMode;
    }
    const watchdogIntervalEl = document.getElementById('agent-watchdog-interval');
    const watchdogInt = Number(cfg.watchdog_interval_sec);
    if (watchdogIntervalEl && Number.isFinite(watchdogInt)) {
        watchdogIntervalEl.value = String(Math.max(5, Math.min(300, Math.round(watchdogInt))));
    }
    const watchdogLlmIntervalEl = document.getElementById('agent-watchdog-llm-interval');
    const watchdogLlmInt = Number(cfg.watchdog_llm_min_interval_sec);
    if (watchdogLlmIntervalEl && Number.isFinite(watchdogLlmInt)) {
        watchdogLlmIntervalEl.value = String(Math.max(10, Math.min(3600, Math.round(watchdogLlmInt))));
    }
    const watchdogTriggerApprovalEl = document.getElementById('agent-watchdog-trigger-require-approval');
    if (watchdogTriggerApprovalEl) {
        watchdogTriggerApprovalEl.checked = Boolean(cfg.watchdog_trigger_requires_approval);
    }
    const guardrailEnabledEl = document.getElementById('agent-guardrail-enabled');
    if (guardrailEnabledEl) {
        const rawEnabled = cfg.guardrail_enabled;
        guardrailEnabledEl.checked = (rawEnabled === undefined || rawEnabled === null) ? true : Boolean(rawEnabled);
    }
    const guardrailSessionEl = document.getElementById('agent-guardrail-session-filter');
    if (guardrailSessionEl) {
        guardrailSessionEl.checked = Boolean(cfg.guardrail_session_filter_enabled);
    }
    const guardrailNewsEl = document.getElementById('agent-guardrail-news-filter');
    if (guardrailNewsEl) {
        guardrailNewsEl.checked = Boolean(cfg.guardrail_news_filter_enabled);
    }
    const guardrailNewsLookbackEl = document.getElementById('agent-guardrail-news-lookback');
    const lookbackMin = Number(cfg.guardrail_news_lookback_min);
    if (guardrailNewsLookbackEl && Number.isFinite(lookbackMin)) {
        guardrailNewsLookbackEl.value = String(Math.max(15, Math.min(1440, Math.round(lookbackMin))));
    }
    const newsProviderEl = document.getElementById('agent-news-provider');
    const newsProvider = String(cfg.market_news_provider || '').trim().toLowerCase();
    if (newsProviderEl && ['polygon', 'ibkr'].includes(newsProvider)) {
        newsProviderEl.value = newsProvider;
    }
    const newsLlmSummaryEl = document.getElementById('agent-news-llm-summary');
    if (newsLlmSummaryEl) {
        newsLlmSummaryEl.checked = Boolean(cfg.market_news_llm_summary_enabled);
    }
    const newsSummaryModelEl = document.getElementById('agent-news-summary-model');
    const newsSummaryModel = String(cfg.market_news_summary_model || '').trim();
    if (newsSummaryModelEl && newsSummaryModel) {
        newsSummaryModelEl.value = newsSummaryModel;
    }
    const newsIbkrHostEl = document.getElementById('agent-news-ibkr-host');
    const newsIbkrHost = String(cfg.market_news_ibkr_host || '').trim();
    if (newsIbkrHostEl && newsIbkrHost) {
        newsIbkrHostEl.value = newsIbkrHost;
    }
    const newsIbkrPortEl = document.getElementById('agent-news-ibkr-port');
    const newsIbkrPort = Number(cfg.market_news_ibkr_port);
    if (newsIbkrPortEl && Number.isFinite(newsIbkrPort)) {
        newsIbkrPortEl.value = String(Math.max(1, Math.min(65535, Math.round(newsIbkrPort))));
    }
    syncAgentGuardrailControls();
    syncAgentNewsProviderControls();
    void refreshAgentNewsHealth(false);
    if (!feedEl.children.length) {
        feedEl.classList.add('d-none');
        return;
    }
    feedEl.classList.remove('d-none');
}

function setAgentChatAvailability(enabled) {
    const canChat = !!enabled;
    const chatGateEl = document.getElementById('agent-chat-gate');
    const chatGateModalEl = document.getElementById('agent-chat-gate-modal');
    const chatSectionEl = document.getElementById('agent-chat-section');
    const openChatBtn = document.getElementById('btn-open-agent-chat');
    if (chatGateEl) {
        chatGateEl.classList.toggle('d-none', canChat);
        if (!canChat) chatGateEl.textContent = 'Start a Workbench session first, then chat is available.';
    }
    if (chatGateModalEl) {
        chatGateModalEl.classList.toggle('d-none', canChat);
        if (!canChat) chatGateModalEl.textContent = 'Start a Workbench session first, then open chat.';
    }
    if (chatSectionEl) chatSectionEl.classList.toggle('d-none', !canChat);
    if (openChatBtn) openChatBtn.disabled = !canChat;
}

function _applyAgentFvgToolOutput(data, args, plannerTool, sourceTag) {
    const rawZones = Array.isArray(data?.zones) ? data.zones : [];
    const cfg = (args && typeof args.config === 'object') ? args.config : {};
    const detectTf = normalizeTimeframeLabel(
        String(data?.scan_timeframe || cfg.timeframe || toolStates?.fvg?.detect_timeframe || getChartTimeframe()),
        getChartTimeframe(),
    );
    const adaptedZones = rawZones.map((z) => ({
        ...z,
        scan_timeframe: detectTf,
        style: getFvgTfStyle(detectTf, z?.type),
    }));
    if (!fvgZonesByTimeframe || typeof fvgZonesByTimeframe !== 'object') fvgZonesByTimeframe = {};
    fvgZonesByTimeframe[detectTf] = adaptedZones;
    renderAllFvgOverlays(true);
    rebuildFvgNavigation();

    if (!toolStates.fvg) toolStates.fvg = {};
    const mergedZones = flattenFvgZonesAcrossTimeframes();
    toolStates.fvg.last_zone_count = mergedZones.length;
    toolStates.fvg.zones_sample = mergedZones.slice(0, 20);
    toolStates.fvg.detect_timeframe = detectTf;

    const trend = (data && typeof data.trend === 'object') ? data.trend : {};
    const movement = (data && typeof data.movement_strength === 'object') ? data.movement_strength : {};
    if (movement && Object.keys(movement).length > 0) {
        toolStates.fvg.movement_strength = movement;
        updateFvgStrengthBadge(movement);
    }

    const detectTfEl = document.getElementById('fvg-detect-timeframe');
    if (detectTfEl) {
        const chartTf = getChartTimeframe();
        detectTfEl.value = detectTf === chartTf ? 'chart' : detectTf;
    }
    const badge = document.getElementById('fvg-zone-count');
    if (badge) {
        badge.textContent = String(mergedZones.length);
        badge.classList.toggle('d-none', mergedZones.length === 0);
    }

    const trendLabel = (trend && trend.direction)
        ? `${sourceTag} ${detectTf} | ${String(trend.direction)} @ ${String(trend.trend_timeframe || '')}`.trim()
        : `${sourceTag} ${detectTf}`.trim();
    renderFvgInspector(adaptedZones, trendLabel);

    if (plannerTool === 'scan_draw_fvg_range') {
        fvgCreatorMarkers = buildFvgCreatorMarkers(adaptedZones);
        syncCandleMarkers();
        const selection = (data && typeof data.selection === 'object') ? data.selection : {};
        const bars = Number(selection?.bars || 0);
        if (bars > 0) _updateDrawFvgStatus(`Agent drew+scanned ${bars} selected bars and found ${adaptedZones.length} zone(s).`);
    }

    lastAgentZoneSignature = JSON.stringify(rawZones.slice(0, 20));
    return true;
}

function _applyAgentMeanRevToolOutput(data, sourceTag) {
    const rawZones = Array.isArray(data?.zones) ? data.zones : [];
    if (zoneRenderer) {
        zoneRenderer.clearAll();
        renderedToolId = rawZones.length > 0 ? 'mean_rev' : null;
        for (const z of rawZones) zoneRenderer.addZone(z);
    }
    if (!toolStates.mean_rev) toolStates.mean_rev = {};
    toolStates.mean_rev.last_zone_count = rawZones.length;
    toolStates.mean_rev.zones_sample = rawZones.slice(0, 20);
    toolStates.mean_rev.current_state = (data && typeof data.current_state === 'object') ? data.current_state : {};
    updateMeanRevZscoreBadge(toolStates.mean_rev.current_state);
    renderMeanRevInspector(rawZones, sourceTag);
    const badge = document.getElementById('mean-rev-zone-count');
    if (badge) {
        badge.textContent = String(rawZones.length);
        badge.classList.toggle('d-none', rawZones.length === 0);
    }
    return true;
}

function _applyAgentLiquidityToolOutput(data, sourceTag) {
    const rawZones = Array.isArray(data?.zones) ? data.zones : [];
    if (!toolStates.liquidity) toolStates.liquidity = {};
    toolStates.liquidity.last_zone_count = rawZones.length;
    toolStates.liquidity.zones_sample = rawZones.slice(0, 20);
    toolStates.liquidity.current_state = (data && typeof data.current_state === 'object') ? data.current_state : {};
    toolStates.liquidity.movement_strength = (data && typeof data.movement_strength === 'object') ? data.movement_strength : {};
    const nearest = toolStates.liquidity.current_state?.nearest_pool_level;
    const summary = Number.isFinite(Number(nearest))
        ? `${sourceTag}: liquidity scan found ${rawZones.length} zones. Nearest pool ${Number(nearest).toFixed(2)}`
        : `${sourceTag}: liquidity scan found ${rawZones.length} zones.`;
    showStatus(summary, 'info');
    return true;
}

function _applyAgentIndicatorVisibilityOutput(data, sourceTag) {
    const vis = (data && typeof data.visibility === 'object') ? data.visibility : {};
    if (!vis || typeof vis !== 'object') return false;
    const next = {
        smaEma: !!vis.smaEma,
        adx: !!vis.adx,
        rsi: !!vis.rsi,
        stoch: !!vis.stoch,
        bollinger: !!vis.bollinger,
        goldenCross: !!vis.goldenCross,
    };
    indicatorSelection = { ...indicatorSelection, ...next };
    const map = {
        smaEma: 'ind-sma-ema',
        adx: 'ind-adx',
        rsi: 'ind-rsi',
        stoch: 'ind-stoch',
        bollinger: 'ind-bollinger',
        goldenCross: 'ind-golden-cross',
    };
    Object.entries(map).forEach(([k, id]) => {
        const el = document.getElementById(id);
        if (el) el.checked = !!indicatorSelection[k];
    });
    updateIndicatorsOnChart();
    showStatus(`Agent updated indicators (${sourceTag})`, 'info');
    return true;
}

async function _applyAgentMarketContextOutput(data, args, sourceTag) {
    const payload = (data && typeof data === 'object') ? data : {};
    const rawArgs = (args && typeof args === 'object') ? args : {};
    const symbol = String(payload.symbol || rawArgs.symbol || document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    const timeframe = normalizeTimeframeLabel(payload.timeframe || rawArgs.timeframe || document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
    const source = String(payload.source || rawArgs.source || document.getElementById('live-source')?.value || 'mt5').toLowerCase() === 'databento' ? 'databento' : 'mt5';
    const rawDays = Number(payload.history_days ?? rawArgs.history_days ?? getLiveHistoryDays());
    const historyDays = Math.max(0.1, Math.min(60, Number.isFinite(rawDays) ? rawDays : 2));

    const fsSymbol = document.getElementById('fs-market-symbol');
    const fsTf = document.getElementById('fs-market-timeframe');
    const fsSource = document.getElementById('fs-market-source');
    const fsDays = document.getElementById('fs-market-days');
    if (fsSymbol) fsSymbol.value = symbol;
    if (fsTf) fsTf.value = timeframe;
    if (fsSource) fsSource.value = source;
    if (fsDays) fsDays.value = String(historyDays);

    try {
        await applyFullscreenMarketSwitch();
        showStatus(`Agent switched market context to ${symbol} ${timeframe} (${getLiveSourceLabel(source)})`, 'success');
        return true;
    } catch (err) {
        showStatus(`Agent market switch failed: ${err?.message || err}`, 'warning');
        return false;
    }
}

async function applyAgentToolCallsToChart(toolCalls, sourceTag = 'agent_tool') {
    const calls = Array.isArray(toolCalls) ? toolCalls : [];
    if (calls.length === 0) return 0;
    let applied = 0;
    for (const tc of calls) {
        if (!tc || typeof tc !== 'object') continue;
        const plannerTool = String(tc.tool_id || '').trim().toLowerCase();
        const result = (tc.result && typeof tc.result === 'object') ? tc.result : {};
        if (result.ok === false) continue;
        const data = (result.data && typeof result.data === 'object') ? { ...result.data } : null;
        if (!data) continue;
        if (result.selection && typeof result.selection === 'object') data.selection = result.selection;
        const args = (tc.args && typeof tc.args === 'object') ? tc.args : {};
        const scannedTool = String(
            data.tool_id || args.tool_id || (plannerTool === 'scan_draw_fvg_range' ? 'fvg' : ''),
        ).trim().toLowerCase();
        if (scannedTool === 'fvg' && (plannerTool === 'scan_tool' || plannerTool === 'scan_draw_fvg_range')) {
            if (_applyAgentFvgToolOutput(data, args, plannerTool, sourceTag)) applied += 1;
            continue;
        }
        if (scannedTool === 'mean_rev' && plannerTool === 'scan_tool') {
            if (_applyAgentMeanRevToolOutput(data, `${sourceTag} mean_rev`)) applied += 1;
            continue;
        }
        if (scannedTool === 'liquidity' && plannerTool === 'scan_tool') {
            if (_applyAgentLiquidityToolOutput(data, `${sourceTag} liquidity`)) applied += 1;
            continue;
        }
        if (plannerTool === 'set_indicator_visibility') {
            if (_applyAgentIndicatorVisibilityOutput(data, sourceTag)) applied += 1;
            continue;
        }
        if (plannerTool === 'set_market_context') {
            if (await _applyAgentMarketContextOutput(data, args, sourceTag)) applied += 1;
            continue;
        }
        if (plannerTool === 'schedule_trade_entry' || plannerTool === 'cancel_scheduled_entry') {
            await refreshAgentTriggerList(false);
            applied += 1;
            continue;
        }
    }
    return applied;
}

async function logAgentAction(adviceId, actionType) {
    if (!sessionId || !adviceId || !actionType) return;
    const raw = String(actionType || '').toUpperCase().trim();
    let mappedActionType = 'REVIEW_NOTE';
    let mappedStatus = 'APPROVED';
    if (raw === 'REJECTED') {
        mappedStatus = 'REJECTED';
    } else if (raw.includes('ENTRY')) {
        mappedActionType = 'EXECUTE_TRADE_ENTRY';
        mappedStatus = 'EXECUTED';
    } else if (raw.includes('EXIT') || raw.includes('CLOSE')) {
        mappedActionType = 'EXECUTE_TRADE_EXIT';
        mappedStatus = 'EXECUTED';
    } else if (raw.includes('SCAN')) {
        mappedActionType = 'SCAN_TOOL';
        mappedStatus = 'EXECUTED';
    } else if (raw.includes('INDICATOR')) {
        mappedActionType = 'SET_INDICATOR_VISIBILITY';
        mappedStatus = 'EXECUTED';
    } else if (raw.includes('RESEARCH')) {
        mappedActionType = 'RUN_RESEARCH_OPTIMIZER';
        mappedStatus = 'EXECUTED';
    } else if (raw === 'ACCEPTED') {
        mappedStatus = 'APPROVED';
    }
    const advice = latestAgentAdvicesById[Number(adviceId)] || {};
    const actionPayload = (advice && typeof advice.action === 'object' && advice.action.payload && typeof advice.action.payload === 'object')
        ? advice.action.payload
        : {};
    const payload = {
        action_id: Number(adviceId),
        requested_by: 'USER',
        action_type: mappedActionType,
        status: mappedStatus,
        reason: null,
        payload: {
            ...actionPayload,
            source_action_type: raw,
            advice_type: String(advice?.advice_type || ''),
        },
    };
    const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/action`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data?.ok === false) {
        throw new Error(String(data?.detail || data?.error || `Action failed (${res.status})`));
    }
}

async function onAgentFeedClick(event) {
    const btn = event.target?.closest?.('button[data-agent-action]');
    if (!btn) return;
    const adviceId = Number(btn.getAttribute('data-advice-id') || 0);
    const actionType = String(btn.getAttribute('data-agent-action') || '').trim();
    if (!adviceId || !actionType) return;
    btn.disabled = true;
    try {
        await logAgentAction(adviceId, actionType);
        showStatus(`Agent action logged: ${actionType}`, 'success');
        await refreshAgentState(true);
    } catch (err) {
        showStatus(`Agent action failed: ${err.message || err}`, 'danger');
    } finally {
        btn.disabled = false;
    }
}

function updateConsultantProviderDefaults() {
    const providerEl = document.getElementById('consultant-provider');
    const modelEl = document.getElementById('consultant-model');
    const modelListEl = document.getElementById('consultant-model-options');
    const urlEl = document.getElementById('consultant-url');
    const keyEl = document.getElementById('consultant-api-key');
    const keyHintEl = document.getElementById('consultant-key-hint');
    const timeoutEl = document.getElementById('agent-timeout');
    if (!providerEl || !modelEl || !urlEl || !keyEl || !modelListEl) return;

    const p = String(providerEl.value || 'local_gptoss_http');
    const allKnown = [
        'gpt-oss-20b',
        'gpt-4.1-mini',
        'gpt-4o-mini',
        'gpt-4.1',
        'claude-sonnet-4-5-20250929',
        'claude-haiku-4-5-20251001',
        'claude-3-5-haiku-latest',
        'claude-3-5-sonnet-latest',
        'deterministic',
    ];
    const setModelOptions = (options) => {
        const uniq = Array.from(new Set((options || []).map((x) => String(x || '').trim()).filter(Boolean)));
        modelListEl.innerHTML = uniq.map((m) => `<option value="${escapeHtml(m)}"></option>`).join('');
        return uniq;
    };
    const maybeResetModel = (options, fallback) => {
        const cur = String(modelEl.value || '').trim();
        if (!cur || (allKnown.includes(cur) && !options.includes(cur))) {
            modelEl.value = String(fallback || options[0] || '');
        }
    };

    if (p === 'local_gptoss_http') {
        const opts = setModelOptions(['gpt-oss-20b']);
        maybeResetModel(opts, 'gpt-oss-20b');
        if (!urlEl.value || String(urlEl.value).includes('api.openai.com') || String(urlEl.value).includes('api.anthropic.com')) {
            urlEl.value = 'http://127.0.0.1:8012';
        }
        if (timeoutEl) {
            const cur = Number(timeoutEl.value || 45);
            if (!Number.isFinite(cur) || cur < 90) timeoutEl.value = '180';
        }
        modelEl.disabled = true;
        keyEl.disabled = true;
        keyEl.placeholder = 'Not required for local GPT-OSS';
        if (keyHintEl) keyHintEl.textContent = 'Local GPT-OSS does not need an API key.';
    } else if (p === 'openai_compat') {
        const opts = setModelOptions(['gpt-4.1-mini', 'gpt-4o-mini', 'gpt-4.1']);
        maybeResetModel(opts, 'gpt-4.1-mini');
        if (!urlEl.value || String(urlEl.value).includes('127.0.0.1:8012') || String(urlEl.value).includes('api.anthropic.com')) {
            urlEl.value = 'https://api.openai.com/v1';
        }
        modelEl.disabled = false;
        keyEl.disabled = false;
        keyEl.placeholder = 'Optional OpenAI key (leave empty to use OPENAI_API_KEY from .env)';
        if (keyHintEl) keyHintEl.textContent = 'If key is empty, backend uses OPENAI_API_KEY from environment.';
    } else if (p === 'claude') {
        const opts = setModelOptions([
            'claude-sonnet-4-5-20250929',
            'claude-3-5-sonnet-latest',
            'claude-haiku-4-5-20251001',
            'claude-3-5-haiku-latest',
        ]);
        maybeResetModel(opts, 'claude-sonnet-4-5-20250929');
        if (!urlEl.value || String(urlEl.value).includes('127.0.0.1:8012') || String(urlEl.value).includes('api.openai.com')) {
            urlEl.value = 'https://api.anthropic.com';
        }
        modelEl.disabled = false;
        keyEl.disabled = false;
        keyEl.placeholder = 'Optional Claude key (leave empty to use CLAUDE_API_KEY/ANTHROPIC_API_KEY)';
        if (keyHintEl) keyHintEl.textContent = 'If key is empty, backend uses CLAUDE_API_KEY / ANTHROPIC_API_KEY from environment.';
    } else {
        const opts = setModelOptions(['deterministic']);
        maybeResetModel(opts, 'deterministic');
        modelEl.disabled = true;
        urlEl.value = '';
        keyEl.disabled = true;
        keyEl.placeholder = 'Not required for deterministic';
        if (keyHintEl) keyHintEl.textContent = 'Deterministic mode does not need model URL or API key.';
    }
}

function setAgentChatTyping(active) {
    agentChatTyping = !!active;
    const el = document.getElementById('agent-chat-typing');
    if (el) el.classList.toggle('d-none', !agentChatTyping);
}

function toggleAgentIdentityFields(forceExpand = null) {
    const body = document.getElementById('agent-identity-fields');
    const btn = document.getElementById('btn-agent-identity-toggle');
    if (!body || !btn) return;
    const shouldShow = forceExpand === null ? body.classList.contains('d-none') : !!forceExpand;
    body.classList.toggle('d-none', !shouldShow);
    btn.classList.toggle('expanded', shouldShow);
}

function toggleAgentMemoryFields(forceExpand = null) {
    const body = document.getElementById('agent-memory-fields');
    const btn = document.getElementById('btn-agent-memory-toggle');
    if (!body || !btn) return;
    const shouldShow = forceExpand === null ? body.classList.contains('d-none') : !!forceExpand;
    body.classList.toggle('d-none', !shouldShow);
    btn.classList.toggle('expanded', shouldShow);
}

function _consultantNowIso() {
    try { return new Date().toISOString(); } catch (_) { return ''; }
}

function _extractReplyFromPayloadLike(rawLike) {
    const raw = String(rawLike || '').trim();
    if (!raw) return '';
    const looksLikePayload = (obj) => {
        if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return false;
        return (
            Object.prototype.hasOwnProperty.call(obj, 'reply')
            || Object.prototype.hasOwnProperty.call(obj, 'tool_calls')
            || Object.prototype.hasOwnProperty.call(obj, 'proposed_actions')
            || Object.prototype.hasOwnProperty.call(obj, 'memory_notes')
        );
    };
    const tryParse = (txt) => {
        try {
            const obj = JSON.parse(String(txt || '').trim());
            if (looksLikePayload(obj)) return String(obj.reply || '').trim();
        } catch (_) {
            return '';
        }
        return '';
    };

    let reply = tryParse(raw);
    if (reply) return reply;

    const fenceMatch = raw.match(/```json\s*([\s\S]*)$/i);
    if (fenceMatch && fenceMatch[1]) {
        reply = tryParse(String(fenceMatch[1] || '').replace(/```$/g, '').trim());
        if (reply) return reply;
    }

    const low = raw.toLowerCase();
    if (!low.includes('"reply"') || (!low.includes('"proposed_actions"') && !low.includes('"tool_calls"') && !low.includes('"memory_notes"'))) {
        return '';
    }
    const m = raw.match(/"reply"\s*:\s*"((?:\\.|[^"\\])*)"/s);
    if (!m || !m[1]) return '';
    const body = String(m[1]);
    try {
        return String(JSON.parse(`"${body}"`) || '').trim();
    } catch (_) {
        return body.replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\').trim();
    }
}

function sanitizeAgentReplyText(rawLike) {
    let text = String(rawLike || '').trim();
    if (!text) return '';
    const extracted = _extractReplyFromPayloadLike(text);
    if (extracted) return extracted;
    const looksLikePayload = (obj) => {
        if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return false;
        return (
            Object.prototype.hasOwnProperty.call(obj, 'reply')
            || Object.prototype.hasOwnProperty.call(obj, 'tool_calls')
            || Object.prototype.hasOwnProperty.call(obj, 'proposed_actions')
            || Object.prototype.hasOwnProperty.call(obj, 'memory_notes')
        );
    };

    // Remove fenced JSON payload blocks if they are structured agent payloads.
    const fenceRe = /```json\s*([\s\S]*?)```/gi;
    text = text.replace(fenceRe, (full, body) => {
        const rawBody = String(body || '').trim();
        try {
            const obj = JSON.parse(rawBody);
            if (looksLikePayload(obj)) return '';
        } catch (_) {
            const lowered = rawBody.toLowerCase();
            if (
                lowered.includes('"reply"')
                && (
                    lowered.includes('"proposed_actions"')
                    || lowered.includes('"tool_calls"')
                    || lowered.includes('"memory_notes"')
                )
            ) {
                return '';
            }
        }
        return full;
    }).trim();

    // Remove trailing raw JSON payload object appended after prose.
    const tailMatch = text.match(/(\{[\s\S]*\})\s*$/);
    if (tailMatch && tailMatch.index !== undefined && tailMatch.index > 0) {
        const tailBody = String(tailMatch[1] || '').trim();
        try {
            const obj = JSON.parse(tailBody);
            if (looksLikePayload(obj)) {
                text = text.slice(0, tailMatch.index).trim();
            }
        } catch (_) {
            const lowered = tailBody.toLowerCase();
            if (
                lowered.includes('"reply"')
                && (
                    lowered.includes('"proposed_actions"')
                    || lowered.includes('"tool_calls"')
                    || lowered.includes('"memory_notes"')
                )
            ) {
                text = text.slice(0, tailMatch.index).trim();
            }
        }
    }
    return text;
}

function saveAgentProviderPrefs() {
    try {
        const provider = String(document.getElementById('consultant-provider')?.value || '').trim();
        const model = String(document.getElementById('consultant-model')?.value || '').trim();
        const llmUrl = String(document.getElementById('consultant-url')?.value || '').trim();
        const timeoutRaw = Number(document.getElementById('agent-timeout')?.value || 45);
        const timeoutSec = Number.isFinite(timeoutRaw) ? Math.max(10, Math.min(600, Math.round(timeoutRaw))) : 45;
        localStorage.setItem(
            AGENT_PROVIDER_PREFS_KEY,
            JSON.stringify({
                provider,
                model,
                llm_url: llmUrl,
                timeout_sec: timeoutSec,
            }),
        );
    } catch (_) {
        // noop
    }
}

function loadAgentProviderPrefs() {
    try {
        const raw = localStorage.getItem(AGENT_PROVIDER_PREFS_KEY);
        if (!raw) return;
        const obj = JSON.parse(raw);
        if (!obj || typeof obj !== 'object') return;
        const provider = String(obj.provider || '').trim();
        const model = String(obj.model || '').trim();
        const llmUrl = String(obj.llm_url || '').trim();
        const timeoutSec = Number(obj.timeout_sec);
        const providerEl = document.getElementById('consultant-provider');
        const modelEl = document.getElementById('consultant-model');
        const urlEl = document.getElementById('consultant-url');
        const timeoutEl = document.getElementById('agent-timeout');
        if (providerEl && provider) providerEl.value = provider;
        updateConsultantProviderDefaults();
        if (modelEl && model) modelEl.value = model;
        if (urlEl && llmUrl) urlEl.value = llmUrl;
        if (timeoutEl && Number.isFinite(timeoutSec)) {
            timeoutEl.value = String(Math.max(10, Math.min(600, Math.round(timeoutSec))));
        }
    } catch (_) {
        // noop
    }
}

function _identityLinesFromText(raw, maxItems = 12) {
    const rows = String(raw || '')
        .split(/\r?\n/)
        .map((x) => x.trim())
        .filter((x) => x.length >= 2);
    const out = [];
    for (let i = 0; i < rows.length && out.length < maxItems; i += 1) {
        const text = rows[i].replace(/\s+/g, ' ').trim();
        if (text) out.push(text.slice(0, 220));
    }
    return out;
}

function _identityTextFromLines(rowsLike) {
    return (Array.isArray(rowsLike) ? rowsLike : [])
        .map((x) => String(x || '').trim())
        .filter(Boolean)
        .join('\n');
}

function _identityNormText(v) {
    return String(v || '').replace(/\s+/g, ' ').trim().toLowerCase();
}

function _identityNormLines(rowsLike) {
    return (Array.isArray(rowsLike) ? rowsLike : [])
        .map((x) => _identityNormText(x))
        .filter(Boolean);
}

function _identityMatchesPreset(identityLike, presetLike) {
    const identity = identityLike && typeof identityLike === 'object' ? identityLike : {};
    const preset = presetLike && typeof presetLike === 'object' ? presetLike : {};
    const iPersona = _identityNormText(identity.persona);
    const iTone = _identityNormText(identity.tone);
    const pPersona = _identityNormText(preset.persona);
    const pTone = _identityNormText(preset.tone);
    if (!iPersona || !iTone || iPersona !== pPersona || iTone !== pTone) return false;
    const iRisk = _identityNormLines(identity.risk_doctrine);
    const pRisk = _identityNormLines(preset.risk_doctrine);
    const iRules = _identityNormLines(identity.immutable_rules);
    const pRules = _identityNormLines(preset.immutable_rules);
    return JSON.stringify(iRisk) === JSON.stringify(pRisk)
        && JSON.stringify(iRules) === JSON.stringify(pRules);
}

function _resolveIdentityPresetKey(identityLike) {
    const identity = {
        ...AGENT_IDENTITY_DEFAULTS,
        ...(identityLike && typeof identityLike === 'object' ? identityLike : {}),
    };
    if (_identityMatchesPreset(identity, AGENT_IDENTITY_PRESETS.master_quant)) return 'master_quant';
    return 'apprentice';
}

function _syncIdentityPresetInUI(identityLike) {
    const sel = document.getElementById('agent-identity-preset');
    if (!sel) return;
    sel.value = _resolveIdentityPresetKey(identityLike);
}

function applyAgentIdentityPresetFromUI(presetKey) {
    const key = String(presetKey || 'apprentice').toLowerCase();
    const preset = AGENT_IDENTITY_PRESETS[key] || AGENT_IDENTITY_PRESETS.apprentice;
    const current = {
        ...AGENT_IDENTITY_DEFAULTS,
        ...(agentIdentityState && typeof agentIdentityState === 'object' ? agentIdentityState : {}),
    };
    const nextIdentity = {
        ...current,
        lock_personality: preset.lock_personality !== false,
        persona: String(preset.persona || AGENT_IDENTITY_DEFAULTS.persona),
        tone: String(preset.tone || AGENT_IDENTITY_DEFAULTS.tone),
        risk_doctrine: Array.isArray(preset.risk_doctrine) ? preset.risk_doctrine.slice(0, 12) : AGENT_IDENTITY_DEFAULTS.risk_doctrine.slice(),
        immutable_rules: Array.isArray(preset.immutable_rules) ? preset.immutable_rules.slice(0, 12) : AGENT_IDENTITY_DEFAULTS.immutable_rules.slice(),
    };
    applyAgentIdentityToUI(nextIdentity);
    const status = document.getElementById('agent-identity-status');
    if (status) status.textContent = `Preset applied: ${_identityPresetLabel(key)}. Click Save to persist.`;
}

function applyAgentIdentityToUI(identityLike) {
    const identity = {
        ...AGENT_IDENTITY_DEFAULTS,
        ...(identityLike && typeof identityLike === 'object' ? identityLike : {}),
    };
    agentIdentityState = identity;
    const setChk = (id, v) => { const el = document.getElementById(id); if (el) el.checked = !!v; };
    const setVal = (id, v) => { const el = document.getElementById(id); if (el) el.value = String(v ?? ''); };
    setChk('agent-identity-enabled', identity.enabled !== false);
    setChk('agent-identity-lock', identity.lock_personality !== false);
    setVal('agent-identity-persona', identity.persona || AGENT_IDENTITY_DEFAULTS.persona);
    setVal('agent-identity-tone', identity.tone || AGENT_IDENTITY_DEFAULTS.tone);
    setVal('agent-identity-risk', _identityTextFromLines(identity.risk_doctrine || AGENT_IDENTITY_DEFAULTS.risk_doctrine));
    setVal('agent-identity-rules', _identityTextFromLines(identity.immutable_rules || AGENT_IDENTITY_DEFAULTS.immutable_rules));
    _syncIdentityPresetInUI(identity);
    _refreshAgentAvatarMeta(identity);
    const version = Number(identity.version || 1);
    const verEl = document.getElementById('agent-identity-version-label');
    if (verEl) verEl.textContent = `v${Number.isFinite(version) ? version : 1}`;
    const status = document.getElementById('agent-identity-status');
    if (status) status.textContent = 'Identity ready.';
}

function getAgentIdentityFromUI() {
    const getChk = (id, fallback = false) => {
        const el = document.getElementById(id);
        return el ? !!el.checked : !!fallback;
    };
    const getVal = (id, fallback = '') => {
        const el = document.getElementById(id);
        return String(el?.value || fallback).trim();
    };
    const versionRaw = Number(agentIdentityState?.version || 1);
    const version = Number.isFinite(versionRaw) ? Math.max(1, Math.min(10000, Math.round(versionRaw))) : 1;
    return {
        enabled: getChk('agent-identity-enabled', true),
        version,
        lock_personality: getChk('agent-identity-lock', true),
        persona: getVal('agent-identity-persona', AGENT_IDENTITY_DEFAULTS.persona).slice(0, 300),
        tone: getVal('agent-identity-tone', AGENT_IDENTITY_DEFAULTS.tone).slice(0, 300),
        risk_doctrine: _identityLinesFromText(getVal('agent-identity-risk', ''), 12),
        immutable_rules: _identityLinesFromText(getVal('agent-identity-rules', ''), 12),
    };
}

async function refreshAgentIdentity(showSuccess = false) {
    if (!sessionId) {
        applyAgentIdentityToUI(AGENT_IDENTITY_DEFAULTS);
        const st = document.getElementById('agent-identity-status');
        if (st) st.textContent = 'Identity defaults loaded. Start session to fetch saved identity.';
        return { ok: false, error: 'No active session' };
    }
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/identity`);
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            const msg = String(data?.detail || data?.error || `HTTP ${res.status}`);
            const st = document.getElementById('agent-identity-status');
            if (st) st.textContent = `Identity load failed: ${msg}`;
            return { ok: false, error: msg };
        }
        applyAgentIdentityToUI(data?.identity || AGENT_IDENTITY_DEFAULTS);
        if (showSuccess) showStatus('Agent identity loaded.', 'success');
        return { ok: true, identity: data?.identity || AGENT_IDENTITY_DEFAULTS };
    } catch (err) {
        const msg = String(err?.message || err || 'identity load failed');
        const st = document.getElementById('agent-identity-status');
        if (st) st.textContent = `Identity load failed: ${msg}`;
        return { ok: false, error: msg };
    }
}

async function saveAgentIdentityFromUI(silent = false) {
    if (!sessionId) {
        if (!silent) showStatus('Start a session first, then save identity.', 'warning');
        return;
    }
    const btn = document.getElementById('btn-agent-identity-save');
    if (btn) btn.disabled = true;
    const payload = getAgentIdentityFromUI();
    if (!Array.isArray(payload.risk_doctrine) || payload.risk_doctrine.length === 0) {
        payload.risk_doctrine = AGENT_IDENTITY_DEFAULTS.risk_doctrine.slice();
    }
    if (!Array.isArray(payload.immutable_rules) || payload.immutable_rules.length === 0) {
        payload.immutable_rules = AGENT_IDENTITY_DEFAULTS.immutable_rules.slice();
    }
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/identity`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            const msg = String(data?.detail || data?.error || `HTTP ${res.status}`);
            const st = document.getElementById('agent-identity-status');
            if (st) st.textContent = `Identity save failed: ${msg}`;
            if (!silent) showStatus(`Identity save failed: ${msg}`, 'warning');
            return;
        }
        applyAgentIdentityToUI(data?.identity || payload);
        const st = document.getElementById('agent-identity-status');
        if (st) st.textContent = 'Identity saved.';
        if (!silent) showStatus('Agent identity saved.', 'success');
    } catch (err) {
        const msg = String(err?.message || err || 'identity save failed');
        const st = document.getElementById('agent-identity-status');
        if (st) st.textContent = `Identity save failed: ${msg}`;
        if (!silent) showStatus(`Identity save failed: ${msg}`, 'danger');
    } finally {
        if (btn) btn.disabled = false;
    }
}

function _consultantSessionTitle() {
    const symbol = String(document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    const tf = String(document.getElementById('sim-timeframe')?.value || 'M15').toUpperCase();
    const ts = new Date();
    const hh = String(ts.getHours()).padStart(2, '0');
    const mm = String(ts.getMinutes()).padStart(2, '0');
    return `${symbol} ${tf} ${hh}:${mm}`;
}

function _newConsultantSession() {
    const id = `cs_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    return {
        id,
        title: _consultantSessionTitle(),
        created_at: _consultantNowIso(),
        updated_at: _consultantNowIso(),
        messages: [],
    };
}

function loadConsultantSessions() {
    consultantSessions = {};
    consultantActiveSession = '';
    try {
        const rawNew = localStorage.getItem(AGENT_CHAT_STORAGE_KEY);
        const rawLegacy = localStorage.getItem(LEGACY_CONSULTANT_STORAGE_KEY);
        const raw = rawNew || rawLegacy;
        if (raw) {
            const parsed = JSON.parse(raw);
            if (parsed && typeof parsed === 'object') {
                const sessions = parsed.sessions;
                if (sessions && typeof sessions === 'object') {
                    consultantSessions = sessions;
                }
                consultantActiveSession = String(parsed.active || '');
            }
            if (!rawNew && rawLegacy) {
                try {
                    localStorage.setItem(AGENT_CHAT_STORAGE_KEY, rawLegacy);
                    localStorage.removeItem(LEGACY_CONSULTANT_STORAGE_KEY);
                } catch (_) {}
            }
        }
    } catch (_) {
        consultantSessions = {};
        consultantActiveSession = '';
    }
}

function saveConsultantSessions() {
    try {
        localStorage.setItem(
            AGENT_CHAT_STORAGE_KEY,
            JSON.stringify({
                active: consultantActiveSession,
                sessions: consultantSessions,
            }),
        );
    } catch (_) {}
}

function refreshConsultantSessionList() {
    const selectEl = document.getElementById('consultant-session-select');
    if (!selectEl) return;
    const rows = Object.values(consultantSessions || {});
    rows.sort((a, b) => String(b?.updated_at || '').localeCompare(String(a?.updated_at || '')));
    if (!rows.length) {
        const s = _newConsultantSession();
        consultantSessions[s.id] = s;
        consultantActiveSession = s.id;
    } else if (!consultantActiveSession || !consultantSessions[consultantActiveSession]) {
        consultantActiveSession = String(rows[0]?.id || '');
    }

    const html = Object.values(consultantSessions)
        .sort((a, b) => String(b?.updated_at || '').localeCompare(String(a?.updated_at || '')))
        .map((s) => {
            const id = String(s?.id || '');
            const title = escapeHtml(String(s?.title || id));
            return `<option value="${escapeHtml(id)}">${title}</option>`;
        })
        .join('');
    selectEl.innerHTML = html;
    selectEl.value = consultantActiveSession;
}

function switchConsultantSession(sessionIdLike) {
    const sid = String(sessionIdLike || '');
    if (!sid || !consultantSessions[sid]) return;
    consultantActiveSession = sid;
    renderConsultantChat();
    saveConsultantSessions();
}

function createConsultantSession() {
    const s = _newConsultantSession();
    consultantSessions[s.id] = s;
    consultantActiveSession = s.id;
    refreshConsultantSessionList();
    renderConsultantChat();
    saveConsultantSessions();
    showStatus('Consultant session created', 'success');
}

function deleteConsultantSession() {
    const sid = String(consultantActiveSession || '');
    if (!sid || !consultantSessions[sid]) return;
    const ok = window.confirm('Delete this consultant chat session?');
    if (!ok) return;
    delete consultantSessions[sid];
    const keys = Object.keys(consultantSessions);
    if (!keys.length) {
        const s = _newConsultantSession();
        consultantSessions[s.id] = s;
        consultantActiveSession = s.id;
    } else {
        consultantActiveSession = keys[0];
    }
    refreshConsultantSessionList();
    renderConsultantChat();
    saveConsultantSessions();
    showStatus('Consultant session deleted', 'info');
}

function renderConsultantChat() {
    const wrap = document.getElementById('consultant-chat-log');
    if (!wrap) return;
    const sid = String(consultantActiveSession || '');
    const session = consultantSessions[sid];
    const msgs = Array.isArray(session?.messages) ? session.messages : [];
    if (!msgs.length) {
        wrap.innerHTML = '<div class="fvg-empty">Agent is ready. Ask about setup, risk, entries, or invalidation.</div>';
        return;
    }
    const start = Math.max(0, msgs.length - 60);
    wrap.innerHTML = msgs
        .slice(start)
        .map((m, localIdx) => {
            const role = String(m?.role || 'assistant').toLowerCase() === 'user' ? 'user' : 'assistant';
            const content = escapeHtml(String(m?.content || ''));
            const idx = start + localIdx;
            const ts = String(m?.ts || '').trim();
            const tlabel = ts ? new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) : '';
            const usageMeta = role === 'assistant' ? _formatChatUsageMeta(m?.usage) : '';
            const rememberBtn = role === 'assistant'
                ? `<div class="text-end mt-1"><button class="btn btn-sm btn-outline-info py-0 px-2" data-chat-remember-idx="${idx}" type="button"><i class="bi bi-bookmark-plus"></i> Remember</button></div>`
                : '';
            const roleLabel = role === 'user' ? 'You' : 'Agent';
            const avatarIcon = role === 'user' ? 'bi-person' : 'bi-stars';
            const metaParts = [roleLabel];
            if (tlabel) metaParts.push(tlabel);
            if (usageMeta) metaParts.push(usageMeta);
            return `
                <article class="agent-chat-msg role-${role}">
                    <div class="agent-chat-msg-avatar"><i class="bi ${avatarIcon}"></i></div>
                    <div class="agent-chat-bubble">
                        ${content}
                        ${rememberBtn}
                        <div class="agent-chat-msg-meta">${escapeHtml(metaParts.join(' | '))}</div>
                    </div>
                </article>
            `;
        })
        .join('');
    wrap.scrollTop = wrap.scrollHeight;
}

function _pendingApprovalSignature(tool, args) {
    let raw = '';
    try {
        raw = JSON.stringify(args || {});
    } catch (_) {
        raw = String(args || '');
    }
    return `${String(tool || '')}|${raw}`;
}

function _approvalNum(v, decimals = 5) {
    const n = Number(v);
    if (!Number.isFinite(n)) return '';
    const p = Math.max(0, Math.min(8, Number(decimals) || 0));
    return n.toFixed(p);
}

function _approvalSemanticKey(toolLike, argsLike) {
    const tool = String(toolLike || '').trim().toLowerCase();
    const args = (argsLike && typeof argsLike === 'object') ? argsLike : {};
    if (tool === 'place_trade') {
        const dir = String(args.direction || '').trim().toUpperCase();
        const sl = _approvalNum(args.stop_loss, 5);
        const tp = _approvalNum(args.take_profit, 5);
        const lot = _approvalNum(args.lot_size, 3);
        const entry = _approvalNum(args.entry_price, 5);
        return `place_trade|${dir}|sl=${sl}|tp=${tp}|lot=${lot}|entry=${entry}`;
    }
    if (tool === 'close_trade') {
        const tid = Number(args.trade_id || 0);
        return `close_trade|trade_id=${Number.isFinite(tid) ? Math.trunc(tid) : 0}`;
    }
    return _pendingApprovalSignature(tool, args);
}

function _removePendingApprovalSiblings(referenceRow, excludeId = null) {
    const row = (referenceRow && typeof referenceRow === 'object') ? referenceRow : {};
    const refKey = String(row.semantic_key || _approvalSemanticKey(row.tool, row.args) || '');
    if (!refKey) return 0;
    const before = pendingAgentApprovals.length;
    pendingAgentApprovals = (pendingAgentApprovals || []).filter((x) => {
        const id = String(x?.id || '');
        if (excludeId && id === String(excludeId)) return true;
        const key = String(x?.semantic_key || _approvalSemanticKey(x?.tool, x?.args) || '');
        return key !== refKey;
    });
    return Math.max(0, before - pendingAgentApprovals.length);
}

function _agentTraceNowLabel() {
    try {
        return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    } catch (_) {
        return '';
    }
}

function addAgentExecutionTrace(entryLike) {
    const row = entryLike && typeof entryLike === 'object' ? entryLike : {};
    const statusRaw = String(row.status || 'EXECUTED').toUpperCase();
    const status =
        statusRaw.includes('PENDING') ? 'PENDING_APPROVAL' :
        statusRaw.includes('BLOCK') ? 'BLOCKED' :
        statusRaw.includes('ERR') ? 'ERROR' : 'EXECUTED';
    const item = {
        id: `trace_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        ts: _agentTraceNowLabel(),
        tool: String(row.tool || 'unknown'),
        source: String(row.source || 'agent'),
        status,
        details: String(row.details || '').slice(0, 500),
    };
    agentExecutionTrace.push(item);
    if (agentExecutionTrace.length > 160) {
        agentExecutionTrace = agentExecutionTrace.slice(agentExecutionTrace.length - 160);
    }
    renderAgentExecutionTrace();
}

function renderAgentExecutionTrace() {
    const wrap = document.getElementById('agent-trace-list');
    if (!wrap) return;
    const rows = Array.isArray(agentExecutionTrace) ? agentExecutionTrace : [];
    if (!rows.length) {
        wrap.innerHTML = '<div class="fvg-empty mb-0">No tool execution yet.</div>';
        return;
    }
    const out = rows.slice(-60).reverse().map((r) => {
        const statusClass =
            r.status === 'EXECUTED' ? 'executed' :
            r.status === 'PENDING_APPROVAL' ? 'pending' :
            r.status === 'BLOCKED' ? 'blocked' : 'error';
        return `
            <div class="agent-trace-item">
                <div class="top">
                    <span class="tool">${escapeHtml(String(r.tool || 'unknown'))}</span>
                    <span class="status ${statusClass}">${escapeHtml(String(r.status || ''))}</span>
                </div>
                <div class="meta">${escapeHtml(`${r.ts || ''} â€¢ ${r.source || 'agent'}${r.details ? `\n${r.details}` : ''}`)}</div>
            </div>
        `;
    }).join('');
    wrap.innerHTML = out;
}

function toggleAgentTraceWindow(forceOpen = null) {
    const el = document.getElementById('agent-trace-window');
    if (!el) return;
    const shouldShow = forceOpen === null ? el.classList.contains('d-none') : !!forceOpen;
    el.classList.toggle('d-none', !shouldShow);
    if (shouldShow) {
        const triggerEl = document.getElementById('agent-trigger-window');
        if (triggerEl) triggerEl.classList.add('d-none');
    }
}

function toggleAgentTriggerWindow(forceOpen = null) {
    const el = document.getElementById('agent-trigger-window');
    if (!el) return;
    const shouldShow = forceOpen === null ? el.classList.contains('d-none') : !!forceOpen;
    el.classList.toggle('d-none', !shouldShow);
    if (shouldShow) {
        const traceEl = document.getElementById('agent-trace-window');
        if (traceEl) traceEl.classList.add('d-none');
        void refreshAgentTriggerList(false);
    }
}

function clearAgentExecutionTrace() {
    agentExecutionTrace = [];
    renderAgentExecutionTrace();
}

function appendExecutionTraceFromToolCalls(toolCalls, sourceTag = 'agent') {
    const calls = Array.isArray(toolCalls) ? toolCalls : [];
    for (const tc of calls) {
        if (!tc || typeof tc !== 'object') continue;
        const tool = String(tc.tool_id || 'unknown').trim();
        const result = (tc.result && typeof tc.result === 'object') ? tc.result : {};
        let status = 'EXECUTED';
        if (result.requires_confirmation === true) status = 'PENDING_APPROVAL';
        else if (result.ok === false) status = String(result.error || '').includes('permission_denied') ? 'BLOCKED' : 'ERROR';
        const signature = _pendingApprovalSignature(tool, (tc.args && typeof tc.args === 'object') ? tc.args : {});
        const now = Date.now();
        if (status === 'PENDING_APPROVAL') {
            const lastTs = Number(lastPendingTraceBySignature[signature] || 0);
            if (Number.isFinite(lastTs) && (now - lastTs) < 60000) {
                continue;
            }
            lastPendingTraceBySignature[signature] = now;
        }
        const details = [
            result.error ? `error=${String(result.error)}` : '',
            (result.data && typeof result.data === 'object' && result.data.id !== undefined) ? `id=${String(result.data.id)}` : '',
        ].filter(Boolean).join(' | ');
        addAgentExecutionTrace({ tool, source: sourceTag, status, details });
    }
}

function _normalizePendingApprovalFromToolCall(tc, sourceTag = 'agent') {
    if (!tc || typeof tc !== 'object') return null;
    const result = (tc.result && typeof tc.result === 'object') ? tc.result : {};
    if (!result || result.requires_confirmation !== true) return null;
    const pending = (result.pending_action && typeof result.pending_action === 'object') ? result.pending_action : {};
    const tool = String(pending.tool || tc.tool_id || '').trim();
    if (!tool) return null;
    const args = (pending.args && typeof pending.args === 'object') ? pending.args : {};
    const signature = _pendingApprovalSignature(tool, args);
    const semanticKey = _approvalSemanticKey(tool, args);
    return {
        id: `pa_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
        signature,
        semantic_key: semanticKey,
        tool,
        args,
        message: String(pending.message || result.error || 'Action requires approval.'),
        source: String(sourceTag || 'agent'),
        created_at: _consultantNowIso(),
    };
}

function ingestPendingApprovalsFromToolCalls(toolCalls, sourceTag = 'agent') {
    const calls = Array.isArray(toolCalls) ? toolCalls : [];
    if (!calls.length) return 0;
    let added = 0;
    const seen = new Set((pendingAgentApprovals || []).map((x) => String(x.signature || '')));
    const seenSemantic = new Set((pendingAgentApprovals || []).map((x) => String(x.semantic_key || _approvalSemanticKey(x.tool, x.args) || '')));
    for (const tc of calls) {
        const row = _normalizePendingApprovalFromToolCall(tc, sourceTag);
        if (!row) continue;
        if (seen.has(row.signature)) continue;
        if (row.semantic_key && seenSemantic.has(row.semantic_key)) {
            pendingAgentApprovals = pendingAgentApprovals.filter((x) => String(x.semantic_key || _approvalSemanticKey(x.tool, x.args) || '') !== String(row.semantic_key));
        }
        seen.add(row.signature);
        if (row.semantic_key) seenSemantic.add(row.semantic_key);
        pendingAgentApprovals.push(row);
        added += 1;
    }
    if (added > 0) {
        renderPendingAgentApprovals();
        showStatus(`Agent requested ${added} approval${added !== 1 ? 's' : ''}.`, 'warning');
    }
    return added;
}

function _rememberWatchdogApprovalSignature(signature) {
    const sig = String(signature || '').trim();
    if (!sig) return;
    seenWatchdogApprovalSignatures[sig] = Date.now();
    const keys = Object.keys(seenWatchdogApprovalSignatures);
    if (keys.length > 600) {
        const stale = keys
            .map((k) => [k, Number(seenWatchdogApprovalSignatures[k] || 0)])
            .sort((a, b) => a[1] - b[1])
            .slice(0, keys.length - 500);
        for (const [k] of stale) delete seenWatchdogApprovalSignatures[k];
    }
}

function ingestPendingApprovalsFromWatchdogEvents(eventsLike) {
    const events = Array.isArray(eventsLike) ? eventsLike : [];
    if (!events.length) return 0;
    let added = 0;
    const seen = new Set((pendingAgentApprovals || []).map((x) => String(x.signature || '')));
    for (const ev of events) {
        if (!ev || typeof ev !== 'object') continue;
        const et = String(ev.event_type || '').toUpperCase();
        if (et === 'WATCHDOG_DECISION_TIMEOUT') {
            const payload = (ev.payload && typeof ev.payload === 'object') ? ev.payload : {};
            const tradeId = Number(payload.trade_id || 0);
            if (Number.isFinite(tradeId) && tradeId > 0) {
                const before = pendingAgentApprovals.length;
                pendingAgentApprovals = pendingAgentApprovals.filter((row) => {
                    const tool = String(row?.tool || '').toLowerCase();
                    const rid = Number(row?.args?.trade_id || 0);
                    return !(tool === 'close_trade' && rid === tradeId && String(row?.source || '').includes('watchdog'));
                });
                if (pendingAgentApprovals.length !== before) {
                    const st = String(payload.status || '').trim();
                    _consultantAppendMessage('assistant', `Watchdog timeout result for trade #${tradeId}: ${st || 'resolved'}.`);
                }
            }
            continue;
        }
        if (et !== 'WATCHDOG_MODEL_REVIEW' && et !== 'WATCHDOG_ENTRY_PENDING') continue;
        const payload = (ev.payload && typeof ev.payload === 'object') ? ev.payload : {};
        const pending = (payload.pending_action && typeof payload.pending_action === 'object') ? payload.pending_action : {};
        const tool = String(pending.tool || '').trim().toLowerCase();
        if (tool !== 'close_trade' && tool !== 'place_trade') continue;
        const args = (pending.args && typeof pending.args === 'object') ? pending.args : {};
        const tradeId = Number(args.trade_id || 0);
        if (tool === 'close_trade' && (!Number.isFinite(tradeId) || tradeId <= 0)) continue;
        const eventId = Number(ev.id || 0);
        const decisionId = String(payload.decision_id || '').trim();
        const triggerId = String(payload.trigger_id || '').trim();
        const sig = decisionId
            ? `watchdog_decision:${decisionId}`
            : (triggerId
                ? `watchdog_entry:${triggerId}:${tool}`
                : `watchdog:${eventId > 0 ? eventId : String(ev.created_at || '')}:${tool}:${tradeId}`);
        if (seen.has(sig) || seenWatchdogApprovalSignatures[sig]) continue;
        if (tool === 'close_trade') {
            const duplicateTradePending = pendingAgentApprovals.some((row) =>
                String(row?.source || '').includes('watchdog')
                && String(row?.tool || '').toLowerCase() === 'close_trade'
                && Number(row?.args?.trade_id || 0) === tradeId
                && !row?._timeout_handled
            );
            if (duplicateTradePending) continue;
        } else {
            const k = _approvalSemanticKey(tool, args);
            const duplicateEntryPending = pendingAgentApprovals.some((row) =>
                String(row?.source || '').includes('watchdog')
                && String(row?.tool || '').toLowerCase() === 'place_trade'
                && String(row?.semantic_key || _approvalSemanticKey(row?.tool, row?.args) || '') === String(k || '')
                && !row?._timeout_handled
            );
            if (duplicateEntryPending) continue;
        }
        const createdAt = String(ev.created_at || '').trim();
        const createdMs = createdAt ? Date.parse(createdAt) : Date.now();
        const rawWin = Number(payload.decision_window_sec || 0);
        const decisionWindowSec = Number.isFinite(rawWin) && rawWin > 0
            ? Math.max(10, Math.min(600, rawWin))
            : null;
        const deadlineMs = decisionWindowSec !== null
            ? (Number.isFinite(createdMs) ? createdMs : Date.now()) + (decisionWindowSec * 1000)
            : null;
        const recommendation = String(payload.recommendation || 'HOLD').toUpperCase();
        const summary = String(payload.message || pending.message || 'Watchdog review triggered a trade-risk decision.');
        const autoDecisionRaw = String(payload.auto_decision || '').toLowerCase();
        const autoDecision = autoDecisionRaw === 'approve' ? 'approve' : 'cancel';
        pendingAgentApprovals.push({
            id: `pa_wd_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
            signature: sig,
            semantic_key: _approvalSemanticKey(tool, args),
            tool,
            args,
            message: `Watchdog -> Apprentice: ${recommendation}. ${summary}`,
            source: 'watchdog_model_review',
            created_at: createdAt || _consultantNowIso(),
            deadline_ms: decisionWindowSec !== null ? deadlineMs : null,
            decision_window_sec: decisionWindowSec,
            auto_decision: autoDecision,
            decision_id: decisionId || null,
            trigger_id: triggerId || null,
        });
        _consultantAppendMessage(
            'assistant',
            tool === 'close_trade'
                ? `Watchdog report received for apprentice: ${recommendation} on trade #${tradeId}.`
                : `Watchdog conditional-entry trigger fired for apprentice: ${recommendation}.`,
        );
        _rememberWatchdogApprovalSignature(sig);
        seen.add(sig);
        added += 1;
    }
    if (added > 0) {
        renderPendingAgentApprovals();
        renderConsultantChat();
        saveConsultantSessions();
        ensurePendingApprovalTimer();
        showStatus(`Watchdog requested ${added} timed approval${added !== 1 ? 's' : ''} for apprentice decision.`, 'warning');
    } else {
        renderPendingAgentApprovals();
        renderConsultantChat();
        saveConsultantSessions();
    }
    return added;
}

function _approvalRemainingSec(row) {
    const dl = Number(row?.deadline_ms || 0);
    if (!Number.isFinite(dl) || dl <= 0) return null;
    return Math.max(0, Math.ceil((dl - Date.now()) / 1000));
}

function ensurePendingApprovalTimer() {
    if (pendingApprovalTimer) return;
    pendingApprovalTimer = setInterval(() => {
        void processPendingApprovalTimeouts();
    }, 1000);
}

function stopPendingApprovalTimer() {
    if (!pendingApprovalTimer) return;
    clearInterval(pendingApprovalTimer);
    pendingApprovalTimer = null;
}

async function processPendingApprovalTimeouts() {
    if (pendingApprovalTimeoutBusy) return;
    pendingApprovalTimeoutBusy = true;
    try {
        if (!Array.isArray(pendingAgentApprovals) || pendingAgentApprovals.length === 0) {
            stopPendingApprovalTimer();
            return;
        }
        const now = Date.now();
        const expired = pendingAgentApprovals
            .filter((row) => {
                const dl = Number(row?.deadline_ms || 0);
                if (!Number.isFinite(dl) || dl <= 0) return false;
                if (row?._timeout_handled) return false;
                return now >= dl;
            })
            .map((row) => String(row.id || ''))
            .filter(Boolean);
        for (const id of expired) {
            const idx = pendingAgentApprovals.findIndex((x) => String(x?.id || '') === id);
            if (idx < 0) continue;
            const row = pendingAgentApprovals[idx];
            row._timeout_handled = true;
            if (String(row?.source || '').includes('watchdog')) {
                // Backend watchdog executes timeout fallback; keep row visible until timeout event arrives.
                continue;
            }
            const decision = String(row.auto_decision || 'cancel').toLowerCase();
            if (decision === 'approve') {
                await approvePendingAgentApproval(id, { autoTimeout: true });
            } else {
                cancelPendingAgentApproval(id, { autoTimeout: true });
            }
        }
        renderPendingAgentApprovals();
    } finally {
        pendingApprovalTimeoutBusy = false;
    }
}

function renderPendingAgentApprovals() {
    const wrap = document.getElementById('agent-approval-list');
    if (!wrap) return;
    const rows = Array.isArray(pendingAgentApprovals) ? pendingAgentApprovals : [];
    if (!rows.length) {
        wrap.innerHTML = '<div class="fvg-empty mb-0">No pending trade approvals.</div>';
        renderInlinePendingApproval();
        stopPendingApprovalTimer();
        return;
    }
    wrap.innerHTML = rows.map((r) => {
        const id = escapeHtml(String(r.id || ''));
        const tool = String(r.tool || '').toLowerCase();
        const args = (r.args && typeof r.args === 'object') ? r.args : {};
        const title = tool === 'place_trade' ? 'Trade Entry Approval' : (tool === 'close_trade' ? 'Trade Exit Approval' : 'Action Approval');
        let meta = '';
        if (tool === 'place_trade') {
            meta = `Direction: ${String(args.direction || '-').toUpperCase()}\nEntry: ${args.entry_price ?? 'market'}\nSL: ${args.stop_loss ?? '-'}\nTP: ${args.take_profit ?? '-'}\nLot: ${args.lot_size ?? '0.01'}`;
        } else if (tool === 'close_trade') {
            meta = `Trade ID: ${args.trade_id ?? '-'}\nExit: ${args.exit_price ?? 'market'}`;
        } else {
            meta = String(r.message || '');
        }
        const rem = _approvalRemainingSec(r);
        if (rem !== null) {
            if (rem > 0) meta += `\nDecision window: ${rem}s`;
            else if (String(r?.source || '').includes('watchdog')) meta += `\nDecision window elapsed: awaiting backend auto-decision...`;
            else meta += `\nDecision window: 0s`;
        }
        return `
            <div class="agent-approval-item">
                <div class="title">${escapeHtml(title)}</div>
                <div class="meta">${escapeHtml(meta)}</div>
                <div class="agent-approval-actions">
                    <button class="btn btn-sm btn-success" data-approval-action="approve" data-approval-id="${id}" type="button">
                        <i class="bi bi-check2-circle me-1"></i>Approve
                    </button>
                    <button class="btn btn-sm btn-outline-danger" data-approval-action="cancel" data-approval-id="${id}" type="button">
                        <i class="bi bi-x-circle me-1"></i>Cancel
                    </button>
                </div>
            </div>
        `;
    }).join('');
    renderInlinePendingApproval();
    ensurePendingApprovalTimer();
}

function renderInlinePendingApproval() {
    const box = document.getElementById('agent-inline-approval');
    const metaEl = document.getElementById('agent-inline-approval-meta');
    const approveBtn = document.getElementById('btn-inline-approval-approve');
    const cancelBtn = document.getElementById('btn-inline-approval-cancel');
    if (!box || !metaEl || !approveBtn || !cancelBtn) return;
    const rows = Array.isArray(pendingAgentApprovals) ? pendingAgentApprovals : [];
    if (!rows.length) {
        box.classList.add('d-none');
        approveBtn.setAttribute('data-approval-id', '');
        cancelBtn.setAttribute('data-approval-id', '');
        metaEl.textContent = '';
        return;
    }
    const row = rows[rows.length - 1];
    const tool = String(row?.tool || '').toLowerCase();
    const args = (row?.args && typeof row.args === 'object') ? row.args : {};
    let meta = '';
    if (tool === 'place_trade') {
        meta = `Direction: ${String(args.direction || '-').toUpperCase()}\nEntry: ${args.entry_price ?? 'market'}\nSL: ${args.stop_loss ?? '-'}\nTP: ${args.take_profit ?? '-'}\nLot: ${args.lot_size ?? '0.01'}`;
    } else if (tool === 'close_trade') {
        meta = `Trade ID: ${args.trade_id ?? '-'}\nExit: ${args.exit_price ?? 'market'}`;
    } else {
        meta = String(row?.message || 'Action requires approval.');
    }
    const rem = _approvalRemainingSec(row);
    if (rem !== null) {
        if (rem > 0) meta += `\nDecision window: ${rem}s`;
        else if (String(row?.source || '').includes('watchdog')) meta += `\nDecision window elapsed: awaiting backend auto-decision...`;
        else meta += `\nDecision window: 0s`;
    }
    metaEl.textContent = meta;
    approveBtn.setAttribute('data-approval-id', String(row?.id || ''));
    cancelBtn.setAttribute('data-approval-id', String(row?.id || ''));
    box.classList.remove('d-none');
}

async function approvePendingAgentApproval(approvalIdLike, opts = {}) {
    const approvalId = String(approvalIdLike || '').trim();
    if (!approvalId || !sessionId) return;
    const autoTimeout = !!opts?.autoTimeout;
    const idx = pendingAgentApprovals.findIndex((x) => String(x?.id || '') === approvalId);
    if (idx < 0) return;
    const row = pendingAgentApprovals[idx];
    const tool = String(row.tool || '').toLowerCase();
    const args = (row.args && typeof row.args === 'object') ? row.args : {};

    if (tool === 'place_trade') {
        const body = {
            direction: String(args.direction || '').toUpperCase(),
            stop_loss: Number(args.stop_loss),
            take_profit: (args.take_profit === null || args.take_profit === undefined || args.take_profit === '') ? null : Number(args.take_profit),
            lot_size: Number(args.lot_size || 0.01),
            entry_price: (args.entry_price === null || args.entry_price === undefined || args.entry_price === '') ? null : Number(args.entry_price),
            bar_time_unix: (args.bar_time_unix === null || args.bar_time_unix === undefined || args.bar_time_unix === '') ? null : Number(args.bar_time_unix),
            cost_spread: (args.cost_spread === null || args.cost_spread === undefined || args.cost_spread === '') ? null : Number(args.cost_spread),
            cost_tc_rate: (args.cost_tc_rate === null || args.cost_tc_rate === undefined || args.cost_tc_rate === '') ? null : Number(args.cost_tc_rate),
            cost_spread_source: args.cost_spread_source ? String(args.cost_spread_source) : null,
        };
        if (!['BUY', 'SELL'].includes(body.direction) || !Number.isFinite(Number(body.stop_loss))) {
            showStatus('Approval payload is invalid for trade entry.', 'danger');
            return;
        }
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/trade`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.error) {
            showStatus(`Approval execution failed: ${data?.error || data?.detail || res.status}`, 'danger');
            addAgentExecutionTrace({
                tool: 'place_trade',
                source: 'approval',
                status: 'ERROR',
                details: String(data?.error || data?.detail || `HTTP ${res.status}`),
            });
            return;
        }
        updateOpenPosition(data, 0);
        renderCostModelSummary(data?.cost_breakdown || null);
        _consultantAppendMessage('assistant', `${autoTimeout ? 'Auto-timeout approved and executed' : 'Approved and executed'}: ${body.direction} trade (id=${data?.id ?? 'n/a'}).`);
        renderConsultantChat();
        saveConsultantSessions();
        showStatus(autoTimeout ? 'Timeout fallback executed trade approval.' : 'Approved trade executed.', 'success');
        addAgentExecutionTrace({
            tool: 'place_trade',
            source: 'approval',
            status: 'EXECUTED',
            details: `trade_id=${String(data?.id ?? 'n/a')}`,
        });
    } else if (tool === 'close_trade') {
        const tradeId = Number(args.trade_id || 0);
        if (!Number.isFinite(tradeId) || tradeId <= 0) {
            showStatus('Approval payload is invalid for trade close.', 'danger');
            return;
        }
        const body = {
            exit_price: (args.exit_price === null || args.exit_price === undefined || args.exit_price === '') ? null : Number(args.exit_price),
            bar_time_unix: (args.bar_time_unix === null || args.bar_time_unix === undefined || args.bar_time_unix === '') ? null : Number(args.bar_time_unix),
            cost_spread: (args.cost_spread === null || args.cost_spread === undefined || args.cost_spread === '') ? null : Number(args.cost_spread),
            cost_tc_rate: (args.cost_tc_rate === null || args.cost_tc_rate === undefined || args.cost_tc_rate === '') ? null : Number(args.cost_tc_rate),
            cost_spread_source: args.cost_spread_source ? String(args.cost_spread_source) : null,
        };
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/close-trade/${tradeId}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.error) {
            const detailText = String(data?.error || data?.detail || '').toLowerCase();
            if (res.status === 404 && (detailText.includes('trade not found') || detailText.includes('not found in this session'))) {
                pendingAgentApprovals.splice(idx, 1);
                _removePendingApprovalSiblings(row, null);
                renderPendingAgentApprovals();
                _consultantAppendMessage('assistant', `Close request resolved: trade #${tradeId} is no longer open.`);
                renderConsultantChat();
                saveConsultantSessions();
                showStatus(`Trade #${tradeId} was already closed or unavailable.`, 'info');
                addAgentExecutionTrace({
                    tool: 'close_trade',
                    source: 'approval',
                    status: 'BLOCKED',
                    details: 'trade_already_closed_or_missing',
                });
                return;
            }
            showStatus(`Approval execution failed: ${data?.error || data?.detail || res.status}`, 'danger');
            addAgentExecutionTrace({
                tool: 'close_trade',
                source: 'approval',
                status: 'ERROR',
                details: String(data?.error || data?.detail || `HTTP ${res.status}`),
            });
            return;
        }
        updateOpenPosition(null);
        addTradeToLog(data);
        showTradeResult(data);
        _consultantAppendMessage('assistant', `${autoTimeout ? 'Auto-timeout approved and executed' : 'Approved and executed'}: close trade #${tradeId}.`);
        renderConsultantChat();
        saveConsultantSessions();
        showStatus(autoTimeout ? 'Timeout fallback executed trade close.' : 'Approved trade close executed.', 'success');
        addAgentExecutionTrace({
            tool: 'close_trade',
            source: 'approval',
            status: 'EXECUTED',
            details: `trade_id=${String(tradeId)}`,
        });
    } else {
        showStatus(`Unsupported approval tool: ${tool}`, 'warning');
        addAgentExecutionTrace({
            tool,
            source: 'approval',
            status: 'ERROR',
            details: 'unsupported approval tool',
        });
        return;
    }

    pendingAgentApprovals.splice(idx, 1);
    _removePendingApprovalSiblings(row, null);
    renderPendingAgentApprovals();
}

function cancelPendingAgentApproval(approvalIdLike, opts = {}) {
    const approvalId = String(approvalIdLike || '').trim();
    if (!approvalId) return;
    const autoTimeout = !!opts?.autoTimeout;
    const idx = pendingAgentApprovals.findIndex((x) => String(x?.id || '') === approvalId);
    if (idx < 0) return;
    const row = pendingAgentApprovals[idx];
    pendingAgentApprovals.splice(idx, 1);
    _removePendingApprovalSiblings(row, null);
    renderPendingAgentApprovals();
    _consultantAppendMessage('assistant', `${autoTimeout ? 'Auto-timeout decision: continue/hold' : 'Approval cancelled'} for ${String(row.tool || 'action')}.`);
    addAgentExecutionTrace({
        tool: String(row.tool || 'action'),
        source: 'approval',
        status: 'BLOCKED',
        details: 'cancelled by user',
    });
    renderConsultantChat();
    saveConsultantSessions();
    showStatus(autoTimeout ? 'Timeout fallback kept position open.' : 'Approval cancelled.', 'info');
}

async function onAgentApprovalListClick(event) {
    const btn = event.target?.closest?.('button[data-approval-action]');
    if (!btn) return;
    const action = String(btn.getAttribute('data-approval-action') || '').trim().toLowerCase();
    const id = String(btn.getAttribute('data-approval-id') || '').trim();
    if (!action || !id) return;
    btn.disabled = true;
    try {
        if (action === 'approve') {
            await approvePendingAgentApproval(id);
        } else if (action === 'cancel') {
            cancelPendingAgentApproval(id);
        }
    } finally {
        btn.disabled = false;
    }
}

function _normalizeChatUsage(rawLike, providerLike = '', modelLike = '') {
    const raw = (rawLike && typeof rawLike === 'object') ? rawLike : {};
    const totalTokens = Number(raw.total_tokens || 0);
    const inputTokens = Number(raw.input_tokens || 0);
    const outputTokens = Number(raw.output_tokens || 0);
    const estimatedCost = Number(raw.estimated_cost_usd || 0);
    const apiCalls = Number(raw.api_calls || 0);
    const provider = String(raw.provider || providerLike || '').trim();
    const model = String(raw.model || modelLike || '').trim();
    const hasAny = Number.isFinite(totalTokens) || Number.isFinite(inputTokens) || Number.isFinite(outputTokens) || Number.isFinite(estimatedCost);
    if (!hasAny) return null;
    return {
        total_tokens: Number.isFinite(totalTokens) ? Math.max(0, Math.round(totalTokens)) : 0,
        input_tokens: Number.isFinite(inputTokens) ? Math.max(0, Math.round(inputTokens)) : 0,
        output_tokens: Number.isFinite(outputTokens) ? Math.max(0, Math.round(outputTokens)) : 0,
        estimated_cost_usd: Number.isFinite(estimatedCost) ? Math.max(0, estimatedCost) : 0,
        api_calls: Number.isFinite(apiCalls) ? Math.max(0, Math.round(apiCalls)) : 0,
        provider,
        model,
    };
}

function _formatChatUsageMeta(rawLike) {
    const u = (rawLike && typeof rawLike === 'object') ? rawLike : null;
    if (!u) return '';
    const tok = Number(u.total_tokens || 0);
    const usd = Number(u.estimated_cost_usd || 0);
    const provider = String(u.provider || '').trim();
    const model = String(u.model || '').trim();
    const modelLabel = provider ? `${provider}${model ? `/${model}` : ''}` : '';
    const tokLabel = `${Math.max(0, Math.round(tok)).toLocaleString()} tok`;
    const usdLabel = `$${Math.max(0, usd).toFixed(4)}`;
    return `${tokLabel} | ${usdLabel}${modelLabel ? ` | ${modelLabel}` : ''}`;
}

function _consultantAppendMessage(role, content, opts = null) {
    const sid = String(consultantActiveSession || '');
    if (!sid || !consultantSessions[sid]) return;
    const safeRole = String(role || '').toLowerCase() === 'user' ? 'user' : 'assistant';
    const text = String(content || '').trim();
    if (!text) return;
    const session = consultantSessions[sid];
    if (!Array.isArray(session.messages)) session.messages = [];
    const usage = _normalizeChatUsage(opts?.usage, opts?.provider, opts?.model);
    const row = {
        role: safeRole,
        content: text,
        ts: _consultantNowIso(),
    };
    if (usage && safeRole === 'assistant') {
        row.usage = usage;
    }
    session.messages.push(row);
    session.updated_at = _consultantNowIso();
}

function _latestFinite(values) {
    if (!Array.isArray(values) || values.length === 0) return null;
    for (let i = values.length - 1; i >= 0; i -= 1) {
        const v = Number(values[i]);
        if (Number.isFinite(v)) return v;
    }
    return null;
}

function buildCompactIndicatorSnapshot() {
    const cacheKey = `${Number(allBars?.length || 0)}:${Number(currentBar || 0)}:${Number(allBars?.[allBars.length - 1]?.time || 0)}`;
    if (compactIndicatorSnapshotCacheKey === cacheKey && compactIndicatorSnapshotCacheValue && typeof compactIndicatorSnapshotCacheValue === 'object') {
        return { ...compactIndicatorSnapshotCacheValue };
    }
    const visible = getVisibleBarsForIndicators();
    if (!Array.isArray(visible) || visible.length < 20) return {};
    const bars = visible.slice(-300).map((b) => ({
        time: Number(b?.time || 0),
        open: Number(b?.open || 0),
        high: Number(b?.high || 0),
        low: Number(b?.low || 0),
        close: Number(b?.close || 0),
        volume: Number(b?.volume || 0),
    }));
    const fullSel = { smaEma: true, adx: true, rsi: true, stoch: true, bollinger: true, goldenCross: true };
    const pack = computeIndicatorPack(bars, fullSel);
    const out = {
        timeframe: String(document.getElementById('sim-timeframe')?.value || '').toUpperCase(),
        at_time: Number(bars[bars.length - 1]?.time || 0),
        sma20: _latestFinite(pack?.sma20),
        sma50: _latestFinite(pack?.sma50),
        sma200: _latestFinite(pack?.sma200),
        ema20: _latestFinite(pack?.ema20),
        ema50: _latestFinite(pack?.ema50),
        ema200: _latestFinite(pack?.ema200),
        bb_upper: _latestFinite(pack?.bbUpper),
        bb_mid: _latestFinite(pack?.bbMid),
        bb_lower: _latestFinite(pack?.bbLower),
        adx: _latestFinite(pack?.adx),
        rsi: _latestFinite(pack?.rsi),
        stoch_k: _latestFinite(pack?.stochK),
        stoch_d: _latestFinite(pack?.stochD),
    };
    compactIndicatorSnapshotCacheKey = cacheKey;
    compactIndicatorSnapshotCacheValue = { ...out };
    return out;
}

function buildConsultantContext() {
    const mode = getWorkbenchMode();
    const symbol = String(document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    const timeframe = String(document.getElementById('sim-timeframe')?.value || 'M15').toUpperCase();
    const visible = getVisibleBarsForIndicators();
    const recentBars = (Array.isArray(visible) ? visible : []).slice(-80).map((b) => ({
        time: Number(b.time || 0),
        open: Number(b.open || 0),
        high: Number(b.high || 0),
        low: Number(b.low || 0),
        close: Number(b.close || 0),
        volume: Number(b.volume || 0),
    }));
    const fullSel = { smaEma: true, adx: true, rsi: true, stoch: true, bollinger: true, goldenCross: true };
    const pack = recentBars.length ? computeIndicatorPack(recentBars, fullSel) : null;
    const indicatorsLatest = pack ? {
        sma20: _latestFinite(pack.sma20),
        sma50: _latestFinite(pack.sma50),
        sma200: _latestFinite(pack.sma200),
        ema20: _latestFinite(pack.ema20),
        ema50: _latestFinite(pack.ema50),
        ema200: _latestFinite(pack.ema200),
        bb_upper: _latestFinite(pack.bbUpper),
        bb_mid: _latestFinite(pack.bbMid),
        bb_lower: _latestFinite(pack.bbLower),
        adx: _latestFinite(pack.adx),
        rsi: _latestFinite(pack.rsi),
        stoch_k: _latestFinite(pack.stochK),
        stoch_d: _latestFinite(pack.stochD),
    } : {};

    const sessionStats = {
        initial_balance: Number(initialBalance || 0),
        current_balance: Number(String(document.getElementById('stat-balance')?.textContent || '').replace(/[^0-9+-.]/g, '')) || null,
        total_pnl: Number(String(document.getElementById('stat-pnl')?.textContent || '').replace(/[^0-9+-.]/g, '')) || null,
        trades_count: Number(String(document.getElementById('stat-trades')?.textContent || '').replace(/[^0-9+-.]/g, '')) || null,
        wins: null,
        losses: null,
    };

    return {
        mode,
        session: {
            id: sessionId,
            symbol,
            timeframe,
            current_bar: Number(currentBar || 0),
            total_bars: Number(totalBars || 0),
            live_feed_active: !!liveFeedActive,
            live_feed_requested: !!liveFeedRequested,
            transport_mode: String(transportMode || 'IDLE'),
        },
        stats: {
            balance: String(document.getElementById('stat-balance')?.textContent || ''),
            pnl: String(document.getElementById('stat-pnl')?.textContent || ''),
            trades: String(document.getElementById('stat-trades')?.textContent || ''),
            win_rate: String(document.getElementById('stat-winrate')?.textContent || ''),
            speed: String(document.getElementById('stat-barsps')?.textContent || ''),
        },
        indicators: {
            enabled: { ...indicatorSelection },
            latest: indicatorsLatest,
        },
        bars: recentBars,
        session_stats: sessionStats,
        open_positions: [],
        recent_trades: [],
        metadata: {
            mode,
            transport_mode: String(transportMode || 'IDLE'),
        },
        identity: getAgentIdentityFromUI(),
        tool_state: getToolStatePayload(),
    };
}

function getAgentProviderConfig() {
    const providerEl = document.getElementById('consultant-provider');
    const modelEl = document.getElementById('consultant-model');
    const urlEl = document.getElementById('consultant-url');
    const keyEl = document.getElementById('consultant-api-key');
    const timeoutEl = document.getElementById('agent-timeout');
    const provider = String(providerEl?.value || 'deterministic');
    const model = String(modelEl?.value || '').trim() || null;
    const llmUrl = String(urlEl?.value || '').trim() || null;
    const apiKey = String(keyEl?.value || '').trim() || null;
    const timeoutSecRaw = Number(timeoutEl?.value || 45);
    const timeoutSec = Number.isFinite(timeoutSecRaw) ? Math.max(10, Math.min(600, Math.round(timeoutSecRaw))) : 45;
    return {
        provider,
        model_label: model,
        llm_url: llmUrl,
        api_key: apiKey,
        timeout_sec: timeoutSec,
    };
}

function getAgentRecommendedMaxToolSteps(mode = 'chat') {
    const provider = String(document.getElementById('consultant-provider')?.value || 'deterministic').trim().toLowerCase();
    const externalProvider = provider === 'claude' || provider === 'openai_compat';
    if (mode === 'run_once') {
        return externalProvider ? 6 : 4;
    }
    return externalProvider ? 10 : 3;
}

function getAgentWatchdogConfigFromUI() {
    const modeEl = document.getElementById('agent-watchdog-mode');
    const intervalEl = document.getElementById('agent-watchdog-interval');
    const llmIntervalEl = document.getElementById('agent-watchdog-llm-interval');
    const triggerApprovalEl = document.getElementById('agent-watchdog-trigger-require-approval');
    const guardrailEnabledEl = document.getElementById('agent-guardrail-enabled');
    const sessionFilterEl = document.getElementById('agent-guardrail-session-filter');
    const newsFilterEl = document.getElementById('agent-guardrail-news-filter');
    const newsLookbackEl = document.getElementById('agent-guardrail-news-lookback');
    const newsProviderEl = document.getElementById('agent-news-provider');
    const newsLlmSummaryEl = document.getElementById('agent-news-llm-summary');
    const newsSummaryModelEl = document.getElementById('agent-news-summary-model');
    const newsIbkrHostEl = document.getElementById('agent-news-ibkr-host');
    const newsIbkrPortEl = document.getElementById('agent-news-ibkr-port');
    const modeRaw = String(modeEl?.value || 'deterministic').trim().toLowerCase();
    const mode = ['deterministic', 'local_gptoss_http', 'claude'].includes(modeRaw) ? modeRaw : 'deterministic';
    const intervalRaw = Number(intervalEl?.value || 30);
    const intervalSec = Number.isFinite(intervalRaw) ? Math.max(5, Math.min(300, Math.round(intervalRaw))) : 30;
    const llmIntervalRaw = Number(llmIntervalEl?.value || 180);
    const llmMinIntervalSec = Number.isFinite(llmIntervalRaw) ? Math.max(10, Math.min(3600, Math.round(llmIntervalRaw))) : 180;
    const newsLookbackRaw = Number(newsLookbackEl?.value || 120);
    const newsLookbackMin = Number.isFinite(newsLookbackRaw) ? Math.max(15, Math.min(1440, Math.round(newsLookbackRaw))) : 120;
    const newsProviderRaw = String(newsProviderEl?.value || 'polygon').trim().toLowerCase();
    const newsProvider = ['polygon', 'ibkr'].includes(newsProviderRaw) ? newsProviderRaw : 'polygon';
    const newsSummaryModel = String(newsSummaryModelEl?.value || '').trim() || 'claude-haiku-4-5-20251001';
    const newsIbkrHost = String(newsIbkrHostEl?.value || '').trim() || '127.0.0.1';
    const newsIbkrPortRaw = Number(newsIbkrPortEl?.value || 7497);
    const newsIbkrPort = Number.isFinite(newsIbkrPortRaw) ? Math.max(1, Math.min(65535, Math.round(newsIbkrPortRaw))) : 7497;
    const out = {
        watchdog_mode: mode,
        watchdog_interval_sec: intervalSec,
        watchdog_llm_min_interval_sec: llmMinIntervalSec,
        watchdog_trigger_requires_approval: Boolean(triggerApprovalEl?.checked),
        guardrail_enabled: Boolean(guardrailEnabledEl?.checked),
        guardrail_session_filter_enabled: Boolean(sessionFilterEl?.checked),
        guardrail_news_filter_enabled: Boolean(newsFilterEl?.checked),
        guardrail_news_lookback_min: newsLookbackMin,
        market_news_provider: newsProvider,
        market_news_llm_summary_enabled: Boolean(newsLlmSummaryEl?.checked),
        market_news_summary_model: newsSummaryModel,
        market_news_ibkr_host: newsIbkrHost,
        market_news_ibkr_port: newsIbkrPort,
    };
    if (mode !== 'deterministic') {
        const providerCfg = getAgentProviderConfig();
        if (mode === String(providerCfg?.provider || '').trim().toLowerCase()) {
            const m = String(providerCfg?.model_label || '').trim();
            const u = String(providerCfg?.llm_url || '').trim();
            if (m) out.watchdog_model_label = m;
            if (u) out.watchdog_llm_url = u;
        } else if (mode === 'claude') {
            out.watchdog_model_label = 'claude-sonnet-4-5-20250929';
        } else if (mode === 'local_gptoss_http') {
            out.watchdog_model_label = 'gpt-oss-20b';
        }
    }
    return out;
}

function syncAgentGuardrailControls() {
    const guardrailEnabledEl = document.getElementById('agent-guardrail-enabled');
    const sessionFilterEl = document.getElementById('agent-guardrail-session-filter');
    const newsFilterEl = document.getElementById('agent-guardrail-news-filter');
    const newsLookbackEl = document.getElementById('agent-guardrail-news-lookback');
    const statusEl = document.getElementById('agent-guardrail-effective-status');
    const guardrailsEnabled = !!guardrailEnabledEl?.checked;
    const sessionEnabled = !!sessionFilterEl?.checked;
    const newsEnabled = !!newsFilterEl?.checked;
    if (sessionFilterEl) sessionFilterEl.disabled = !guardrailsEnabled;
    if (newsFilterEl) newsFilterEl.disabled = !guardrailsEnabled;
    if (newsLookbackEl) newsLookbackEl.disabled = !guardrailsEnabled || !Boolean(newsFilterEl?.checked);
    if (statusEl) {
        if (!guardrailsEnabled) {
            statusEl.textContent = 'Guardrails OFF: execution filters are bypassed.';
            statusEl.style.color = '#fca5a5';
        } else if (!sessionEnabled && !newsEnabled) {
            statusEl.textContent = 'Guardrails ON, but no child filters selected (no execution blocking active).';
            statusEl.style.color = '#fcd34d';
        } else if (sessionEnabled && newsEnabled) {
            statusEl.textContent = 'Guardrails ON: Session Filter + News Filter active.';
            statusEl.style.color = '#86efac';
        } else if (sessionEnabled) {
            statusEl.textContent = 'Guardrails ON: Session Filter active.';
            statusEl.style.color = '#93c5fd';
        } else {
            statusEl.textContent = 'Guardrails ON: News Filter active.';
            statusEl.style.color = '#93c5fd';
        }
    }
}

function syncAgentNewsProviderControls() {
    const providerEl = document.getElementById('agent-news-provider');
    const llmSummaryEl = document.getElementById('agent-news-llm-summary');
    const summaryModelEl = document.getElementById('agent-news-summary-model');
    const ibkrHostEl = document.getElementById('agent-news-ibkr-host');
    const ibkrPortEl = document.getElementById('agent-news-ibkr-port');
    const ibkrHostWrap = ibkrHostEl ? ibkrHostEl.closest('div') : null;
    const ibkrPortWrap = ibkrPortEl ? ibkrPortEl.closest('div') : null;
    const provider = String(providerEl?.value || 'polygon').trim().toLowerCase();
    const useIbkr = provider === 'ibkr';
    if (ibkrHostEl) ibkrHostEl.disabled = !useIbkr;
    if (ibkrPortEl) ibkrPortEl.disabled = !useIbkr;
    if (ibkrHostWrap) ibkrHostWrap.classList.toggle('d-none', !useIbkr);
    if (ibkrPortWrap) ibkrPortWrap.classList.toggle('d-none', !useIbkr);
    if (summaryModelEl) summaryModelEl.disabled = !Boolean(llmSummaryEl?.checked);
    renderAgentNewsSummaryWarning();
    if (Boolean(llmSummaryEl?.checked) && agentAdminNewsHealth.anthropicApiKeyConfigured !== true) {
        void refreshAgentNewsHealth(false);
    }
}

function renderAgentNewsSummaryWarning() {
    const warnEl = document.getElementById('agent-news-llm-summary-warning');
    const llmSummaryEl = document.getElementById('agent-news-llm-summary');
    if (!warnEl) return;
    if (!Boolean(llmSummaryEl?.checked)) {
        warnEl.classList.add('d-none');
        warnEl.textContent = '';
        return;
    }
    if (agentAdminNewsHealth.anthropicApiKeyConfigured === false) {
        warnEl.textContent = 'LLM summary is enabled but backend ANTHROPIC_API_KEY is missing. Summaries will fail until key is configured.';
        warnEl.classList.remove('d-none');
        return;
    }
    warnEl.classList.add('d-none');
    warnEl.textContent = '';
}

async function refreshAgentNewsHealth(force = false) {
    if (!sessionId) return;
    const now = Date.now();
    if (!force && (now - Number(agentAdminNewsHealth.checkedAtMs || 0)) < 60000) {
        return;
    }
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/admin`);
        const data = await res.json().catch(() => ({}));
        if (!res.ok || !data || typeof data !== 'object') return;
        agentAdminNewsHealth.checkedAtMs = now;
        const configured = data?.guardrails?.anthropic_api_key_configured;
        agentAdminNewsHealth.anthropicApiKeyConfigured = (configured === undefined || configured === null)
            ? null
            : Boolean(configured);
    } catch (_) {
        // Best-effort UI hint only.
    } finally {
        renderAgentNewsSummaryWarning();
    }
}

function syncAgentPermissionDependencies() {
    const autoEl = document.getElementById('agent-can-auto-execute');
    const confirmEl = document.getElementById('agent-require-confirm');
    const placeEl = document.getElementById('agent-can-place-trades');
    const closeEl = document.getElementById('agent-can-close-trades');
    if (!autoEl || !confirmEl || !placeEl || !closeEl) return;

    if (autoEl.checked) {
        // AUTO_PAPER requires full trade permissions and no manual confirm.
        placeEl.checked = true;
        closeEl.checked = true;
        confirmEl.checked = false;
        confirmEl.disabled = true;
    } else {
        confirmEl.disabled = false;
    }
    if (confirmEl.checked && autoEl.checked) {
        autoEl.checked = false;
        confirmEl.disabled = false;
    }
}

function getAgentPermissionsFromUI() {
    const on = (id, fallback = false) => {
        const el = document.getElementById(id);
        return el ? !!el.checked : !!fallback;
    };
    const perms = {
        can_chat: true,
        can_scan_tools: on('agent-can-scan-tools', true),
        can_use_research: on('agent-can-use-research', false),
        can_manage_indicators: on('agent-can-manage-indicators', true),
        can_place_trades: on('agent-can-place-trades', false),
        can_close_trades: on('agent-can-close-trades', false),
        can_auto_execute: on('agent-can-auto-execute', false),
        requires_user_confirm_for_trade: on('agent-require-confirm', true),
    };
    // Final payload normalization to avoid backend 422 on conflicting toggles.
    if (perms.can_auto_execute) {
        perms.can_place_trades = true;
        perms.can_close_trades = true;
        perms.requires_user_confirm_for_trade = false;
    }
    if (perms.requires_user_confirm_for_trade) {
        perms.can_auto_execute = false;
    }
    return perms;
}

function _normalizeAgentStatePayload(data) {
    if (!data || typeof data !== 'object') return {};
    if (data.agent_state && typeof data.agent_state === 'object') return data.agent_state;
    if (data.copilot_state && typeof data.copilot_state === 'object') return data.copilot_state;
    if (data.state && typeof data.state === 'object') return data.state;
    return data;
}

function _agentTriggerConditionLabel(condLike) {
    const c = String(condLike || '').trim().toLowerCase();
    if (c === 'close_below') return 'Candle Close <';
    if (c === 'close_above') return 'Candle Close >';
    if (c === 'price_below') return 'Price <';
    if (c === 'price_above') return 'Price >';
    return c || 'condition';
}

function renderAgentTriggerList(rowsLike) {
    const wrap = document.getElementById('agent-trigger-list');
    const modalWrap = document.getElementById('agent-trigger-list-modal');
    if (!wrap && !modalWrap) return;
    const rows = Array.isArray(rowsLike) ? rowsLike : [];
    agentScheduledTriggers = rows.slice(0, 300);
    const setHtml = (html) => {
        if (wrap) wrap.innerHTML = html;
        if (modalWrap) modalWrap.innerHTML = html;
    };
    if (!rows.length) {
        setHtml('<div class="fvg-empty">No scheduled triggers.</div>');
        return;
    }
    const out = rows.map((r) => {
        const id = String(r?.id || '').trim();
        const status = String(r?.status || 'pending').trim().toLowerCase();
        const state = String(r?.state || 'waiting_entry').trim().toLowerCase();
        const tf = String(r?.timeframe || '').trim().toUpperCase();
        const cond = _agentTriggerConditionLabel(r?.condition);
        const trg = Number(r?.trigger_price);
        const pre = (r?.precondition && typeof r.precondition === 'object') ? r.precondition : null;
        const preCond = pre ? _agentTriggerConditionLabel(pre.condition) : '';
        const prePrice = pre ? Number(pre.trigger_price) : NaN;
        const preHitAt = pre ? String(pre.hit_at || '').replace('T', ' ').slice(0, 19) : '';
        const cancelRule = (r?.cancel_rule && typeof r.cancel_rule === 'object') ? r.cancel_rule : null;
        const cancelCond = cancelRule ? _agentTriggerConditionLabel(cancelRule.condition) : '';
        const cancelPrice = cancelRule ? Number(cancelRule.trigger_price) : NaN;
        const cancelHitAt = cancelRule ? String(cancelRule.hit_at || '').replace('T', ' ').slice(0, 19) : '';
        const targs = (r?.trade_args && typeof r.trade_args === 'object') ? r.trade_args : {};
        const dir = String(targs.direction || '').trim().toUpperCase();
        const sl = Number(targs.stop_loss);
        const tp = Number(targs.take_profit);
        const lot = Number(targs.lot_size);
        const created = String(r?.created_at || '').replace('T', ' ').slice(0, 19);
        const expires = String(r?.expires_at || '').replace('T', ' ').slice(0, 19);
        const isCanceled = status === 'canceled' || status === 'cancelled';
        const statusColor = status === 'pending'
            ? '#fcd34d'
            : (status === 'executed'
                ? '#86efac'
                : (status === 'pending_approval'
                    ? '#93c5fd'
                    : (isCanceled ? '#fb923c' : '#94a3b8')));
        const stateLabel = state === 'waiting_precondition'
            ? 'Stage 1: Precondition'
            : (state === 'waiting_entry' ? 'Stage 2: Entry Armed' : `State: ${state}`);
        const stateColor = state === 'waiting_precondition'
            ? '#f59e0b'
            : (state === 'waiting_entry' ? '#22d3ee' : '#94a3b8');
        const canCancel = status === 'pending' || status === 'pending_approval';
        const meta = [
            `${escapeHtml(stateLabel)}`,
            pre ? `Precondition ${escapeHtml(preCond)} ${Number.isFinite(prePrice) ? prePrice.toFixed(2) : '?'}${preHitAt ? ` | hit ${escapeHtml(preHitAt)}` : ''}` : '',
            cancelRule ? `Cancel if ${escapeHtml(cancelCond)} ${Number.isFinite(cancelPrice) ? cancelPrice.toFixed(2) : '?'}${cancelHitAt ? ` | hit ${escapeHtml(cancelHitAt)}` : ''}` : '',
            `${escapeHtml(cond)} ${Number.isFinite(trg) ? trg.toFixed(2) : '?'}`,
            `${escapeHtml(dir)} | SL ${Number.isFinite(sl) ? sl.toFixed(2) : '?'} | TP ${Number.isFinite(tp) ? tp.toFixed(2) : '-'} | Lot ${Number.isFinite(lot) ? lot.toFixed(2) : '0.01'}`,
            `${escapeHtml(tf || 'M15')} | Created ${escapeHtml(created || '-')}${expires ? ` | Expires ${escapeHtml(expires)}` : ''}`,
        ].filter(Boolean).join('\n');
        return `
            <div class="agent-trigger-item">
                <div>
                    <strong>${escapeHtml(id || 'trigger')}</strong>
                    <span style="color:${statusColor};">(${escapeHtml(status.toUpperCase())})</span>
                    <span style="color:${stateColor};margin-left:6px;">[${escapeHtml(state === 'waiting_precondition' ? 'PRE' : (state === 'waiting_entry' ? 'ARMED' : String(state || '').toUpperCase()))}]</span>
                </div>
                <div class="meta">${meta}</div>
                ${canCancel ? `<div class="actions"><button class="btn btn-sm btn-outline-danger" data-trigger-cancel="${escapeHtml(id)}" type="button"><i class="bi bi-x-circle me-1"></i>Cancel</button></div>` : ''}
            </div>
        `;
    }).join('');
    setHtml(out);
}

async function refreshAgentTriggerList(showStatusErrors = false) {
    if (!sessionId) {
        renderAgentTriggerList([]);
        return { ok: false, error: 'No active session', triggers: [] };
    }
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/triggers`);
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            const msg = String(data?.detail || data?.error || `HTTP ${res.status}`);
            if (showStatusErrors) showStatus(`Trigger refresh failed: ${msg}`, 'warning');
            return { ok: false, error: msg, triggers: [] };
        }
        const rows = Array.isArray(data?.triggers) ? data.triggers : [];
        renderAgentTriggerList(rows);
        return { ok: true, triggers: rows };
    } catch (err) {
        const msg = String(err?.message || err || 'trigger refresh failed');
        if (showStatusErrors) showStatus(`Trigger refresh failed: ${msg}`, 'warning');
        return { ok: false, error: msg, triggers: [] };
    }
}

async function cancelAgentTriggerById(triggerIdLike) {
    const triggerId = String(triggerIdLike || '').trim();
    if (!sessionId || !triggerId) return;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/triggers/${encodeURIComponent(triggerId)}`, {
            method: 'DELETE',
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            const msg = String(data?.detail || data?.error || `HTTP ${res.status}`);
            showStatus(`Trigger cancel failed: ${msg}`, 'warning');
            return;
        }
        const rows = Array.isArray(data?.triggers) ? data.triggers : [];
        renderAgentTriggerList(rows);
        showStatus('Trigger cancelled.', 'info');
    } catch (err) {
        showStatus(`Trigger cancel failed: ${String(err?.message || err)}`, 'danger');
    }
}

async function cancelAllAgentTriggers() {
    if (!sessionId) return;
    const ok = window.confirm('Cancel all pending agent triggers?');
    if (!ok) return;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/triggers?all=1`, {
            method: 'DELETE',
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            const msg = String(data?.detail || data?.error || `HTTP ${res.status}`);
            showStatus(`Cancel-all failed: ${msg}`, 'warning');
            return;
        }
        const rows = Array.isArray(data?.triggers) ? data.triggers : [];
        renderAgentTriggerList(rows);
        const n = Number(data?.cancelled || 0);
        showStatus(`Cancelled ${Number.isFinite(n) ? n : 0} trigger(s).`, 'info');
    } catch (err) {
        showStatus(`Cancel-all failed: ${String(err?.message || err)}`, 'danger');
    }
}

function onAgentTriggerListClick(event) {
    const btn = event.target?.closest?.('button[data-trigger-cancel]');
    if (!btn) return;
    const id = String(btn.getAttribute('data-trigger-cancel') || '').trim();
    if (!id) return;
    void cancelAgentTriggerById(id);
}

async function agentMemoryAdd(content, scope = 'GLOBAL', memoryType = 'trader_rule', importance = 0.9) {
    if (!sessionId) return { ok: false, error: 'No active session' };
    const text = String(content || '').trim();
    if (text.length < 8) {
        return { ok: false, error: 'Memory note must be at least 8 characters.' };
    }
    const payload = {
        content: text,
        scope: String(scope || 'GLOBAL').toUpperCase(),
        memory_type: String(memoryType || 'trader_rule'),
        importance: Number.isFinite(Number(importance)) ? Math.max(0, Math.min(1, Number(importance))) : 0.9,
        metadata: { from: 'chat_command' },
    };
    const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/memory`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data?.ok === false) {
        return { ok: false, error: String(data?.detail || data?.error || `HTTP ${res.status}`) };
    }
    return { ok: true, data };
}

async function agentMemorySearch(query, limit = 8) {
    if (!sessionId) return { ok: false, error: 'No active session', memories: [] };
    const q = encodeURIComponent(String(query || '').trim());
    const l = Math.max(1, Math.min(30, Number(limit) || 8));
    const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/memory?query=${q}&limit=${l}`);
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data?.ok === false) {
        return { ok: false, error: String(data?.detail || data?.error || `HTTP ${res.status}`), memories: [] };
    }
    const memories = Array.isArray(data?.memories) ? data.memories : [];
    if (data?.policy && typeof data.policy === 'object') {
        agentMemoryPolicy = data.policy;
        applyAgentMemoryPolicyToUI(agentMemoryPolicy);
    }
    return { ok: true, memories };
}

function readAgentMemoryPolicyFromUI() {
    const on = (id, fallback = false) => {
        const el = document.getElementById(id);
        return el ? !!el.checked : !!fallback;
    };
    const num = (id, fallback) => {
        const el = document.getElementById(id);
        const v = Number(el?.value);
        if (!Number.isFinite(v)) return fallback;
        return v;
    };
    return {
        enabled: on('agent-memory-policy-enabled', true),
        pinned_never_expires: on('agent-memory-policy-pinned', true),
        ttl_days_default: Math.max(1, Math.min(3650, num('agent-memory-policy-ttl', 180))),
        min_importance: Math.max(0, Math.min(1, num('agent-memory-policy-min-imp', 0.1))),
        max_hits: Math.max(1, Math.min(50, Math.round(num('agent-memory-policy-max-hits', 12)))),
    };
}

function applyAgentMemoryPolicyToUI(policyLike) {
    const p = (policyLike && typeof policyLike === 'object') ? policyLike : {};
    const setVal = (id, val) => {
        const el = document.getElementById(id);
        if (el && val !== undefined && val !== null) el.value = String(val);
    };
    const setChk = (id, val) => {
        const el = document.getElementById(id);
        if (el) el.checked = !!val;
    };
    setChk('agent-memory-policy-enabled', p.enabled !== false);
    setChk('agent-memory-policy-pinned', p.pinned_never_expires !== false);
    setVal('agent-memory-policy-ttl', Number.isFinite(Number(p.ttl_days_default)) ? Number(p.ttl_days_default) : 180);
    setVal('agent-memory-policy-min-imp', Number.isFinite(Number(p.min_importance)) ? Number(p.min_importance).toFixed(2) : '0.10');
    setVal('agent-memory-policy-max-hits', Number.isFinite(Number(p.max_hits)) ? Number(p.max_hits) : 12);
}

async function agentMemoryGetPolicy() {
    if (!sessionId) return { ok: false, error: 'No active session' };
    const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/memory-policy`);
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data?.ok === false) {
        return { ok: false, error: String(data?.detail || data?.error || `HTTP ${res.status}`) };
    }
    const policy = (data?.policy && typeof data.policy === 'object') ? data.policy : {};
    agentMemoryPolicy = policy;
    applyAgentMemoryPolicyToUI(policy);
    return { ok: true, policy };
}

async function agentMemorySetPolicy(policyPatch) {
    if (!sessionId) return { ok: false, error: 'No active session' };
    const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/memory-policy`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(policyPatch || {}),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data?.ok === false) {
        return { ok: false, error: String(data?.detail || data?.error || `HTTP ${res.status}`) };
    }
    const policy = (data?.policy && typeof data.policy === 'object') ? data.policy : {};
    agentMemoryPolicy = policy;
    applyAgentMemoryPolicyToUI(policy);
    return { ok: true, policy };
}

async function applyAgentMemoryPolicyFromUI() {
    const patch = readAgentMemoryPolicyFromUI();
    const out = await agentMemorySetPolicy(patch);
    if (!out.ok) {
        showStatus(`Memory policy update failed: ${out.error}`, 'warning');
        return;
    }
    showStatus('Memory policy updated', 'success');
    await refreshAgentMemoryList();
}

async function agentMemoryUpdate(memoryId, patch) {
    if (!sessionId) return { ok: false, error: 'No active session' };
    const id = Number(memoryId);
    if (!Number.isFinite(id) || id <= 0) return { ok: false, error: 'Invalid memory id' };
    const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/memory/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(patch || {}),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data?.ok === false) {
        return { ok: false, error: String(data?.detail || data?.error || `HTTP ${res.status}`) };
    }
    return { ok: true, data };
}

async function agentMemoryDelete(memoryId) {
    if (!sessionId) return { ok: false, error: 'No active session' };
    const id = Number(memoryId);
    if (!Number.isFinite(id) || id <= 0) return { ok: false, error: 'Invalid memory id' };
    const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/memory/${id}`, { method: 'DELETE' });
    const data = await res.json().catch(() => ({}));
    if (!res.ok || data?.ok === false) {
        return { ok: false, error: String(data?.detail || data?.error || `HTTP ${res.status}`) };
    }
    return { ok: true, data };
}

function renderAgentMemoryList(rowsLike = null) {
    const wrap = document.getElementById('agent-memory-list');
    if (!wrap) return;
    const rows = Array.isArray(rowsLike) ? rowsLike : (Array.isArray(agentMemoryRows) ? agentMemoryRows : []);
    if (!rows.length) {
        wrap.innerHTML = '<div class="fvg-empty">No memory found.</div>';
        return;
    }
    wrap.innerHTML = rows.slice(0, 60).map((m) => {
        const id = Number(m?.id || 0);
        const scope = escapeHtml(String(m?.scope || 'SESSION'));
        const mtype = escapeHtml(String(m?.memory_type || 'note'));
        const content = escapeHtml(String(m?.content || ''));
        const imp = Number.isFinite(Number(m?.importance)) ? Number(m.importance).toFixed(2) : '0.00';
        const pinned = !!m?.pinned;
        return `
            <div class="agent-memory-item">
                <div>${content}</div>
                <div class="meta">#${id} | ${scope} | ${mtype} | imp ${imp}${pinned ? ' | pinned' : ''}</div>
                <div class="actions">
                    <button class="btn btn-sm btn-outline-info" data-memory-action="pin" data-memory-id="${id}" data-memory-pinned="${pinned ? '1' : '0'}">${pinned ? 'Unpin' : 'Pin'}</button>
                    <button class="btn btn-sm btn-outline-secondary" data-memory-action="edit" data-memory-id="${id}">Edit</button>
                    <button class="btn btn-sm btn-outline-danger" data-memory-action="delete" data-memory-id="${id}">Delete</button>
                </div>
            </div>
        `;
    }).join('');
}

async function refreshAgentMemoryList(forceQuery = null) {
    if (!sessionId) {
        agentMemoryRows = [];
        renderAgentMemoryList([]);
        return;
    }
    if (agentMemoryLoading) return;
    agentMemoryLoading = true;
    try {
        if (!agentMemoryPolicy) {
            await agentMemoryGetPolicy();
        }
        const queryEl = document.getElementById('agent-memory-query');
        const query = forceQuery !== null ? String(forceQuery || '').trim() : String(queryEl?.value || '').trim();
        const out = await agentMemorySearch(query, query ? 30 : 20);
        if (!out.ok) {
            showStatus(`Memory fetch failed: ${out.error}`, 'warning');
            return;
        }
        agentMemoryRows = Array.isArray(out.memories) ? out.memories : [];
        renderAgentMemoryList(agentMemoryRows);
    } finally {
        agentMemoryLoading = false;
    }
}

async function addAgentMemoryFromPanel() {
    const inputEl = document.getElementById('agent-memory-new');
    const scopeEl = document.getElementById('agent-memory-scope');
    const content = String(inputEl?.value || '').trim();
    if (!content) return;
    const scope = String(scopeEl?.value || 'GLOBAL').toUpperCase();
    const out = await agentMemoryAdd(content, scope, 'trader_rule', 0.9);
    if (!out.ok) {
        showStatus(`Memory save failed: ${out.error}`, 'warning');
        return;
    }
    if (inputEl) inputEl.value = '';
    showStatus('Memory saved', 'success');
    await refreshAgentMemoryList();
}

async function rememberLastAssistantReply() {
    const sid = String(consultantActiveSession || '');
    const msgs = Array.isArray(consultantSessions?.[sid]?.messages) ? consultantSessions[sid].messages : [];
    let last = '';
    for (let i = msgs.length - 1; i >= 0; i -= 1) {
        const m = msgs[i];
        if (String(m?.role || '').toLowerCase() === 'assistant') {
            last = String(m?.content || '').trim();
            if (last) break;
        }
    }
    if (!last) {
        showStatus('No assistant reply to remember yet.', 'info');
        return;
    }
    const out = await agentMemoryAdd(last, 'GLOBAL', 'agent_reply', 0.75);
    if (!out.ok) {
        showStatus(`Memory save failed: ${out.error}`, 'warning');
        return;
    }
    showStatus('Last reply saved to memory.', 'success');
    await refreshAgentMemoryList();
}

async function rememberAssistantMessageByIndex(indexLike) {
    const sid = String(consultantActiveSession || '');
    const msgs = Array.isArray(consultantSessions?.[sid]?.messages) ? consultantSessions[sid].messages : [];
    const idx = Number(indexLike);
    if (!Number.isFinite(idx) || idx < 0 || idx >= msgs.length) return;
    const m = msgs[idx];
    if (!m || String(m.role || '').toLowerCase() !== 'assistant') return;
    const text = String(m.content || '').trim();
    if (!text) return;
    const out = await agentMemoryAdd(text, 'GLOBAL', 'agent_reply', 0.75);
    if (!out.ok) {
        showStatus(`Memory save failed: ${out.error}`, 'warning');
        return;
    }
    showStatus('Reply saved to memory.', 'success');
    await refreshAgentMemoryList();
}

async function onAgentMemoryListClick(event) {
    const btn = event.target?.closest?.('button[data-memory-action]');
    if (!btn) return;
    const action = String(btn.getAttribute('data-memory-action') || '').trim();
    const id = Number(btn.getAttribute('data-memory-id') || 0);
    if (!Number.isFinite(id) || id <= 0) return;
    if (action === 'pin') {
        const pinned = String(btn.getAttribute('data-memory-pinned') || '0') === '1';
        const out = await agentMemoryUpdate(id, { pinned: !pinned });
        if (!out.ok) {
            showStatus(`Memory update failed: ${out.error}`, 'warning');
            return;
        }
        await refreshAgentMemoryList();
        return;
    }
    if (action === 'edit') {
        const row = (agentMemoryRows || []).find((r) => Number(r?.id) === id);
        if (!row) return;
        openAgentMemoryEditModal(row);
        return;
    }
    if (action === 'delete') {
        const ok = window.confirm(`Delete memory #${id}?`);
        if (!ok) return;
        const out = await agentMemoryDelete(id);
        if (!out.ok) {
            showStatus(`Memory delete failed: ${out.error}`, 'warning');
            return;
        }
        await refreshAgentMemoryList();
    }
}

function openAgentMemoryEditModal(row) {
    const id = Number(row?.id || 0);
    if (!Number.isFinite(id) || id <= 0) return;
    const el = document.getElementById('agent-memory-edit-content');
    if (el) el.value = String(row?.content || '');
    agentMemoryEditId = id;
    if (typeof bootstrap === 'undefined') return;
    const modalEl = document.getElementById('agentMemoryEditModal');
    if (!modalEl) return;
    bootstrap.Modal.getOrCreateInstance(modalEl).show();
}

async function saveAgentMemoryEditFromModal() {
    const id = Number(agentMemoryEditId || 0);
    if (!Number.isFinite(id) || id <= 0) return;
    const el = document.getElementById('agent-memory-edit-content');
    const text = String(el?.value || '').trim();
    if (text.length < 8) {
        showStatus('Memory note must be at least 8 characters.', 'warning');
        return;
    }
    const row = (agentMemoryRows || []).find((r) => Number(r?.id) === id);
    if (row && text === String(row?.content || '').trim()) {
        if (typeof bootstrap !== 'undefined') {
            const modalEl = document.getElementById('agentMemoryEditModal');
            if (modalEl) bootstrap.Modal.getOrCreateInstance(modalEl).hide();
        }
        return;
    }
    const btn = document.getElementById('btn-agent-memory-edit-save');
    if (btn) btn.disabled = true;
    try {
        const out = await agentMemoryUpdate(id, { content: text });
        if (!out.ok) {
            showStatus(`Memory update failed: ${out.error}`, 'warning');
            return;
        }
        if (typeof bootstrap !== 'undefined') {
            const modalEl = document.getElementById('agentMemoryEditModal');
            if (modalEl) bootstrap.Modal.getOrCreateInstance(modalEl).hide();
        }
        agentMemoryEditId = null;
        await refreshAgentMemoryList();
        showStatus('Memory updated.', 'success');
    } finally {
        if (btn) btn.disabled = false;
    }
}

function onConsultantChatLogClick(event) {
    const btn = event.target?.closest?.('button[data-chat-remember-idx]');
    if (!btn) return;
    const idx = Number(btn.getAttribute('data-chat-remember-idx') || -1);
    void rememberAssistantMessageByIndex(idx);
}

function isApprovalTextCommand(textLike) {
    const t = String(textLike || '').trim().toLowerCase();
    if (!t) return false;
    return /^(yes|y|approve|approved|confirm|confirmed|ok|okay|go|proceed|do it|execute|final approval|evet|onay|no|n|cancel|reject|stop|dont|don't|hayir|hayÄ±r|reddet)$/.test(t);
}

async function sendConsultantMessage() {
    if (consultantSending) return;
    if (!sessionId) {
        showStatus('Start a session first', 'warning');
        return;
    }
    const inputEl = document.getElementById('consultant-input');
    if (!inputEl) return;

    const message = String(inputEl.value || '').trim();
    if (!message) return;
    const sid = String(consultantActiveSession || '');
    if (!sid || !consultantSessions[sid]) {
        createConsultantSession();
    }
    const active = String(consultantActiveSession || '');
    if (!active || !consultantSessions[active]) return;

    if (Array.isArray(pendingAgentApprovals) && pendingAgentApprovals.length > 0 && isApprovalTextCommand(message)) {
        _consultantAppendMessage('user', message);
        _consultantAppendMessage('assistant', 'Use the Approve/Cancel buttons in the Pending Approval card. Text confirmations are disabled.');
        renderConsultantChat();
        saveConsultantSessions();
        inputEl.value = '';
        showStatus('Use Approve/Cancel buttons for tool execution approval.', 'info');
        return;
    }

    const rememberMatch = message.match(/^\/remember(?:\s+(global|session|symbol))?\s*:\s*(.+)$/i)
        || message.match(/^\/remember(?:\s+(global|session|symbol))?\s+(.+)$/i);
    if (rememberMatch) {
        const scope = String(rememberMatch[1] || 'GLOBAL').toUpperCase();
        const content = String(rememberMatch[2] || '').trim();
        _consultantAppendMessage('user', message);
        renderConsultantChat();
        saveConsultantSessions();
        inputEl.value = '';
        consultantSending = true;
        const sendBtnLocal = document.getElementById('btn-consultant-send');
        if (sendBtnLocal) sendBtnLocal.disabled = true;
        try {
            const out = await agentMemoryAdd(content, scope, 'trader_rule', 0.92);
            if (!out.ok) {
                _consultantAppendMessage('assistant', `Could not save memory: ${out.error}`);
                showStatus(`Memory save failed: ${out.error}`, 'warning');
            } else {
                _consultantAppendMessage('assistant', `Memory saved (${scope}): ${content}`);
                showStatus('Memory saved', 'success');
            }
            renderConsultantChat();
            saveConsultantSessions();
        } finally {
            consultantSending = false;
            if (sendBtnLocal) sendBtnLocal.disabled = false;
        }
        return;
    }

    const memSearchMatch = message.match(/^\/memory\s+(.+)$/i);
    if (memSearchMatch) {
        const query = String(memSearchMatch[1] || '').trim();
        _consultantAppendMessage('user', message);
        renderConsultantChat();
        saveConsultantSessions();
        inputEl.value = '';
        consultantSending = true;
        const sendBtnLocal = document.getElementById('btn-consultant-send');
        if (sendBtnLocal) sendBtnLocal.disabled = true;
        try {
            const out = await agentMemorySearch(query, 8);
            if (!out.ok) {
                _consultantAppendMessage('assistant', `Memory search failed: ${out.error}`);
            } else if (!out.memories.length) {
                _consultantAppendMessage('assistant', 'No matching memory found.');
            } else {
                const lines = out.memories.slice(0, 8).map((m, i) => `${i + 1}. [${String(m.scope || 'SESSION')}] ${String(m.content || '')}`);
                _consultantAppendMessage('assistant', `Memory results:\n${lines.join('\n')}`);
            }
            renderConsultantChat();
            saveConsultantSessions();
        } finally {
            consultantSending = false;
            if (sendBtnLocal) sendBtnLocal.disabled = false;
        }
        return;
    }

    _consultantAppendMessage('user', message);
    renderConsultantChat();
    saveConsultantSessions();
    inputEl.value = '';
    consultantSending = true;
    setAgentChatTyping(true);
    const sendBtn = document.getElementById('btn-consultant-send');
    if (sendBtn) sendBtn.disabled = true;

    try {
        saveAgentProviderPrefs();
        await saveAgentIdentityFromUI(true);
        const history = (consultantSessions[active]?.messages || [])
            .slice(-8)
            .filter((m) => m && typeof m === 'object')
            .map((m) => ({
                role: String(m.role || '').toLowerCase() === 'user' ? 'user' : 'assistant',
                content: String(m.content || '').slice(0, 800),
            }));
        const payload = {
            provider: getAgentProviderConfig(),
            permissions: getAgentPermissionsFromUI(),
            config: getAgentWatchdogConfigFromUI(),
            message,
            conversation_history: history,
            context_snapshot: buildConsultantContext(),
            allow_tools: true,
            max_tool_steps: getAgentRecommendedMaxToolSteps('chat'),
        };
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/chat`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            const err = String(data?.detail || data?.error || data?.message || data?.audit?.error || `HTTP ${res.status}`);
            _consultantAppendMessage('assistant', `I could not process that request: ${err}`, {
                usage: data?.usage,
                provider: data?.provider,
                model: data?.model_label || data?.model,
            });
            renderConsultantChat();
            saveConsultantSessions();
            showStatus(`Agent error: ${err}`, 'warning');
            return;
        }
        const replyRaw = String(data?.message || data?.reply || '').trim();
        const reply = sanitizeAgentReplyText(replyRaw) || replyRaw || 'No response.';
        _consultantAppendMessage('assistant', reply, {
            usage: data?.usage,
            provider: data?.provider,
            model: data?.model_label || data?.model,
        });
        renderConsultantChat();
        saveConsultantSessions();
        appendExecutionTraceFromToolCalls(data?.tool_calls, 'agent_chat');
        ingestPendingApprovalsFromToolCalls(data?.tool_calls, 'agent_chat');
        void (async () => {
            try {
                await applyAgentToolCallsToChart(data?.tool_calls, 'agent_chat');
            } catch (postErr) {
                showStatus(`Tool-output sync warning: ${postErr?.message || postErr}`, 'warning');
            } finally {
                void refreshAgentState(false);
            }
        })();
    } catch (err) {
        const msg = String(err?.message || err || 'Unknown error');
        _consultantAppendMessage('assistant', `I could not process that request: ${msg}`);
        renderConsultantChat();
        saveConsultantSessions();
        showStatus(`Agent error: ${msg}`, 'warning');
    } finally {
        consultantSending = false;
        setAgentChatTyping(false);
        if (sendBtn) sendBtn.disabled = false;
    }
}

async function runAgentOnce() {
    if (!sessionId) {
        showStatus('Start a session first', 'warning');
        return;
    }
    const btn = document.getElementById('btn-agent-run-once');
    const inputEl = document.getElementById('consultant-input');
    const objectiveRaw = String(inputEl?.value || '').trim();
    const objective = objectiveRaw || 'Review current context and propose the next best action.';
    try {
        setAgentChatTyping(true);
        if (btn) {
            btn.disabled = true;
            btn.innerHTML = '<i class="bi bi-hourglass-split me-1"></i>Running...';
        }
        const payload = {
            provider: getAgentProviderConfig(),
            permissions: getAgentPermissionsFromUI(),
            config: getAgentWatchdogConfigFromUI(),
            context_snapshot: buildConsultantContext(),
            objective,
            allow_tools: true,
            max_tool_steps: getAgentRecommendedMaxToolSteps('run_once'),
        };
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/run-once`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            const msg = String(data?.detail || data?.error || data?.message || data?.audit?.error || `HTTP ${res.status}`);
            showStatus(`Agent run failed: ${msg}`, 'danger');
            _consultantAppendMessage('assistant', `Run-once failed: ${msg}`, {
                usage: data?.usage,
                provider: data?.provider,
                model: data?.model_label || data?.model,
            });
            renderConsultantChat();
            saveConsultantSessions();
            return;
        }
        const appliedTools = await applyAgentToolCallsToChart(data?.tool_calls, 'agent_run_once');
        appendExecutionTraceFromToolCalls(data?.tool_calls, 'agent_run_once');
        ingestPendingApprovalsFromToolCalls(data?.tool_calls, 'agent_run_once');
        const agentState = _normalizeAgentStatePayload(data);
        if (
            agentState && typeof agentState === 'object' &&
            (Object.prototype.hasOwnProperty.call(agentState, 'active') || Array.isArray(agentState.recent_advices))
        ) {
            renderAgentState(agentState);
        }
        const replyRaw = String(data?.message || '').trim();
        const reply = sanitizeAgentReplyText(replyRaw) || replyRaw;
        if (reply) {
            _consultantAppendMessage('assistant', reply, {
                usage: data?.usage,
                provider: data?.provider,
                model: data?.model_label || data?.model,
            });
            renderConsultantChat();
            saveConsultantSessions();
        }
        showStatus(
            appliedTools > 0
                ? `Agent run-once completed (applied ${appliedTools} tool result${appliedTools !== 1 ? 's' : ''})`
                : 'Agent run-once completed',
            'success',
        );
        await refreshAgentState(false);
    } catch (err) {
        showStatus(`Agent run failed: ${err.message || err}`, 'danger');
    } finally {
        setAgentChatTyping(false);
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = '<i class="bi bi-lightning-charge me-1"></i>Run Once';
        }
    }
}

function initConsultantState() {
    loadConsultantSessions();
    refreshConsultantSessionList();
    renderConsultantChat();
    renderPendingAgentApprovals();
    ensurePendingApprovalTimer();
    renderAgentExecutionTrace();
    renderAgentUsageMeter({});
    setAgentChatTyping(false);
    loadAgentProviderPrefs();
    setAgentChatAvailability(!!sessionId);
}

function getToolStrictness(toolId, defaultValue = 3) {
    const el = document.getElementById(`tool-${toolId}-strictness`);
    const raw = Number(el?.value ?? defaultValue);
    if (!Number.isFinite(raw)) return defaultValue;
    return Math.max(1, Math.min(5, Math.round(raw)));
}

function updateFvgScopeControls() {
    const scopeEl = document.getElementById('fvg-scan-scope');
    const lookbackEl = document.getElementById('fvg-lookback-days');
    if (!scopeEl || !lookbackEl) return;
    const scope = String(scopeEl.value || 'last_n_days');
    const useDaysWindow = scope !== 'visible';
    lookbackEl.disabled = !useDaysWindow;
    lookbackEl.classList.toggle('opacity-50', !useDaysWindow);
    lookbackEl.title = useDaysWindow ? '' : 'Disabled when Scan Scope is Visible Bars';
}

function updateMeanRevScopeControls() {
    const scopeEl = document.getElementById('mean-rev-scan-scope');
    const lookbackEl = document.getElementById('mean-rev-lookback-days');
    if (!scopeEl || !lookbackEl) return;
    const scope = String(scopeEl.value || 'last_n_days');
    const useDaysWindow = scope !== 'visible';
    lookbackEl.disabled = !useDaysWindow;
    lookbackEl.classList.toggle('opacity-50', !useDaysWindow);
    lookbackEl.title = useDaysWindow ? '' : 'Disabled when Scan Scope is Visible Bars';
}

function getToolStatePayload() {
    const activeTools = [];
    const tools = {};
    for (const [toolId, state] of Object.entries(toolStates || {})) {
        const s = state || {};
        const enabled = !!s.enabled;
        if (enabled) activeTools.push(String(toolId));
        const baseConfig = { ...(s.config || {}) };
        if (toolId === 'fvg') {
            baseConfig.min_gap = s.min_gap ?? (s.config?.min_gap ?? null);
            baseConfig.show_filled = !!(s.show_filled ?? s.config?.show_filled);
            baseConfig.trend_filter_enabled = !!(s.trend_filter_enabled ?? s.config?.trend_filter_enabled ?? true);
            baseConfig.trend_multiplier = Number(s.trend_multiplier ?? s.config?.trend_multiplier ?? 3);
            baseConfig.trend_alignment_mode = String(s.trend_alignment_mode ?? s.config?.trend_alignment_mode ?? 'prefer');
            baseConfig.scan_scope = String(s.scan_scope ?? s.config?.scan_scope ?? 'last_n_days');
            baseConfig.lookback_days = Number(s.lookback_days ?? s.config?.lookback_days ?? 2);
            baseConfig.timeframe = String(s.detect_timeframe ?? s.config?.timeframe ?? getChartTimeframe());
        } else if (toolId === 'mean_rev') {
            baseConfig.strictness = Number(s.strictness ?? s.config?.strictness ?? 3);
            baseConfig.sma_period = Number(s.sma_period ?? s.config?.sma_period ?? 30);
            baseConfig.deviation = Number(s.deviation ?? s.config?.deviation ?? 2.0);
            baseConfig.show_exit_signals = !!(s.show_exit_signals ?? s.config?.show_exit_signals ?? true);
            baseConfig.scan_scope = String(s.scan_scope ?? s.config?.scan_scope ?? 'last_n_days');
            baseConfig.lookback_days = Number(s.lookback_days ?? s.config?.lookback_days ?? 2);
        }
        tools[String(toolId)] = {
            enabled,
            scan_count: Number(s.scan_count || 0),
            last_zone_count: Number(s.last_zone_count || 0),
            zones_sample: Array.isArray(s.zones_sample) ? s.zones_sample.slice(0, 20) : [],
            config: baseConfig,
            movement_strength: (s.movement_strength && typeof s.movement_strength === 'object') ? s.movement_strength : {},
            current_state: (s.current_state && typeof s.current_state === 'object') ? s.current_state : {},
        };
    }
    const fvg = tools.fvg || { enabled: false, scan_count: 0, last_zone_count: 0, config: {} };
    const meanRev = tools.mean_rev || { enabled: false, scan_count: 0, last_zone_count: 0, config: {}, current_state: {} };
    const liquidity = tools.liquidity || { enabled: false, scan_count: 0, last_zone_count: 0, config: {}, current_state: {} };
    return {
        active_tools: activeTools,
        tools,
        // Legacy compatibility fields used by existing backend evaluators
        fvg_enabled: !!fvg.enabled,
        fvg_scan_count: Number(fvg.scan_count || 0),
        fvg_last_zone_count: Number(fvg.last_zone_count || 0),
        fvg_config: fvg.config || {},
        fvg_movement_strength: (fvg.movement_strength && typeof fvg.movement_strength === 'object') ? fvg.movement_strength : {},
        mean_rev_enabled: !!meanRev.enabled,
        mean_rev_scan_count: Number(meanRev.scan_count || 0),
        mean_rev_last_zone_count: Number(meanRev.last_zone_count || 0),
        mean_rev_config: meanRev.config || {},
        mean_rev_current_state: (meanRev.current_state && typeof meanRev.current_state === 'object') ? meanRev.current_state : {},
        liquidity_enabled: !!liquidity.enabled,
        liquidity_scan_count: Number(liquidity.scan_count || 0),
        liquidity_last_zone_count: Number(liquidity.last_zone_count || 0),
        liquidity_config: liquidity.config || {},
        liquidity_current_state: (liquidity.current_state && typeof liquidity.current_state === 'object') ? liquidity.current_state : {},
    };
}

function escapeHtml(value) {
    return String(value || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/\"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function toFiniteNumber(v) {
    const n = Number(v);
    return Number.isFinite(n) ? n : NaN;
}

function getVisibleBarsForIndicators() {
    if (!Array.isArray(allBars) || allBars.length === 0) return [];
    const cap = Math.max(0, Number(currentBar) + 1);
    if (!Number.isFinite(cap) || cap <= 0) return [];
    if (cap >= allBars.length) return allBars.slice();
    return allBars.slice(0, cap);
}

function rollingSMA(values, period) {
    const out = new Array(values.length).fill(NaN);
    if (!Array.isArray(values) || values.length === 0) return out;
    const p = Math.max(1, Number(period) || 1);
    const queue = [];
    let sum = 0;
    let validCount = 0;
    for (let i = 0; i < values.length; i += 1) {
        const cur = toFiniteNumber(values[i]);
        queue.push(cur);
        if (Number.isFinite(cur)) {
            sum += cur;
            validCount += 1;
        }
        if (queue.length > p) {
            const dropped = queue.shift();
            if (Number.isFinite(dropped)) {
                sum -= dropped;
                validCount -= 1;
            }
        }
        if (queue.length === p && validCount === p) out[i] = sum / p;
    }
    return out;
}

function rollingEMA(values, period) {
    const out = new Array(values.length).fill(NaN);
    if (!Array.isArray(values) || values.length === 0) return out;
    const p = Math.max(1, Number(period) || 1);
    const alpha = 2 / (p + 1);
    let ema = NaN;
    for (let i = 0; i < values.length; i += 1) {
        const v = toFiniteNumber(values[i]);
        if (!Number.isFinite(v)) continue;
        if (!Number.isFinite(ema)) ema = v;
        else ema = (alpha * v) + ((1 - alpha) * ema);
        out[i] = ema;
    }
    return out;
}

function rollingStdDev(values, period) {
    const out = new Array(values.length).fill(NaN);
    if (!Array.isArray(values) || values.length === 0) return out;
    const p = Math.max(1, Number(period) || 1);
    for (let i = p - 1; i < values.length; i += 1) {
        let sum = 0;
        let sumSq = 0;
        let count = 0;
        for (let j = i - p + 1; j <= i; j += 1) {
            const v = toFiniteNumber(values[j]);
            if (!Number.isFinite(v)) continue;
            sum += v;
            sumSq += v * v;
            count += 1;
        }
        if (count === p) {
            const mean = sum / p;
            const variance = Math.max(0, (sumSq / p) - (mean * mean));
            out[i] = Math.sqrt(variance);
        }
    }
    return out;
}

function computeRSI(closes, period) {
    const out = new Array(closes.length).fill(NaN);
    const p = Math.max(2, Number(period) || 14);
    if (!Array.isArray(closes) || closes.length <= p) return out;

    let gain = 0;
    let loss = 0;
    for (let i = 1; i <= p; i += 1) {
        const delta = toFiniteNumber(closes[i]) - toFiniteNumber(closes[i - 1]);
        if (!Number.isFinite(delta)) continue;
        if (delta >= 0) gain += delta;
        else loss += Math.abs(delta);
    }
    let avgGain = gain / p;
    let avgLoss = loss / p;
    out[p] = avgLoss === 0 ? 100 : 100 - (100 / (1 + (avgGain / avgLoss)));

    for (let i = p + 1; i < closes.length; i += 1) {
        const delta = toFiniteNumber(closes[i]) - toFiniteNumber(closes[i - 1]);
        if (!Number.isFinite(delta)) continue;
        const g = delta > 0 ? delta : 0;
        const l = delta < 0 ? Math.abs(delta) : 0;
        avgGain = ((avgGain * (p - 1)) + g) / p;
        avgLoss = ((avgLoss * (p - 1)) + l) / p;
        out[i] = avgLoss === 0 ? 100 : 100 - (100 / (1 + (avgGain / avgLoss)));
    }
    return out;
}

function computeADX(highs, lows, closes, period) {
    const len = closes.length;
    const adx = new Array(len).fill(NaN);
    const p = Math.max(2, Number(period) || 14);
    if (len <= (p * 2)) return adx;

    const tr = new Array(len).fill(NaN);
    const plusDM = new Array(len).fill(0);
    const minusDM = new Array(len).fill(0);
    const dx = new Array(len).fill(NaN);

    for (let i = 1; i < len; i += 1) {
        const h = toFiniteNumber(highs[i]);
        const l = toFiniteNumber(lows[i]);
        const prevH = toFiniteNumber(highs[i - 1]);
        const prevL = toFiniteNumber(lows[i - 1]);
        const prevC = toFiniteNumber(closes[i - 1]);
        if (![h, l, prevH, prevL, prevC].every(Number.isFinite)) continue;

        const upMove = h - prevH;
        const downMove = prevL - l;
        plusDM[i] = (upMove > downMove && upMove > 0) ? upMove : 0;
        minusDM[i] = (downMove > upMove && downMove > 0) ? downMove : 0;
        tr[i] = Math.max(h - l, Math.abs(h - prevC), Math.abs(l - prevC));
    }

    let trSum = 0;
    let plusDMSum = 0;
    let minusDMSum = 0;
    for (let i = 1; i <= p; i += 1) {
        trSum += Number.isFinite(tr[i]) ? tr[i] : 0;
        plusDMSum += plusDM[i] || 0;
        minusDMSum += minusDM[i] || 0;
    }

    for (let i = p; i < len; i += 1) {
        if (i > p) {
            trSum = trSum - (trSum / p) + (Number.isFinite(tr[i]) ? tr[i] : 0);
            plusDMSum = plusDMSum - (plusDMSum / p) + (plusDM[i] || 0);
            minusDMSum = minusDMSum - (minusDMSum / p) + (minusDM[i] || 0);
        }
        if (!Number.isFinite(trSum) || trSum <= 1e-9) continue;
        const plusDI = 100 * (plusDMSum / trSum);
        const minusDI = 100 * (minusDMSum / trSum);
        const denom = plusDI + minusDI;
        if (denom <= 1e-9) continue;
        dx[i] = 100 * (Math.abs(plusDI - minusDI) / denom);
    }

    let dxSeedSum = 0;
    let dxSeedCount = 0;
    for (let i = p; i < p * 2; i += 1) {
        if (Number.isFinite(dx[i])) {
            dxSeedSum += dx[i];
            dxSeedCount += 1;
        }
    }
    if (dxSeedCount <= 0) return adx;
    let adxSmoothed = dxSeedSum / dxSeedCount;
    adx[(p * 2) - 1] = adxSmoothed;

    for (let i = p * 2; i < len; i += 1) {
        const d = Number.isFinite(dx[i]) ? dx[i] : adxSmoothed;
        adxSmoothed = ((adxSmoothed * (p - 1)) + d) / p;
        adx[i] = adxSmoothed;
    }
    return adx;
}

function computeStochastic(highs, lows, closes, kPeriod, smoothK, smoothD) {
    const len = closes.length;
    const fastK = new Array(len).fill(NaN);
    const pK = Math.max(2, Number(kPeriod) || 14);
    const pSmoothK = Math.max(1, Number(smoothK) || 3);
    const pSmoothD = Math.max(1, Number(smoothD) || 3);

    for (let i = pK - 1; i < len; i += 1) {
        let hh = -Infinity;
        let ll = Infinity;
        for (let j = i - pK + 1; j <= i; j += 1) {
            const h = toFiniteNumber(highs[j]);
            const l = toFiniteNumber(lows[j]);
            if (Number.isFinite(h)) hh = Math.max(hh, h);
            if (Number.isFinite(l)) ll = Math.min(ll, l);
        }
        const c = toFiniteNumber(closes[i]);
        if (!Number.isFinite(c) || !Number.isFinite(hh) || !Number.isFinite(ll)) continue;
        const range = hh - ll;
        fastK[i] = range <= 1e-9 ? 50 : ((c - ll) / range) * 100;
    }
    const slowK = rollingSMA(fastK, pSmoothK);
    const slowD = rollingSMA(slowK, pSmoothD);
    return { k: slowK, d: slowD };
}

function seriesDataFromArray(bars, values) {
    const out = [];
    const n = Math.min(bars.length, values.length);
    for (let i = 0; i < n; i += 1) {
        const t = Number(bars[i]?.time || 0);
        const v = toFiniteNumber(values[i]);
        if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
        out.push({ time: t, value: v });
    }
    return out;
}

function computeIndicatorPack(bars, selection) {
    const sel = selection || {};
    const needSmaEma = !!sel.smaEma;
    const needBoll = !!sel.bollinger;
    const needAdx = !!sel.adx;
    const needRsi = !!sel.rsi;
    const needStoch = !!sel.stoch;
    const needGoldenCross = !!sel.goldenCross;

    const needCloses = needSmaEma || needBoll || needAdx || needRsi || needStoch || needGoldenCross;
    const needHighLow = needAdx || needStoch;

    const closes = needCloses ? bars.map(b => toFiniteNumber(b?.close)) : [];
    const highs = needHighLow ? bars.map(b => toFiniteNumber(b?.high)) : [];
    const lows = needHighLow ? bars.map(b => toFiniteNumber(b?.low)) : [];

    const needTrendLong = needSmaEma || needGoldenCross;
    const sma20 = needSmaEma ? rollingSMA(closes, INDICATOR_DEFAULTS.smaPeriodFast) : [];
    const sma50 = (needSmaEma || needGoldenCross) ? rollingSMA(closes, INDICATOR_DEFAULTS.smaPeriodSlow) : [];
    const sma200 = needTrendLong ? rollingSMA(closes, INDICATOR_DEFAULTS.smaPeriodCrossSlow) : [];
    const ema20 = needSmaEma ? rollingEMA(closes, INDICATOR_DEFAULTS.emaPeriodFast) : [];
    const ema50 = needSmaEma ? rollingEMA(closes, INDICATOR_DEFAULTS.emaPeriodSlow) : [];
    const ema200 = needTrendLong ? rollingEMA(closes, INDICATOR_DEFAULTS.smaPeriodCrossSlow) : [];
    const bbMid = needBoll ? rollingSMA(closes, INDICATOR_DEFAULTS.bbPeriod) : [];
    const bbStd = needBoll ? rollingStdDev(closes, INDICATOR_DEFAULTS.bbPeriod) : [];
    const bbUpper = needBoll
        ? bbMid.map((m, i) => (Number.isFinite(m) && Number.isFinite(bbStd[i])) ? (m + (INDICATOR_DEFAULTS.bbStd * bbStd[i])) : NaN)
        : [];
    const bbLower = needBoll
        ? bbMid.map((m, i) => (Number.isFinite(m) && Number.isFinite(bbStd[i])) ? (m - (INDICATOR_DEFAULTS.bbStd * bbStd[i])) : NaN)
        : [];
    const adx = needAdx ? computeADX(highs, lows, closes, INDICATOR_DEFAULTS.adxPeriod) : [];
    const rsi = needRsi ? computeRSI(closes, INDICATOR_DEFAULTS.rsiPeriod) : [];
    const stoch = needStoch
        ? computeStochastic(highs, lows, closes, INDICATOR_DEFAULTS.stochKPeriod, INDICATOR_DEFAULTS.stochSmoothK, INDICATOR_DEFAULTS.stochSmoothD)
        : { k: [], d: [] };
    return {
        sma20, sma50, sma200, ema20, ema50, ema200,
        bbUpper, bbMid, bbLower,
        adx, rsi,
        stochK: stoch.k,
        stochD: stoch.d,
    };
}

function ensureIndicatorSeries(key, options) {
    if (indicatorSeries[key] || !chart) return indicatorSeries[key] || null;
    indicatorSeries[key] = chart.addLineSeries(options || {});
    return indicatorSeries[key];
}

function removeIndicatorSeries(key) {
    const s = indicatorSeries[key];
    if (!s || !chart) return;
    try { chart.removeSeries(s); } catch (_) {}
    delete indicatorSeries[key];
}

function ensureOscillatorScale() {
    if (!chart) return;
    chart.priceScale('osc').applyOptions({
        autoScale: true,
        scaleMargins: { top: 0.74, bottom: 0.03 },
        borderColor: '#334155',
    });
}

function clearAllIndicatorSeries() {
    for (const key of Object.keys(indicatorSeries)) removeIndicatorSeries(key);
}

function computeGoldenCrossMarkers(bars, fastSma, slowSma) {
    const markers = [];
    const n = Math.min(bars.length, fastSma.length, slowSma.length);
    for (let i = 1; i < n; i += 1) {
        const prevFast = toFiniteNumber(fastSma[i - 1]);
        const prevSlow = toFiniteNumber(slowSma[i - 1]);
        const curFast = toFiniteNumber(fastSma[i]);
        const curSlow = toFiniteNumber(slowSma[i]);
        if (![prevFast, prevSlow, curFast, curSlow].every(Number.isFinite)) continue;
        if (prevFast <= prevSlow && curFast > curSlow) {
            const t = Number(bars[i]?.time || 0);
            if (!Number.isFinite(t)) continue;
            markers.push({
                time: t,
                position: 'belowBar',
                color: '#facc15',
                shape: 'arrowUp',
                text: 'Golden Cross',
            });
        }
        if (prevFast >= prevSlow && curFast < curSlow) {
            const t = Number(bars[i]?.time || 0);
            if (!Number.isFinite(t)) continue;
            markers.push({
                time: t,
                position: 'aboveBar',
                color: '#ef4444',
                shape: 'arrowDown',
                text: 'Death Cross',
            });
        }
    }
    return markers;
}

function syncCandleMarkers() {
    if (!candleSeries) return;
    const markers = [];
    if (Array.isArray(tradeMarkers) && tradeMarkers.length > 0) markers.push(...tradeMarkers);
    if (indicatorSelection.goldenCross && Array.isArray(goldenCrossMarkers) && goldenCrossMarkers.length > 0) {
        markers.push(...goldenCrossMarkers);
    }
    if (Array.isArray(fvgCreatorMarkers) && fvgCreatorMarkers.length > 0) {
        markers.push(...fvgCreatorMarkers);
    }
    markers.sort((a, b) => Number(a.time || 0) - Number(b.time || 0));
    candleSeries.setMarkers(markers);
}

function applyIndicatorVisibility() {
    const showSmaEma = !!indicatorSelection.smaEma;
    const showBoll = !!indicatorSelection.bollinger;
    const showAdx = !!indicatorSelection.adx;
    const showRsi = !!indicatorSelection.rsi;
    const showStoch = !!indicatorSelection.stoch;

    if (!showSmaEma) {
        removeIndicatorSeries('sma20');
        removeIndicatorSeries('sma50');
        removeIndicatorSeries('ema20');
        removeIndicatorSeries('ema50');
    }
    if (!showBoll) {
        removeIndicatorSeries('bbUpper');
        removeIndicatorSeries('bbMid');
        removeIndicatorSeries('bbLower');
    }
    if (!showAdx) removeIndicatorSeries('adx');
    if (!showRsi) removeIndicatorSeries('rsi');
    if (!showStoch) {
        removeIndicatorSeries('stochK');
        removeIndicatorSeries('stochD');
    }
    if (!(showAdx || showRsi || showStoch) && chart) {
        chart.priceScale('osc').applyOptions({
            autoScale: true,
            scaleMargins: { top: 0.99, bottom: 0.0 },
            borderColor: '#334155',
        });
    }
}

function updateIndicatorsOnChart() {
    if (!chart || !candleSeries) return;
    applyIndicatorVisibility();
    const bars = getVisibleBarsForIndicators();
    const hasSelection = indicatorSelection.smaEma
        || indicatorSelection.bollinger
        || indicatorSelection.adx
        || indicatorSelection.rsi
        || indicatorSelection.stoch
        || indicatorSelection.goldenCross;

    if (!hasSelection) {
        goldenCrossMarkers = [];
        syncCandleMarkers();
        return;
    }

    if (!Array.isArray(bars) || bars.length === 0) {
        goldenCrossMarkers = [];
        syncCandleMarkers();
        return;
    }

    const pack = computeIndicatorPack(bars, indicatorSelection);

    if (indicatorSelection.smaEma) {
        ensureIndicatorSeries('sma20', { color: '#f59e0b', lineWidth: 2 });
        ensureIndicatorSeries('sma50', { color: '#f97316', lineWidth: 2 });
        ensureIndicatorSeries('ema20', { color: '#60a5fa', lineWidth: 2, lineStyle: 1 });
        ensureIndicatorSeries('ema50', { color: '#3b82f6', lineWidth: 2, lineStyle: 1 });
        indicatorSeries.sma20?.setData(seriesDataFromArray(bars, pack.sma20));
        indicatorSeries.sma50?.setData(seriesDataFromArray(bars, pack.sma50));
        indicatorSeries.ema20?.setData(seriesDataFromArray(bars, pack.ema20));
        indicatorSeries.ema50?.setData(seriesDataFromArray(bars, pack.ema50));
    }

    if (indicatorSelection.bollinger) {
        ensureIndicatorSeries('bbUpper', { color: '#a78bfa', lineWidth: 1 });
        ensureIndicatorSeries('bbMid', { color: '#c084fc', lineWidth: 1 });
        ensureIndicatorSeries('bbLower', { color: '#a78bfa', lineWidth: 1 });
        indicatorSeries.bbUpper?.setData(seriesDataFromArray(bars, pack.bbUpper));
        indicatorSeries.bbMid?.setData(seriesDataFromArray(bars, pack.bbMid));
        indicatorSeries.bbLower?.setData(seriesDataFromArray(bars, pack.bbLower));
    }

    if (indicatorSelection.adx || indicatorSelection.rsi || indicatorSelection.stoch) ensureOscillatorScale();

    if (indicatorSelection.adx) {
        ensureIndicatorSeries('adx', { color: '#22d3ee', lineWidth: 1, priceScaleId: 'osc' });
        indicatorSeries.adx?.setData(seriesDataFromArray(bars, pack.adx));
    }

    if (indicatorSelection.rsi) {
        ensureIndicatorSeries('rsi', { color: '#f472b6', lineWidth: 1, priceScaleId: 'osc' });
        indicatorSeries.rsi?.setData(seriesDataFromArray(bars, pack.rsi));
    }

    if (indicatorSelection.stoch) {
        ensureIndicatorSeries('stochK', { color: '#38bdf8', lineWidth: 1, priceScaleId: 'osc' });
        ensureIndicatorSeries('stochD', { color: '#f97316', lineWidth: 1, priceScaleId: 'osc' });
        indicatorSeries.stochK?.setData(seriesDataFromArray(bars, pack.stochK));
        indicatorSeries.stochD?.setData(seriesDataFromArray(bars, pack.stochD));
    }

    goldenCrossMarkers = computeGoldenCrossMarkers(bars, pack.sma50, pack.sma200);
    syncCandleMarkers();
}

function readIndicatorSelectionFromUI() {
    const read = (id) => !!document.getElementById(id)?.checked;
    indicatorSelection = {
        smaEma: read('ind-sma-ema'),
        adx: read('ind-adx'),
        rsi: read('ind-rsi'),
        stoch: read('ind-stoch'),
        bollinger: read('ind-bollinger'),
        goldenCross: read('ind-golden-cross'),
    };
}

function resetIndicatorSelectionUI() {
    const ids = ['ind-sma-ema', 'ind-adx', 'ind-rsi', 'ind-stoch', 'ind-bollinger', 'ind-golden-cross'];
    for (const id of ids) {
        const el = document.getElementById(id);
        if (el) el.checked = false;
    }
    readIndicatorSelectionFromUI();
    clearAllIndicatorSeries();
    goldenCrossMarkers = [];
    syncCandleMarkers();
    showStatus('All indicators hidden', 'info');
}

function getZonePriceDecimals() {
    const symbol = String(document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    if (symbol.includes('USD') && (symbol.startsWith('EUR') || symbol.startsWith('GBP'))) return 5;
    if (symbol.includes('NAS') || symbol.includes('US500') || symbol.includes('SPX') || symbol.includes('DJI')) return 1;
    return 2;
}

function formatZonePrice(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return '-';
    return n.toFixed(getZonePriceDecimals());
}

function formatZoneTime(unixTs) {
    const ts = Number(unixTs || 0);
    if (!Number.isFinite(ts) || ts <= 0) return '-';
    const d = new Date(ts * 1000);
    if (Number.isNaN(d.getTime())) return '-';
    return d.toLocaleString([], {
        month: 'short',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
    });
}

function flattenFvgZonesAcrossTimeframes() {
    const merged = [];
    Object.entries(fvgZonesByTimeframe || {}).forEach(([tf, zones]) => {
        if (!Array.isArray(zones)) return;
        for (const z of zones) {
            if (!z || typeof z !== 'object') continue;
            merged.push({
                ...z,
                scan_timeframe: normalizeTimeframeLabel(z.scan_timeframe || tf || getChartTimeframe(), getChartTimeframe()),
            });
        }
    });
    merged.sort((a, b) => Number(a?.end_time_unix || a?.start_time_unix || 0) - Number(b?.end_time_unix || b?.start_time_unix || 0));
    return merged;
}

function renderAllFvgOverlays(force = false) {
    if (!zoneRenderer) return;
    if (!force && renderedToolId && renderedToolId !== 'fvg') return;
    zoneRenderer.clearAll();
    const merged = flattenFvgZonesAcrossTimeframes();
    if (merged.length === 0) {
        if (!renderedToolId || renderedToolId === 'fvg') renderedToolId = null;
        return;
    }
    renderedToolId = 'fvg';
    for (const z of merged) zoneRenderer.addZone(z);
}

function rebuildFvgNavigation() {
    fvgNavigationList = flattenFvgZonesAcrossTimeframes();
    if (!Array.isArray(fvgNavigationList) || fvgNavigationList.length === 0) {
        fvgNavigationIndex = -1;
    } else if (fvgNavigationIndex < 0 || fvgNavigationIndex >= fvgNavigationList.length) {
        fvgNavigationIndex = 0;
    }
    updateFvgJumpIndexLabel();
}

function updateFvgJumpIndexLabel() {
    const el = document.getElementById('fvg-jump-index');
    if (!el) return;
    if (!Array.isArray(fvgNavigationList) || fvgNavigationList.length === 0 || fvgNavigationIndex < 0) {
        el.textContent = '0/0';
        return;
    }
    el.textContent = `${fvgNavigationIndex + 1}/${fvgNavigationList.length}`;
}

function focusFvgZoneByIndex(idx) {
    if (!Array.isArray(fvgNavigationList) || fvgNavigationList.length === 0) return;
    const safe = Math.max(0, Math.min(fvgNavigationList.length - 1, Number(idx || 0)));
    fvgNavigationIndex = safe;
    const z = fvgNavigationList[safe];
    if (!z || !chart) {
        updateFvgJumpIndexLabel();
        return;
    }
    const ts = Number(z.end_time_unix || z.start_time_unix || 0);
    if (Number.isFinite(ts) && ts > 0) {
        const barSec = Math.max(60, timeframeToMinutes(getChartTimeframe()) * 60);
        const left = ts - (barSec * 120);
        const right = ts + (barSec * 50);
        chart.timeScale().setVisibleRange({ from: left, to: right });
    }
    updateFvgJumpIndexLabel();
    const scanTf = String(z.scan_timeframe || '').toUpperCase();
    const label = String(z.type || '').includes('bear') ? 'bearish' : 'bullish';
    showStatus(`Jumped to ${label} FVG${scanTf ? ` (${scanTf})` : ''}`, 'info');
    renderFvgInspector(lastFvgInspectorZones, lastFvgInspectorSource);
}

function jumpFvgRelative(delta) {
    if (!Array.isArray(fvgNavigationList) || fvgNavigationList.length === 0) return;
    const n = fvgNavigationList.length;
    const start = fvgNavigationIndex >= 0 ? fvgNavigationIndex : 0;
    const next = (start + n + Number(delta || 0)) % n;
    focusFvgZoneByIndex(next);
}

function renderFvgInspector(zones, sourceLabel) {
    const listEl = document.getElementById('fvg-zone-list');
    const sourceEl = document.getElementById('fvg-inspector-source');
    if (!listEl) return;
    const normalized = Array.isArray(zones) ? zones.filter(z => z && typeof z === 'object') : [];
    lastFvgInspectorZones = normalized.slice();
    lastFvgInspectorSource = String(sourceLabel || 'manual');
    if (sourceEl) {
        sourceEl.textContent = String(sourceLabel || 'manual').toLowerCase();
    }
    if (normalized.length === 0) {
        listEl.innerHTML = '<div class="fvg-empty" id="fvg-zone-empty">No zones detected in current scan window.</div>';
        updateFvgJumpIndexLabel();
        return;
    }
    const topN = normalized
        .slice()
        .sort((a, b) => Number(b?.end_time_unix || b?.start_time_unix || 0) - Number(a?.end_time_unix || a?.start_time_unix || 0))
        .slice(0, 12);
    listEl.innerHTML = topN.map((z) => {
        const type = String(z.type || '');
        const label = type === 'bearish_fvg' ? 'Bearish FVG' : 'Bullish FVG';
        const top = Number(z.top);
        const bottom = Number(z.bottom);
        const hi = Number.isFinite(top) && Number.isFinite(bottom) ? Math.max(top, bottom) : NaN;
        const lo = Number.isFinite(top) && Number.isFinite(bottom) ? Math.min(top, bottom) : NaN;
        const originTop = Number(z.origin_top);
        const originBottom = Number(z.origin_bottom);
        const origHi = Number.isFinite(originTop) && Number.isFinite(originBottom) ? Math.max(originTop, originBottom) : NaN;
        const origLo = Number.isFinite(originTop) && Number.isFinite(originBottom) ? Math.min(originTop, originBottom) : NaN;
        const originalGap = Number(z.original_gap_size ?? z.gap_size);
        const currentGap = Number(z.current_gap_size ?? z.gap_size);
        const mitigations = Math.max(0, Number(z.mitigations || 0));
        const filled = !!z.filled;
        const statusClass = filled ? 'filled' : 'active';
        const statusLabel = filled ? 'filled' : 'active';
        const aligned = !!z.trend_aligned;
        const when = formatZoneTime(z.end_time_unix || z.start_time_unix);
        const tf = normalizeTimeframeLabel(z.scan_timeframe || getChartTimeframe(), getChartTimeframe());
        const navIdx = fvgNavigationList.findIndex((x) =>
            Number(x?.start_time_unix || 0) === Number(z?.start_time_unix || 0)
            && Number(x?.end_time_unix || 0) === Number(z?.end_time_unix || 0)
            && String(x?.type || '') === String(z?.type || '')
            && String(x?.scan_timeframe || '') === String(tf || '')
        );
        const selectedCls = navIdx >= 0 && navIdx === fvgNavigationIndex ? 'selected' : '';
        return `
            <div class="fvg-zone-item ${escapeHtml(type)} ${escapeHtml(selectedCls)}" data-fvg-nav-index="${navIdx}">
                <div class="fvg-zone-row">
                    <div class="fvg-zone-title">${escapeHtml(label)}</div>
                    <div class="fvg-zone-range">${escapeHtml(formatZonePrice(lo))} - ${escapeHtml(formatZonePrice(hi))}</div>
                </div>
                <div class="fvg-zone-meta">
                    <span class="fvg-pill">${escapeHtml(tf)}</span>
                    <span class="fvg-pill ${statusClass}">${escapeHtml(statusLabel)}</span>
                    <span class="fvg-pill ${aligned ? 'active' : ''}">${aligned ? 'trend-aligned' : 'counter-trend'}</span>
                    <span class="fvg-pill">gap ${escapeHtml(Number.isFinite(currentGap) ? currentGap.toFixed(getZonePriceDecimals()) : '-')}</span>
                    <span class="fvg-pill">orig ${escapeHtml(Number.isFinite(originalGap) ? originalGap.toFixed(getZonePriceDecimals()) : '-')}</span>
                    <span class="fvg-pill">orig-range ${escapeHtml(formatZonePrice(origLo))} - ${escapeHtml(formatZonePrice(origHi))}</span>
                    <span class="fvg-pill">mitigations ${escapeHtml(String(mitigations))}</span>
                    <span class="fvg-pill">${escapeHtml(when)}</span>
                </div>
            </div>
        `;
    }).join('');
}

function updateFvgStrengthBadge(movementStrength) {
    const el = document.getElementById('fvg-strength-badge');
    if (!el) return;
    const mv = movementStrength && typeof movementStrength === 'object' ? movementStrength : {};
    const score = Number(mv.score);
    const state = String(mv.state || '').toLowerCase();
    el.classList.remove('strong', 'steady', 'weakening', 'exhausted');
    if (!Number.isFinite(score)) {
        el.textContent = 'strength n/a';
        return;
    }
    const cls = ['strong', 'steady', 'weakening', 'exhausted'].includes(state) ? state : '';
    if (cls) el.classList.add(cls);
    el.textContent = `strength ${score.toFixed(1)} (${state || 'n/a'})`;
}

function renderMeanRevInspector(zones, sourceLabel) {
    const listEl = document.getElementById('mean-rev-zone-list');
    const sourceEl = document.getElementById('mean-rev-inspector-source');
    if (!listEl) return;
    const normalized = Array.isArray(zones) ? zones.filter(z => z && typeof z === 'object') : [];
    if (sourceEl) sourceEl.textContent = String(sourceLabel || 'manual').toLowerCase();
    if (normalized.length === 0) {
        listEl.innerHTML = '<div class="fvg-empty" id="mean-rev-zone-empty">No signals detected in current scan window.</div>';
        return;
    }
    const topN = normalized
        .slice()
        .sort((a, b) => Number(b?.end_time_unix || b?.start_time_unix || 0) - Number(a?.end_time_unix || a?.start_time_unix || 0))
        .slice(0, 12);

    listEl.innerHTML = topN.map((z) => {
        const type = String(z.type || '');
        let label = 'Mean Signal';
        if (type === 'buy_zone') label = 'Buy Zone (Below Lower Band)';
        else if (type === 'sell_zone') label = 'Sell Zone (Above Upper Band)';
        else if (type === 'mean_cross') label = 'Mean Cross (Flatten)';
        const top = Number(z.top);
        const bottom = Number(z.bottom);
        const hi = Number.isFinite(top) && Number.isFinite(bottom) ? Math.max(top, bottom) : NaN;
        const lo = Number.isFinite(top) && Number.isFinite(bottom) ? Math.min(top, bottom) : NaN;
        const zScore = Number(z.z_score);
        const strength = Number(z.signal_strength);
        const when = formatZoneTime(z.end_time_unix || z.start_time_unix);
        return `
            <div class="fvg-zone-item ${escapeHtml(type)}">
                <div class="fvg-zone-row">
                    <div class="fvg-zone-title">${escapeHtml(label)}</div>
                    <div class="fvg-zone-range">${escapeHtml(formatZonePrice(lo))} - ${escapeHtml(formatZonePrice(hi))}</div>
                </div>
                <div class="fvg-zone-meta">
                    <span class="fvg-pill">${escapeHtml(type)}</span>
                    <span class="fvg-pill">z ${escapeHtml(Number.isFinite(zScore) ? zScore.toFixed(2) : '-')}</span>
                    <span class="fvg-pill">strength ${escapeHtml(Number.isFinite(strength) ? strength.toFixed(2) : '-')}</span>
                    <span class="fvg-pill">${escapeHtml(when)}</span>
                </div>
            </div>
        `;
    }).join('');
}

function updateMeanRevZscoreBadge(currentState) {
    const el = document.getElementById('mean-rev-zscore-badge');
    if (!el) return;
    el.classList.remove('overextended-up', 'overextended-down');
    const state = (currentState && typeof currentState === 'object') ? currentState : {};
    const z = Number(state.z_score);
    if (!Number.isFinite(z)) {
        el.textContent = 'z n/a';
        return;
    }
    if (z >= 2.0) el.classList.add('overextended-up');
    if (z <= -2.0) el.classList.add('overextended-down');
    el.textContent = `z ${z.toFixed(2)} (${escapeHtml(String(state.state || 'neutral'))})`;
}

// â”€â”€ Chart Zone Renderer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        div.className = `fvg-zone ${zone.type}${zone.filled ? ' filled' : ''}`;
        div.dataset.zoneId = String(zone.bar_index);
        div.dataset.scanTf = String(zone.scan_timeframe || '');
        const type = String(zone.type || '');
        let direction = 'Zone';
        if (type === 'bullish_fvg') direction = 'Bullish FVG';
        else if (type === 'bearish_fvg') direction = 'Bearish FVG';
        else if (type === 'buy_zone') direction = 'MeanRev Buy Zone';
        else if (type === 'sell_zone') direction = 'MeanRev Sell Zone';
        else if (type === 'mean_cross') direction = 'MeanRev Mean Cross';
        const top = Number(zone.top);
        const bottom = Number(zone.bottom);
        const rangeLabel = `${formatZonePrice(Math.min(top, bottom))} - ${formatZonePrice(Math.max(top, bottom))}`;
        const originTop = Number(zone.origin_top);
        const originBottom = Number(zone.origin_bottom);
        const originRangeLabel = (Number.isFinite(originTop) && Number.isFinite(originBottom))
            ? `${formatZonePrice(Math.min(originTop, originBottom))} - ${formatZonePrice(Math.max(originTop, originBottom))}`
            : rangeLabel;
        const originalGap = Number(zone.original_gap_size ?? zone.gap_size);
        const currentGap = Number(zone.current_gap_size ?? zone.gap_size);
        const gapLabel = Number.isFinite(currentGap) ? currentGap.toFixed(getZonePriceDecimals()) : '-';
        const originalGapLabel = Number.isFinite(originalGap) ? originalGap.toFixed(getZonePriceDecimals()) : '-';
        const mitigationCount = Math.max(0, Number(zone.mitigations || 0));
        const zLabel = Number.isFinite(Number(zone.z_score)) ? Number(zone.z_score).toFixed(2) : null;
        const statusLabel = zone.filled ? 'Filled' : 'Active';
        const extra = zLabel !== null ? ` | Z: ${zLabel}` : '';
        const scanTf = String(zone.scan_timeframe || '').toUpperCase();
        div.title = `${direction}${scanTf ? ` [${scanTf}]` : ''} | Range: ${rangeLabel} | OrigRange: ${originRangeLabel} | Gap: ${gapLabel} | OrigGap: ${originalGapLabel}${extra} | ${statusLabel}${mitigationCount > 0 ? ` | Mitigations: ${mitigationCount}` : ''}`;

        const colorCfg = zone.style || getFvgTfStyle(scanTf || getChartTimeframe(), type);
        if (colorCfg && typeof colorCfg === 'object') {
            if (colorCfg.bg) div.style.backgroundColor = String(colorCfg.bg);
            if (colorCfg.border) div.style.border = `1px solid ${String(colorCfg.border)}`;
        }

        let topLine = null;
        let bottomLine = null;
        const isFvg = type === 'bullish_fvg' || type === 'bearish_fvg';
        // For FVGs, top/bottom boundaries are drawn via dedicated extension lines.
        // Avoid rectangle borders that can visually imply incorrect boundary start times.
        if (isFvg) {
            div.style.border = 'none';
        }
        if (isFvg) {
            topLine = document.createElement('div');
            bottomLine = document.createElement('div');
            topLine.className = 'fvg-zone-line';
            bottomLine.className = 'fvg-zone-line';
            const lineCol = (colorCfg && colorCfg.line) ? String(colorCfg.line) : 'rgba(148,163,184,0.9)';
            topLine.style.borderTopColor = lineCol;
            bottomLine.style.borderTopColor = lineCol;
            this.overlayContainer.appendChild(topLine);
            this.overlayContainer.appendChild(bottomLine);
        }

        this.overlayContainer.appendChild(div);
        this.zones.push({ data: zone, el: div, topLine, bottomLine });
        this._positionZone(zone, div, topLine, bottomLine);
    }

    _resolveBoundaryStarts(zone) {
        const zType = String(zone?.type || '').toLowerCase();
        const startTs = Number(zone?.start_time_unix || 0);
        const endTs = Number(zone?.end_time_unix || startTs || 0);
        const lastMitTs = Number(zone?.last_mitigated_unix || 0);

        // FVG structure:
        // bullish: top from candle3.low (end), bottom from candle1.high (start)
        // bearish: top from candle1.low (start), bottom from candle3.high (end)
        // mitigation updates top for bullish and bottom for bearish.
        let topStartTs = endTs;
        let bottomStartTs = startTs;
        if (zType === 'bearish_fvg') {
            topStartTs = startTs;
            bottomStartTs = endTs;
        }
        if (lastMitTs > 0) {
            if (zType === 'bullish_fvg') topStartTs = lastMitTs;
            if (zType === 'bearish_fvg') bottomStartTs = lastMitTs;
        }
        return {
            topStartTs: Number.isFinite(topStartTs) && topStartTs > 0 ? topStartTs : endTs,
            bottomStartTs: Number.isFinite(bottomStartTs) && bottomStartTs > 0 ? bottomStartTs : startTs,
        };
    }

    _resolveX(timeScale, ts, fallback = 0) {
        const v = timeScale.timeToCoordinate(ts);
        if (v !== null && Number.isFinite(Number(v))) return Number(v);
        const vr = timeScale.getVisibleRange();
        if (vr && Number.isFinite(Number(vr.from)) && Number.isFinite(Number(vr.to))) {
            if (ts < Number(vr.from)) return 0;
            if (ts > Number(vr.to)) return null;
        }
        return Number.isFinite(Number(fallback)) ? Number(fallback) : 0;
    }

    _positionZone(zone, div, topLine = null, bottomLine = null) {
        const timeScale = this.chart.timeScale();
        const x1 = timeScale.timeToCoordinate(zone.start_time_unix);
        const x2 = timeScale.timeToCoordinate(zone.end_time_unix);
        const y1 = this.series.priceToCoordinate(zone.top);
        const y2 = this.series.priceToCoordinate(zone.bottom);

        if (y1 === null || y2 === null) {
            div.style.display = 'none';
            if (topLine) topLine.style.display = 'none';
            if (bottomLine) bottomLine.style.display = 'none';
            return;
        }

        const paneH = Number(this.container.clientHeight || this.overlayContainer.clientHeight || 0);
        const priceAreaBottom = paneH > 0 ? (paneH * 0.88) : null;
        if (priceAreaBottom !== null && Number.isFinite(priceAreaBottom)) {
            // Hide obvious off-pane artifacts (typically when coordinates collapse into indicator/volume zone).
            if (Math.min(y1, y2) > priceAreaBottom) {
                div.style.display = 'none';
                if (topLine) topLine.style.display = 'none';
                if (bottomLine) bottomLine.style.display = 'none';
                return;
            }
        }

        const starts = this._resolveBoundaryStarts(zone);
        const fallbackX = (x2 !== null) ? Number(x2) : ((x1 !== null) ? Number(x1) : 0);
        const topXStart = this._resolveX(timeScale, starts.topStartTs, fallbackX);
        const bottomXStart = this._resolveX(timeScale, starts.bottomStartTs, fallbackX);
        if (topXStart === null && bottomXStart === null) {
            div.style.display = 'none';
            if (topLine) topLine.style.display = 'none';
            if (bottomLine) bottomLine.style.display = 'none';
            return;
        }
        // Current active gap starts where BOTH current boundaries are valid.
        // Using max(starts) avoids displaying a rectangle before the active gap exists.
        const zoneStart = Math.max(
            0,
            Math.max(
                Number.isFinite(Number(topXStart)) ? Number(topXStart) : Number(bottomXStart),
                Number.isFinite(Number(bottomXStart)) ? Number(bottomXStart) : Number(topXStart),
            ),
        );
        let left = zoneStart;
        const width = Math.max(6, (this.container.clientWidth || this.overlayContainer.clientWidth || 0) - left - 2);
        div.style.display = 'block';
        div.style.left = `${left}px`;
        div.style.top = `${Math.min(y1, y2)}px`;
        div.style.width = `${width}px`;
        div.style.height = `${Math.max(Math.abs(y2 - y1), 2)}px`;

        if (topLine && bottomLine) {
            const yTop = Math.min(y1, y2);
            const yBottom = Math.max(y1, y2);
            const topLeft = Math.max(0, Number.isFinite(Number(topXStart)) ? Number(topXStart) : left);
            const bottomLeft = Math.max(0, Number.isFinite(Number(bottomXStart)) ? Number(bottomXStart) : left);
            const topWidth = Math.max(4, (this.container.clientWidth || this.overlayContainer.clientWidth || 0) - topLeft - 2);
            const bottomWidth = Math.max(4, (this.container.clientWidth || this.overlayContainer.clientWidth || 0) - bottomLeft - 2);
            topLine.style.display = 'block';
            bottomLine.style.display = 'block';
            topLine.style.left = `${topLeft}px`;
            bottomLine.style.left = `${bottomLeft}px`;
            topLine.style.width = `${topWidth}px`;
            bottomLine.style.width = `${bottomWidth}px`;
            topLine.style.top = `${yTop}px`;
            bottomLine.style.top = `${yBottom}px`;
        }
    }

    _repositionAll() {
        for (const z of this.zones) {
            this._positionZone(z.data, z.el, z.topLine, z.bottomLine);
        }
    }

    clearAll() {
        for (const z of this.zones) {
            z.el.remove();
            if (z.topLine) z.topLine.remove();
            if (z.bottomLine) z.bottomLine.remove();
        }
        this.zones = [];
    }
}


// â”€â”€ Initialization â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

document.addEventListener('DOMContentLoaded', () => {
    tickMs = getTickMsForSpeed(playSpeed);
    setTransportMode('IDLE');
    updateSessionIdStat();
    updateSpeedButtons();
    updatePerfStats();
    initChart();
    bindEvents();
    initWorkbenchState();
    clearPersistedSessionId();
    applyWorkbenchModeUI();
    setWorkbenchFullscreenUI(!!document.fullscreenElement);
});

function initWorkbenchState() {
    fvgZonesByTimeframe = {};
    fvgNavigationList = [];
    fvgNavigationIndex = -1;
    lastFvgInspectorZones = [];
    lastFvgInspectorSource = 'idle';
    warnedDatabentoCreditsForFvg = false;
    toolStates = {
        fvg: {
            enabled: false,
            scan_count: 0,
            last_zone_count: 0,
            zones_sample: [],
            show_filled: false,
            min_gap: null,
            trend_filter_enabled: true,
            trend_multiplier: 3,
            trend_alignment_mode: 'prefer',
            movement_strength: {},
            detect_timeframe: 'M15',
            scan_scope: 'last_n_days',
            lookback_days: 2,
            config: {},
        },
        mean_rev: {
            enabled: false,
            scan_count: 0,
            last_zone_count: 0,
            zones_sample: [],
            strictness: 3,
            sma_period: 30,
            deviation: 2.0,
            show_exit_signals: true,
            scan_scope: 'last_n_days',
            lookback_days: 2,
            current_state: {},
            config: {},
        },
        liquidity: {
            enabled: false,
            scan_count: 0,
            last_zone_count: 0,
            zones_sample: [],
            current_state: {},
            movement_strength: {},
            config: {},
        },
        draw_fvg: {
            enabled: false,
            picks: [],
        },
    };
    if (toolStates?.fvg) {
        toolStates.fvg.detect_timeframe = getChartTimeframe();
    }
    const detectTfEl = document.getElementById('fvg-detect-timeframe');
    if (detectTfEl) detectTfEl.value = 'chart';
    renderedToolId = null;
    initConsultantState();
    applyCostModelToUI(null);
    renderCostModelSummary(null);
    setLiveFeedButtonState(false);
    updateSessionIdStat();
    renderFvgInspector([], 'idle');
    updateFvgJumpIndexLabel();
    updateFvgStrengthBadge(null);
    renderMeanRevInspector([], 'idle');
    updateMeanRevZscoreBadge(null);
    const drawToggle = document.getElementById('tool-draw-fvg-toggle');
    if (drawToggle) drawToggle.checked = false;
    const drawSettings = document.getElementById('draw-fvg-settings');
    if (drawSettings) drawSettings.classList.remove('active');
    const drawStatus = document.getElementById('draw-fvg-status');
    if (drawStatus) drawStatus.textContent = 'Pick two bars on chart to begin.';
    tradeMarkers = [];
    goldenCrossMarkers = [];
    fvgCreatorMarkers = [];
    clearAllIndicatorSeries();
    readIndicatorSelectionFromUI();
    syncCandleMarkers();
    updateIndicatorsOnChart();
    syncFullscreenMarketControlsFromMain();
    agentMemoryRows = [];
    agentMemoryPolicy = null;
    agentIdentityState = null;
    agentScheduledTriggers = [];
    pendingAgentApprovals = [];
    agentExecutionTrace = [];
    lastPendingTraceBySignature = {};
    seenWatchdogApprovalSignatures = {};
    stopPendingApprovalTimer();
    applyAgentMemoryPolicyToUI(null);
    renderAgentMemoryList([]);
    renderAgentTriggerList([]);
    renderPendingAgentApprovals();
    renderAgentExecutionTrace();
    applyAgentIdentityToUI(AGENT_IDENTITY_DEFAULTS);
    if (sessionId) {
        void refreshAgentMemoryList('');
        void refreshAgentIdentity(false);
        void refreshAgentTriggerList(false);
    }
}

function initChart() {
    const container = document.getElementById('chart-main');
    if (!container || typeof LightweightCharts === 'undefined') {
        console.error('Chart container or LightweightCharts not found');
        return;
    }

    chart = LightweightCharts.createChart(container, {
        width: container.clientWidth,
        height: 450,
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
        rightPriceScale: { borderColor: '#2a2e39' },
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

    volumeSeries = chart.addHistogramSeries({
        color: '#385263',
        priceFormat: { type: 'volume' },
        priceScaleId: 'volume',
    });
    chart.priceScale('volume').applyOptions({
        scaleMargins: { top: 0.85, bottom: 0 },
    });

    const resizeObserver = new ResizeObserver(entries => {
        for (const entry of entries) {
            chart.applyOptions({ width: entry.contentRect.width });
        }
    });
    resizeObserver.observe(container);

    // Initialize zone renderer
    zoneRenderer = new ChartZoneRenderer(chart, candleSeries);
    if (chartClickHandler) {
        try { chart.unsubscribeClick(chartClickHandler); } catch (_) { /* ignore */ }
    }
    chartClickHandler = (param) => { void handleDrawFvgChartClick(param); };
    chart.subscribeClick(chartClickHandler);
}

function bindEvents() {
    ensurePanelHomeMarkers();
    document.getElementById('btn-toggle-fullscreen')?.addEventListener('click', toggleWorkbenchFullscreen);
    document.addEventListener('fullscreenchange', () => {
        setWorkbenchFullscreenUI(!!document.fullscreenElement);
    });
    document.querySelectorAll('[data-panel-launch]').forEach((btn) => {
        btn.addEventListener('click', () => {
            const kind = String(btn.getAttribute('data-panel-launch') || '').trim().toLowerCase();
            openWorkbenchPanel(kind);
        });
    });
    document.getElementById('dock-open-research')?.addEventListener('click', () => {
        const m = document.getElementById('researchModal');
        if (!m || typeof bootstrap === 'undefined') return;
        bootstrap.Modal.getOrCreateInstance(m).show();
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
        void toggleWorkbenchFullscreen();
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
    Object.entries(WORKBENCH_PANELS).forEach(([kind, cfg]) => {
        const modalEl = document.getElementById(cfg.modalId);
        if (!modalEl) return;
        modalEl.addEventListener('hidden.bs.modal', () => {
            restorePanelHome(kind);
            setDockActiveState(kind, false);
            requestAnimationFrame(() => setTimeout(refreshChartViewport, 40));
        });
    });
    document.querySelectorAll('.panel-toggle[data-target]').forEach((el) => {
        el.addEventListener('click', () => {
            const targetSel = String(el.getAttribute('data-target') || '').trim();
            if (!targetSel) return;
            const body = document.querySelector(targetSel);
            if (!body) return;
            body.classList.toggle('d-none');
        });
    });
    document.getElementById('workbench-mode')?.addEventListener('change', () => {
        applyWorkbenchModeUI();
        const mode = getWorkbenchMode();
        showStatus(mode === 'replay' ? 'Playback trading mode selected.' : 'Normal live mode selected.', 'info');
    });
    document.getElementById('btn-start-session')?.addEventListener('click', startSession);
    document.getElementById('btn-live-feed')?.addEventListener('click', toggleLiveFeed);
    document.getElementById('sim-symbol')?.addEventListener('change', () => {
        updateCostModelHint();
        const spreadEl = document.getElementById('cost-model-spread');
        if (spreadEl && (!spreadEl.value || Number.isNaN(Number(spreadEl.value)))) {
            spreadEl.value = String(getDefaultSpreadForSymbol(getCostModelSymbol()));
        }
        void autoSwitchLiveContextFromInputs('symbol change');
    });
    document.getElementById('sim-timeframe')?.addEventListener('change', () => {
        void autoSwitchLiveContextFromInputs('timeframe change');
    });
    document.getElementById('cost-model-spread-source')?.addEventListener('change', updateCostModelHint);
    document.getElementById('btn-cost-model-apply')?.addEventListener('click', applySessionCostModelConfig);
    document.getElementById('live-source')?.addEventListener('change', () => {
        if (getSelectedLiveSource() === 'mt5') warnedDatabentoCreditsForFvg = false;
        if (!liveFeedActive && !liveFeedRequested) setLiveFeedButtonState(false);
        void autoSwitchLiveContextFromInputs('source change');
    });
    document.getElementById('live-history-days')?.addEventListener('change', () => {
        const el = document.getElementById('live-history-days');
        const normalized = getLiveHistoryDays();
        if (el) el.value = String(normalized);
        if (fullscreenWorkbench) {
            const fsDays = document.getElementById('fs-market-days');
            if (fsDays) fsDays.value = String(normalized);
        }
        void autoSwitchLiveContextFromInputs('window change');
    });
    document.getElementById('fvg-scan-scope')?.addEventListener('change', updateFvgScopeControls);
    document.getElementById('fvg-detect-timeframe')?.addEventListener('change', () => {
        const tf = getFvgDetectionTimeframe();
        showStatus(`FVG detection timeframe set to ${tf}`, 'info');
    });
    document.getElementById('mean-rev-scan-scope')?.addEventListener('change', updateMeanRevScopeControls);
    document.getElementById('research-strategy-type')?.addEventListener('change', updateResearchFormVisibility);
    document.getElementById('btn-research-run')?.addEventListener('click', runResearchOptimize);
    document.getElementById('btn-ml-diagnostic-run')?.addEventListener('click', runMLDiagnostic);
    document.getElementById('consultant-provider')?.addEventListener('change', () => {
        updateConsultantProviderDefaults();
        saveAgentProviderPrefs();
    });
    document.getElementById('consultant-model')?.addEventListener('change', saveAgentProviderPrefs);
    document.getElementById('consultant-model')?.addEventListener('input', saveAgentProviderPrefs);
    document.getElementById('consultant-url')?.addEventListener('change', saveAgentProviderPrefs);
    document.getElementById('agent-timeout')?.addEventListener('change', saveAgentProviderPrefs);
    document.getElementById('agent-can-auto-execute')?.addEventListener('change', () => {
        syncAgentPermissionDependencies();
    });
    document.getElementById('agent-require-confirm')?.addEventListener('change', () => {
        syncAgentPermissionDependencies();
    });
    document.getElementById('agent-can-place-trades')?.addEventListener('change', () => {
        syncAgentPermissionDependencies();
    });
    document.getElementById('agent-can-close-trades')?.addEventListener('change', () => {
        syncAgentPermissionDependencies();
    });
    document.getElementById('btn-consultant-send')?.addEventListener('click', sendConsultantMessage);
    document.getElementById('btn-remember-last-reply')?.addEventListener('click', () => {
        void rememberLastAssistantReply();
    });
    document.getElementById('consultant-input')?.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            void sendConsultantMessage();
        }
    });
    document.getElementById('consultant-session-select')?.addEventListener('change', (e) => {
        switchConsultantSession(String(e.target?.value || ''));
    });
    document.getElementById('btn-consultant-new-session')?.addEventListener('click', () => {
        createConsultantSession();
    });
    document.getElementById('btn-consultant-delete-session')?.addEventListener('click', () => {
        deleteConsultantSession();
    });
    document.getElementById('consultant-chat-log')?.addEventListener('click', onConsultantChatLogClick);
    document.getElementById('agent-approval-list')?.addEventListener('click', (e) => {
        void onAgentApprovalListClick(e);
    });
    document.getElementById('btn-inline-approval-approve')?.addEventListener('click', () => {
        const id = String(document.getElementById('btn-inline-approval-approve')?.getAttribute('data-approval-id') || '').trim();
        if (!id) return;
        void approvePendingAgentApproval(id);
    });
    document.getElementById('btn-inline-approval-cancel')?.addEventListener('click', () => {
        const id = String(document.getElementById('btn-inline-approval-cancel')?.getAttribute('data-approval-id') || '').trim();
        if (!id) return;
        cancelPendingAgentApproval(id);
    });
    document.getElementById('btn-open-agent-trace')?.addEventListener('click', () => {
        toggleAgentTraceWindow(true);
    });
    document.getElementById('btn-close-agent-trace')?.addEventListener('click', () => {
        toggleAgentTraceWindow(false);
    });
    document.getElementById('btn-clear-agent-trace')?.addEventListener('click', () => {
        clearAgentExecutionTrace();
    });
    document.getElementById('btn-open-agent-triggers')?.addEventListener('click', () => {
        toggleAgentTriggerWindow(true);
    });
    document.getElementById('btn-close-agent-triggers')?.addEventListener('click', () => {
        toggleAgentTriggerWindow(false);
    });
    document.getElementById('btn-refresh-agent-triggers-window')?.addEventListener('click', () => {
        void refreshAgentTriggerList(true);
    });
    document.getElementById('btn-cancel-all-agent-triggers-window')?.addEventListener('click', () => {
        void cancelAllAgentTriggers();
    });
    document.getElementById('btn-agent-trigger-refresh')?.addEventListener('click', () => {
        void refreshAgentTriggerList(true);
    });
    document.getElementById('btn-agent-trigger-cancel-all')?.addEventListener('click', () => {
        void cancelAllAgentTriggers();
    });
    document.getElementById('agent-trigger-list')?.addEventListener('click', (e) => {
        onAgentTriggerListClick(e);
    });
    document.getElementById('agent-trigger-list-modal')?.addEventListener('click', (e) => {
        onAgentTriggerListClick(e);
    });
    document.getElementById('btn-agent-memory-search')?.addEventListener('click', () => {
        void refreshAgentMemoryList();
    });
    document.getElementById('btn-agent-memory-toggle')?.addEventListener('click', () => {
        toggleAgentMemoryFields(null);
    });
    document.getElementById('btn-agent-memory-refresh')?.addEventListener('click', () => {
        void refreshAgentMemoryList('');
    });
    document.getElementById('btn-agent-memory-add')?.addEventListener('click', () => {
        void addAgentMemoryFromPanel();
    });
    document.getElementById('btn-agent-memory-policy-apply')?.addEventListener('click', () => {
        void applyAgentMemoryPolicyFromUI();
    });
    document.getElementById('btn-agent-identity-toggle')?.addEventListener('click', () => {
        toggleAgentIdentityFields(null);
    });
    document.getElementById('btn-agent-identity-refresh')?.addEventListener('click', () => {
        void refreshAgentIdentity(true);
    });
    document.getElementById('btn-agent-identity-save')?.addEventListener('click', () => {
        void saveAgentIdentityFromUI();
    });
    document.getElementById('agent-identity-preset')?.addEventListener('change', async (e) => {
        const key = String(e?.target?.value || 'apprentice');
        applyAgentIdentityPresetFromUI(key);
        if (sessionId) await saveAgentIdentityFromUI();
    });
    document.getElementById('agent-memory-query')?.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            void refreshAgentMemoryList();
        }
    });
    document.getElementById('agent-memory-new')?.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            void addAgentMemoryFromPanel();
        }
    });
    document.getElementById('agent-memory-list')?.addEventListener('click', (e) => {
        void onAgentMemoryListClick(e);
    });
    document.getElementById('btn-agent-memory-edit-save')?.addEventListener('click', () => {
        void saveAgentMemoryEditFromModal();
    });
    document.getElementById('agent-memory-edit-content')?.addEventListener('keydown', (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
            e.preventDefault();
            void saveAgentMemoryEditFromModal();
        }
    });
    document.getElementById('agentMemoryEditModal')?.addEventListener('hidden.bs.modal', () => {
        agentMemoryEditId = null;
    });
    document.getElementById('btn-agent-run-once')?.addEventListener('click', () => {
        void runAgentOnce();
    });
    document.getElementById('btn-agent-refresh')?.addEventListener('click', () => {
        void refreshAgentState(true);
    });
    updateFvgScopeControls();
    updateMeanRevScopeControls();
    updateResearchFormVisibility();
    syncAgentPermissionDependencies();
    syncAgentGuardrailControls();
    syncAgentNewsProviderControls();
    toggleAgentIdentityFields(false);
    toggleAgentMemoryFields(false);
    document.getElementById('agent-guardrail-enabled')?.addEventListener('change', () => {
        syncAgentGuardrailControls();
    });
    document.getElementById('agent-guardrail-news-filter')?.addEventListener('change', () => {
        syncAgentGuardrailControls();
    });
    document.getElementById('agent-news-provider')?.addEventListener('change', () => {
        syncAgentNewsProviderControls();
    });
    document.getElementById('agent-news-llm-summary')?.addEventListener('change', () => {
        syncAgentNewsProviderControls();
    });
    ['ind-sma-ema', 'ind-adx', 'ind-rsi', 'ind-stoch', 'ind-bollinger', 'ind-golden-cross'].forEach((id) => {
        document.getElementById(id)?.addEventListener('change', () => {
            readIndicatorSelectionFromUI();
            updateIndicatorsOnChart();
        });
    });
    document.getElementById('btn-indicators-reset')?.addEventListener('click', resetIndicatorSelectionUI);

    // Playback
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
            if (changed && sessionId && isPlaying) { stopPlay(); startPlay(); return; }
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

    // Reset
    document.getElementById('btn-reset')?.addEventListener('click', resetSession);

    // Keyboard
    document.addEventListener('keydown', (e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'SELECT' || e.target.tagName === 'TEXTAREA') return;
        switch(e.code) {
            case 'Space': e.preventDefault(); togglePlay(); break;
            case 'ArrowRight': advanceBars(1); break;
            case 'ArrowLeft': advanceBars(-1); break;
        }
    });

    // FVG tool events
    document.getElementById('tool-fvg-toggle')?.addEventListener('change', (e) => {
        const settings = document.getElementById('fvg-settings');
        if (settings) settings.classList.toggle('active', e.target.checked);
        if (!toolStates.fvg) toolStates.fvg = {};
        toolStates.fvg.enabled = !!e.target.checked;
        if (e.target.checked && sessionId) {
            scanFVG();
        } else {
            clearFVGZones();
        }
    });
    document.getElementById('btn-fvg-scan')?.addEventListener('click', scanFVG);
    document.getElementById('btn-fvg-clear')?.addEventListener('click', clearFVGZones);
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
    document.getElementById('btn-fvg-prev')?.addEventListener('click', () => jumpFvgRelative(-1));
    document.getElementById('btn-fvg-next')?.addEventListener('click', () => jumpFvgRelative(1));
    document.getElementById('fvg-zone-list')?.addEventListener('click', (e) => {
        const target = e.target instanceof Element ? e.target.closest('[data-fvg-nav-index]') : null;
        if (!target) return;
        const idx = Number(target.getAttribute('data-fvg-nav-index') || -1);
        if (Number.isFinite(idx) && idx >= 0) focusFvgZoneByIndex(idx);
    });

    document.getElementById('tool-mean-rev-toggle')?.addEventListener('change', (e) => {
        const settings = document.getElementById('mean-rev-settings');
        if (settings) settings.classList.toggle('active', e.target.checked);
        if (!toolStates.mean_rev) toolStates.mean_rev = {};
        toolStates.mean_rev.enabled = !!e.target.checked;
        if (e.target.checked && sessionId) {
            scanMeanRev();
        } else {
            clearMeanRevZones();
        }
    });
    document.getElementById('btn-mean-rev-scan')?.addEventListener('click', scanMeanRev);
    document.getElementById('btn-mean-rev-clear')?.addEventListener('click', clearMeanRevZones);

    // Agent loop events (copilot-backed runtime)
    document.getElementById('btn-agent-start')?.addEventListener('click', startAgentLoop);
    document.getElementById('btn-agent-stop')?.addEventListener('click', stopAgentLoop);
    document.getElementById('btn-agent-pause-auto')?.addEventListener('click', pauseAutoAgent);
    document.getElementById('btn-agent-resume-auto')?.addEventListener('click', resumeAutoAgent);
    document.getElementById('agent-feed')?.addEventListener('click', onAgentFeedClick);
    window.addEventListener('beforeunload', () => {
        stopAgentPoller();
        stopPendingApprovalTimer();
    });
}


// â”€â”€ Session Management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function renderTradeLog(trades) {
    const tbody = document.getElementById('trade-log-body');
    if (!tbody) return;
    tbody.innerHTML = '';
    const ordered = (trades || []).slice().reverse();
    for (const t of ordered) {
        if ((t.status || '').toLowerCase() === 'closed') addTradeToLog(t);
    }
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
    fvgCreatorMarkers = [];
    syncCandleMarkers();
    _syncDrawFvgStatusFromPicks();
}

function summarizeFvgZoneStats(zones) {
    const items = Array.isArray(zones) ? zones : [];
    let mitigations = 0;
    let filled = 0;
    for (const z of items) {
        mitigations += Math.max(0, Number(z?.mitigations || 0));
        if (z?.filled) filled += 1;
    }
    return {
        total: items.length,
        mitigations,
        filled,
        active: Math.max(0, items.length - filled),
    };
}

function buildFvgCreatorMarkers(zones) {
    const src = Array.isArray(zones) ? zones : [];
    const limited = src.slice(0, 60);
    const markers = [];
    const seen = new Set();
    for (let i = 0; i < limited.length; i += 1) {
        const z = limited[i] || {};
        const isBear = String(z.type || '').toLowerCase().includes('bear');
        const tA = Number(z.start_time_unix || 0);
        const tC = Number(z.end_time_unix || 0);
        const id = i + 1;
        if (Number.isFinite(tA) && tA > 0) {
            const keyA = `${tA}|A|${isBear ? 'B' : 'U'}|${id}`;
            if (!seen.has(keyA)) {
                seen.add(keyA);
                markers.push({
                    time: tA,
                    position: 'belowBar',
                    color: isBear ? '#f97316' : '#22c55e',
                    shape: 'circle',
                    text: `F${id}A`,
                });
            }
        }
        if (Number.isFinite(tC) && tC > 0) {
            const keyC = `${tC}|C|${isBear ? 'B' : 'U'}|${id}`;
            if (!seen.has(keyC)) {
                seen.add(keyC);
                markers.push({
                    time: tC,
                    position: 'aboveBar',
                    color: isBear ? '#ef4444' : '#10b981',
                    shape: 'square',
                    text: `F${id}C`,
                });
            }
        }
    }
    return markers;
}

async function scanDrawFvgSelection() {
    if (!sessionId) { showStatus('Start a session first', 'warning'); return; }
    const picks = Array.isArray(toolStates?.draw_fvg?.picks) ? toolStates.draw_fvg.picks : [];
    if (picks.length < 2) { showStatus('Pick two bars first', 'warning'); return; }
    const start = Math.min(picks[0], picks[1]);
    const end = Math.max(picks[0], picks[1]);
    const selected = Array.isArray(allBars) ? allBars.slice(start, end + 1) : [];
    if (selected.length < 3) { showStatus('Selection must include at least 3 bars', 'warning'); return; }

    const minGapInput = document.getElementById('fvg-min-gap')?.value;
    const showFilled = document.getElementById('fvg-show-filled')?.checked || false;
    const chartTf = getChartTimeframe();
    const config = {
        // Force all-zone fetch so mitigation/filled stats are complete for selected range.
        show_filled: true,
        scan_scope: 'visible',
        trend_filter_enabled: false,
        trend_alignment_mode: 'prefer',
        timeframe: chartTf,
        scan_timeframe: chartTf,
    };
    if (minGapInput && !isNaN(parseFloat(minGapInput))) config.min_gap = parseFloat(minGapInput);

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
        if (data.error) { showStatus(`manual FVG scan error: ${data.error}`, 'danger'); return; }

        const rawZones = Array.isArray(data?.zones) ? data.zones : [];
        const zonesAll = rawZones.map((z) => ({
            ...z,
            scan_timeframe: chartTf,
            style: getFvgTfStyle(chartTf, z?.type),
        }));
        const zones = showFilled ? zonesAll : zonesAll.filter((z) => !z?.filled);
        if (!fvgZonesByTimeframe || typeof fvgZonesByTimeframe !== 'object') fvgZonesByTimeframe = {};
        fvgZonesByTimeframe[chartTf] = zones;
        renderAllFvgOverlays(true);
        rebuildFvgNavigation();
        fvgCreatorMarkers = buildFvgCreatorMarkers(zones);
        syncCandleMarkers();

        if (!toolStates.fvg) toolStates.fvg = {};
        const mergedZones = flattenFvgZonesAcrossTimeframes();
        toolStates.fvg.last_zone_count = mergedZones.length;
        toolStates.fvg.zones_sample = mergedZones.slice(0, 20);
        toolStates.fvg.scan_count = Number(toolStates.fvg.scan_count || 0) + 1;
        renderFvgInspector(zones, `manual_selection | detect ${chartTf}`);
        updateFvgStrengthBadge(null);
        const badge = document.getElementById('fvg-zone-count');
        if (badge) {
            badge.textContent = String(mergedZones.length);
            badge.classList.toggle('d-none', mergedZones.length === 0);
        }
        const stats = summarizeFvgZoneStats(zonesAll);
        const shownPart = showFilled ? `${zones.length}` : `${zones.length}/${zonesAll.length}`;
        _updateDrawFvgStatus(`Selection scanned: shown ${shownPart}, active ${stats.active}, filled ${stats.filled}, mitigations ${stats.mitigations}.`);
        showStatus(
            `Manual FVG scan: shown ${shownPart} | active ${stats.active} | filled ${stats.filled} | mitigations ${stats.mitigations}`,
            zones.length > 0 ? 'success' : 'info'
        );
        await pushAgentToolState('TOOL_SIGNAL_CHANGED');
    } catch (err) {
        showStatus(`manual FVG scan error: ${err.message}`, 'danger');
    }
}

async function handleDrawFvgChartClick(param) {
    if (!toolStates?.draw_fvg?.enabled) return;
    const ts = _resolveUnixFromChartTime(param?.time);
    const idx = _findBarIndexByTime(ts);
    if (idx < 0) { showStatus('Could not map click to a candle. Zoom in and try again.', 'warning'); return; }
    if (!Array.isArray(toolStates.draw_fvg.picks)) toolStates.draw_fvg.picks = [];
    const picks = toolStates.draw_fvg.picks;
    if (picks.length >= 2) {
        toolStates.draw_fvg.picks = [idx];
    } else if (!(picks.length === 1 && picks[0] === idx)) {
        picks.push(idx);
    }
    _syncDrawFvgStatusFromPicks();
    if (toolStates.draw_fvg.picks.length >= 2) await scanDrawFvgSelection();
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
    lastAgentLivePushAtMs = 0;
    lastAgentLiveBarTime = 0;
    if (liveFeedSocket) {
        const s = liveFeedSocket;
        liveFeedSocket = null;
        try { s.close(); } catch (_) {}
    }
    setLiveFeedButtonState(false);
    if (sessionId && getWorkbenchMode() === 'replay') {
        document.getElementById('playback-controls')?.classList.remove('d-none');
        setTransportMode('READY');
    } else {
        document.getElementById('playback-controls')?.classList.add('d-none');
        if (!isPlaying) setTransportMode('IDLE');
    }
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

async function startLiveFeed(isReconnect = false) {
    if (getWorkbenchMode() !== 'live') {
        showStatus('Switch mode to "Normal (Live Feed)" to use live bars.', 'warning');
        return;
    }
    stopPlay();
    const symbol = document.getElementById('sim-symbol')?.value || 'XAUUSD';
    const timeframe = document.getElementById('sim-timeframe')?.value || 'M15';
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
            lastAgentLivePushAtMs = 0;
            lastAgentLiveBarTime = 0;
            setLiveFeedButtonState(true, source);
            setTransportMode(source === 'databento' ? 'DATABENTO' : 'MT5');
            showStatus(
                `${sourceLabel} live feed started: ${symbol} ${timeframe} (${historyDays} day window) | Session #${sessionId}`,
                'success'
            );
            document.getElementById('playback-controls')?.classList.add('d-none');
            document.getElementById('sim-config-panel')?.classList.remove('d-none');
            applyWorkbenchModeUI();
        };
        ws.onmessage = (event) => {
            let msg;
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
                updateIndicatorsOnChart();
                updateBarCounter();
                updateStats({ balance: initialBalance, total_pnl: 0, trades_count: 0, wins: 0 });
                void maybePushLiveAgentTick(true);
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
                updateIndicatorsOnChart();
                updateBarCounter();
                void maybePushLiveAgentTick(false);
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
    if (sessionId) {
        try {
            const existingRes = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}`);
            const existing = await existingRes.json().catch(() => ({}));
            if (existingRes.ok && existing?.id && String(existing.strategy_id || '') === STRATEGY_ID) {
                const sameSymbol = String(existing.symbol || '').toUpperCase() === String(symbol || '').toUpperCase();
                const sameTimeframe = String(existing.timeframe || '').toUpperCase() === String(timeframe || '').toUpperCase();
                applyCostModelToUI(existing?.cost_model || null);
                if (!sameSymbol || !sameTimeframe) {
                    showStatus(
                        `Live feed context switched to ${symbol} ${timeframe}. Current paper-trading session is preserved.`,
                        'info'
                    );
                }
                updateSessionIdStat();
                void refreshAgentMemoryList('');
                void refreshAgentIdentity(false);
                return true;
            }
        } catch (_) {
            // Fall through and recreate session.
        }
    }
    const dataFile = document.getElementById('sim-datafile')?.value || '';
    const balance = parseFloat(document.getElementById('sim-balance')?.value) || 10000;
    try {
        const costModelCfg = getCostModelConfigFromUI();
        const res = await fetch(`${API_BASE}/api/simulation/sessions`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                strategy_id: STRATEGY_ID,
                symbol,
                timeframe,
                data_file: dataFile || null,
                initial_balance: balance,
                config: { cost_model: costModelCfg },
            }),
        });
        const data = await res.json();
        if (!res.ok || data?.error || !data?.id) {
            showStatus(`Session init failed: ${data?.error || 'backend error'}`, 'danger');
            return false;
        }
        sessionId = data.id;
        persistSessionId(sessionId);
        updateSessionIdStat();
        setAgentChatAvailability(true);
        totalBars = Number(data.total_bars || 0);
        currentBar = 0;
        initialBalance = Number(data.initial_balance || balance || 10000);
        applyCostModelToUI(data?.cost_model || costModelCfg);
        updateStats({ balance: initialBalance, total_pnl: 0, trades_count: 0, wins: 0 });
        updateIndicatorsOnChart();
        void refreshAgentMemoryList('');
        void refreshAgentIdentity(false);
        return true;
    } catch (err) {
        showStatus(`Session init failed: ${err.message}`, 'danger');
        return false;
    }
}

async function applySessionCostModelConfig() {
    const cfg = getCostModelConfigFromUI();
    applyCostModelToUI(cfg);
    if (!sessionId) {
        showStatus('Cost model updated for next session start.', 'info');
        return;
    }
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/cost-model`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(cfg),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.error) {
            showStatus(`Cost model update failed: ${data?.error || res.status}`, 'danger');
            return;
        }
        applyCostModelToUI(data?.cost_model || cfg);
        showStatus('Cost model applied to active session.', 'success');
    } catch (err) {
        showStatus(`Cost model update failed: ${err.message || err}`, 'danger');
    }
}

async function startSession() {
    if (getWorkbenchMode() !== 'replay') {
        showStatus('Switch mode to "Playback Trading (CSV)" to start replay.', 'warning');
        return;
    }
    stopLiveFeed();
    stopPlay();
    stopAgentPoller();
    const symbol = document.getElementById('sim-symbol')?.value || 'XAUUSD';
    const timeframe = document.getElementById('sim-timeframe')?.value || 'M15';
    const dataFile = document.getElementById('sim-datafile')?.value || '';
    const balance = parseFloat(document.getElementById('sim-balance')?.value) || 10000;
    const costModelCfg = getCostModelConfigFromUI();

    try {
        showStatus('Creating session...');
        const res = await fetch(`${API_BASE}/api/simulation/sessions`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                strategy_id: STRATEGY_ID,
                symbol, timeframe,
                data_file: dataFile || null,
                initial_balance: balance,
                config: { cost_model: costModelCfg },
            }),
        });

        const data = await res.json();
        if (data.error) { showStatus(`Error: ${data.error}`, 'danger'); return; }

        sessionId = data.id;
        persistSessionId(sessionId);
        updateSessionIdStat();
        setAgentChatAvailability(true);
        totalBars = data.total_bars || 0;
        currentBar = 0;
        allBars = [];
        pendingAdvance = 0;
        isAdvancing = false;
        initialBalance = Number(data.initial_balance || balance);
        tickCounter = 0; tickWindowStartMs = 0; barsPerSecond = 0;
        lastPayloadAtMs = 0; adaptiveLastTuneMs = 0;
        wsReconnectRequested = false; droppedTickCount = 0; reconnectCount = 0;
        latencySamples = [];
        updatePerfStats();
        setTransportMode('READY');

        candleSeries.setData([]);
        volumeSeries.setData([]);
        if (zoneRenderer) zoneRenderer.clearAll();
        initWorkbenchState();
        applyCostModelToUI(data?.cost_model || costModelCfg);

        document.getElementById('playback-controls')?.classList.remove('d-none');
        document.getElementById('sim-config-panel')?.classList.add('d-none');
        applyWorkbenchModeUI();

        updateBarCounter();
        showStatus(`Session started: #${sessionId} ${symbol} ${timeframe} (${totalBars} bars)`, 'success');
        await advanceBars(50);
        await refreshAgentState(false);
        await refreshAgentMemoryList('');
        await refreshAgentIdentity(false);

    } catch (err) {
        showStatus(`Connection error: ${err.message}`, 'danger');
    }
}

async function resetSession() {
    if (!sessionId) return;
    stopPlay();
    stopAgentPoller();

    try {
        await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/reset`, { method: 'POST' });
        currentBar = 0;
        allBars = [];
        pendingAdvance = 0;
        tickCounter = 0; tickWindowStartMs = 0; barsPerSecond = 0;
        lastPayloadAtMs = 0; adaptiveLastTuneMs = 0;
        wsReconnectRequested = false; droppedTickCount = 0; reconnectCount = 0;
        latencySamples = [];
        updatePerfStats();
        setTransportMode('READY');
        candleSeries.setData([]);
        volumeSeries.setData([]);
        tradeMarkers = [];
        goldenCrossMarkers = [];
        fvgCreatorMarkers = [];
        clearAllIndicatorSeries();
        syncCandleMarkers();
        if (zoneRenderer) zoneRenderer.clearAll();
        resetDrawFvgPicks();
        updateBarCounter();
        updateStats({ balance: initialBalance, total_pnl: 0, trades_count: 0, wins: 0 });
        updateOpenPosition(null);
        showStatus('Session reset', 'info');
        await advanceBars(50);
        await refreshAgentState(false);
    } catch (err) {
        showStatus(`Reset error: ${err.message}`, 'danger');
    }
}


// â”€â”€ Bar Advancement â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async function advanceBars(count) {
    if (liveFeedActive) return;
    if (!sessionId) return;
    if (playSocket && count > 0) return;
    if (isAdvancing) {
        if (count > 0) pendingAdvance += count;
        return;
    }

    if (count < 0) {
        if (isPlaying) stopPlay();
        const newBar = Math.max(0, currentBar + count);
        if (newBar < currentBar) {
            currentBar = newBar;
            const visibleBars = allBars.slice(0, currentBar + 1);
            candleSeries.setData(visibleBars);
            volumeSeries.setData(visibleBars.map(b => ({
                time: b.time, value: b.volume || 0,
                color: b.close >= b.open ? '#26a69a44' : '#ef535044',
            })));
            updateIndicatorsOnChart();
            updateBarCounter();
            try {
                const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/seek?bar=${currentBar}`, { method: 'POST' });
                const data = await res.json();
                applyAdvancePayload(data);
            } catch (_) {}
        }
        return;
    }

    try {
        isAdvancing = true;
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/advance`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ count, indicators_mode: 'delta' }),
        });
        const data = await res.json();
        if (data.error) {
            if (String(data.error).toLowerCase().includes('session not found')) {
                clearPersistedSessionId();
                sessionId = null;
                updateSessionIdStat();
                stopAgentPoller();
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
            const consume = Math.min(queued, 50);
            setTimeout(() => advanceBars(consume), 0);
        }
    }
}


// â”€â”€ Playback Controls â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function togglePlay() { isPlaying ? stopPlay() : startPlay(); }

function startWsWatchdog() {
    stopWsWatchdog();
    wsWatchdogTimer = setInterval(() => {
        if (!isPlaying || !playSocket) return;
        const now = performance.now();
        if (!lastPayloadAtMs) return;
        const stallThreshold = Math.max(3000, tickMs * WS_STALL_FACTOR);
        if ((now - lastPayloadAtMs) > stallThreshold) {
            droppedTickCount += 1;
            showStatus('WS stream stalled, switching transport...', 'warning');
            wsReconnectRequested = false;
            try { playSocket.close(); } catch (_) {}
        }
    }, 1000);
}

function stopWsWatchdog() {
    if (wsWatchdogTimer) { clearInterval(wsWatchdogTimer); wsWatchdogTimer = null; }
}

function startPlay() {
    if (getWorkbenchMode() !== 'replay') {
        showStatus('Replay controls are available only in "Playback Trading (CSV)" mode.', 'warning');
        return;
    }
    if (liveFeedActive || liveFeedRequested) {
        showStatus('Stop live feed before replay playback.', 'warning');
        return;
    }
    if (!sessionId || isPlaying) return;
    isPlaying = true;
    document.getElementById('btn-play')?.querySelector('i')?.classList.replace('bi-play-fill', 'bi-pause-fill');
    tickCounter = 0; tickWindowStartMs = 0; barsPerSecond = 0;
    lastPayloadAtMs = 0; adaptiveLastTuneMs = 0; wsReconnectRequested = false;
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
            ws.onopen = () => { connected = true; clearTimeout(timeout); resolve(true); };
            ws.onmessage = (event) => {
                let msg;
                try { msg = JSON.parse(event.data); } catch (_) { return; }
                if (!msg || !msg.type) return;
                if (msg.type === 'tick' && msg.data) { applyAdvancePayload(msg.data); return; }
                if (msg.type === 'completed') { stopPlay(); showStatus(msg.message || 'Replay complete!', 'info'); return; }
                if (msg.type === 'error') { showStatus(`WS error: ${msg.message}`, 'warning'); try { ws.close(); } catch (_) {} }
            };
            ws.onerror = () => { clearTimeout(timeout); if (!connected) reject(new Error('WS error')); };
        });

        ws.onclose = () => {
            if (playSocket === ws) playSocket = null;
            if (isPlaying) {
                reconnectCount += 1;
                if (wsReconnectRequested) { wsReconnectRequested = false; void startWebSocketPlayback(); return; }
                showStatus('WebSocket disconnected, using HTTP playback', 'warning');
                startHttpPlaybackLoop();
            }
        };

        await readyPromise;
        lastPayloadAtMs = performance.now();
        startWsWatchdog();
        setTransportMode('WS');
        showStatus('Live streaming playback enabled', 'info');
    } catch (err) {
        if (playSocket) { try { playSocket.close(); } catch (_) {} playSocket = null; }
        if (isPlaying) { showStatus('WebSocket unavailable, using HTTP playback', 'warning'); startHttpPlaybackLoop(); }
    }
}

function startHttpPlaybackLoop() {
    if (!sessionId || !isPlaying || playSocket) return;
    stopWsWatchdog();
    setTransportMode('HTTP');
    if (playInterval) { clearTimeout(playInterval); playInterval = null; }
    const loop = async () => {
        if (!isPlaying || !sessionId) return;
        const t0 = performance.now();
        if (!isAdvancing) await advanceBars(playSpeed);
        const t1 = performance.now();
        lastAdvanceMs = Math.max(0, t1 - t0);
        recordLatencySample(lastAdvanceMs);
        if (!isPlaying || !sessionId) return;
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
    if (playInterval) { clearTimeout(playInterval); playInterval = null; }
    if (playSocket) { const s = playSocket; playSocket = null; try { s.close(); } catch (_) {} }
    setTransportMode('PAUSED');
}

function applyAdvancePayload(data) {
    if (!data) return;

    currentBar = data.current_bar ?? currentBar;
    totalBars = data.total_bars ?? totalBars;
    const barsAdded = Array.isArray(data.bars) ? data.bars.length : 0;
    const nowMs = performance.now();
    if (lastPayloadAtMs > 0) {
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

    updateIndicatorsOnChart();

    // No indicators/steps/suggestion/bias in workbench mode

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


// â”€â”€ Trade Execution â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async function executeTrade(direction) {
    if (!sessionId) return;
    const sl = parseFloat(document.getElementById('trade-sl')?.value);
    const tpLongRaw = parseFloat(document.getElementById('trade-tp-long')?.value);
    const tpShortRaw = parseFloat(document.getElementById('trade-tp-short')?.value);
    const tpLong = Number.isFinite(tpLongRaw) ? tpLongRaw : null;
    const tpShort = Number.isFinite(tpShortRaw) ? tpShortRaw : null;
    const tp = String(direction).toUpperCase() === 'BUY' ? tpLong : tpShort;
    const lots = parseFloat(document.getElementById('trade-lots')?.value) || 0.01;

    if (!sl || isNaN(sl)) { showStatus('Please set a Stop Loss', 'warning'); return; }

    try {
        const lastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
        const costCfg = getCostModelConfigFromUI();
        const body = {
            direction,
            stop_loss: sl,
            take_profit: tp,
            lot_size: lots,
            cost_spread: Number(costCfg.spread),
            cost_tc_rate: Number(costCfg.tc_rate),
            cost_spread_source: String(costCfg.spread_source || 'manual'),
        };
        if (liveFeedActive && lastBar && Number.isFinite(Number(lastBar.close))) {
            body.entry_price = Number(lastBar.close);
            body.bar_time_unix = Number(lastBar.time || 0);
        }
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/trade`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
        const data = await res.json();
        if (data.error) { showStatus(`Trade error: ${data.error}`, 'danger'); return; }

        updateOpenPosition(data, 0);
        renderCostModelSummary(data?.cost_breakdown || null);
        showStatus(`${direction} @ ${data.entry_price?.toFixed(2)}`, 'success');

        if (allBars.length > 0) {
            const lastBar = allBars[allBars.length - 1];
            tradeMarkers.push({
                time: lastBar.time,
                position: direction === 'BUY' ? 'belowBar' : 'aboveBar',
                color: direction === 'BUY' ? '#26a69a' : '#ef5350',
                shape: direction === 'BUY' ? 'arrowUp' : 'arrowDown',
                text: direction,
            });
            if (tradeMarkers.length > 400) tradeMarkers = tradeMarkers.slice(tradeMarkers.length - 400);
            syncCandleMarkers();
        }
    } catch (err) {
        showStatus(`Trade error: ${err.message}`, 'danger');
    }
}

async function closePosition() {
    if (!sessionId) return;
    const tradeId = document.getElementById('open-pos-id')?.dataset.tradeId;
    if (!tradeId) return;

    try {
        const lastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
        const costCfg = getCostModelConfigFromUI();
        let requestBody = {
            cost_spread: Number(costCfg.spread),
            cost_tc_rate: Number(costCfg.tc_rate),
            cost_spread_source: String(costCfg.spread_source || 'manual'),
        };
        if (liveFeedActive && lastBar && Number.isFinite(Number(lastBar.close))) {
            requestBody = {
                ...requestBody,
                exit_price: Number(lastBar.close),
                bar_time_unix: Number(lastBar.time || 0),
            };
        }
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/close-trade/${tradeId}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(requestBody),
        });
        const data = await res.json();
        if (data.error) { showStatus(`Close error: ${data.error}`, 'danger'); return; }
        updateOpenPosition(null);
        addTradeToLog(data);
        showTradeResult(data);
    } catch (err) {
        showStatus(`Close error: ${err.message}`, 'danger');
    }
}


// â”€â”€ FVG Tool â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

async function scanFVG() {
    if (!sessionId) { showStatus('Start a session first', 'warning'); return; }
    fvgCreatorMarkers = [];
    syncCandleMarkers();

    const minGapInput = document.getElementById('fvg-min-gap')?.value;
    const lookbackDaysInput = document.getElementById('fvg-lookback-days')?.value;
    const showFilled = document.getElementById('fvg-show-filled')?.checked || false;
    const scanScope = String(document.getElementById('fvg-scan-scope')?.value || 'last_n_days').toLowerCase();
    const trendFilterEnabled = document.getElementById('fvg-trend-filter')?.checked ?? true;
    const trendMultiplierInput = document.getElementById('fvg-trend-multiplier')?.value;
    const trendAlignmentMode = String(document.getElementById('fvg-trend-alignment-mode')?.value || 'prefer').toLowerCase();
    const chartTf = getChartTimeframe();
    const detectTf = getFvgDetectionTimeframe();

    const config = {
        show_filled: showFilled,
        scan_scope: scanScope === 'visible' ? 'visible' : 'last_n_days',
        trend_filter_enabled: !!trendFilterEnabled,
        trend_alignment_mode: trendAlignmentMode === 'strict' ? 'strict' : 'prefer',
        timeframe: detectTf,
        scan_timeframe: detectTf,
    };
    const trendMultiplierParsed = Number(trendMultiplierInput);
    if (Number.isFinite(trendMultiplierParsed)) {
        config.trend_multiplier = Math.max(2, Math.min(12, Math.round(trendMultiplierParsed)));
    }
    if (minGapInput && !isNaN(parseFloat(minGapInput))) {
        config.min_gap = parseFloat(minGapInput);
    }
    if (config.scan_scope === 'last_n_days' && lookbackDaysInput && !isNaN(parseFloat(lookbackDaysInput))) {
        config.lookback_days = Math.max(0.1, Math.min(30, parseFloat(lookbackDaysInput)));
    }
    if (!toolStates.fvg) toolStates.fvg = {};
    toolStates.fvg.show_filled = !!showFilled;
    toolStates.fvg.min_gap = config.min_gap ?? null;
    toolStates.fvg.trend_filter_enabled = !!config.trend_filter_enabled;
    toolStates.fvg.trend_multiplier = Number(config.trend_multiplier ?? toolStates.fvg.trend_multiplier ?? 3);
    toolStates.fvg.trend_alignment_mode = String(config.trend_alignment_mode || 'prefer');
    toolStates.fvg.scan_scope = config.scan_scope;
    toolStates.fvg.lookback_days = config.lookback_days ?? Number(toolStates.fvg.lookback_days || 2);
    toolStates.fvg.detect_timeframe = detectTf;
    toolStates.fvg.config = { ...config };

    try {
        showStatus(`Scanning for FVG zones (${detectTf})...`, 'info');
        let barsPayload = null;
        let scanSourceHint = '';
        const symbol = String(document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
        const source = getSelectedLiveSource();
        const lookbackDays = Number(config.lookback_days ?? 2);
        if (source === 'databento' && getWorkbenchMode() === 'live' && !warnedDatabentoCreditsForFvg) {
            showStatus('Databento HTF scans consume credits. Switch Live Source to MT5 if you want zero Databento usage.', 'warning');
            warnedDatabentoCreditsForFvg = true;
        }

        if (detectTf !== chartTf && getWorkbenchMode() === 'live') {
            try {
                const liveBars = await fetchLiveHistoryBars(symbol, detectTf, source, lookbackDays);
                if (Array.isArray(liveBars) && liveBars.length >= 3) {
                    let srcBars = liveBars.slice();
                    if (config.scan_scope === 'last_n_days' && Number.isFinite(lookbackDays)) srcBars = trimBarsByLookbackDays(srcBars, lookbackDays);
                    if (srcBars.length < 3) srcBars = liveBars.slice(-3);
                    barsPayload = barsToPayload(srcBars, 12000, 3);
                    if (barsPayload && barsPayload.length >= 3) scanSourceHint = `live_${source}_${detectTf.toLowerCase()}`;
                }
            } catch (err) {
                showStatus(`HTF fetch fallback to chart bars: ${err.message}`, 'warning');
            }
        }

        if (!barsPayload && detectTf !== chartTf && Array.isArray(allBars) && allBars.length >= 3) {
            let srcBars = aggregateBarsToTimeframe(allBars, detectTf);
            if (config.scan_scope === 'last_n_days' && Number.isFinite(lookbackDays)) srcBars = trimBarsByLookbackDays(srcBars, lookbackDays);
            if (srcBars.length < 3) srcBars = aggregateBarsToTimeframe(allBars.slice(-1200), detectTf);
            if (srcBars.length >= 3) {
                barsPayload = barsToPayload(srcBars, 12000, 3);
            }
            if (barsPayload && barsPayload.length >= 3) {
                scanSourceHint = `client_resample_${detectTf.toLowerCase()}`;
            }
        }

        if (!barsPayload && (liveFeedActive || liveFeedRequested) && Array.isArray(allBars) && allBars.length > 0) {
            let srcBars = allBars.slice();
            if (config.scan_scope === 'last_n_days' && Number.isFinite(Number(config.lookback_days))) srcBars = trimBarsByLookbackDays(srcBars, Number(config.lookback_days));
            if (srcBars.length < 3) srcBars = allBars.slice(-3);
            barsPayload = barsToPayload(srcBars, 12000, 3);
            if (barsPayload && !scanSourceHint) scanSourceHint = 'client_live';
        }

        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/tools/fvg/scan`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(barsPayload ? { config, bars: barsPayload } : { config }),
        });
        const data = await res.json();
        if (data.error) { showStatus(`FVG scan error: ${data.error}`, 'danger'); return; }

        const rawZones = Array.isArray(data?.zones) ? data.zones : [];
        const zones = rawZones.map((z) => {
            const tf = normalizeTimeframeLabel(detectTf, chartTf);
            return {
                ...z,
                scan_timeframe: tf,
                style: getFvgTfStyle(tf, z?.type),
            };
        });

        if (!fvgZonesByTimeframe || typeof fvgZonesByTimeframe !== 'object') fvgZonesByTimeframe = {};
        fvgZonesByTimeframe[detectTf] = zones;
        renderAllFvgOverlays(true);
        rebuildFvgNavigation();
        if (zones.length > 0) {
            const last = zones[zones.length - 1];
            const idx = fvgNavigationList.findIndex((x) =>
                Number(x?.start_time_unix || 0) === Number(last?.start_time_unix || 0)
                && Number(x?.end_time_unix || 0) === Number(last?.end_time_unix || 0)
                && String(x?.type || '') === String(last?.type || '')
                && String(x?.scan_timeframe || '') === String(last?.scan_timeframe || '')
            );
            if (idx >= 0) fvgNavigationIndex = idx;
            updateFvgJumpIndexLabel();
        }

        toolStates.fvg.scan_count = Number(toolStates.fvg.scan_count || 0) + 1;
        const mergedZones = flattenFvgZonesAcrossTimeframes();
        toolStates.fvg.last_zone_count = mergedZones.length;
        toolStates.fvg.zones_sample = mergedZones.slice(0, 20);
        const trend = data?.trend || {};
        const movement = data?.movement_strength || {};
        const trendLabel = trend?.direction
            ? `${String(data?.scan_source || scanSourceHint || 'manual_scan')} | ${String(trend.direction)} @ ${String(trend.trend_timeframe || '')}`
            : String(data?.scan_source || scanSourceHint || 'manual_scan');
        renderFvgInspector(zones, `${trendLabel} | detect ${detectTf}`);
        toolStates.fvg.movement_strength = movement;
        updateFvgStrengthBadge(movement);
        const badge = document.getElementById('fvg-zone-count');
        if (badge) {
            badge.textContent = String(mergedZones.length);
            badge.classList.toggle('d-none', mergedZones.length === 0);
        }
        const scopeLabel = config.scan_scope === 'visible'
            ? 'visible bars'
            : `last ${config.lookback_days ?? 2} day(s)`;
        const sourceLabel = data?.scan_source ? ` [${data.scan_source}]` : (scanSourceHint ? ` [${scanSourceHint}]` : '');
        const trendInfo = data?.trend || {};
        const trendPart = trendInfo?.direction
            ? ` | trend ${String(trendInfo.direction)} @ ${String(trendInfo.trend_timeframe || '')}`
            : '';
        const movePart = Number.isFinite(Number(movement?.score))
            ? ` | strength ${Number(movement.score).toFixed(1)} (${String(movement.state || 'n/a')})`
            : '';
        const tfPart = detectTf !== chartTf ? ` | detect ${detectTf} on chart ${chartTf}` : ` | tf ${chartTf}`;
        showStatus(`Found ${zones.length} FVG zone${zones.length !== 1 ? 's' : ''} in ${scopeLabel}${sourceLabel}${tfPart}${trendPart}${movePart}`, 'success');
        await pushAgentToolState('TOOL_SIGNAL_CHANGED');
    } catch (err) {
        showStatus(`FVG scan error: ${err.message}`, 'danger');
    }
}

function clearFVGZones() {
    fvgCreatorMarkers = [];
    syncCandleMarkers();
    const detectTf = getFvgDetectionTimeframe();
    if (fvgZonesByTimeframe && typeof fvgZonesByTimeframe === 'object') {
        delete fvgZonesByTimeframe[detectTf];
    }
    renderAllFvgOverlays();
    rebuildFvgNavigation();
    if (!toolStates.fvg) toolStates.fvg = {};
    const mergedZones = flattenFvgZonesAcrossTimeframes();
    toolStates.fvg.last_zone_count = mergedZones.length;
    toolStates.fvg.zones_sample = mergedZones.slice(0, 20);
    toolStates.fvg.movement_strength = {};
    renderFvgInspector([], `cleared ${detectTf}`);
    updateFvgStrengthBadge(null);
    const badge = document.getElementById('fvg-zone-count');
    if (badge) {
        badge.textContent = String(mergedZones.length);
        badge.classList.toggle('d-none', mergedZones.length === 0);
    }
    if (mergedZones.length > 0) showStatus(`Cleared ${detectTf} FVG overlays. ${mergedZones.length} zone(s) remain from other TF scans.`, 'info');
    else showStatus('FVG zones cleared', 'info');
    void pushAgentToolState('TOOL_SIGNAL_CHANGED');
}

async function scanMeanRev() {
    if (!sessionId) { showStatus('Start a session first', 'warning'); return; }

    const strictness = getToolStrictness('mean-rev', 3);
    const smaPeriodInput = document.getElementById('mean-rev-sma-period')?.value;
    const deviationInput = document.getElementById('mean-rev-deviation')?.value;
    const showExitSignals = document.getElementById('mean-rev-show-exit-signals')?.checked ?? true;
    const scanScope = String(document.getElementById('mean-rev-scan-scope')?.value || 'last_n_days').toLowerCase();
    const lookbackDaysInput = document.getElementById('mean-rev-lookback-days')?.value;

    const config = {
        strictness,
        show_exit_signals: !!showExitSignals,
        scan_scope: scanScope === 'visible' ? 'visible' : 'last_n_days',
    };
    const smaPeriod = Number(smaPeriodInput);
    if (Number.isFinite(smaPeriod)) config.sma_period = Math.max(5, Math.min(400, Math.round(smaPeriod)));
    const deviation = Number(deviationInput);
    if (Number.isFinite(deviation)) config.deviation = Math.max(0.5, Math.min(8, deviation));
    if (config.scan_scope === 'last_n_days') {
        const lb = Number(lookbackDaysInput);
        if (Number.isFinite(lb)) config.lookback_days = Math.max(0.1, Math.min(30, lb));
    }

    if (!toolStates.mean_rev) toolStates.mean_rev = {};
    toolStates.mean_rev.strictness = strictness;
    toolStates.mean_rev.sma_period = Number(config.sma_period ?? toolStates.mean_rev.sma_period ?? 30);
    toolStates.mean_rev.deviation = Number(config.deviation ?? toolStates.mean_rev.deviation ?? 2.0);
    toolStates.mean_rev.show_exit_signals = !!config.show_exit_signals;
    toolStates.mean_rev.scan_scope = String(config.scan_scope || 'last_n_days');
    toolStates.mean_rev.lookback_days = Number(config.lookback_days ?? toolStates.mean_rev.lookback_days ?? 2);
    toolStates.mean_rev.config = { ...config };

    try {
        showStatus('Scanning mean-reversion signals...', 'info');
        let barsPayload = null;
        if ((liveFeedActive || liveFeedRequested) && Array.isArray(allBars) && allBars.length > 0) {
            let srcBars = allBars.slice();
            if (config.scan_scope === 'last_n_days' && Number.isFinite(Number(config.lookback_days))) {
                const lbDays = Number(config.lookback_days);
                const lastTs = Number(srcBars[srcBars.length - 1]?.time || 0);
                if (lbDays > 0 && lastTs > 0) {
                    const cutoff = lastTs - (lbDays * 86400);
                    srcBars = srcBars.filter(b => Number(b?.time || 0) >= cutoff);
                }
            }
            if (srcBars.length < 3) srcBars = allBars.slice(-3);
            if (srcBars.length > 12000) srcBars = srcBars.slice(-12000);
            barsPayload = srcBars.map(b => ({
                time: Number(b.time || 0),
                open: Number(b.open || 0),
                high: Number(b.high || 0),
                low: Number(b.low || 0),
                close: Number(b.close || 0),
                volume: Number(b.volume || 0),
            }));
        }

        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/tools/mean_rev/scan`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(barsPayload ? { config, bars: barsPayload } : { config }),
        });
        const data = await res.json();
        if (data.error) { showStatus(`Mean-rev scan error: ${data.error}`, 'danger'); return; }

        if (zoneRenderer) {
            zoneRenderer.clearAll();
            renderedToolId = 'mean_rev';
            const zones = data.zones || [];
            for (const zone of zones) zoneRenderer.addZone(zone);
            toolStates.mean_rev.scan_count = Number(toolStates.mean_rev.scan_count || 0) + 1;
            toolStates.mean_rev.last_zone_count = zones.length;
            toolStates.mean_rev.zones_sample = zones.slice(0, 20);
            const currentState = (data.current_state && typeof data.current_state === 'object') ? data.current_state : {};
            toolStates.mean_rev.current_state = currentState;
            renderMeanRevInspector(zones, String(data?.scan_source || 'manual_scan'));
            updateMeanRevZscoreBadge(currentState);

            const badge = document.getElementById('mean-rev-zone-count');
            if (badge) {
                badge.textContent = String(zones.length);
                badge.classList.toggle('d-none', zones.length === 0);
            }
            const z = Number(currentState?.z_score);
            const zPart = Number.isFinite(z) ? ` | z ${z.toFixed(2)}` : '';
            const scopeLabel = config.scan_scope === 'visible' ? 'visible bars' : `last ${config.lookback_days ?? 2} day(s)`;
            const sourceLabel = data?.scan_source ? ` [${data.scan_source}]` : '';
            showStatus(`Found ${zones.length} mean-reversion signal${zones.length !== 1 ? 's' : ''} in ${scopeLabel}${sourceLabel}${zPart}`, 'success');
            await pushAgentToolState('TOOL_SIGNAL_CHANGED');
        }
    } catch (err) {
        showStatus(`Mean-rev scan error: ${err.message}`, 'danger');
    }
}

function clearMeanRevZones() {
    const renderedByOtherTool = !!(renderedToolId && renderedToolId !== 'mean_rev');
    if (zoneRenderer && (renderedToolId === 'mean_rev' || renderedToolId === null)) {
        zoneRenderer.clearAll();
        renderedToolId = null;
    }
    if (!toolStates.mean_rev) toolStates.mean_rev = {};
    toolStates.mean_rev.last_zone_count = 0;
    toolStates.mean_rev.zones_sample = [];
    toolStates.mean_rev.current_state = {};
    renderMeanRevInspector([], 'cleared');
    updateMeanRevZscoreBadge(null);
    const badge = document.getElementById('mean-rev-zone-count');
    if (badge) { badge.textContent = '0'; badge.classList.add('d-none'); }
    if (renderedByOtherTool) {
        showStatus(`Mean-reversion signals cleared (chart is currently showing ${renderedToolId} overlays)`, 'info');
    } else {
        showStatus('Mean-reversion signals cleared', 'info');
    }
    void pushAgentToolState('TOOL_SIGNAL_CHANGED');
}


// â”€â”€ UI Updates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function updateOpenPosition(pos, pnl) {
    const container = document.getElementById('open-position-display');
    const idEl = document.getElementById('open-pos-id');
    const closeBtn = document.getElementById('btn-close-pos');
    const tradeButtons = document.getElementById('trade-buttons');
    if (!container) return;

    if (pos) {
        const pnlValue = pnl || 0;
        const pnlClass = pnlValue >= 0 ? 'positive' : 'negative';
        const direction = String(pos.direction || '');
        const directionText = escapeHtml(direction);
        const directionClass = direction.toUpperCase() === 'BUY' ? 'buy' : (direction.toUpperCase() === 'SELL' ? 'sell' : '');
        const entry = Number(pos.entry_price);
        const sl = Number(pos.stop_loss);
        const tp = Number(pos.take_profit);
        const lots = Number(pos.lot_size);
        container.innerHTML = `
            <div class="open-position">
                <div class="d-flex justify-content-between align-items-center">
                    <span class="pos-direction ${directionClass}">${directionText} @ ${Number.isFinite(entry) ? entry.toFixed(2) : '-'}</span>
                    <span class="pos-pnl ${pnlClass}">$${pnlValue.toFixed(2)}</span>
                </div>
                <div class="mt-1" style="font-size: 0.72rem; color: #94a3b8;">
                    SL: ${Number.isFinite(sl) ? sl.toFixed(2) : '-'} | TP: ${Number.isFinite(tp) ? tp.toFixed(2) : 'None'} | Lots: ${Number.isFinite(lots) ? lots : '-'}
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
        if (el) { el.textContent = val; if (cls) el.className = `stat-value ${cls}`; }
    };

    const balance = Number(data.balance ?? data.current_balance ?? 0);
    const hasTotalPnl = Number.isFinite(Number(data.total_pnl));
    const pnl = hasTotalPnl ? Number(data.total_pnl) : (balance - initialBalance);
    const pnlClass = pnl >= 0 ? 'positive' : 'negative';

    setVal('stat-balance', `$${balance.toFixed(0)}`);
    setVal('stat-pnl', `${pnl >= 0 ? '+' : ''}$${pnl.toFixed(0)}`, pnlClass);

    const tradesCount = data.trades_count ?? data.total_trades;
    if (tradesCount !== undefined) setVal('stat-trades', tradesCount);
    if (data.wins !== undefined && tradesCount !== undefined) {
        const wr = tradesCount > 0 ? ((data.wins / tradesCount) * 100).toFixed(0) : '0';
        setVal('stat-winrate', `${wr}%`);
    }
}

function updateBarCounter() {
    const el = document.getElementById('bar-counter');
    if (el) el.textContent = `Bar ${currentBar} / ${totalBars}`;
    const fill = document.getElementById('progress-fill');
    if (fill && totalBars > 0) fill.style.width = `${(currentBar / totalBars) * 100}%`;
}

function addTradeToLog(trade) {
    const tbody = document.getElementById('trade-log-body');
    if (!tbody) return;
    const pnl = Number(trade.pnl || 0);
    const rawPnl = Number.isFinite(Number(trade.raw_pnl)) ? Number(trade.raw_pnl) : pnl;
    const spreadCost = Number(trade.spread_cost || 0);
    const turnoverCost = Number(trade.turnover_cost || 0);
    const totalCost = Number.isFinite(Number(trade.total_cost)) ? Number(trade.total_cost) : (spreadCost + turnoverCost);
    const pnlClass = pnl >= 0 ? 'text-success' : 'text-danger';
    const pnlTitle = `raw: ${rawPnl.toFixed(2)} | costs: ${totalCost.toFixed(2)}`;
    const row = document.createElement('tr');
    row.innerHTML = `
        <td>${escapeHtml(String(trade.direction || ''))}</td>
        <td>${trade.entry_price?.toFixed(2)}</td>
        <td>${trade.exit_price?.toFixed(2) || '-'}</td>
        <td>${trade.stop_loss?.toFixed(2) || '-'}</td>
        <td>${trade.take_profit?.toFixed(2) || '-'}</td>
        <td class="${pnlClass} fw-bold" title="${escapeHtml(pnlTitle)}">$${pnl.toFixed(2)}</td>
        <td>${trade.r_multiple?.toFixed(1) || '-'}R</td>
        <td><small>${escapeHtml(String(trade.exit_reason || '-'))}</small></td>
    `;
    tbody.insertBefore(row, tbody.firstChild);
}

function showTradeResult(trade) {
    const pnl = Number(trade.pnl || 0);
    const rawPnl = Number.isFinite(Number(trade.raw_pnl)) ? Number(trade.raw_pnl) : pnl;
    const spreadCost = Number(trade.spread_cost || 0);
    const turnoverCost = Number(trade.turnover_cost || 0);
    const totalCost = Number.isFinite(Number(trade.total_cost)) ? Number(trade.total_cost) : (spreadCost + turnoverCost);
    const type = pnl >= 0 ? 'success' : 'danger';
    const emoji = pnl >= 0 ? 'WIN' : 'LOSS';
    renderCostModelSummary(trade?.cost_breakdown || trade);
    showStatus(
        `${emoji}: ${trade.direction} closed @ ${trade.exit_price?.toFixed(2)} | Net: $${pnl.toFixed(2)} (raw $${rawPnl.toFixed(2)}, cost $${totalCost.toFixed(2)}) | ${trade.exit_reason}`,
        type,
    );
}

function showStatus(msg, type) {
    const el = document.getElementById('sim-status');
    if (!el) return;
    const colors = { success: '#16a34a', danger: '#dc2626', warning: '#d97706', info: '#2563eb' };
    el.textContent = msg;
    el.style.color = colors[type] || '#64748b';
    setTimeout(() => { if (el.textContent === msg) el.textContent = ''; }, 5000);
}

async function maybePushLiveAgentTick(force = false) {
    if (!sessionId || !agentLoopActive || !liveFeedActive) return;
    if (!Array.isArray(allBars) || allBars.length === 0) return;

    const lastBar = allBars[allBars.length - 1];
    const barTime = Number(lastBar?.time || 0);
    if (!Number.isFinite(barTime) || barTime <= 0) return;

    const nowMs = Date.now();
    const newBarArrived = barTime !== lastAgentLiveBarTime;
    const canPushByRate = (nowMs - lastAgentLivePushAtMs) >= AGENT_LIVE_PUSH_MIN_MS;
    const keepAliveDue = (nowMs - lastAgentLivePushAtMs) >= AGENT_LIVE_KEEPALIVE_MS;
    if (!force && !newBarArrived && !keepAliveDue) return;
    if (!force && !canPushByRate) return;

    const baseToolState = getToolStatePayload();
    const payload = {
        event_type: 'LIVE_TICK',
        severity: 'info',
        tool_state: {
            ...baseToolState,
            indicator_last: buildCompactIndicatorSnapshot(),
            live_feed_active: true,
            live_source: getSelectedLiveSource(),
            live_stream: {
                bar_index: Math.max(0, allBars.length - 1),
                total_bars: allBars.length,
                pushed_at_ms: nowMs,
            },
            live_bar: {
                time: barTime,
                open: Number(lastBar.open || 0),
                high: Number(lastBar.high || 0),
                low: Number(lastBar.low || 0),
                close: Number(lastBar.close || 0),
                volume: Number(lastBar.volume || 0),
            },
        },
    };

    try {
        await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/tool-state`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        lastAgentLivePushAtMs = nowMs;
        lastAgentLiveBarTime = barTime;
    } catch (_) {
        // non-blocking best-effort
    }
}

async function pushAgentToolState(eventType = 'TOOL_SIGNAL_CHANGED') {
    if (!sessionId || !agentLoopActive) return;
    const payload = {
        event_type: String(eventType || 'TOOL_SIGNAL_CHANGED').toUpperCase(),
        severity: 'info',
        tool_state: getToolStatePayload(),
    };
    try {
        await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/tool-state`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
    } catch (_) {
        // non-blocking best-effort
    }
}

async function startAgentLoop() {
    const btn = document.getElementById('btn-agent-start');
    if (btn) btn.disabled = true;
    if (!sessionId) {
        showStatus('Start a session first', 'warning');
        if (btn) btn.disabled = false;
        return;
    }
    saveAgentProviderPrefs();
    await saveAgentIdentityFromUI(true);
    const providerCfg = getAgentProviderConfig();
    const permissions = getAgentPermissionsFromUI();
    const watchdogCfg = getAgentWatchdogConfigFromUI();
    const loopIntervalRaw = Number(document.getElementById('agent-loop-interval')?.value || 5);
    const loopInterval = Number.isFinite(loopIntervalRaw) ? Math.max(0.5, Math.min(120, loopIntervalRaw)) : 5.0;
    const payload = {
        provider: providerCfg,
        permissions,
        loop_interval_sec: loopInterval,
        mode: 'LOOP',
        config: {
            ...watchdogCfg,
        },
        runtime: {},
    };
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/start`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const data = await res.json().catch(() => ({}));
        if (data.error || data?.ok === false) {
            const msg = String(data?.detail || data?.error || data?.message || 'start failed');
            showStatus(`Agent start failed: ${msg}`, 'danger');
            return;
        }
        renderAgentState(_normalizeAgentStatePayload(data));
        ensureAgentPoller();
        showStatus(`Agent loop started (watchdog=${watchdogCfg.watchdog_mode})`, 'success');
        await pushAgentToolState('TOOL_SIGNAL_CHANGED');
        await maybePushLiveAgentTick(true);
    } catch (err) {
        showStatus(`Agent start failed: ${err.message}`, 'danger');
    } finally {
        if (btn) btn.disabled = false;
    }
}

async function stopAgentLoop() {
    if (!sessionId) return;
    const btn = document.getElementById('btn-agent-stop');
    if (btn) btn.disabled = true;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/stop`, {
            method: 'POST',
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false || data?.error) {
            const msg = String(data?.detail || data?.error || data?.message || `HTTP ${res.status}`);
            showStatus(`Agent stop failed: ${msg}`, 'danger');
            return;
        }
        renderAgentState(_normalizeAgentStatePayload(data));
        showStatus('Agent loop stopped', 'info');
    } catch (err) {
        showStatus(`Agent stop failed: ${err.message}`, 'danger');
    } finally {
        if (btn) btn.disabled = false;
    }
}

async function pauseAutoAgent() {
    if (!sessionId) return;
    const btn = document.getElementById('btn-agent-pause-auto');
    if (btn) btn.disabled = true;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/pause`, {
            method: 'POST',
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false || data?.error) {
            const msg = String(data?.detail || data?.error || data?.message || `HTTP ${res.status}`);
            showStatus(`Pause auto failed: ${msg}`, 'danger');
            return;
        }
        renderAgentState(_normalizeAgentStatePayload(data));
        showStatus('AUTO_PAPER paused by guardrail', 'warning');
    } catch (err) {
        showStatus(`Pause auto failed: ${err.message}`, 'danger');
    } finally {
        if (btn) btn.disabled = false;
    }
}

async function resumeAutoAgent() {
    if (!sessionId) return;
    const btn = document.getElementById('btn-agent-resume-auto');
    if (btn) btn.disabled = true;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/resume`, {
            method: 'POST',
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false || data?.error) {
            const msg = String(data?.detail || data?.error || data?.message || `HTTP ${res.status}`);
            showStatus(`Resume auto failed: ${msg}`, 'danger');
            return;
        }
        renderAgentState(_normalizeAgentStatePayload(data));
        showStatus('AUTO_PAPER resume requested', 'success');
    } catch (err) {
        showStatus(`Resume auto failed: ${err.message}`, 'danger');
    } finally {
        if (btn) btn.disabled = false;
    }
}

async function refreshAgentState(showStatusErrors = false) {
    if (!sessionId) return;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/state`);
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false || data?.error) {
            if (showStatusErrors) {
                const msg = String(data?.detail || data?.error || data?.message || `HTTP ${res.status}`);
                showStatus(`Agent state error: ${msg}`, 'warning');
            }
            return;
        }
        renderAgentState(_normalizeAgentStatePayload(data));
    } catch (err) {
        if (showStatusErrors) showStatus(`Agent state error: ${err.message}`, 'warning');
    }
}

