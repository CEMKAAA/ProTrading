using System;
using System.Collections.Generic;
using System.Globalization;
using IoFile = global::System.IO.File;
using IoPath = global::System.IO.Path;
using IoFileStream = global::System.IO.FileStream;
using IoFileMode = global::System.IO.FileMode;
using IoFileAccess = global::System.IO.FileAccess;
using IoFileShare = global::System.IO.FileShare;
using IoStreamWriter = global::System.IO.StreamWriter;
using IoDirectory = global::System.IO.Directory;
using IoException = global::System.IO.IOException;
using System.Linq;
using System.Text;
using cAlgo.API;

namespace cAlgo.Robots
{
    [Robot(TimeZone = TimeZones.UTC, AccessRights = AccessRights.FullAccess)]
    public class LiqNarrativeSolAdvancedCTraderListener : Robot
    {
        private const string Build = "2026-07-24.liq-sol-advanced-isolated-v4";

        [Parameter("Executor Enabled", DefaultValue = true)]
        public bool ExecutorEnabled { get; set; }

        [Parameter("Bridge Latest Path", DefaultValue = "C:\\Users\\Cem\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\LiqNarrativeSolAdvancedBridge_Latest.csv")]
        public string BridgeLatestPath { get; set; }

        [Parameter("Prefer Scoped Latest", DefaultValue = true)]
        public bool PreferScopedLatest { get; set; }

        [Parameter("Poll Milliseconds", DefaultValue = 500, MinValue = 100)]
        public int PollMilliseconds { get; set; }

        [Parameter("Max Signal Age Sec", DefaultValue = 900, MinValue = 1)]
        public int MaxSignalAgeSeconds { get; set; }

        [Parameter("Ignore Existing On Init", DefaultValue = true)]
        public bool IgnoreExistingSignalOnInit { get; set; }

        [Parameter("Symbol Map CSV", DefaultValue = "")]
        public string SymbolMapCsv { get; set; }

        [Parameter("Use Built-In Oil Map", DefaultValue = true)]
        public bool UseBuiltInOilSymbolMap { get; set; }

        [Parameter("Built-In Oil Map", DefaultValue = "UKOILm=XBRUSD,UKOIL=XBRUSD,USOILm=XTIUSD,USOIL=XTIUSD")]
        public string BuiltInOilSymbolMapCsv { get; set; }

        [Parameter("Use Built-In Index Map", DefaultValue = true)]
        public bool UseBuiltInIndexSymbolMap { get; set; }

        [Parameter("Built-In Index Map", DefaultValue = "DE30m=GERMANY 40,DE30=GERMANY 40,GER30m=GERMANY 40,GER30=GERMANY 40,GER40m=GERMANY 40,GER40=GERMANY 40,DAX40m=GERMANY 40,DAX40=GERMANY 40,US500m=US 500,US500=US 500,SPX500m=US 500,SPX500=US 500,USTECm=US Tech 100,USTEC=US Tech 100,US100m=US Tech 100,US100=US Tech 100,US30m=Wall Street 30,US30=Wall Street 30,JP225m=JPN225,JP225=JPN225,JPN225m=JPN225,JPN225=JPN225")]
        public string BuiltInIndexSymbolMapCsv { get; set; }

        [Parameter("Require Chart Symbol", DefaultValue = true)]
        public bool RequireMappedSymbolEqualsChart { get; set; }

        [Parameter("Source TF Filter", DefaultValue = "")]
        public string SourceTimeframeFilter { get; set; }

        [Parameter("Default TF To Chart", DefaultValue = true)]
        public bool DefaultSourceTfToChartPeriod { get; set; }

        [Parameter("Source Filter", DefaultValue = "LiqNarrativeSolAdvanced")]
        public string SourceFilter { get; set; }

        [Parameter("Rebase Levels To Live", DefaultValue = false)]
        public bool RebaseMappedLevelsToLiveEntry { get; set; }

        [Parameter("Rebase Only Source Differs", DefaultValue = true)]
        public bool RebaseOnlyWhenSourceDiffers { get; set; }

        [Parameter("Auto Rebase Oil Aliases", DefaultValue = true)]
        public bool AutoRebaseOilAliases { get; set; }

        [Parameter("Mapped Basis Guard % Risk", DefaultValue = 25.0, MinValue = 0.0)]
        public double MappedBasisGuardPctRisk { get; set; }

        [Parameter("Close Reverse", DefaultValue = true)]
        public bool CloseReverse { get; set; }

        [Parameter("Close Reverse Across TF", DefaultValue = false)]
        public bool CloseReverseAcrossSourceTf { get; set; }

        [Parameter("Fail If Reverse Close Fails", DefaultValue = true)]
        public bool FailIfReverseCloseFails { get; set; }

        [Parameter("Fail If Exact Protection Fails", DefaultValue = true)]
        public bool FailIfExactProtectionFails { get; set; }

        [Parameter("Enable Close-Only Signals", DefaultValue = true)]
        public bool EnableCloseOnlySignals { get; set; }

        [Parameter("Permanent Reject Guard", DefaultValue = true)]
        public bool PermanentRejectGuard { get; set; }

        [Parameter("Market Closed Retry Sec", DefaultValue = 900, MinValue = 30)]
        public int MarketClosedRetrySeconds { get; set; }

        [Parameter("Order Failure Retry Sec", DefaultValue = 60, MinValue = 5)]
        public int OrderFailureRetrySeconds { get; set; }

        [Parameter("Label Prefix", DefaultValue = "LN_ADV")]
        public string LabelPrefix { get; set; }

        [Parameter("Use Risk Lot", DefaultValue = true)]
        public bool UseRiskLot { get; set; }

        [Parameter("Local Risk %", DefaultValue = 1.0, MinValue = 0.0)]
        public double LocalRiskPct { get; set; }

        [Parameter("Use Bridge Risk %", DefaultValue = true)]
        public bool UseBridgeRiskPct { get; set; }

        [Parameter("Use Balance For Risk", DefaultValue = false)]
        public bool UseBalanceForRisk { get; set; }

        [Parameter("Manual Volume Units", DefaultValue = 1000, MinValue = 1)]
        public double ManualVolumeInUnits { get; set; }

        [Parameter("Max Volume Units", DefaultValue = 0, MinValue = 0)]
        public double MaxVolumeInUnits { get; set; }

        [Parameter("Use Margin Shrink Guard", DefaultValue = true)]
        public bool UseMarginShrinkGuard { get; set; }

        [Parameter("Max Margin Usage %", DefaultValue = 40.0, MinValue = 0)]
        public double MaxMarginUsagePct { get; set; }

        [Parameter("Fail Closed On Risk Error", DefaultValue = true)]
        public bool FailClosedOnRiskError { get; set; }

        [Parameter("Block If Min Vol Exceeds Risk", DefaultValue = true)]
        public bool BlockIfMinVolumeExceedsRisk { get; set; }

        [Parameter("Post-Fill Risk Guard", DefaultValue = true)]
        public bool PostFillRiskGuard { get; set; }

        [Parameter("Max Risk Overshoot %", DefaultValue = 5.0, MinValue = 0.0)]
        public double MaxRiskOvershootPct { get; set; }

        [Parameter("No-Money Retry Shrink", DefaultValue = true)]
        public bool NoMoneyRetryShrink { get; set; }

        [Parameter("Max Spread Pips", DefaultValue = 0, MinValue = 0)]
        public double MaxSpreadPips { get; set; }

        [Parameter("Manage HCBE", DefaultValue = true)]
        public bool ManageHalfCloseBe { get; set; }

        [Parameter("Half Close Fraction", DefaultValue = 0.5, MinValue = 0.01, MaxValue = 0.99)]
        public double HalfCloseFraction { get; set; }

        [Parameter("HCBE Retry Sec", DefaultValue = 5, MinValue = 1)]
        public int HalfBeRetrySeconds { get; set; }

        [Parameter("HCBE Volume Retry Sec", DefaultValue = 60, MinValue = 5)]
        public int HalfBeVolumeRetrySeconds { get; set; }

        [Parameter("Audit Enabled", DefaultValue = true)]
        public bool AuditEnabled { get; set; }

        [Parameter("Audit File Prefix", DefaultValue = "LiqNarrativeSolAdvanced_cTrader_Audit_")]
        public string AuditFilePrefix { get; set; }

        [Parameter("Poll Heartbeat Sec", DefaultValue = 300, MinValue = 0)]
        public int PollHeartbeatSeconds { get; set; }

        [Parameter("Show Dashboard", DefaultValue = true)]
        public bool ShowDashboard { get; set; }

        private string _lastSeenEventId = string.Empty;
        private string _lastRejectedEventId = string.Empty;
        private string _lastAction = "boot";
        private string _lastDetail = string.Empty;
        private string _lastSignal = "none";
        private readonly Dictionary<long, HalfState> _halfStates = new Dictionary<long, HalfState>();
        private readonly Dictionary<string, DateTime> _orderRetryBlockedUntil = new Dictionary<string, DateTime>();
        private readonly Dictionary<long, DateTime> _emergencyCloseRetryAt = new Dictionary<long, DateTime>();
        private readonly Dictionary<long, DateTime> _halfRetryAt = new Dictionary<long, DateTime>();
        private readonly Dictionary<string, DateTime> _eventClaimAuditAt = new Dictionary<string, DateTime>();
        private string _resolvedBridgePath;
        private DateTime _lastPollHeartbeat = DateTime.MinValue;
        private DateTime _lastReadFailAudit = DateTime.MinValue;
        private string _lastInitMarkerAuditKey = string.Empty;
        private string _lastReadFailAuditKey = string.Empty;
        private string _auditDir;
        private string _lockDir;
        private string _stateDir;
        private static readonly object AuditWriteSync = new object();

