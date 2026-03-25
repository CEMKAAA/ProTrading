/**
 * Trader's Workbench - JavaScript
 * Strategy-free chart analysis with professional tools (FVG, etc.)
 * Adapted from simulation.js â€” same chart + playback, tools panel replaces steps.
 */

// â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
let sessionId = null;
let sessionCreateNewRequested = false;
let sessionSwitchSeq = 0;
let chart = null;
let candleSeries = null;
let volumeSeries = null;
let mainCrosshairSeries = null;
let trendiloPanelChart = null;
let trendiloPanelSeries = {};
let trendiloPanelSyncingRange = false;
let trendiloPanelSyncingCrosshair = false;
let userHasScrolledAway = false;
let mainCloseByTime = new Map();
let trendiloSignalByTime = new Map();
let trendiloDirByTime = new Map();
let rsiByTime = new Map();
let rsiHoverTooltipEl = null;
let sessionCatalog = [];
let brokerSymbolCatalog = [];
let sessionLiveExecutionMode = 'paper';
let sessionLiveControlState = null;
let sessionLiveAccountState = null;
let sessionSymbolEconomics = null;
let currentOpenPositionState = null;
let quickOpenTradesState = [];
let quickOpenTradesPollTimer = null;
let quickOpenTradesInFlight = false;
let quickCloseInFlightKeys = new Set();
let quickTpUsdTarget = null;
let quickTpTradeId = null;
let quickTpAutoCloseInFlight = false;
let streamModeActive = false;
let streamModeUrl = '';

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
    trendilo: false,
    advancedTrendilo: false,
    trendiloLsma: false,
    alphaWave: false,
    deadzonePro: false,
    orbSignal: false,
    trendiloBarColor: false,
    goldenCross: false,
};
let tradeMarkers = [];
let openPositionSlLine = null;
let openPositionTpLine = null;
let goldenCrossMarkers = [];
let fvgCreatorMarkers = [];
let strategyBacktestMarkers = [];
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
const LIVE_CONFIRMATION_PHRASE = 'CONFIRM_LIVE_ORDER';
const SESSION_STORAGE_KEY = 'sim:lastSession:_workbench';
const SESSION_LIST_LIMIT = 200;
const SPEED_STEPS = [1, 2, 5, 10];
const ADAPTIVE_TUNE_INTERVAL_MS = 4000;
const WS_STALL_FACTOR = 8;
const LATENCY_SAMPLE_CAP = 200;
const AGENT_LIVE_PUSH_MIN_MS = 1500;
const AGENT_LIVE_KEEPALIVE_MS = 12000;
const CHART_BG_COLOR = '#131722';
const CHART_RIGHT_SCALE_MIN_WIDTH = 72;
const ORB_NY_TIMEZONE = 'America/New_York';
const ORB_NY_PARTS_FORMATTER = new Intl.DateTimeFormat('en-US', {
    timeZone: ORB_NY_TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
});
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
    trendiloSmooth: 1,
    trendiloLength: 50,
    trendiloOffset: 0.85,
    trendiloSigma: 6,
    trendiloBandMultiplier: 1.0,
    trendiloUseCustomBandLength: false,
    trendiloBandLength: 20,
    trendiloVolumeSmaPeriod: 20,
    trendiloFillEnabled: true,
    advancedTrendiloHysteresisMult: 0.15,
    trendiloLsmaLength: 25,
    trendiloLsmaOffset: 0,
    trendiloLsmaSmooth: 5,
    trendiloLsmaHmaLength: 50,
    alphaWaveBaselineAdxLength: 2,
    alphaWaveBaselineWeight: 10.0,
    alphaWaveBaselineMaLength: 6,
};
const COST_MODEL_DEFAULTS = {
    XAUUSD: 0.30,
    NAS100: 1.5,
    US500: 0.5,
    GBPUSD: 0.00015,
    EURUSD: 0.00012,
};
const COST_MODEL_DEFAULT_TC_RATE = 0.0001;
const CURATED_SYMBOL_OPTIONS = [
    { value: 'XAUUSD', label: 'XAUUSD (Gold)' },
    { value: 'NAS100', label: 'NAS100' },
    { value: 'US500', label: 'US500' },
    { value: 'GBPUSD', label: 'GBPUSD' },
    { value: 'EURUSD', label: 'EURUSD' },
];
const AGENT_CHAT_STORAGE_KEY = 'workbench:agent:chat:sessions:v1';
const LEGACY_CONSULTANT_STORAGE_KEY = 'workbench:consultant:sessions:v1';
const AGENT_PROVIDER_PREFS_KEY = 'workbench:agent:provider:prefs:v1';
const TRENDILO_OPP_CACHE_KEY_PREFIX = 'workbench:strategy:opportunity_scan:v1:';
const TRENDILO_OPP_CACHE_MAX_AGE_MIN = 180;
const QUICK_OPEN_TRADES_POLL_MS = 3000;
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
let strategyAutomationJobs = [];
let strategyAutomationJobIndex = {};
let automationMonitorExpandedJobs = new Set();
let lastStrategyOpportunityScanData = null;
let automationChartJobContext = null;
let automationChartMain = null;
let automationChartCandles = null;
let automationChartVolume = null;
let automationChartOverlay = null;
let automationChartOverlaySecondary = null;
let automationChartPanel = null;
let automationChartPanelSeries = {};
let automationChartResizeObserver = null;
let automationChartPanelResizeObserver = null;
let automationChartSyncingRange = false;
let automationLogsContext = null;
let automationLogsEvents = [];
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
    const el = document.getElementById('chart-main');
    if (chart && el) {
        const width = Math.max(320, Math.round(el.clientWidth || 0));
        const height = Math.max(220, Math.round(el.clientHeight || 0));
        chart.applyOptions({ width, height });
    }
    const panelEl = document.getElementById('chart-trendilo-panel');
    if (trendiloPanelChart && panelEl && !panelEl.classList.contains('d-none')) {
        const width = Math.max(320, Math.round(panelEl.clientWidth || 0));
        const height = Math.max(120, Math.round(panelEl.clientHeight || 0));
        trendiloPanelChart.applyOptions({ width, height });
    }
}

function _normalizeLivestreamUrl(rawUrl) {
    const raw = String(rawUrl || '').trim();
    if (!raw) return '';
    let parsed = null;
    try {
        parsed = new URL(raw);
    } catch (_) {
        return '';
    }
    const host = String(parsed.hostname || '').toLowerCase();
    const isYoutube = host.includes('youtube.com') || host.includes('youtu.be');
    if (!isYoutube) return parsed.toString();

    let videoId = '';
    if (host.includes('youtu.be')) {
        videoId = String(parsed.pathname || '').replace(/^\/+/, '').split('/')[0];
    } else {
        videoId = parsed.searchParams.get('v') || '';
        if (!videoId && String(parsed.pathname || '').includes('/shorts/')) {
            videoId = String(parsed.pathname || '').split('/shorts/')[1]?.split('/')[0] || '';
        }
        if (!videoId && String(parsed.pathname || '').includes('/embed/')) {
            videoId = String(parsed.pathname || '').split('/embed/')[1]?.split('/')[0] || '';
        }
    }
    videoId = String(videoId || '').trim();
    if (!videoId) return parsed.toString();

    const embed = new URL(`https://www.youtube.com/embed/${encodeURIComponent(videoId)}`);
    embed.searchParams.set('autoplay', '1');
    embed.searchParams.set('mute', '1');
    embed.searchParams.set('rel', '0');
    return embed.toString();
}

function setLivestreamMode(active, url = '') {
    const nextActive = !!active;
    const chartContainer = document.querySelector('.chart-container');
    const streamWrap = document.getElementById('chart-stream-wrap');
    const streamFrame = document.getElementById('chart-stream-frame');
    const streamLabel = document.getElementById('chart-stream-url-label');
    const btn = document.getElementById('btn-toggle-livestream');

    streamModeActive = nextActive;
    if (nextActive) {
        streamModeUrl = String(url || streamModeUrl || '').trim();
        if (streamFrame) streamFrame.src = streamModeUrl;
        if (streamLabel) streamLabel.textContent = streamModeUrl || 'Livestream URL';
        chartContainer?.classList.add('stream-mode');
        streamWrap?.classList.remove('d-none');
        hideRsiHoverTooltip();
        setTrendiloPanelVisibility(false);
        if (btn) {
            btn.innerHTML = '<i class="bi bi-broadcast-pin me-1"></i>Live ON';
            btn.classList.add('btn-outline-warning');
        }
    } else {
        if (streamFrame) streamFrame.src = '';
        if (streamLabel) streamLabel.textContent = 'No URL';
        chartContainer?.classList.remove('stream-mode');
        streamWrap?.classList.add('d-none');
        if (btn) {
            btn.innerHTML = '<i class="bi bi-broadcast-pin me-1"></i>Livestream';
            btn.classList.remove('btn-outline-warning');
        }
        setTrendiloPanelVisibility(isTrendiloPanelEnabled());
        refreshChartViewport();
    }
}

function toggleLivestreamMode() {
    if (streamModeActive) {
        setLivestreamMode(false);
        showStatus('Livestream mode disabled.', 'info');
        return;
    }
    const initial = String(streamModeUrl || '').trim();
    const raw = window.prompt('Livestream URL girin', initial);
    if (raw === null) return;
    const normalized = _normalizeLivestreamUrl(raw);
    if (!normalized) {
        showStatus('Geçerli bir URL girin (http/https).', 'warning');
        return;
    }
    setLivestreamMode(true, normalized);
    showStatus('Livestream mode enabled.', 'success');
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

function renderExecutionModeBadge() {
    const el = document.getElementById('stat-execution');
    if (!el) return;
    const badgeClassBase = 'stat-value execution-badge clickable';
    if (!(sessionId && Number.isFinite(Number(sessionId)) && Number(sessionId) > 0)) {
        el.textContent = 'NO SESSION';
        el.className = `${badgeClassBase} mode-none`;
        el.title = 'No active session';
        return;
    }
    const cfg = _normalizeSessionLiveControl(sessionLiveControlState || { execution_mode: 'paper' });
    const mode = String(cfg.execution_mode || 'paper').toLowerCase();
    if (mode === 'live_mt5') {
        if (Boolean(cfg.kill_switch_enabled)) {
            el.textContent = 'LIVE MT5 · KILL';
            el.className = `${badgeClassBase} mode-kill`;
            el.title = 'Live MT5 selected but kill switch is ON (order routing blocked)';
        } else {
            el.textContent = 'LIVE MT5';
            el.className = `${badgeClassBase} mode-live`;
            el.title = 'Live MT5 execution enabled';
        }
    } else {
        el.textContent = 'PAPER';
        el.className = `${badgeClassBase} mode-paper`;
        el.title = 'Paper execution mode (simulated orders)';
    }
}

function _numFmt(value, digits = 2) {
    const n = Number(value);
    if (!Number.isFinite(n)) return '-';
    return n.toFixed(digits);
}

function _parseUiDecimal(rawValue, fallback = null) {
    const txt = String(rawValue ?? '').trim();
    if (!txt) return fallback;
    const normalized = txt.replace(',', '.');
    const n = Number(normalized);
    if (!Number.isFinite(n)) return fallback;
    return n;
}

function renderSymbolEconomicsHint(snapshotLike = null) {
    if (snapshotLike && typeof snapshotLike === 'object') {
        sessionSymbolEconomics = { ...snapshotLike };
    } else if (!sessionSymbolEconomics) {
        sessionSymbolEconomics = null;
    }
    const el = document.getElementById('symbol-econ-hint');
    if (!el) return;
    const s = sessionSymbolEconomics;
    if (!s || typeof s !== 'object') {
        el.textContent = 'Symbol economics will be shown after session start.';
        return;
    }
    const resolved = String(s.resolved_symbol || s.requested_symbol || '').toUpperCase();
    const source = String(s.source || 'instrument_specs');
    const contract = _numFmt(s.contract_size, 6);
    const point = _numFmt(s.point, 8);
    const value1Lot = _numFmt(s.point_value_per_1lot, 6);
    const pnlPoint1Lot = _numFmt(s.pnl_per_point_1lot, 6);
    const minLot = _numFmt(s.volume_min, 4);
    const maxLot = _numFmt(s.volume_max, 4);
    const stepLot = _numFmt(s.volume_step, 4);
    const lot1pct100p = (s.risk_examples && s.risk_examples.lot_for_1pct_risk_at_100_points_stop !== undefined)
        ? _numFmt(s.risk_examples.lot_for_1pct_risk_at_100_points_stop, 4)
        : '-';
    el.textContent = `Symbol economics (${resolved || '-'}, ${source}): contract_size=${contract}, point_value_per_1lot=${value1Lot}, point=${point}, pnl_per_point_1lot=${pnlPoint1Lot}, lot[min/step/max]=${minLot}/${stepLot}/${maxLot}, lot@1%risk(100 points SL)=${lot1pct100p}`;
}

function setPanelBodyExpanded(bodyId, expanded) {
    const id = String(bodyId || '').trim();
    if (!id) return false;
    const body = document.getElementById(id);
    if (!body) return false;
    const isOpen = !!expanded;
    body.classList.toggle('d-none', !isOpen);
    const toggle = document.querySelector(`.panel-toggle[data-target="#${id}"]`);
    if (toggle) toggle.setAttribute('aria-expanded', String(isOpen));
    return true;
}

function setAgentSectionExpanded(sectionId, expanded) {
    const id = String(sectionId || '').trim();
    if (!id) return false;
    const body = document.getElementById(id);
    if (!body) return false;
    const isOpen = !!expanded;
    body.classList.toggle('d-none', !isOpen);
    const toggle = document.querySelector(`.agent-section-toggle[data-agent-section="${id}"]`);
    if (toggle) toggle.setAttribute('aria-expanded', String(isOpen));
    return true;
}

function focusAgentSafetyExecutionMode() {
    const input = document.getElementById('agent-live-execution-mode');
    if (!input) return;
    try {
        input.focus({ preventScroll: false });
    } catch (_) {
        input.focus();
    }
}

function openAgentSafetyFromExecutionBadge() {
    const expandSafety = () => {
        setPanelBodyExpanded('agent-panel-body', true);
        setAgentSectionExpanded('agent-sec-safety', true);
        focusAgentSafetyExecutionMode();
    };
    if (fullscreenWorkbench && typeof bootstrap !== 'undefined') {
        const modalEl = document.getElementById('agentPanelModal');
        if (modalEl) {
            const onShown = () => {
                modalEl.removeEventListener('shown.bs.modal', onShown);
                expandSafety();
            };
            modalEl.addEventListener('shown.bs.modal', onShown);
            openWorkbenchPanel('agent');
            return;
        }
    }
    expandSafety();
}

function updateSessionIdStat() {
    const el = document.getElementById('stat-session-id');
    const sel = document.getElementById('sim-session-select');
    if (!el) return;
    if (sessionId && Number.isFinite(Number(sessionId)) && Number(sessionId) > 0) {
        const sid = Number(sessionId);
        el.textContent = `#${sid}`;
        el.title = `Telegram: /use ${sid}`;
        if (sel && Array.from(sel.options || []).some((o) => String(o.value) === String(sid))) {
            sel.value = String(sid);
        }
    } else {
        el.textContent = '-';
        el.title = 'No active session';
        if (sel) sel.value = '';
    }
    renderExecutionModeBadge();
}

function setSelectValueCaseInsensitive(selectEl, rawValue) {
    if (!selectEl) return false;
    const desired = String(rawValue || '').trim();
    if (!desired) return false;
    const direct = Array.from(selectEl.options || []).find((o) => String(o.value || '') === desired);
    if (direct) {
        selectEl.value = desired;
        return true;
    }
    const lower = desired.toLowerCase();
    const matched = Array.from(selectEl.options || []).find((o) => String(o.value || '').trim().toLowerCase() === lower);
    if (matched) {
        selectEl.value = String(matched.value || '');
        return true;
    }
    return false;
}

function _sessionLabel(row) {
    const sid = Number(row?.id || 0);
    const sym = String(row?.symbol || '').toUpperCase() || '?';
    const tf = String(row?.timeframe || '').toUpperCase() || '?';
    const st = String(row?.status || '').toUpperCase() || '?';
    const pnl = Number(row?.total_pnl || 0);
    const pnlTxt = Number.isFinite(pnl) ? `${pnl >= 0 ? '+' : ''}${pnl.toFixed(2)}` : '0.00';
    return `#${sid} ${sym} ${tf} | ${st} | PnL ${pnlTxt}`;
}

function renderSessionSelector() {
    const selectEl = document.getElementById('sim-session-select');
    if (!selectEl) return;
    const prev = String(selectEl.value || '');
    const rows = Array.isArray(sessionCatalog) ? sessionCatalog : [];
    let html = '<option value="">(new session)</option>';
    for (const row of rows) {
        const sid = Number(row?.id || 0);
        if (!Number.isFinite(sid) || sid <= 0) continue;
        html += `<option value="${sid}">${escapeHtml(_sessionLabel(row))}</option>`;
    }
    selectEl.innerHTML = html;
    const target = sessionCreateNewRequested
        ? ''
        : ((sessionId && Number.isFinite(Number(sessionId))) ? String(Number(sessionId)) : prev);
    if (target && Array.from(selectEl.options).some((o) => String(o.value) === target)) {
        selectEl.value = target;
    } else {
        selectEl.value = '';
    }
}

async function refreshSessionCatalog(showToast = false) {
    try {
        const q = new URLSearchParams();
        q.set('strategy_id', STRATEGY_ID);
        q.set('limit', String(SESSION_LIST_LIMIT));
        q.set('include_automation_children', '0');
        const res = await fetch(`${API_BASE}/api/simulation/sessions?${q.toString()}`);
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false || !Array.isArray(data?.sessions)) {
            if (showToast) showStatus(`Session list load failed: ${data?.error || res.status}`, 'warning');
            return;
        }
        sessionCatalog = data.sessions || [];
        renderSessionSelector();
        if (showToast) showStatus(`Loaded ${sessionCatalog.length} session(s)`, 'info');
    } catch (err) {
        if (showToast) showStatus(`Session list load failed: ${err.message}`, 'warning');
    }
}

async function switchToSession(nextSessionId, { restartLive = false, forceLiveMode = false } = {}) {
    const sid = Number(nextSessionId);
    if (!Number.isFinite(sid) || sid <= 0) {
        showStatus('Invalid session id', 'warning');
        return false;
    }
    if (forceLiveMode) {
        const modeEl = document.getElementById('workbench-mode');
        if (modeEl) modeEl.value = 'live';
        applyWorkbenchModeUI();
    }
    const switchSeq = ++sessionSwitchSeq;
    const wasLive = liveFeedActive || liveFeedRequested;
    stopPlay();
    stopAgentPoller();
    stopLiveFeed();
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sid}`);
        const data = await res.json().catch(() => ({}));
        if (switchSeq !== sessionSwitchSeq) {
            return false;
        }
        if (!res.ok || data?.error || !data?.id) {
            if (Number(res.status) === 404 || String(data?.error || '').toLowerCase().includes('not found')) {
                if (Number(sessionId) === sid) {
                    sessionId = null;
                    clearPersistedSessionId();
                    updateSessionIdStat();
                    sessionSymbolEconomics = null;
                    renderSymbolEconomicsHint(null);
                }
            }
            showStatus(`Session switch failed: ${data?.error || res.status}`, 'danger');
            return false;
        }
        sessionId = Number(data.id);
        setSessionLiveExecutionModeFromLiveControl(data?.live_control || null, data?.live_account || null);
        renderSymbolEconomicsHint(data?.symbol_economics || null);
        sessionCreateNewRequested = false;
        persistSessionId(sessionId);
        updateSessionIdStat();
        setAgentChatAvailability(true);

        const symbolRaw = String(data.symbol || '').trim();
        const symbol = symbolRaw.toUpperCase();
        const timeframe = normalizeTimeframeLabel(data.timeframe || 'M15', 'M15');
        const symEl = document.getElementById('sim-symbol');
        const tfEl = document.getElementById('sim-timeframe');
        if (symEl && !setSelectValueCaseInsensitive(symEl, symbolRaw)) symEl.value = symbolRaw || symbol;
        if (tfEl) tfEl.value = timeframe;
        const balEl = document.getElementById('sim-balance');
        if (balEl && Number.isFinite(Number(data.initial_balance))) {
            balEl.value = String(Number(data.initial_balance));
        }

        initialBalance = Number(data.initial_balance || 10000);
        currentBar = Number(data.current_bar || 0);
        totalBars = Number(data.total_bars || 0);
        allBars = [];
        pendingAdvance = 0;
        isAdvancing = false;
        candleSeries.setData([]);
        volumeSeries.setData([]);
        if (zoneRenderer) zoneRenderer.clearAll();
        tradeMarkers = [];
        strategyBacktestMarkers = [];
        goldenCrossMarkers = [];
        fvgCreatorMarkers = [];
        clearAllIndicatorSeries();
        syncCandleMarkers();
        updateBarCounter();
        renderTradeLog(Array.isArray(data.trades) ? data.trades : []);
        updateStats({
            balance: Number(data.current_balance || initialBalance),
            total_pnl: Number(data.total_pnl || 0),
            trades_count: Number(data.trades_count || 0),
            wins: Number(data.wins || 0),
            losses: Number(data.losses || 0),
        });
        applyCostModelToUI(data?.cost_model || null);
        renderCostModelSummary(null);
        applyWorkbenchModeUI();

        if (getWorkbenchMode() === 'replay' && Number(totalBars || 0) > 0) {
            const seekRes = await fetch(
                `${API_BASE}/api/simulation/sessions/${sessionId}/seek?bar=${Math.max(0, currentBar)}&include_bars=1&bars_limit=1500`,
                { method: 'POST' },
            );
            const seekData = await seekRes.json().catch(() => ({}));
            if (switchSeq !== sessionSwitchSeq) {
                return false;
            }
            if (seekRes.ok && !seekData?.error && Array.isArray(seekData?.bars)) {
                allBars = [];
                applyAdvancePayload(seekData);
            }
        }

        if (getWorkbenchMode() === 'live' && (wasLive || restartLive)) {
            await startLiveFeed(false);
            if (switchSeq !== sessionSwitchSeq) {
                return false;
            }
        }
        await refreshSessionCatalog(false);
        await refreshAgentState(false);
        await refreshAgentMemoryList('');
        await refreshAgentIdentity(false);
        await refreshAgentTriggerList(false);
        await refreshQuickOpenTrades();
        if (switchSeq !== sessionSwitchSeq) {
            return false;
        }
        renderSessionSelector();
        showStatus(`Switched to session #${sessionId} (${symbol} ${timeframe})`, 'success');
        return true;
    } catch (err) {
        showStatus(`Session switch failed: ${err.message}`, 'danger');
        return false;
    }
}

async function closeSelectedSession() {
    const selectEl = document.getElementById('sim-session-select');
    const sid = Number(selectEl?.value || 0);
    if (!Number.isFinite(sid) || sid <= 0) {
        showStatus('Select a session to close', 'warning');
        return;
    }
    if (!window.confirm(`Close session #${sid}? This deletes its runtime state.`)) return;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sid}`, { method: 'DELETE' });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false || data?.error) {
            showStatus(`Close session failed: ${data?.error || res.status}`, 'danger');
            return;
        }
        const wasCurrent = Number(sessionId) === sid;
        if (wasCurrent) {
            stopLiveFeed();
            stopPlay();
            stopAgentPoller();
            sessionId = null;
            clearPersistedSessionId();
            updateSessionIdStat();
            setAgentChatAvailability(false);
            allBars = [];
            currentBar = 0;
            totalBars = 0;
            candleSeries.setData([]);
            volumeSeries.setData([]);
            updateBarCounter();
            updateStats({ balance: initialBalance, total_pnl: 0, trades_count: 0, wins: 0, losses: 0 });
            updateOpenPosition(null);
            renderTradeLog([]);
            renderAgentTriggerList([]);
            renderPendingAgentApprovals();
            sessionSymbolEconomics = null;
            renderSymbolEconomicsHint(null);
            quickOpenTradesState = [];
            renderQuickOpenTrades([]);
        }
        await refreshSessionCatalog(false);
        showStatus(`Session #${sid} closed`, 'success');
    } catch (err) {
        showStatus(`Close session failed: ${err.message}`, 'danger');
    }
}

function escapeRegExp(raw) {
    return String(raw || '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function _compileLikePattern(rawTerm) {
    const term = String(rawTerm || '').trim();
    if (!term) return null;
    const hasWildcards = term.includes('%') || term.includes('_');
    const likePattern = hasWildcards ? term : `%${term}%`;
    const regexBody = escapeRegExp(likePattern).replace(/%/g, '.*').replace(/_/g, '.');
    return new RegExp(`^${regexBody}$`, 'i');
}

function _symbolSearchMatch(rawTerm, parts) {
    const rx = _compileLikePattern(rawTerm);
    if (!rx) return true;
    const values = Array.isArray(parts) ? parts : [];
    return values.some((p) => rx.test(String(p || '').trim()));
}

function applyBrokerSymbolsToUI(rows, opts = {}) {
    const selectEl = document.getElementById('sim-symbol');
    const metaEl = document.getElementById('sim-symbol-meta');
    if (!selectEl) return;
    const current = String(selectEl.value || '').trim();
    const currentUpper = current.toUpperCase();
    const searchInputEl = document.getElementById('sim-symbol-search');
    const rawSearch = (typeof opts.searchTerm === 'string')
        ? opts.searchTerm
        : String(searchInputEl?.value || '');
    const searchTerm = String(rawSearch || '').trim();
    const list = Array.isArray(rows) ? rows : [];
    brokerSymbolCatalog = list.slice();
    const seen = new Set();
    const curatedRows = [];
    for (const opt of CURATED_SYMBOL_OPTIONS) {
        const value = String(opt?.value || '').trim();
        const label = String(opt?.label || value).trim();
        if (!value) continue;
        const keep = value.toUpperCase() === currentUpper || _symbolSearchMatch(searchTerm, [value, label]);
        if (!keep) continue;
        curatedRows.push({ value, label });
        seen.add(value.toUpperCase());
    }

    const brokerRows = [];
    for (const row of list) {
        const name = String(row?.name || '').trim();
        if (!name) continue;
        if (seen.has(name.toUpperCase())) continue;
        const desc = String(row?.description || '').trim();
        const vis = row?.visible ? 'visible' : 'hidden';
        const label = desc ? `${name} - ${desc}` : `${name} (${vis})`;
        const keep = name.toUpperCase() === currentUpper || _symbolSearchMatch(searchTerm, [name, desc, label]);
        if (!keep) continue;
        brokerRows.push({ name, label });
    }

    let html = '<optgroup label="Curated">';
    for (const opt of curatedRows) {
        const value = String(opt?.value || '').trim();
        const label = String(opt?.label || value).trim();
        html += `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`;
    }
    html += '</optgroup>';
    html += '<optgroup label="Broker (MT5)">';
    for (const row of brokerRows) {
        const name = String(row?.name || '').trim();
        const label = String(row?.label || name).trim();
        html += `<option value="${escapeHtml(name)}">${escapeHtml(label)}</option>`;
    }
    html += '</optgroup>';
    if (curatedRows.length === 0 && brokerRows.length === 0) {
        html = '<option value="" disabled selected>No symbols match your search</option>';
    }
    selectEl.innerHTML = html;
    if (current && Array.from(selectEl.options).some((o) => String(o.value).toUpperCase() === currentUpper)) {
        selectEl.value = current;
    } else if (selectEl.options.length > 0) {
        selectEl.selectedIndex = 0;
    }
    if (metaEl) {
        if (list.length === 0) {
            metaEl.textContent = 'No symbols returned from MT5; using curated defaults.';
        } else if (searchTerm) {
            metaEl.textContent = `Loaded ${list.length} MT5 symbols. Showing ${brokerRows.length} broker matches for "${searchTerm}".`;
        } else {
            metaEl.textContent = `Loaded ${list.length} MT5 symbols from active broker.`;
        }
    }
}

function applyBrokerSymbolsToAutomationUI(rows, opts = {}) {
    const selectEl = document.getElementById('auto-start-symbol');
    const metaEl = document.getElementById('auto-start-symbol-meta');
    if (!selectEl) return;
    const current = String(selectEl.value || '').trim();
    const currentUpper = current.toUpperCase();
    const searchInputEl = document.getElementById('auto-start-symbol-search');
    const rawSearch = (typeof opts.searchTerm === 'string')
        ? opts.searchTerm
        : String(searchInputEl?.value || '');
    const searchTerm = String(rawSearch || '').trim();
    const list = Array.isArray(rows) ? rows : [];
    const seen = new Set();
    const curatedRows = [];
    for (const opt of CURATED_SYMBOL_OPTIONS) {
        const value = String(opt?.value || '').trim();
        const label = String(opt?.label || value).trim();
        if (!value) continue;
        const keep = value.toUpperCase() === currentUpper || _symbolSearchMatch(searchTerm, [value, label]);
        if (!keep) continue;
        curatedRows.push({ value, label });
        seen.add(value.toUpperCase());
    }

    const brokerRows = [];
    for (const row of list) {
        const name = String(row?.name || '').trim();
        if (!name) continue;
        if (seen.has(name.toUpperCase())) continue;
        const desc = String(row?.description || '').trim();
        const vis = row?.visible ? 'visible' : 'hidden';
        const label = desc ? `${name} - ${desc}` : `${name} (${vis})`;
        const keep = name.toUpperCase() === currentUpper || _symbolSearchMatch(searchTerm, [name, desc, label]);
        if (!keep) continue;
        brokerRows.push({ name, label });
    }

    let html = '<optgroup label="Curated">';
    for (const opt of curatedRows) {
        const value = String(opt?.value || '').trim();
        const label = String(opt?.label || value).trim();
        html += `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`;
    }
    html += '</optgroup>';
    html += '<optgroup label="Broker (MT5)">';
    for (const row of brokerRows) {
        const name = String(row?.name || '').trim();
        const label = String(row?.label || name).trim();
        html += `<option value="${escapeHtml(name)}">${escapeHtml(label)}</option>`;
    }
    html += '</optgroup>';
    if (curatedRows.length === 0 && brokerRows.length === 0) {
        html = '<option value="" disabled selected>No symbols match your search</option>';
    }
    selectEl.innerHTML = html;
    if (current && Array.from(selectEl.options).some((o) => String(o.value).toUpperCase() === currentUpper)) {
        selectEl.value = current;
    } else if (selectEl.options.length > 0) {
        selectEl.selectedIndex = 0;
    }
    if (metaEl) {
        if (list.length === 0) {
            metaEl.textContent = 'No symbols returned from MT5; using curated defaults.';
        } else if (searchTerm) {
            metaEl.textContent = `Loaded ${list.length} MT5 symbols. Showing ${brokerRows.length} broker matches for "${searchTerm}".`;
        } else {
            metaEl.textContent = `Loaded ${list.length} MT5 symbols from active broker.`;
        }
    }
}

function applyBrokerSymbolsToTradeUI(rows) {
    const selectEl = document.getElementById('trade-quick-symbol');
    if (!selectEl) return;
    const current = String(selectEl.value || '').trim();
    const currentUpper = current.toUpperCase();
    const list = Array.isArray(rows) ? rows : [];
    const seen = new Set();
    const curatedRows = [];
    for (const opt of CURATED_SYMBOL_OPTIONS) {
        const value = String(opt?.value || '').trim();
        const label = String(opt?.label || value).trim();
        if (!value) continue;
        curatedRows.push({ value, label });
        seen.add(value.toUpperCase());
    }

    const brokerRows = [];
    for (const row of list) {
        const name = String(row?.name || '').trim();
        if (!name) continue;
        if (seen.has(name.toUpperCase())) continue;
        const desc = String(row?.description || '').trim();
        const vis = row?.visible ? 'visible' : 'hidden';
        const label = desc ? `${name} - ${desc}` : `${name} (${vis})`;
        brokerRows.push({ name, label });
    }

    let html = '<optgroup label="Curated">';
    for (const opt of curatedRows) {
        const value = String(opt?.value || '').trim();
        const label = String(opt?.label || value).trim();
        html += `<option value="${escapeHtml(value)}">${escapeHtml(label)}</option>`;
    }
    html += '</optgroup>';
    html += '<optgroup label="Broker (MT5)">';
    for (const row of brokerRows) {
        const name = String(row?.name || '').trim();
        const label = String(row?.label || name).trim();
        html += `<option value="${escapeHtml(name)}">${escapeHtml(label)}</option>`;
    }
    html += '</optgroup>';
    if (curatedRows.length === 0 && brokerRows.length === 0) {
        html = '<option value="" disabled selected>No symbols available</option>';
    }
    selectEl.innerHTML = html;
    if (current && Array.from(selectEl.options).some((o) => String(o.value).toUpperCase() === currentUpper)) {
        selectEl.value = current;
        return;
    }
    const mainSymbol = String(document.getElementById('sim-symbol')?.value || '').trim().toUpperCase();
    if (mainSymbol && setSelectValueCaseInsensitive(selectEl, mainSymbol)) {
        return;
    }
    if (selectEl.options.length > 0) {
        selectEl.selectedIndex = 0;
    }
}

function syncQuickTradeControlsFromMain() {
    const symbolEl = document.getElementById('trade-quick-symbol');
    const mainSymbol = String(document.getElementById('sim-symbol')?.value || '').trim().toUpperCase();
    if (symbolEl && mainSymbol) {
        setSelectValueCaseInsensitive(symbolEl, mainSymbol);
    }
    const quickLotsEl = document.getElementById('trade-quick-lots');
    const mainLotsEl = document.getElementById('trade-lots');
    if (quickLotsEl && mainLotsEl && !String(quickLotsEl.value || '').trim()) {
        quickLotsEl.value = String(mainLotsEl.value || '0.01');
    }
    const quickRiskEl = document.getElementById('trade-quick-risk-usd');
    if (quickRiskEl && !String(quickRiskEl.value || '').trim()) {
        quickRiskEl.value = '5';
    }
}

function isNoProtectionModeEnabled() {
    return !!document.getElementById('trade-no-protection-toggle')?.checked;
}

function syncTradeProtectionToggleUI() {
    const noProtection = isNoProtectionModeEnabled();
    const slEl = document.getElementById('trade-sl');
    const tpLongEl = document.getElementById('trade-tp-long');
    const tpShortEl = document.getElementById('trade-tp-short');
    if (slEl) {
        slEl.disabled = noProtection;
        if (noProtection) slEl.value = '0';
    }
    if (tpLongEl) {
        tpLongEl.disabled = noProtection;
        if (noProtection) tpLongEl.value = '0';
    }
    if (tpShortEl) {
        tpShortEl.disabled = noProtection;
        if (noProtection) tpShortEl.value = '0';
    }
}

function clearQuickTpWatcher() {
    quickTpUsdTarget = null;
    quickTpTradeId = null;
    quickTpAutoCloseInFlight = false;
}

function armQuickTpWatcher(openTrade, targetUsd) {
    const target = Number(targetUsd);
    const tradeId = Number(openTrade?.id);
    if (!Number.isFinite(target) || target <= 0 || !Number.isFinite(tradeId) || tradeId <= 0) {
        clearQuickTpWatcher();
        return;
    }
    quickTpUsdTarget = target;
    quickTpTradeId = tradeId;
    quickTpAutoCloseInFlight = false;
}

function computeLiveOpenPnlUsd(openPos, markPrice) {
    const position = openPos && typeof openPos === 'object' ? openPos : null;
    const px = Number(markPrice);
    if (!position || !Number.isFinite(px) || px <= 0) return NaN;
    const entry = Number(position.entry_price);
    const lots = Number(position.lot_size);
    if (!Number.isFinite(entry) || !Number.isFinite(lots) || lots <= 0) return NaN;
    const econ = (sessionSymbolEconomics && typeof sessionSymbolEconomics === 'object') ? sessionSymbolEconomics : null;
    const valuePer1Lot = Number(econ?.point_value_per_1lot);
    if (!Number.isFinite(valuePer1Lot) || valuePer1Lot <= 0) return NaN;
    const dir = String(position.direction || '').trim().toUpperCase();
    const sign = dir === 'BUY' ? 1 : (dir === 'SELL' ? -1 : 0);
    if (!sign) return NaN;
    return (px - entry) * sign * valuePer1Lot * lots;
}

async function maybeQuickTpAutoClose(markPrice = NaN) {
    if (!Number.isFinite(Number(quickTpUsdTarget)) || Number(quickTpUsdTarget) <= 0) return;
    if (!Number.isFinite(Number(quickTpTradeId)) || Number(quickTpTradeId) <= 0) return;
    if (quickTpAutoCloseInFlight) return;
    const openPos = currentOpenPositionState && typeof currentOpenPositionState === 'object'
        ? currentOpenPositionState
        : null;
    const openTradeId = Number(openPos?.id);
    if (!openPos || !Number.isFinite(openTradeId) || openTradeId <= 0) {
        return;
    }
    if (openTradeId !== Number(quickTpTradeId)) {
        clearQuickTpWatcher();
        return;
    }
    let px = Number(markPrice);
    if (!Number.isFinite(px) || px <= 0) {
        const lastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
        px = Number(lastBar?.close);
    }
    if (!Number.isFinite(px) || px <= 0) return;
    const pnlUsd = computeLiveOpenPnlUsd(openPos, px);
    if (!Number.isFinite(pnlUsd)) return;
    if (pnlUsd < Number(quickTpUsdTarget)) return;

    quickTpAutoCloseInFlight = true;
    showStatus(`Quick TP hit: $${Number(quickTpUsdTarget).toFixed(2)} reached, closing...`, 'info');
    try {
        const closeRes = await closePosition({ expectedTradeId: quickTpTradeId });
        if (!closeRes) {
            quickTpAutoCloseInFlight = false;
        }
    } catch (_) {
        quickTpAutoCloseInFlight = false;
    }
}

async function refreshBrokerSymbols(showToast = false) {
    try {
        const q = new URLSearchParams();
        q.set('include_hidden', 'true');
        q.set('limit', '2000');
        const res = await fetch(`${API_BASE}/api/simulation/mt5/symbols?${q.toString()}`);
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false || !Array.isArray(data?.symbols)) {
            if (showToast) showStatus(`MT5 symbols load failed: ${data?.error || res.status}`, 'warning');
            return;
        }
        const rows = Array.isArray(data?.symbols) ? data.symbols : [];
        applyBrokerSymbolsToUI(rows);
        applyBrokerSymbolsToAutomationUI(rows);
        applyBrokerSymbolsToTradeUI(rows);
        if (showToast) {
            if (rows.length > 0) {
                showStatus(`Loaded ${Number(data.count || 0)} broker symbols`, 'success');
            } else {
                showStatus(`MT5 symbols load failed: ${data?.error || 'no symbols returned'}`, 'warning');
            }
        }
    } catch (err) {
        if (showToast) showStatus(`MT5 symbols load failed: ${err.message}`, 'warning');
    }
}

