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
    public class ProRenkoFileBridgeCTraderListener : Robot
    {
        private const string Build = "2026-07-14.ml-basket-lifecycle";

        [Parameter("Executor Enabled", DefaultValue = true)]
        public bool ExecutorEnabled { get; set; }

        [Parameter("Bridge Latest Path", DefaultValue = "C:\\Users\\Cem\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common\\Files\\PRORENKOFileBridge_Latest.csv")]
        public string BridgeLatestPath { get; set; }

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

        [Parameter("Built-In Index Map", DefaultValue = "DE30m=GERMANY 40,DE30=GERMANY 40,GER30m=GERMANY 40,GER30=GERMANY 40,GER40m=GERMANY 40,GER40=GERMANY 40,DAX40m=GERMANY 40,DAX40=GERMANY 40")]
        public string BuiltInIndexSymbolMapCsv { get; set; }

        [Parameter("Require Chart Symbol", DefaultValue = true)]
        public bool RequireMappedSymbolEqualsChart { get; set; }

        [Parameter("Source TF Filter", DefaultValue = "")]
        public string SourceTimeframeFilter { get; set; }

        [Parameter("Default TF To Chart", DefaultValue = true)]
        public bool DefaultSourceTfToChartPeriod { get; set; }

        [Parameter("Source Filter", DefaultValue = "")]
        public string SourceFilter { get; set; }

        [Parameter("Rebase Levels To Live", DefaultValue = false)]
        public bool RebaseMappedLevelsToLiveEntry { get; set; }

        [Parameter("Rebase Only Source Differs", DefaultValue = true)]
        public bool RebaseOnlyWhenSourceDiffers { get; set; }

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

        [Parameter("Label Prefix", DefaultValue = "PRB_CT")]
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

        [Parameter("No-Money Retry Shrink", DefaultValue = true)]
        public bool NoMoneyRetryShrink { get; set; }

        [Parameter("Max Spread Pips", DefaultValue = 0, MinValue = 0)]
        public double MaxSpreadPips { get; set; }

        [Parameter("Manage HCBE", DefaultValue = true)]
        public bool ManageHalfCloseBe { get; set; }

        [Parameter("Half Close Fraction", DefaultValue = 0.5, MinValue = 0.01, MaxValue = 0.99)]
        public double HalfCloseFraction { get; set; }

        [Parameter("Audit Enabled", DefaultValue = true)]
        public bool AuditEnabled { get; set; }

        [Parameter("Audit File Prefix", DefaultValue = "ProRenkoFileBridge_cTrader_Audit_")]
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
        private readonly Dictionary<long, BasketPositionState> _basketStates = new Dictionary<long, BasketPositionState>();
        private readonly Dictionary<string, double> _basketClosedPnlByDay = new Dictionary<string, double>();
        private readonly HashSet<string> _basketDayDone = new HashSet<string>();
        private string _resolvedBridgePath;
        private DateTime _lastPollHeartbeat = DateTime.MinValue;
        private DateTime _lastReadFailAudit = DateTime.MinValue;
        private string _auditDir;
        private string _lockDir;

        protected override void OnStart()
        {
            _resolvedBridgePath = ResolveBridgePath();
            _auditDir = IoPath.GetDirectoryName(_resolvedBridgePath) ?? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            _lockDir = IoPath.Combine(IoPath.GetTempPath(), "ProRenkoFileBridge_cTrader_Locks");
            IoDirectory.CreateDirectory(_lockDir);

            Timer.Start(TimeSpan.FromMilliseconds(Math.Max(100, PollMilliseconds)));
            AuditRaw("init", $"build={Build} bridge={_resolvedBridgePath} symbol={SymbolName} risk_capital_source={(UseBalanceForRisk ? "ctrader_balance" : "ctrader_equity")} use_bridge_risk_pct={UseBridgeRiskPct} margin_guard={UseMarginShrinkGuard} max_margin_pct={MaxMarginUsagePct:F1}");
            RepairOpenPositionStates("init");

            if (IgnoreExistingSignalOnInit)
            {
                if (TryReadSignal(out var sig, out var detail) && SignalIdentityMatches(sig, out _))
                {
                    _lastSeenEventId = sig.EventId;
                    Audit("init_baseline_existing_signal", sig, "seeded_last_seen=1 no_trade_on_attach " + detail);
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
            ManageBasketRuntimeGuards();
            PollBridge("timer");
            RepairOpenPositionStates("timer");
            ManageHalfClose();
            DrawDashboard();
        }

        protected override void OnTick()
        {
            ManageBasketRuntimeGuards();
            ManageHalfClose();
        }

        private void PollBridge(string caller)
        {
            if (!TryReadSignal(out var sig, out var detail))
            {
                SetAction("read_failed", detail);
                var initMarker = detail.IndexOf("bridge_init_marker", StringComparison.OrdinalIgnoreCase) >= 0
                              || detail.IndexOf("source=bridge_initiated", StringComparison.OrdinalIgnoreCase) >= 0
                              || detail.IndexOf("dir=INIT", StringComparison.OrdinalIgnoreCase) >= 0;
                var throttleSeconds = initMarker ? 60 : 10;
                if ((DateTime.UtcNow - _lastReadFailAudit).TotalSeconds >= throttleSeconds)
                {
                    _lastReadFailAudit = DateTime.UtcNow;
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
        private bool ExecuteSignal(BridgeSignal sig)
        {
            if (IsBasketSignal(sig))
                return ExecuteBasketSignal(sig);

            var tradeType = sig.Direction > 0 ? TradeType.Buy : TradeType.Sell;
            var entry = sig.Direction > 0 ? Symbol.Ask : Symbol.Bid;
            var rebaseDetail = "";
            if (ShouldRebaseLevels(sig))
            {
                RebaseLevelsToLiveEntry(ref sig, entry, out rebaseDetail);
                if (!string.IsNullOrEmpty(rebaseDetail))
                    Audit("levels_rebased", sig, rebaseDetail);
            }

            if (!ValidateStops(sig, entry, out var stopLossPips, out var takeProfitPips, out var stopDetail))
            {
                if (PermanentRejectGuard)
                    _lastRejectedEventId = sig.EventId;
                Audit("skip_geometry", sig, stopDetail + " " + StopContext(entry, sig.Sl, sig.Tp));
                return false;
            }

            if (!ClaimEvent(sig.EventId))
            {
                var duplicateReverseDetail = "";
                if (CloseReverse)
                    CloseReversePositions(sig, out duplicateReverseDetail);
                Audit("skip_duplicate_global", sig, "lock_exists " + duplicateReverseDetail);
                return true;
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
                        if (PermanentRejectGuard && IsPermanentOrderFailure(retry.Error))
                            _lastRejectedEventId = sig.EventId;
                        Audit("order_failed_no_money_retry", sig, $"original_error={originalError} retry_error={retry.Error} original_volume={volume} retry_volume={retryVolume} sl_pips={stopLossPips:F2} tp_pips={takeProfitPips:F2} {retryDetail} {lotDetail}");
                        return false;
                    }
                }
                else
                {
                    ReleaseEvent(sig.EventId);
                    var permanent = IsPermanentOrderFailure(originalError);
                    if (PermanentRejectGuard && permanent)
                        _lastRejectedEventId = sig.EventId;
                    Audit("order_failed", sig, $"error={originalError} permanent_reject={(permanent ? 1 : 0)} volume={volume} sl_pips={stopLossPips:F2} tp_pips={takeProfitPips:F2} {StopContext(entry, sig.Sl, sig.Tp)} {retryDetail} {lotDetail}");
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
                        return true;
                    }
                }
                else if (!string.IsNullOrWhiteSpace(exactDetail))
                {
                    Audit("exact_protection_applied", sig, exactDetail);
                }
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
                    Done = false
                };
            }

            Audit("order_sent", sig, orderAuditPrefix + $"position={result.Position?.Id} volume={result.Position?.VolumeInUnits ?? finalVolume} live_entry={entry} fill_entry={result.Position?.EntryPrice ?? entry} sl_pips={stopLossPips:F2} tp_pips={takeProfitPips:F2} rebase={rebaseDetail} {lotDetail}");
            return true;
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

        private bool ExecuteBasketSignal(BridgeSignal sig)
        {
            var tradeType = sig.Direction > 0 ? TradeType.Buy : TradeType.Sell;
            var entry = sig.Direction > 0 ? Symbol.Ask : Symbol.Bid;
            var targetPips = sig.BasketTargetPips > 0 ? sig.BasketTargetPips : 500.0;
            var targetPct = sig.BasketTargetPct > 0 ? sig.BasketTargetPct : (UseBridgeRiskPct && sig.RiskPct > 0 ? sig.RiskPct : LocalRiskPct);
            var maxLossPips = sig.BasketMaxLossPips > 0 ? sig.BasketMaxLossPips : targetPips * 2.0;
            var catPips = sig.BasketCatastrophicSlPips > 0 ? sig.BasketCatastrophicSlPips : Math.Max(targetPips * 5.0, maxLossPips * 2.0);
            var sessionEndMin = ParseHhMm(sig.BasketSessionEndTime);
            var dayKey = BasketDayKey(sig);
            var stateKey = BasketStateKey(sig);

            if (BasketDayDone(stateKey))
            {
                Audit("basket_blocked_day_done", sig, $"key={stateKey} day={dayKey}");
                return true;
            }

            if (sig.BasketCloseSessionEnd && BasketSessionEndReached(sessionEndMin))
            {
                BasketSetDayDone(stateKey);
                CloseBasketPositions(sig, "basket_session_close", out var sessionDetail);
                Audit("basket_blocked_session_end", sig, $"session_end={sig.BasketSessionEndTime} key={stateKey} {sessionDetail}");
                return true;
            }

            if (!ValidateBasketStop(entry, sig.Direction, catPips, out var slPips, out var stopDetail))
            {
                if (PermanentRejectGuard)
                    _lastRejectedEventId = sig.EventId;
                Audit("basket_skip_geometry", sig, stopDetail);
                return false;
            }

            if (!ClaimEvent(sig.EventId))
            {
                if (sig.BasketCloseOnReverse)
                    CloseReverseBasketPositions(sig, out _);
                Audit("basket_skip_duplicate_global", sig, "lock_exists");
                return true;
            }

            if (sig.BasketCloseOnReverse && !CloseReverseBasketPositions(sig, out var reverseDetail))
            {
                ReleaseEvent(sig.EventId);
                if (FailIfReverseCloseFails)
                {
                    if (PermanentRejectGuard)
                        _lastRejectedEventId = sig.EventId;
                    Audit("basket_skip_reverse_close_failed", sig, reverseDetail);
                    return false;
                }
                Audit("basket_reverse_close_failed_continue", sig, reverseDetail);
            }

            var volume = ResolveBasketVolume(sig, targetPips, targetPct, maxLossPips, catPips, out var lotDetail, out var targetMoney, out var maxLossMoney, out var estimatedCatRisk);
            if (volume <= 0)
            {
                ReleaseEvent(sig.EventId);
                if (PermanentRejectGuard)
                    _lastRejectedEventId = sig.EventId;
                Audit("basket_skip_lot", sig, lotDetail);
                return false;
            }

            var label = BuildBasketLabel(sig);
            var comment = BuildBasketComment(sig, targetPips, targetPct, maxLossPips, catPips, targetMoney, maxLossMoney, sessionEndMin, dayKey);
            var result = ExecuteMarketOrder(tradeType, SymbolName, volume, label, slPips, (double?)null, comment);
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
                    var retry = ExecuteMarketOrder(tradeType, SymbolName, retryVolume, label, slPips, (double?)null, comment);
                    if (retry.IsSuccessful)
                    {
                        result = retry;
                        finalVolume = retryVolume;
                        orderAuditPrefix = $"original_error={originalError} original_volume={volume} retry_volume={retryVolume} {retryDetail} ";
                        Audit("basket_order_sent_no_money_retry", sig, orderAuditPrefix + $"cat_sl_pips={slPips:F2} {lotDetail}");
                    }
                    else
                    {
                        ReleaseEvent(sig.EventId);
                        if (PermanentRejectGuard && IsPermanentOrderFailure(retry.Error))
                            _lastRejectedEventId = sig.EventId;
                        Audit("basket_order_failed_no_money_retry", sig, $"original_error={originalError} retry_error={retry.Error} original_volume={volume} retry_volume={retryVolume} cat_sl_pips={slPips:F2} {retryDetail} {lotDetail}");
                        return false;
                    }
                }
                else
                {
                    ReleaseEvent(sig.EventId);
                    var permanent = IsPermanentOrderFailure(originalError);
                    if (PermanentRejectGuard && permanent)
                        _lastRejectedEventId = sig.EventId;
                    Audit("basket_order_failed", sig, $"error={originalError} permanent_reject={(permanent ? 1 : 0)} volume={volume} cat_sl_pips={slPips:F2} {retryDetail} {lotDetail}");
                    return false;
                }
            }

            if (result.Position != null)
            {
                _basketStates[result.Position.Id] = new BasketPositionState
                {
                    EventId = sig.EventId,
                    SourceTf = NormalizeTf(sig.SourceTf),
                    DayKey = dayKey,
                    TargetPips = targetPips,
                    TargetPct = targetPct,
                    MaxLossPips = maxLossPips,
                    CatastrophicSlPips = catPips,
                    TargetMoney = targetMoney,
                    MaxLossMoney = maxLossMoney,
                    CloseSessionEnd = sig.BasketCloseSessionEnd,
                    SessionEndMinutes = sessionEndMin,
                    LastNetProfit = result.Position.NetProfit,
                    OpenTime = result.Position.EntryTime,
                    EntryPrice = result.Position.EntryPrice,
                    Direction = result.Position.TradeType == TradeType.Buy ? 1 : -1,
                    MfePips = 0.0,
                    MaePips = 0.0,
                    MfeMoney = result.Position.NetProfit,
                    MaeMoney = result.Position.NetProfit,
                    MfeTime = result.Position.EntryTime,
                    MaeTime = result.Position.EntryTime,
                    MfePrice = result.Position.EntryPrice,
                    MaePrice = result.Position.EntryPrice,
                    FirstTargetHitTime = DateTime.MinValue,
                    FirstLossHitTime = DateTime.MinValue,
                    ReverseSignalCount = 0
                };
                var seeded = _basketStates[result.Position.Id];
                UpdateBasketLifecycleState(result.Position, ref seeded);
                _basketStates[result.Position.Id] = seeded;
            }

            Audit("basket_order_sent", sig, orderAuditPrefix + $"position={result.Position?.Id} volume={result.Position?.VolumeInUnits ?? finalVolume} live_entry={entry} fill_entry={result.Position?.EntryPrice ?? entry} cat_sl_pips={slPips:F2} tp=0 hcbe=0 day={dayKey} target_money={targetMoney:F2} max_loss_money={maxLossMoney:F2} actual_risk_to_cat_sl={estimatedCatRisk:F2} {lotDetail}");
            return true;
        }

        private bool ValidateBasketStop(double entry, int direction, double catPips, out double stopLossPips, out string detail)
        {
            stopLossPips = catPips;
            if (entry <= 0 || direction == 0 || catPips <= 0)
            {
                detail = $"invalid_basket_cat_sl entry={entry} dir={direction} cat_pips={catPips:F2}";
                return false;
            }
            detail = "ok";
            return true;
        }

        private double ResolveBasketVolume(BridgeSignal sig, double targetPips, double targetPct, double maxLossPips, double catPips, out string detail, out double targetMoney, out double maxLossMoney, out double estimatedCatRisk)
        {
            targetMoney = 0;
            maxLossMoney = 0;
            estimatedCatRisk = 0;

            if (!UseRiskLot)
            {
                var manual = Symbol.NormalizeVolumeInUnits(ManualVolumeInUnits, RoundingMode.Down);
                targetMoney = Symbol.AmountRisked(manual, targetPips);
                maxLossMoney = targetMoney * (maxLossPips / Math.Max(targetPips, Symbol.PipSize));
                estimatedCatRisk = Symbol.AmountRisked(manual, catPips);
                detail = $"basket_manual_volume={manual} basket_target_money_preview={targetMoney:F2} basket_max_loss_money_preview={maxLossMoney:F2}";
                return manual;
            }

            var riskCapital = UseBalanceForRisk ? Account.Balance : Account.Equity;
            targetMoney = riskCapital * Math.Max(0, targetPct) / 100.0;
            maxLossMoney = targetMoney * (maxLossPips / Math.Max(targetPips, 0.0000001));

            if (targetMoney <= 0 || targetPips <= 0)
            {
                detail = $"basket_target_unavailable target_money={targetMoney:F2} target_pips={targetPips:F2} target_pct={targetPct:F3}";
                return 0;
            }

            double volume;
            try
            {
                volume = Symbol.VolumeForFixedRisk(targetMoney, targetPips, RoundingMode.Down);
            }
            catch (Exception ex)
            {
                detail = $"basket_volume_for_target_failed error={ex.Message} target_money={targetMoney:F2} target_pips={targetPips:F2}";
                return 0;
            }

            if (MaxVolumeInUnits > 0)
                volume = Math.Min(volume, MaxVolumeInUnits);

            var minTargetValue = Symbol.AmountRisked(Symbol.VolumeInUnitsMin, targetPips);
            if (BlockIfMinVolumeExceedsRisk && volume < Symbol.VolumeInUnitsMin && minTargetValue > targetMoney * 1.001)
            {
                detail = $"basket_min_volume_exceeds_target target_money={targetMoney:F2} target_pips={targetPips:F2} raw_volume={volume} min_volume={Symbol.VolumeInUnitsMin} min_volume_target_value={minTargetValue:F2}";
                return 0;
            }

            volume = Symbol.NormalizeVolumeInUnits(volume, RoundingMode.Down);
            if (volume < Symbol.VolumeInUnitsMin)
            {
                detail = $"basket_volume_below_min target_money={targetMoney:F2} target_pips={targetPips:F2} raw_volume={volume} min={Symbol.VolumeInUnitsMin}";
                return FailClosedOnRiskError ? 0 : Symbol.NormalizeVolumeInUnits(ManualVolumeInUnits, RoundingMode.Down);
            }

            var actualTargetValue = Symbol.AmountRisked(volume, targetPips);
            if (BlockIfMinVolumeExceedsRisk && actualTargetValue > targetMoney * 1.001)
            {
                detail = $"basket_normalized_volume_exceeds_target target_money={targetMoney:F2} target_pips={targetPips:F2} volume={volume} actual_target_value={actualTargetValue:F2}";
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
                actualTargetValue = Symbol.AmountRisked(volume, targetPips);
            }

            estimatedCatRisk = Symbol.AmountRisked(volume, catPips);
            detail = "basket_target_lot risk_calc=ctrader_volume_for_fixed_risk"
                + $" basket_target_pips={targetPips:F2}"
                + $" basket_target_pct={targetPct:F3}"
                + $" basket_target_money={targetMoney:F2}"
                + $" basket_actual_target_value={actualTargetValue:F2}"
                + $" basket_max_loss_pips={maxLossPips:F2}"
                + $" basket_max_loss_money={maxLossMoney:F2}"
                + $" basket_catastrophic_sl_pips={catPips:F2}"
                + $" actual_risk_to_cat_sl={estimatedCatRisk:F2}"
                + $" target_based_volume={volume}"
                + $" risk_capital_source={(UseBalanceForRisk ? "ctrader_balance" : "ctrader_equity")}"
                + $" risk_capital={riskCapital:F2}"
                + (string.IsNullOrEmpty(marginDetail) ? "" : " " + marginDetail);
            return volume;
        }

        private string BuildBasketComment(BridgeSignal sig, double targetPips, double targetPct, double maxLossPips, double catPips, double targetMoney, double maxLossMoney, int sessionEndMin, string dayKey)
        {
            return $"mode=basket;event={ShortEvent(sig.EventId)};src={sig.Source};tf={NormalizeTf(sig.SourceTf)};day={dayKey};btp={targetPips.ToString(CultureInfo.InvariantCulture)};bpct={targetPct.ToString(CultureInfo.InvariantCulture)};blp={maxLossPips.ToString(CultureInfo.InvariantCulture)};bcat={catPips.ToString(CultureInfo.InvariantCulture)};btmoney={targetMoney.ToString(CultureInfo.InvariantCulture)};blmoney={maxLossMoney.ToString(CultureInfo.InvariantCulture)};bsess={(sig.BasketCloseSessionEnd ? 1 : 0)};bsessmin={sessionEndMin}";
        }

        private IEnumerable<Position> BasketScopedPositions(BridgeSignal sig)
        {
            var sourceTf = NormalizeTf(sig.SourceTf);
            foreach (var p in Positions)
            {
                if (!SameText(p.SymbolName, SymbolName))
                    continue;
                if (!IsBasketPosition(p))
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

        private bool CloseReverseBasketPositions(BridgeSignal sig, out string detail)
        {
            detail = "";
            var targetType = sig.Direction > 0 ? TradeType.Buy : TradeType.Sell;
            var reverse = targetType == TradeType.Buy ? TradeType.Sell : TradeType.Buy;
            var positions = BasketScopedPositions(sig).Where(p => p.TradeType == reverse).ToArray();
            var found = 0;
            var closed = 0;
            var failed = 0;

            foreach (var p in positions)
            {
                found++;
                var pnl = p.NetProfit;
                var lifecycle = BasketLifecycleSnapshot(p, "basket_reverse_close", pnl, true);
                var res = ClosePosition(p);
                if (!res.IsSuccessful)
                {
                    failed++;
                    detail += $" close_failed pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} err={res.Error}";
                    Audit("basket_reverse_close_failed", sig, $"pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} err={res.Error} {lifecycle}");
                    continue;
                }
                AddBasketClosedPnl(BasketStateKeyFromPosition(p), pnl);
                _basketStates.Remove(p.Id);
                closed++;
                detail += $" closed_reverse pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} {lifecycle}";
                Audit("basket_reverse_close", sig, $"pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} {lifecycle}");
            }

            detail = $"basket_reverse_found={found} closed={closed} failed={failed} scope={(CloseReverseAcrossSourceTf ? "all_source_tf" : "same_source_tf")}" + detail;
            return failed == 0;
        }

        private bool CloseBasketPositions(BridgeSignal sig, string auditEvent, out string detail)
        {
            detail = "";
            var positions = BasketScopedPositions(sig).ToArray();
            var closed = 0;
            var failed = 0;
            foreach (var p in positions)
            {
                var pnl = p.NetProfit;
                var lifecycle = BasketLifecycleSnapshot(p, auditEvent, pnl, false);
                var res = ClosePosition(p);
                if (!res.IsSuccessful)
                {
                    failed++;
                    detail += $" close_failed pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} err={res.Error}";
                    Audit(auditEvent + "_failed", sig, $"pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} err={res.Error} {lifecycle}");
                    continue;
                }
                AddBasketClosedPnl(BasketStateKeyFromPosition(p), pnl);
                _basketStates.Remove(p.Id);
                closed++;
                detail += $" closed pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} {lifecycle}";
                Audit(auditEvent, sig, $"pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} {lifecycle}");
            }
            detail = $"basket_close_found={positions.Length} closed={closed} failed={failed}" + detail;
            return failed == 0;
        }

        private void ManageBasketRuntimeGuards()
        {
            RepairBasketStates("guard");
            SweepClosedBasketStates();

            var open = Positions.Where(p => p.SymbolName == SymbolName && IsBasketPosition(p)).ToArray();
            foreach (var p in open)
            {
                if (_basketStates.TryGetValue(p.Id, out var st))
                {
                    UpdateBasketLifecycleState(p, ref st);
                    _basketStates[p.Id] = st;
                }
            }

            var groups = open.GroupBy(p => BasketStateKeyFromPosition(p));
            foreach (var g in groups)
            {
                var first = g.First();
                var state = GetBasketState(first);
                var key = g.Key;
                if (BasketDayDone(key))
                    continue;

                var closedPnl = GetBasketClosedPnl(key);
                var floating = g.Sum(p => p.NetProfit);
                var total = closedPnl + floating;
                var targetMoney = state.TargetMoney > 0 ? state.TargetMoney : BasketTargetMoneyFromState(state);
                var maxLossMoney = state.MaxLossMoney > 0 ? state.MaxLossMoney : BasketMaxLossMoneyFromState(state, targetMoney);

                if (state.CloseSessionEnd && BasketSessionEndReached(state.SessionEndMinutes))
                {
                    BasketSetDayDone(key);
                    CloseBasketGroup(g.ToArray(), key, "basket_session_close", $"session_end_min={state.SessionEndMinutes} total_pnl={total:F2}");
                    continue;
                }

                if (targetMoney > 0 && total >= targetMoney)
                {
                    BasketSetDayDone(key);
                    CloseBasketGroup(g.ToArray(), key, "basket_target_hit_close", $"total_pnl={total:F2} target_money={targetMoney:F2} closed_pnl={closedPnl:F2} floating={floating:F2}");
                    continue;
                }

                if (maxLossMoney > 0 && total <= -maxLossMoney)
                {
                    BasketSetDayDone(key);
                    CloseBasketGroup(g.ToArray(), key, "basket_loss_hit_close", $"total_pnl={total:F2} max_loss_money={maxLossMoney:F2} closed_pnl={closedPnl:F2} floating={floating:F2}");
                }
            }
        }

        private void CloseBasketGroup(Position[] positions, string key, string auditEvent, string baseDetail)
        {
            foreach (var p in positions)
            {
                var pnl = p.NetProfit;
                var lifecycle = BasketLifecycleSnapshot(p, auditEvent, pnl, false);
                var res = ClosePosition(p);
                if (res.IsSuccessful)
                {
                    AddBasketClosedPnl(key, pnl);
                    _basketStates.Remove(p.Id);
                    AuditRaw(auditEvent, baseDetail + $" pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} {lifecycle}");
                }
                else
                {
                    AuditRaw(auditEvent + "_failed", baseDetail + $" pos={p.Id} dir={p.TradeType} volume={p.VolumeInUnits} pnl={pnl:F2} err={res.Error} {lifecycle}");
                }
            }
        }

        private void RepairBasketStates(string reason)
        {
            foreach (var p in Positions.Where(p => p.SymbolName == SymbolName && IsBasketPosition(p)))
            {
                if (_basketStates.ContainsKey(p.Id))
                    continue;
                var st = new BasketPositionState
                {
                    EventId = ParseCommentString(p.Comment, "event"),
                    SourceTf = PositionSourceTf(p),
                    DayKey = ParseCommentString(p.Comment, "day"),
                    TargetPips = ParseCommentDouble(p.Comment, "btp"),
                    TargetPct = ParseCommentDouble(p.Comment, "bpct"),
                    MaxLossPips = ParseCommentDouble(p.Comment, "blp"),
                    CatastrophicSlPips = ParseCommentDouble(p.Comment, "bcat"),
                    TargetMoney = ParseCommentDouble(p.Comment, "btmoney"),
                    MaxLossMoney = ParseCommentDouble(p.Comment, "blmoney"),
                    CloseSessionEnd = ParseCommentDouble(p.Comment, "bsess") > 0,
                    SessionEndMinutes = (int)ParseCommentDouble(p.Comment, "bsessmin"),
                    LastNetProfit = p.NetProfit,
                    OpenTime = p.EntryTime,
                    EntryPrice = p.EntryPrice,
                    Direction = p.TradeType == TradeType.Buy ? 1 : -1,
                    MfePips = 0.0,
                    MaePips = 0.0,
                    MfeMoney = p.NetProfit,
                    MaeMoney = p.NetProfit,
                    MfeTime = p.EntryTime,
                    MaeTime = p.EntryTime,
                    MfePrice = p.EntryPrice,
                    MaePrice = p.EntryPrice,
                    FirstTargetHitTime = DateTime.MinValue,
                    FirstLossHitTime = DateTime.MinValue,
                    ReverseSignalCount = 0
                };
                UpdateBasketLifecycleState(p, ref st);
                if (string.IsNullOrWhiteSpace(st.DayKey)) st.DayKey = Server.Time.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
                _basketStates[p.Id] = st;
                AuditRaw("basket_state_repaired", $"reason={reason} pos={p.Id} label={p.Label} key={BasketStateKeyFromPosition(p)} pnl={p.NetProfit:F2}");
            }
        }

        private void SweepClosedBasketStates()
        {
            foreach (var kv in _basketStates.ToArray())
            {
                if (Positions.Any(p => p.Id == kv.Key))
                    continue;
                var key = BasketStateKeyFromState(kv.Value);
                AddBasketClosedPnl(key, kv.Value.LastNetProfit);
                AuditRaw("basket_position_disappeared", $"pos={kv.Key} key={key} last_net_profit={kv.Value.LastNetProfit:F2} {BasketLifecycleDetail(kv.Value, "position_disappeared", kv.Value.LastNetProfit)}");
                _basketStates.Remove(kv.Key);
            }
        }


        private void UpdateBasketLifecycleState(Position p, ref BasketPositionState st)
        {
            if (p == null) return;
            if (st.OpenTime == DateTime.MinValue) st.OpenTime = p.EntryTime;
            if (st.EntryPrice <= 0) st.EntryPrice = p.EntryPrice;
            if (st.Direction == 0) st.Direction = p.TradeType == TradeType.Buy ? 1 : -1;
            var pipSize = Symbol.PipSize > 0 ? Symbol.PipSize : Symbol.TickSize;
            if (pipSize <= 0 || st.EntryPrice <= 0) return;
            var closePx = p.TradeType == TradeType.Buy ? Symbol.Bid : Symbol.Ask;
            var signedPips = st.Direction > 0 ? (closePx - st.EntryPrice) / pipSize : (st.EntryPrice - closePx) / pipSize;
            var now = DateTime.UtcNow;
            if (st.MfeTime == DateTime.MinValue || signedPips > st.MfePips)
            {
                st.MfePips = signedPips;
                st.MfeMoney = p.NetProfit;
                st.MfeTime = now;
                st.MfePrice = closePx;
            }
            if (st.MaeTime == DateTime.MinValue || signedPips < st.MaePips)
            {
                st.MaePips = signedPips;
                st.MaeMoney = p.NetProfit;
                st.MaeTime = now;
                st.MaePrice = closePx;
            }
            if (st.TargetPips > 0 && st.FirstTargetHitTime == DateTime.MinValue && signedPips >= st.TargetPips)
                st.FirstTargetHitTime = now;
            if (st.MaxLossPips > 0 && st.FirstLossHitTime == DateTime.MinValue && signedPips <= -st.MaxLossPips)
                st.FirstLossHitTime = now;
            st.LastNetProfit = p.NetProfit;
        }

        private string BasketLifecycleSnapshot(Position p, string closeReason, double closePnl, bool countReverseSignal)
        {
            if (p == null) return "ml_state=missing_position";
            if (!_basketStates.TryGetValue(p.Id, out var st))
            {
                st = new BasketPositionState
                {
                    EventId = ParseCommentString(p.Comment, "event"),
                    SourceTf = PositionSourceTf(p),
                    DayKey = ParseCommentString(p.Comment, "day"),
                    TargetPips = ParseCommentDouble(p.Comment, "btp"),
                    TargetPct = ParseCommentDouble(p.Comment, "bpct"),
                    MaxLossPips = ParseCommentDouble(p.Comment, "blp"),
                    CatastrophicSlPips = ParseCommentDouble(p.Comment, "bcat"),
                    TargetMoney = ParseCommentDouble(p.Comment, "btmoney"),
                    MaxLossMoney = ParseCommentDouble(p.Comment, "blmoney"),
                    OpenTime = p.EntryTime,
                    EntryPrice = p.EntryPrice,
                    Direction = p.TradeType == TradeType.Buy ? 1 : -1,
                    MfeTime = DateTime.MinValue,
                    MaeTime = DateTime.MinValue,
                    FirstTargetHitTime = DateTime.MinValue,
                    FirstLossHitTime = DateTime.MinValue
                };
            }
            if (countReverseSignal) st.ReverseSignalCount++;
            UpdateBasketLifecycleState(p, ref st);
            _basketStates[p.Id] = st;
            return BasketLifecycleDetail(st, closeReason, closePnl);
        }

        private string BasketLifecycleDetail(BasketPositionState st, string closeReason, double closePnl)
        {
            var now = DateTime.UtcNow;
            var open = st.OpenTime == DateTime.MinValue ? now : st.OpenTime;
            var duration = Math.Max(0, (now - open).TotalSeconds);
            var mfeFav = Math.Max(0.0, st.MfePips);
            var maeAdv = Math.Max(0.0, -st.MaePips);
            var targetHit = st.FirstTargetHitTime != DateTime.MinValue;
            var lossHit = st.FirstLossHitTime != DateTime.MinValue;
            var first = "none";
            if (targetHit && lossHit) first = st.FirstTargetHitTime <= st.FirstLossHitTime ? "target" : "loss";
            else if (targetHit) first = "target";
            else if (lossHit) first = "loss";
            return $"ml=1 close_reason={closeReason} event_id={st.EventId} day={st.DayKey} entry={st.EntryPrice:F5} dir={st.Direction} duration_sec={duration:F0} close_pnl={closePnl:F2} target_pips={st.TargetPips:F2} max_loss_pips={st.MaxLossPips:F2} cat_sl_pips={st.CatastrophicSlPips:F2} target_money={st.TargetMoney:F2} max_loss_money={st.MaxLossMoney:F2} mfe_pips={mfeFav:F2} mae_pips={maeAdv:F2} mfe_signed_pips={st.MfePips:F2} mae_signed_pips={st.MaePips:F2} mfe_money={st.MfeMoney:F2} mae_money={st.MaeMoney:F2} mfe_price={st.MfePrice:F5} mae_price={st.MaePrice:F5} first_target_hit={(targetHit ? 1 : 0)} first_loss_hit={(lossHit ? 1 : 0)} first_hit={first} target_hit_time={TimeText(st.FirstTargetHitTime)} loss_hit_time={TimeText(st.FirstLossHitTime)} mfe_time={TimeText(st.MfeTime)} mae_time={TimeText(st.MaeTime)} reverse_signal_count={st.ReverseSignalCount}";
        }

        private static string TimeText(DateTime t)
        {
            return t == DateTime.MinValue ? "" : t.ToUniversalTime().ToString("yyyy-MM-dd_HH:mm:ss", CultureInfo.InvariantCulture);
        }

        private bool IsBasketPosition(Position p)
        {
            if (p == null || string.IsNullOrWhiteSpace(p.Label)) return false;
            return p.Label.StartsWith(LabelPrefix + "B", StringComparison.Ordinal) || SameText(ParseCommentString(p.Comment, "mode"), "basket");
        }

        private string BasketDayKey(BridgeSignal sig)
        {
            return !string.IsNullOrWhiteSpace(sig.BasketDayKey) ? sig.BasketDayKey.Trim() : Server.Time.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
        }

        private string BasketStateKey(BridgeSignal sig)
        {
            return $"{Account.Number}|{SymbolName}|{NormalizeTf(sig.SourceTf)}|{BasketDayKey(sig)}";
        }

        private string BasketStateKeyFromPosition(Position p)
        {
            var st = GetBasketState(p);
            return BasketStateKeyFromState(st);
        }

        private string BasketStateKeyFromState(BasketPositionState st)
        {
            return $"{Account.Number}|{SymbolName}|{NormalizeTf(st.SourceTf)}|{st.DayKey}";
        }

        private BasketPositionState GetBasketState(Position p)
        {
            if (_basketStates.TryGetValue(p.Id, out var st))
                return st;
            return new BasketPositionState
            {
                EventId = ParseCommentString(p.Comment, "event"),
                SourceTf = PositionSourceTf(p),
                DayKey = ParseCommentString(p.Comment, "day"),
                TargetPips = ParseCommentDouble(p.Comment, "btp"),
                TargetPct = ParseCommentDouble(p.Comment, "bpct"),
                MaxLossPips = ParseCommentDouble(p.Comment, "blp"),
                CatastrophicSlPips = ParseCommentDouble(p.Comment, "bcat"),
                TargetMoney = ParseCommentDouble(p.Comment, "btmoney"),
                MaxLossMoney = ParseCommentDouble(p.Comment, "blmoney"),
                CloseSessionEnd = ParseCommentDouble(p.Comment, "bsess") > 0,
                SessionEndMinutes = (int)ParseCommentDouble(p.Comment, "bsessmin"),
                LastNetProfit = p.NetProfit
            };
        }

        private void AddBasketClosedPnl(string key, double pnl)
        {
            if (string.IsNullOrWhiteSpace(key)) return;
            _basketClosedPnlByDay[key] = GetBasketClosedPnl(key) + pnl;
        }

        private double GetBasketClosedPnl(string key)
        {
            return _basketClosedPnlByDay.TryGetValue(key, out var pnl) ? pnl : 0.0;
        }

        private bool BasketDayDone(string key) => _basketDayDone.Contains(key);
        private void BasketSetDayDone(string key) { if (!string.IsNullOrWhiteSpace(key)) _basketDayDone.Add(key); }

        private double BasketTargetMoneyFromState(BasketPositionState st)
        {
            var capital = UseBalanceForRisk ? Account.Balance : Account.Equity;
            return capital * Math.Max(0, st.TargetPct) / 100.0;
        }

        private double BasketMaxLossMoneyFromState(BasketPositionState st, double targetMoney)
        {
            if (st.TargetPips <= 0) return 0;
            return targetMoney * (st.MaxLossPips / st.TargetPips);
        }

        private bool BasketSessionEndReached(int minutes)
        {
            if (minutes < 0) return false;
            var now = Server.Time;
            return now.Hour * 60 + now.Minute >= minutes;
        }

        private static int ParseHhMm(string value)
        {
            if (string.IsNullOrWhiteSpace(value)) return -1;
            var parts = value.Trim().Split(':');
            if (parts.Length != 2) return -1;
            if (!int.TryParse(parts[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out var h)) return -1;
            if (!int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var m)) return -1;
            if (h < 0 || h > 23 || m < 0 || m > 59) return -1;
            return h * 60 + m;
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

            var mod = ModifyPosition(position, sig.Sl, sig.Tp);
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
                if (IsBasketPosition(p))
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
                    continue;
                }

                var st = kv.Value;
                if (st.Done || st.HalfTrigger <= 0)
                    continue;

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
                    AuditRaw("halfbe_blocked_volume", baseDetail + " reason=partial_close_impossible_for_broker_volume");
                    continue;
                }

                var close = ClosePosition(pos, closeVolume);
                if (!close.IsSuccessful)
                {
                    AuditRaw("halfbe_partial_close_failed", baseDetail + $" err={close.Error}");
                    continue;
                }

                var remaining = Positions.FirstOrDefault(p => p.Id == pos.Id) ?? Positions.FirstOrDefault(p => p.SymbolName == SymbolName && p.Label == pos.Label);
                if (remaining == null)
                {
                    st.Done = true;
                    _halfStates[kv.Key] = st;
                    AuditRaw("halfbe_partial_close_success_position_closed", baseDetail);
                    continue;
                }

                var be = remaining.EntryPrice;
                var mod = ModifyPosition(remaining, be, remaining.TakeProfit, ProtectionType.Absolute);
                AuditRaw(mod.IsSuccessful ? "halfbe_done" : "halfbe_sl_to_be_failed_after_partial", baseDetail + $" be_sl={be} remaining_after={remaining.VolumeInUnits} modify_err={mod.Error}");
                st.Done = true;
                _halfStates[kv.Key] = st;
            }
        }
        private bool IsBasketSignal(BridgeSignal sig)
        {
            return SameText(sig.TradeMode, "basket_daily_target") || SameText(sig.TradeMode, "basket");
        }

        private bool TryReadSignal(out BridgeSignal sig, out string detail)
        {
            sig = new BridgeSignal();
            detail = "";
            if (!IoFile.Exists(_resolvedBridgePath))
            {
                detail = "file_not_found " + _resolvedBridgePath;
                return false;
            }

            string text;
            try
            {
                text = IoFile.ReadAllText(_resolvedBridgePath);
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
                if (fields.Count > 18 && fields[18] == "trade_mode")
                    offset = 27;
                else if (fields.Count > 17 && fields[17] == "risk_pct")
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
            sig.TradeMode = fields.Count > offset + 18 ? fields[offset + 18] : "traditional";
            if (string.IsNullOrWhiteSpace(sig.TradeMode)) sig.TradeMode = "traditional";
            sig.BasketTargetPips = fields.Count > offset + 19 ? ParseDouble(fields[offset + 19]) : 0;
            sig.BasketTargetPct = fields.Count > offset + 20 ? ParseDouble(fields[offset + 20]) : 0;
            sig.BasketMaxLossPips = fields.Count > offset + 21 ? ParseDouble(fields[offset + 21]) : 0;
            sig.BasketCatastrophicSlPips = fields.Count > offset + 22 ? ParseDouble(fields[offset + 22]) : 0;
            sig.BasketCloseOnReverse = fields.Count > offset + 23 && ParseBool(fields[offset + 23]);
            sig.BasketCloseSessionEnd = fields.Count > offset + 24 && ParseBool(fields[offset + 24]);
            sig.BasketSessionEndTime = fields.Count > offset + 25 ? fields[offset + 25] : "";
            sig.BasketDayKey = fields.Count > offset + 26 ? fields[offset + 26] : "";
            var rawDir = fields[offset + 7];
            sig.Valid = !string.IsNullOrWhiteSpace(sig.EventId) && sig.Direction != 0;

            detail = $"read_ok fields={fields.Count} offset={offset} event={sig.EventId} source_symbol={sig.SourceSymbol} source_tf={sig.SourceTf} dir={rawDir} risk_pct={sig.RiskPct:F3} trade_mode={sig.TradeMode} basket_target_pips={sig.BasketTargetPips:F2} basket_target_pct={sig.BasketTargetPct:F3}";
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
            if (RequireMappedSymbolEqualsChart && !SameText(mapped, SymbolName))
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

            if (!string.IsNullOrWhiteSpace(SourceFilter) && !ContainsText(sig.Source, SourceFilter))
            {
                reason = $"source_filter source={sig.Source} expected={SourceFilter}";
                return false;
            }
            return true;
        }

        private string ResolveBridgePath()
        {
            if (!string.IsNullOrWhiteSpace(BridgeLatestPath))
                return BridgeLatestPath.Trim();
            return IoPath.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MetaQuotes", "Terminal", "Common", "Files", "PRORENKOFileBridge_Latest.csv");
        }

        private string BuildLabel(BridgeSignal sig) => $"{LabelPrefix}|T{NormalizeTf(sig.SourceTf)}|{Hash32(sig.EventId):X8}";
        private string BuildBasketLabel(BridgeSignal sig) => $"{LabelPrefix}B|T{NormalizeTf(sig.SourceTf)}|{Hash32(sig.EventId):X8}";

        private bool ClaimEvent(string eventId)
        {
            var lockPath = IoPath.Combine(_lockDir, $"{Account.Number}_{Sanitize(SymbolName)}_{Hash32(eventId):X8}.lock");
            try
            {
                using (var fs = new IoFileStream(lockPath, IoFileMode.CreateNew, IoFileAccess.Write, IoFileShare.None))
                using (var sw = new IoStreamWriter(fs))
                    sw.WriteLine(DateTime.UtcNow.ToString("O") + " " + eventId);
                return true;
            }
            catch (IoException)
            {
                return false;
            }
        }

        private void ReleaseEvent(string eventId)
        {
            var lockPath = IoPath.Combine(_lockDir, $"{Account.Number}_{Sanitize(SymbolName)}_{Hash32(eventId):X8}.lock");
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
            if (source.EndsWith("m", StringComparison.OrdinalIgnoreCase) && SameText(source.Substring(0, source.Length - 1), SymbolName))
                return SymbolName;
            return source;
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
            if (!RebaseMappedLevelsToLiveEntry) return false;
            if (sig.BridgeEntry <= 0 || sig.Sl <= 0 || sig.Tp <= 0) return false;
            var mapped = MapSymbol(sig.SourceSymbol);
            if (!SameText(mapped, SymbolName)) return false;
            if (RebaseOnlyWhenSourceDiffers && (SameText(sig.SourceSymbol, SymbolName) || SameEconomicSymbol(sig.SourceSymbol, SymbolName))) return false;
            return true;
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

        private void RepairOpenPositionStates(string reason)
        {
            if (!ManageHalfCloseBe) return;
            foreach (var p in Positions.Where(p => p.SymbolName == SymbolName && !string.IsNullOrWhiteSpace(p.Label) && p.Label.StartsWith(LabelPrefix, StringComparison.Ordinal)))
            {
                if (_halfStates.ContainsKey(p.Id)) continue;
                var half = ParseCommentDouble(p.Comment, "half");
                if (half <= 0) continue;
                _halfStates[p.Id] = new HalfState
                {
                    EventId = ParseCommentString(p.Comment, "event"),
                    SourceTf = PositionSourceTf(p),
                    Direction = p.TradeType == TradeType.Buy ? 1 : -1,
                    Entry = p.EntryPrice,
                    HalfTrigger = half,
                    InitialVolume = p.VolumeInUnits,
                    StopLoss = ParseCommentDouble(p.Comment, "sl"),
                    TakeProfit = ParseCommentDouble(p.Comment, "tp"),
                    Done = false
                };
                AuditRaw("position_state_repaired", $"reason={reason} pos={p.Id} label={p.Label} source_tf={PositionSourceTf(p)} entry={p.EntryPrice} half={half} sl={ParseCommentDouble(p.Comment, "sl")} tp={ParseCommentDouble(p.Comment, "tp")}");
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
            var scoped = Positions.Where(p => p.SymbolName == SymbolName && !string.IsNullOrWhiteSpace(p.Label) && p.Label.StartsWith(LabelPrefix, StringComparison.Ordinal)).ToArray();
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

        private string BasketOpenSummary()
        {
            var open = Positions.Where(p => p.SymbolName == SymbolName && IsBasketPosition(p)).ToArray();
            if (open.Length == 0) return "0";
            var groups = open.GroupBy(p => BasketStateKeyFromPosition(p)).Select(g =>
            {
                var key = g.Key;
                var closed = GetBasketClosedPnl(key);
                var floating = g.Sum(p => p.NetProfit);
                var state = GetBasketState(g.First());
                var target = state.TargetMoney > 0 ? state.TargetMoney : BasketTargetMoneyFromState(state);
                var loss = state.MaxLossMoney > 0 ? state.MaxLossMoney : BasketMaxLossMoneyFromState(state, target);
                return $"tf={PositionSourceTf(g.First())} open={g.Count()} pnl={(closed + floating):F2}/{target:F2} lossLimit={loss:F2}";
            });
            return string.Join(" | ", groups);
        }
        private void DrawDashboard()
        {
            if (!ShowDashboard) return;
            var text = $"ProRenko cTrader Listener {Build}\n"
                     + $"Executor={(ExecutorEnabled ? "ON" : "OFF")} Symbol={SymbolName} File={IoPath.GetFileName(_resolvedBridgePath)}\n"
                     + $"RiskPct={(UseBridgeRiskPct ? "BRIDGE" : "LOCAL")} Capital={(UseBalanceForRisk ? "cTrader BAL" : "cTrader EQ")} Equity={Account.Equity:F2} Balance={Account.Balance:F2}\n"
                     + $"Positions={OpenPositionSummary()}\n"
                     + $"Basket={BasketOpenSummary()}\n"
                     + $"Seen={ShortEvent(_lastSeenEventId)} Rej={ShortEvent(_lastRejectedEventId)}\n"
                     + $"Last={_lastAction} {_lastDetail}\nSignal={_lastSignal}";
            Chart.DrawStaticText("PRB_CT_DASH", text, VerticalAlignment.Top, HorizontalAlignment.Left, Color.LightSkyBlue);
        }

        private void Audit(string eventName, BridgeSignal sig, string detail)
        {
            _lastAction = eventName;
            _lastDetail = detail;
            _lastSignal = $"{sig.SourceSymbol} {sig.SourceTf} {(sig.Direction > 0 ? "BUY" : "SELL")} mode={sig.TradeMode} {ShortEvent(sig.EventId)}";
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
            try
            {
                var file = IoPath.Combine(_auditDir, AuditFilePrefix + DateTime.UtcNow.ToString("yyyyMMdd") + ".csv");
                var header = !IoFile.Exists(file);
                using (var sw = new IoStreamWriter(file, true, Encoding.UTF8))
                {
                    if (header)
                        sw.WriteLine("time_gmt,build,event,account,chart_symbol,source_symbol,source_tf,event_id,source,dir,entry,sl,tp,half,detail");
                    sw.WriteLine(string.Join(",", Escape(DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss")), Escape(Build), Escape(eventName), Escape(Account.Number.ToString()), Escape(SymbolName), Escape(sourceSymbol), Escape(sourceTf), Escape(eventId), Escape(source), Escape(dir), entry.ToString(CultureInfo.InvariantCulture), sl.ToString(CultureInfo.InvariantCulture), tp.ToString(CultureInfo.InvariantCulture), half.ToString(CultureInfo.InvariantCulture), Escape(detail)));
                }
            }
            catch (Exception ex)
            {
                Print("Audit write failed: {0}", ex.Message);
            }
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

        private static bool ParseBool(string s)
        {
            var v = (s ?? "").Trim().ToLowerInvariant();
            return v == "1" || v == "true" || v == "yes" || v == "on";
        }

        private static string CanonicalSymbol(string value)
        {
            var s = new string((value ?? "").Trim().Where(char.IsLetterOrDigit).ToArray()).ToUpperInvariant();
            if (s.EndsWith("M", StringComparison.OrdinalIgnoreCase) && s.Length > 1)
                s = s.Substring(0, s.Length - 1);
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
            public string TradeMode;
            public double BasketTargetPips;
            public double BasketTargetPct;
            public double BasketMaxLossPips;
            public double BasketCatastrophicSlPips;
            public bool BasketCloseOnReverse;
            public bool BasketCloseSessionEnd;
            public string BasketSessionEndTime;
            public string BasketDayKey;
        }

        private struct BasketPositionState
        {
            public string EventId;
            public string SourceTf;
            public string DayKey;
            public double TargetPips;
            public double TargetPct;
            public double MaxLossPips;
            public double CatastrophicSlPips;
            public double TargetMoney;
            public double MaxLossMoney;
            public bool CloseSessionEnd;
            public int SessionEndMinutes;
            public double LastNetProfit;
            public DateTime OpenTime;
            public double EntryPrice;
            public int Direction;
            public double MfePips;
            public double MaePips;
            public double MfeMoney;
            public double MaeMoney;
            public DateTime MfeTime;
            public DateTime MaeTime;
            public double MfePrice;
            public double MaePrice;
            public DateTime FirstTargetHitTime;
            public DateTime FirstLossHitTime;
            public int ReverseSignalCount;
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
            public bool Done;
        }
    }
}