        private void EnforceAdvancedIsolationDefaults()
        {
            var configuredPath = (BridgeLatestPath ?? string.Empty).Trim();
            var configuredFile = IoPath.GetFileName(configuredPath) ?? string.Empty;
            if (string.IsNullOrWhiteSpace(configuredPath)
                || configuredFile.Equals("LiqNarrativeSolBridge_Latest.csv", StringComparison.OrdinalIgnoreCase)
                || configuredFile.Equals("LiquidityNarrativeBridge_Latest.csv", StringComparison.OrdinalIgnoreCase))
            {
                var configuredDir = IoPath.GetDirectoryName(configuredPath);
                BridgeLatestPath = string.IsNullOrWhiteSpace(configuredDir)
                    ? IoPath.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MetaQuotes", "Terminal", "Common", "Files", "LiqNarrativeSolAdvancedBridge_Latest.csv")
                    : IoPath.Combine(configuredDir, "LiqNarrativeSolAdvancedBridge_Latest.csv");
            }

            if (string.IsNullOrWhiteSpace(LabelPrefix) || LabelPrefix.Equals("LN_CT", StringComparison.OrdinalIgnoreCase))
                LabelPrefix = "LN_ADV";
            if (string.IsNullOrWhiteSpace(SourceFilter)
                || SourceFilter.Equals("LiqNarrativeSol", StringComparison.OrdinalIgnoreCase)
                || SourceFilter.Equals("LiquidityNarrative", StringComparison.OrdinalIgnoreCase))
                SourceFilter = "LiqNarrativeSolAdvanced";
            if (string.IsNullOrWhiteSpace(AuditFilePrefix)
                || AuditFilePrefix.Equals("LiquidityNarrative_cTrader_Audit_", StringComparison.OrdinalIgnoreCase)
                || AuditFilePrefix.Equals("LiqNarrativeSol_cTrader_Audit_", StringComparison.OrdinalIgnoreCase))
                AuditFilePrefix = "LiqNarrativeSolAdvanced_cTrader_Audit_";
        }
        protected override void OnStart()
        {
            EnforceAdvancedIsolationDefaults();
            _resolvedBridgePath = ResolveBridgePath();
            _auditDir = IoPath.GetDirectoryName(_resolvedBridgePath) ?? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            _lockDir = IoPath.Combine(IoPath.GetTempPath(), "LiqNarrativeSolAdvanced_cTrader_Locks");
            IoDirectory.CreateDirectory(_lockDir);
            _stateDir = IoPath.Combine(_auditDir, "LiqNarrativeSolAdvanced_cTrader_State");
            IoDirectory.CreateDirectory(_stateDir);

            Timer.Start(TimeSpan.FromMilliseconds(Math.Max(100, PollMilliseconds)));
            AuditRaw("init", $"build={Build} bridge={_resolvedBridgePath} symbol={SymbolName} risk_capital_source={(UseBalanceForRisk ? "ctrader_balance" : "ctrader_equity")} use_bridge_risk_pct={UseBridgeRiskPct} margin_guard={UseMarginShrinkGuard} max_margin_pct={MaxMarginUsagePct:F1}");
            RepairOpenPositionStates("init");

            if (IgnoreExistingSignalOnInit)
            {
                if (TryReadSignal(out var sig, out var detail) && SignalIdentityMatches(sig, out _))
                {
                    var age = (Server.Time.ToUniversalTime() - sig.WrittenGmt.ToUniversalTime()).TotalSeconds;
                    if (MaxSignalAgeSeconds > 0 && age <= MaxSignalAgeSeconds)
                    {
                        Audit("init_existing_fresh_signal_pending", sig, $"seeded_last_seen=0 trade_on_next_poll age_sec={age:F0} max={MaxSignalAgeSeconds} " + detail);
                    }
                    else
                    {
                        _lastSeenEventId = sig.EventId;
                        Audit("init_baseline_existing_signal", sig, $"seeded_last_seen=1 no_trade_on_attach age_sec={age:F0} max={MaxSignalAgeSeconds} " + detail);
                    }
                }
                else
                {
                    AuditRaw("init_baseline_empty", detail);
                }
            }

            DrawDashboard();
        }

        protected override void OnTimer()
        {
            PollBridge("timer");
            RepairOpenPositionStates("timer");
            ManageHalfClose();
            ManageEmergencyCloses();
            DrawDashboard();
        }

        protected override void OnTick()
        {
            ManageHalfClose();
            ManageEmergencyCloses();
        }

        private void PollBridge(string caller)
        {
            if (!TryReadSignal(out var sig, out var detail))
            {
                SetAction("read_failed", detail);
                var initMarker = detail.IndexOf("bridge_init_marker", StringComparison.OrdinalIgnoreCase) >= 0
                              || detail.IndexOf("source=bridge_initiated", StringComparison.OrdinalIgnoreCase) >= 0
                              || detail.IndexOf("dir=INIT", StringComparison.OrdinalIgnoreCase) >= 0;
                var sinceLastAudit = (DateTime.UtcNow - _lastReadFailAudit).TotalSeconds;
                var initChanged = initMarker && !string.Equals(_lastInitMarkerAuditKey, detail, StringComparison.Ordinal);
                var readFailureChanged = !initMarker && !string.Equals(_lastReadFailAuditKey, detail, StringComparison.Ordinal);
                var auditDue = initMarker ? (initChanged || sinceLastAudit >= 21600) : (readFailureChanged || sinceLastAudit >= 300);
                if (auditDue)
                {
                    _lastReadFailAudit = DateTime.UtcNow;
                    if (initMarker) _lastInitMarkerAuditKey = detail;
                    else _lastReadFailAuditKey = detail;
                    AuditRaw(initMarker ? "bridge_initiated_seen" : "read_failed", $"caller={caller} {detail}");
                }
                return;
            }

            if (PollHeartbeatSeconds > 0 && (DateTime.UtcNow - _lastPollHeartbeat).TotalSeconds >= PollHeartbeatSeconds)
            {
                _lastPollHeartbeat = DateTime.UtcNow;
                AuditRaw("poll_heartbeat", $"caller={caller} {detail} last_seen={_lastSeenEventId} last_rejected={_lastRejectedEventId}");
            }

            if (SignalIdentityMatches(sig, out _))
                RepairOpenPositionStates("poll_identity_match");

            if (sig.EventId == _lastSeenEventId || (PermanentRejectGuard && sig.EventId == _lastRejectedEventId))
            {
                SetAction("idle_duplicate_latest", ShortEvent(sig.EventId));
                return;
            }

            if (!SignalIdentityMatches(sig, out var identityReason))
            {
                if (PermanentRejectGuard)
                    _lastRejectedEventId = sig.EventId;
                Audit("skip_filter", sig, $"caller={caller} {identityReason} {detail}");
                return;
            }

            if (OrderRetryBlocked(sig, out var retryBlockDetail))
            {
                SetAction("order_retry_cooldown", retryBlockDetail);
                return;
            }

            Audit("signal_received", sig, $"caller={caller} mapped_symbol={MapSymbol(sig.SourceSymbol)} {detail}");

            var age = (Server.Time.ToUniversalTime() - sig.WrittenGmt.ToUniversalTime()).TotalSeconds;
            if (MaxSignalAgeSeconds > 0 && age > MaxSignalAgeSeconds)
            {
                if (PermanentRejectGuard)
                    _lastRejectedEventId = sig.EventId;
                Audit("skip_stale", sig, $"age_sec={age:F0} max={MaxSignalAgeSeconds}");
                return;
            }

            if (!ExecutorEnabled)
            {
                _lastSeenEventId = sig.EventId;
                Audit("skip_executor_off", sig, "executor disabled");
                return;
            }

            if (EnableCloseOnlySignals && IsCloseOnlySignal(sig))
            {
                var ok = CloseSameDirectionPositions(sig, out var closeOnlyDetail);
                if (ok)
                    _lastSeenEventId = sig.EventId;
                else if (PermanentRejectGuard)
                    _lastRejectedEventId = sig.EventId;
                Audit("close_only_processed", sig, $"caller={caller} {closeOnlyDetail}");
                return;
            }

            if (MaxSpreadPips > 0 && CurrentSpreadPips() > MaxSpreadPips)
            {
                if (PermanentRejectGuard)
                    _lastRejectedEventId = sig.EventId;
                Audit("skip_spread", sig, $"spread_pips={CurrentSpreadPips():F2} max={MaxSpreadPips:F2}");
                return;
            }

            if (ExecuteSignal(sig))
                _lastSeenEventId = sig.EventId;
        }
        private void AuditPendingEventClaim(BridgeSignal sig, string eventName)
        {
            if (_eventClaimAuditAt.TryGetValue(sig.EventId, out var last) && (DateTime.UtcNow - last).TotalSeconds < 10)
                return;
            _eventClaimAuditAt[sig.EventId] = DateTime.UtcNow;
            Audit(eventName, sig, "pending_lock_exists_retry_later");
        }
        private bool OrderRetryBlocked(BridgeSignal sig, out string detail)
        {
            detail = string.Empty;
            if (string.IsNullOrWhiteSpace(sig.EventId))
                return false;
            if (!_orderRetryBlockedUntil.TryGetValue(sig.EventId, out var until))
                return false;
            var now = DateTime.UtcNow;
            if (now < until)
            {
                detail = $"event={ShortEvent(sig.EventId)} retry_after_utc={until:O} seconds_left={(until - now).TotalSeconds:F0}";
                return true;
            }
            _orderRetryBlockedUntil.Remove(sig.EventId);
            return false;
        }