function applySymbolSearchFilter() {
    applyBrokerSymbolsToUI(brokerSymbolCatalog);
}

function applyAutomationSymbolSearchFilter() {
    applyBrokerSymbolsToAutomationUI(brokerSymbolCatalog);
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
function getPersistedSessionId() {
    try {
        const raw = String(localStorage.getItem(SESSION_STORAGE_KEY) || '').trim();
        const sid = Number(raw);
        return Number.isFinite(sid) && sid > 0 ? Math.floor(sid) : null;
    } catch (_) {
        return null;
    }
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
    // Keep enough warmup bars for heavy indicators (Trendilo/LSMA/300-length stacks),
    // especially on higher timeframes like D1 where day-based fetches can be too short.
    const warmupFloor = tfMins >= 1440 ? 220 : (tfMins >= 240 ? 180 : 140);
    const withBuffer = base + 20;
    return Math.max(warmupFloor, Math.min(10000, withBuffer));
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

function setAgentToolModeBadge(modeLike) {
    const badgeEl = document.getElementById('agent-tool-mode-badge');
    if (!badgeEl) return;
    const raw = String(modeLike || '').trim().toLowerCase();
    const mode = ['all', 'parent', 'child'].includes(raw) ? raw : 'all';
    if (mode === 'parent') {
        badgeEl.textContent = 'PARENT';
        badgeEl.style.background = '#1d4ed8';
        badgeEl.style.color = '#dbeafe';
        return;
    }
    if (mode === 'child') {
        badgeEl.textContent = 'CHILD';
        badgeEl.style.background = '#7c3aed';
        badgeEl.style.color = '#ede9fe';
        return;
    }
    badgeEl.textContent = 'ALL';
    badgeEl.style.background = '#334155';
    badgeEl.style.color = '#e2e8f0';
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
    const strategyToolAccessEl = document.getElementById('agent-strategy-tool-access');
    const strategyToolAccess = String(cfg.strategy_tool_access_mode || '').trim().toLowerCase();
    if (strategyToolAccessEl && ['all', 'parent', 'child'].includes(strategyToolAccess)) {
        strategyToolAccessEl.value = strategyToolAccess;
    }
    const toolSelectionModeEl = document.getElementById('agent-tool-selection-mode');
    const toolSelectionMode = String(cfg.tool_selection_mode || '').trim().toLowerCase();
    if (toolSelectionModeEl && ['autonomous', 'guided', 'minimal'].includes(toolSelectionMode)) {
        toolSelectionModeEl.value = toolSelectionMode;
    }
    const strategyProfileEl = document.getElementById('agent-strategy-profile');
    const strategyProfile = String(cfg.agent_strategy_profile || '').trim().toLowerCase();
    if (strategyProfileEl && ['classic_htf_fvg', 'htf_fvg_liquidity_reclaim_v2', 'orb_ny_15m_imbalance', 'trendilo_confirmation_v1', 'advanced_trendilo_confirmation_v1', 'trendilo_lsma_confirmation_v1', 'alpha_wave_confirmation_v1'].includes(strategyProfile)) {
        strategyProfileEl.value = strategyProfile;
    }
    const strategyPresetEl = document.getElementById('agent-strategy-preset');
    const strategyPreset = String(cfg.agent_strategy_preset || '').trim().toLowerCase();
    if (strategyPresetEl && ['default', 'conservative', 'aggressive', 'xauusd_m15', 'nas100_m15', 'xauusd_m1', 'nas100_m1', 'us500_m1'].includes(strategyPreset)) {
        strategyPresetEl.value = strategyPreset;
    }
    const liqGateModeEl = document.getElementById('agent-liq-gate-mode');
    const liqGateMode = String(cfg.mtf_liquidity_gate_mode || cfg.liquidity_gate_mode || '').trim().toLowerCase();
    if (liqGateModeEl && ['hybrid', 'strict', 'assist'].includes(liqGateMode)) {
        liqGateModeEl.value = liqGateMode;
    }
    const liqSweepFreshHoursEl = document.getElementById('agent-liq-sweep-fresh-hours');
    const liqSweepFreshHours = Number(cfg.mtf_liquidity_sweep_freshness_hours ?? cfg.liquidity_sweep_freshness_hours);
    if (liqSweepFreshHoursEl && Number.isFinite(liqSweepFreshHours)) {
        liqSweepFreshHoursEl.value = String(Math.max(0.5, Math.min(24, liqSweepFreshHours)));
    }
    const liqSweepMinBarsEl = document.getElementById('agent-liq-sweep-min-bars');
    const liqSweepMinBars = Number(cfg.mtf_liquidity_sweep_freshness_min_bars ?? cfg.liquidity_sweep_freshness_min_bars);
    if (liqSweepMinBarsEl && Number.isFinite(liqSweepMinBars)) {
        liqSweepMinBarsEl.value = String(Math.max(1, Math.min(200, Math.round(liqSweepMinBars))));
    }
    const liqSweepDistGoldEl = document.getElementById('agent-liq-sweep-dist-gold');
    const liqSweepDistGold = Number(cfg.mtf_liquidity_sweep_distance_atr_gold ?? cfg.liquidity_sweep_distance_atr_gold);
    if (liqSweepDistGoldEl && Number.isFinite(liqSweepDistGold)) {
        liqSweepDistGoldEl.value = String(Math.max(0.05, Math.min(3, liqSweepDistGold)));
    }
    const liqSweepDistIndicesEl = document.getElementById('agent-liq-sweep-dist-indices');
    const liqSweepDistIndices = Number(cfg.mtf_liquidity_sweep_distance_atr_indices ?? cfg.liquidity_sweep_distance_atr_indices);
    if (liqSweepDistIndicesEl && Number.isFinite(liqSweepDistIndices)) {
        liqSweepDistIndicesEl.value = String(Math.max(0.05, Math.min(3, liqSweepDistIndices)));
    }
    const liqSweepDistFxEl = document.getElementById('agent-liq-sweep-dist-fx');
    const liqSweepDistFx = Number(cfg.mtf_liquidity_sweep_distance_atr_fx ?? cfg.liquidity_sweep_distance_atr_fx);
    if (liqSweepDistFxEl && Number.isFinite(liqSweepDistFx)) {
        liqSweepDistFxEl.value = String(Math.max(0.05, Math.min(3, liqSweepDistFx)));
    }
    const liqSweepDistDefaultEl = document.getElementById('agent-liq-sweep-dist-default');
    const liqSweepDistDefault = Number(cfg.mtf_liquidity_sweep_distance_atr_default ?? cfg.liquidity_sweep_distance_atr_default);
    if (liqSweepDistDefaultEl && Number.isFinite(liqSweepDistDefault)) {
        liqSweepDistDefaultEl.value = String(Math.max(0.05, Math.min(3, liqSweepDistDefault)));
    }
    syncAgentStrategyControls();
    setAgentToolModeBadge(strategyToolAccess);
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
    const guardrailMaxRiskEl = document.getElementById('agent-guardrail-max-risk-per-trade');
    const guardrailMaxRisk = Number(
        cfg.guardrail_max_risk_per_trade_usd
        ?? cfg.guardrail_trade_risk_cap_usd
        ?? cfg.guardrail_max_risk_per_trade
    );
    if (guardrailMaxRiskEl && Number.isFinite(guardrailMaxRisk)) {
        guardrailMaxRiskEl.value = String(Math.max(0, Math.min(1_000_000_000, guardrailMaxRisk)));
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
        trendilo: !!vis.trendilo,
        advancedTrendilo: !!vis.advancedTrendilo,
        trendiloLsma: !!vis.trendiloLsma,
        alphaWave: !!vis.alphaWave,
        deadzonePro: !!vis.deadzonePro,
        orbSignal: !!vis.orbSignal,
        trendiloBarColor: !!vis.trendiloBarColor,
        goldenCross: !!vis.goldenCross,
    };
    indicatorSelection = { ...indicatorSelection, ...next };
    const map = {
        smaEma: 'ind-sma-ema',
        adx: 'ind-adx',
        rsi: 'ind-rsi',
        stoch: 'ind-stoch',
        bollinger: 'ind-bollinger',
        trendilo: 'ind-trendilo',
        advancedTrendilo: 'ind-advanced-trendilo',
        trendiloLsma: 'ind-trendilo-lsma',
        alphaWave: 'ind-alpha-wave',
        deadzonePro: 'ind-deadzone-pro',
        orbSignal: 'ind-orb-signal',
        trendiloBarColor: 'ind-trendilo-barcolor',
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
        applyLiveConfirmationToPayload(body);
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
        void refreshQuickOpenTrades();
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
        applyLiveConfirmationToPayload(body);
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
        void refreshQuickOpenTrades();
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

function _trendiloOppCacheKey() {
    const sid = Number(sessionId || 0);
    const strategy = String(document.getElementById('trendilo-opp-strategy')?.value || 'trendilo').trim().toLowerCase() || 'trendilo';
    return `${TRENDILO_OPP_CACHE_KEY_PREFIX}${sid > 0 ? sid : 0}:${strategy}`;
}

function _saveTrendiloOppScanCache(scanData) {
    if (!scanData || typeof scanData !== 'object') return;
    const strategy = String(scanData.strategy || document.getElementById('trendilo-opp-strategy')?.value || 'trendilo').trim().toLowerCase() || 'trendilo';
    const payload = {
        session_id: Number(sessionId || 0),
        saved_at: new Date().toISOString(),
        strategy,
        data: scanData,
    };
    try {
        localStorage.setItem(_trendiloOppCacheKey(), JSON.stringify(payload));
    } catch (_) {
        // ignore storage failures
    }
}

function _loadTrendiloOppScanCache(maxAgeMin = TRENDILO_OPP_CACHE_MAX_AGE_MIN) {
    try {
        const raw = String(localStorage.getItem(_trendiloOppCacheKey()) || '').trim();
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        if (!parsed || typeof parsed !== 'object' || !parsed.data || typeof parsed.data !== 'object') return null;
        const savedAt = Date.parse(String(parsed.saved_at || ''));
        if (Number.isFinite(savedAt)) {
            const ageMin = (Date.now() - savedAt) / 60000.0;
            if (Number.isFinite(ageMin) && ageMin > Number(maxAgeMin || TRENDILO_OPP_CACHE_MAX_AGE_MIN)) return null;
        }
        return parsed;
    } catch (_) {
        return null;
    }
}

function _compactTrendiloOppCacheForContext(maxRows = 12) {
    const cached = _loadTrendiloOppScanCache(TRENDILO_OPP_CACHE_MAX_AGE_MIN);
    if (!cached || !cached.data || typeof cached.data !== 'object') return null;
    const d = cached.data;
    const rows = Array.isArray(d.opportunities) ? d.opportunities.slice(0, Math.max(1, Number(maxRows || 12))) : [];
    const compactRows = rows.map((r) => ({
        strategy: String(r?.strategy || ''),
        symbol: String(r?.symbol || ''),
        direction: String(r?.direction || ''),
        confidence: Number(r?.confidence || 0),
        entry_ref: Number(r?.entry_ref || 0),
        stop_loss: Number(r?.stop_loss || 0),
        take_profit: Number(r?.take_profit || 0),
        rr: Number(r?.rr || 0),
        lot_size: Number(r?.lot_size || 0),
    }));
    return {
        saved_at: String(cached.saved_at || ''),
        strategy: String(d.strategy || cached.strategy || ''),
        timeframe: String(d.timeframe || ''),
        execution_timeframe: String(d.execution_timeframe || d.timeframe || ''),
        source: String(d.source || ''),
        symbols_scanned: Number(d.symbols_scanned || 0),
        tradeable_count: Number(d.tradeable_count || 0),
        top_opportunities: compactRows,
    };
}

function _parseTrendiloOppSymbols(rawLike) {
    const raw = String(rawLike || '').trim();
    if (!raw) return [];
    const out = [];
    const seen = new Set();
    raw.split(/[\s,;]+/g).forEach((part) => {
        const s = String(part || '').trim().toUpperCase();
        if (!s || seen.has(s)) return;
        seen.add(s);
        out.push(s);
    });
    return out;
}

function _collectTrendiloOppScanArgs() {
    const strategy = String(document.getElementById('trendilo-opp-strategy')?.value || 'trendilo').trim().toLowerCase() || 'trendilo';
    const universe = String(document.getElementById('trendilo-opp-universe')?.value || '').trim();
    const scanTimeframe = normalizeTimeframeLabel(
        document.getElementById('trendilo-opp-timeframe')?.value || document.getElementById('sim-timeframe')?.value || 'M5',
        'M5',
    );
    const execRaw = String(document.getElementById('trendilo-opp-exec-timeframe')?.value || 'AUTO').trim().toUpperCase();
    const executionTimeframe = execRaw === 'AUTO' ? scanTimeframe : normalizeTimeframeLabel(execRaw, scanTimeframe);
    const rawLimit = Number(document.getElementById('trendilo-opp-universe-limit')?.value || 80);
    const rawLookback = Number(document.getElementById('trendilo-opp-lookback')?.value || 120);
    const rawMaxResults = Number(document.getElementById('trendilo-opp-max-results')?.value || 25);
    const symbols = _parseTrendiloOppSymbols(document.getElementById('trendilo-opp-symbols')?.value || '');
    const args = {
        strategy,
        timeframe: scanTimeframe,
        execution_timeframe: executionTimeframe,
        lookback_bars: Number.isFinite(rawLookback) ? Math.max(20, Math.min(3000, Math.round(rawLookback))) : 120,
        max_results: Number.isFinite(rawMaxResults) ? Math.max(1, Math.min(200, Math.round(rawMaxResults))) : 25,
        summary_only: true,
        include_non_tradeable: false,
        preset: String(document.getElementById('agent-strategy-preset')?.value || 'default'),
    };
    if (universe) args.universe = universe;
    if (Number.isFinite(rawLimit)) args.universe_limit = Math.max(1, Math.min(200, Math.round(rawLimit)));
    if (symbols.length) args.symbols = symbols.slice(0, 120);
    return args;
}

function _strategyAutomationSupportsStrategy(strategyLike) {
    const s = _strategyAutomationResolveStartStrategy(strategyLike);
    return s === 'trendilo'
        || s === 'advanced_trendilo'
        || s === 'trendilo_lsma'
        || s === 'alpha_wave'
        || s === 'orb_alpha_hybrid'
        || s === 'deadzone_pro';
}

function _strategyAutomationResolveStartStrategy(strategyLike) {
    const s = String(strategyLike || '').trim().toLowerCase();
    if (s === 'orb') return 'orb_alpha_hybrid';
    if (s === 'deadzone' || s === 'deadzonepro') return 'deadzone_pro';
    return s;
}

function _normalizeDeadzoneAutomationMode(modeLike) {
    const m = String(modeLike || 'default').trim().toLowerCase();
    if (m === 'advanced') return 'advanced';
    if (m === 'rsi_adaptive' || m === 'adaptive_rsi' || m === 'rsi') return 'rsi_adaptive';
    if (m === 'rsi_quant_sell_only' || m === 'quant_sell_only' || m === 'qns' || m === 'sell_only') return 'rsi_quant_sell_only';
    if (m === 'rsi_quant' || m === 'quant_rsi' || m === 'quant') return 'rsi_quant';
    return 'default';
}

function _getAutoStartDeadzoneMode() {
    return _normalizeDeadzoneAutomationMode(document.getElementById('auto-start-deadzone-mode')?.value || 'default');
}

function _syncAutoStartDeadzoneModeControl() {
    const strategy = _strategyAutomationResolveStartStrategy(document.getElementById('auto-start-strategy')?.value || 'trendilo');
    const wrap = document.getElementById('auto-start-deadzone-mode-wrap');
    const sel = document.getElementById('auto-start-deadzone-mode');
    const isDeadzone = strategy === 'deadzone_pro';
    if (wrap) wrap.classList.toggle('d-none', !isDeadzone);
    if (sel && !isDeadzone) sel.value = 'default';
}

function _formatAutomationStrategyLabel(jobLike) {
    const strategy = String(jobLike?.strategy || '').trim();
    const mode = _normalizeDeadzoneAutomationMode(jobLike?.deadzone_mode || 'default');
    if (String(strategy).toLowerCase() === 'deadzone_pro') {
        const modeLbl = mode === 'advanced' ? 'ADV' : (mode === 'rsi_adaptive' ? 'RSI' : (mode === 'rsi_quant' ? 'QNT' : (mode === 'rsi_quant_sell_only' ? 'QNS' : 'DEF')));
        return `${strategy} (${modeLbl})`;
    }
    return strategy;
}

function _strategyAutomationJobKey(jobLike) {
    const strategy = String(jobLike?.strategy || '').trim().toLowerCase();
    const symbol = String(jobLike?.symbol || '').trim().toUpperCase();
    const timeframe = normalizeTimeframeLabel(jobLike?.timeframe || '', 'M15');
    const mode = strategy === 'deadzone_pro'
        ? _normalizeDeadzoneAutomationMode(jobLike?.deadzone_mode || 'default')
        : 'default';
    return `${strategy}|${symbol}|${timeframe}|${mode}`;
}

function _syncStrategyAutomationJobsCache(jobsLike) {
    const list = Array.isArray(jobsLike) ? jobsLike : [];
    strategyAutomationJobs = list.map((j) => (j && typeof j === 'object' ? { ...j } : {}));
    strategyAutomationJobIndex = {};
    const validJobIds = new Set();
    strategyAutomationJobs.forEach((job) => {
        if (!job || typeof job !== 'object') return;
        const jobId = String(job?.job_id || '').trim();
        if (jobId) validJobIds.add(jobId);
        const key = _strategyAutomationJobKey(job);
        strategyAutomationJobIndex[key] = { ...job };
    });
    automationMonitorExpandedJobs.forEach((jobId) => {
        if (!validJobIds.has(String(jobId || ''))) automationMonitorExpandedJobs.delete(jobId);
    });
}

function _findAutomationJobForOpportunity(row) {
    if (!row || typeof row !== 'object') return null;
    const resolvedStrategy = _strategyAutomationResolveStartStrategy(row.strategy);
    const key = _strategyAutomationJobKey({
        strategy: resolvedStrategy,
        symbol: row.symbol,
        timeframe: row?.schedule_trade_entry_args?.timeframe || lastStrategyOpportunityScanData?.execution_timeframe || lastStrategyOpportunityScanData?.timeframe || 'M15',
    });
    return strategyAutomationJobIndex[key] || null;
}

function _renderStrategyAutomationJobsTable(jobsLike) {
    const head = document.getElementById('trendilo-auto-head');
    const body = document.getElementById('trendilo-auto-body');
    const summary = document.getElementById('trendilo-auto-summary');
    if (!head || !body || !summary) return;
    const jobs = Array.isArray(jobsLike) ? jobsLike : [];
    const running = jobs.filter((j) => !!j?.enabled).length;
    summary.textContent = `Automation jobs: ${running} running / ${jobs.length} total.`;
    if (!jobs.length) {
        head.innerHTML = '';
        body.innerHTML = '<tr><td class="text-center text-muted py-2"><small>No automation jobs running.</small></td></tr>';
        return;
    }
    head.innerHTML = `
        <tr>
            <th>Job</th>
            <th>Strategy</th>
            <th>Symbol</th>
            <th>TF</th>
            <th>Status</th>
            <th>Color</th>
            <th>Open</th>
            <th>Action</th>
        </tr>
    `;
    body.innerHTML = jobs.map((j) => {
        const status = !!j?.enabled ? 'RUNNING' : 'STOPPED';
        const color = String(j?.current_color || j?.last_color || 'gray').toUpperCase();
        const openCount = Number(j?.open_trades_count || 0);
        const childId = Number(j?.child_session_id || 0);
        const parentId = Number(j?.parent_session_id || 0);
        const jobId = String(j?.job_id || '');
        const stopBtn = !!j?.enabled
            ? `<button type="button" class="btn btn-sm btn-outline-danger" data-auto-action="stop-job" data-auto-parent="${parentId}" data-auto-child="${childId}" data-auto-job="${escapeHtml(jobId)}">Stop</button>`
            : '<span class="text-muted">-</span>';
        return `
            <tr>
                <td>${escapeHtml(jobId)}</td>
                <td>${escapeHtml(_formatAutomationStrategyLabel(j))}</td>
                <td>${escapeHtml(String(j?.symbol || ''))}</td>
                <td>${escapeHtml(String(j?.timeframe || ''))}</td>
                <td>${escapeHtml(status)}</td>
                <td>${escapeHtml(color)}</td>
                <td>${openCount}</td>
                <td>${stopBtn}</td>
            </tr>
        `;
    }).join('');
}

async function loadStrategyAutomationJobs(showStatusToast = false) {
    const statusEl = document.getElementById('trendilo-opp-status');
    try {
        const res = await fetch(`${API_BASE}/api/simulation/agent/strategy-automation/jobs?include_disabled=1`);
        const out = await res.json().catch(() => ({}));
        if (!res.ok || out?.ok === false) {
            const err = String(out?.error || out?.detail || `HTTP ${res.status}`);
            _syncStrategyAutomationJobsCache([]);
            _renderStrategyAutomationJobsTable([]);
            if (showStatusToast) showStatus(`Automation jobs load failed: ${err}`, 'warning');
            return;
        }
        _syncStrategyAutomationJobsCache(Array.isArray(out?.jobs) ? out.jobs : []);
        _renderStrategyAutomationJobsTable(strategyAutomationJobs);
        _renderAutomationMonitorRows(strategyAutomationJobs);
        if (showStatusToast && statusEl) statusEl.textContent = `Automation jobs loaded (${strategyAutomationJobs.length})`;
    } catch (err) {
        _syncStrategyAutomationJobsCache([]);
        _renderStrategyAutomationJobsTable([]);
        _renderAutomationMonitorRows([]);
        if (showStatusToast) showStatus(`Automation jobs load failed: ${String(err?.message || err)}`, 'warning');
    }
}

function _automationJobOpenTrades(jobLike) {
    const job = (jobLike && typeof jobLike === 'object') ? jobLike : {};
    const list = Array.isArray(job?.open_trades) ? job.open_trades : [];
    const normalized = list
        .map((t) => (t && typeof t === 'object' ? t : {}))
        .map((t) => ({
            id: Number(t?.id || 0),
            direction: String(t?.direction || '').trim().toUpperCase(),
            entry_price: Number(t?.entry_price),
            stop_loss: Number(t?.stop_loss),
            take_profit: Number(t?.take_profit),
            lot_size: Number(t?.lot_size),
            status: String(t?.status || '').trim().toLowerCase(),
        }))
        .filter((t) => Number.isFinite(t.id) && t.id > 0);
    if (normalized.length > 0) return normalized;
    const one = (job?.open_trade && typeof job.open_trade === 'object') ? job.open_trade : null;
    if (!one) return [];
    const oneId = Number(one?.id || 0);
    if (!Number.isFinite(oneId) || oneId <= 0) return [];
    return [{
        id: oneId,
        direction: String(one?.direction || '').trim().toUpperCase(),
        entry_price: Number(one?.entry_price),
        stop_loss: Number(one?.stop_loss),
        take_profit: Number(one?.take_profit),
        lot_size: Number(one?.lot_size),
        status: String(one?.status || '').trim().toLowerCase(),
    }];
}

function _automationMonitorRunningOnlyEnabled() {
    return !!document.getElementById('auto-monitor-running-only')?.checked;
}

function _automationMonitorSortMode() {
    const raw = String(document.getElementById('auto-monitor-sort')?.value || 'created_desc').trim().toLowerCase();
    return raw === 'created_asc' ? 'created_asc' : 'created_desc';
}

function _automationMonitorParseMs(rawLike) {
    const raw = String(rawLike || '').trim();
    if (!raw) return Number.NaN;
    let ms = Date.parse(raw);
    if (Number.isFinite(ms)) return ms;
    ms = Date.parse(raw.replace(' ', 'T'));
    if (Number.isFinite(ms)) return ms;
    return Number.NaN;
}

function _automationMonitorSortJobs(jobsLike) {
    const list = Array.isArray(jobsLike) ? jobsLike.slice() : [];
    const mode = _automationMonitorSortMode();
    list.sort((a, b) => {
        const aMs = _automationMonitorParseMs(a?.created_at);
        const bMs = _automationMonitorParseMs(b?.created_at);
        const aHas = Number.isFinite(aMs);
        const bHas = Number.isFinite(bMs);
        if (aHas && bHas && aMs !== bMs) {
            return mode === 'created_asc' ? (aMs - bMs) : (bMs - aMs);
        }
        if (aHas !== bHas) {
            return aHas ? -1 : 1;
        }
        const aId = Number(a?.child_session_id || 0);
        const bId = Number(b?.child_session_id || 0);
        if (aId !== bId) return mode === 'created_asc' ? (aId - bId) : (bId - aId);
        return String(a?.job_id || '').localeCompare(String(b?.job_id || ''));
    });
    return list;
}

function _renderAutomationMonitorRows(jobsLike) {
    const head = document.getElementById('auto-monitor-head');
    const body = document.getElementById('auto-monitor-body');
    const summary = document.getElementById('auto-monitor-summary');
    if (!head || !body || !summary) return;
    const allJobs = Array.isArray(jobsLike) ? jobsLike : [];
    const running = allJobs.filter((j) => !!j?.enabled).length;
    const runningOnly = _automationMonitorRunningOnlyEnabled();
    const jobs = _automationMonitorSortJobs(runningOnly ? allJobs.filter((j) => !!j?.enabled) : allJobs);
    summary.textContent = runningOnly
        ? `${running} running / ${allJobs.length} total automation jobs. Showing running only.`
        : `${running} running / ${allJobs.length} total automation jobs.`;
    if (!jobs.length) {
        head.innerHTML = '';
        body.innerHTML = runningOnly
            ? '<tr><td class="text-center text-muted py-3"><small>No running automation jobs.</small></td></tr>'
            : '<tr><td class="text-center text-muted py-3"><small>No automation jobs.</small></td></tr>';
        return;
    }
    head.innerHTML = `
        <tr>
            <th>Job</th>
            <th>Strategy</th>
            <th>Symbol</th>
            <th>TF</th>
            <th>Status</th>
            <th>Color</th>
            <th>Open</th>
            <th>Session</th>
            <th>Actions</th>
        </tr>
    `;
    const htmlRows = [];
    jobs.forEach((j) => {
        const childId = Number(j?.child_session_id || 0);
        const parentId = Number(j?.parent_session_id || 0);
        const jobId = String(j?.job_id || '').trim();
        const status = !!j?.enabled ? 'RUNNING' : 'STOPPED';
        const color = String(j?.current_color || j?.last_color || 'gray').toUpperCase();
        const openTrades = _automationJobOpenTrades(j);
        const openCount = Number(j?.open_trades_count || openTrades.length || 0);
        const hasOpen = openTrades.length > 0;
        const expanded = hasOpen && automationMonitorExpandedJobs.has(jobId);
        const toggleBtn = hasOpen
            ? `<button type="button" class="btn btn-sm btn-outline-secondary me-1" data-auto-action="toggle-job-trades" data-auto-job="${escapeHtml(jobId)}">${expanded ? 'Hide Trades' : 'View Trades'}</button>`
            : '<span class="text-muted">No Trades</span>';
        const stopBtn = !!j?.enabled
            ? `<button type="button" class="btn btn-sm btn-outline-danger" data-auto-action="stop-job" data-auto-parent="${parentId}" data-auto-child="${childId}" data-auto-job="${escapeHtml(String(j?.job_id || ''))}">Stop</button>`
            : '<span class="text-muted">-</span>';
        htmlRows.push(`
            <tr data-auto-row="${escapeHtml(jobId)}">
                <td>${escapeHtml(String(j?.job_id || ''))}</td>
                <td>${escapeHtml(_formatAutomationStrategyLabel(j))}</td>
                <td>${escapeHtml(String(j?.symbol || ''))}</td>
                <td>${escapeHtml(String(j?.timeframe || ''))}</td>
                <td>${escapeHtml(status)}</td>
                <td>${escapeHtml(color)}</td>
                <td>${openCount}</td>
                <td>P#${parentId} / C#${childId}</td>
                <td>
                    ${toggleBtn}
                    <button
                        type="button"
                        class="btn btn-sm btn-outline-info me-1"
                        data-auto-action="show-job-logs"
                        data-auto-job="${escapeHtml(String(j?.job_id || ''))}"
                        data-auto-parent="${parentId}"
                        data-auto-child="${childId}"
                        data-auto-symbol="${escapeHtml(String(j?.symbol || ''))}"
                        data-auto-strategy="${escapeHtml(String(j?.strategy || ''))}"
                        data-auto-timeframe="${escapeHtml(String(j?.timeframe || 'M15'))}"
                        data-auto-source="${escapeHtml(String(j?.source || 'mt5'))}"
                        data-auto-deadzone-mode="${escapeHtml(String(j?.deadzone_mode || 'default'))}"
                    >Show Logs</button>
                    <button
                        type="button"
                        class="btn btn-sm btn-outline-primary me-1"
                        data-auto-action="open-job-chart"
                        data-auto-job="${escapeHtml(String(j?.job_id || ''))}"
                        data-auto-parent="${parentId}"
                        data-auto-child="${childId}"
                        data-auto-symbol="${escapeHtml(String(j?.symbol || ''))}"
                        data-auto-strategy="${escapeHtml(String(j?.strategy || ''))}"
                        data-auto-timeframe="${escapeHtml(String(j?.timeframe || 'M15'))}"
                        data-auto-source="${escapeHtml(String(j?.source || 'mt5'))}"
                    >Open Chart</button>
                    ${stopBtn}
                </td>
            </tr>
        `);
        if (expanded) {
            const tradeRows = openTrades.map((t) => {
                const entry = Number.isFinite(Number(t?.entry_price)) ? Number(t.entry_price).toFixed(5) : '-';
                const sl = Number.isFinite(Number(t?.stop_loss)) ? Number(t.stop_loss).toFixed(5) : '-';
                const tp = Number.isFinite(Number(t?.take_profit)) ? Number(t.take_profit).toFixed(5) : '-';
                const lot = Number.isFinite(Number(t?.lot_size)) ? Number(t.lot_size).toFixed(3) : '-';
                return `
                    <tr>
                        <td>${Number(t?.id || 0)}</td>
                        <td>${escapeHtml(String(t?.direction || ''))}</td>
                        <td>${entry}</td>
                        <td>${sl}</td>
                        <td>${tp}</td>
                        <td>${lot}</td>
                        <td>
                            <button
                                type="button"
                                class="btn btn-sm btn-outline-warning"
                                data-auto-action="close-open-trade"
                                data-auto-job="${escapeHtml(jobId)}"
                                data-auto-child="${childId}"
                                data-auto-trade="${Number(t?.id || 0)}"
                            >Close</button>
                        </td>
                    </tr>
                `;
            }).join('');
            htmlRows.push(`
                <tr data-auto-detail-row="${escapeHtml(jobId)}">
                    <td colspan="9" class="py-2">
                        <div class="p-2 border rounded" style="border-color: rgba(148,163,184,0.28) !important; background: rgba(15,23,42,0.45);">
                            <div class="mb-1" style="font-size:0.78rem;color:#cbd5e1;">
                                Open trades under job <code>${escapeHtml(jobId)}</code> (session #${childId})
                            </div>
                            <div class="table-responsive">
                                <table class="table table-sm mb-0">
                                    <thead>
                                        <tr>
                                            <th>ID</th>
                                            <th>Dir</th>
                                            <th>Entry</th>
                                            <th>SL</th>
                                            <th>TP</th>
                                            <th>Lot</th>
                                            <th>Action</th>
                                        </tr>
                                    </thead>
                                    <tbody>${tradeRows}</tbody>
                                </table>
                            </div>
                        </div>
                    </td>
                </tr>
            `);
        }
    });
    body.innerHTML = htmlRows.join('');
}

function _automationLogsSortMode() {
    return String(document.getElementById('auto-logs-sort')?.value || 'event_time_desc').trim().toLowerCase();
}

function _automationLogsDirectionFilter() {
    const raw = String(document.getElementById('auto-logs-direction')?.value || 'all').trim().toLowerCase();
    return raw === 'buy' || raw === 'sell' ? raw : 'all';
}

function _automationLogsScopeFilter() {
    const raw = String(document.getElementById('auto-logs-scope')?.value || 'both').trim().toLowerCase();
    return raw === 'major' || raw === 'routine' || raw === 'both' ? raw : 'both';
}

function _automationLogsParseMs(rawLike) {
    return _automationMonitorParseMs(rawLike);
}

function _automationLogsFormatTime(rawLike) {
    const ms = _automationLogsParseMs(rawLike);
    if (!Number.isFinite(ms)) return '-';
    try {
        return new Date(ms).toLocaleString([], {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: false,
        });
    } catch (_) {
        return '-';
    }
}

function _automationLogsPriceDecimals() {
    const symbol = String(automationLogsContext?.symbol || document.getElementById('sim-symbol')?.value || 'XAUUSD').toUpperCase();
    return getPriceDecimalsForSymbol(symbol);
}

function _automationLogsFormatPrice(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return '-';
    return n.toFixed(_automationLogsPriceDecimals());
}

function _automationLogsFormatPnl(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return '-';
    return n.toFixed(2);
}

function _automationLogsFormatR(v) {
    const n = Number(v);
    if (!Number.isFinite(n)) return '-';
    return n.toFixed(2);
}

function _automationLogsApplySortFilter(eventsLike) {
    const list = Array.isArray(eventsLike) ? eventsLike.slice() : [];
    const dirFilter = _automationLogsDirectionFilter();
    const scopeFilter = _automationLogsScopeFilter();
    let rows = list.filter((row) => {
        const ev = String(row?.event || '').trim().toLowerCase();
        if (scopeFilter === 'major' && ev === 'routine') return false;
        if (scopeFilter === 'routine' && ev !== 'routine') return false;
        const dir = String(row?.direction || '').trim().toLowerCase();
        if (dirFilter === 'buy') return dir === 'buy';
        if (dirFilter === 'sell') return dir === 'sell';
        return true;
    });
    const mode = _automationLogsSortMode();
    const byEventTime = (a, b) => _automationLogsParseMs(a?.event_time) - _automationLogsParseMs(b?.event_time);
    const byCreatedTime = (a, b) => _automationLogsParseMs(a?.trade_created_at) - _automationLogsParseMs(b?.trade_created_at);
    const byTradeId = (a, b) => Number(a?.trade_id || 0) - Number(b?.trade_id || 0);
    const byDirection = (a, b) => String(a?.direction || '').localeCompare(String(b?.direction || ''));

    switch (mode) {
        case 'event_time_asc':
            rows.sort(byEventTime);
            break;
        case 'trade_created_desc':
            rows.sort((a, b) => byCreatedTime(b, a));
            break;
        case 'trade_created_asc':
            rows.sort(byCreatedTime);
            break;
        case 'trade_id_desc':
            rows.sort((a, b) => byTradeId(b, a));
            break;
        case 'trade_id_asc':
            rows.sort(byTradeId);
            break;
        case 'direction_buy_sell':
            rows.sort((a, b) => {
                const cmp = byDirection(a, b);
                if (cmp !== 0) return cmp;
                return byEventTime(b, a);
            });
            break;
        case 'direction_sell_buy':
            rows.sort((a, b) => {
                const cmp = byDirection(b, a);
                if (cmp !== 0) return cmp;
                return byEventTime(b, a);
            });
            break;
        case 'event_time_desc':
        default:
            rows.sort((a, b) => byEventTime(b, a));
            break;
    }
    return rows;
}

function _renderAutomationLogsRows() {
    const head = document.getElementById('auto-logs-head');
    const body = document.getElementById('auto-logs-body');
    const summary = document.getElementById('auto-logs-summary');
    const statusEl = document.getElementById('auto-logs-status');
    if (!head || !body || !summary) return;

    const ctx = automationLogsContext || {};
    const strategyLabel = _formatAutomationStrategyLabel(ctx);
    const rows = _automationLogsApplySortFilter(automationLogsEvents);
    const uniqueTradeIds = new Set(rows.map((r) => Number(r?.trade_id || 0)).filter((v) => v > 0));
    const openCount = rows.filter((r) => String(r?.event || '').toLowerCase() === 'open').length;
    const closeCount = rows.filter((r) => String(r?.event || '').toLowerCase() === 'close').length;
    const routineCount = rows.filter((r) => String(r?.event || '').toLowerCase() === 'routine').length;
    summary.textContent = `Job ${String(ctx?.job_id || '-')} | ${strategyLabel} | ${String(ctx?.symbol || '-')} ${String(ctx?.timeframe || '-')} | Events: ${rows.length} (open=${openCount}, close=${closeCount}, routine=${routineCount}) | Trades: ${uniqueTradeIds.size}`;
    if (statusEl) statusEl.textContent = rows.length ? `Loaded ${rows.length} log rows` : 'No logs';

    head.innerHTML = `
        <tr>
            <th>Event Time</th>
            <th>Trade Created</th>
            <th>Trade ID</th>
            <th>Event</th>
            <th>Dir</th>
            <th>Reason</th>
            <th>M1</th>
            <th>M5</th>
            <th>M15</th>
            <th>Price</th>
            <th>RSI(14)</th>
            <th>M1 DEF R/U</th>
            <th>M1 ADV R/U</th>
            <th>M5 DEF R/U</th>
            <th>M5 ADV R/U</th>
            <th>M5 Flip At</th>
            <th>Mode</th>
            <th>Entry</th>
            <th>Exit</th>
            <th>P&L</th>
            <th>R</th>
            <th>Status</th>
        </tr>
    `;

    if (!rows.length) {
        body.innerHTML = '<tr><td colspan="22" class="text-center text-muted py-3"><small>No logs found for this automation.</small></td></tr>';
        return;
    }

    body.innerHTML = rows.map((r) => {
        const event = String(r?.event || '').toUpperCase();
        const dir = String(r?.direction || '').toUpperCase();
        const reason = String(r?.reason || '').trim() || '-';
        const m1Color = String(r?.m1_color || '').trim().toUpperCase() || '-';
        const m5Color = String(r?.m5_color || '').trim().toUpperCase() || '-';
        const m15Color = String(r?.m15_color || r?.color || '').trim().toUpperCase() || '-';
        const m5FlipAt = _automationLogsFormatTime(r?.m5_flip_at || r?.m5_bar_at);
        const mode = String(r?.mode || 'default').toUpperCase();
        const status = String(r?.status || '').trim().toLowerCase() || '-';
        const rsiVal = Number(r?.rsi);
        const priceVal = _automationLogsFormatPrice(r?.price);
        const m1DefR = _automationLogsFormatPnl(r?.m1_default_realized_pnl);
        const m1DefU = _automationLogsFormatPnl(r?.m1_default_unrealized_pnl);
        const m1AdvR = _automationLogsFormatPnl(r?.m1_advanced_realized_pnl);
        const m1AdvU = _automationLogsFormatPnl(r?.m1_advanced_unrealized_pnl);
        const m5DefR = _automationLogsFormatPnl(r?.m5_default_realized_pnl);
        const m5DefU = _automationLogsFormatPnl(r?.m5_default_unrealized_pnl);
        const m5AdvR = _automationLogsFormatPnl(r?.m5_advanced_realized_pnl);
        const m5AdvU = _automationLogsFormatPnl(r?.m5_advanced_unrealized_pnl);
        return `
            <tr>
                <td>${escapeHtml(_automationLogsFormatTime(r?.event_time))}</td>
                <td>${escapeHtml(_automationLogsFormatTime(r?.trade_created_at))}</td>
                <td>${Number(r?.trade_id || 0)}</td>
                <td>${escapeHtml(event)}</td>
                <td>${escapeHtml(dir)}</td>
                <td>${escapeHtml(reason)}</td>
                <td>${escapeHtml(m1Color)}</td>
                <td>${escapeHtml(m5Color)}</td>
                <td>${escapeHtml(m15Color)}</td>
                <td>${escapeHtml(priceVal)}</td>
                <td>${Number.isFinite(rsiVal) ? rsiVal.toFixed(2) : '-'}</td>
                <td>${escapeHtml(`${m1DefR}/${m1DefU}`)}</td>
                <td>${escapeHtml(`${m1AdvR}/${m1AdvU}`)}</td>
                <td>${escapeHtml(`${m5DefR}/${m5DefU}`)}</td>
                <td>${escapeHtml(`${m5AdvR}/${m5AdvU}`)}</td>
                <td>${escapeHtml(m5FlipAt)}</td>
                <td>${escapeHtml(mode)}</td>
                <td>${escapeHtml(_automationLogsFormatPrice(r?.entry_price))}</td>
                <td>${escapeHtml(_automationLogsFormatPrice(r?.exit_price))}</td>
                <td>${escapeHtml(_automationLogsFormatPnl(r?.pnl))}</td>
                <td>${escapeHtml(_automationLogsFormatR(r?.r_multiple))}</td>
                <td>${escapeHtml(status.toUpperCase())}</td>
            </tr>
        `;
    }).join('');
}

function _automationJobFromMonitorActionTarget(target) {
    const childSessionId = Number(target?.getAttribute?.('data-auto-child') || 0);
    const parentSessionId = Number(target?.getAttribute?.('data-auto-parent') || 0);
    const jobId = String(target?.getAttribute?.('data-auto-job') || '').trim();
    const strategy = String(target?.getAttribute?.('data-auto-strategy') || '').trim().toLowerCase();
    const symbol = String(target?.getAttribute?.('data-auto-symbol') || '').trim().toUpperCase();
    const timeframe = normalizeTimeframeLabel(target?.getAttribute?.('data-auto-timeframe') || 'M15', 'M15');
    const source = String(target?.getAttribute?.('data-auto-source') || 'mt5').trim().toLowerCase() || 'mt5';
    const deadzoneMode = _normalizeDeadzoneAutomationMode(target?.getAttribute?.('data-auto-deadzone-mode') || 'default');
    const fromCache = strategyAutomationJobs.find((j) => (
        (jobId && String(j?.job_id || '') === jobId)
        || (childSessionId > 0 && Number(j?.child_session_id || 0) === childSessionId)
    ));
    return {
        ...(fromCache && typeof fromCache === 'object' ? fromCache : {}),
        job_id: jobId || String(fromCache?.job_id || ''),
        parent_session_id: parentSessionId || Number(fromCache?.parent_session_id || 0),
        child_session_id: childSessionId || Number(fromCache?.child_session_id || 0),
        symbol: symbol || String(fromCache?.symbol || ''),
        strategy: strategy || String(fromCache?.strategy || ''),
        timeframe: timeframe || String(fromCache?.timeframe || 'M15'),
        source: source || String(fromCache?.source || 'mt5'),
        deadzone_mode: deadzoneMode || String(fromCache?.deadzone_mode || 'default'),
    };
}

async function openAutomationLogsModal(jobLike, opts = {}) {
    const showModal = opts?.showModal !== false;
    const parentSessionId = Number(jobLike?.parent_session_id || 0);
    const childSessionId = Number(jobLike?.child_session_id || 0);
    const jobId = String(jobLike?.job_id || '').trim();
    if (!(parentSessionId > 0) || (!(childSessionId > 0) && !jobId)) {
        showStatus('Automation logs unavailable: missing job context.', 'warning');
        return;
    }
    const titleEl = document.getElementById('automationLogsModalLabel');
    if (titleEl) {
        titleEl.innerHTML = `<i class="bi bi-journal-text me-1"></i>Automation Logs - ${escapeHtml(_formatAutomationStrategyLabel(jobLike))} ${escapeHtml(String(jobLike?.symbol || ''))} ${escapeHtml(String(jobLike?.timeframe || ''))}`;
    }
    const statusEl = document.getElementById('auto-logs-status');
    if (statusEl) statusEl.textContent = 'Loading...';
    automationLogsContext = { ...(jobLike && typeof jobLike === 'object' ? jobLike : {}) };
    automationLogsEvents = [];
    _renderAutomationLogsRows();
    if (showModal) {
        const modalEl = document.getElementById('automationLogsModal');
        if (modalEl && window.bootstrap && window.bootstrap.Modal) {
            window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
        }
    }
    const params = new URLSearchParams();
    if (childSessionId > 0) params.set('child_session_id', String(childSessionId));
    if (jobId) params.set('job_id', jobId);
    params.set('log_scope', _automationLogsScopeFilter());
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${parentSessionId}/agent/strategy-automation/logs?${params.toString()}`);
        const out = await res.json().catch(() => ({}));
        if (!res.ok || out?.ok === false) {
            const err = String(out?.error || out?.detail || `HTTP ${res.status}`);
            if (statusEl) statusEl.textContent = `Load failed: ${err}`;
            showStatus(`Automation logs load failed: ${err}`, 'warning');
            return;
        }
        automationLogsContext = {
            ...(automationLogsContext || {}),
            parent_session_id: Number(out?.parent_session_id || parentSessionId),
            child_session_id: Number(out?.child_session_id || childSessionId),
            job_id: String(out?.job_id || jobId),
            strategy: String(out?.strategy || jobLike?.strategy || ''),
            deadzone_mode: _normalizeDeadzoneAutomationMode(out?.deadzone_mode || jobLike?.deadzone_mode || 'default'),
            symbol: String(out?.symbol || jobLike?.symbol || ''),
            timeframe: String(out?.timeframe || jobLike?.timeframe || 'M15'),
            log_scope: String(out?.log_scope || _automationLogsScopeFilter()),
        };
        automationLogsEvents = Array.isArray(out?.events) ? out.events : [];
        _renderAutomationLogsRows();
    } catch (err) {
        if (statusEl) statusEl.textContent = `Load failed: ${String(err?.message || err)}`;
        showStatus(`Automation logs load failed: ${String(err?.message || err)}`, 'warning');
    }
}

async function refreshAutomationMonitorModal(showStatusToast = false) {
    const statusEl = document.getElementById('auto-monitor-status');
    if (statusEl) statusEl.textContent = 'Loading...';
    await loadStrategyAutomationJobs(false);
    _renderAutomationMonitorRows(strategyAutomationJobs);
    if (statusEl) statusEl.textContent = `Loaded ${strategyAutomationJobs.length} jobs`;
    if (showStatusToast) showStatus(`Automation monitor refreshed (${strategyAutomationJobs.length})`, 'info');
}

async function closeAutomationOpenTrade(opts = {}) {
    const childSessionId = Number(opts?.childSessionId || opts?.child_session_id || 0);
    const tradeId = Number(opts?.tradeId || opts?.trade_id || 0);
    if (!(childSessionId > 0) || !(tradeId > 0)) {
        showStatus('Close trade failed: invalid session/trade id.', 'warning');
        return;
    }
    const payload = {
        confirm_live_order: true,
        live_confirmation_phrase: LIVE_CONFIRMATION_PHRASE,
    };
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${childSessionId}/close-trade/${tradeId}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const out = await res.json().catch(() => ({}));
        if (!res.ok || out?.error || out?.ok === false) {
            const err = String(out?.error || out?.detail || `HTTP ${res.status}`);
            showStatus(`Close trade #${tradeId} failed: ${err}`, 'warning');
            return;
        }
        showStatus(`Closed trade #${tradeId} (automation session #${childSessionId}).`, 'success');
        await loadStrategyAutomationJobs(false);
        _renderStrategyAutomationJobsTable(strategyAutomationJobs);
        _renderAutomationMonitorRows(strategyAutomationJobs);
    } catch (err) {
        showStatus(`Close trade #${tradeId} failed: ${String(err?.message || err)}`, 'warning');
    }
}

function _automationChartSelectionForStrategy(strategyLike) {
    const strategy = String(strategyLike || '').trim().toLowerCase();
    const base = {
        smaEma: false,
        adx: false,
        rsi: false,
        stoch: false,
        bollinger: false,
        trendilo: false,
        advancedTrendilo: false,
        trendiloLsma: false,
        alphaWave: false,
        deadzonePro: false,
        orbSignal: false,
        trendiloBarColor: false,
        goldenCross: false,
    };
    if (strategy === 'trendilo') {
        base.trendilo = true;
        base.trendiloBarColor = true;
    } else if (strategy === 'advanced_trendilo') {
        base.advancedTrendilo = true;
        base.trendiloBarColor = true;
    } else if (strategy === 'trendilo_lsma') {
        base.trendiloLsma = true;
    } else if (strategy === 'alpha_wave') {
        base.alphaWave = true;
    } else if (strategy === 'deadzone_pro' || strategy === 'deadzone' || strategy === 'deadzonepro') {
        base.deadzonePro = true;
    } else if (strategy === 'orb') {
        base.orbSignal = true;
    } else if (strategy === 'orb_alpha_hybrid') {
        base.orbSignal = true;
        base.alphaWave = true;
    }
    return base;
}

function _automationChartLatestDir(dirArr) {
    if (!Array.isArray(dirArr) || dirArr.length === 0) return 0;
    for (let i = dirArr.length - 1; i >= 0; i -= 1) {
        const d = Number(dirArr[i] || 0);
        if (!Number.isFinite(d)) continue;
        if (d > 0) return 1;
        if (d < 0) return -1;
        return 0;
    }
    return 0;
}

function _automationChartSignalLabel(strategyLike, dir) {
    const strategy = String(strategyLike || '').trim().toLowerCase();
    const d = Number(dir || 0);
    if (strategy === 'alpha_wave') {
        if (d > 0) return 'GREEN (LONG)';
        if (d < 0) return 'PINK (SHORT)';
        return 'GRAY (WAIT)';
    }
    if (d > 0) return 'GREEN (LONG)';
    if (d < 0) return 'RED (SHORT)';
    return 'GRAY (WAIT)';
}

function _automationChartSetStatus(text, tone = 'info') {
    const el = document.getElementById('automation-chart-status');
    if (!el) return;
    const msg = String(text || '').trim() || 'Ready.';
    el.textContent = msg;
    const color = tone === 'warning'
        ? '#fca5a5'
        : (tone === 'success' ? '#86efac' : '#cbd5e1');
    el.style.color = color;
}

function _automationChartSetMeta(job, barsCount, signalLabel) {
    const el = document.getElementById('automation-chart-meta');
    if (!el) return;
    const symbol = String(job?.symbol || '').toUpperCase();
    const tf = normalizeTimeframeLabel(job?.timeframe || 'M15', 'M15');
    const strategy = String(job?.strategy || '').toLowerCase();
    const source = String(job?.source || 'mt5').toLowerCase();
    const child = Number(job?.child_session_id || 0);
    const jobId = String(job?.job_id || '').trim();
    const barsText = Number.isFinite(Number(barsCount)) ? `${Number(barsCount)} bars` : 'no bars';
    const signalText = String(signalLabel || 'n/a');
    el.textContent = `${symbol} ${tf} | ${strategy} | source=${source} | child=#${child} | ${barsText} | signal=${signalText} | job=${jobId}`;
}

function _automationChartSetPanelVisible(show) {
    const panelEl = document.getElementById('automation-chart-panel');
    if (!panelEl) return;
    panelEl.classList.toggle('d-none', !show);
}

function _automationChartEnsureMain() {
    const container = document.getElementById('automation-chart-main');
    if (!container || typeof LightweightCharts === 'undefined') return false;
    if (automationChartMain) return true;

    automationChartMain = LightweightCharts.createChart(container, {
        width: Math.max(320, container.clientWidth || 320),
        height: Math.max(240, container.clientHeight || 240),
        layout: {
            background: { type: 'solid', color: CHART_BG_COLOR },
            textColor: '#d1d4dc',
            fontSize: 12,
        },
        grid: {
            vertLines: { color: '#1e222d' },
            horzLines: { color: '#1e222d' },
        },
        crosshair: { mode: LightweightCharts.CrosshairMode.Normal },
        rightPriceScale: { borderColor: '#2a2e39', minimumWidth: CHART_RIGHT_SCALE_MIN_WIDTH },
        timeScale: {
            borderColor: '#2a2e39',
            timeVisible: true,
            secondsVisible: false,
            rightOffset: 8,
            rightBarStaysOnScroll: false,
            fixRightEdge: false,
            shiftVisibleRangeOnNewBar: false,
        },
    });
    automationChartCandles = automationChartMain.addCandlestickSeries({
        upColor: '#26a69a',
        downColor: '#ef5350',
        borderDownColor: '#ef5350',
        borderUpColor: '#26a69a',
        wickDownColor: '#ef5350',
        wickUpColor: '#26a69a',
    });
    automationChartVolume = automationChartMain.addHistogramSeries({
        color: '#385263',
        priceFormat: { type: 'volume' },
        priceScaleId: 'volume',
    });
    automationChartOverlay = automationChartMain.addLineSeries({
        color: '#cbd5e1',
        lineWidth: 2,
        lastValueVisible: false,
        priceLineVisible: false,
    });
    automationChartOverlaySecondary = automationChartMain.addLineSeries({
        color: '#9ca3af',
        lineWidth: 2,
        lineStyle: 2,
        lastValueVisible: false,
        priceLineVisible: false,
    });
    automationChartMain.priceScale('volume').applyOptions({
        scaleMargins: { top: 0.85, bottom: 0.0 },
    });

    if (automationChartResizeObserver) {
        try { automationChartResizeObserver.disconnect(); } catch (_) {}
    }
    automationChartResizeObserver = new ResizeObserver((entries) => {
        for (const entry of entries) {
            automationChartMain?.applyOptions({
                width: Math.max(320, entry.contentRect.width || 320),
                height: Math.max(240, entry.contentRect.height || 240),
            });
        }
    });
    automationChartResizeObserver.observe(container);
    return true;
}

function _automationChartEnsurePanel() {
    const panelEl = document.getElementById('automation-chart-panel');
    if (!panelEl || typeof LightweightCharts === 'undefined') return false;
    if (automationChartPanel) return true;

    automationChartPanel = LightweightCharts.createChart(panelEl, {
        width: Math.max(320, panelEl.clientWidth || 320),
        height: Math.max(120, panelEl.clientHeight || 140),
        layout: {
            background: { type: 'solid', color: CHART_BG_COLOR },
            textColor: '#d1d4dc',
            fontSize: 11,
        },
        grid: {
            vertLines: { color: '#1e222d' },
            horzLines: { color: '#1e222d' },
        },
        crosshair: { mode: LightweightCharts.CrosshairMode.Normal },
        rightPriceScale: { borderColor: '#2a2e39', minimumWidth: CHART_RIGHT_SCALE_MIN_WIDTH },
        timeScale: {
            borderColor: '#2a2e39',
            timeVisible: true,
            secondsVisible: false,
        },
    });
    automationChartPanelSeries.upper = automationChartPanel.addLineSeries({
        color: '#a855f7',
        lineWidth: 2,
        lastValueVisible: false,
        priceLineVisible: false,
    });
    automationChartPanelSeries.lower = automationChartPanel.addLineSeries({
        color: '#a855f7',
        lineWidth: 2,
        lastValueVisible: false,
        priceLineVisible: false,
    });
    automationChartPanelSeries.signal = automationChartPanel.addLineSeries({
        color: '#9ca3af',
        lineWidth: 3,
        lastValueVisible: false,
        priceLineVisible: false,
    });
    automationChartPanelSeries.zero = automationChartPanel.addLineSeries({
        color: '#6b7280',
        lineWidth: 1,
        lineStyle: 2,
        lastValueVisible: false,
        priceLineVisible: false,
    });

    if (automationChartResizeObserver && automationChartMain) {
        automationChartMain.timeScale().subscribeVisibleLogicalRangeChange((range) => {
            if (!automationChartPanel || automationChartSyncingRange) return;
            automationChartSyncingRange = true;
            try { automationChartPanel.timeScale().setVisibleLogicalRange(range); } catch (_) {}
            requestAnimationFrame(() => { automationChartSyncingRange = false; });
        });
        automationChartPanel.timeScale().subscribeVisibleLogicalRangeChange((range) => {
            if (!automationChartMain || automationChartSyncingRange) return;
            automationChartSyncingRange = true;
            try { automationChartMain.timeScale().setVisibleLogicalRange(range); } catch (_) {}
            requestAnimationFrame(() => { automationChartSyncingRange = false; });
        });
    }

    if (automationChartPanelResizeObserver) {
        try { automationChartPanelResizeObserver.disconnect(); } catch (_) {}
    }
    automationChartPanelResizeObserver = new ResizeObserver((entries) => {
        for (const entry of entries) {
            automationChartPanel?.applyOptions({
                width: Math.max(320, entry.contentRect.width || 320),
                height: Math.max(120, entry.contentRect.height || 120),
            });
        }
    });
    automationChartPanelResizeObserver.observe(panelEl);
    return true;
}

function _automationChartClearPanelData() {
    Object.values(automationChartPanelSeries || {}).forEach((series) => {
        try { series?.setData([]); } catch (_) {}
    });
}

function _automationChartApplyTrendiloBarColor(bars, dirArr) {
    if (!automationChartCandles) return;
    const out = (Array.isArray(bars) ? bars : []).map((b, i) => {
        const up = Number(b?.close || 0) >= Number(b?.open || 0);
        let color = up ? '#26a69a' : '#ef5350';
        const d = Number(Array.isArray(dirArr) ? (dirArr[i] || 0) : 0);
        if (d > 0) color = '#22c55e';
        else if (d < 0) color = '#ef4444';
        else color = '#9ca3af';
        return {
            time: Number(b?.time || 0),
            open: Number(b?.open || 0),
            high: Number(b?.high || 0),
            low: Number(b?.low || 0),
            close: Number(b?.close || 0),
            color,
            borderColor: color,
            wickColor: color,
        };
    });
    automationChartCandles.setData(out);
}

function _automationChartApplyDefaultCandles(bars) {
    if (!automationChartCandles) return;
    automationChartCandles.setData(Array.isArray(bars) ? bars : []);
}

async function openAutomationChartModal(jobLike, opts = {}) {
    const showModal = opts?.showModal !== false;
    const candidate = jobLike && typeof jobLike === 'object' ? jobLike : {};
    const strategy = String(candidate?.strategy || '').trim().toLowerCase();
    const symbol = String(candidate?.symbol || '').trim().toUpperCase();
    const timeframe = normalizeTimeframeLabel(candidate?.timeframe || 'M15', 'M15');
    const source = String(candidate?.source || 'mt5').trim().toLowerCase() || 'mt5';
    const childSessionId = Number(candidate?.child_session_id || 0);
    const jobId = String(candidate?.job_id || '').trim();
    if (!symbol || !strategy) {
        _automationChartSetStatus('Automation chart open failed: symbol/strategy missing.', 'warning');
        return;
    }
    automationChartJobContext = {
        ...candidate,
        strategy,
        symbol,
        timeframe,
        source,
        child_session_id: childSessionId,
        job_id: jobId,
    };

    const modalEl = document.getElementById('automationChartModal');
    if (showModal && modalEl && window.bootstrap && window.bootstrap.Modal) {
        window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
    }
    _automationChartSetStatus(`Loading ${symbol} ${timeframe} (${strategy})...`, 'info');
    _automationChartSetMeta(automationChartJobContext, null, 'LOADING');
    if (!_automationChartEnsureMain()) {
        _automationChartSetStatus('Automation chart unavailable: chart container missing.', 'warning');
        return;
    }

    const tfMin = Math.max(1, timeframeToMinutes(timeframe));
    const lookbackDays = Math.max(2, Math.min(120, Math.ceil((2200 * tfMin) / 1440)));
    let bars = [];
    let fetchError = null;
    try {
        bars = await fetchLiveHistoryBars(symbol, timeframe, source, lookbackDays);
    } catch (err) {
        fetchError = String(err?.message || err || 'history_fetch_failed');
    }
    if ((!Array.isArray(bars) || bars.length < 20) && source !== 'mt5') {
        try {
            bars = await fetchLiveHistoryBars(symbol, timeframe, 'mt5', lookbackDays);
            automationChartJobContext.source = 'mt5';
        } catch (_) {
            // keep prior error/path
        }
    }
    if ((!Array.isArray(bars) || bars.length < 20)) {
        const liveSymbol = String(document.getElementById('sim-symbol')?.value || '').trim().toUpperCase();
        const liveTf = normalizeTimeframeLabel(document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
        if (liveSymbol === symbol && liveTf === timeframe && Array.isArray(allBars) && allBars.length >= 20) {
            bars = allBars.slice(-5000);
        }
    }
    if (!Array.isArray(bars) || bars.length === 0) {
        _automationChartApplyDefaultCandles([]);
        automationChartVolume?.setData([]);
        automationChartOverlay?.setData([]);
        automationChartOverlaySecondary?.setData([]);
        _automationChartClearPanelData();
        _automationChartSetPanelVisible(false);
        _automationChartSetMeta(automationChartJobContext, 0, 'N/A');
        _automationChartSetStatus(
            `No bars for ${symbol} ${timeframe}${fetchError ? ` (${fetchError})` : ''}`,
            'warning',
        );
        return;
    }

    bars = bars
        .map((b) => ({
            time: Number(b?.time || 0),
            open: Number(b?.open || 0),
            high: Number(b?.high || 0),
            low: Number(b?.low || 0),
            close: Number(b?.close || 0),
            volume: Number(b?.volume || 0),
        }))
        .filter((b) => Number.isFinite(b.time) && b.time > 0 && Number.isFinite(b.open) && Number.isFinite(b.high) && Number.isFinite(b.low) && Number.isFinite(b.close))
        .sort((a, b) => Number(a.time || 0) - Number(b.time || 0));
    if (bars.length > 5000) bars = bars.slice(-5000);

    const selection = _automationChartSelectionForStrategy(strategy);
    const pack = computeIndicatorPack(bars, selection);
    const volumeData = bars.map((b) => ({
        time: b.time,
        value: Math.max(0, Number(b.volume || 0)),
        color: Number(b.close) >= Number(b.open) ? '#26a69a55' : '#ef535055',
    }));
    automationChartVolume?.setData(volumeData);

    let dirArr = [];
    if (strategy === 'trendilo') dirArr = pack.trendiloDir || [];
    else if (strategy === 'advanced_trendilo') dirArr = pack.advancedTrendiloDir || [];
    else if (strategy === 'trendilo_lsma') dirArr = pack.trendiloLsmaDir || [];
    else if (strategy === 'alpha_wave') dirArr = pack.alphaWaveDir || [];
    else if (strategy === 'deadzone_pro' || strategy === 'deadzone') dirArr = pack.deadzoneProDir || [];
    else if (strategy === 'orb') dirArr = pack.orbDir || [];
    else if (strategy === 'orb_alpha_hybrid') dirArr = pack.orbDir || [];

    if (strategy === 'trendilo' || strategy === 'advanced_trendilo') {
        _automationChartApplyTrendiloBarColor(bars, dirArr);
    } else {
        _automationChartApplyDefaultCandles(bars);
    }

    let overlayData = [];
    let secondaryOverlayData = [];
    if (strategy === 'trendilo_lsma') {
        const values = pack.trendiloLsmaCombine || [];
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const v = toFiniteNumber(values[i]);
            if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
            const d = Number(dirArr[i] || 0);
            overlayData.push({
                time: t,
                value: v,
                color: d > 0 ? '#00ff0a' : (d < 0 ? '#fe1807' : '#ffff00'),
            });
        }
    } else if (strategy === 'alpha_wave') {
        const values = pack.alphaWaveBaseline || [];
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const v = toFiniteNumber(values[i]);
            if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
            const d = Number(dirArr[i] || 0);
            overlayData.push({
                time: t,
                value: v,
                color: d > 0 ? '#01ffa7' : (d < 0 ? '#fb0bff' : '#9e9e9e'),
            });
        }
    } else if (strategy === 'deadzone_pro' || strategy === 'deadzone') {
        const values = pack.deadzoneProLine || [];
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const v = toFiniteNumber(values[i]);
            if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
            const d = Number(dirArr[i] || 0);
            overlayData.push({
                time: t,
                value: v,
                color: d > 0 ? '#4caf50' : (d < 0 ? '#ff5252' : '#9ca3af'),
            });
        }
    } else if (strategy === 'orb' || strategy === 'orb_alpha_hybrid') {
        const values = pack.orbSignal || [];
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const v = toFiniteNumber(values[i]);
            if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
            const d = Number(dirArr[i] || 0);
            overlayData.push({
                time: t,
                value: v,
                color: d > 0 ? '#22c55e' : (d < 0 ? '#ef4444' : '#9ca3af'),
            });
        }
        if (strategy === 'orb_alpha_hybrid') {
            const alphaValues = pack.alphaWaveBaseline || [];
            const alphaDirArr = pack.alphaWaveDir || [];
            for (let i = 0; i < bars.length; i += 1) {
                const t = Number(bars[i]?.time || 0);
                const v = toFiniteNumber(alphaValues[i]);
                if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
                const d = Number(alphaDirArr[i] || 0);
                secondaryOverlayData.push({
                    time: t,
                    value: v,
                    color: d > 0 ? '#01ffa7' : (d < 0 ? '#fb0bff' : '#9e9e9e'),
                });
            }
        }
    }
    automationChartOverlay?.setData(overlayData);
    automationChartOverlaySecondary?.setData(secondaryOverlayData);

    if (strategy === 'trendilo' || strategy === 'advanced_trendilo') {
        if (_automationChartEnsurePanel()) {
            _automationChartSetPanelVisible(true);
            const avpchArr = strategy === 'advanced_trendilo' ? (pack.advancedTrendiloAvpch || []) : (pack.trendiloAvpch || []);
            const rmsArr = strategy === 'advanced_trendilo' ? (pack.advancedTrendiloRms || []) : (pack.trendiloRms || []);
            const negRmsArr = strategy === 'advanced_trendilo' ? (pack.advancedTrendiloNegRms || []) : (pack.trendiloNegRms || []);
            const signalData = [];
            for (let i = 0; i < bars.length; i += 1) {
                const t = Number(bars[i]?.time || 0);
                const a = toFiniteNumber(avpchArr[i]);
                if (!Number.isFinite(t) || !Number.isFinite(a)) continue;
                const d = Number(dirArr[i] || 0);
                signalData.push({
                    time: t,
                    value: a,
                    color: d > 0 ? '#22c55e' : (d < 0 ? '#ef4444' : '#9ca3af'),
                });
            }
            const zeroLine = new Array(bars.length).fill(0);
            automationChartPanelSeries.upper?.setData(seriesDataFromArray(bars, rmsArr));
            automationChartPanelSeries.lower?.setData(seriesDataFromArray(bars, negRmsArr));
            automationChartPanelSeries.signal?.setData(signalData);
            automationChartPanelSeries.zero?.setData(seriesDataFromArray(bars, zeroLine));
            try { automationChartPanel.timeScale().fitContent(); } catch (_) {}
        } else {
            _automationChartSetPanelVisible(false);
        }
    } else {
        _automationChartClearPanelData();
        _automationChartSetPanelVisible(false);
    }

    const latestDir = _automationChartLatestDir(dirArr);
    const signalLabel = _automationChartSignalLabel(strategy, latestDir);
    _automationChartSetMeta(automationChartJobContext, bars.length, signalLabel);
    _automationChartSetStatus(`Loaded ${bars.length} bars | ${signalLabel}`, 'success');
    try { automationChartMain.timeScale().fitContent(); } catch (_) {}
}

