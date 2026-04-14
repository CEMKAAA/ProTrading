(function () {
    'use strict';

    const els = {
        alert: document.getElementById('tg-auto-alert'),
        enabled: document.getElementById('tg-enabled'),
        requireConfirm: document.getElementById('tg-require-confirm'),
        waitEntryZone: document.getElementById('tg-wait-entry-zone'),
        requireConfirmChannels: document.getElementById('tg-require-confirm-channels'),
        noConfirmChannels: document.getElementById('tg-no-confirm-channels'),
        channels: document.getElementById('tg-channels'),
        timeframe: document.getElementById('tg-timeframe'),
        lot: document.getElementById('tg-lot'),
        lotModeHint: document.getElementById('tg-lot-mode-hint'),
        modeSummary: document.getElementById('tg-mode-summary'),
        waitEntryZoneHint: document.getElementById('tg-wait-entry-zone-hint'),
        forceSingle01: document.getElementById('tg-force-single-01'),
        allowMessageSingleTradeOverride: document.getElementById('tg-allow-message-single-trade-override'),
        distribution: document.getElementById('tg-distribution'),
        confirmWindow: document.getElementById('tg-confirm-window'),
        evalMode: document.getElementById('tg-eval-mode'),
        aiProvider: document.getElementById('tg-ai-provider'),
        aiModel: document.getElementById('tg-ai-model'),
        aiTimeout: document.getElementById('tg-ai-timeout'),
        saveBtn: document.getElementById('tg-save-btn'),
        refreshBtn: document.getElementById('tg-refresh-btn'),
        pendingCount: document.getElementById('tg-pending-count'),
        activeCount: document.getElementById('tg-active-count'),
        feedCount: document.getElementById('tg-feed-count'),
        feedBody: document.getElementById('tg-feed-body'),
        execLogBody: document.getElementById('tg-exec-log-body'),
        execSourceFilter: document.getElementById('tg-exec-source-filter'),
        execTriggerFilter: document.getElementById('tg-exec-trigger-filter'),
        execTraceSearch: document.getElementById('tg-exec-trace-search'),
        feedSourceFilter: document.getElementById('tg-feed-source-filter'),
        feedKindFilter: document.getElementById('tg-feed-kind-filter'),
        feedSignalsOnly: document.getElementById('tg-feed-signals-only'),
        updated: document.getElementById('tg-status-updated'),
        userEnabled: document.getElementById('tg-ul-enabled'),
        userApiId: document.getElementById('tg-ul-api-id'),
        userApiHash: document.getElementById('tg-ul-api-hash'),
        userSessionPath: document.getElementById('tg-ul-session-path'),
        userChannels: document.getElementById('tg-ul-channels'),
        userPollSec: document.getElementById('tg-ul-poll-sec'),
        userBackfillCount: document.getElementById('tg-ul-backfill-count'),
        userPhone: document.getElementById('tg-ul-phone'),
        userCode: document.getElementById('tg-ul-code'),
        userPassword: document.getElementById('tg-ul-password'),
        userStatusLine: document.getElementById('tg-ul-status-line'),
        userRunState: document.getElementById('tg-ul-run-state'),
        userForwardOk: document.getElementById('tg-ul-forward-ok'),
        userForwardFail: document.getElementById('tg-ul-forward-fail'),
        userFlowLine: document.getElementById('tg-ul-flow-line'),
        userPipelineLine: document.getElementById('tg-ul-pipeline-line'),
        userChannelLine: document.getElementById('tg-ul-channel-line'),
        userSaveBtn: document.getElementById('tg-ul-save-btn'),
        userSendCodeBtn: document.getElementById('tg-ul-send-code-btn'),
        userVerifyBtn: document.getElementById('tg-ul-verify-btn'),
        userStopBtn: document.getElementById('tg-ul-stop-btn')
    };

    let pollTimer = null;
    let mainFormDirty = false;
    let userFormDirty = false;
    let suppressDirtyTracking = false;
    let latestFeedRows = [];
    let latestExecLogs = [];
    let pendingLoginCtx = {
        phoneCodeHash: '',
        pendingSession: ''
    };

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

    function getApiErrorMessage(data, fallback) {
        const d = data || {};
        const result = (d && typeof d.result === 'object') ? d.result : {};
        return String(
            d.error ||
            d.detail ||
            result.error ||
            result.message ||
            fallback ||
            'operation_failed'
        );
    }

    function toLines(list) {
        if (!Array.isArray(list)) return '';
        return list.map((x) => String(x || '').trim()).filter(Boolean).join('\n');
    }

    function fillForm(cfg, opts) {
        const force = !!(opts && opts.force);
        if (!force && mainFormDirty) return;
        const c = cfg || {};
        suppressDirtyTracking = true;
        if (els.enabled) els.enabled.checked = !!c.enabled;
        if (els.requireConfirm) els.requireConfirm.checked = !!c.require_confirm;
        if (els.waitEntryZone) els.waitEntryZone.checked = (c.wait_entry_zone !== false);
        if (els.requireConfirmChannels) els.requireConfirmChannels.value = toLines(c.require_confirm_channels);
        if (els.noConfirmChannels) els.noConfirmChannels.value = toLines(c.no_confirm_channels);
        if (els.channels) els.channels.value = toLines(c.channels);
        if (els.timeframe) els.timeframe.value = String(c.default_timeframe || 'M5');
        if (els.lot) els.lot.value = Number(c.default_lot || 0.05).toFixed(2);
        if (els.forceSingle01) els.forceSingle01.checked = !!c.force_single_trade_01;
        if (els.allowMessageSingleTradeOverride) {
            els.allowMessageSingleTradeOverride.checked = (c.allow_message_single_trade_override !== false);
        }
        if (els.distribution) els.distribution.value = String(c.distribution_mode || 'equal');
        if (els.confirmWindow) els.confirmWindow.value = String(parseInt(c.confirm_window_sec || 1800, 10));
        if (els.evalMode) els.evalMode.value = String(c.evaluation_mode || 'deterministic');
        if (els.aiProvider) els.aiProvider.value = String(c.ai_provider || 'claude');
        if (els.aiModel) els.aiModel.value = String(c.ai_model || '');
        if (els.aiTimeout) els.aiTimeout.value = String(parseInt(c.ai_timeout_sec || 10, 10));
        suppressDirtyTracking = false;
        syncEmergencyLotUi();
    }

    function syncEmergencyLotUi() {
        const isEmergency = !!(els.forceSingle01 && els.forceSingle01.checked);
        const allowMsgOverride = !!(els.allowMessageSingleTradeOverride && els.allowMessageSingleTradeOverride.checked);
        const requireConfirm = !!(els.requireConfirm && els.requireConfirm.checked);
        if (els.lotModeHint) {
            els.lotModeHint.classList.toggle('d-none', !isEmergency);
        }
        if (els.allowMessageSingleTradeOverride) {
            els.allowMessageSingleTradeOverride.disabled = isEmergency;
        }
        if (els.distribution) {
            els.distribution.disabled = isEmergency;
        }
        if (els.waitEntryZone) {
            // Entry-zone wait is meaningful only for no-confirm flow.
            els.waitEntryZone.disabled = requireConfirm;
        }
        if (els.waitEntryZoneHint) {
            if (requireConfirm) {
                els.waitEntryZoneHint.textContent = 'Require Confirm açıksa bu seçenek kullanılmaz. Confirm sonrası giriş doğrudan execute edilir.';
            } else {
                els.waitEntryZoneHint.textContent = 'Açıkken (no-confirm kanallarda) fiyat entry aralığına gelince emir açılır. Kapalıyken mesaj gelir gelmez açılır.';
            }
        }
        if (els.modeSummary) {
            const modeTxt = isEmergency
                ? 'Global mode: single_trade (no partial), distribution devre dışı.'
                : (allowMsgOverride
                    ? 'Global mode: ladder. Mesaj bazlı NO PARTIAL / SINGLE TP override açık.'
                    : 'Global mode: ladder. Mesaj bazlı single-trade override kapalı.');
            const confirmTxt = requireConfirm
                ? 'Confirm workflow: onay mesajı zorunlu.'
                : 'Confirm workflow: no-confirm akışı aktif (entry-zone seçeneğine göre).';
            els.modeSummary.textContent = `${modeTxt} ${confirmTxt}`;
        }
    }

    function fillUserListenerForm(state, opts) {
        const force = !!(opts && opts.force);
        if (!force && userFormDirty) return;
        const s = state || {};
        suppressDirtyTracking = true;
        if (els.userEnabled) els.userEnabled.checked = !!s.enabled;
        if (els.userSessionPath) els.userSessionPath.value = String(s.session_path || 'dashboard/data/telegram_user_listener');
        if (els.userChannels) els.userChannels.value = toLines(s.channels);
        if (els.userPollSec) els.userPollSec.value = String(parseFloat(s.poll_sec || 3));
        if (els.userBackfillCount) els.userBackfillCount.value = String(parseInt(s.feed_backfill_count || 8, 10));
        suppressDirtyTracking = false;
    }

    function renderUserListenerStatus(state) {
        const s = state || {};
        const telethon = !!s.telethon_available ? 'telethon:ok' : 'telethon:missing';
        const run = !!s.running ? 'running' : 'stopped';
        const authHint = (s.last_error && String(s.last_error).includes('user_session_not_authorized')) ? ' | login needed' : '';
        const err = s.last_error ? ` | err: ${String(s.last_error)}` : '';
        const resolvedCount = Array.isArray(s.resolved_channels) ? s.resolved_channels.length : 0;
        const skippedCount = Array.isArray(s.skipped_specs) ? s.skipped_specs.length : 0;
        const routing = ` | channels:${resolvedCount} ok, ${skippedCount} skipped`;
        if (els.userStatusLine) {
            els.userStatusLine.textContent = `Reader status: ${run} | ${telethon}${routing}${authHint}${err}`;
        }
    }

    function renderListenerFlowStatus(state) {
        const s = state || {};
        const running = !!s.running;
        const forwardOk = Number(s.forward_ok || 0);
        const forwardFail = Number(s.forward_fail || 0);
        const forwardTotal = Number(s.forward_total || 0);
        const lastForward = String(s.last_forward || '').trim();
        const lastForwardErr = String(s.last_forward_error || '').trim();
        const lastSource = String(s.last_forward_source || '').trim();
        const lastMessageId = Number(s.last_forward_message_id || 0);
        const pipelineConnected = !!s.pipeline_connected;
        const pipelineTarget = String(s.pipeline_target || '').trim() || '-';

        if (els.userRunState) {
            els.userRunState.textContent = running ? 'RUNNING' : 'STOPPED';
            els.userRunState.className = running ? 'fs-6 text-success' : 'fs-6 text-danger';
        }
        if (els.userForwardOk) els.userForwardOk.textContent = String(forwardOk);
        if (els.userForwardFail) els.userForwardFail.textContent = String(forwardFail);

        if (els.userFlowLine) {
            const last = lastForward ? `${lastForward}${lastSource ? ` | source: ${lastSource}` : ''}${lastMessageId > 0 ? ` | msg:${lastMessageId}` : ''}` : 'no forward yet';
            const err = lastForwardErr ? ` | last_err: ${lastForwardErr}` : '';
            els.userFlowLine.textContent = `Listener flow: total ${forwardTotal} | ok ${forwardOk} | fail ${forwardFail} | last ${last}${err}`;
        }
        if (els.userPipelineLine) {
            els.userPipelineLine.textContent = `Pipeline: ${pipelineConnected ? 'connected' : 'not connected'} -> ${pipelineTarget}`;
        }
        if (els.userChannelLine) {
            const rows = Array.isArray(s.channel_health) ? s.channel_health : [];
            if (!rows.length) {
                els.userChannelLine.textContent = 'Channel coverage: no resolved channel yet';
            } else {
                const parts = rows.map((r) => {
                    const name = String(r.spec || r.title || r.id || '').trim() || 'channel';
                    const last = Number(r.last_seen_msg_id || 0);
                    return `${name} (last_msg:${last > 0 ? last : '-'})`;
                });
                els.userChannelLine.textContent = `Channel coverage: ${parts.join(' | ')}`;
            }
        }
    }

    function feedRowSortKey(row) {
        const r = row || {};
        const eventUnix = Number(r.event_unix || 0);
        if (Number.isFinite(eventUnix) && eventUnix > 0) return eventUnix;
        const eventTs = String(r.event_ts || r.ts || '');
        const parsed = Date.parse(eventTs);
        if (Number.isFinite(parsed) && parsed > 0) return parsed / 1000.0;
        return Number(r.id || 0);
    }

    function escapeHtml(v) {
        return String(v || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function formatFeedTimestamp(value) {
        const raw = String(value || '').trim();
        if (!raw) return '-';
        const dt = new Date(raw);
        if (Number.isNaN(dt.getTime())) return raw;
        try {
            return new Intl.DateTimeFormat('tr-TR', {
                day: '2-digit',
                month: '2-digit',
                year: 'numeric',
                hour: '2-digit',
                minute: '2-digit',
                hour12: false
            }).format(dt);
        } catch (_) {
            const dd = String(dt.getDate()).padStart(2, '0');
            const mm = String(dt.getMonth() + 1).padStart(2, '0');
            const yyyy = String(dt.getFullYear());
            const hh = String(dt.getHours()).padStart(2, '0');
            const mi = String(dt.getMinutes()).padStart(2, '0');
            return `${dd}.${mm}.${yyyy} ${hh}:${mi}`;
        }
    }

    function renderFeed(rows) {
        const all = Array.isArray(rows) ? rows.slice() : [];
        const selectedSource = String((els.feedSourceFilter && els.feedSourceFilter.value) || '__all__');
        const selectedKind = String((els.feedKindFilter && els.feedKindFilter.value) || '__all__').toLowerCase();
        const sources = [];
        const seen = new Set();
        for (const r of all) {
            const src = String((r && r.source) || '').trim();
            if (!src) continue;
            if (seen.has(src)) continue;
            seen.add(src);
            sources.push(src);
        }
        sources.sort((a, b) => a.localeCompare(b));
        if (els.feedSourceFilter) {
            const prev = selectedSource;
            const opts = ['<option value="__all__">All sources</option>']
                .concat(sources.map((s) => `<option value="${escapeHtml(s)}">${escapeHtml(s)}</option>`));
            els.feedSourceFilter.innerHTML = opts.join('');
            const canKeep = prev === '__all__' || sources.includes(prev);
            els.feedSourceFilter.value = canKeep ? prev : '__all__';
        }
        const activeSource = String((els.feedSourceFilter && els.feedSourceFilter.value) || '__all__');
        const signalsOnly = !!(els.feedSignalsOnly && els.feedSignalsOnly.checked);
        const inferKind = (r) => {
            const kind = String((r && r.kind) || '').toLowerCase();
            if (kind) return kind;
            const txtRaw = String((r && r.text) || '').trim();
            const txt = (typeof txtRaw.normalize === 'function') ? txtRaw.normalize('NFKC') : txtRaw;
            if (!txt) return 'other';
            if (/\bCONFIRM\s+SIGNAL\b/im.test(txt)) return 'confirm_signal';
            if (/\bTP\s*(?:[1-9]\d*)?\s*HIT\b/im.test(txt) || /\ball\s+target(?:s)?\s+(?:successfully\s+)?(?:hit|completed)\b/im.test(txt) || /\btarget(?:s)?\s+completed\b/im.test(txt)) return 'tp_hit';
            if (/\b(?:SL(?:\s*[1-9]\d*)?|STOP\s*LOSS)\b.*\bHIT\b/im.test(txt)) return 'sl_hit';
            if (/\bCLOSE\s+IT\b/im.test(txt) || /\bCLOSE\s+NOW\b/im.test(txt)) return 'close_instruction';
            if (
                /^\s*#?\s*[A-Z]{3,12}(?:\s+#?\s*[A-Z]{3,12})?\s*(?:[_\-\s]+)(BUY|SELL)\s+(?:NOW\s+)?[0-9]+(?:\.[0-9]+)?(?:\s*(?:\/|-|TO)\s*[0-9]+(?:\.[0-9]+)?)?\s*$/im.test(txt) ||
                /^\s*[A-Z]{3,12}\s+(BUY|SELL)\s+NOW\b/im.test(txt)
            ) return 'signal';
            return 'other';
        };
        const isSignalRow = (r) => {
            const k = inferKind(r);
            return k === 'signal' || k === 'confirm_signal' || k === 'tp_hit' || k === 'sl_hit' || k === 'close_instruction';
        };
        const filtered = all.filter((r) => {
            if (activeSource !== '__all__' && String((r && r.source) || '') !== activeSource) return false;
            if (signalsOnly && !isSignalRow(r)) return false;
            if (selectedKind !== '__all__' && inferKind(r) !== selectedKind) return false;
            return true;
        });
        const items = filtered.sort((a, b) => {
            const ka = feedRowSortKey(a);
            const kb = feedRowSortKey(b);
            if (kb !== ka) return kb - ka;
            const ma = Number((a && a.source_message_id) || 0);
            const mb = Number((b && b.source_message_id) || 0);
            if (mb !== ma) return mb - ma;
            return Number((b && b.id) || 0) - Number((a && a.id) || 0);
        });
        if (els.feedCount) els.feedCount.textContent = String(items.length);
        if (!els.feedBody) return;
        if (!items.length) {
            els.feedBody.innerHTML = '<tr><td colspan="4" class="text-muted text-center py-3">No messages yet.</td></tr>';
            return;
        }
        els.feedBody.innerHTML = items.map((r) => {
            const ts = String(r.event_ts || r.ts || '-');
            const tsLabel = formatFeedTimestamp(ts);
            const src = String(r.source || '-');
            const kind = inferKind(r);
            const txt = escapeHtml(String(r.text || ''));
            return `<tr><td class="small text-muted">${tsLabel}</td><td>${src}</td><td><span class="badge text-bg-secondary">${kind}</span></td><td style="white-space: pre-wrap;">${txt}</td></tr>`;
        }).join('');
    }

    function renderExecutionLogs(rows) {
        const all = Array.isArray(rows) ? rows.slice() : [];
        const selectedSource = String((els.execSourceFilter && els.execSourceFilter.value) || '__all__');
        const selectedTrigger = String((els.execTriggerFilter && els.execTriggerFilter.value) || '__all__').toLowerCase();
        const traceSearch = String((els.execTraceSearch && els.execTraceSearch.value) || '').trim().toLowerCase();
        const sources = [];
        const triggers = [];
        const seenSrc = new Set();
        const seenTr = new Set();
        for (const r of all) {
            const src = String((r && r.source_name) || '').trim();
            const tr = String((r && (r.trigger || r.stage)) || '').trim().toLowerCase();
            if (src && !seenSrc.has(src)) {
                seenSrc.add(src);
                sources.push(src);
            }
            if (tr && !seenTr.has(tr)) {
                seenTr.add(tr);
                triggers.push(tr);
            }
        }
        sources.sort((a, b) => a.localeCompare(b));
        triggers.sort((a, b) => a.localeCompare(b));
        if (els.execSourceFilter) {
            const prev = selectedSource;
            const opts = ['<option value="__all__">All sources</option>']
                .concat(sources.map((s) => `<option value="${escapeHtml(s)}">${escapeHtml(s)}</option>`));
            els.execSourceFilter.innerHTML = opts.join('');
            els.execSourceFilter.value = (prev === '__all__' || sources.includes(prev)) ? prev : '__all__';
        }
        if (els.execTriggerFilter) {
            const prev = selectedTrigger;
            const opts = ['<option value="__all__">All stages</option>']
                .concat(triggers.map((t) => `<option value="${escapeHtml(t)}">${escapeHtml(t)}</option>`));
            els.execTriggerFilter.innerHTML = opts.join('');
            els.execTriggerFilter.value = (prev === '__all__' || triggers.includes(prev)) ? prev : '__all__';
        }
        const activeSource = String((els.execSourceFilter && els.execSourceFilter.value) || '__all__');
        const activeTrigger = String((els.execTriggerFilter && els.execTriggerFilter.value) || '__all__').toLowerCase();
        const items = all.filter((r) => {
            const src = String((r && r.source_name) || '').trim();
            const tr = String((r && (r.trigger || r.stage)) || '').trim().toLowerCase();
            const trace = String((r && r.trace_id) || '').trim().toLowerCase();
            if (activeSource !== '__all__' && src !== activeSource) return false;
            if (activeTrigger !== '__all__' && tr !== activeTrigger) return false;
            if (traceSearch && !trace.includes(traceSearch)) return false;
            return true;
        });
        if (!els.execLogBody) return;
        if (!items.length) {
            els.execLogBody.innerHTML = '<tr><td colspan="8" class="text-muted text-center py-3">No execution logs yet.</td></tr>';
            return;
        }
        items.sort((a, b) => {
            const ta = Date.parse(String((a && (a.event_ts || a.ts)) || '')) || 0;
            const tb = Date.parse(String((b && (b.event_ts || b.ts)) || '')) || 0;
            return tb - ta;
        });
        els.execLogBody.innerHTML = items.map((r) => {
            const ts = formatFeedTimestamp((r && (r.event_ts || r.ts)) || '');
            const srcName = escapeHtml(String((r && r.source_name) || '-'));
            const sym = String((r && r.symbol) || '').trim();
            const tf = String((r && r.timeframe) || '').trim();
            const symTf = escapeHtml((sym || tf) ? `${sym}${tf ? ` ${tf}` : ''}` : '-');
            const dir = escapeHtml(String((r && r.direction) || '-'));
            const lotRaw = Number((r && r.lot) || 0);
            const lot = Number.isFinite(lotRaw) && lotRaw > 0 ? lotRaw.toFixed(2) : '-';
            const status = escapeHtml(String((r && r.status) || '-'));
            const trigger = escapeHtml(String((r && (r.trigger || r.stage)) || '-'));
            const stageStatus = escapeHtml(String((r && r.stage_status) || ''));
            const ticketRaw = Number((r && r.ticket) || 0);
            const ticket = ticketRaw > 0 ? String(ticketRaw) : '-';
            const msg = escapeHtml(String((r && r.message) || ''));
            const trace = escapeHtml(String((r && r.trace_id) || '-'));
            const mode = escapeHtml(String((r && r.execution_mode) || '-'));
            const stageTxt = `${trigger}${stageStatus ? ` / ${stageStatus}` : ''} / ${status}`;
            const detailBits = [];
            if (mode && mode !== '-') detailBits.push(`mode=${mode}`);
            if (msg) detailBits.push(msg);
            return `<tr><td class="small text-muted">${ts}</td><td>${srcName}</td><td>${symTf}</td><td>${dir} / ${lot}</td><td>${stageTxt}</td><td>${ticket}</td><td><code>${trace}</code></td><td>${detailBits.join(' | ')}</td></tr>`;
        }).join('');
    }

    async function loadState(force) {
        const data = await req('/api/telegram/automation/state?limit=500');
        fillForm(data.config || {}, { force: !!force });
        if (els.pendingCount) els.pendingCount.textContent = String(data.pending_confirm_count || 0);
        if (els.activeCount) els.activeCount.textContent = String(data.active_ladder_count || 0);
        latestFeedRows = Array.isArray(data.feed) ? data.feed.slice() : [];
        renderFeed(latestFeedRows);
        latestExecLogs = Array.isArray(data.execution_logs) ? data.execution_logs.slice() : [];
        renderExecutionLogs(latestExecLogs);
        fillUserListenerForm(data.user_listener || {}, { force: !!force });
        renderUserListenerStatus(data.user_listener || {});
        renderListenerFlowStatus(data.user_listener || {});
        if (els.updated) els.updated.textContent = `Updated: ${new Date().toLocaleTimeString()}`;
    }

    function collectPayload() {
        const channelLines = String((els.channels && els.channels.value) || '')
            .split('\n')
            .map((x) => x.trim())
            .filter(Boolean);
        return {
            enabled: !!(els.enabled && els.enabled.checked),
            require_confirm: !!(els.requireConfirm && els.requireConfirm.checked),
            wait_entry_zone: !!(els.waitEntryZone && els.waitEntryZone.checked),
            require_confirm_channels: String((els.requireConfirmChannels && els.requireConfirmChannels.value) || '')
                .split('\n')
                .map((x) => x.trim())
                .filter(Boolean),
            no_confirm_channels: String((els.noConfirmChannels && els.noConfirmChannels.value) || '')
                .split('\n')
                .map((x) => x.trim())
                .filter(Boolean),
            channels: channelLines,
            default_timeframe: String((els.timeframe && els.timeframe.value) || 'M5').trim().toUpperCase(),
            default_lot: parseFloat((els.lot && els.lot.value) || '0.05'),
            force_single_trade_01: !!(els.forceSingle01 && els.forceSingle01.checked),
            allow_message_single_trade_override: !!(els.allowMessageSingleTradeOverride && els.allowMessageSingleTradeOverride.checked),
            distribution_mode: String((els.distribution && els.distribution.value) || 'equal').trim(),
            confirm_window_sec: parseInt((els.confirmWindow && els.confirmWindow.value) || '1800', 10),
            evaluation_mode: String((els.evalMode && els.evalMode.value) || 'deterministic').trim(),
            ai_provider: String((els.aiProvider && els.aiProvider.value) || 'claude').trim(),
            ai_model: String((els.aiModel && els.aiModel.value) || '').trim(),
            ai_timeout_sec: parseInt((els.aiTimeout && els.aiTimeout.value) || '10', 10)
        };
    }

    async function saveConfig() {
        const payload = collectPayload();
        const data = await req('/api/telegram/automation/config', {
            method: 'POST',
            body: JSON.stringify(payload)
        });
        if (data && data.ok === false) {
            throw new Error(getApiErrorMessage(data, 'save_config_failed'));
        }
        mainFormDirty = false;
        fillForm((data && data.config) || {}, { force: true });
        if (els.pendingCount) els.pendingCount.textContent = String((data && data.pending_confirm_count) || 0);
        if (els.activeCount) els.activeCount.textContent = String((data && data.active_ladder_count) || 0);
        latestFeedRows = Array.isArray((data && data.feed)) ? (data.feed).slice() : [];
        renderFeed(latestFeedRows);
        latestExecLogs = Array.isArray((data && data.execution_logs)) ? (data.execution_logs).slice() : [];
        renderExecutionLogs(latestExecLogs);
        showAlert('Telegram automation config saved.', 'success');
    }

    function collectUserListenerPayload() {
        const channelLines = String((els.userChannels && els.userChannels.value) || '')
            .split('\n')
            .map((x) => x.trim())
            .filter(Boolean);
        const payload = {
            enabled: !!(els.userEnabled && els.userEnabled.checked),
            channels: channelLines,
            session_path: String((els.userSessionPath && els.userSessionPath.value) || '').trim(),
            poll_sec: parseFloat((els.userPollSec && els.userPollSec.value) || '3'),
            feed_backfill_count: parseInt((els.userBackfillCount && els.userBackfillCount.value) || '8', 10),
        };
        const apiIdRaw = String((els.userApiId && els.userApiId.value) || '').trim();
        const apiHashRaw = String((els.userApiHash && els.userApiHash.value) || '').trim();
        if (apiIdRaw) payload.api_id = parseInt(apiIdRaw, 10);
        if (apiHashRaw) payload.api_hash = apiHashRaw;
        return payload;
    }

    async function saveUserListenerConfig() {
        const payload = collectUserListenerPayload();
        const data = await req('/api/telegram/user-listener/config', {
            method: 'POST',
            body: JSON.stringify(payload)
        });
        if (data && data.ok === false) {
            throw new Error(getApiErrorMessage(data, 'save_reader_config_failed'));
        }
        userFormDirty = false;
        fillUserListenerForm(data || {}, { force: true });
        renderUserListenerStatus(data || {});
        showAlert('Telegram reader config saved.', 'success');
    }

    async function userAction(url, payload, okMsg) {
        const data = await req(url, {
            method: 'POST',
            body: JSON.stringify(payload || {})
        });
        if (data && data.ok === false) {
            throw new Error(getApiErrorMessage(data, 'reader_action_failed'));
        }
        const st = (data && (data.state || data)) || {};
        renderUserListenerStatus(st);
        renderListenerFlowStatus(st);
        if (okMsg) showAlert(okMsg, 'success');
        return data;
    }

    async function init() {
        const mainInputs = [
            els.enabled, els.requireConfirm, els.waitEntryZone, els.requireConfirmChannels, els.noConfirmChannels, els.channels, els.timeframe, els.lot,
            els.forceSingle01, els.allowMessageSingleTradeOverride, els.distribution, els.confirmWindow, els.evalMode, els.aiProvider, els.aiModel, els.aiTimeout
        ].filter(Boolean);
        const userInputs = [
            els.userEnabled, els.userApiId, els.userApiHash, els.userSessionPath,
            els.userChannels, els.userPollSec, els.userBackfillCount, els.userPhone, els.userCode, els.userPassword
        ].filter(Boolean);
        for (const el of mainInputs) {
            el.addEventListener('input', () => {
                if (!suppressDirtyTracking) mainFormDirty = true;
            });
            el.addEventListener('change', () => {
                if (!suppressDirtyTracking) mainFormDirty = true;
            });
        }
        if (els.forceSingle01) {
            els.forceSingle01.addEventListener('change', () => {
                syncEmergencyLotUi();
            });
        }
        if (els.allowMessageSingleTradeOverride) {
            els.allowMessageSingleTradeOverride.addEventListener('change', () => {
                syncEmergencyLotUi();
            });
        }
        if (els.requireConfirm) {
            els.requireConfirm.addEventListener('change', () => {
                syncEmergencyLotUi();
            });
        }
        for (const el of userInputs) {
            el.addEventListener('input', () => {
                if (!suppressDirtyTracking) userFormDirty = true;
            });
            el.addEventListener('change', () => {
                if (!suppressDirtyTracking) userFormDirty = true;
            });
        }
        try {
            await loadState(true);
        } catch (err) {
            showAlert(`Load failed: ${String(err.message || err)}`, 'error');
        }
        if (els.saveBtn) {
            els.saveBtn.addEventListener('click', async () => {
                els.saveBtn.disabled = true;
                try {
                    await saveConfig();
                    await loadState(true);
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
                    mainFormDirty = false;
                    userFormDirty = false;
                    await loadState(true);
                } catch (err) {
                    showAlert(`Refresh failed: ${String(err.message || err)}`, 'error');
                }
            });
        }
        if (els.feedSourceFilter) {
            els.feedSourceFilter.addEventListener('change', () => {
                renderFeed(latestFeedRows);
            });
        }
        if (els.feedKindFilter) {
            els.feedKindFilter.addEventListener('change', () => {
                renderFeed(latestFeedRows);
            });
        }
        if (els.feedSignalsOnly) {
            els.feedSignalsOnly.addEventListener('change', () => {
                renderFeed(latestFeedRows);
            });
        }
        if (els.execSourceFilter) {
            els.execSourceFilter.addEventListener('change', () => {
                renderExecutionLogs(latestExecLogs);
            });
        }
        if (els.execTriggerFilter) {
            els.execTriggerFilter.addEventListener('change', () => {
                renderExecutionLogs(latestExecLogs);
            });
        }
        if (els.execTraceSearch) {
            els.execTraceSearch.addEventListener('input', () => {
                renderExecutionLogs(latestExecLogs);
            });
        }
        if (els.userSaveBtn) {
            els.userSaveBtn.addEventListener('click', async () => {
                els.userSaveBtn.disabled = true;
                try {
                    await saveUserListenerConfig();
                    await loadState(true);
                } catch (err) {
                    showAlert(`Reader save failed: ${String(err.message || err)}`, 'error');
                } finally {
                    els.userSaveBtn.disabled = false;
                }
            });
        }
        if (els.userSendCodeBtn) {
            els.userSendCodeBtn.addEventListener('click', async () => {
                const phone = String((els.userPhone && els.userPhone.value) || '').trim();
                if (!phone) {
                    showAlert('Phone is required for login code.', 'error');
                    return;
                }
                els.userSendCodeBtn.disabled = true;
                try {
                    const out = await userAction('/api/telegram/user-listener/send-code', { phone }, 'Login code sent.');
                    const r = (out && out.result) || {};
                    pendingLoginCtx.phoneCodeHash = String(r.phone_code_hash || '').trim();
                    pendingLoginCtx.pendingSession = String(r.pending_session || '').trim();
                } catch (err) {
                    showAlert(`Send code failed: ${String(err.message || err)}`, 'error');
                } finally {
                    els.userSendCodeBtn.disabled = false;
                }
            });
        }
        if (els.userVerifyBtn) {
            els.userVerifyBtn.addEventListener('click', async () => {
                const phone = String((els.userPhone && els.userPhone.value) || '').trim();
                const code = String((els.userCode && els.userCode.value) || '').trim();
                const password = String((els.userPassword && els.userPassword.value) || '').trim();
                if (!phone || !code) {
                    showAlert('Phone and code are required.', 'error');
                    return;
                }
                els.userVerifyBtn.disabled = true;
                try {
                    await userAction('/api/telegram/user-listener/verify-code', {
                        phone,
                        code,
                        password,
                        phone_code_hash: String(pendingLoginCtx.phoneCodeHash || '').trim() || undefined,
                        pending_session: String(pendingLoginCtx.pendingSession || '').trim() || undefined
                    }, 'Login verified. Listener auto-starts when enabled.');
                    pendingLoginCtx = { phoneCodeHash: '', pendingSession: '' };
                    userFormDirty = false;
                    await loadState(true);
                } catch (err) {
                    showAlert(`Verify failed: ${String(err.message || err)}`, 'error');
                } finally {
                    els.userVerifyBtn.disabled = false;
                }
            });
        }
        if (els.userStopBtn) {
            els.userStopBtn.addEventListener('click', async () => {
                els.userStopBtn.disabled = true;
                try {
                    await userAction('/api/telegram/user-listener/stop', {}, 'Reader stopped.');
                    await loadState(true);
                } catch (err) {
                    showAlert(`Stop failed: ${String(err.message || err)}`, 'error');
                } finally {
                    els.userStopBtn.disabled = false;
                }
            });
        }
        if (pollTimer) {
            clearInterval(pollTimer);
        }
        pollTimer = setInterval(async () => {
            try {
                await loadState(false);
            } catch (_) {
                // keep silent on periodic poll
            }
        }, 5000);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