        private void BlockOrderRetry(BridgeSignal sig, object error, string reason, int requestedSeconds = 0)
        {
            if (string.IsNullOrWhiteSpace(sig.EventId))
                return;
            var seconds = requestedSeconds > 0 ? Math.Max(5, requestedSeconds) : Math.Max(30, MarketClosedRetrySeconds);
            var until = DateTime.UtcNow.AddSeconds(seconds);
            _orderRetryBlockedUntil[sig.EventId] = until;
            Audit("order_retry_throttled", sig, $"reason={reason} error={error} retry_after_utc={until:O} cooldown_sec={seconds}");
        }
        private bool ExecuteSignal(BridgeSignal sig)
        {
            var tradeType = sig.Direction > 0 ? TradeType.Buy : TradeType.Sell;
            var entry = sig.Direction > 0 ? Symbol.Ask : Symbol.Bid;
            var rebaseDetail = "";
            var willRebase = ShouldRebaseLevels(sig);
            if (willRebase)
            {
                RebaseLevelsToLiveEntry(ref sig, entry, out rebaseDetail);
                if (!string.IsNullOrEmpty(rebaseDetail))
                    Audit("levels_rebased", sig, rebaseDetail);
            }
            else if (!ValidateMappedPriceBasis(sig, entry, out var basisDetail))
            {
                BlockOrderRetry(sig, "mapped_price_basis", "mapped_price_basis", Math.Max(5, OrderFailureRetrySeconds));
                Audit("skip_mapped_price_basis", sig, basisDetail);
                return false;
            }

            if (!ValidateStops(sig, entry, out var stopLossPips, out var takeProfitPips, out var stopDetail))
            {
                if (PermanentRejectGuard)
                    _lastRejectedEventId = sig.EventId;
                Audit("skip_geometry", sig, stopDetail + " " + StopContext(entry, sig.Sl, sig.Tp));
                return false;
            }

            if (!ClaimEvent(sig.EventId, out var committedDuplicate))
            {
                if (committedDuplicate)
                    Audit("skip_duplicate_global", sig, "committed_lock_exists");
                else
                    AuditPendingEventClaim(sig, "event_claim_pending");
                return committedDuplicate;
            }

            if (CloseReverse && !CloseReversePositions(sig, out var reverseDetail))
            {
                if (FailIfReverseCloseFails)
                {
                    ReleaseEvent(sig.EventId);
                    if (PermanentRejectGuard)
                        _lastRejectedEventId = sig.EventId;
                    Audit("skip_reverse_close_failed", sig, reverseDetail);
                    return false;
                }
                Audit("reverse_close_failed_continue", sig, reverseDetail);
            }

            var volume = ResolveVolume(sig, stopLossPips, out var lotDetail);
            if (volume <= 0)
            {
                ReleaseEvent(sig.EventId);
                if (PermanentRejectGuard)
                    _lastRejectedEventId = sig.EventId;
                Audit("skip_lot", sig, lotDetail);
                return false;
            }

            var label = BuildLabel(sig);
            var comment = BuildComment(sig);
            var result = ExecuteMarketOrder(tradeType, SymbolName, volume, label, stopLossPips, takeProfitPips, comment);
            var finalVolume = volume;
            var orderAuditPrefix = "";

            if (!result.IsSuccessful)
            {
                var originalError = result.Error;
                var retryDetail = "";
                var retryVolume = 0.0;
                if (NoMoneyRetryShrink && IsNoMoneyError(originalError))
                    retryVolume = ShrinkVolumeToFreeMargin(tradeType, volume, out retryDetail);

                if (retryVolume > 0 && retryVolume < volume)
                {
                    var retry = ExecuteMarketOrder(tradeType, SymbolName, retryVolume, label, stopLossPips, takeProfitPips, comment);
                    if (retry.IsSuccessful)
                    {
                        result = retry;
                        finalVolume = retryVolume;
                        orderAuditPrefix = $"original_error={originalError} original_volume={volume} retry_volume={retryVolume} {retryDetail} ";
                        Audit("order_sent_no_money_retry", sig, orderAuditPrefix + $"sl_pips={stopLossPips:F2} tp_pips={takeProfitPips:F2} {lotDetail}");
                    }
                    else
                    {
                        ReleaseEvent(sig.EventId);
                        var retryMarketClosed = IsMarketClosedError(retry.Error);
                        if (retryMarketClosed)
                            BlockOrderRetry(sig, retry.Error, "market_closed_retry");
                        else if (IsNoMoneyError(retry.Error))
                            BlockOrderRetry(sig, retry.Error, "no_money_retry", OrderFailureRetrySeconds);
                        if (PermanentRejectGuard && IsPermanentOrderFailure(retry.Error) && !retryMarketClosed)
                            _lastRejectedEventId = sig.EventId;
                        Audit("order_failed_no_money_retry", sig, $"original_error={originalError} retry_error={retry.Error} market_closed={(retryMarketClosed ? 1 : 0)} original_volume={volume} retry_volume={retryVolume} sl_pips={stopLossPips:F2} tp_pips={takeProfitPips:F2} {retryDetail} {lotDetail}");
                        return false;
                    }
                }
                else
                {
                    ReleaseEvent(sig.EventId);
                    var permanent = IsPermanentOrderFailure(originalError);
                    var marketClosed = IsMarketClosedError(originalError);
                    if (marketClosed)
                        BlockOrderRetry(sig, originalError, "market_closed");
                    else if (IsNoMoneyError(originalError))
                        BlockOrderRetry(sig, originalError, "no_money", OrderFailureRetrySeconds);
                    if (PermanentRejectGuard && permanent && !marketClosed)
                        _lastRejectedEventId = sig.EventId;
                    Audit("order_failed", sig, $"error={originalError} permanent_reject={(permanent ? 1 : 0)} market_closed={(marketClosed ? 1 : 0)} volume={volume} sl_pips={stopLossPips:F2} tp_pips={takeProfitPips:F2} {StopContext(entry, sig.Sl, sig.Tp)} {retryDetail} {lotDetail}");
                    return false;
                }
            }

            if (result.Position != null)
            {
                if (!ApplyExactBridgeProtection(sig, result.Position, out var exactDetail))
                {
                    Audit("exact_protection_failed", sig, exactDetail);
                    if (PermanentRejectGuard)
                        _lastRejectedEventId = sig.EventId;
                    if (FailIfExactProtectionFails)
                    {
                        var close = ClosePosition(result.Position);
                        Audit(close.IsSuccessful ? "exact_protection_fail_closed" : "exact_protection_fail_close_failed", sig, exactDetail + $" close_error={close.Error}");
                        if (!close.IsSuccessful) QueueEmergencyClose(result.Position, "exact_protection_failure_close_failed");
                        CommitEvent(sig.EventId, result.Position.Id, close.IsSuccessful ? "exact_protection_failed_closed" : "exact_protection_failed_emergency_close");
                        return true;
                    }
                }
                else if (!string.IsNullOrWhiteSpace(exactDetail))
                {
                    Audit("exact_protection_applied", sig, exactDetail);
                }
            }
            if (result.Position != null && !ValidatePostFillRisk(sig, result.Position, out var postFillRiskDetail))
            {
                var close = ClosePosition(result.Position);
                if (!close.IsSuccessful)
                    QueueEmergencyClose(result.Position, "post_fill_risk_guard_close_failed");
                CommitEvent(sig.EventId, result.Position.Id, close.IsSuccessful ? "post_fill_risk_guard_closed" : "post_fill_risk_guard_emergency_close");
                Audit(close.IsSuccessful ? "post_fill_risk_guard_closed" : "post_fill_risk_guard_close_failed", sig, postFillRiskDetail + $" close_error={close.Error}");
                return true;
            }
            if (result.Position != null && ManageHalfCloseBe && sig.HalfTrigger > 0)
            {
                var fill = result.Position.EntryPrice;
                _halfStates[result.Position.Id] = new HalfState
                {
                    EventId = sig.EventId,
                    SourceTf = NormalizeTf(sig.SourceTf),
                    Direction = sig.Direction,
                    Entry = fill,
                    HalfTrigger = sig.HalfTrigger,
                    InitialVolume = result.Position.VolumeInUnits,
                    StopLoss = sig.Sl,
                    TakeProfit = sig.Tp,
                    PartialClosed = false,
                    Done = false
                };
                SaveHalfState(result.Position.Id, _halfStates[result.Position.Id]);
            }

            CommitEvent(sig.EventId, result.Position?.Id ?? 0, "order_opened");
            Audit("order_sent", sig, orderAuditPrefix + $"position={result.Position?.Id} volume={result.Position?.VolumeInUnits ?? finalVolume} live_entry={entry} fill_entry={result.Position?.EntryPrice ?? entry} sl_pips={stopLossPips:F2} tp_pips={takeProfitPips:F2} rebase={rebaseDetail} {lotDetail}");
            return true;
        }
        private bool ValidatePostFillRisk(BridgeSignal sig, Position position, out string detail)
        {
            detail = "post_fill_risk_guard_not_required";
            if (!PostFillRiskGuard || !UseRiskLot || position == null)
                return true;
            if (sig.Sl <= 0 || Symbol.PipSize <= 0)
            {
                detail = $"invalid_post_fill_risk_geometry position={position?.Id} fill={position?.EntryPrice} sl={sig.Sl} pip_size={Symbol.PipSize}";
                return !FailClosedOnRiskError;
            }

            try
            {
                var effectiveRiskPct = UseBridgeRiskPct && sig.RiskPct > 0 ? sig.RiskPct : LocalRiskPct;
                var riskCapital = UseBalanceForRisk ? Account.Balance : Account.Equity;
                var allowedRisk = riskCapital * Math.Max(0.0, effectiveRiskPct) / 100.0;
                var actualRiskPips = Math.Abs(position.EntryPrice - sig.Sl) / Symbol.PipSize;
                var actualRisk = Symbol.AmountRisked(position.VolumeInUnits, actualRiskPips);
                var allowedWithTolerance = allowedRisk * (1.0 + Math.Max(0.0, MaxRiskOvershootPct) / 100.0);
                detail = $"position={position.Id} fill={position.EntryPrice} exact_sl={sig.Sl} volume={position.VolumeInUnits} actual_risk_pips={actualRiskPips:F2} actual_risk={actualRisk:F2} allowed_risk={allowedRisk:F2} allowed_with_tolerance={allowedWithTolerance:F2} risk_pct={effectiveRiskPct:F4} capital={riskCapital:F2}";
                return allowedRisk > 0 && actualRisk <= allowedWithTolerance;
            }
            catch (Exception ex)
            {
                detail = $"post_fill_risk_calculation_failed position={position.Id} error={ex.Message}";
                return !FailClosedOnRiskError;
            }
        }
        private double ResolveVolume(BridgeSignal sig, double stopLossPips, out string detail)
        {
            if (!UseRiskLot)
            {
                var manual = Symbol.NormalizeVolumeInUnits(ManualVolumeInUnits, RoundingMode.Down);
                detail = $"manual_volume={manual}";
                return manual;
            }

            var effectiveRiskPct = UseBridgeRiskPct && sig.RiskPct > 0 ? sig.RiskPct : LocalRiskPct;
            var riskCapital = UseBalanceForRisk ? Account.Balance : Account.Equity;
            var riskMoney = riskCapital * Math.Max(0, effectiveRiskPct) / 100.0;

            if (riskMoney <= 0 || stopLossPips <= 0)
            {
                detail = $"risk_unavailable risk_money={riskMoney:F2} stop_loss_pips={stopLossPips:F2}";
                return 0;
            }

            double volume;
            try
            {
                volume = Symbol.VolumeForFixedRisk(riskMoney, stopLossPips, RoundingMode.Down);
            }
            catch (Exception ex)
            {
                detail = $"volume_for_fixed_risk_failed error={ex.Message} risk_money={riskMoney:F2} stop_loss_pips={stopLossPips:F2}";
                return 0;
            }

            if (MaxVolumeInUnits > 0)
                volume = Math.Min(volume, MaxVolumeInUnits);

            var minRisk = Symbol.AmountRisked(Symbol.VolumeInUnitsMin, stopLossPips);
            if (BlockIfMinVolumeExceedsRisk && volume < Symbol.VolumeInUnitsMin && minRisk > riskMoney * 1.001)
            {
                detail = $"min_volume_exceeds_risk risk_money={riskMoney:F2} stop_loss_pips={stopLossPips:F2} raw_volume={volume} min_volume={Symbol.VolumeInUnitsMin} min_volume_risk={minRisk:F2}";
                return 0;
            }

            volume = Symbol.NormalizeVolumeInUnits(volume, RoundingMode.Down);
            if (volume < Symbol.VolumeInUnitsMin)
            {
                detail = $"volume_below_min risk_money={riskMoney:F2} stop_loss_pips={stopLossPips:F2} raw_volume={volume} min={Symbol.VolumeInUnitsMin}";
                return FailClosedOnRiskError ? 0 : Symbol.NormalizeVolumeInUnits(ManualVolumeInUnits, RoundingMode.Down);
            }

            var estimatedRisk = Symbol.AmountRisked(volume, stopLossPips);
            if (BlockIfMinVolumeExceedsRisk && estimatedRisk > riskMoney * 1.001)
            {
                detail = $"normalized_volume_exceeds_risk risk_money={riskMoney:F2} stop_loss_pips={stopLossPips:F2} volume={volume} estimated_risk={estimatedRisk:F2}";
                return 0;
            }

            var marginDetail = "";
            if (UseMarginShrinkGuard && MaxMarginUsagePct > 0)
            {
                var dir = sig.Direction > 0 ? TradeType.Buy : TradeType.Sell;
                var shrunk = ShrinkVolumeToMarginLimit(dir, volume, MaxMarginUsagePct, out marginDetail);
                if (shrunk <= 0)
                {
                    detail = marginDetail;
                    return 0;
                }
                volume = shrunk;
                estimatedRisk = Symbol.AmountRisked(volume, stopLossPips);
            }
            detail = "risk_lot"
                + $" risk_pct={effectiveRiskPct:F3}"
                + $" pct_source={(UseBridgeRiskPct && sig.RiskPct > 0 ? "bridge" : "local")}"
                + $" risk_capital_source={(UseBalanceForRisk ? "ctrader_balance" : "ctrader_equity")}"
                + $" risk_capital={riskCapital:F2}"
                + $" risk_money={riskMoney:F2}"
                + $" stop_loss_pips={stopLossPips:F2}"
                + $" volume={volume}"
                + $" estimated_risk={estimatedRisk:F2}"
                + (string.IsNullOrEmpty(marginDetail) ? "" : " " + marginDetail);
            return volume;
        }