async function startStrategyAutomationFromOpportunityRow(rowLike, opts = {}) {
    const row = rowLike && typeof rowLike === 'object' ? rowLike : {};
    const strategyRaw = String(row?.strategy || '').trim().toLowerCase();
    const strategy = _strategyAutomationResolveStartStrategy(strategyRaw);
    if (!_strategyAutomationSupportsStrategy(strategy)) {
        showStatus('Automation supports Trendilo, Advanced Trendilo, Trendilo LSMA, Alpha Wave, and ORB+Alpha hybrid modes.', 'warning');
        return;
    }
    if (!sessionId) {
        showStatus('Start a session first.', 'warning');
        return;
    }
    const symbol = String(row?.symbol || '').trim().toUpperCase();
    if (!symbol) {
        showStatus('Automation start failed: symbol missing.', 'warning');
        return;
    }
    const timeframe = normalizeTimeframeLabel(
        row?.schedule_trade_entry_args?.timeframe
            || row?.timeframe
            || lastStrategyOpportunityScanData?.execution_timeframe
            || lastStrategyOpportunityScanData?.timeframe
            || document.getElementById('trendilo-opp-exec-timeframe')?.value
            || document.getElementById('trendilo-opp-timeframe')?.value
            || 'M15',
        'M15',
    );
    const executionMode = String(
        document.getElementById('agent-live-execution-mode')?.value
        || sessionLiveControlState?.execution_mode
        || sessionLiveExecutionMode
        || 'paper',
    ).trim().toLowerCase() === 'live_mt5' ? 'live_mt5' : 'paper';
    const sourceRaw = String(lastStrategyOpportunityScanData?.source || document.getElementById('live-source')?.value || 'mt5').trim().toLowerCase() || 'mt5';
    const source = executionMode === 'live_mt5' ? 'mt5' : sourceRaw;
    const preset = String(document.getElementById('agent-strategy-preset')?.value || 'default').trim() || 'default';
    const riskOverride = Number.isFinite(Number(opts?.riskPercent)) ? Number(opts.riskPercent) : (Number.isFinite(Number(row?.risk_percent)) ? Number(row.risk_percent) : undefined);
    const rrOverride = Number.isFinite(Number(opts?.rrTarget)) ? Number(opts.rrTarget) : (Number.isFinite(Number(row?.rr)) ? Number(row.rr) : undefined);
    const payload = {
        symbol,
        strategy,
        timeframe,
        source,
        execution_mode: executionMode,
        preset,
        volume_sma_period: 20,
        force_first_entry: true,
        immediate_entry: true,
        risk_percent: riskOverride,
        rr_target: rrOverride,
        lot_size_override: Number.isFinite(Number(opts?.lotSizeOverride)) ? Number(opts.lotSizeOverride) : undefined,
    };
    if (strategy === 'deadzone_pro') {
        payload.deadzone_mode = _getAutoStartDeadzoneMode();
    }
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/strategy-automation/start`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const out = await res.json().catch(() => ({}));
        if (!res.ok || out?.ok === false) {
            const err = String(out?.error || out?.detail || `HTTP ${res.status}`);
            showStatus(`Automation start failed (${symbol}): ${err}`, 'warning');
            return;
        }
        await loadStrategyAutomationJobs(false);
        _renderStrategyAutomationJobsTable(strategyAutomationJobs);
        _renderAutomationMonitorRows(strategyAutomationJobs);
        _renderTrendiloOppRows(Array.isArray(lastStrategyOpportunityScanData?.opportunities) ? lastStrategyOpportunityScanData.opportunities : []);
        const immediate = out?.immediate_entry && typeof out.immediate_entry === 'object' ? out.immediate_entry : null;
        const immediateMsg = immediate
            ? ` | immediate_entry=${String(immediate.ok ? 'OPENED' : String(immediate.reason || 'no_open'))}`
            : '';
        showStatus(`Automation started: ${symbol} ${timeframe} ${strategy}${immediateMsg}`, 'success');
    } catch (err) {
        showStatus(`Automation start failed (${symbol}): ${String(err?.message || err)}`, 'warning');
    }
}

async function startStrategyAutomationFromManualModal() {
    const statusEl = document.getElementById('auto-start-status');
    if (!sessionId) {
        if (statusEl) statusEl.textContent = 'Start/select a session first.';
        showStatus('Start/select a session first.', 'warning');
        return;
    }
    const strategy = String(document.getElementById('auto-start-strategy')?.value || 'trendilo').trim().toLowerCase();
    if (!_strategyAutomationSupportsStrategy(strategy)) {
        if (statusEl) statusEl.textContent = 'Unsupported strategy for automation.';
        showStatus('Unsupported strategy for automation.', 'warning');
        return;
    }
    const symbol = String(document.getElementById('auto-start-symbol')?.value || document.getElementById('sim-symbol')?.value || '').trim().toUpperCase();
    if (!symbol) {
        if (statusEl) statusEl.textContent = 'Symbol is required.';
        showStatus('Symbol is required.', 'warning');
        return;
    }
    const timeframe = normalizeTimeframeLabel(
        document.getElementById('auto-start-timeframe')?.value || document.getElementById('sim-timeframe')?.value || 'M15',
        'M15',
    );
    const executionMode = String(
        document.getElementById('agent-live-execution-mode')?.value
        || sessionLiveControlState?.execution_mode
        || sessionLiveExecutionMode
        || 'paper',
    ).trim().toLowerCase() === 'live_mt5' ? 'live_mt5' : 'paper';
    const sourceRaw = String(document.getElementById('auto-start-source')?.value || document.getElementById('live-source')?.value || 'mt5').trim().toLowerCase() || 'mt5';
    const source = executionMode === 'live_mt5' ? 'mt5' : sourceRaw;
    const riskRaw = Number(document.getElementById('auto-start-risk')?.value);
    const rrRaw = Number(document.getElementById('auto-start-rr')?.value);
    const lotRaw = Number(document.getElementById('auto-start-lot')?.value);
    const riskPercent = Number.isFinite(riskRaw) ? Math.max(0.05, Math.min(25.0, riskRaw)) : 0.75;
    const rrTarget = Number.isFinite(rrRaw) ? Math.max(1.0, Math.min(12.0, rrRaw)) : 2.0;
    const lotOverride = Number.isFinite(lotRaw) ? Math.max(0.001, Math.min(200.0, lotRaw)) : null;
    const preset = String(document.getElementById('agent-strategy-preset')?.value || 'default').trim() || 'default';
    const payload = {
        symbol,
        strategy,
        timeframe,
        source,
        execution_mode: executionMode,
        preset,
        volume_sma_period: 20,
        force_first_entry: true,
        immediate_entry: true,
        risk_percent: riskPercent,
        rr_target: rrTarget,
        lot_size_override: lotOverride,
    };
    if (strategy === 'deadzone_pro') {
        payload.deadzone_mode = _getAutoStartDeadzoneMode();
    }
    if (statusEl) statusEl.textContent = `Starting ${strategy} automation on ${symbol} ${timeframe}...`;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/strategy-automation/start`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const out = await res.json().catch(() => ({}));
        if (!res.ok || out?.ok === false) {
            const err = String(out?.error || out?.detail || `HTTP ${res.status}`);
            if (statusEl) statusEl.textContent = `Failed: ${err}`;
            showStatus(`Automation start failed (${symbol}): ${err}`, 'warning');
            return;
        }
        await loadStrategyAutomationJobs(false);
        _renderStrategyAutomationJobsTable(strategyAutomationJobs);
        _renderAutomationMonitorRows(strategyAutomationJobs);
        const immediate = out?.immediate_entry && typeof out.immediate_entry === 'object' ? out.immediate_entry : null;
        const immediateTxt = immediate ? ` | immediate=${String(immediate.ok ? 'OPENED' : (immediate.reason || 'no_open'))}` : '';
        if (statusEl) statusEl.textContent = `Started ${strategy} ${symbol} ${timeframe}${immediateTxt}`;
        showStatus(`Automation started: ${symbol} ${timeframe} ${strategy}${immediateTxt}`, 'success');
        const modalEl = document.getElementById('automationStarterModal');
        if (modalEl && window.bootstrap && window.bootstrap.Modal) {
            const modal = window.bootstrap.Modal.getInstance(modalEl);
            if (modal) modal.hide();
        }
    } catch (err) {
        const msg = String(err?.message || err || 'request_failed');
        if (statusEl) statusEl.textContent = `Failed: ${msg}`;
        showStatus(`Automation start failed (${symbol}): ${msg}`, 'warning');
    }
}