        private bool ApplyExactBridgeProtection(BridgeSignal sig, Position position, out string detail)
        {
            detail = "";
            if (position == null)
            {
                detail = "position_null";
                return false;
            }

            var tick = Symbol.TickSize > 0 ? Symbol.TickSize : Symbol.PipSize;
            var tolerance = Math.Max(tick * 0.5, 0.00000001);
            var beforeSl = position.StopLoss;
            var beforeTp = position.TakeProfit;
            var slDiff = !beforeSl.HasValue || Math.Abs(beforeSl.Value - sig.Sl) > tolerance;
            var tpDiff = !beforeTp.HasValue || Math.Abs(beforeTp.Value - sig.Tp) > tolerance;
            if (!slDiff && !tpDiff)
            {
                detail = $"already_exact pos={position.Id} sl={FormatNullable(beforeSl)} tp={FormatNullable(beforeTp)} exact_sl={sig.Sl} exact_tp={sig.Tp}";
                return true;
            }

            var mod = ModifyPosition(position, sig.Sl, sig.Tp, ProtectionType.Absolute);
            detail = $"pos={position.Id} before_sl={FormatNullable(beforeSl)} before_tp={FormatNullable(beforeTp)} exact_sl={sig.Sl} exact_tp={sig.Tp} tick={tick} modify_error={mod.Error}";
            return mod.IsSuccessful;
        }

        private static string FormatNullable(double? value)
        {
            return value.HasValue ? value.Value.ToString("G17", CultureInfo.InvariantCulture) : "null";
        }
        private bool ValidateStops(BridgeSignal sig, double entry, out double stopLossPips, out double takeProfitPips, out string detail)
        {
            stopLossPips = 0;
            takeProfitPips = 0;
            if (sig.Direction > 0)
            {
                stopLossPips = (entry - sig.Sl) / Symbol.PipSize;
                takeProfitPips = (sig.Tp - entry) / Symbol.PipSize;
            }
            else
            {
                stopLossPips = (sig.Sl - entry) / Symbol.PipSize;
                takeProfitPips = (entry - sig.Tp) / Symbol.PipSize;
            }

            if (stopLossPips <= 0 || takeProfitPips <= 0)
            {
                detail = $"invalid_sl_tp entry={entry} sl={sig.Sl} tp={sig.Tp} sl_pips={stopLossPips:F2} tp_pips={takeProfitPips:F2}";
                return false;
            }

            detail = "ok";
            return true;
        }

        private bool IsCloseOnlySignal(BridgeSignal sig)
        {
            return ContainsText(sig.Source, "CloseOnly") || ContainsText(sig.EventId, "invalidate_close");
        }

        private bool CloseSameDirectionPositions(BridgeSignal sig, out string detail)
        {
            detail = "";
            var target = sig.Direction > 0 ? TradeType.Buy : TradeType.Sell;
            var positions = ScopedPositions(sig).Where(p => p.TradeType == target).ToArray();
            var found = 0;
            var closed = 0;
            var failed = 0;
            foreach (var p in positions)
            {
                found++;
                var pnl = p.NetProfit;
                var res = ClosePosition(p);
                if (!res.IsSuccessful)
                {
                    failed++;
                    detail += $" close_failed pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} err={res.Error}";
                    Audit("close_only_failed", sig, $"pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} err={res.Error}");
                    continue;
                }
                closed++;
                detail += $" closed_same pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2}";
                Audit("close_only_sent", sig, $"pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2}");
            }
            if (found == 0)
                Audit("close_only_none", sig, "no_same_direction_position_in_scope");
            detail = $"close_only_found={found} closed={closed} failed={failed}" + detail;
            return failed == 0;
        }

        private bool CloseReversePositions(BridgeSignal sig, out string detail)
        {
            detail = "";
            var targetType = sig.Direction > 0 ? TradeType.Buy : TradeType.Sell;
            var reverse = targetType == TradeType.Buy ? TradeType.Sell : TradeType.Buy;
            var positions = ScopedPositions(sig).Where(p => p.TradeType == reverse).ToArray();
            var found = 0;
            var closed = 0;
            var failed = 0;

            foreach (var p in positions)
            {
                found++;
                var pnl = p.NetProfit;
                var res = ClosePosition(p);
                if (!res.IsSuccessful)
                {
                    failed++;
                    detail += $" close_failed pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} err={res.Error}";
                    Audit("reverse_close_failed", sig, $"pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} err={res.Error}");
                    continue;
                }
                closed++;
                detail += $" closed_reverse pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2}";
                Audit("reverse_close_sent", sig, $"pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2}");
            }

            if (found == 0)
                Audit("reverse_close_none", sig, "no_reverse_position_in_scope");
            detail = $"reverse_found={found} closed={closed} failed={failed} scope={(CloseReverseAcrossSourceTf ? "all_source_tf" : "same_source_tf")}" + detail;
            return failed == 0;
        }

        private IEnumerable<Position> ScopedPositions(BridgeSignal sig)
        {
            var sourceTf = NormalizeTf(sig.SourceTf);
            foreach (var p in Positions)
            {
                if (!SameText(p.SymbolName, SymbolName))
                    continue;
                if (string.IsNullOrWhiteSpace(p.Label) || !p.Label.StartsWith(LabelPrefix, StringComparison.Ordinal))
                    continue;
                if (!CloseReverseAcrossSourceTf)
                {
                    var posTf = PositionSourceTf(p);
                    if (!string.IsNullOrWhiteSpace(sourceTf) && !string.IsNullOrWhiteSpace(posTf) && !SameText(sourceTf, posTf))
                        continue;
                }
                yield return p;
            }
        }

        private bool PositionBelongsToThisInstance(Position p)
        {
            if (p == null || !SameText(p.SymbolName, SymbolName))
                return false;
            var expectedTf = EffectiveSourceTf();
            if (string.IsNullOrWhiteSpace(expectedTf))
                return true;
            var positionTf = PositionSourceTf(p);
            return !string.IsNullOrWhiteSpace(positionTf) && SameText(expectedTf, positionTf);
        }
        private string PositionSourceTf(Position p)
        {
            var labelTf = LabelSourceTf(p.Label);
            if (!string.IsNullOrWhiteSpace(labelTf))
                return labelTf;
            var commentTf = ParseCommentString(p.Comment, "tf");
            return NormalizeTf(commentTf);
        }

        private string LabelSourceTf(string label)
        {
            if (string.IsNullOrWhiteSpace(label))
                return "";
            foreach (var part in label.Split('|'))
            {
                if (part.Length > 1 && (part[0] == 'T' || part[0] == 't'))
                    return NormalizeTf(part.Substring(1));
            }
            return "";
        }

        private string BuildComment(BridgeSignal sig)
        {
            return $"event={ShortEvent(sig.EventId)};src={sig.Source};tf={NormalizeTf(sig.SourceTf)};half={sig.HalfTrigger.ToString(CultureInfo.InvariantCulture)};sl={sig.Sl.ToString(CultureInfo.InvariantCulture)};tp={sig.Tp.ToString(CultureInfo.InvariantCulture)}";
        }

        private string StopContext(double entry, double sl, double tp)
        {
            var spreadPips = CurrentSpreadPips();
            return $"bid={Symbol.Bid} ask={Symbol.Ask} entry={entry} sl_dist={Math.Abs(entry - sl):F5} tp_dist={Math.Abs(entry - tp):F5} spread_pips={spreadPips:F2}";
        }

        private double CurrentSpreadPips()
        {
            return Symbol.Spread;
        }
        private bool IsPermanentOrderFailure(object error)
        {
            var e = (error == null ? "" : error.ToString()).ToLowerInvariant().Replace("_", "").Replace(" ", "");
            return e.Contains("invalid") || e.Contains("badvolume") || e.Contains("badvolume") || e.Contains("stoploss") || e.Contains("takeprofit");
        }

        private bool IsMarketClosedError(object error)
        {
            var e = (error == null ? "" : error.ToString()).ToLowerInvariant().Replace("_", "").Replace(" ", "").Replace(":", "");
            return e.Contains("marketclosed") || e.Contains("marketisclosed") || e.Contains("tradingisnotavailable") || e.Contains("notavailable") || e.Contains("offquotes");
        }

        private bool IsNoMoneyError(object error)
        {
            var e = (error == null ? "" : error.ToString()).ToLowerInvariant().Replace("_", "").Replace(" ", "");
            return e.Contains("nomoney") || e.Contains("notenoughmoney") || e.Contains("insufficient") || e.Contains("margin");
        }
        private void ManageHalfClose()
        {
            if (!ManageHalfCloseBe || _halfStates.Count == 0)
                return;

            foreach (var kv in _halfStates.ToArray())
            {
                var pos = Positions.FirstOrDefault(p => p.Id == kv.Key);
                if (pos == null)
                {
                    _halfStates.Remove(kv.Key);
                    _halfRetryAt.Remove(kv.Key);
                    DeleteHalfState(kv.Key);
                    continue;
                }

                if (_halfRetryAt.TryGetValue(kv.Key, out var retryAt))
                {
                    if (DateTime.UtcNow < retryAt)
                        continue;
                    _halfRetryAt.Remove(kv.Key);
                }

                var st = kv.Value;
                var persistedPhase = LoadHalfStatePhase(kv.Key);
                if (persistedPhase == "done")
                {
                    st.PartialClosed = true;
                    st.Done = true;
                    _halfStates[kv.Key] = st;
                    continue;
                }
                if (persistedPhase == "partial")
                    st.PartialClosed = true;
                if (st.Done || st.HalfTrigger <= 0)
                    continue;

                if (st.PartialClosed)
                {
                    TryFinishBreakEven(pos, kv.Key, ref st, "halfbe_retry_after_partial");
                    continue;
                }

                var triggerPx = st.Direction > 0 ? Symbol.Bid : Symbol.Ask;
                var reached = st.Direction > 0 ? Symbol.Bid >= st.HalfTrigger : Symbol.Ask <= st.HalfTrigger;
                if (!reached)
                    continue;

                var desiredClose = pos.VolumeInUnits * Math.Max(0.0, Math.Min(1.0, HalfCloseFraction));
                var closeVolume = Symbol.NormalizeVolumeInUnits(desiredClose, RoundingMode.Down);
                var minVolume = Symbol.VolumeInUnitsMin;
                if (closeVolume <= 0 || closeVolume >= pos.VolumeInUnits || pos.VolumeInUnits - closeVolume < minVolume)
                {
                    var maxClosable = Symbol.NormalizeVolumeInUnits(pos.VolumeInUnits - minVolume, RoundingMode.Down);
                    if (maxClosable > 0 && maxClosable < pos.VolumeInUnits)
                        closeVolume = maxClosable;
                }

                var remainingVolume = Symbol.NormalizeVolumeInUnits(pos.VolumeInUnits - closeVolume, RoundingMode.Down);
                var riskPips = Math.Abs(st.Entry - st.StopLoss) / Symbol.PipSize;
                var hcPips = Math.Abs(st.HalfTrigger - st.Entry) / Symbol.PipSize;
                var hcR = riskPips > 0 ? hcPips / riskPips : 0;
                var expectedFullRisk = riskPips > 0 ? Symbol.AmountRisked(pos.VolumeInUnits, riskPips) : 0;
                var expectedHalfPnl = hcPips > 0 && closeVolume > 0 ? Symbol.AmountRisked(closeVolume, hcPips) : 0;
                var baseDetail = $"pos={pos.Id} label={pos.Label} src_tf={st.SourceTf} type={pos.TradeType} entry={st.Entry} hc={st.HalfTrigger} trigger_px={triggerPx} volume={pos.VolumeInUnits} desired_close={desiredClose} close_volume={closeVolume} remaining_volume={remainingVolume} min_volume={minVolume} fraction={HalfCloseFraction:F2} sl={st.StopLoss} tp={st.TakeProfit} risk_pips={riskPips:F2} hc_pips={hcPips:F2} hc_r={hcR:F3} expected_full_risk={expectedFullRisk:F2} expected_half_pnl_at_hc={expectedHalfPnl:F2}";

                if (closeVolume <= 0 || closeVolume >= pos.VolumeInUnits || remainingVolume < minVolume)
                {
                    _halfRetryAt[kv.Key] = DateTime.UtcNow.AddSeconds(Math.Max(5, HalfBeVolumeRetrySeconds));
                    AuditRaw("halfbe_blocked_volume", baseDetail + $" reason=partial_close_impossible_for_broker_volume retry_sec={Math.Max(5, HalfBeVolumeRetrySeconds)}");
                    continue;
                }

                var close = ClosePosition(pos, closeVolume);
                if (!close.IsSuccessful)
                {
                    _halfRetryAt[kv.Key] = DateTime.UtcNow.AddSeconds(Math.Max(1, HalfBeRetrySeconds));
                    AuditRaw("halfbe_partial_close_failed", baseDetail + $" err={close.Error} retry_sec={Math.Max(1, HalfBeRetrySeconds)}");
                    continue;
                }

                st.PartialClosed = true;
                SaveHalfState(kv.Key, st);
                var remaining = Positions.FirstOrDefault(p => p.Id == pos.Id) ?? Positions.FirstOrDefault(p => p.SymbolName == SymbolName && p.Label == pos.Label);
                if (remaining == null)
                {
                    st.Done = true;
                    SaveHalfState(kv.Key, st);
                    _halfStates[kv.Key] = st;
                    AuditRaw("halfbe_partial_close_success_position_closed", baseDetail);
                    continue;
                }

                if (remaining.Id != kv.Key)
                {
                    _halfStates.Remove(kv.Key);
                    DeleteHalfState(kv.Key);
                    _halfStates[remaining.Id] = st;
                    SaveHalfState(remaining.Id, st);
                }
                TryFinishBreakEven(remaining, remaining.Id, ref st, baseDetail);
            }
        }

        private void TryFinishBreakEven(Position remaining, long stateId, ref HalfState st, string baseDetail)
        {
            var be = remaining.EntryPrice;
            var mod = ModifyPosition(remaining, be, remaining.TakeProfit, ProtectionType.Absolute);
            if (mod.IsSuccessful)
            {
                st.Done = true;
                st.PartialClosed = true;
                _halfRetryAt.Remove(stateId);
                SaveHalfState(stateId, st);
                AuditRaw("halfbe_done", baseDetail + $" be_sl={be} remaining_after={remaining.VolumeInUnits} modify_err={mod.Error}");
            }
            else
            {
                st.Done = false;
                st.PartialClosed = true;
                _halfRetryAt[stateId] = DateTime.UtcNow.AddSeconds(Math.Max(1, HalfBeRetrySeconds));
                SaveHalfState(stateId, st);
                AuditRaw("halfbe_sl_to_be_retry_pending", baseDetail + $" be_sl={be} remaining_after={remaining.VolumeInUnits} modify_err={mod.Error} retry_sec={Math.Max(1, HalfBeRetrySeconds)}");
            }
            _halfStates[stateId] = st;
        }
        private bool TryReadSignal(out BridgeSignal sig, out string detail)
        {
            sig = new BridgeSignal();
            detail = "";
            var readPath = ResolveBridgeReadPath();
            if (!IoFile.Exists(readPath))
            {
                detail = "file_not_found " + readPath;
                return false;
            }

            string text;
            try
            {
                text = IoFile.ReadAllText(readPath);
            }
            catch (Exception ex)
            {
                detail = "file_read_failed " + ex.Message;
                return false;
            }

            var fields = ParseCsvFlat(text);
            if (fields.Count < 17)
            {
                detail = "not_enough_fields count=" + fields.Count;
                return false;
            }

            var offset = 0;
            if (fields[0] == "version")
            {
                offset = 17;
                if (fields.Count > 17 && fields[17] == "risk_pct")
                    offset = 18;
            }
            if (fields.Count < offset + 17)
            {
                detail = $"not_enough_data_fields count={fields.Count} offset={offset}";
                return false;
            }

            sig.Version = fields[offset + 0];
            sig.WrittenGmt = ParseDate(fields[offset + 1]);
            sig.SourceLogin = fields[offset + 2];
            sig.SourceSymbol = fields[offset + 3];
            sig.SourceTf = fields[offset + 4];
            sig.EventId = fields[offset + 5];
            sig.Source = fields[offset + 6];
            sig.Direction = fields[offset + 7] == "BUY" ? 1 : fields[offset + 7] == "SELL" ? -1 : 0;
            sig.SignalTime = ParseDate(fields[offset + 8]);
            sig.BridgeEntry = ParseDouble(fields[offset + 9]);
            sig.Sl = ParseDouble(fields[offset + 10]);
            sig.Tp = ParseDouble(fields[offset + 11]);
            sig.HalfTrigger = ParseDouble(fields[offset + 12]);
            sig.HalfLabel = fields[offset + 13];
            sig.SourceBuild = fields[offset + 14];
            sig.SourceBid = ParseDouble(fields[offset + 15]);
            sig.SourceAsk = ParseDouble(fields[offset + 16]);
            sig.RiskPct = fields.Count > offset + 17 ? ParseDouble(fields[offset + 17]) : 0;
            var rawDir = fields[offset + 7];
            sig.Valid = !string.IsNullOrWhiteSpace(sig.EventId) && sig.Direction != 0;

            detail = $"read_ok path={IoPath.GetFileName(readPath)} fields={fields.Count} offset={offset} event={sig.EventId} source_symbol={sig.SourceSymbol} source_tf={sig.SourceTf} dir={rawDir} risk_pct={sig.RiskPct:F3}";
            if (!sig.Valid)
            {
                var initMarker = SameText(sig.Source, "bridge_initiated") || SameText(rawDir, "INIT");
                detail = (initMarker ? "bridge_init_marker " : "invalid_parsed_signal ") + detail;
            }
            return sig.Valid;
        }

        private bool SignalIdentityMatches(BridgeSignal sig, out string reason)
        {
            reason = "";
            var mapped = MapSymbol(sig.SourceSymbol);
            if (RequireMappedSymbolEqualsChart && !SameText(mapped, SymbolName) && !SameEconomicSymbol(mapped, SymbolName))
            {
                reason = $"symbol_filter source={sig.SourceSymbol} mapped={mapped} chart={SymbolName}";
                return false;
            }

            var tfFilter = SourceTimeframeFilter?.Trim() ?? "";
            if (string.IsNullOrWhiteSpace(tfFilter) && DefaultSourceTfToChartPeriod)
                tfFilter = ChartTfString();
            if (!string.IsNullOrWhiteSpace(tfFilter) && NormalizeTf(tfFilter) != NormalizeTf(sig.SourceTf))
            {
                reason = $"tf_filter source={sig.SourceTf} expected={tfFilter}";
                return false;
            }

            var expectedSource = string.IsNullOrWhiteSpace(SourceFilter)
                ? "LiqNarrativeSolAdvanced|"
                : (SourceFilter.Trim().Contains("|") ? SourceFilter.Trim() : SourceFilter.Trim() + "|");
            if (string.IsNullOrWhiteSpace(sig.Source) || !sig.Source.StartsWith(expectedSource, StringComparison.OrdinalIgnoreCase))
            {
                reason = $"source_filter source={sig.Source} expected_namespace={expectedSource}";
                return false;
            }
            return true;
        }