async function stopStrategyAutomationJob(opts = {}) {
    const childSessionId = Number(opts?.childSessionId || opts?.child_session_id || 0);
    let parentSessionId = Number(opts?.parentSessionId || opts?.parent_session_id || 0);
    const jobId = String(opts?.jobId || opts?.job_id || '').trim();
    if (!childSessionId && !jobId) {
        showStatus('Automation stop failed: missing job id.', 'warning');
        return;
    }
    if (!(parentSessionId > 0)) {
        const found = strategyAutomationJobs.find((j) => (
            (childSessionId > 0 && Number(j?.child_session_id || 0) === childSessionId)
            || (jobId && String(j?.job_id || '') === jobId)
        ));
        parentSessionId = Number(found?.parent_session_id || 0);
    }
    if (!(parentSessionId > 0) && sessionId) {
        parentSessionId = Number(sessionId);
    }
    if (!(parentSessionId > 0)) {
        showStatus('Automation stop failed: parent session not found.', 'warning');
        return;
    }
    const payload = {};
    if (childSessionId > 0) payload.child_session_id = childSessionId;
    if (jobId) payload.job_id = jobId;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${parentSessionId}/agent/strategy-automation/stop`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const out = await res.json().catch(() => ({}));
        if (!res.ok || out?.ok === false) {
            const err = String(out?.error || out?.detail || `HTTP ${res.status}`);
            showStatus(`Automation stop failed: ${err}`, 'warning');
            return;
        }
        await loadStrategyAutomationJobs(false);
        _renderStrategyAutomationJobsTable(strategyAutomationJobs);
        _renderAutomationMonitorRows(strategyAutomationJobs);
        _renderTrendiloOppRows(Array.isArray(lastStrategyOpportunityScanData?.opportunities) ? lastStrategyOpportunityScanData.opportunities : []);
        showStatus('Automation stopped.', 'info');
    } catch (err) {
        showStatus(`Automation stop failed: ${String(err?.message || err)}`, 'warning');
    }
}

function _renderTrendiloOppRows(rows) {
    const body = document.getElementById('trendilo-opp-body');
    const head = document.getElementById('trendilo-opp-head');
    if (!body || !head) return;
    const list = Array.isArray(rows) ? rows : [];
    if (!list.length) {
        head.innerHTML = '';
        body.innerHTML = '<tr><td class="text-center text-muted py-3"><small>No tradeable opportunities found.</small></td></tr>';
        return;
    }
    head.innerHTML = `
        <tr>
            <th>Rank</th>
            <th>Strategy</th>
            <th>Symbol</th>
            <th>State</th>
            <th>Dir</th>
            <th>Entry</th>
            <th>SL</th>
            <th>TP</th>
            <th>RR</th>
            <th>Lot</th>
            <th>Score</th>
            <th>Conf</th>
            <th>Risk%</th>
            <th>RR</th>
            <th>Action</th>
        </tr>
    `;
    body.innerHTML = list.map((r, idx) => `
        <tr>
            <td>${Number(r?.rank || 0)}</td>
            <td>${escapeHtml(String(r?.strategy || ''))}</td>
            <td>${escapeHtml(String(r?.symbol || ''))}</td>
            <td>${escapeHtml(String(r?.opportunity_state || (r?.watch_only ? 'watch_only' : (r?.executable_now ? 'ready' : 'blocked'))).toUpperCase())}</td>
            <td>${escapeHtml(String(r?.direction || ''))}</td>
            <td>${Number(r?.entry_ref || 0).toFixed(3)}</td>
            <td>${Number(r?.stop_loss || 0).toFixed(3)}</td>
            <td>${Number(r?.take_profit || 0).toFixed(3)}</td>
            <td>${Number(r?.rr || 0).toFixed(2)}</td>
            <td>${Number(r?.lot_size || 0).toFixed(2)}</td>
            <td>${(() => {
                const v = Number(r?.rank_score);
                return Number.isFinite(v) ? v.toFixed(1) : '0.0';
            })()}</td>
            <td>${(() => {
                const raw = Number(r?.confidence);
                if (!Number.isFinite(raw)) return '0.0';
                const normalized = (raw > 0 && raw <= 1) ? (raw * 100) : raw;
                return Number(normalized).toFixed(1);
            })()}</td>
            <td><input id="auto-risk-${idx}" type="number" class="form-control form-control-sm" style="min-width:72px" step="0.05" min="0.1" max="5" value="${Number.isFinite(Number(r?.risk_percent)) ? Number(r.risk_percent).toFixed(2) : '0.75'}"></td>
            <td><input id="auto-rr-${idx}" type="number" class="form-control form-control-sm" style="min-width:68px" step="0.1" min="1" max="12" value="${Number.isFinite(Number(r?.rr)) ? Number(r.rr).toFixed(2) : '2.00'}"></td>
            <td>${(() => {
                const strategyRaw = String(r?.strategy || '').trim().toLowerCase();
                const strategy = _strategyAutomationResolveStartStrategy(strategyRaw);
                if (!_strategyAutomationSupportsStrategy(strategy)) {
                    return '<span class="text-muted">-</span>';
                }
                const job = _findAutomationJobForOpportunity(r);
                if (job && job.enabled) {
                    return `<button type="button" class="btn btn-sm btn-outline-danger" data-auto-action="stop-row" data-auto-parent="${Number(job?.parent_session_id || 0)}" data-auto-child="${Number(job?.child_session_id || 0)}" data-auto-job="${escapeHtml(String(job?.job_id || ''))}">Stop Auto</button>`;
                }
                return `<button type="button" class="btn btn-sm btn-outline-success" data-auto-action="start-row" data-auto-symbol="${escapeHtml(String(r?.symbol || ''))}" data-auto-strategy="${escapeHtml(strategy)}" data-auto-row="${idx}">Start Auto</button>`;
            })()}</td>
        </tr>
    `).join('');
}

function _renderTrendiloOppResult(data, fromCache = false) {
    const summaryEl = document.getElementById('trendilo-opp-summary');
    if (!summaryEl) return;
    if (!data || typeof data !== 'object') {
        summaryEl.textContent = 'No scan data.';
        _renderTrendiloOppRows([]);
        return;
    }
    const scanned = Number(data.symbols_scanned || 0);
    const okCount = Number(data.ok_count || 0);
    const errCount = Number(data.error_count || 0);
    const tradeableCountShown = Number(data.tradeable_count || 0);
    const tradeableTotalCount = Number(data.tradeable_total_count || tradeableCountShown);
    const readyCount = Number(data.ready_count || 0);
    const watchOnlyCount = Number(data.watch_only_count || 0);
    const scanTf = String(data.timeframe || data.scan_timeframe || '');
    const execTf = String(data.execution_timeframe || data.exec_timeframe || scanTf || '');
    const strategy = String(data.strategy || '').trim().toLowerCase() || 'trendilo';
    const src = String(data.source || '');
    const elapsed = Number(data.elapsed_ms || 0);
    const prefix = fromCache ? '[CACHED] ' : '';
    summaryEl.textContent = `${prefix}Strategy=${strategy} | Scanned ${scanned} symbols (${okCount} ok, ${errCount} error). Tradeable shown/total: ${tradeableCountShown}/${tradeableTotalCount} (ready: ${readyCount}, watch-only: ${watchOnlyCount}). Ranked best→worst by score. ScanTF=${scanTf} ExecTF=${execTf} Source=${src} Elapsed=${elapsed}ms.`;
    lastStrategyOpportunityScanData = { ...(data || {}) };
    _renderTrendiloOppRows(Array.isArray(data.opportunities) ? data.opportunities : []);
}

async function runTrendiloOpportunityScreener() {
    const btn = document.getElementById('btn-run-trendilo-opps');
    const statusEl = document.getElementById('trendilo-opp-status');
    const args = _collectTrendiloOppScanArgs();
    try {
        if (!sessionId) {
            const bootSymbol = String(document.getElementById('sim-symbol')?.value || 'XAUUSD').trim().toUpperCase() || 'XAUUSD';
            const bootTf = normalizeTimeframeLabel(
                document.getElementById('sim-timeframe')?.value || args.execution_timeframe || args.timeframe || 'M15',
                'M15',
            );
            const bootSource = String(args.source || 'mt5').trim().toLowerCase() || 'mt5';
            if (statusEl) statusEl.textContent = `No active session. Initializing ${bootSource.toUpperCase()} session...`;
            const ready = await ensureSessionForLive(bootSymbol, bootTf, bootSource);
            if (!ready || !sessionId) {
                if (statusEl) statusEl.textContent = 'Failed: unable to initialize session context for screener';
                showStatus('Strategy screener failed: unable to initialize session context', 'warning');
                return;
            }
        }
        if (btn) {
            btn.disabled = true;
            btn.innerHTML = '<i class="bi bi-hourglass-split me-1"></i>Running...';
        }
        if (statusEl) statusEl.textContent = 'Running deterministic screener...';
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/strategy-opportunities`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(args),
        });
        const out = await res.json().catch(() => ({}));
        if (!res.ok || out?.ok === false || !out?.data || typeof out.data !== 'object') {
            const err = String(out?.error || out?.detail || `HTTP ${res.status}`);
            if (statusEl) statusEl.textContent = `Failed: ${err}`;
            showStatus(`Strategy screener failed: ${err}`, 'warning');
            return;
        }
        // Keep both scan/execution timeframe explicit in cached payloads for UI consistency.
        out.data.timeframe = String(out.data?.timeframe || args?.timeframe || '');
        out.data.execution_timeframe = String(out.data?.execution_timeframe || args?.execution_timeframe || out.data?.timeframe || '');
        _saveTrendiloOppScanCache(out.data);
        _renderTrendiloOppResult(out.data, false);
        await loadStrategyAutomationJobs(false);
        const shown = Number(out.data?.tradeable_count || 0);
        const total = Number(out.data?.tradeable_total_count || shown);
        if (statusEl) statusEl.textContent = `Completed: ${shown}/${total} opportunities (shown/total)`;
        showStatus(`Strategy screener complete: ${shown}/${total} tradeable setup(s) shown/total`, 'success');
    } catch (err) {
        const msg = String(err?.message || err || 'Unknown error');
        if (statusEl) statusEl.textContent = `Failed: ${msg}`;
        showStatus(`Strategy screener failed: ${msg}`, 'warning');
    } finally {
        if (btn) {
            btn.disabled = false;
            btn.innerHTML = '<i class="bi bi-play-fill me-1"></i>Run Screener';
        }
    }
}