        private string ResolveBridgeReadPath()
        {
            if (!PreferScopedLatest || string.IsNullOrWhiteSpace(_resolvedBridgePath))
                return _resolvedBridgePath;
            var fileName = IoPath.GetFileName(_resolvedBridgePath) ?? "";
            const string latestSuffix = "_Latest.csv";
            if (!fileName.EndsWith(latestSuffix, StringComparison.OrdinalIgnoreCase))
                return _resolvedBridgePath;
            var scopedPrefix = fileName.Substring(0, fileName.Length - latestSuffix.Length) + "_Latest_";
            var dir = IoPath.GetDirectoryName(_resolvedBridgePath) ?? "";
            var tf = NormalizeTf(string.IsNullOrWhiteSpace(SourceTimeframeFilter) && DefaultSourceTfToChartPeriod ? ChartTfString() : SourceTimeframeFilter);
            if (string.IsNullOrWhiteSpace(tf))
                return _resolvedBridgePath;
            string newestCandidate = null;
            var newestWrite = DateTime.MinValue;
            foreach (var symbol in ScopedSourceSymbolCandidates())
            {
                var candidate = IoPath.Combine(dir, $"{scopedPrefix}{Sanitize(symbol)}_{tf}.csv");
                if (!IoFile.Exists(candidate))
                    continue;
                DateTime writeTime;
                try { writeTime = IoFile.GetLastWriteTimeUtc(candidate); }
                catch { continue; }
                if (newestCandidate == null || writeTime > newestWrite)
                {
                    newestCandidate = candidate;
                    newestWrite = writeTime;
                }
            }
            return newestCandidate ?? _resolvedBridgePath;
        }