function loadTrendiloOpportunityScreenerCache() {
    const statusEl = document.getElementById('trendilo-opp-status');
    const cached = _loadTrendiloOppScanCache(TRENDILO_OPP_CACHE_MAX_AGE_MIN);
    if (!cached || !cached.data) {
        if (statusEl) statusEl.textContent = 'No fresh cache found.';
        _renderTrendiloOppResult(null, true);
        return;
    }
    _renderTrendiloOppResult(cached.data, true);
    if (statusEl) statusEl.textContent = `Loaded cache from ${String(cached.saved_at || '').replace('T', ' ').replace('Z', ' UTC')}`;
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
    const fullSel = { smaEma: true, adx: true, rsi: true, stoch: true, bollinger: true, trendilo: true, deadzonePro: true, goldenCross: true };
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
        trendilo_avpch: _latestFinite(pack?.trendiloAvpch),
        trendilo_rms: _latestFinite(pack?.trendiloRms),
        deadzone_line: _latestFinite(pack?.deadzoneProLine),
        deadzone_dir: _latestFinite(pack?.deadzoneProDir),
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
    const fullSel = { smaEma: true, adx: true, rsi: true, stoch: true, bollinger: true, trendilo: true, deadzonePro: true, goldenCross: true };
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
        trendilo_avpch: _latestFinite(pack.trendiloAvpch),
        trendilo_rms: _latestFinite(pack.trendiloRms),
        deadzone_line: _latestFinite(pack.deadzoneProLine),
        deadzone_dir: _latestFinite(pack.deadzoneProDir),
    } : {};

    const sessionStats = {
        initial_balance: Number(initialBalance || 0),
        current_balance: Number(String(document.getElementById('stat-balance')?.textContent || '').replace(/[^0-9+-.]/g, '')) || null,
        total_pnl: Number(String(document.getElementById('stat-pnl')?.textContent || '').replace(/[^0-9+-.]/g, '')) || null,
        trades_count: Number(String(document.getElementById('stat-trades')?.textContent || '').replace(/[^0-9+-.]/g, '')) || null,
        wins: null,
        losses: null,
    };
    const trendiloOppCache = _compactTrendiloOppCacheForContext(10);

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
        trendilo_opportunity_scan: trendiloOppCache,
        strategy_opportunity_scan: trendiloOppCache,
        metadata: {
            mode,
            transport_mode: String(transportMode || 'IDLE'),
            trendilo_opportunity_cache_available: !!trendiloOppCache,
            strategy_opportunity_cache_available: !!trendiloOppCache,
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
    const strategyToolAccessEl = document.getElementById('agent-strategy-tool-access');
    const toolSelectionModeEl = document.getElementById('agent-tool-selection-mode');
    const strategyProfileEl = document.getElementById('agent-strategy-profile');
    const strategyPresetEl = document.getElementById('agent-strategy-preset');
    const intervalEl = document.getElementById('agent-watchdog-interval');
    const llmIntervalEl = document.getElementById('agent-watchdog-llm-interval');
    const triggerApprovalEl = document.getElementById('agent-watchdog-trigger-require-approval');
    const guardrailEnabledEl = document.getElementById('agent-guardrail-enabled');
    const sessionFilterEl = document.getElementById('agent-guardrail-session-filter');
    const newsFilterEl = document.getElementById('agent-guardrail-news-filter');
    const guardrailMaxRiskEl = document.getElementById('agent-guardrail-max-risk-per-trade');
    const newsLookbackEl = document.getElementById('agent-guardrail-news-lookback');
    const newsProviderEl = document.getElementById('agent-news-provider');
    const newsLlmSummaryEl = document.getElementById('agent-news-llm-summary');
    const newsSummaryModelEl = document.getElementById('agent-news-summary-model');
    const newsIbkrHostEl = document.getElementById('agent-news-ibkr-host');
    const newsIbkrPortEl = document.getElementById('agent-news-ibkr-port');
    const liqGateModeEl = document.getElementById('agent-liq-gate-mode');
    const liqSweepFreshHoursEl = document.getElementById('agent-liq-sweep-fresh-hours');
    const liqSweepMinBarsEl = document.getElementById('agent-liq-sweep-min-bars');
    const liqSweepDistGoldEl = document.getElementById('agent-liq-sweep-dist-gold');
    const liqSweepDistIndicesEl = document.getElementById('agent-liq-sweep-dist-indices');
    const liqSweepDistFxEl = document.getElementById('agent-liq-sweep-dist-fx');
    const liqSweepDistDefaultEl = document.getElementById('agent-liq-sweep-dist-default');
    const modeRaw = String(modeEl?.value || 'deterministic').trim().toLowerCase();
    const mode = ['deterministic', 'local_gptoss_http', 'claude'].includes(modeRaw) ? modeRaw : 'deterministic';
    const strategyToolAccessRaw = String(strategyToolAccessEl?.value || 'all').trim().toLowerCase();
    const strategyToolAccess = ['all', 'parent', 'child'].includes(strategyToolAccessRaw) ? strategyToolAccessRaw : 'all';
    const toolSelectionRaw = String(toolSelectionModeEl?.value || 'autonomous').trim().toLowerCase();
    const toolSelectionMode = ['autonomous', 'guided', 'minimal'].includes(toolSelectionRaw) ? toolSelectionRaw : 'autonomous';
    const strategyProfileRaw = String(strategyProfileEl?.value || 'classic_htf_fvg').trim().toLowerCase();
    const strategyProfile = ['classic_htf_fvg', 'htf_fvg_liquidity_reclaim_v2', 'orb_ny_15m_imbalance', 'trendilo_confirmation_v1', 'advanced_trendilo_confirmation_v1', 'trendilo_lsma_confirmation_v1', 'alpha_wave_confirmation_v1'].includes(strategyProfileRaw) ? strategyProfileRaw : 'classic_htf_fvg';
    const strategyPresetRaw = String(strategyPresetEl?.value || 'default').trim().toLowerCase();
    const strategyPreset = ['default', 'conservative', 'aggressive', 'xauusd_m15', 'nas100_m15', 'xauusd_m1', 'nas100_m1', 'us500_m1'].includes(strategyPresetRaw) ? strategyPresetRaw : 'default';
    const intervalRaw = Number(intervalEl?.value || 30);
    const intervalSec = Number.isFinite(intervalRaw) ? Math.max(5, Math.min(300, Math.round(intervalRaw))) : 30;
    const llmIntervalRaw = Number(llmIntervalEl?.value || 180);
    const llmMinIntervalSec = Number.isFinite(llmIntervalRaw) ? Math.max(10, Math.min(3600, Math.round(llmIntervalRaw))) : 180;
    const newsLookbackRaw = Number(newsLookbackEl?.value || 120);
    const newsLookbackMin = Number.isFinite(newsLookbackRaw) ? Math.max(15, Math.min(1440, Math.round(newsLookbackRaw))) : 120;
    const guardrailMaxRiskRaw = Number(guardrailMaxRiskEl?.value || 0);
    const guardrailMaxRiskPerTradeUsd = Number.isFinite(guardrailMaxRiskRaw)
        ? Math.max(0, Math.min(1_000_000_000, guardrailMaxRiskRaw))
        : 0;
    const newsProviderRaw = String(newsProviderEl?.value || 'polygon').trim().toLowerCase();
    const newsProvider = ['polygon', 'ibkr'].includes(newsProviderRaw) ? newsProviderRaw : 'polygon';
    const newsSummaryModel = String(newsSummaryModelEl?.value || '').trim() || 'claude-haiku-4-5-20251001';
    const newsIbkrHost = String(newsIbkrHostEl?.value || '').trim() || '127.0.0.1';
    const newsIbkrPortRaw = Number(newsIbkrPortEl?.value || 7497);
    const newsIbkrPort = Number.isFinite(newsIbkrPortRaw) ? Math.max(1, Math.min(65535, Math.round(newsIbkrPortRaw))) : 7497;
    const liqGateModeRaw = String(liqGateModeEl?.value || 'hybrid').trim().toLowerCase();
    const liqGateMode = ['hybrid', 'strict', 'assist'].includes(liqGateModeRaw) ? liqGateModeRaw : 'hybrid';
    const liqSweepFreshHoursRaw = Number(liqSweepFreshHoursEl?.value || 4);
    const liqSweepFreshHours = Number.isFinite(liqSweepFreshHoursRaw) ? Math.max(0.5, Math.min(24, liqSweepFreshHoursRaw)) : 4;
    const liqSweepMinBarsRaw = Number(liqSweepMinBarsEl?.value || 4);
    const liqSweepMinBars = Number.isFinite(liqSweepMinBarsRaw) ? Math.max(1, Math.min(200, Math.round(liqSweepMinBarsRaw))) : 4;
    const liqSweepDistGoldRaw = Number(liqSweepDistGoldEl?.value || 0.5);
    const liqSweepDistGold = Number.isFinite(liqSweepDistGoldRaw) ? Math.max(0.05, Math.min(3, liqSweepDistGoldRaw)) : 0.5;
    const liqSweepDistIndicesRaw = Number(liqSweepDistIndicesEl?.value || 0.3);
    const liqSweepDistIndices = Number.isFinite(liqSweepDistIndicesRaw) ? Math.max(0.05, Math.min(3, liqSweepDistIndicesRaw)) : 0.3;
    const liqSweepDistFxRaw = Number(liqSweepDistFxEl?.value || 0.25);
    const liqSweepDistFx = Number.isFinite(liqSweepDistFxRaw) ? Math.max(0.05, Math.min(3, liqSweepDistFxRaw)) : 0.25;
    const liqSweepDistDefaultRaw = Number(liqSweepDistDefaultEl?.value || 0.3);
    const liqSweepDistDefault = Number.isFinite(liqSweepDistDefaultRaw) ? Math.max(0.05, Math.min(3, liqSweepDistDefaultRaw)) : 0.3;
    const out = {
        watchdog_mode: mode,
        tool_selection_mode: toolSelectionMode,
        strategy_tool_access_mode: strategyToolAccess,
        agent_strategy_profile: strategyProfile,
        agent_strategy_preset: strategyPreset,
        mtf_liquidity_gate_mode: liqGateMode,
        mtf_liquidity_sweep_freshness_hours: liqSweepFreshHours,
        mtf_liquidity_sweep_freshness_min_bars: liqSweepMinBars,
        mtf_liquidity_sweep_distance_atr_gold: liqSweepDistGold,
        mtf_liquidity_sweep_distance_atr_indices: liqSweepDistIndices,
        mtf_liquidity_sweep_distance_atr_fx: liqSweepDistFx,
        mtf_liquidity_sweep_distance_atr_default: liqSweepDistDefault,
        watchdog_interval_sec: intervalSec,
        watchdog_llm_min_interval_sec: llmMinIntervalSec,
        watchdog_trigger_requires_approval: Boolean(triggerApprovalEl?.checked),
        guardrail_enabled: Boolean(guardrailEnabledEl?.checked),
        guardrail_session_filter_enabled: Boolean(sessionFilterEl?.checked),
        guardrail_news_filter_enabled: Boolean(newsFilterEl?.checked),
        guardrail_max_risk_per_trade_usd: guardrailMaxRiskPerTradeUsd,
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
    const maxRiskEl = document.getElementById('agent-guardrail-max-risk-per-trade');
    const newsLookbackEl = document.getElementById('agent-guardrail-news-lookback');
    const statusEl = document.getElementById('agent-guardrail-effective-status');
    const guardrailsEnabled = !!guardrailEnabledEl?.checked;
    const sessionEnabled = !!sessionFilterEl?.checked;
    const newsEnabled = !!newsFilterEl?.checked;
    if (sessionFilterEl) sessionFilterEl.disabled = !guardrailsEnabled;
    if (newsFilterEl) newsFilterEl.disabled = !guardrailsEnabled;
    if (maxRiskEl) maxRiskEl.disabled = !guardrailsEnabled;
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

function syncAgentStrategyControls() {
    const profileEl = document.getElementById('agent-strategy-profile');
    const presetEl = document.getElementById('agent-strategy-preset');
    if (!profileEl || !presetEl) return;
    const profile = String(profileEl.value || 'classic_htf_fvg').trim().toLowerCase();
    const isLiquidityProfile = profile === 'htf_fvg_liquidity_reclaim_v2';
    const isOrbProfile = profile === 'orb_ny_15m_imbalance';
    const isTrendiloProfile = profile === 'trendilo_confirmation_v1';
    const isAdvancedTrendiloProfile = profile === 'advanced_trendilo_confirmation_v1';
    const isTrendiloLsmaProfile = profile === 'trendilo_lsma_confirmation_v1';
    const isAlphaWaveProfile = profile === 'alpha_wave_confirmation_v1';
    presetEl.disabled = !(isLiquidityProfile || isOrbProfile || isTrendiloProfile || isAdvancedTrendiloProfile || isTrendiloLsmaProfile || isAlphaWaveProfile);
    const hintEl = presetEl.parentElement?.querySelector('.agent-field-hint');
    if (hintEl) {
        if (isLiquidityProfile) {
            hintEl.textContent = 'Used by the liquidity-reclaim strategy profile. Classic HTF FVG ignores this.';
        } else if (isOrbProfile) {
            hintEl.textContent = 'Used by NY 15m ORB profile (default/xauusd_m1/nas100_m1/us500_m1).';
        } else if (isTrendiloProfile) {
            hintEl.textContent = 'Used by Trendilo strategy profile (default/conservative/aggressive/xauusd_m15/nas100_m15/us500_m15).';
        } else if (isAdvancedTrendiloProfile) {
            hintEl.textContent = 'Used by Advanced Trendilo profile (anti-whipsaw: persistence/edge/ADX-rising/DI-spread filters).';
        } else if (isTrendiloLsmaProfile) {
            hintEl.textContent = 'Used by Trendilo LSMA profile (Pine-parity LSMA/HMA combine direction).';
        } else if (isAlphaWaveProfile) {
            hintEl.textContent = 'Used by Alpha Wave profile (Pine-parity DaviddTech baseline/wave/quantum/momentum state machine).';
        } else {
            hintEl.textContent = 'Classic HTF FVG is selected, so this preset is currently ignored.';
        }
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

function rollingALMA(values, length, offset, sigma) {
    const out = new Array(values.length).fill(NaN);
    if (!Array.isArray(values) || values.length === 0) return out;
    const ln = Math.max(2, Number(length) || 2);
    const off = Math.max(0, Math.min(1, Number(offset)));
    const sig = Math.max(0.1, Number(sigma) || 6);
    const m = off * (ln - 1);
    const s = ln / sig;
    const w = new Array(ln).fill(0);
    let wsum = 0;
    for (let i = 0; i < ln; i += 1) {
        const wi = Math.exp(-((i - m) ** 2) / (2 * (s ** 2)));
        w[i] = wi;
        wsum += wi;
    }
    if (!Number.isFinite(wsum) || wsum <= 1e-12) return out;
    for (let i = 0; i < ln; i += 1) w[i] /= wsum;
    for (let i = ln - 1; i < values.length; i += 1) {
        let acc = 0;
        let valid = true;
        for (let j = 0; j < ln; j += 1) {
            const v = toFiniteNumber(values[i - ln + 1 + j]);
            if (!Number.isFinite(v)) {
                valid = false;
                break;
            }
            acc += v * w[j];
        }
        if (valid) out[i] = acc;
    }
    return out;
}

function rollingRms(values, period) {
    const out = new Array(values.length).fill(NaN);
    if (!Array.isArray(values) || values.length === 0) return out;
    const p = Math.max(1, Number(period) || 1);
    for (let i = p - 1; i < values.length; i += 1) {
        let sumSq = 0;
        let valid = true;
        for (let j = i - p + 1; j <= i; j += 1) {
            const v = toFiniteNumber(values[j]);
            if (!Number.isFinite(v)) {
                valid = false;
                break;
            }
            sumSq += v * v;
        }
        if (valid) out[i] = Math.sqrt(sumSq / p);
    }
    return out;
}

function rollingWMA(values, period) {
    const out = new Array(values.length).fill(NaN);
    if (!Array.isArray(values) || values.length === 0) return out;
    const p = Math.max(1, Number(period) || 1);
    const weights = Array.from({ length: p }, (_, i) => i + 1);
    const weightSum = weights.reduce((acc, n) => acc + n, 0);
    for (let i = p - 1; i < values.length; i += 1) {
        let acc = 0;
        let valid = true;
        for (let j = 0; j < p; j += 1) {
            const v = toFiniteNumber(values[i - p + 1 + j]);
            if (!Number.isFinite(v)) {
                valid = false;
                break;
            }
            acc += v * weights[j];
        }
        if (valid) out[i] = acc / weightSum;
    }
    return out;
}

function rollingLinReg(values, period, offset) {
    const out = new Array(values.length).fill(NaN);
    if (!Array.isArray(values) || values.length === 0) return out;
    const p = Math.max(2, Number(period) || 2);
    const off = Math.round(Number(offset) || 0);
    const x = Array.from({ length: p }, (_, i) => i);
    const sx = x.reduce((acc, v) => acc + v, 0);
    const sx2 = x.reduce((acc, v) => acc + (v * v), 0);
    const denom = (p * sx2) - (sx * sx);
    if (!Number.isFinite(denom) || Math.abs(denom) <= 1e-12) return out;
    const xEval = (p - 1) - off;
    for (let i = p - 1; i < values.length; i += 1) {
        let sy = 0;
        let sxy = 0;
        let valid = true;
        for (let j = 0; j < p; j += 1) {
            const y = toFiniteNumber(values[i - p + 1 + j]);
            if (!Number.isFinite(y)) {
                valid = false;
                break;
            }
            sy += y;
            sxy += (x[j] * y);
        }
        if (!valid) continue;
        const slope = ((p * sxy) - (sx * sy)) / denom;
        const intercept = (sy - (slope * sx)) / p;
        out[i] = intercept + (slope * xEval);
    }
    return out;
}

function rollingHMA(values, period) {
    const p = Math.max(2, Number(period) || 2);
    const half = Math.max(1, Math.floor(p / 2));
    const sqrtP = Math.max(1, Math.floor(Math.sqrt(p)));
    const w1 = rollingWMA(values, half);
    const w2 = rollingWMA(values, p);
    const raw = new Array(values.length).fill(NaN);
    for (let i = 0; i < values.length; i += 1) {
        const a = toFiniteNumber(w1[i]);
        const b = toFiniteNumber(w2[i]);
        if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
        raw[i] = (2 * a) - b;
    }
    return rollingWMA(raw, sqrtP);
}

function computeTrendilo(closes, volumes) {
    const len = closes.length;
    const pch = new Array(len).fill(NaN);
    const smooth = Math.max(1, Number(INDICATOR_DEFAULTS.trendiloSmooth) || 1);
    const length = Math.max(1, Number(INDICATOR_DEFAULTS.trendiloLength) || 50);
    const offset = Number(INDICATOR_DEFAULTS.trendiloOffset);
    const sigma = Math.max(0, Number(INDICATOR_DEFAULTS.trendiloSigma) || 6);
    const bmult = Number(INDICATOR_DEFAULTS.trendiloBandMultiplier) || 1.0;
    const useCustomBand = !!INDICATOR_DEFAULTS.trendiloUseCustomBandLength;
    const bandLength = Math.max(1, useCustomBand ? (Number(INDICATOR_DEFAULTS.trendiloBandLength) || 20) : length);
    const volumeSmaPeriod = Math.max(1, Number(INDICATOR_DEFAULTS.trendiloVolumeSmaPeriod) || 20);

    for (let i = smooth; i < len; i += 1) {
        const cur = toFiniteNumber(closes[i]);
        const prev = toFiniteNumber(closes[i - smooth]);
        if (!Number.isFinite(cur) || !Number.isFinite(prev) || Math.abs(cur) <= 1e-12) continue;
        pch[i] = ((cur - prev) / cur) * 100.0;
    }

    const avpch = rollingALMA(pch, length, offset, sigma);
    const rmsBase = rollingRms(avpch, bandLength);
    const rms = rmsBase.map((v) => (Number.isFinite(v) ? v * bmult : NaN));
    const negRms = rms.map((v) => (Number.isFinite(v) ? -v : NaN));
    const vol = Array.isArray(volumes) ? volumes : new Array(len).fill(0);
    const volSma = rollingSMA(vol.map((v) => Math.max(0, toFiniteNumber(v) || 0)), volumeSmaPeriod);
    const isVolumeConfirmed = new Array(len).fill(false);
    const cdir = new Array(len).fill(0);
    const cdirRaw = new Array(len).fill(0);
    const avpchBull = new Array(len).fill(NaN);
    const avpchBear = new Array(len).fill(NaN);
    const avpchNeutral = new Array(len).fill(NaN);
    for (let i = 0; i < len; i += 1) {
        const a = toFiniteNumber(avpch[i]);
        const r = toFiniteNumber(rms[i]);
        const vNow = Math.max(0, toFiniteNumber(vol[i]) || 0);
        const vAvg = Math.max(0, toFiniteNumber(volSma[i]) || 0);
        isVolumeConfirmed[i] = Number.isFinite(vNow) && Number.isFinite(vAvg) && (vNow > Math.max(1e-12, vAvg));
        if (!Number.isFinite(a) || !Number.isFinite(r)) continue;
        if (a > r) cdirRaw[i] = 1;
        else if (a < -r) cdirRaw[i] = -1;
        cdir[i] = isVolumeConfirmed[i] ? cdirRaw[i] : 0;
        if (cdir[i] > 0) avpchBull[i] = a;
        else if (cdir[i] < 0) avpchBear[i] = a;
        else avpchNeutral[i] = a;
    }
    return { pch, avpch, rms, negRms, cdir, cdirRaw, isVolumeConfirmed, volumeSma: volSma, avpchBull, avpchBear, avpchNeutral };
}

function computeAdvancedTrendilo(closes, volumes) {
    const base = computeTrendilo(closes, volumes);
    const len = Math.min(base.avpch.length, base.rms.length);
    const hystMult = Math.max(0, Number(INDICATOR_DEFAULTS.advancedTrendiloHysteresisMult) || 0.15);
    const cdir = new Array(len).fill(0);
    const cdirRaw = new Array(len).fill(0);
    const avpchBull = new Array(len).fill(NaN);
    const avpchBear = new Array(len).fill(NaN);
    const avpchNeutral = new Array(len).fill(NaN);
    let prevDir = 0;

    for (let i = 0; i < len; i += 1) {
        const a = toFiniteNumber(base.avpch[i]);
        const r = Math.abs(toFiniteNumber(base.rms[i]));
        if (!Number.isFinite(a) || !Number.isFinite(r)) {
            cdir[i] = 0;
            prevDir = 0;
            continue;
        }
        const h = r * hystMult;
        const upEnter = r + h;
        const dnEnter = -r - h;
        const upHold = r - h;
        const dnHold = -r + h;
        let dirNow = 0;
        if (a > upEnter) dirNow = 1;
        else if (a < dnEnter) dirNow = -1;
        else if (prevDir > 0 && a > upHold) dirNow = 1;
        else if (prevDir < 0 && a < dnHold) dirNow = -1;
        cdirRaw[i] = dirNow;
        cdir[i] = base.isVolumeConfirmed[i] ? dirNow : 0;
        prevDir = dirNow;
        if (cdir[i] > 0) avpchBull[i] = a;
        else if (cdir[i] < 0) avpchBear[i] = a;
        else avpchNeutral[i] = a;
    }

    return {
        pch: base.pch,
        avpch: base.avpch,
        rms: base.rms,
        negRms: base.negRms,
        isVolumeConfirmed: base.isVolumeConfirmed,
        volumeSma: base.volumeSma,
        cdir,
        cdirRaw,
        avpchBull,
        avpchBear,
        avpchNeutral,
    };
}

function computeTrendiloLsma(highs, lows) {
    const len = Math.min(Array.isArray(highs) ? highs.length : 0, Array.isArray(lows) ? lows.length : 0);
    const hl2 = new Array(len).fill(NaN);
    for (let i = 0; i < len; i += 1) {
        const h = toFiniteNumber(highs[i]);
        const l = toFiniteNumber(lows[i]);
        if (!Number.isFinite(h) || !Number.isFinite(l)) continue;
        hl2[i] = (h + l) / 2;
    }
    const smooth = Math.max(1, Number(INDICATOR_DEFAULTS.trendiloLsmaSmooth) || 5);
    const lsmaLength = Math.max(2, Number(INDICATOR_DEFAULTS.trendiloLsmaLength) || 25);
    const lsmaOffset = Math.round(Number(INDICATOR_DEFAULTS.trendiloLsmaOffset) || 0);
    const hmaLength = Math.max(2, Number(INDICATOR_DEFAULTS.trendiloLsmaHmaLength) || 50);

    const src = rollingEMA(hl2, smooth);
    const lsma = rollingLinReg(src, lsmaLength, lsmaOffset);
    const hma = rollingHMA(src, hmaLength);
    const combine = new Array(len).fill(NaN);
    const signal = new Array(len).fill(NaN);
    const dir = new Array(len).fill(0);
    for (let i = 0; i < len; i += 1) {
        const a = toFiniteNumber(lsma[i]);
        const b = toFiniteNumber(hma[i]);
        if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
        combine[i] = (a + b) / 2;
        if (i <= 0) continue;
        const prev = toFiniteNumber(combine[i - 1]);
        if (!Number.isFinite(prev)) continue;
        signal[i] = combine[i] - prev;
        if (signal[i] > 0) dir[i] = 1;
        else if (signal[i] < 0) dir[i] = -1;
    }
    return { src, lsma, hma, combine, signal, dir };
}

function computeAlphaWave(highs, lows, closes) {
    const len = Math.min(
        Array.isArray(highs) ? highs.length : 0,
        Array.isArray(lows) ? lows.length : 0,
        Array.isArray(closes) ? closes.length : 0,
    );
    const baseline = new Array(len).fill(NaN);
    const dir = new Array(len).fill(0);
    if (len <= 0) return { baseline, dir };

    const adxLen = Math.max(1, Number(INDICATOR_DEFAULTS.alphaWaveBaselineAdxLength) || 2);
    const weight = Math.max(0.1, Number(INDICATOR_DEFAULTS.alphaWaveBaselineWeight) || 10.0);
    const maLen = Math.max(1, Number(INDICATOR_DEFAULTS.alphaWaveBaselineMaLength) || 6);

    const powerBulls = new Array(len).fill(0);
    const powerBears = new Array(len).fill(0);
    const strRange = new Array(len).fill(0);
    const diagX = new Array(len).fill(0);
    const varMa = new Array(len).fill(NaN);

    const h0 = toFiniteNumber(highs[0]);
    const l0 = toFiniteNumber(lows[0]);
    const c0 = toFiniteNumber(closes[0]);
    if (!Number.isFinite(h0) || !Number.isFinite(l0) || !Number.isFinite(c0)) {
        return { baseline, dir };
    }
    strRange[0] = Math.max(h0 - l0, 1e-12);
    varMa[0] = c0;

    for (let i = 1; i < len; i += 1) {
        const hi = toFiniteNumber(highs[i]);
        const hi1 = toFiniteNumber(highs[i - 1]);
        const lo = toFiniteNumber(lows[i]);
        const lo1 = toFiniteNumber(lows[i - 1]);
        const close1 = toFiniteNumber(closes[i - 1]);
        const ci = toFiniteNumber(closes[i]);
        if (![hi, hi1, lo, lo1, close1, ci].every(Number.isFinite)) {
            powerBulls[i] = powerBulls[i - 1];
            powerBears[i] = powerBears[i - 1];
            strRange[i] = strRange[i - 1];
            diagX[i] = diagX[i - 1];
            varMa[i] = varMa[i - 1];
            continue;
        }
        const bulls1 = 0.5 * (Math.abs(hi - hi1) + (hi - hi1));
        const bears1 = 0.5 * (Math.abs(lo1 - lo) + (lo1 - lo));
        const bears = bulls1 >= bears1 ? 0 : bears1;
        const bulls = bulls1 <= bears1 ? 0 : bulls1;
        powerBulls[i] = ((weight * powerBulls[i - 1]) + bulls) / (weight + 1.0);
        powerBears[i] = ((weight * powerBears[i - 1]) + bears) / (weight + 1.0);
        const trueRange = Math.max(hi - lo, hi - close1);
        strRange[i] = ((weight * strRange[i - 1]) + trueRange) / (weight + 1.0);
        const posDi = strRange[i] > 0 ? powerBulls[i] / strRange[i] : 0;
        const negDi = strRange[i] > 0 ? powerBears[i] / strRange[i] : 0;
        const diSum = posDi + negDi;
        const diDiff = diSum > 0 ? Math.abs(posDi - negDi) / diSum : 0;
        diagX[i] = ((weight * diagX[i - 1]) + diDiff) / (weight + 1.0);
        const loIdx = Math.max(0, i - adxLen + 1);
        let adxMin = Number.POSITIVE_INFINITY;
        let adxMax = Number.NEGATIVE_INFINITY;
        for (let j = loIdx; j <= i; j += 1) {
            const v = toFiniteNumber(diagX[j]);
            if (!Number.isFinite(v)) continue;
            if (v < adxMin) adxMin = v;
            if (v > adxMax) adxMax = v;
        }
        if (!Number.isFinite(adxMin) || !Number.isFinite(adxMax)) {
            adxMin = 0;
            adxMax = 0;
        }
        const adxDiff = adxMax - adxMin;
        const adxConst = adxDiff > 1e-12 ? (diagX[i] - adxMin) / adxDiff : 0;
        varMa[i] = (((2.0 - adxConst) * varMa[i - 1]) + (adxConst * ci)) / 2.0;
    }

    let rollingSum = 0.0;
    for (let i = 0; i < len; i += 1) {
        const cur = toFiniteNumber(varMa[i]);
        if (!Number.isFinite(cur)) continue;
        rollingSum += cur;
        const dropIdx = i - maLen;
        if (dropIdx >= 0) {
            const drop = toFiniteNumber(varMa[dropIdx]);
            if (Number.isFinite(drop)) rollingSum -= drop;
        }
        const denom = Math.min(maLen, i + 1);
        if (denom > 0) baseline[i] = rollingSum / denom;
        const c = toFiniteNumber(closes[i]);
        const b = toFiniteNumber(baseline[i]);
        if (Number.isFinite(c) && Number.isFinite(b)) {
            if (c > b) dir[i] = 1;
            else if (c < b) dir[i] = -1;
            else dir[i] = 0;
        }
    }
    return { baseline, dir };
}

function computeDeadzonePro(closes) {
    const len = Array.isArray(closes) ? closes.length : 0;
    const line = new Array(len).fill(NaN);
    const dir = new Array(len).fill(0);
    if (len <= 0) return { line, dir };

    // Pine defaults from the shared script:
    // atp_hull_length=21, atp_hull_source=close
    const hullLength = 21;
    const halfLength = Math.max(1, Math.floor(hullLength / 2));
    const sqrtLength = Math.max(1, Math.round(Math.sqrt(hullLength)));

    const wma1 = rollingWMA(closes, halfLength);
    const wma2 = rollingWMA(closes, hullLength);
    const diff = new Array(len).fill(NaN);
    for (let i = 0; i < len; i += 1) {
        const a = toFiniteNumber(wma1[i]);
        const b = toFiniteNumber(wma2[i]);
        if (!Number.isFinite(a) || !Number.isFinite(b)) continue;
        diff[i] = (2.0 * a) - b;
    }
    const hull = rollingWMA(diff, sqrtLength);
    for (let i = 0; i < len; i += 1) {
        const h = toFiniteNumber(hull[i]);
        if (!Number.isFinite(h)) continue;
        line[i] = h;
        if (i <= 0) continue;
        const prev = toFiniteNumber(hull[i - 1]);
        if (!Number.isFinite(prev)) continue;
        const slope = h - prev;
        if (slope > 0) dir[i] = 1;
        else if (slope < 0) dir[i] = -1;
        else dir[i] = 0;
    }
    return { line, dir };
}

function _orbNyParts(unixSec) {
    const ts = Number(unixSec);
    if (!Number.isFinite(ts) || ts <= 0) return null;
    const d = new Date(ts * 1000);
    if (Number.isNaN(d.getTime())) return null;
    const parts = ORB_NY_PARTS_FORMATTER.formatToParts(d);
    const out = {};
    for (const p of parts) {
        if (p && p.type && p.type !== 'literal') out[p.type] = p.value;
    }
    const y = Number(out.year);
    const m = Number(out.month);
    const dd = Number(out.day);
    let hh = Number(out.hour);
    const mm = Number(out.minute);
    if (![y, m, dd, hh, mm].every(Number.isFinite)) return null;
    if (hh === 24) hh = 0;
    const dateKey = `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(dd).padStart(2, '0')}`;
    return {
        dateKey,
        minutesOfDay: (Math.max(0, Math.min(23, hh)) * 60) + Math.max(0, Math.min(59, mm)),
    };
}

function _orbIsIndexSymbol(symbolLike) {
    const s = String(symbolLike || '').trim().toUpperCase();
    if (!s) return false;
    return s.includes('NAS')
        || s.includes('US500')
        || s.includes('SPX')
        || s.includes('DJI')
        || s.includes('US30')
        || s.includes('NQ')
        || s.includes('ES')
        || s.includes('USTEC');
}

function _orbInWindow(minute, startMin, endMin) {
    const m = Number(minute);
    if (!Number.isFinite(m)) return false;
    if (endMin >= startMin) {
        return m >= startMin && m < endMin;
    }
    return m >= startMin || m < endMin;
}

function _orbInKillZone(minute, isIndex) {
    const windows = isIndex
        ? [
            [20 * 60, 24 * 60],       // Asia
            [2 * 60, 5 * 60],         // London
            [(8 * 60) + 30, 11 * 60], // NY AM
            [(13 * 60) + 30, 16 * 60],// NY PM
        ]
        : [
            [20 * 60, 24 * 60],       // Asia
            [2 * 60, 5 * 60],         // London
            [7 * 60, 10 * 60],        // NY AM
            [10 * 60, 12 * 60],       // London Close
        ];
    return windows.some(([startMin, endMin]) => _orbInWindow(minute, startMin, endMin));
}

function computeOrbSignal(bars, symbolLike) {
    const len = Array.isArray(bars) ? bars.length : 0;
    const signal = new Array(len).fill(NaN);
    const dir = new Array(len).fill(0);
    const inKillZone = new Array(len).fill(false);
    if (!Array.isArray(bars) || len <= 0) return { signal, dir, inKillZone };

    const perDay = new Map();

    for (let i = 0; i < len; i += 1) {
        const b = bars[i] || {};
        const parts = _orbNyParts(b.time);
        const c = toFiniteNumber(b.close);
        if (!parts || !Number.isFinite(c)) continue;
        signal[i] = c;
        inKillZone[i] = false;
        let bucket = perDay.get(parts.dateKey);
        if (!bucket) {
            bucket = { indices: [], orHigh: NaN, orLow: NaN };
            perDay.set(parts.dateKey, bucket);
        }
        bucket.indices.push(i);
    }

    const OR_START_MIN = (9 * 60) + 30; // NY 09:30
    const OR_END_MIN = (9 * 60) + 45;   // NY 09:45
    const EXEC_END_MIN = 12 * 60;       // NY 12:00 hard stop (gray after this)
    const HOLD_BARS = 2;

    for (const bucket of perDay.values()) {
        for (const idx of bucket.indices) {
            const b = bars[idx] || {};
            const parts = _orbNyParts(b.time);
            const h = toFiniteNumber(b.high);
            const l = toFiniteNumber(b.low);
            if (!parts || !Number.isFinite(h) || !Number.isFinite(l)) continue;
            if (parts.minutesOfDay >= OR_START_MIN && parts.minutesOfDay < OR_END_MIN) {
                bucket.orHigh = Number.isFinite(bucket.orHigh) ? Math.max(bucket.orHigh, h) : h;
                bucket.orLow = Number.isFinite(bucket.orLow) ? Math.min(bucket.orLow, l) : l;
            }
        }
    }

    for (const bucket of perDay.values()) {
        if (!Number.isFinite(bucket.orHigh) || !Number.isFinite(bucket.orLow)) continue;
        let upCount = 0;
        let downCount = 0;
        let sessionDir = 0;      // 1 long, -1 short, 0 wait
        let tradeLocked = false; // one ORB cycle per day: enter once, then wait after re-entry
        for (const idx of bucket.indices) {
            const b = bars[idx] || {};
            const parts = _orbNyParts(bars[idx]?.time);
            const close = toFiniteNumber(b?.close);
            const high = toFiniteNumber(b?.high);
            const low = toFiniteNumber(b?.low);
            if (!parts || !Number.isFinite(close)) continue;

            const minute = Number(parts.minutesOfDay || 0);
            const afterOpenRange = minute >= OR_END_MIN;
            const inExecWindow = minute >= OR_END_MIN && minute < EXEC_END_MIN;
            inKillZone[idx] = inExecWindow;

            // Before OR closes or after execution window, stay gray.
            if (!afterOpenRange || !inExecWindow) {
                dir[idx] = 0;
                upCount = 0;
                downCount = 0;
                continue;
            }

            // Once one full ORB trade cycle is finished, no more signals for the day.
            if (tradeLocked) {
                dir[idx] = 0;
                continue;
            }

            // If in position, hold only while price remains outside ORB.
            if (sessionDir > 0) {
                if (close > bucket.orHigh) {
                    dir[idx] = 1;
                    continue;
                }
                // Returned to range -> done for today.
                sessionDir = 0;
                tradeLocked = true;
                dir[idx] = 0;
                continue;
            }
            if (sessionDir < 0) {
                if (close < bucket.orLow) {
                    dir[idx] = -1;
                    continue;
                }
                // Returned to range -> done for today.
                sessionDir = 0;
                tradeLocked = true;
                dir[idx] = 0;
                continue;
            }

            // Flat state: require breakout + displacement proxy (3-candle FVG on chart TF).
            const prev2 = idx >= 2 ? (bars[idx - 2] || {}) : null;
            const prev2High = toFiniteNumber(prev2?.high);
            const prev2Low = toFiniteNumber(prev2?.low);
            const bullFvg = Number.isFinite(low) && Number.isFinite(prev2High) && (low > prev2High);
            const bearFvg = Number.isFinite(high) && Number.isFinite(prev2Low) && (high < prev2Low);

            if (close > bucket.orHigh && bullFvg) {
                upCount += 1;
                downCount = 0;
            } else if (close < bucket.orLow && bearFvg) {
                downCount += 1;
                upCount = 0;
            } else {
                upCount = 0;
                downCount = 0;
            }

            if (upCount >= HOLD_BARS) {
                sessionDir = 1;
                dir[idx] = 1;
            } else if (downCount >= HOLD_BARS) {
                sessionDir = -1;
                dir[idx] = -1;
            } else {
                dir[idx] = 0;
            }
        }
    }
    return { signal, dir, inKillZone };
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

function normalizeTimeKey(t) {
    if (typeof t === 'number') return `n:${t}`;
    if (typeof t === 'string') return `s:${t}`;
    if (t && typeof t === 'object') {
        try { return `o:${JSON.stringify(t)}`; } catch (_) { return 'o:[invalid]'; }
    }
    return '';
}

function computeIndicatorPack(bars, selection) {
    const sel = selection || {};
    const needSmaEma = !!sel.smaEma;
    const needBoll = !!sel.bollinger;
    const needAdx = !!sel.adx;
    const needRsi = !!sel.rsi;
    const needStoch = !!sel.stoch;
    const needTrendilo = !!sel.trendilo || !!sel.advancedTrendilo || !!sel.trendiloBarColor;
    const needTrendiloLsma = !!sel.trendiloLsma;
    const needAlphaWave = !!sel.alphaWave;
    const needDeadzonePro = !!sel.deadzonePro;
    const needOrbSignal = !!sel.orbSignal;
    const needGoldenCross = !!sel.goldenCross;

    const needCloses = needSmaEma || needBoll || needAdx || needRsi || needStoch || needTrendilo || needGoldenCross || needAlphaWave || needDeadzonePro || needOrbSignal;
    const needHighLow = needAdx || needStoch || needTrendiloLsma || needAlphaWave;

    const closes = needCloses ? bars.map(b => toFiniteNumber(b?.close)) : [];
    const highs = needHighLow ? bars.map(b => toFiniteNumber(b?.high)) : [];
    const lows = needHighLow ? bars.map(b => toFiniteNumber(b?.low)) : [];
    const volumes = needTrendilo ? bars.map(b => Math.max(0, toFiniteNumber(b?.volume) || 0)) : [];

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
    const trendilo = needTrendilo ? computeTrendilo(closes, volumes) : {
        pch: [],
        avpch: [],
        rms: [],
        negRms: [],
        cdir: [],
        cdirRaw: [],
        isVolumeConfirmed: [],
        volumeSma: [],
        avpchBull: [],
        avpchBear: [],
        avpchNeutral: [],
    };
    const advancedTrendilo = needTrendilo ? computeAdvancedTrendilo(closes, volumes) : {
        pch: [],
        avpch: [],
        rms: [],
        negRms: [],
        cdir: [],
        cdirRaw: [],
        isVolumeConfirmed: [],
        volumeSma: [],
        avpchBull: [],
        avpchBear: [],
        avpchNeutral: [],
    };
    const trendiloLsma = needTrendiloLsma ? computeTrendiloLsma(highs, lows) : {
        src: [],
        lsma: [],
        hma: [],
        combine: [],
        signal: [],
        dir: [],
    };
    const alphaWave = needAlphaWave ? computeAlphaWave(highs, lows, closes) : {
        baseline: [],
        dir: [],
    };
    const deadzonePro = needDeadzonePro ? computeDeadzonePro(closes) : {
        line: [],
        dir: [],
    };
    const orbSignal = needOrbSignal ? computeOrbSignal(bars, getCostModelSymbol()) : {
        signal: [],
        dir: [],
        inKillZone: [],
    };
    return {
        sma20, sma50, sma200, ema20, ema50, ema200,
        bbUpper, bbMid, bbLower,
        adx, rsi,
        stochK: stoch.k,
        stochD: stoch.d,
        trendiloPch: trendilo.pch,
        trendiloAvpch: trendilo.avpch,
        trendiloRms: trendilo.rms,
        trendiloNegRms: trendilo.negRms,
        trendiloDir: trendilo.cdir,
        trendiloBull: trendilo.avpchBull,
        trendiloBear: trendilo.avpchBear,
        trendiloNeutral: trendilo.avpchNeutral,
        advancedTrendiloPch: advancedTrendilo.pch,
        advancedTrendiloAvpch: advancedTrendilo.avpch,
        advancedTrendiloRms: advancedTrendilo.rms,
        advancedTrendiloNegRms: advancedTrendilo.negRms,
        advancedTrendiloDir: advancedTrendilo.cdir,
        advancedTrendiloBull: advancedTrendilo.avpchBull,
        advancedTrendiloBear: advancedTrendilo.avpchBear,
        advancedTrendiloNeutral: advancedTrendilo.avpchNeutral,
        trendiloLsmaSrc: trendiloLsma.src,
        trendiloLsmaLsma: trendiloLsma.lsma,
        trendiloLsmaHma: trendiloLsma.hma,
        trendiloLsmaCombine: trendiloLsma.combine,
        trendiloLsmaSignal: trendiloLsma.signal,
        trendiloLsmaDir: trendiloLsma.dir,
        alphaWaveBaseline: alphaWave.baseline,
        alphaWaveDir: alphaWave.dir,
        deadzoneProLine: deadzonePro.line,
        deadzoneProDir: deadzonePro.dir,
        orbSignal: orbSignal.signal,
        orbDir: orbSignal.dir,
        orbKillZone: orbSignal.inKillZone,
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

function setTrendiloPanelVisibility(show) {
    const panelEl = document.getElementById('chart-trendilo-panel');
    const containerEl = document.querySelector('.chart-container');
    if (!panelEl || !containerEl) return;
    const visible = !!show;
    panelEl.classList.toggle('d-none', !visible);
    containerEl.classList.toggle('with-trendilo-panel', visible);
    if (!visible) {
        try { trendiloPanelChart?.clearCrosshairPosition?.(); } catch (_) {}
        try { chart?.clearCrosshairPosition?.(); } catch (_) {}
    }
    refreshChartViewport();
}

function isTrendiloPanelEnabled() {
    return !!(indicatorSelection.trendilo || indicatorSelection.advancedTrendilo);
}

function ensureTrendiloPanelChart() {
    if (trendiloPanelChart || typeof LightweightCharts === 'undefined') return;
    const panelEl = document.getElementById('chart-trendilo-panel');
    if (!panelEl) return;

    trendiloPanelChart = LightweightCharts.createChart(panelEl, {
        width: Math.max(320, panelEl.clientWidth || 320),
        height: Math.max(120, panelEl.clientHeight || 180),
        layout: {
            background: { type: 'solid', color: CHART_BG_COLOR },
            textColor: '#d1d4dc',
            fontSize: 11,
        },
        grid: {
            vertLines: { color: '#1e222d' },
            horzLines: { color: '#1e222d' },
        },
        crosshair: { mode: LightweightCharts.CrosshairMode.Normal },
        rightPriceScale: { borderColor: '#2a2e39', minimumWidth: CHART_RIGHT_SCALE_MIN_WIDTH },
        timeScale: {
            borderColor: '#2a2e39',
            timeVisible: true,
            secondsVisible: false,
        },
    });

    trendiloPanelSeries.upper = trendiloPanelChart.addLineSeries({
        color: '#a855f7',
        lineWidth: 2,
        lastValueVisible: false,
        priceLineVisible: false,
    });
    trendiloPanelSeries.lower = trendiloPanelChart.addLineSeries({
        color: '#a855f7',
        lineWidth: 2,
        lastValueVisible: false,
        priceLineVisible: false,
    });
    trendiloPanelSeries.signal = trendiloPanelChart.addLineSeries({
        color: '#9ca3af',
        lineWidth: 3,
        lastValueVisible: false,
        priceLineVisible: false,
    });
    trendiloPanelSeries.zero = trendiloPanelChart.addLineSeries({
        color: '#6b7280',
        lineWidth: 1,
        lineStyle: 2,
        lastValueVisible: false,
        priceLineVisible: false,
    });

    const panelResizeObserver = new ResizeObserver((entries) => {
        for (const entry of entries) {
            trendiloPanelChart?.applyOptions({
                width: Math.max(320, entry.contentRect.width || 320),
                height: Math.max(120, entry.contentRect.height || 120),
            });
        }
    });
    panelResizeObserver.observe(panelEl);

    if (chart) {
        const initialRange = chart.timeScale().getVisibleLogicalRange?.();
        if (initialRange) {
            try { trendiloPanelChart.timeScale().setVisibleLogicalRange(initialRange); } catch (_) {}
        }
        chart.timeScale().subscribeVisibleLogicalRangeChange((range) => {
            if (!trendiloPanelChart || trendiloPanelSyncingRange) return;
            trendiloPanelSyncingRange = true;
            try {
                trendiloPanelChart.timeScale().setVisibleLogicalRange(range);
            } catch (_) {
                // ignore transient sync errors when chart has no data
            }
            requestAnimationFrame(() => { trendiloPanelSyncingRange = false; });
        });
        chart.subscribeCrosshairMove((param) => {
            if (!trendiloPanelChart || !isTrendiloPanelEnabled() || trendiloPanelSyncingCrosshair) return;
            if (typeof trendiloPanelChart.setCrosshairPosition !== 'function') return;
            trendiloPanelSyncingCrosshair = true;
            try {
                const t = param?.time;
                if (t == null) {
                    trendiloPanelChart.clearCrosshairPosition?.();
                } else {
                    const key = normalizeTimeKey(t);
                    const v = trendiloSignalByTime.get(key);
                    const d = Number(trendiloDirByTime.get(key) || 0);
                    const targetSeries = trendiloPanelSeries.signal;
                    if (Number.isFinite(v) && targetSeries) {
                        trendiloPanelChart.setCrosshairPosition(v, t, targetSeries);
                    } else {
                        trendiloPanelChart.clearCrosshairPosition?.();
                    }
                }
            } catch (_) {
                // noop
            }
            trendiloPanelSyncingCrosshair = false;
        });
        trendiloPanelChart.timeScale().subscribeVisibleLogicalRangeChange((range) => {
            if (!chart || trendiloPanelSyncingRange) return;
            trendiloPanelSyncingRange = true;
            try {
                chart.timeScale().setVisibleLogicalRange(range);
            } catch (_) {
                // ignore transient sync errors when chart has no data
            }
            requestAnimationFrame(() => { trendiloPanelSyncingRange = false; });
        });
        trendiloPanelChart.subscribeCrosshairMove((param) => {
            if (!chart || !isTrendiloPanelEnabled() || trendiloPanelSyncingCrosshair) return;
            if (typeof chart.setCrosshairPosition !== 'function') return;
            trendiloPanelSyncingCrosshair = true;
            try {
                const t = param?.time;
                if (t == null) {
                    chart.clearCrosshairPosition?.();
                } else {
                    const key = normalizeTimeKey(t);
                    const close = mainCloseByTime.get(key);
                    if (Number.isFinite(close) && mainCrosshairSeries) {
                        chart.setCrosshairPosition(close, t, mainCrosshairSeries);
                    } else {
                        chart.clearCrosshairPosition?.();
                    }
                }
            } catch (_) {
                // noop
            }
            trendiloPanelSyncingCrosshair = false;
        });
    }
}

function clearTrendiloPanelData() {
    Object.values(trendiloPanelSeries).forEach((series) => {
        try { series?.setData([]); } catch (_) {}
    });
}

function ensureOscillatorScale() {
    if (!chart) return;
    chart.priceScale('osc').applyOptions({
        autoScale: true,
        scaleMargins: { top: 0.52, bottom: 0.02 },
        borderColor: '#334155',
    });
}

function ensureRsiHoverTooltip() {
    const container = document.getElementById('chart-main');
    if (!container) return null;
    if (!rsiHoverTooltipEl) {
        const el = document.createElement('div');
        el.id = 'rsi-hover-tooltip';
        el.style.position = 'absolute';
        el.style.display = 'none';
        el.style.pointerEvents = 'none';
        el.style.zIndex = '30';
        el.style.padding = '4px 8px';
        el.style.borderRadius = '6px';
        el.style.background = 'rgba(15, 23, 42, 0.92)';
        el.style.border = '1px solid rgba(244, 114, 182, 0.7)';
        el.style.color = '#fbcfe8';
        el.style.fontSize = '11px';
        el.style.fontWeight = '600';
        el.style.lineHeight = '1.2';
        el.style.whiteSpace = 'nowrap';
        rsiHoverTooltipEl = el;
        container.appendChild(el);
    }
    const style = window.getComputedStyle(container);
    if (style.position === 'static') container.style.position = 'relative';
    return rsiHoverTooltipEl;
}

function hideRsiHoverTooltip() {
    if (rsiHoverTooltipEl) rsiHoverTooltipEl.style.display = 'none';
}

function updateRsiHoverTooltip(param) {
    if (!chart || !indicatorSelection.rsi) {
        hideRsiHoverTooltip();
        return;
    }
    const container = document.getElementById('chart-main');
    if (!container) {
        hideRsiHoverTooltip();
        return;
    }
    const point = param?.point;
    const maxX = Number(container.clientWidth || 0);
    const maxY = Number(container.clientHeight || 0);
    if (!point || !Number.isFinite(point.x) || !Number.isFinite(point.y) || point.x < 0 || point.y < 0 || point.x > maxX || point.y > maxY) {
        hideRsiHoverTooltip();
        return;
    }

    let rsiVal = NaN;
    try {
        const rsiSeries = indicatorSeries.rsi;
        const seriesData = param?.seriesData;
        if (rsiSeries && seriesData && typeof seriesData.get === 'function') {
            const row = seriesData.get(rsiSeries);
            if (typeof row === 'number') rsiVal = Number(row);
            else if (row && typeof row === 'object' && Number.isFinite(Number(row.value))) rsiVal = Number(row.value);
        }
    } catch (_) { /* noop */ }

    if (!Number.isFinite(rsiVal)) {
        const key = normalizeTimeKey(param?.time);
        const mapped = Number(rsiByTime.get(key));
        if (Number.isFinite(mapped)) rsiVal = mapped;
    }

    if (!Number.isFinite(rsiVal)) {
        hideRsiHoverTooltip();
        return;
    }

    const tip = ensureRsiHoverTooltip();
    if (!tip) return;
    tip.textContent = `RSI(${INDICATOR_DEFAULTS.rsiPeriod}): ${rsiVal.toFixed(2)}`;

    const tipW = Number(tip.offsetWidth || 96);
    const tipH = Number(tip.offsetHeight || 22);
    let left = Number(point.x) + 10;
    let top = Number(point.y) - (tipH + 10);
    if (left + tipW > maxX - 6) left = maxX - tipW - 6;
    if (left < 6) left = 6;
    if (top < 6) top = Number(point.y) + 10;
    if (top + tipH > maxY - 6) top = maxY - tipH - 6;

    tip.style.left = `${Math.round(left)}px`;
    tip.style.top = `${Math.round(top)}px`;
    tip.style.display = 'block';
}

function clearAllIndicatorSeries() {
    for (const key of Object.keys(indicatorSeries)) removeIndicatorSeries(key);
    clearTrendiloPanelData();
    setTrendiloPanelVisibility(false);
    trendiloSignalByTime.clear();
    trendiloDirByTime.clear();
    rsiByTime.clear();
    hideRsiHoverTooltip();
    mainCloseByTime.clear();
    mainCrosshairSeries?.setData([]);
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
    if (Array.isArray(strategyBacktestMarkers) && strategyBacktestMarkers.length > 0) markers.push(...strategyBacktestMarkers);
    if (indicatorSelection.goldenCross && Array.isArray(goldenCrossMarkers) && goldenCrossMarkers.length > 0) {
        markers.push(...goldenCrossMarkers);
    }
    if (Array.isArray(fvgCreatorMarkers) && fvgCreatorMarkers.length > 0) {
        markers.push(...fvgCreatorMarkers);
    }
    markers.sort((a, b) => Number(a.time || 0) - Number(b.time || 0));
    candleSeries.setMarkers(markers);
}

function applyTrendiloBarColoring(bars, trendiloDir) {
    if (!candleSeries || !Array.isArray(bars) || bars.length === 0) return;
    const useTrendiloBarColor = !!indicatorSelection.trendiloBarColor;
    const colored = bars.map((b, i) => {
        const up = Number(b?.close || 0) >= Number(b?.open || 0);
        let color = up ? '#26a69a44' : '#ef535044';
        if (useTrendiloBarColor && Array.isArray(trendiloDir)) {
            const d = Number(trendiloDir[i] || 0);
            if (d > 0) color = '#22c55e66';
            else if (d < 0) color = '#ef444466';
            else color = '#9ca3af55';
        }
        return { ...b, color };
    });
    candleSeries.setData(colored);
}

function applyIndicatorVisibility() {
    const showSmaEma = !!indicatorSelection.smaEma;
    const showBoll = !!indicatorSelection.bollinger;
    const showAdx = !!indicatorSelection.adx;
    const showRsi = !!indicatorSelection.rsi;
    const showStoch = !!indicatorSelection.stoch;
    const showTrendilo = !!(indicatorSelection.trendilo || indicatorSelection.advancedTrendilo);
    const showTrendiloLsma = !!indicatorSelection.trendiloLsma;
    const showAlphaWave = !!indicatorSelection.alphaWave;
    const showDeadzonePro = !!indicatorSelection.deadzonePro;
    const showOrbSignal = !!indicatorSelection.orbSignal;
    const showTrendiloBarColor = !!indicatorSelection.trendiloBarColor;

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
    if (!showTrendilo) {
        clearTrendiloPanelData();
        setTrendiloPanelVisibility(false);
    }
    if (!showTrendiloLsma) {
        removeIndicatorSeries('trendiloLsma');
    }
    if (!showAlphaWave) {
        removeIndicatorSeries('alphaWave');
    }
    if (!showDeadzonePro) {
        removeIndicatorSeries('deadzonePro');
    }
    if (!showOrbSignal) {
        removeIndicatorSeries('orbSignal');
    }
    if (!(showAdx || showRsi || showStoch || showTrendiloBarColor) && chart) {
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
        || indicatorSelection.trendilo
        || indicatorSelection.advancedTrendilo
        || indicatorSelection.trendiloLsma
        || indicatorSelection.alphaWave
        || indicatorSelection.deadzonePro
        || indicatorSelection.orbSignal
        || indicatorSelection.trendiloBarColor
        || indicatorSelection.goldenCross;

    if (!hasSelection) {
        applyTrendiloBarColoring(bars, null);
        mainCloseByTime.clear();
        trendiloSignalByTime.clear();
        trendiloDirByTime.clear();
        rsiByTime.clear();
        hideRsiHoverTooltip();
        mainCrosshairSeries?.setData([]);
        goldenCrossMarkers = [];
        syncCandleMarkers();
        return;
    }

    if (!Array.isArray(bars) || bars.length === 0) {
        mainCloseByTime.clear();
        trendiloSignalByTime.clear();
        trendiloDirByTime.clear();
        rsiByTime.clear();
        hideRsiHoverTooltip();
        mainCrosshairSeries?.setData([]);
        if (indicatorSelection.trendilo || indicatorSelection.advancedTrendilo) {
            ensureTrendiloPanelChart();
            setTrendiloPanelVisibility(true);
            clearTrendiloPanelData();
        }
        goldenCrossMarkers = [];
        syncCandleMarkers();
        return;
    }

    const pack = computeIndicatorPack(bars, indicatorSelection);
    mainCloseByTime.clear();
    const crosshairBaseData = [];
    for (const b of bars) {
        const t = Number(b?.time || 0);
        const c = toFiniteNumber(b?.close);
        if (!Number.isFinite(t) || !Number.isFinite(c)) continue;
        mainCloseByTime.set(normalizeTimeKey(t), c);
        crosshairBaseData.push({ time: t, value: c });
    }
    mainCrosshairSeries?.setData(crosshairBaseData);

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
        ensureIndicatorSeries('rsi', { color: '#f472b6', lineWidth: 3, priceScaleId: 'osc' });
        indicatorSeries.rsi?.setData(seriesDataFromArray(bars, pack.rsi));
        rsiByTime.clear();
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const v = toFiniteNumber(pack.rsi?.[i]);
            if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
            rsiByTime.set(normalizeTimeKey(t), v);
        }
    } else {
        rsiByTime.clear();
        hideRsiHoverTooltip();
    }

    if (indicatorSelection.stoch) {
        ensureIndicatorSeries('stochK', { color: '#38bdf8', lineWidth: 1, priceScaleId: 'osc' });
        ensureIndicatorSeries('stochD', { color: '#f97316', lineWidth: 1, priceScaleId: 'osc' });
        indicatorSeries.stochK?.setData(seriesDataFromArray(bars, pack.stochK));
        indicatorSeries.stochD?.setData(seriesDataFromArray(bars, pack.stochD));
    }

    const useAdvancedTrendilo = !!indicatorSelection.advancedTrendilo;
    if (indicatorSelection.trendilo || indicatorSelection.advancedTrendilo) {
        ensureTrendiloPanelChart();
        setTrendiloPanelVisibility(true);
        const zeroLine = new Array(bars.length).fill(0);
        trendiloSignalByTime.clear();
        trendiloDirByTime.clear();
        const avpchArr = useAdvancedTrendilo ? pack.advancedTrendiloAvpch : pack.trendiloAvpch;
        const dirArr = useAdvancedTrendilo ? pack.advancedTrendiloDir : pack.trendiloDir;
        const rmsArr = useAdvancedTrendilo ? pack.advancedTrendiloRms : pack.trendiloRms;
        const negRmsArr = useAdvancedTrendilo ? pack.advancedTrendiloNegRms : pack.trendiloNegRms;
        const signalData = [];
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const a = toFiniteNumber(avpchArr[i]);
            if (!Number.isFinite(t) || !Number.isFinite(a)) continue;
            const key = normalizeTimeKey(t);
            const d = Number(dirArr[i] || 0);
            trendiloSignalByTime.set(key, a);
            trendiloDirByTime.set(key, d);
            signalData.push({
                time: t,
                value: a,
                color: d > 0 ? '#22c55e' : (d < 0 ? '#ef4444' : '#9ca3af'),
            });
        }
        trendiloPanelSeries.upper?.setData(seriesDataFromArray(bars, rmsArr));
        trendiloPanelSeries.lower?.setData(seriesDataFromArray(bars, negRmsArr));
        trendiloPanelSeries.signal?.setData(signalData);
        trendiloPanelSeries.zero?.setData(seriesDataFromArray(bars, zeroLine));
    } else {
        trendiloSignalByTime.clear();
        trendiloDirByTime.clear();
        clearTrendiloPanelData();
        setTrendiloPanelVisibility(false);
    }

    if (indicatorSelection.trendiloLsma) {
        ensureIndicatorSeries('trendiloLsma', { color: '#ffff00', lineWidth: 2 });
        const combineArr = pack.trendiloLsmaCombine || [];
        const dirArr = pack.trendiloLsmaDir || [];
        const lsmaData = [];
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const v = toFiniteNumber(combineArr[i]);
            if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
            const d = Number(dirArr[i] || 0);
            lsmaData.push({
                time: t,
                value: v,
                color: d > 0 ? '#00ff0a' : (d < 0 ? '#fe1807' : '#ffff00'),
            });
        }
        indicatorSeries.trendiloLsma?.setData(lsmaData);
    } else {
        removeIndicatorSeries('trendiloLsma');
    }

    if (indicatorSelection.alphaWave) {
        ensureIndicatorSeries('alphaWave', { color: '#9ca3af', lineWidth: 2 });
        const baselineArr = pack.alphaWaveBaseline || [];
        const dirArr = pack.alphaWaveDir || [];
        const alphaData = [];
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const v = toFiniteNumber(baselineArr[i]);
            if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
            const d = Number(dirArr[i] || 0);
            alphaData.push({
                time: t,
                value: v,
                color: d > 0 ? '#01ffa7' : (d < 0 ? '#fb0bff' : '#9e9e9e'),
            });
        }
        indicatorSeries.alphaWave?.setData(alphaData);
    } else {
        removeIndicatorSeries('alphaWave');
    }

    if (indicatorSelection.deadzonePro) {
        ensureIndicatorSeries('deadzonePro', { color: '#9ca3af', lineWidth: 2 });
        const lineArr = pack.deadzoneProLine || [];
        const dirArr = pack.deadzoneProDir || [];
        const deadzoneData = [];
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const v = toFiniteNumber(lineArr[i]);
            if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
            const d = Number(dirArr[i] || 0);
            deadzoneData.push({
                time: t,
                value: v,
                color: d > 0 ? '#4caf50' : (d < 0 ? '#ff5252' : '#9ca3af'),
            });
        }
        indicatorSeries.deadzonePro?.setData(deadzoneData);
    } else {
        removeIndicatorSeries('deadzonePro');
    }

    if (indicatorSelection.orbSignal) {
        ensureIndicatorSeries('orbSignal', { color: '#9ca3af', lineWidth: 2 });
        const signalArr = pack.orbSignal || [];
        const dirArr = pack.orbDir || [];
        const orbData = [];
        for (let i = 0; i < bars.length; i += 1) {
            const t = Number(bars[i]?.time || 0);
            const v = toFiniteNumber(signalArr[i]);
            if (!Number.isFinite(t) || !Number.isFinite(v)) continue;
            const d = Number(dirArr[i] || 0);
            orbData.push({
                time: t,
                value: v,
                color: d > 0 ? '#22c55e' : (d < 0 ? '#ef4444' : '#9ca3af'),
            });
        }
        indicatorSeries.orbSignal?.setData(orbData);
    } else {
        removeIndicatorSeries('orbSignal');
    }

    const barDir = useAdvancedTrendilo ? pack.advancedTrendiloDir : pack.trendiloDir;
    applyTrendiloBarColoring(bars, barDir);
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
        trendilo: read('ind-trendilo'),
        advancedTrendilo: read('ind-advanced-trendilo'),
        trendiloLsma: read('ind-trendilo-lsma'),
        alphaWave: read('ind-alpha-wave'),
        deadzonePro: read('ind-deadzone-pro'),
        orbSignal: read('ind-orb-signal'),
        trendiloBarColor: read('ind-trendilo-barcolor'),
        goldenCross: read('ind-golden-cross'),
    };
}

function resetIndicatorSelectionUI() {
    const ids = ['ind-sma-ema', 'ind-adx', 'ind-rsi', 'ind-stoch', 'ind-bollinger', 'ind-trendilo', 'ind-advanced-trendilo', 'ind-trendilo-lsma', 'ind-alpha-wave', 'ind-deadzone-pro', 'ind-orb-signal', 'ind-trendilo-barcolor', 'ind-golden-cross'];
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
    return getPriceDecimalsForSymbol(symbol);
}

function getPriceDecimalsForSymbol(symbolLike) {
    const symbol = String(symbolLike || 'XAUUSD').toUpperCase();
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
    const restoredSessionId = getPersistedSessionId();
    sessionId = null;
    sessionCreateNewRequested = true;
    tickMs = getTickMsForSpeed(playSpeed);
    setTransportMode('IDLE');
    updateSessionIdStat();
    renderSymbolEconomicsHint(null);
    updateSpeedButtons();
    updatePerfStats();
    initChart();
    bindEvents();
    initWorkbenchState();
    applyWorkbenchModeUI();
    setWorkbenchFullscreenUI(!!document.fullscreenElement);
    startQuickOpenTradesPoller();
    void refreshSessionCatalog(false);
    void refreshBrokerSymbols(false);
    if (restoredSessionId) {
        showStatus(`Saved session #${restoredSessionId} is available in the Session list.`, 'info');
    }
});

function initWorkbenchState() {
    currentOpenPositionState = null;
    quickOpenTradesState = [];
    clearQuickTpWatcher();
    clearOpenPositionProtectionLines();
    renderQuickOpenTrades([]);
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
        strategy_backtest: {
            enabled: false,
            strategy: 'deadzone_pro',
            deadzone_mode: 'default',
            lookback_days: 30,
            force_first_entry: true,
            last_result: null,
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
    const sbToggle = document.getElementById('tool-strategy-backtest-toggle');
    if (sbToggle) sbToggle.checked = false;
    const sbSettings = document.getElementById('strategy-backtest-settings');
    if (sbSettings) sbSettings.classList.remove('active');
    syncStrategyBacktestModeControls();
    renderStrategyBacktestSummary(null);
    tradeMarkers = [];
    strategyBacktestMarkers = [];
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
        width: Math.max(320, container.clientWidth || 320),
        height: Math.max(220, container.clientHeight || 400),
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
        rightPriceScale: { borderColor: '#2a2e39', minimumWidth: CHART_RIGHT_SCALE_MIN_WIDTH },
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
    mainCrosshairSeries = chart.addLineSeries({
        color: 'rgba(0,0,0,0)',
        lineWidth: 1,
        lastValueVisible: false,
        priceLineVisible: false,
    });
    chart.priceScale('volume').applyOptions({
        scaleMargins: { top: 0.85, bottom: 0 },
    });

    // Track user scroll: detect when user scrolls away from realtime
    chart.timeScale().subscribeVisibleLogicalRangeChange(() => {
        if (trendiloPanelSyncingRange) return; // ignore sync-caused changes
        try {
            const range = chart.timeScale().getVisibleLogicalRange();
            if (range && candleSeries) {
                const barCount = allBars.length || 0;
                // If the right edge of visible range is near the last bar, user is at realtime
                const atRealtime = range.to >= barCount - 3;
                userHasScrolledAway = !atRealtime;
            }
        } catch (_) { /* ignore */ }
    });
    chart.subscribeCrosshairMove((param) => {
        updateRsiHoverTooltip(param);
    });
    container.addEventListener('mouseleave', () => {
        hideRsiHoverTooltip();
    });

    const resizeObserver = new ResizeObserver(entries => {
        for (const entry of entries) {
            chart.applyOptions({
                width: Math.max(320, entry.contentRect.width || 320),
                height: Math.max(220, entry.contentRect.height || 220),
            });
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
    document.getElementById('btn-toggle-livestream')?.addEventListener('click', toggleLivestreamMode);
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
    // Agent config accordion sections
    document.querySelectorAll('.agent-section-toggle[data-agent-section]').forEach((btn) => {
        btn.addEventListener('click', () => {
            const secId = btn.getAttribute('data-agent-section');
            const body = document.getElementById(secId);
            if (!body) return;
            const isOpen = !body.classList.contains('d-none');
            body.classList.toggle('d-none', isOpen);
            btn.setAttribute('aria-expanded', String(!isOpen));
        });
    });
    document.getElementById('workbench-mode')?.addEventListener('change', () => {
        applyWorkbenchModeUI();
        const mode = getWorkbenchMode();
        showStatus(mode === 'replay' ? 'Playback trading mode selected.' : 'Normal live mode selected.', 'info');
    });
    document.getElementById('btn-session-refresh')?.addEventListener('click', () => {
        void refreshSessionCatalog(true);
    });
    document.getElementById('btn-session-close')?.addEventListener('click', () => {
        void closeSelectedSession();
    });
    document.getElementById('sim-session-select')?.addEventListener('change', (e) => {
        const val = String(e?.target?.value || '').trim();
        if (!val) {
            sessionCreateNewRequested = true;
            clearPersistedSessionId();
            renderSessionSelector();
            sessionSymbolEconomics = null;
            renderSymbolEconomicsHint(null);
            showStatus('New session mode selected. Starting replay/live will create a fresh session.', 'info');
            return;
        }
        sessionCreateNewRequested = false;
        void switchToSession(Number(val), { restartLive: true });
    });
    document.getElementById('btn-start-session')?.addEventListener('click', startSession);
    document.getElementById('btn-live-feed')?.addEventListener('click', toggleLiveFeed);
    document.getElementById('btn-refresh-symbols')?.addEventListener('click', () => {
        void refreshBrokerSymbols(true);
    });
    document.getElementById('btn-run-trendilo-opps')?.addEventListener('click', () => {
        void runTrendiloOpportunityScreener();
    });
    document.getElementById('btn-load-trendilo-opps-cache')?.addEventListener('click', () => {
        loadTrendiloOpportunityScreenerCache();
    });
    document.getElementById('trendilo-opp-body')?.addEventListener('click', (e) => {
        const target = e?.target?.closest?.('[data-auto-action]');
        if (!target) return;
        const action = String(target.getAttribute('data-auto-action') || '').trim().toLowerCase();
        if (action === 'start-row') {
            const symbol = String(target.getAttribute('data-auto-symbol') || '').trim().toUpperCase();
            const strategy = String(target.getAttribute('data-auto-strategy') || '').trim().toLowerCase();
            const rowIdx = Number(target.getAttribute('data-auto-row') || -1);
            const riskEl = Number.isFinite(rowIdx) && rowIdx >= 0 ? document.getElementById(`auto-risk-${rowIdx}`) : null;
            const rrEl = Number.isFinite(rowIdx) && rowIdx >= 0 ? document.getElementById(`auto-rr-${rowIdx}`) : null;
            const riskPercent = Number.isFinite(Number(riskEl?.value)) ? Number(riskEl.value) : undefined;
            const rrTarget = Number.isFinite(Number(rrEl?.value)) ? Number(rrEl.value) : undefined;
            const rows = Array.isArray(lastStrategyOpportunityScanData?.opportunities) ? lastStrategyOpportunityScanData.opportunities : [];
            const row = rows.find((r) => String(r?.symbol || '').trim().toUpperCase() === symbol && String(r?.strategy || '').trim().toLowerCase() === strategy);
            if (!row) {
                showStatus('Automation start failed: screener row not found.', 'warning');
                return;
            }
            target.setAttribute('disabled', 'disabled');
            void startStrategyAutomationFromOpportunityRow(row, { riskPercent, rrTarget }).finally(() => {
                target.removeAttribute('disabled');
            });
            return;
        }
        if (action === 'stop-row' || action === 'stop-job') {
            const parentSessionId = Number(target.getAttribute('data-auto-parent') || 0);
            const childSessionId = Number(target.getAttribute('data-auto-child') || 0);
            const jobId = String(target.getAttribute('data-auto-job') || '').trim();
            void stopStrategyAutomationJob({ parentSessionId, childSessionId, jobId });
        }
    });
    document.getElementById('trendilo-auto-body')?.addEventListener('click', (e) => {
        const target = e?.target?.closest?.('[data-auto-action]');
        if (!target) return;
        const action = String(target.getAttribute('data-auto-action') || '').trim().toLowerCase();
        if (action !== 'stop-job') return;
        const parentSessionId = Number(target.getAttribute('data-auto-parent') || 0);
        const childSessionId = Number(target.getAttribute('data-auto-child') || 0);
        const jobId = String(target.getAttribute('data-auto-job') || '').trim();
        void stopStrategyAutomationJob({ parentSessionId, childSessionId, jobId });
    });
    document.getElementById('auto-monitor-body')?.addEventListener('click', (e) => {
        const target = e?.target?.closest?.('[data-auto-action]');
        if (!target) {
            const rowEl = e?.target?.closest?.('tr[data-auto-row]');
            if (!rowEl) return;
            const rowJobId = String(rowEl.getAttribute('data-auto-row') || '').trim();
            if (!rowJobId) return;
            if (automationMonitorExpandedJobs.has(rowJobId)) automationMonitorExpandedJobs.delete(rowJobId);
            else automationMonitorExpandedJobs.add(rowJobId);
            _renderAutomationMonitorRows(strategyAutomationJobs);
            return;
        }
        const action = String(target.getAttribute('data-auto-action') || '').trim().toLowerCase();
        if (action === 'stop-job') {
            const parentSessionId = Number(target.getAttribute('data-auto-parent') || 0);
            const childSessionId = Number(target.getAttribute('data-auto-child') || 0);
            const jobId = String(target.getAttribute('data-auto-job') || '').trim();
            void stopStrategyAutomationJob({ parentSessionId, childSessionId, jobId });
            return;
        }
        if (action === 'toggle-job-trades') {
            const jobId = String(target.getAttribute('data-auto-job') || '').trim();
            if (!jobId) return;
            if (automationMonitorExpandedJobs.has(jobId)) automationMonitorExpandedJobs.delete(jobId);
            else automationMonitorExpandedJobs.add(jobId);
            _renderAutomationMonitorRows(strategyAutomationJobs);
            return;
        }
        if (action === 'close-open-trade') {
            const childSessionId = Number(target.getAttribute('data-auto-child') || 0);
            const tradeId = Number(target.getAttribute('data-auto-trade') || 0);
            if (!(childSessionId > 0) || !(tradeId > 0)) return;
            target.setAttribute('disabled', 'disabled');
            void closeAutomationOpenTrade({ childSessionId, tradeId }).finally(() => {
                target.removeAttribute('disabled');
            });
            return;
        }
        if (action === 'open-job-chart') {
            const job = _automationJobFromMonitorActionTarget(target);
            void openAutomationChartModal(job, { showModal: true });
            const modalEl = document.getElementById('automationMonitorModal');
            if (modalEl && window.bootstrap && window.bootstrap.Modal) {
                const modal = window.bootstrap.Modal.getInstance(modalEl);
                if (modal) modal.hide();
            }
            showStatus(`Opened automation chart: ${job.symbol} ${job.timeframe} ${job.strategy}`, 'info');
            return;
        }
        if (action === 'show-job-logs') {
            const job = _automationJobFromMonitorActionTarget(target);
            void openAutomationLogsModal(job, { showModal: true });
            return;
        }
    });
    document.getElementById('btn-refresh-auto-monitor')?.addEventListener('click', () => {
        void refreshAutomationMonitorModal(true);
    });
    document.getElementById('auto-monitor-sort')?.addEventListener('change', () => {
        _renderAutomationMonitorRows(strategyAutomationJobs);
    });
    document.getElementById('auto-monitor-running-only')?.addEventListener('change', () => {
        _renderAutomationMonitorRows(strategyAutomationJobs);
    });
    document.getElementById('btn-refresh-auto-logs')?.addEventListener('click', () => {
        if (!automationLogsContext) {
            showStatus('No automation selected for logs.', 'warning');
            return;
        }
        void openAutomationLogsModal(automationLogsContext, { showModal: false });
    });
    document.getElementById('auto-logs-sort')?.addEventListener('change', () => {
        _renderAutomationLogsRows();
    });
    document.getElementById('auto-logs-direction')?.addEventListener('change', () => {
        _renderAutomationLogsRows();
    });
    document.getElementById('auto-logs-scope')?.addEventListener('change', () => {
        if (!automationLogsContext) {
            _renderAutomationLogsRows();
            return;
        }
        void openAutomationLogsModal(automationLogsContext, { showModal: false });
    });
    const executionBadgeEl = document.getElementById('stat-execution');
    if (executionBadgeEl) {
        executionBadgeEl.addEventListener('click', () => {
            openAgentSafetyFromExecutionBadge();
        });
        executionBadgeEl.addEventListener('keydown', (e) => {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                openAgentSafetyFromExecutionBadge();
            }
        });
    }
    document.getElementById('trendiloOppModal')?.addEventListener('show.bs.modal', () => {
        const strategyEl = document.getElementById('trendilo-opp-strategy');
        const profile = String(document.getElementById('agent-strategy-profile')?.value || '').trim().toLowerCase();
        const profileToStrategy = {
            classic_htf_fvg: 'mtf',
            htf_fvg_liquidity_reclaim_v2: 'htf_reclaim',
            orb_ny_15m_imbalance: 'orb',
            trendilo_confirmation_v1: 'trendilo',
            advanced_trendilo_confirmation_v1: 'advanced_trendilo',
            trendilo_lsma_confirmation_v1: 'trendilo_lsma',
            alpha_wave_confirmation_v1: 'alpha_wave',
        };
        const mappedStrategy = String(profileToStrategy[profile] || '');
        if (strategyEl && mappedStrategy && Array.from(strategyEl.options || []).some((o) => String(o.value || '').toLowerCase() === mappedStrategy)) {
            strategyEl.value = mappedStrategy;
        }
        const tfMain = normalizeTimeframeLabel(document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
        const tfEl = document.getElementById('trendilo-opp-timeframe');
        if (tfEl && Array.from(tfEl.options || []).some((o) => String(o.value || '').toUpperCase() === tfMain)) {
            tfEl.value = tfMain;
        }
        const execTfEl = document.getElementById('trendilo-opp-exec-timeframe');
        if (execTfEl) execTfEl.value = 'AUTO';
        loadTrendiloOpportunityScreenerCache();
        void loadStrategyAutomationJobs(false);
    });
    document.getElementById('automationMonitorModal')?.addEventListener('show.bs.modal', () => {
        void refreshAutomationMonitorModal(false);
    });
    document.getElementById('automationChartModal')?.addEventListener('shown.bs.modal', () => {
        const mainEl = document.getElementById('automation-chart-main');
        if (automationChartMain && mainEl) {
            automationChartMain.applyOptions({
                width: Math.max(320, mainEl.clientWidth || 320),
                height: Math.max(240, mainEl.clientHeight || 240),
            });
            try { automationChartMain.timeScale().fitContent(); } catch (_) {}
        }
        const panelEl = document.getElementById('automation-chart-panel');
        if (automationChartPanel && panelEl && !panelEl.classList.contains('d-none')) {
            automationChartPanel.applyOptions({
                width: Math.max(320, panelEl.clientWidth || 320),
                height: Math.max(120, panelEl.clientHeight || 120),
            });
            try { automationChartPanel.timeScale().fitContent(); } catch (_) {}
        }
    });
    document.getElementById('btn-refresh-automation-chart')?.addEventListener('click', () => {
        if (!automationChartJobContext) {
            _automationChartSetStatus('No automation job selected yet.', 'warning');
            return;
        }
        void openAutomationChartModal(automationChartJobContext, { showModal: false });
    });
    document.getElementById('automationStarterModal')?.addEventListener('show.bs.modal', () => {
        const strategyEl = document.getElementById('auto-start-strategy');
        const symbolEl = document.getElementById('auto-start-symbol');
        const tfEl = document.getElementById('auto-start-timeframe');
        const sourceEl = document.getElementById('auto-start-source');
        const searchEl = document.getElementById('auto-start-symbol-search');
        const statusEl = document.getElementById('auto-start-status');
        const profile = String(document.getElementById('agent-strategy-profile')?.value || '').trim().toLowerCase();
        const profileToStrategy = {
            trendilo_confirmation_v1: 'trendilo',
            advanced_trendilo_confirmation_v1: 'advanced_trendilo',
            trendilo_lsma_confirmation_v1: 'trendilo_lsma',
            alpha_wave_confirmation_v1: 'alpha_wave',
        };
        const mapped = String(profileToStrategy[profile] || 'trendilo');
        if (strategyEl && Array.from(strategyEl.options || []).some((o) => String(o.value || '').toLowerCase() === mapped)) {
            strategyEl.value = mapped;
        }
        applyBrokerSymbolsToAutomationUI(brokerSymbolCatalog);
        if (searchEl) searchEl.value = '';
        const mainSymbol = String(document.getElementById('sim-symbol')?.value || '').trim().toUpperCase();
        if (symbolEl && mainSymbol) {
            const hasOption = Array.from(symbolEl.options || []).some((o) => String(o.value || '').trim().toUpperCase() === mainSymbol);
            if (hasOption) {
                symbolEl.value = mainSymbol;
            }
        }
        const tfMain = normalizeTimeframeLabel(document.getElementById('sim-timeframe')?.value || 'M15', 'M15');
        if (tfEl && Array.from(tfEl.options || []).some((o) => String(o.value || '').toUpperCase() === tfMain)) {
            tfEl.value = tfMain;
        }
        if (sourceEl) sourceEl.value = String(document.getElementById('live-source')?.value || 'mt5').toLowerCase();
        _syncAutoStartDeadzoneModeControl();
        if (statusEl) statusEl.textContent = 'Ready.';
    });
    document.getElementById('auto-start-strategy')?.addEventListener('change', () => {
        _syncAutoStartDeadzoneModeControl();
    });
    document.getElementById('btn-start-auto-manual')?.addEventListener('click', () => {
        void startStrategyAutomationFromManualModal();
    });
    document.getElementById('sim-symbol-search')?.addEventListener('input', () => {
        applySymbolSearchFilter();
    });
    document.getElementById('sim-symbol-search')?.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            const searchEl = document.getElementById('sim-symbol-search');
            if (searchEl) {
                searchEl.value = '';
                applySymbolSearchFilter();
            }
        }
    });
    document.getElementById('btn-clear-symbol-search')?.addEventListener('click', () => {
        const searchEl = document.getElementById('sim-symbol-search');
        if (!searchEl) return;
        searchEl.value = '';
        applySymbolSearchFilter();
        searchEl.focus();
    });
    document.getElementById('auto-start-symbol-search')?.addEventListener('input', () => {
        applyAutomationSymbolSearchFilter();
    });
    document.getElementById('auto-start-symbol-search')?.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            const searchEl = document.getElementById('auto-start-symbol-search');
            if (searchEl) {
                searchEl.value = '';
                applyAutomationSymbolSearchFilter();
            }
        }
    });
    document.getElementById('btn-clear-auto-start-symbol-search')?.addEventListener('click', () => {
        const searchEl = document.getElementById('auto-start-symbol-search');
        if (!searchEl) return;
        searchEl.value = '';
        applyAutomationSymbolSearchFilter();
        searchEl.focus();
    });
    document.getElementById('btn-refresh-auto-start-symbols')?.addEventListener('click', () => {
        void refreshBrokerSymbols(true);
    });
    document.getElementById('sim-symbol')?.addEventListener('change', () => {
        updateCostModelHint();
        syncQuickTradeControlsFromMain();
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
    syncAgentStrategyControls();
    renderSessionLiveControlUI(sessionLiveControlState || { execution_mode: 'paper' }, sessionLiveAccountState);
    setAgentToolModeBadge(document.getElementById('agent-strategy-tool-access')?.value || 'all');
    toggleAgentIdentityFields(false);
    toggleAgentMemoryFields(false);
    document.getElementById('agent-guardrail-enabled')?.addEventListener('change', () => {
        syncAgentGuardrailControls();
    });
    document.getElementById('agent-guardrail-news-filter')?.addEventListener('change', () => {
        syncAgentGuardrailControls();
    });
    document.getElementById('agent-guardrail-max-risk-per-trade')?.addEventListener('change', () => {
        syncAgentGuardrailControls();
    });
    document.getElementById('agent-live-execution-mode')?.addEventListener('change', () => {
        const modeEl = document.getElementById('agent-live-execution-mode');
        const selected = String(modeEl?.value || 'paper').trim().toLowerCase() === 'live_mt5' ? 'live_mt5' : 'paper';
        const nextCfg = {
            ...(sessionLiveControlState || _normalizeSessionLiveControl({ execution_mode: 'paper' })),
            execution_mode: selected,
        };
        renderSessionLiveControlUI(nextCfg, sessionLiveAccountState);
    });
    document.getElementById('btn-agent-live-apply')?.addEventListener('click', () => {
        void applySessionLiveControlFromUI();
    });
    document.getElementById('btn-agent-live-mode-paper')?.addEventListener('click', () => {
        void applySessionLiveControlFromUI({ forceMode: 'paper' });
    });
    document.getElementById('btn-agent-live-mode-live')?.addEventListener('click', () => {
        void applySessionLiveControlFromUI({ forceMode: 'live_mt5' });
    });
    document.getElementById('agent-news-provider')?.addEventListener('change', () => {
        syncAgentNewsProviderControls();
    });
    document.getElementById('agent-news-llm-summary')?.addEventListener('change', () => {
        syncAgentNewsProviderControls();
    });
    document.getElementById('agent-strategy-tool-access')?.addEventListener('change', (e) => {
        setAgentToolModeBadge(String(e?.target?.value || 'all'));
    });
    document.getElementById('agent-strategy-profile')?.addEventListener('change', () => {
        syncAgentStrategyControls();
    });
    ['ind-sma-ema', 'ind-adx', 'ind-rsi', 'ind-stoch', 'ind-bollinger', 'ind-trendilo', 'ind-advanced-trendilo', 'ind-trendilo-lsma', 'ind-alpha-wave', 'ind-deadzone-pro', 'ind-orb-signal', 'ind-trendilo-barcolor', 'ind-golden-cross'].forEach((id) => {
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
    document.getElementById('btn-trade-quick-enter')?.addEventListener('click', () => {
        void executeQuickTradeFromControls();
    });
    document.getElementById('trade-no-protection-toggle')?.addEventListener('change', () => {
        syncTradeProtectionToggleUI();
    });
    document.getElementById('btn-close-pos')?.addEventListener('click', closePosition);
    document.getElementById('quick-open-trades-list')?.addEventListener('click', (e) => {
        const btn = e?.target?.closest?.('[data-quick-close="1"]');
        if (!btn) return;
        const row = {
            session_trade_id: Number(btn.getAttribute('data-session-trade-id') || 0),
            ticket: Number(btn.getAttribute('data-ticket') || 0),
            symbol: String(btn.getAttribute('data-symbol') || '').trim().toUpperCase(),
            lot_size: Number(btn.getAttribute('data-lot-size') || 0),
        };
        void quickCloseOpenTrade(row);
    });
    syncQuickTradeControlsFromMain();
    syncTradeProtectionToggleUI();

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
    document.getElementById('tool-strategy-backtest-toggle')?.addEventListener('change', (e) => {
        const settings = document.getElementById('strategy-backtest-settings');
        if (settings) settings.classList.toggle('active', e.target.checked);
        if (!toolStates.strategy_backtest) toolStates.strategy_backtest = {};
        toolStates.strategy_backtest.enabled = !!e.target.checked;
        if (!e.target.checked) clearStrategyBacktestOverlay(false);
    });
    document.getElementById('btn-strategy-backtest-run')?.addEventListener('click', () => {
        void runStrategyBacktestOverlay();
    });
    document.getElementById('btn-strategy-backtest-clear')?.addEventListener('click', () => {
        clearStrategyBacktestOverlay();
    });
    document.getElementById('strategy-backtest-strategy')?.addEventListener('change', () => {
        syncStrategyBacktestModeControls();
    });

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

function _normalizeLiveBar(rawBar, prevBar = null) {
    if (!rawBar || typeof rawBar !== 'object') return null;
    const t = Number(rawBar.time);
    if (!Number.isFinite(t) || t <= 0) return null;

    let o = Number(rawBar.open);
    let h = Number(rawBar.high);
    let l = Number(rawBar.low);
    let c = Number(rawBar.close);
    const vRaw = Number(rawBar.volume || 0);
    const vol = Number.isFinite(vRaw) && vRaw > 0 ? vRaw : 0;

    const prev = (prevBar && typeof prevBar === 'object') ? prevBar : null;
    const prevTime = Number(prev?.time);
    const prevOpen = Number(prev?.open);
    const prevHigh = Number(prev?.high);
    const prevLow = Number(prev?.low);
    const prevClose = Number(prev?.close);
    const tfSec = Math.max(60, timeframeToMinutes(document.getElementById('sim-timeframe')?.value || 'M15') * 60);

    if (!Number.isFinite(o)) o = Number.isFinite(c) ? c : (Number.isFinite(prevClose) ? prevClose : NaN);
    if (!Number.isFinite(c)) c = Number.isFinite(o) ? o : NaN;
    if (!Number.isFinite(h)) h = Math.max(o, c);
    if (!Number.isFinite(l)) l = Math.min(o, c);

    if (!Number.isFinite(o) || !Number.isFinite(h) || !Number.isFinite(l) || !Number.isFinite(c)) return null;
    if (o <= 0 || h <= 0 || l <= 0 || c <= 0) return null;

    if (Number.isFinite(prevTime) && Number.isFinite(prevClose) && prevClose > 0) {
        if (t < prevTime) {
            if ((prevTime - t) > tfSec) return null;
        }

        // Merge intrabar updates safely to avoid flicker/corruption on the same candle.
        if (t === prevTime) {
            o = Number.isFinite(prevOpen) && prevOpen > 0 ? prevOpen : o;
            c = Number.isFinite(c) ? c : prevClose;
            const hiCand = [h, o, c, prevHigh].filter((x) => Number.isFinite(x) && x > 0);
            const loCand = [l, o, c, prevLow].filter((x) => Number.isFinite(x) && x > 0);
            h = hiCand.length ? Math.max(...hiCand) : h;
            l = loCand.length ? Math.min(...loCand) : l;
        } else if (t > prevTime) {
            // Guard against obvious outliers from transient feed glitches.
            const ratio = c / prevClose;
            if (!Number.isFinite(ratio) || ratio <= 0 || ratio > 5.0 || ratio < 0.2) return null;

            // For contiguous candles, anchor the new candle open to previous close.
            const dt = t - prevTime;
            const contiguous = Number.isFinite(dt) && dt > 0 && dt <= Math.ceil(tfSec * 1.5);
            if (contiguous) {
                const openGapRatio = Math.abs(o - prevClose) / prevClose;
                // Preserve rare true gaps, otherwise enforce OHLC continuity.
                if (!Number.isFinite(openGapRatio) || openGapRatio <= 0.02) {
                    o = prevClose;
                }
                // First-seen new bar should spawn from a minimal body/wick.
                h = Math.max(o, c);
                l = Math.min(o, c);
            } else {
                h = Math.max(h, o, c);
                l = Math.min(l, o, c);
            }
        }
    }

    if (!(h >= l)) {
        const hi = Math.max(h, l, o, c);
        const lo = Math.min(h, l, o, c);
        h = hi;
        l = lo;
    }

    return {
        time: Math.floor(t),
        open: o,
        high: h,
        low: l,
        close: c,
        volume: vol,
    };
}

function _sanitizeLiveBars(rawBars) {
    const src = Array.isArray(rawBars) ? rawBars : [];
    if (!src.length) return [];
    const sorted = src
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
            && b.open > 0
            && b.high > 0
            && b.low > 0
            && b.close > 0
        )
        .sort((a, b) => a.time - b.time);

    const deduped = [];
    for (const b of sorted) {
        if (deduped.length > 0 && Number(deduped[deduped.length - 1].time) === Number(b.time)) {
            deduped[deduped.length - 1] = b;
        } else {
            deduped.push(b);
        }
    }

    const out = [];
    for (const b of deduped) {
        const prev = out.length > 0 ? out[out.length - 1] : null;
        const normalized = _normalizeLiveBar(b, prev);
        if (normalized) out.push(normalized);
    }
    return out;
}

function upsertLiveBar(bar) {
    const prev = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
    const normalized = _normalizeLiveBar(bar, prev);
    if (!normalized) return;
    const t = Number(normalized.time);
    if (allBars.length > 0 && Number(allBars[allBars.length - 1].time) === t) {
        allBars[allBars.length - 1] = normalized;
    } else {
        allBars.push(normalized);
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
    const activeSource = getSelectedLiveSource();
    if (sessionId) {
        void setSessionLiveControl(false, activeSource);
    }
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

function _shouldCreateFreshSession() {
    const selectEl = document.getElementById('sim-session-select');
    if (sessionCreateNewRequested) return true;
    return String(selectEl?.value || '').trim() === '';
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
    const candle = (status && typeof status === 'object' && status.current_candle && typeof status.current_candle === 'object')
        ? status.current_candle
        : {};
    const candleHasTime = Number.isFinite(Number(candle?.time)) || String(candle?.time || '').trim().length > 0;
    const candleOk = !candle?.error && Number.isFinite(Number(candle?.close)) && candleHasTime;
    // Accept MT5 source when either backend marks connected OR we already have a valid candle.
    // Some brokers expose a valid current candle even when large history windows are not yet available.
    const connected = !!status?.mt5_connected || candleOk;
    const historyOk = status?.history_ready !== false;
    let error = status?.error || '';
    let warning = '';
    if (!connected) {
        error = error || (candle?.error ? String(candle.error) : 'mt5 unavailable');
    } else if (!historyOk) {
        warning = `limited history for ${symbol} ${timeframe}; starting stream with reduced bootstrap`;
    }
    console.info('[LiveWS] preflight', {
        symbol,
        timeframe,
        connected,
        historyOk,
        mt5Connected: !!status?.mt5_connected,
        candleOk,
        error: error || null,
        warning: warning || null,
    });
    return {
        ok: !!statusRes.ok && status?.ok !== false && connected,
        error: error || 'mt5 unavailable',
        warning,
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

    const hasSession = await ensureSessionForLive(symbol, timeframe, source);
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
        if (chk.warning) {
            showStatus(chk.warning, 'warning');
        }
    } catch (err) {
        showStatus(`${sourceLabel} status check failed: ${err.message}`, 'warning');
        if (!isReconnect) liveFeedRequested = false;
        return;
    }

    const liveCtl = await setSessionLiveControl(true, source);
    if (!liveCtl.ok) {
        showStatus(`Backend live trigger relay warning: ${liveCtl.error}`, 'warning');
    }

    const wsUrl = _buildLiveWsUrl(source, symbol, timeframe, historyBars);
    try {
        const ws = new WebSocket(wsUrl);
        liveFeedSocket = ws;
        let receivedStreamPayload = false;
        let lastStreamError = '';
        ws.onopen = () => {
            console.info('[LiveWS] open', { source, symbol, timeframe, sessionId, wsUrl });
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
            try {
                let msg;
                try { msg = JSON.parse(event.data); } catch (_) { return; }
                if (!msg || !msg.type) return;
                if (msg.type === 'snapshot') {
                    receivedStreamPayload = true;
                    const barsRaw = Array.isArray(msg.bars) ? msg.bars : [];
                    const bars = _sanitizeLiveBars(barsRaw);
                    console.info('[LiveWS] snapshot', {
                        symbol: msg.symbol || symbol,
                        resolvedSymbol: msg.resolved_symbol || '',
                        bars: bars.length,
                        requestedHistory: msg.requested_history,
                        returnedBars: msg.returned_bars,
                    });
                    allBars = bars.slice();
                    currentBar = Math.max(0, allBars.length - 1);
                    totalBars = allBars.length;
                    userHasScrolledAway = false;
                    candleSeries.setData(allBars);
                    volumeSeries.setData(allBars.map(b => ({
                        time: b.time,
                        value: b.volume || 0,
                        color: b.close >= b.open ? '#26a69a44' : '#ef535044',
                    })));
                    updateIndicatorsOnChart();
                    updateBarCounter();
                    updateStats({ balance: initialBalance, total_pnl: 0, trades_count: 0, wins: 0 });
                    const snapshotLastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
                    if (snapshotLastBar && Number.isFinite(Number(snapshotLastBar.close))) {
                        void maybeQuickTpAutoClose(Number(snapshotLastBar.close));
                    }
                    try { chart?.timeScale()?.fitContent(); } catch (_) { /* ignore */ }
                    void maybePushLiveAgentTick(true);
                    return;
                }
                if (msg.type === 'tick') {
                    receivedStreamPayload = true;
                    const bars = Array.isArray(msg.bars) ? msg.bars : [];
                    for (const b of bars) {
                        const prev = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
                        const normalized = _normalizeLiveBar(b, prev);
                        if (!normalized) continue;
                        upsertLiveBar(normalized);
                        candleSeries.update(normalized);
                        volumeSeries.update({
                            time: normalized.time,
                            value: normalized.volume || 0,
                            color: normalized.close >= normalized.open ? '#26a69a44' : '#ef535044',
                        });
                    }
                    updateIndicatorsOnChart();
                    updateBarCounter();
                    const tickLastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
                    if (tickLastBar && Number.isFinite(Number(tickLastBar.close))) {
                        void maybeQuickTpAutoClose(Number(tickLastBar.close));
                    }
                    void maybePushLiveAgentTick(false);
                    return;
                }
                if (msg.type === 'warning') {
                    console.warn('[LiveWS] warning', msg.message || `${sourceLabel} warning`);
                    showStatus(String(msg.message || `${sourceLabel} warning`), 'warning');
                    return;
                }
                if (msg.type === 'error') {
                    lastStreamError = String(msg.message || `${sourceLabel} stream error`);
                    console.error('[LiveWS] error', lastStreamError);
                    showStatus(lastStreamError, 'danger');
                }
            } catch (err) {
                console.error('[LiveWS] onmessage failed', err);
                showStatus(`Live chart render failed: ${err?.message || err}`, 'danger');
            }
        };
        ws.onclose = (event) => {
            const wasRequested = liveFeedRequested && !liveFeedManualStop;
            liveFeedActive = false;
            if (liveFeedSocket === ws) liveFeedSocket = null;
            setLiveFeedButtonState(false, source);
            const closeCode = Number(event?.code || 0);
            const closeReason = String(event?.reason || '').trim();
            const closeDetail = lastStreamError || closeReason || (closeCode ? `close code ${closeCode}` : 'socket closed');
            const immediateFailure = !receivedStreamPayload;
            const retryable = !immediateFailure && ![4404, 4408].includes(closeCode);
            console.warn('[LiveWS] close', { closeCode, closeReason, closeDetail, immediateFailure, retryable, wasRequested, manualStop: liveFeedManualStop });
            if (wasRequested) {
                if (!retryable) {
                    liveFeedRequested = false;
                    showStatus(`${sourceLabel} live feed failed: ${closeDetail}`, 'danger');
                    if (!isPlaying) setTransportMode(sessionId ? 'READY' : 'IDLE');
                    return;
                }
                const backoffMs = Math.min(8000, 500 * Math.pow(2, liveFeedReconnectAttempts));
                liveFeedReconnectAttempts += 1;
                showStatus(`${sourceLabel} live feed disconnected (${closeDetail}), reconnecting...`, 'warning');
                setTimeout(() => {
                    if (liveFeedRequested && !liveFeedActive) void startLiveFeed(true);
                }, backoffMs);
                return;
            }
            if (!isPlaying) setTransportMode(sessionId ? 'READY' : 'IDLE');
            showStatus(`${sourceLabel} live feed stopped`, 'info');
        };
        ws.onerror = () => {
            console.error('[LiveWS] socket error', { source, symbol, timeframe, sessionId });
            showStatus(`${sourceLabel} live feed socket error`, 'danger');
        };
    } catch (err) {
        if (!isReconnect) liveFeedRequested = false;
        showStatus(`Failed to start ${sourceLabel} live feed: ${err.message}`, 'danger');
    }
}

async function ensureSessionForLive(symbol, timeframe, source = 'mt5') {
    if (sessionId && !_shouldCreateFreshSession()) {
        try {
            const existingRes = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}`);
            const existing = await existingRes.json().catch(() => ({}));
            if (existingRes.ok && existing?.id && String(existing.strategy_id || '') === STRATEGY_ID) {
                setSessionLiveExecutionModeFromLiveControl(existing?.live_control || null, existing?.live_account || null);
                renderSymbolEconomicsHint(existing?.symbol_economics || null);
                const sameSymbol = String(existing.symbol || '').toUpperCase() === String(symbol || '').toUpperCase();
                const sameTimeframe = String(existing.timeframe || '').toUpperCase() === String(timeframe || '').toUpperCase();
                applyCostModelToUI(existing?.cost_model || null);
                if (sameSymbol && sameTimeframe) {
                    updateSessionIdStat();
                    void refreshAgentMemoryList('');
                    void refreshAgentIdentity(false);
                    return true;
                }
                showStatus(
                    `Creating a new live session for ${symbol} ${timeframe} (existing session #${existing.id} is preserved).`,
                    'info'
                );
            }
        } catch (_) {
            // Fall through and recreate session.
        }
    }
    const dataFile = document.getElementById('sim-datafile')?.value || '';
    const balance = parseFloat(document.getElementById('sim-balance')?.value) || 10000;
    try {
        // New live session creation invalidates any in-flight async session switch.
        sessionSwitchSeq += 1;
        const costModelCfg = getCostModelConfigFromUI();
        const res = await fetch(`${API_BASE}/api/simulation/sessions`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                strategy_id: STRATEGY_ID,
                symbol,
                timeframe,
                mode: 'live',
                data_file: dataFile || null,
                initial_balance: balance,
                allow_empty_replay: true,
                config: {
                    cost_model: costModelCfg,
                    live_control: {
                        enabled: true,
                        source: String(source || 'mt5').toLowerCase(),
                        backend_native: String(source || 'mt5').toLowerCase() === 'mt5',
                        execution_mode: 'paper',
                    },
                },
            }),
        });
        const data = await res.json();
        if (!res.ok || data?.error || !data?.id) {
            showStatus(`Session init failed: ${data?.error || 'backend error'}`, 'danger');
            return false;
        }
        sessionId = data.id;
        setSessionLiveExecutionModeFromLiveControl({ execution_mode: 'paper' });
        renderSymbolEconomicsHint(data?.symbol_economics || null);
        sessionCreateNewRequested = false;
        persistSessionId(sessionId);
        updateSessionIdStat();
        await refreshSessionCatalog(false);
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
        // New replay session creation invalidates any in-flight async session switch.
        sessionSwitchSeq += 1;
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
        renderSymbolEconomicsHint(data?.symbol_economics || null);
        sessionCreateNewRequested = false;
        persistSessionId(sessionId);
        updateSessionIdStat();
        await refreshSessionCatalog(false);
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
        await refreshQuickOpenTrades();

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
        strategyBacktestMarkers = [];
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
        await refreshSessionCatalog(false);
        await refreshAgentState(false);
        await refreshQuickOpenTrades();
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
                void refreshSessionCatalog(false);
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
        const guardOutliers = getWorkbenchMode() === 'live';
        let prevBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
        for (const rawBar of data.bars) {
            const bt = Number(rawBar?.time);
            const bo = Number(rawBar?.open);
            const bh = Number(rawBar?.high);
            const bl = Number(rawBar?.low);
            const bc = Number(rawBar?.close);
            const bv = Number(rawBar?.volume || 0);
            if (!Number.isFinite(bt) || bt <= 0) continue;
            if (!Number.isFinite(bo) || !Number.isFinite(bh) || !Number.isFinite(bl) || !Number.isFinite(bc)) continue;
            if (bo <= 0 || bh <= 0 || bl <= 0 || bc <= 0) continue;
            const hi = Math.max(bh, bo, bc);
            const lo = Math.min(bl, bo, bc);
            if (!(hi >= lo)) continue;
            if (
                guardOutliers
                && prevBar
                && Number.isFinite(Number(prevBar?.close))
                && Number(prevBar.close) > 0
            ) {
                const ratio = bc / Number(prevBar.close);
                if (!Number.isFinite(ratio) || ratio <= 0 || ratio > 5.0 || ratio < 0.2) {
                    continue;
                }
            }
            const bar = {
                time: bt,
                open: bo,
                high: hi,
                low: lo,
                close: bc,
                volume: Number.isFinite(bv) && bv > 0 ? bv : 0,
            };
            allBars.push(bar);
            candleSeries.update(bar);
            volumeSeries.update({
                time: bar.time,
                value: bar.volume || 0,
                color: bar.close >= bar.open ? '#26a69a44' : '#ef535044',
            });
            prevBar = bar;
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
    renderQuickOpenTrades(quickOpenTradesState);
    const replayLastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
    if (replayLastBar && Number.isFinite(Number(replayLastBar.close))) {
        void maybeQuickTpAutoClose(Number(replayLastBar.close));
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

function _buildQuickRiskStopLoss(direction, entryPrice, lotSize, riskUsd, symbolLike) {
    const dir = String(direction || '').trim().toUpperCase();
    const px = Number(entryPrice);
    const lots = Number(lotSize);
    const risk = Number(riskUsd);
    if (!Number.isFinite(px)) return NaN;
    if (!Number.isFinite(lots) || lots <= 0) return NaN;
    if (!Number.isFinite(risk) || risk <= 0) return NaN;
    const econ = (sessionSymbolEconomics && typeof sessionSymbolEconomics === 'object') ? sessionSymbolEconomics : null;
    const econSymbol = String(econ?.resolved_symbol || econ?.requested_symbol || '').trim().toUpperCase();
    const reqSymbol = String(symbolLike || '').trim().toUpperCase();
    if (econSymbol && reqSymbol && econSymbol !== reqSymbol) return NaN;
    const valuePer1Lot = Number(econ?.point_value_per_1lot);
    if (!Number.isFinite(valuePer1Lot) || valuePer1Lot <= 0) return NaN;
    const stopDist = risk / (valuePer1Lot * lots);
    if (!Number.isFinite(stopDist) || stopDist <= 0) return NaN;
    const raw = dir === 'SELL' ? px + stopDist : px - stopDist;
    const decimals = getPriceDecimalsForSymbol(symbolLike);
    return Number(raw.toFixed(decimals));
}

async function _ensureQuickTradeSymbolContext(symbolLike) {
    const nextSymbol = String(symbolLike || '').trim().toUpperCase();
    if (!nextSymbol) return false;
    const simSymbolEl = document.getElementById('sim-symbol');
    if (!simSymbolEl) return false;
    const current = String(simSymbolEl.value || '').trim().toUpperCase();
    if (current === nextSymbol) return true;

    if (!setSelectValueCaseInsensitive(simSymbolEl, nextSymbol)) {
        showStatus(`Quick Entry symbol unavailable: ${nextSymbol}`, 'warning');
        return false;
    }

    updateCostModelHint();
    const spreadEl = document.getElementById('cost-model-spread');
    if (spreadEl && (!spreadEl.value || Number.isNaN(Number(spreadEl.value)))) {
        spreadEl.value = String(getDefaultSpreadForSymbol(getCostModelSymbol()));
    }

    if (getWorkbenchMode() === 'live' && (liveFeedActive || liveFeedRequested)) {
        await autoSwitchLiveContextFromInputs('quick entry symbol');
    }
    return true;
}

async function executeQuickTradeFromControls() {
    const symbol = String(document.getElementById('trade-quick-symbol')?.value || document.getElementById('sim-symbol')?.value || '').trim().toUpperCase();
    const direction = String(document.getElementById('trade-quick-direction')?.value || 'BUY').trim().toUpperCase();
    const lotsRaw = Number(document.getElementById('trade-quick-lots')?.value);
    const riskUsdRaw = _parseUiDecimal(document.getElementById('trade-quick-risk-usd')?.value, NaN);
    const tpUsdRaw = _parseUiDecimal(document.getElementById('trade-quick-tp-usd')?.value, NaN);
    const lots = Number.isFinite(lotsRaw) && lotsRaw > 0 ? lotsRaw : 0.01;
    const riskUsd = Number.isFinite(riskUsdRaw) && riskUsdRaw > 0 ? riskUsdRaw : NaN;
    const tpUsd = Number.isFinite(tpUsdRaw) && tpUsdRaw > 0 ? tpUsdRaw : NaN;
    if (!['BUY', 'SELL'].includes(direction)) {
        showStatus('Quick Entry failed: invalid direction.', 'warning');
        return;
    }
    if (isNoProtectionModeEnabled()) {
        const alignedNoProtection = await _ensureQuickTradeSymbolContext(symbol);
        if (!alignedNoProtection) return;
        const openedTrade = await executeTrade(direction, { stop_loss: 0, lot_size: lots, take_profit: 0 });
        if (openedTrade && Number.isFinite(tpUsd) && tpUsd > 0) {
            armQuickTpWatcher(openedTrade, tpUsd);
            showStatus(`Quick TP armed at +$${tpUsd.toFixed(2)} (instant close).`, 'info');
            const lastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
            if (lastBar && Number.isFinite(Number(lastBar.close))) {
                void maybeQuickTpAutoClose(Number(lastBar.close));
            }
        } else if (openedTrade) {
            clearQuickTpWatcher();
        }
        return;
    }
    if (!Number.isFinite(riskUsd) || riskUsd <= 0) {
        showStatus('Quick Entry failed: set a valid Risk $ amount.', 'warning');
        return;
    }
    const aligned = await _ensureQuickTradeSymbolContext(symbol);
    if (!aligned) return;
    const lastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
    const entryPrice = Number(lastBar?.close);
    const autoSl = _buildQuickRiskStopLoss(direction, entryPrice, lots, riskUsd, symbol);
    if (!Number.isFinite(autoSl)) {
        showStatus('Quick Entry failed: symbol economics unavailable for risk-based SL.', 'warning');
        return;
    }
    const slInput = document.getElementById('trade-sl');
    if (slInput) slInput.value = String(autoSl);
    const openedTrade = await executeTrade(direction, { stop_loss: autoSl, lot_size: lots, take_profit: null });
    if (openedTrade && Number.isFinite(tpUsd) && tpUsd > 0) {
        armQuickTpWatcher(openedTrade, tpUsd);
        showStatus(`Quick TP armed at +$${tpUsd.toFixed(2)} (instant close).`, 'info');
        const lastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
        if (lastBar && Number.isFinite(Number(lastBar.close))) {
            void maybeQuickTpAutoClose(Number(lastBar.close));
        }
    } else if (openedTrade) {
        clearQuickTpWatcher();
    }
}

async function executeTrade(direction, options = {}) {
    if (!sessionId) return null;
    const dir = String(direction || '').trim().toUpperCase();
    if (!['BUY', 'SELL'].includes(dir)) { showStatus('Trade error: invalid direction', 'warning'); return null; }
    const noProtection = isNoProtectionModeEnabled();
    const slOverride = Number(options?.stop_loss);
    let sl = Number.isFinite(slOverride) ? slOverride : parseFloat(document.getElementById('trade-sl')?.value);
    const tpLongRaw = parseFloat(document.getElementById('trade-tp-long')?.value);
    const tpShortRaw = parseFloat(document.getElementById('trade-tp-short')?.value);
    const tpLong = Number.isFinite(tpLongRaw) && tpLongRaw > 0 ? tpLongRaw : null;
    const tpShort = Number.isFinite(tpShortRaw) && tpShortRaw > 0 ? tpShortRaw : null;
    const tpOptRaw = options?.take_profit;
    let tp = null;
    if (tpOptRaw === null) {
        tp = null;
    } else if (tpOptRaw === undefined || String(tpOptRaw).trim() === '') {
        tp = dir === 'BUY' ? tpLong : tpShort;
    } else {
        const tpOverride = Number(tpOptRaw);
        tp = Number.isFinite(tpOverride) && tpOverride > 0 ? tpOverride : null;
    }
    const lotsOverride = Number(options?.lot_size);
    const lots = Number.isFinite(lotsOverride) && lotsOverride > 0 ? lotsOverride : (parseFloat(document.getElementById('trade-lots')?.value) || 0.01);

    if (noProtection) {
        sl = 0;
        tp = null;
    }

    if (!Number.isFinite(sl)) { showStatus('Please set a Stop Loss', 'warning'); return null; }
    if (!noProtection && sl <= 0) { showStatus('Stop Loss must be greater than 0', 'warning'); return null; }

    try {
        const lastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
        const costCfg = getCostModelConfigFromUI();
        const body = {
            direction: dir,
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
        applyLiveConfirmationToPayload(body);
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/trade`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
        const data = await res.json();
        if (data.error) { showStatus(`Trade error: ${data.error}`, 'danger'); return null; }

        updateOpenPosition(data, 0);
        void refreshQuickOpenTrades();
        renderCostModelSummary(data?.cost_breakdown || null);
        showStatus(`${dir} @ ${data.entry_price?.toFixed(2)}`, 'success');

        if (allBars.length > 0) {
            const lastBar = allBars[allBars.length - 1];
            tradeMarkers.push({
                time: lastBar.time,
                position: dir === 'BUY' ? 'belowBar' : 'aboveBar',
                color: dir === 'BUY' ? '#26a69a' : '#ef5350',
                shape: dir === 'BUY' ? 'arrowUp' : 'arrowDown',
                text: dir,
            });
            if (tradeMarkers.length > 400) tradeMarkers = tradeMarkers.slice(tradeMarkers.length - 400);
            syncCandleMarkers();
        }
        return data;
    } catch (err) {
        showStatus(`Trade error: ${err.message}`, 'danger');
        return null;
    }
}

async function closePosition(options = null) {
    if (!sessionId) return null;
    const opts = (options && typeof options === 'object' && !(options instanceof Event)) ? options : {};
    const expectedTradeId = Number(opts?.expectedTradeId);
    const tradeIdRaw = document.getElementById('open-pos-id')?.dataset.tradeId;
    const tradeId = Number(tradeIdRaw);
    if (!Number.isFinite(tradeId) || tradeId <= 0) return null;
    if (Number.isFinite(expectedTradeId) && expectedTradeId > 0 && tradeId !== expectedTradeId) {
        return null;
    }

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
        applyLiveConfirmationToPayload(requestBody, { force: true });
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/close-trade/${tradeIdRaw}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(requestBody),
        });
        const data = await res.json();
        if (data.error) { showStatus(`Close error: ${data.error}`, 'danger'); return null; }
        updateOpenPosition(null);
        void refreshQuickOpenTrades();
        addTradeToLog(data);
        showTradeResult(data);
        return data;
    } catch (err) {
        showStatus(`Close error: ${err.message}`, 'danger');
        return null;
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

function _normalizeStrategyBacktestMarker(row) {
    if (!row || typeof row !== 'object') return null;
    const t = Number(row.time);
    if (!Number.isFinite(t) || t <= 0) return null;
    const positionRaw = String(row.position || '').trim();
    const shapeRaw = String(row.shape || '').trim();
    return {
        time: Math.floor(t),
        position: positionRaw || 'aboveBar',
        shape: shapeRaw || 'circle',
        color: String(row.color || '#94a3b8'),
        text: String(row.text || ''),
    };
}

function syncStrategyBacktestModeControls() {
    const strategy = String(document.getElementById('strategy-backtest-strategy')?.value || 'deadzone_pro').trim().toLowerCase();
    const wrap = document.getElementById('strategy-backtest-deadzone-mode-wrap');
    const modeEl = document.getElementById('strategy-backtest-deadzone-mode');
    const isDeadzone = strategy === 'deadzone_pro';
    if (wrap) wrap.style.display = isDeadzone ? '' : 'none';
    if (!isDeadzone && modeEl) modeEl.value = 'default';
}

function renderStrategyBacktestSummary(data) {
    const sourceEl = document.getElementById('strategy-backtest-summary-source');
    const bodyEl = document.getElementById('strategy-backtest-summary-body');
    const badgeEl = document.getElementById('strategy-backtest-trade-count');
    const profitEl = document.getElementById('strategy-backtest-kpi-profit');
    const lossEl = document.getElementById('strategy-backtest-kpi-loss');
    const netEl = document.getElementById('strategy-backtest-kpi-net');
    const pfEl = document.getElementById('strategy-backtest-kpi-pf');
    if (!sourceEl || !bodyEl || !badgeEl) return;

    const setKpiDefaults = () => {
        if (profitEl) profitEl.textContent = '-';
        if (lossEl) lossEl.textContent = '-';
        if (netEl) netEl.textContent = '-';
        if (pfEl) pfEl.textContent = '-';
    };

    if (!data || typeof data !== 'object') {
        sourceEl.textContent = 'idle';
        bodyEl.textContent = 'Run "Show Results" to draw entry/exit markers and summary.';
        badgeEl.textContent = '0';
        badgeEl.classList.add('d-none');
        setKpiDefaults();
        return;
    }

    const summary = (data.summary && typeof data.summary === 'object') ? data.summary : {};
    const tradesTotal = Number(summary.trades_total || 0);
    const closedTrades = Number(summary.closed_trades || 0);
    const openTrades = Number(summary.open_trades || 0);
    const wins = Number(summary.wins || 0);
    const losses = Number(summary.losses || 0);
    const winRate = Number(summary.win_rate_pct || 0);
    const totalPct = Number(summary.total_pnl_pct || 0);
    const avgPct = Number(summary.avg_pnl_pct || 0);
    const maxWin = Number(summary.max_win_pct || 0);
    const maxLoss = Number(summary.max_loss_pct || 0);
    const barsEvaluated = Number(data.bars_evaluated || 0);
    const source = String(data.scan_source || 'unknown');
    const dzMode = String(data.deadzone_mode || 'default');
    sourceEl.textContent = `${source} | ${barsEvaluated} bars${data.strategy === 'deadzone_pro' ? ` | mode ${dzMode}` : ''}`;
    bodyEl.innerHTML = [
        `Trades: <b>${tradesTotal}</b> (closed ${closedTrades}, open ${openTrades})`,
        `Wins/Losses: <b>${wins}/${losses}</b> | Win Rate: <b>${winRate.toFixed(2)}%</b>`,
        `Total PnL: <b>${totalPct.toFixed(2)}%</b> | Avg/Trade: <b>${avgPct.toFixed(2)}%</b>`,
        `Best/Worst: <b>${maxWin.toFixed(2)}%</b> / <b>${maxLoss.toFixed(2)}%</b>`,
    ].join('<br>');
    badgeEl.textContent = String(tradesTotal);
    badgeEl.classList.toggle('d-none', tradesTotal <= 0);

    const trades = Array.isArray(data.trades) ? data.trades : [];
    const closedTradesList = trades.filter((t) => String(t?.status || '').toLowerCase() === 'closed');
    const grossProfitPct = closedTradesList.reduce((acc, t) => {
        const v = Number(t?.pnl_pct || 0);
        return acc + (Number.isFinite(v) && v > 0 ? v : 0);
    }, 0);
    const grossLossPct = closedTradesList.reduce((acc, t) => {
        const v = Number(t?.pnl_pct || 0);
        return acc + (Number.isFinite(v) && v < 0 ? v : 0);
    }, 0);
    const grossProfitPts = closedTradesList.reduce((acc, t) => {
        const v = Number(t?.pnl_points || 0);
        return acc + (Number.isFinite(v) && v > 0 ? v : 0);
    }, 0);
    const grossLossPts = closedTradesList.reduce((acc, t) => {
        const v = Number(t?.pnl_points || 0);
        return acc + (Number.isFinite(v) && v < 0 ? v : 0);
    }, 0);
    const netPctKpi = Number.isFinite(totalPct) ? totalPct : (grossProfitPct + grossLossPct);
    const netPtsKpi = grossProfitPts + grossLossPts;
    let pfText = '-';
    if (Math.abs(grossLossPct) > 1e-9) {
        pfText = (grossProfitPct / Math.abs(grossLossPct)).toFixed(2);
    } else if (grossProfitPct > 0) {
        pfText = '∞';
    } else {
        pfText = '0.00';
    }
    if (profitEl) profitEl.textContent = `${grossProfitPct.toFixed(2)}% | ${grossProfitPts.toFixed(2)} pts`;
    if (lossEl) lossEl.textContent = `${grossLossPct.toFixed(2)}% | ${grossLossPts.toFixed(2)} pts`;
    if (netEl) netEl.textContent = `${netPctKpi.toFixed(2)}% | ${netPtsKpi.toFixed(2)} pts`;
    if (pfEl) pfEl.textContent = pfText;
}

function clearStrategyBacktestOverlay(showToast = true) {
    strategyBacktestMarkers = [];
    if (!toolStates.strategy_backtest) toolStates.strategy_backtest = {};
    toolStates.strategy_backtest.last_result = null;
    syncCandleMarkers();
    renderStrategyBacktestSummary(null);
    if (showToast) showStatus('Strategy backtest overlay cleared', 'info');
}

async function runStrategyBacktestOverlay() {
    if (!sessionId) {
        showStatus('Start a session first', 'warning');
        return;
    }
    const strategy = String(document.getElementById('strategy-backtest-strategy')?.value || 'deadzone_pro').trim().toLowerCase();
    const deadzoneModeRaw = String(document.getElementById('strategy-backtest-deadzone-mode')?.value || 'default').trim().toLowerCase();
    const deadzoneMode = (strategy === 'deadzone_pro' && ['default', 'advanced', 'rsi_adaptive', 'rsi_quant', 'rsi_quant_sell_only'].includes(deadzoneModeRaw))
        ? deadzoneModeRaw
        : 'default';
    const lookbackRaw = Number(document.getElementById('strategy-backtest-lookback-days')?.value || 30);
    const lookbackDays = Number.isFinite(lookbackRaw) ? Math.max(0.1, Math.min(365, lookbackRaw)) : 30;
    const forceFirstEntry = !!document.getElementById('strategy-backtest-force-first-entry')?.checked;
    const chartSymbol = getCostModelSymbol();
    const chartTimeframe = getChartTimeframe();

    let srcBars = Array.isArray(allBars) ? allBars.slice() : [];
    srcBars = trimBarsByLookbackDays(srcBars, lookbackDays);
    const barsPayload = barsToPayload(srcBars, 12000, 3);
    if (!barsPayload || barsPayload.length < 3) {
        showStatus('Not enough chart bars for backtest overlay. Increase window or load more history.', 'warning');
        return;
    }

    if (!toolStates.strategy_backtest) toolStates.strategy_backtest = {};
    toolStates.strategy_backtest.strategy = strategy;
    toolStates.strategy_backtest.deadzone_mode = deadzoneMode;
    toolStates.strategy_backtest.lookback_days = lookbackDays;
    toolStates.strategy_backtest.force_first_entry = forceFirstEntry;

    try {
        showStatus('Running strategy backtest overlay...', 'info');
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/tools/strategy/backtest-overlay`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                strategy,
                deadzone_mode: deadzoneMode,
                symbol: chartSymbol,
                timeframe: chartTimeframe,
                lookback_days: lookbackDays,
                force_first_entry: forceFirstEntry,
                closed_bar_only: false,
                include_open_trade: true,
                max_eval_bars: 6000,
                bars: barsPayload,
            }),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            throw new Error(String(data?.error || data?.detail || `HTTP ${res.status}`));
        }
        const rawMarkers = Array.isArray(data?.markers) ? data.markers : [];
        strategyBacktestMarkers = rawMarkers
            .map(_normalizeStrategyBacktestMarker)
            .filter((m) => !!m);
        if (strategyBacktestMarkers.length > 5000) {
            strategyBacktestMarkers = strategyBacktestMarkers.slice(strategyBacktestMarkers.length - 5000);
        }
        syncCandleMarkers();
        toolStates.strategy_backtest.last_result = data;
        renderStrategyBacktestSummary(data);
        const tradeCount = Number(data?.summary?.trades_total || 0);
        const pnlPct = Number(data?.summary?.total_pnl_pct || 0);
        showStatus(
            `Overlay ready: ${strategy} | trades ${tradeCount} | total ${pnlPct.toFixed(2)}%`,
            tradeCount > 0 ? 'success' : 'info',
        );
    } catch (err) {
        showStatus(`Backtest overlay error: ${err.message}`, 'danger');
    }
}


// â”€â”€ UI Updates â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function clearOpenPositionProtectionLines() {
    if (!candleSeries) return;
    if (openPositionSlLine) {
        try { candleSeries.removePriceLine(openPositionSlLine); } catch (_) { /* ignore */ }
        openPositionSlLine = null;
    }
    if (openPositionTpLine) {
        try { candleSeries.removePriceLine(openPositionTpLine); } catch (_) { /* ignore */ }
        openPositionTpLine = null;
    }
}

function renderOpenPositionProtectionLines(pos) {
    clearOpenPositionProtectionLines();
    if (!candleSeries || !pos || typeof pos !== 'object') return;
    const sl = Number(pos.stop_loss);
    const tp = Number(pos.take_profit);
    if (Number.isFinite(sl) && sl > 0) {
        try {
            openPositionSlLine = candleSeries.createPriceLine({
                price: sl,
                color: '#ef5350',
                lineWidth: 2,
                lineStyle: 2,
                axisLabelVisible: true,
                title: 'SL',
            });
        } catch (_) { /* ignore */ }
    }
    if (Number.isFinite(tp) && tp > 0) {
        try {
            openPositionTpLine = candleSeries.createPriceLine({
                price: tp,
                color: '#26a69a',
                lineWidth: 2,
                lineStyle: 2,
                axisLabelVisible: true,
                title: 'TP',
            });
        } catch (_) { /* ignore */ }
    }
}

function _extractOpenTradePnl(pos) {
    if (!pos || typeof pos !== 'object') return null;
    const candidates = [
        pos.profit_loss,
        pos.pnl,
        pos.profit,
        pos.unrealized_pnl,
        pos.open_pnl,
    ];
    for (const c of candidates) {
        const n = Number(c);
        if (Number.isFinite(n)) return n;
    }
    return null;
}

function _estimateOpenTradePnl(pos) {
    if (!pos || typeof pos !== 'object') return null;
    const direction = String(pos.direction || '').trim().toUpperCase();
    const entry = Number(pos.entry_price);
    const lots = Number(pos.lot_size);
    if (!Number.isFinite(entry) || entry <= 0 || !Number.isFinite(lots) || lots <= 0) return null;

    const lastBar = Array.isArray(allBars) && allBars.length > 0 ? allBars[allBars.length - 1] : null;
    const current = Number(pos.current_price);
    const px = Number.isFinite(current) && current > 0 ? current : Number(lastBar?.close);
    if (!Number.isFinite(px) || px <= 0) return null;

    const pointValue = Number(sessionSymbolEconomics?.point_value_per_1lot);
    if (!Number.isFinite(pointValue) || pointValue <= 0) return null;

    const delta = direction === 'SELL' ? (entry - px) : (px - entry);
    if (!Number.isFinite(delta)) return null;
    return delta * pointValue * lots;
}

function _quickTradeCloseKey(row) {
    const sessionTradeId = Number(row?.session_trade_id);
    if (Number.isFinite(sessionTradeId) && sessionTradeId > 0) {
        return `session:${Math.trunc(sessionTradeId)}`;
    }
    const ticket = Number(row?.ticket ?? row?.id);
    if (Number.isFinite(ticket) && ticket > 0) {
        return `ticket:${Math.trunc(ticket)}`;
    }
    return `row:${Math.random().toString(36).slice(2, 8)}`;
}

async function quickCloseOpenTrade(rowLike) {
    const row = (rowLike && typeof rowLike === 'object') ? rowLike : null;
    if (!row || !sessionId) return;
    const closeKey = _quickTradeCloseKey(row);
    if (quickCloseInFlightKeys.has(closeKey)) return;
    quickCloseInFlightKeys.add(closeKey);
    try {
        const sessionTradeId = Number(row.session_trade_id);
        if (Number.isFinite(sessionTradeId) && sessionTradeId > 0) {
            const body = {};
            applyLiveConfirmationToPayload(body, { force: true });
            const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/close-trade/${sessionTradeId}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
            });
            const data = await res.json().catch(() => ({}));
            if (!res.ok || data?.error) {
                showStatus(`Close error: ${data?.error || data?.detail || res.status}`, 'danger');
                return;
            }
            const openPosId = Number(document.getElementById('open-pos-id')?.dataset.tradeId || 0);
            if (Number.isFinite(openPosId) && openPosId === sessionTradeId) {
                updateOpenPosition(null);
            }
            addTradeToLog(data);
            showTradeResult(data);
            showStatus(`Trade #${sessionTradeId} closed.`, 'success');
            void refreshQuickOpenTrades();
            return;
        }

        const ticket = Number(row.ticket ?? row.id);
        const symbol = String(row.symbol || document.getElementById('sim-symbol')?.value || '').trim().toUpperCase();
        if (!Number.isFinite(ticket) || ticket <= 0 || !symbol) {
            showStatus('Quick close failed: invalid broker ticket/symbol.', 'warning');
            return;
        }
        const body = {
            ticket: Math.trunc(ticket),
            symbol,
            lot_size: Number.isFinite(Number(row.lot_size)) ? Number(row.lot_size) : null,
        };
        applyLiveConfirmationToPayload(body, { force: true });
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/close-broker-position`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.error) {
            showStatus(`Broker close error: ${data?.error || data?.detail || res.status}`, 'danger');
            return;
        }
        showStatus(`Broker position closed: ${symbol} #${Math.trunc(ticket)}`, 'success');
        void refreshQuickOpenTrades();
    } catch (err) {
        showStatus(`Quick close error: ${err?.message || err}`, 'danger');
    } finally {
        quickCloseInFlightKeys.delete(closeKey);
        renderQuickOpenTrades(quickOpenTradesState);
    }
}