        private IEnumerable<string> ScopedSourceSymbolCandidates()
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var s in BuildScopedSourceSymbolCandidates())
            {
                if (!string.IsNullOrWhiteSpace(s) && seen.Add(s))
                    yield return s;
            }
        }

        private IEnumerable<string> BuildScopedSourceSymbolCandidates()
        {
            var raw = (SymbolName ?? "").Trim();
            var canonical = CanonicalSymbol(raw);
            if (!string.IsNullOrWhiteSpace(raw)) yield return raw;
            if (!string.IsNullOrWhiteSpace(canonical)) yield return canonical;
            if (!string.IsNullOrWhiteSpace(canonical) && !canonical.EndsWith("M", StringComparison.OrdinalIgnoreCase)) yield return canonical + "m";
            if (canonical == "US30" || canonical == "WALLSTREET30") yield return "US30m";
            if (canonical == "US500" || canonical == "SPX500") yield return "US500m";
            if (canonical == "USTEC" || canonical == "US100" || canonical == "NAS100") yield return "USTECm";
            if (canonical == "DE30" || canonical == "GERMANY40" || canonical == "DAX40") yield return "DE30m";
            if (canonical == "JP225" || canonical == "JPN225") yield return "JP225m";
            if (canonical == "UKOIL" || canonical == "XBRUSD") yield return "UKOILm";
            if (canonical == "USOIL" || canonical == "XTIUSD") yield return "USOILm";
        }
        private string ResolveBridgePath()
        {
            if (!string.IsNullOrWhiteSpace(BridgeLatestPath))
                return BridgeLatestPath.Trim();
            return IoPath.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MetaQuotes", "Terminal", "Common", "Files", "LiqNarrativeSolAdvancedBridge_Latest.csv");
        }

        private string BuildLabel(BridgeSignal sig) => $"{LabelPrefix}|T{NormalizeTf(sig.SourceTf)}|{Hash64(sig.EventId):X16}";

        private bool ClaimEvent(string eventId, out bool committedDuplicate)
        {
            committedDuplicate = false;
            var legacyPath = LegacyEventLockPath(eventId);
            if (IoFile.Exists(legacyPath))
            {
                try
                {
                    var legacy = IoFile.ReadAllText(legacyPath);
                    if (legacy.IndexOf(eventId, StringComparison.Ordinal) >= 0)
                    {
                        committedDuplicate = true;
                        return false;
                    }
                }
                catch { }
            }

            if (HasPositionForEvent(eventId))
            {
                CommitEvent(eventId, 0, "reconciled_open_position_without_lock");
                committedDuplicate = true;
                return false;
            }

            var lockPath = EventLockPath(eventId);
            if (IoFile.Exists(lockPath))
            {
                try
                {
                    var payload = IoFile.ReadAllText(lockPath);
                    if (payload.StartsWith("committed\t", StringComparison.Ordinal) && payload.IndexOf("\t" + eventId, StringComparison.Ordinal) >= 0)
                    {
                        committedDuplicate = true;
                        return false;
                    }
                    if (HasPositionForEvent(eventId))
                    {
                        CommitEvent(eventId, 0, "reconciled_open_position");
                        committedDuplicate = true;
                        return false;
                    }
                    var age = DateTime.UtcNow - IoFile.GetLastWriteTimeUtc(lockPath);
                    if (age.TotalSeconds < 120)
                        return false;
                    IoFile.Delete(lockPath);
                }
                catch
                {
                    return false;
                }
            }

            try
            {
                using (var fs = new IoFileStream(lockPath, IoFileMode.CreateNew, IoFileAccess.Write, IoFileShare.None))
                using (var sw = new IoStreamWriter(fs))
                    sw.WriteLine("pending\t" + DateTime.UtcNow.ToString("O") + "\t" + eventId);
                return true;
            }
            catch (IoException)
            {
                return false;
            }
        }

        private void CommitEvent(string eventId, long positionId, string outcome)
        {
            try
            {
                WriteStateAtomically(EventLockPath(eventId), "committed\t" + DateTime.UtcNow.ToString("O") + "\t" + eventId + "\t" + positionId.ToString(CultureInfo.InvariantCulture) + "\t" + (outcome ?? ""));
            }
            catch (Exception ex)
            {
                AuditRaw("event_commit_failed", $"event={ShortEvent(eventId)} position={positionId} error={ex.Message}");
            }
        }

        private bool HasPositionForEvent(string eventId)
        {
            var token64 = "|" + Hash64(eventId).ToString("X16", CultureInfo.InvariantCulture);
            var legacyToken32 = "|" + Hash32(eventId).ToString("X8", CultureInfo.InvariantCulture);
            return Positions.Any(p => SameText(p.SymbolName, SymbolName)
                                      && !string.IsNullOrWhiteSpace(p.Label)
                                      && p.Label.StartsWith(LabelPrefix, StringComparison.Ordinal)
                                      && (p.Label.EndsWith(token64, StringComparison.OrdinalIgnoreCase)
                                          || p.Label.EndsWith(legacyToken32, StringComparison.OrdinalIgnoreCase)));
        }

        private string EventLockPath(string eventId) => IoPath.Combine(_lockDir, $"{Account.Number}_{Sanitize(SymbolName)}_{Hash64(eventId):X16}.lock");
        private string LegacyEventLockPath(string eventId) => IoPath.Combine(_lockDir, $"{Account.Number}_{Sanitize(SymbolName)}_{Hash32(eventId):X8}.lock");

        private void ReleaseEvent(string eventId)
        {
            var lockPath = EventLockPath(eventId);
            try { if (IoFile.Exists(lockPath)) IoFile.Delete(lockPath); } catch { }
        }
        private string MapSymbol(string source)
        {
            var mapped = MapSymbolFromCsv(source, SymbolMapCsv);
            if (!string.IsNullOrWhiteSpace(mapped))
                return mapped;
            if (UseBuiltInOilSymbolMap)
            {
                mapped = MapSymbolFromCsv(source, BuiltInOilSymbolMapCsv);
                if (!string.IsNullOrWhiteSpace(mapped))
                    return mapped;
            }
            if (UseBuiltInIndexSymbolMap)
            {
                mapped = MapSymbolFromCsv(source, BuiltInIndexSymbolMapCsv);
                if (!string.IsNullOrWhiteSpace(mapped))
                    return mapped;
            }
            mapped = HardBrokerSymbolMap(source);
            if (!string.IsNullOrWhiteSpace(mapped))
                return mapped;
            if (source.EndsWith("m", StringComparison.OrdinalIgnoreCase) && SameText(source.Substring(0, source.Length - 1), SymbolName))
                return SymbolName;
            return source;
        }


        private static string HardBrokerSymbolMap(string source)
        {
            var s = CanonicalSymbol(source);
            if (s == "US500" || s == "SPX500") return "US 500";
            if (s == "USTEC" || s == "US100" || s == "NAS100") return "US Tech 100";
            if (s == "US30" || s == "DJ30") return "Wall Street 30";
            if (s == "DE30" || s == "GER30" || s == "GER40" || s == "DAX40") return "GERMANY 40";
            if (s == "JP225" || s == "JPN225") return "JPN225";
            if (s == "UKOIL") return "XBRUSD";
            if (s == "USOIL") return "XTIUSD";
            return "";
        }
        private static string MapSymbolFromCsv(string source, string csv)
        {
            if (string.IsNullOrWhiteSpace(csv)) return "";
            foreach (var part in csv.Replace(';', ',').Split(','))
            {
                var kv = part.Split('=');
                if (kv.Length == 2 && SameText(kv[0].Trim(), source))
                    return kv[1].Trim();
            }
            return "";
        }

        private string EffectiveSourceTf()
        {
            var configured = NormalizeTf(SourceTimeframeFilter);
            return string.IsNullOrWhiteSpace(configured) && DefaultSourceTfToChartPeriod ? ChartTfString() : configured;
        }
        private string ChartTfString()
        {
            var tf = TimeFrame.ToString().ToUpperInvariant();
            if (tf.Contains("MINUTE5")) return "5";
            if (tf.Contains("MINUTE15")) return "15";
            if (tf.Contains("MINUTE30")) return "30";
            if (tf.Contains("MINUTE")) return "1";
            if (tf.Contains("HOUR4")) return "240";
            if (tf.Contains("HOUR")) return "60";
            if (tf.Contains("DAILY") || tf.Contains("DAY")) return "1440";
            return "";
        }

        private static string NormalizeTf(string tf)
        {
            if (tf == null) return "";
            var s = tf.Trim().ToUpperInvariant().Replace("PERIOD_", "");
            if (s.StartsWith("M")) return s.Substring(1);
            if (s == "H1") return "60";
            if (s == "H4") return "240";
            if (s == "D1") return "1440";
            return s;
        }


        private bool ShouldRebaseLevels(BridgeSignal sig)
        {
            var oilAlias = AutoRebaseOilAliases && IsMappedOilAlias(sig.SourceSymbol, SymbolName);
            if (!RebaseMappedLevelsToLiveEntry && !oilAlias) return false;
            if (sig.BridgeEntry <= 0 || sig.Sl <= 0 || sig.Tp <= 0) return false;
            var mapped = MapSymbol(sig.SourceSymbol);
            if (!SameText(mapped, SymbolName)) return false;
            if (RebaseOnlyWhenSourceDiffers && SameText(sig.SourceSymbol, SymbolName)) return false;
            return true;
        }

        private bool ValidateMappedPriceBasis(BridgeSignal sig, double liveEntry, out string detail)
        {
            detail = string.Empty;
            if (MappedBasisGuardPctRisk <= 0 || SameText(sig.SourceSymbol, SymbolName) || sig.BridgeEntry <= 0 || sig.Sl <= 0 || liveEntry <= 0)
                return true;
            var sourceRisk = Math.Abs(sig.BridgeEntry - sig.Sl);
            if (sourceRisk <= Math.Max(Symbol.TickSize, 0.00000001))
                return true;
            var basisOffset = Math.Abs(liveEntry - sig.BridgeEntry);
            var basisPctRisk = basisOffset * 100.0 / sourceRisk;
            detail = $"source_symbol={sig.SourceSymbol} chart_symbol={SymbolName} source_entry={sig.BridgeEntry} live_entry={liveEntry} source_sl={sig.Sl} basis_offset={basisOffset} source_risk={sourceRisk} basis_pct_risk={basisPctRisk:F2} max_pct={MappedBasisGuardPctRisk:F2}";
            return basisPctRisk <= MappedBasisGuardPctRisk;
        }

        private static bool IsMappedOilAlias(string source, string chart)
        {
            var a = CanonicalSymbol(source);
            var b = CanonicalSymbol(chart);
            var sourceBrent = a == "UKOIL" || a == "XBRUSD" || a == "BRENT";
            var chartBrent = b == "UKOIL" || b == "XBRUSD" || b == "BRENT";
            var sourceWti = a == "USOIL" || a == "XTIUSD" || a == "WTI";
            var chartWti = b == "USOIL" || b == "XTIUSD" || b == "WTI";
            return !SameText(source, chart) && ((sourceBrent && chartBrent) || (sourceWti && chartWti));
        }

        private void RebaseLevelsToLiveEntry(ref BridgeSignal sig, double liveEntry, out string detail)
        {
            detail = "";
            var oldSl = sig.Sl;
            var oldTp = sig.Tp;
            var oldHalf = sig.HalfTrigger;
            var src = sig.BridgeEntry;
            if (src <= 0 || liveEntry <= 0) return;
            if (sig.Direction > 0)
            {
                var risk = src - oldSl;
                var reward = oldTp - src;
                if (risk > 0) sig.Sl = liveEntry - risk;
                if (reward > 0) sig.Tp = liveEntry + reward;
                if (oldHalf > 0)
                {
                    var half = oldHalf - src;
                    if (half > 0) sig.HalfTrigger = liveEntry + half;
                }
            }
            else
            {
                var risk = oldSl - src;
                var reward = src - oldTp;
                if (risk > 0) sig.Sl = liveEntry + risk;
                if (reward > 0) sig.Tp = liveEntry - reward;
                if (oldHalf > 0)
                {
                    var half = src - oldHalf;
                    if (half > 0) sig.HalfTrigger = liveEntry - half;
                }
            }
            detail = $"source_entry={src} live_entry={liveEntry} old_sl={oldSl} old_tp={oldTp} old_half={oldHalf} new_sl={sig.Sl} new_tp={sig.Tp} new_half={sig.HalfTrigger} mapped={MapSymbol(sig.SourceSymbol)}";
        }

        private double ProjectedMarginPct(TradeType type, double volume)
        {
            try
            {
                var margin = Symbol.GetEstimatedMargin(type, volume);
                var equity = Account.Equity;
                if (equity <= 0) return double.MaxValue;
                return (Account.Margin + margin) * 100.0 / equity;
            }
            catch
            {
                return double.MaxValue;
            }
        }

        private double ShrinkVolumeToMarginLimit(TradeType type, double requestedVolume, double maxMarginPct, out string detail)
        {
            detail = "";
            if (maxMarginPct <= 0) return requestedVolume;
            var min = Symbol.VolumeInUnitsMin;
            var minPct = ProjectedMarginPct(type, min);
            if (minPct > maxMarginPct)
            {
                detail = $"min_volume_margin_exceeds_limit min_volume={min} projected_margin_pct={minPct:F2} max_margin_pct={maxMarginPct:F2}";
                return 0;
            }
            var normalized = Symbol.NormalizeVolumeInUnits(requestedVolume, RoundingMode.Down);
            if (ProjectedMarginPct(type, normalized) <= maxMarginPct)
            {
                detail = $"margin_no_shrink volume={normalized} projected_margin_pct={ProjectedMarginPct(type, normalized):F2} max_margin_pct={maxMarginPct:F2}";
                return normalized;
            }
            var step = Symbol.VolumeInUnitsStep;
            var best = normalized;
            while (best >= min && ProjectedMarginPct(type, best) > maxMarginPct)
                best = Symbol.NormalizeVolumeInUnits(best - step, RoundingMode.Down);
            if (best < min)
            {
                detail = $"margin_shrink_no_valid_volume requested_volume={requestedVolume} max_margin_pct={maxMarginPct:F2}";
                return 0;
            }
            detail = $"margin_shrink requested_volume={requestedVolume} shrunk_volume={best} projected_margin_pct={ProjectedMarginPct(type, best):F2} max_margin_pct={maxMarginPct:F2}";
            return best;
        }

        private double ShrinkVolumeToFreeMargin(TradeType type, double requestedVolume, out string detail)
        {
            detail = "";
            var min = Symbol.VolumeInUnitsMin;
            var step = Symbol.VolumeInUnitsStep;
            double free = Account.FreeMargin;
            if (free <= 0)
            {
                detail = $"free_margin_unavailable free_margin={free:F2}";
                return 0;
            }
            var best = Symbol.NormalizeVolumeInUnits(requestedVolume, RoundingMode.Down);
            while (best >= min)
            {
                double margin;
                try { margin = Symbol.GetEstimatedMargin(type, best); }
                catch { detail = $"free_margin_margin_calc_failed volume={best}"; return 0; }
                if (margin <= free * 0.98)
                {
                    detail = $"free_margin_retry requested_volume={requestedVolume} shrunk_volume={best} required_margin={margin:F2} free_margin={free:F2}";
                    return best;
                }
                best = Symbol.NormalizeVolumeInUnits(best - step, RoundingMode.Down);
            }
            detail = $"free_margin_retry_no_valid_volume requested_volume={requestedVolume} free_margin={free:F2}";
            return 0;
        }

        private string HalfStatePath(long positionId)
        {
            return IoPath.Combine(_stateDir, $"half_{Account.Number}_{Sanitize(SymbolName)}_{positionId}.state");
        }

        private void SaveHalfState(long positionId, HalfState st)
        {
            if (positionId <= 0 || string.IsNullOrWhiteSpace(_stateDir)) return;
            try
            {
                var phase = st.Done ? "done" : st.PartialClosed ? "partial" : "armed";
                WriteStateAtomically(HalfStatePath(positionId), string.Join("\t", phase, st.InitialVolume.ToString("G17", CultureInfo.InvariantCulture), DateTime.UtcNow.ToString("O")));
            }
            catch (Exception ex)
            {
                AuditRaw("halfbe_state_write_failed", $"pos={positionId} error={ex.Message}");
            }
        }

        private string LoadHalfStatePhase(long positionId)
        {
            try
            {
                var path = HalfStatePath(positionId);
                if (!IoFile.Exists(path)) return "";
                var fields = IoFile.ReadAllText(path).Split('\t');
                return fields.Length > 0 ? fields[0].Trim().ToLowerInvariant() : "";
            }
            catch (Exception ex)
            {
                AuditRaw("halfbe_state_read_failed", $"pos={positionId} error={ex.Message}");
                return "";
            }
        }

        private void DeleteHalfState(long positionId)
        {
            try
            {
                var path = HalfStatePath(positionId);
                if (IoFile.Exists(path)) IoFile.Delete(path);
            }
            catch { }
        }

        private void WriteStateAtomically(string path, string content)
        {
            var tmp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            IoFile.WriteAllText(tmp, content, Encoding.UTF8);
            try
            {
                if (IoFile.Exists(path))
                    IoFile.Replace(tmp, path, null);
                else
                    IoFile.Move(tmp, path);
            }
            catch
            {
                IoFile.Copy(tmp, path, true);
                if (IoFile.Exists(tmp)) IoFile.Delete(tmp);
            }
        }

        private bool PositionProtectedAtOrBeyondBe(Position p)
        {
            if (p == null || !p.StopLoss.HasValue) return false;
            var tolerance = Math.Max(Symbol.TickSize, Symbol.PipSize * 0.1);
            return p.TradeType == TradeType.Buy
                ? p.StopLoss.Value >= p.EntryPrice - tolerance
                : p.StopLoss.Value <= p.EntryPrice + tolerance;
        }

        private void QueueEmergencyClose(Position position, string reason)
        {
            if (position == null) return;
            _emergencyCloseRetryAt[position.Id] = DateTime.MinValue;
            AuditRaw("emergency_close_queued", $"pos={position.Id} label={position.Label} reason={reason}");
        }

        private void ManageEmergencyCloses()
        {
            foreach (var kv in _emergencyCloseRetryAt.ToArray())
            {
                var pos = Positions.FirstOrDefault(p => p.Id == kv.Key);
                if (pos == null)
                {
                    _emergencyCloseRetryAt.Remove(kv.Key);
                    DeleteHalfState(kv.Key);
                    continue;
                }
                if (DateTime.UtcNow < kv.Value) continue;
                var result = ClosePosition(pos);
                if (result.IsSuccessful)
                {
                    _emergencyCloseRetryAt.Remove(kv.Key);
                    DeleteHalfState(kv.Key);
                    AuditRaw("emergency_close_done", $"pos={pos.Id} label={pos.Label}");
                }
                else
                {
                    _emergencyCloseRetryAt[kv.Key] = DateTime.UtcNow.AddSeconds(10);
                    AuditRaw("emergency_close_retry_failed", $"pos={pos.Id} label={pos.Label} error={result.Error} next_sec=10");
                }
            }
        }
        private void RepairOpenPositionStates(string reason)
        {
            foreach (var p in Positions.Where(p => PositionBelongsToThisInstance(p) && !string.IsNullOrWhiteSpace(p.Label) && p.Label.StartsWith(LabelPrefix, StringComparison.Ordinal)))
            {
                var expectedSl = ParseCommentDouble(p.Comment, "sl");
                var expectedTp = ParseCommentDouble(p.Comment, "tp");
                var atBe = PositionProtectedAtOrBeyondBe(p);
                var tolerance = Math.Max(Symbol.TickSize * 0.5, 0.00000001);
                var slMismatch = expectedSl > 0 && (!p.StopLoss.HasValue || Math.Abs(p.StopLoss.Value - expectedSl) > tolerance) && !atBe;
                var tpMismatch = expectedTp > 0 && (!p.TakeProfit.HasValue || Math.Abs(p.TakeProfit.Value - expectedTp) > tolerance);
                if (FailIfExactProtectionFails && (slMismatch || tpMismatch) && !_emergencyCloseRetryAt.ContainsKey(p.Id))
                    QueueEmergencyClose(p, $"repair_exact_mismatch reason={reason} expected_sl={expectedSl} actual_sl={FormatNullable(p.StopLoss)} expected_tp={expectedTp} actual_tp={FormatNullable(p.TakeProfit)} at_be={(atBe ? 1 : 0)}");

                if (!ManageHalfCloseBe || _halfStates.ContainsKey(p.Id)) continue;
                var half = ParseCommentDouble(p.Comment, "half");
                if (half <= 0) continue;
                var phase = LoadHalfStatePhase(p.Id);
                var done = phase == "done" || atBe;
                var partial = done || phase == "partial";
                var state = new HalfState
                {
                    EventId = ParseCommentString(p.Comment, "event"),
                    SourceTf = PositionSourceTf(p),
                    Direction = p.TradeType == TradeType.Buy ? 1 : -1,
                    Entry = p.EntryPrice,
                    HalfTrigger = half,
                    InitialVolume = p.VolumeInUnits,
                    StopLoss = expectedSl,
                    TakeProfit = expectedTp,
                    PartialClosed = partial,
                    Done = done
                };
                _halfStates[p.Id] = state;
                if (done && phase != "done") SaveHalfState(p.Id, state);
                AuditRaw("position_state_repaired", $"reason={reason} pos={p.Id} label={p.Label} source_tf={PositionSourceTf(p)} entry={p.EntryPrice} half={half} sl={expectedSl} tp={expectedTp} phase={phase} partial={(partial ? 1 : 0)} done={(done ? 1 : 0)}");
            }
        }
        private static double ParseCommentDouble(string comment, string key)
        {
            var raw = ParseCommentString(comment, key);
            return ParseDouble(raw);
        }

        private static string ParseCommentString(string comment, string key)
        {
            if (string.IsNullOrWhiteSpace(comment)) return "";
            foreach (var part in comment.Split(';'))
            {
                var kv = part.Split(new[] { '=' }, 2);
                if (kv.Length == 2 && SameText(kv[0], key)) return kv[1].Trim();
            }
            return "";
        }
        private string OpenPositionSummary()
        {
            var scoped = Positions.Where(p => PositionBelongsToThisInstance(p) && !string.IsNullOrWhiteSpace(p.Label) && p.Label.StartsWith(LabelPrefix, StringComparison.Ordinal)).ToArray();
            var pnl = scoped.Sum(p => p.NetProfit);
            var vol = scoped.Sum(p => p.VolumeInUnits);
            return $"{scoped.Length} vol={vol} pnl={pnl:F2}";
        }

        private static string Sanitize(string s)
        {
            if (string.IsNullOrEmpty(s)) return "_";
            var arr = s.Select(ch => char.IsLetterOrDigit(ch) ? ch : '_').ToArray();
            return new string(arr);
        }

        private void DrawDashboard()
        {
            if (!ShowDashboard) return;
            var text = $"Liq Narrative Sol Advanced cTrader Listener {Build}\n"
                     + $"Executor={(ExecutorEnabled ? "ON" : "OFF")} Symbol={SymbolName} File={IoPath.GetFileName(_resolvedBridgePath)}\n"
                     + $"RiskPct={(UseBridgeRiskPct ? "BRIDGE" : "LOCAL")} Capital={(UseBalanceForRisk ? "cTrader BAL" : "cTrader EQ")} Equity={Account.Equity:F2} Balance={Account.Balance:F2}\n"
                     + $"Positions={OpenPositionSummary()}\n"
                     + $"Seen={ShortEvent(_lastSeenEventId)} Rej={ShortEvent(_lastRejectedEventId)}\n"
                     + $"Last={_lastAction} {_lastDetail}\nSignal={_lastSignal}";
            Chart.DrawStaticText("LN_ADV_DASH", text, VerticalAlignment.Top, HorizontalAlignment.Left, Color.LightSkyBlue);
        }

        private void Audit(string eventName, BridgeSignal sig, string detail)
        {
            _lastAction = eventName;
            _lastDetail = detail;
            _lastSignal = $"{sig.SourceSymbol} {sig.SourceTf} {(sig.Direction > 0 ? "BUY" : "SELL")} {ShortEvent(sig.EventId)}";
            if (!AuditEnabled) return;
            WriteAudit(eventName, sig.SourceSymbol, sig.SourceTf, sig.EventId, sig.Source, sig.Direction > 0 ? "BUY" : "SELL", sig.BridgeEntry, sig.Sl, sig.Tp, sig.HalfTrigger, detail);
        }

        private void AuditRaw(string eventName, string detail)
        {
            SetAction(eventName, detail);
            if (!AuditEnabled) return;
            WriteAudit(eventName, "", "", "", "", "-", 0, 0, 0, 0, detail);
        }

        private void WriteAudit(string eventName, string sourceSymbol, string sourceTf, string eventId, string source, string dir, double entry, double sl, double tp, double half, string detail)
        {
            var scope = Account.Number.ToString(CultureInfo.InvariantCulture) + "_" + Sanitize(SymbolName)
                      + "_TF" + Sanitize(string.IsNullOrWhiteSpace(SourceTimeframeFilter) ? "ANY" : SourceTimeframeFilter);
            var file = IoPath.Combine(_auditDir, AuditFilePrefix + scope + "_" + DateTime.UtcNow.ToString("yyyyMMdd") + ".csv");
            Exception lastError = null;

            for (var attempt = 0; attempt < 4; attempt++)
            {
                try
                {
                    lock (AuditWriteSync)
                    {
                        using (var fs = new IoFileStream(file, IoFileMode.OpenOrCreate, IoFileAccess.Write, IoFileShare.ReadWrite))
                        {
                            var header = fs.Length == 0;
                            fs.Seek(0, global::System.IO.SeekOrigin.End);
                            using (var sw = new IoStreamWriter(fs, new UTF8Encoding(false)))
                            {
                                if (header)
                                    sw.WriteLine("time_gmt,build,event,account,chart_symbol,source_symbol,source_tf,event_id,source,dir,entry,sl,tp,half,detail");
                                sw.WriteLine(string.Join(",", Escape(DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss")), Escape(Build), Escape(eventName), Escape(Account.Number.ToString()), Escape(SymbolName), Escape(sourceSymbol), Escape(sourceTf), Escape(eventId), Escape(source), Escape(dir), entry.ToString(CultureInfo.InvariantCulture), sl.ToString(CultureInfo.InvariantCulture), tp.ToString(CultureInfo.InvariantCulture), half.ToString(CultureInfo.InvariantCulture), Escape(detail)));
                            }
                        }
                    }
                    return;
                }
                catch (IoException ex)
                {
                    lastError = ex;
                    if (attempt < 3)
                        global::System.Threading.Thread.Sleep(20 * (attempt + 1));
                }
                catch (Exception ex)
                {
                    lastError = ex;
                    break;
                }
            }

            Print("Audit write failed after retries: {0}", lastError == null ? "unknown" : lastError.Message);
        }

        private void SetAction(string action, string detail)
        {
            _lastAction = action;
            _lastDetail = detail;
        }

        private static List<string> ParseCsvFlat(string text)
        {
            var result = new List<string>();
            var sb = new StringBuilder();
            var inQuotes = false;
            for (var i = 0; i < text.Length; i++)
            {
                var c = text[i];
                if (c == '"')
                {
                    if (inQuotes && i + 1 < text.Length && text[i + 1] == '"') { sb.Append('"'); i++; }
                    else inQuotes = !inQuotes;
                    continue;
                }
                if (!inQuotes && (c == ',' || c == ';' || c == '\n' || c == '\r'))
                {
                    if (c == '\r' && i + 1 < text.Length && text[i + 1] == '\n') i++;
                    result.Add(sb.ToString().Trim());
                    sb.Clear();
                    continue;
                }
                sb.Append(c);
            }
            if (sb.Length > 0) result.Add(sb.ToString().Trim());
            return result;
        }

        private static DateTime ParseDate(string s)
        {
            if (DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var dt))
                return dt;
            return DateTime.MinValue;
        }

        private static double ParseDouble(string s)
        {
            double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var v);
            return v;
        }

        private static string CanonicalSymbol(string value)
        {
            var s = new string((value ?? "").Trim().Where(char.IsLetterOrDigit).ToArray()).ToUpperInvariant();
            if (s.EndsWith("M", StringComparison.OrdinalIgnoreCase) && s.Length > 1)
                s = s.Substring(0, s.Length - 1);

            if (s == "USTEC" || s == "US100" || s == "NAS100" || s == "USTECH100" || s == "USTECH" || s == "TECH100")
                return "USTEC";
            if (s == "US500" || s == "SPX500" || s == "SP500")
                return "US500";
            if (s == "US30" || s == "DJ30" || s == "WALLSTREET30" || s == "DOW30")
                return "US30";
            if (s == "DE30" || s == "GER30" || s == "GER40" || s == "DAX40" || s == "GERMANY40")
                return "DE30";
            if (s == "JP225" || s == "JPN225" || s == "NIKKEI225")
                return "JP225";

            return s;
        }

        private static bool SameEconomicSymbol(string a, string b) => CanonicalSymbol(a) == CanonicalSymbol(b);

        private static bool SameText(string a, string b) => string.Equals((a ?? "").Trim(), (b ?? "").Trim(), StringComparison.OrdinalIgnoreCase);
        private static bool ContainsText(string haystack, string needle) => (haystack ?? "").IndexOf(needle ?? "", StringComparison.OrdinalIgnoreCase) >= 0;
        private static string ShortEvent(string s) => string.IsNullOrEmpty(s) || s.Length <= 42 ? s : s.Substring(0, 24) + "..." + s.Substring(s.Length - 14);
        private static uint Hash32(string s)
        {
            unchecked
            {
                uint h = 2166136261;
                foreach (var c in s ?? "") { h ^= c; h *= 16777619; }
                return h;
            }
        }

        private static ulong Hash64(string s)
        {
            unchecked
            {
                ulong h = 14695981039346656037UL;
                foreach (var c in s ?? string.Empty) { h ^= c; h *= 1099511628211UL; }
                return h;
            }
        }
        private static string Escape(string s)
        {
            s = s ?? "";
            if (s.Contains(",") || s.Contains("\"") || s.Contains("\n"))
                return "\"" + s.Replace("\"", "\"\"") + "\"";
            return s;
        }

        private struct BridgeSignal
        {
            public bool Valid;
            public string Version;
            public DateTime WrittenGmt;
            public string SourceLogin;
            public string SourceSymbol;
            public string SourceTf;
            public string EventId;
            public string Source;
            public int Direction;
            public DateTime SignalTime;
            public double BridgeEntry;
            public double Sl;
            public double Tp;
            public double HalfTrigger;
            public string HalfLabel;
            public string SourceBuild;
            public double SourceBid;
            public double SourceAsk;
            public double RiskPct;
        }

        private struct HalfState
        {
            public string EventId;
            public string SourceTf;
            public int Direction;
            public double Entry;
            public double HalfTrigger;
            public double InitialVolume;
            public double StopLoss;
            public double TakeProfit;
            public bool PartialClosed;
            public bool Done;
        }
    }
}