function renderQuickOpenTrades(positionsLike) {
    const listEl = document.getElementById('quick-open-trades-list');
    const summaryEl = document.getElementById('quick-open-trades-summary');
    if (!listEl || !summaryEl) return;

    const rows = Array.isArray(positionsLike) ? positionsLike.filter((x) => x && typeof x === 'object') : [];
    if (!rows.length) {
        listEl.innerHTML = '<div class="fvg-empty mb-0">No open trades.</div>';
        summaryEl.textContent = 'No open trades';
        return;
    }

    let pnlKnownCount = 0;
    let pnlTotal = 0;
    const html = rows.map((row) => {
        const symbol = String(row.symbol || document.getElementById('sim-symbol')?.value || '').toUpperCase() || '-';
        const direction = String(row.direction || '').toUpperCase();
        const dirClass = direction === 'BUY' ? 'buy' : (direction === 'SELL' ? 'sell' : '');
        const lots = Number(row.lot_size);
        const entry = Number(row.entry_price);
        const current = Number(row.current_price);

        let pnl = _extractOpenTradePnl(row);
        if (!Number.isFinite(Number(pnl))) {
            pnl = _estimateOpenTradePnl(row);
        }
        const hasPnl = Number.isFinite(Number(pnl));
        if (hasPnl) {
            pnlKnownCount += 1;
            pnlTotal += Number(pnl);
        }
        const pnlVal = Number(pnl);
        const pnlClass = hasPnl ? (pnlVal >= 0 ? 'positive' : 'negative') : '';
        const pnlText = hasPnl ? `${pnlVal >= 0 ? '+' : ''}$${pnlVal.toFixed(2)}` : 'n/a';

        const entryTxt = Number.isFinite(entry) ? entry.toFixed(2) : '-';
        const currentTxt = Number.isFinite(current) ? current.toFixed(2) : '-';
        const sl = Number(row.stop_loss);
        const tp = Number(row.take_profit);
        const slTxt = Number.isFinite(sl) && sl > 0 ? sl.toFixed(2) : '-';
        const tpTxt = Number.isFinite(tp) && tp > 0 ? tp.toFixed(2) : '-';
        const lotsTxt = Number.isFinite(lots) ? lots.toFixed(2) : '-';
        const closeKey = _quickTradeCloseKey(row);
        const inFlight = quickCloseInFlightKeys.has(closeKey);
        const sessionTradeId = Number(row.session_trade_id);
        const ticket = Number(row.ticket ?? row.id);
        return `
            <div class="quick-open-trade-row">
                <div class="quick-open-trade-top">
                    <span>
                        <span class="quick-open-trade-symbol">${escapeHtml(symbol)}</span>
                        <span class="quick-open-trade-dir ${dirClass} ms-1">${escapeHtml(direction || '-')}</span>
                    </span>
                    <span style="display:flex;align-items:center;gap:6px;">
                        <span class="quick-open-trade-pnl ${pnlClass}">${escapeHtml(pnlText)}</span>
                        <button
                            type="button"
                            class="btn btn-sm btn-outline-danger py-0 px-2"
                            data-quick-close="1"
                            data-session-trade-id="${Number.isFinite(sessionTradeId) ? Math.trunc(sessionTradeId) : 0}"
                            data-ticket="${Number.isFinite(ticket) ? Math.trunc(ticket) : 0}"
                            data-symbol="${escapeHtml(symbol)}"
                            data-lot-size="${Number.isFinite(lots) ? lots : ''}"
                            data-close-key="${escapeHtml(closeKey)}"
                            ${inFlight ? 'disabled' : ''}
                        >
                            ${inFlight ? '...' : 'Kapat'}
                        </button>
                    </span>
                </div>
                <div class="quick-open-trade-meta">
                    Lots: ${escapeHtml(lotsTxt)} | Entry: ${escapeHtml(entryTxt)} | Current: ${escapeHtml(currentTxt)} | SL: ${escapeHtml(slTxt)} | TP: ${escapeHtml(tpTxt)}
                </div>
            </div>
        `;
    }).join('');

    listEl.innerHTML = html;
    if (pnlKnownCount > 0) {
        const totalTxt = `${pnlTotal >= 0 ? '+' : ''}$${pnlTotal.toFixed(2)}`;
        summaryEl.textContent = `${rows.length} open | total ${totalTxt}`;
    } else {
        summaryEl.textContent = `${rows.length} open`;
    }
}

async function refreshQuickOpenTrades() {
    if (!sessionId) {
        quickOpenTradesState = [];
        renderQuickOpenTrades([]);
        return;
    }
    if (quickOpenTradesInFlight) return;
    quickOpenTradesInFlight = true;
    try {
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/open-positions?limit=40`);
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            return;
        }
        const positions = Array.isArray(data?.open_positions) ? data.open_positions : [];
        quickOpenTradesState = positions;
        renderQuickOpenTrades(quickOpenTradesState);
    } catch (_) {
        // Silent by design: polling should not spam status line.
    } finally {
        quickOpenTradesInFlight = false;
    }
}

function startQuickOpenTradesPoller() {
    if (quickOpenTradesPollTimer) {
        clearInterval(quickOpenTradesPollTimer);
        quickOpenTradesPollTimer = null;
    }
    quickOpenTradesPollTimer = setInterval(() => {
        void refreshQuickOpenTrades();
    }, QUICK_OPEN_TRADES_POLL_MS);
    void refreshQuickOpenTrades();
}

function stopQuickOpenTradesPoller() {
    if (quickOpenTradesPollTimer) {
        clearInterval(quickOpenTradesPollTimer);
        quickOpenTradesPollTimer = null;
    }
}

function updateOpenPosition(pos, pnl) {
    const container = document.getElementById('open-position-display');
    const idEl = document.getElementById('open-pos-id');
    const closeBtn = document.getElementById('btn-close-pos');
    const tradeButtons = document.getElementById('trade-buttons');
    if (!container) return;

    if (pos) {
        currentOpenPositionState = { ...pos };
        renderOpenPositionProtectionLines(pos);
        const openTradeId = Number(pos?.id);
        if (
            Number.isFinite(Number(quickTpTradeId))
            && Number(quickTpTradeId) > 0
            && Number.isFinite(openTradeId)
            && openTradeId > 0
            && openTradeId !== Number(quickTpTradeId)
        ) {
            clearQuickTpWatcher();
        }
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
        currentOpenPositionState = null;
        clearOpenPositionProtectionLines();
        clearQuickTpWatcher();
        container.innerHTML = '';
        container.classList.add('d-none');
        if (closeBtn) closeBtn.classList.add('d-none');
        if (tradeButtons) tradeButtons.classList.remove('d-none');
    }
    renderQuickOpenTrades(quickOpenTradesState);
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

function _normalizeSessionLiveControl(liveControlLike) {
    const raw = (liveControlLike && typeof liveControlLike === 'object') ? liveControlLike : {};
    const sourceRaw = String(raw.source || 'mt5').trim().toLowerCase();
    const source = (sourceRaw === 'databento') ? 'databento' : 'mt5';
    const modeRaw = String(raw.execution_mode || 'paper').trim().toLowerCase();
    const executionMode = modeRaw === 'live_mt5' ? 'live_mt5' : 'paper';
    const maxRiskRaw = Number(raw.max_risk_per_trade_usd);
    const maxLotRaw = Number(raw.max_lot_per_trade);
    const dailyLossRaw = (raw.daily_loss_limit_usd === null || raw.daily_loss_limit_usd === undefined || raw.daily_loss_limit_usd === '')
        ? null
        : Number(raw.daily_loss_limit_usd);
    return {
        enabled: Boolean(raw.enabled ?? true),
        source,
        backend_native: Boolean(raw.backend_native ?? (source === 'mt5')),
        use_active_account: Boolean(raw.use_active_account ?? (source === 'mt5')),
        execution_mode: executionMode,
        kill_switch_enabled: Boolean(raw.kill_switch_enabled ?? false),
        max_risk_per_trade_usd: Number.isFinite(maxRiskRaw) ? Math.max(0, Math.min(1_000_000_000, maxRiskRaw)) : 25.0,
        max_lot_per_trade: Number.isFinite(maxLotRaw) ? Math.max(0, Math.min(100, maxLotRaw)) : 5.0,
        daily_loss_limit_usd: Number.isFinite(dailyLossRaw) ? Math.max(0, Math.min(1_000_000_000, dailyLossRaw)) : null,
        require_confirmation_for_live_order: Boolean(raw.require_confirmation_for_live_order ?? true),
    };
}

function syncSessionLiveControlInputs() {
    const modeEl = document.getElementById('agent-live-execution-mode');
    const killEl = document.getElementById('agent-live-kill-switch');
    const confirmEl = document.getElementById('agent-live-require-confirmation');
    const mode = String(modeEl?.value || 'paper').trim().toLowerCase();
    const isLive = mode === 'live_mt5';
    if (killEl) killEl.disabled = !isLive;
    if (confirmEl) confirmEl.disabled = !isLive;
}

function renderSessionLiveControlUI(liveControlLike = null, liveAccountLike = null) {
    if (liveControlLike && typeof liveControlLike === 'object') {
        sessionLiveControlState = _normalizeSessionLiveControl(liveControlLike);
    } else if (!sessionLiveControlState) {
        sessionLiveControlState = _normalizeSessionLiveControl({ execution_mode: 'paper' });
    }
    if (liveAccountLike && typeof liveAccountLike === 'object') {
        sessionLiveAccountState = { ...liveAccountLike };
    }
    const cfg = sessionLiveControlState || _normalizeSessionLiveControl({ execution_mode: 'paper' });
    const modeEl = document.getElementById('agent-live-execution-mode');
    const killEl = document.getElementById('agent-live-kill-switch');
    const riskEl = document.getElementById('agent-live-max-risk-per-trade');
    const lotEl = document.getElementById('agent-live-max-lot-per-trade');
    const dailyEl = document.getElementById('agent-live-daily-loss-limit');
    const confirmEl = document.getElementById('agent-live-require-confirmation');
    if (modeEl) modeEl.value = String(cfg.execution_mode || 'paper');
    if (killEl) killEl.checked = Boolean(cfg.kill_switch_enabled);
    if (riskEl) riskEl.value = String(Number(cfg.max_risk_per_trade_usd || 0));
    if (lotEl) lotEl.value = String(Number(cfg.max_lot_per_trade || 0));
    if (dailyEl) dailyEl.value = (cfg.daily_loss_limit_usd === null || cfg.daily_loss_limit_usd === undefined) ? '' : String(Number(cfg.daily_loss_limit_usd));
    if (confirmEl) confirmEl.checked = Boolean(cfg.require_confirmation_for_live_order);
    syncSessionLiveControlInputs();

    const statusEl = document.getElementById('agent-live-control-status');
    if (statusEl) {
        const isLive = String(cfg.execution_mode || 'paper') === 'live_mt5';
        const accountLogin = sessionLiveAccountState && sessionLiveAccountState.login !== undefined ? String(sessionLiveAccountState.login) : '';
        const accountBalanceRaw = sessionLiveAccountState ? Number(sessionLiveAccountState.balance) : NaN;
        const accountBalance = Number.isFinite(accountBalanceRaw) ? accountBalanceRaw : null;
        const dailyLossTxt = cfg.daily_loss_limit_usd === null ? 'disabled' : `$${Number(cfg.daily_loss_limit_usd).toFixed(2)}`;
        if (!isLive) {
            statusEl.style.color = '#93c5fd';
            statusEl.textContent = `Execution: PAPER | Source: ${String(cfg.source || 'mt5').toUpperCase()} | Live safety stored (risk cap $${Number(cfg.max_risk_per_trade_usd).toFixed(2)}, lot cap ${Number(cfg.max_lot_per_trade).toFixed(2)}).`;
        } else if (cfg.kill_switch_enabled) {
            statusEl.style.color = '#fca5a5';
            statusEl.textContent = `Execution: LIVE MT5 (KILL SWITCH ON) | Caps: risk $${Number(cfg.max_risk_per_trade_usd).toFixed(2)}, lot ${Number(cfg.max_lot_per_trade).toFixed(2)}, daily loss ${dailyLossTxt} | confirm=${cfg.require_confirmation_for_live_order ? 'required' : 'off'}`;
        } else {
            statusEl.style.color = '#86efac';
            statusEl.textContent = `Execution: LIVE MT5 armed | Caps: risk $${Number(cfg.max_risk_per_trade_usd).toFixed(2)}, lot ${Number(cfg.max_lot_per_trade).toFixed(2)}, daily loss ${dailyLossTxt} | confirm=${cfg.require_confirmation_for_live_order ? 'required' : 'off'}${accountLogin ? ` | account #${accountLogin}${accountBalance !== null ? ` bal $${accountBalance.toFixed(2)}` : ''}` : ''}`;
        }
    }
    renderExecutionModeBadge();
}

function setSessionLiveExecutionModeFromLiveControl(liveControlLike, liveAccountLike = null) {
    const normalized = _normalizeSessionLiveControl(liveControlLike);
    sessionLiveExecutionMode = String(normalized.execution_mode || 'paper');
    sessionLiveControlState = normalized;
    renderSessionLiveControlUI(normalized, liveAccountLike);
}

function isSessionLiveMt5Execution() {
    return String(sessionLiveExecutionMode || '').toLowerCase() === 'live_mt5';
}

function applyLiveConfirmationToPayload(payloadLike, opts = {}) {
    const payload = (payloadLike && typeof payloadLike === 'object') ? payloadLike : {};
    const force = !!opts.force;
    if (!force && !isSessionLiveMt5Execution()) return payload;
    payload.confirm_live_order = true;
    payload.live_confirmation_phrase = LIVE_CONFIRMATION_PHRASE;
    return payload;
}

async function setSessionLiveControl(enabled, source = 'mt5', overrides = null) {
    if (!sessionId) return { ok: false, error: 'No active session' };
    try {
        const payload = {
            enabled: !!enabled,
            source: String(source || 'mt5').toLowerCase(),
            backend_native: String(source || 'mt5').toLowerCase() === 'mt5' && !!enabled,
        };
        if (overrides && typeof overrides === 'object') {
            if (overrides.source !== undefined) payload.source = String(overrides.source || payload.source).toLowerCase();
            if (overrides.backend_native !== undefined) payload.backend_native = Boolean(overrides.backend_native);
            if (overrides.use_active_account !== undefined) payload.use_active_account = Boolean(overrides.use_active_account);
            if (overrides.execution_mode !== undefined) payload.execution_mode = String(overrides.execution_mode || '').trim().toLowerCase();
            if (overrides.kill_switch_enabled !== undefined) payload.kill_switch_enabled = Boolean(overrides.kill_switch_enabled);
            if (overrides.max_risk_per_trade_usd !== undefined) payload.max_risk_per_trade_usd = Number(overrides.max_risk_per_trade_usd);
            if (overrides.max_lot_per_trade !== undefined) payload.max_lot_per_trade = Number(overrides.max_lot_per_trade);
            if (overrides.daily_loss_limit_usd !== undefined) payload.daily_loss_limit_usd = overrides.daily_loss_limit_usd;
            if (overrides.require_confirmation_for_live_order !== undefined) {
                payload.require_confirmation_for_live_order = Boolean(overrides.require_confirmation_for_live_order);
            }
        }
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/live-control`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || data?.ok === false) {
            return { ok: false, error: String(data?.detail || data?.error || `HTTP ${res.status}`) };
        }
        setSessionLiveExecutionModeFromLiveControl(data?.live_control || null, data?.live_account || null);
        renderSymbolEconomicsHint(data?.symbol_economics || null);
        const initBal = Number(data?.initial_balance);
        const curBal = Number(data?.current_balance);
        if (Number.isFinite(initBal)) {
            initialBalance = initBal;
            const balEl = document.getElementById('sim-balance');
            if (balEl) balEl.value = String(initBal);
        }
        if (Number.isFinite(curBal)) {
            updateStats({ balance: curBal, current_balance: curBal });
        }
        return { ok: true, data };
    } catch (err) {
        return { ok: false, error: String(err?.message || err || 'live control update failed') };
    }
}

function _collectLiveControlOverridesFromUI() {
    const modeEl = document.getElementById('agent-live-execution-mode');
    const killEl = document.getElementById('agent-live-kill-switch');
    const riskEl = document.getElementById('agent-live-max-risk-per-trade');
    const lotEl = document.getElementById('agent-live-max-lot-per-trade');
    const dailyEl = document.getElementById('agent-live-daily-loss-limit');
    const confirmEl = document.getElementById('agent-live-require-confirmation');
    const executionMode = String(modeEl?.value || 'paper').trim().toLowerCase() === 'live_mt5' ? 'live_mt5' : 'paper';
    const baseCfg = _normalizeSessionLiveControl(sessionLiveControlState || { execution_mode: executionMode });
    const maxRiskRaw = _parseUiDecimal(riskEl?.value, Number(baseCfg.max_risk_per_trade_usd || 0));
    const maxLotRaw = _parseUiDecimal(lotEl?.value, Number(baseCfg.max_lot_per_trade || 0));
    const dailyRawText = String(dailyEl?.value || '').trim();
    const dailyRaw = dailyRawText === ''
        ? null
        : _parseUiDecimal(dailyRawText, baseCfg.daily_loss_limit_usd === null ? null : Number(baseCfg.daily_loss_limit_usd));
    const maxRisk = Number.isFinite(maxRiskRaw) ? Math.max(0, Math.min(1_000_000_000, maxRiskRaw)) : Number(baseCfg.max_risk_per_trade_usd || 0);
    const maxLot = Number.isFinite(maxLotRaw) ? Math.max(0, Math.min(100, maxLotRaw)) : Number(baseCfg.max_lot_per_trade || 0);
    const dailyLoss = (dailyRaw === null || !Number.isFinite(dailyRaw))
        ? null
        : Math.max(0, Math.min(1_000_000_000, dailyRaw));
    const sourceFromUI = getSelectedLiveSource();
    const source = executionMode === 'live_mt5' ? 'mt5' : sourceFromUI;
    return {
        source,
        execution_mode: executionMode,
        use_active_account: source === 'mt5',
        backend_native: source === 'mt5',
        kill_switch_enabled: Boolean(killEl?.checked),
        max_risk_per_trade_usd: maxRisk,
        max_lot_per_trade: maxLot,
        daily_loss_limit_usd: dailyLoss,
        require_confirmation_for_live_order: Boolean(confirmEl?.checked),
    };
}

async function applySessionLiveControlFromUI(opts = {}) {
    if (!sessionId) {
        showStatus('Start or select a session first.', 'warning');
        return;
    }
    const forceMode = String(opts?.forceMode || '').trim().toLowerCase();
    const modeEl = document.getElementById('agent-live-execution-mode');
    if (modeEl && (forceMode === 'paper' || forceMode === 'live_mt5')) {
        modeEl.value = forceMode;
    }
    syncSessionLiveControlInputs();
    const overrides = _collectLiveControlOverridesFromUI();
    const enabled = true;
    const res = await setSessionLiveControl(enabled, String(overrides.source || 'mt5'), overrides);
    if (!res?.ok) {
        showStatus(`Execution settings apply failed: ${res?.error || 'unknown error'}`, 'danger');
        return;
    }
    const modeTxt = String(overrides.execution_mode || 'paper').toUpperCase();
    showStatus(`Execution settings applied (${modeTxt})`, 'success');
}

async function handleAgentToolStateResponse(response, eventType = 'TOOL_SIGNAL_CHANGED') {
    const data = await response.json().catch(() => ({}));
    if (!response.ok || data?.ok === false) {
        const msg = String(data?.detail || data?.error || `HTTP ${response.status}`);
        showStatus(`Agent ${String(eventType || '').toUpperCase()} sync failed: ${msg}`, 'warning');
        return data;
    }
    const tick = data?.live_tick_trigger && typeof data.live_tick_trigger === 'object' ? data.live_tick_trigger : null;
    const eventTypes = Array.isArray(tick?.trigger_event_types) ? tick.trigger_event_types.map(v => String(v || '').toUpperCase()) : [];
    if (tick && tick.ok === false) {
        showStatus(`Trigger processing failed: ${String(tick.error || 'unknown error')}`, 'danger');
    } else if (tick && Number(tick.trigger_events_count || 0) > 0) {
        let type = 'info';
        if (eventTypes.some(v => v.includes('FAILED'))) type = 'danger';
        else if (eventTypes.some(v => v.includes('CANCELED'))) type = 'warning';
        else if (eventTypes.some(v => v.includes('EXECUTED'))) type = 'success';
        const label = eventTypes.join(', ') || 'TRIGGER_EVENT';
        showStatus(`Trigger update: ${label}`, type);
        void refreshAgentTriggerList(false);
    }
    return data;
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
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/tool-state`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        await handleAgentToolStateResponse(res, 'LIVE_TICK');
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
        const res = await fetch(`${API_BASE}/api/simulation/sessions/${sessionId}/agent/tool-state`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload),
        });
        await handleAgentToolStateResponse(res, eventType);
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
