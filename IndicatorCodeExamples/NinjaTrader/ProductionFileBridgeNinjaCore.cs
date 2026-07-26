// NinjaTrader 8 production file-bridge execution core.
// This file contains execution/lifecycle logic only; it does not generate signals.
#region Using declarations
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.ComponentModel.DataAnnotations;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Windows.Media;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
using NinjaTrader.Gui.Tools;
using NinjaTrader.NinjaScript.DrawingTools;
#endregion

namespace NinjaTrader.NinjaScript.Strategies
{
    public abstract partial class ProductionFileBridgeNinjaCore : Strategy
    {
        private const string CoreBuild = "2026-07-26.nt8-production-file-bridge-v4-listener-default-presets";
        private const int PendingLockSeconds = 120;
        private const int EmergencyRetrySeconds = 10;

        protected abstract string ListenerTitle { get; }
        protected abstract string DefaultBridgeLatestPath { get; }
        protected abstract string DefaultSourceNamespace { get; }
        protected abstract string DefaultOrderPrefix { get; }
        protected abstract string DefaultAuditPrefix { get; }
        protected virtual string DefaultSourceTimeframeFilter { get { return string.Empty; } }
        protected virtual bool DefaultSourceTfToChartPeriodSetting { get { return true; } }
        protected virtual string DefaultSourceSymbolAliasesCsv { get { return string.Empty; } }
        protected virtual bool DefaultRebaseMappedLevelsToLiveEntry { get { return false; } }

        #region User inputs
        [NinjaScriptProperty]
        [Display(Name = "Executor Enabled", GroupName = "01 Execution", Order = 0)]
        public bool ExecutorEnabled { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Bridge Latest Path", GroupName = "02 Bridge", Order = 0)]
        public string BridgeLatestPath { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Prefer Scoped Latest", GroupName = "02 Bridge", Order = 1)]
        public bool PreferScopedLatest { get; set; }

        [NinjaScriptProperty]
        [Range(100, 60000)]
        [Display(Name = "Poll Milliseconds", GroupName = "02 Bridge", Order = 2)]
        public int PollMilliseconds { get; set; }

        [NinjaScriptProperty]
        [Range(1, 86400)]
        [Display(Name = "Max Signal Age Sec", GroupName = "02 Bridge", Order = 3)]
        public int MaxSignalAgeSeconds { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Ignore Existing On Init", GroupName = "02 Bridge", Order = 4)]
        public bool IgnoreExistingSignalOnInit { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Source TF Filter", GroupName = "03 Identity", Order = 0)]
        public string SourceTimeframeFilter { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Default TF To Chart", GroupName = "03 Identity", Order = 1)]
        public bool DefaultSourceTfToChartPeriod { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Source Filter", GroupName = "03 Identity", Order = 2)]
        public string SourceFilter { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Source Symbol Aliases CSV", GroupName = "03 Identity", Order = 3)]
        public string SourceSymbolAliasesCsv { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Require Chart Symbol", GroupName = "03 Identity", Order = 4)]
        public bool RequireSourceMatchesChart { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Rebase Levels To Live", GroupName = "04 Geometry", Order = 0)]
        public bool RebaseMappedLevelsToLiveEntry { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Rebase Only Source Differs", GroupName = "04 Geometry", Order = 1)]
        public bool RebaseOnlyWhenSourceDiffers { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, 10000.0)]
        [Display(Name = "Mapped Basis Guard % Risk", GroupName = "04 Geometry", Order = 2)]
        public double MappedBasisGuardPctRisk { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Fail If Exact Protection Fails", GroupName = "04 Geometry", Order = 3)]
        public bool FailIfExactProtectionFails { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Close Reverse", GroupName = "05 Lifecycle", Order = 0)]
        public bool CloseReverse { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Close Reverse Across TF", GroupName = "05 Lifecycle", Order = 1)]
        public bool CloseReverseAcrossSourceTf { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Enable Close-Only Signals", GroupName = "05 Lifecycle", Order = 2)]
        public bool EnableCloseOnlySignals { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Permanent Reject Guard", GroupName = "05 Lifecycle", Order = 3)]
        public bool PermanentRejectGuard { get; set; }

        [NinjaScriptProperty]
        [Range(30, 86400)]
        [Display(Name = "Market Closed Retry Sec", GroupName = "05 Lifecycle", Order = 4)]
        public int MarketClosedRetrySeconds { get; set; }

        [NinjaScriptProperty]
        [Range(5, 3600)]
        [Display(Name = "Order Failure Retry Sec", GroupName = "05 Lifecycle", Order = 5)]
        public int OrderFailureRetrySeconds { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Use Risk Contracts", GroupName = "06 Risk", Order = 0)]
        public bool UseRiskContracts { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, 100.0)]
        [Display(Name = "Local Risk %", GroupName = "06 Risk", Order = 1)]
        public double LocalRiskPct { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Use Bridge Risk %", GroupName = "06 Risk", Order = 2)]
        public bool UseBridgeRiskPct { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Use Cash Value For Risk", GroupName = "06 Risk", Order = 3)]
        public bool UseCashValueForRisk { get; set; }

        [NinjaScriptProperty]
        [Range(1, 100000)]
        [Display(Name = "Manual Contracts", GroupName = "06 Risk", Order = 4)]
        public int ManualContracts { get; set; }

        [NinjaScriptProperty]
        [Range(0, 100000)]
        [Display(Name = "Max Contracts (0=off)", GroupName = "06 Risk", Order = 5)]
        public int MaxContracts { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Block If 1 Contract Exceeds Risk", GroupName = "06 Risk", Order = 6)]
        public bool BlockIfMinContractExceedsRisk { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Post-Fill Risk Guard", GroupName = "06 Risk", Order = 7)]
        public bool PostFillRiskGuard { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, 100.0)]
        [Display(Name = "Max Risk Overshoot %", GroupName = "06 Risk", Order = 8)]
        public double MaxRiskOvershootPct { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Fail Closed On Risk Error", GroupName = "06 Risk", Order = 9)]
        public bool FailClosedOnRiskError { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Use Margin Guard", GroupName = "07 Margin", Order = 0)]
        public bool UseMarginGuard { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, double.MaxValue)]
        [Display(Name = "Estimated Margin / Contract", GroupName = "07 Margin", Order = 1)]
        public double EstimatedMarginPerContract { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, 100.0)]
        [Display(Name = "Max Margin Usage %", GroupName = "07 Margin", Order = 2)]
        public double MaxMarginUsagePct { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Fail If Margin Estimate Missing", GroupName = "07 Margin", Order = 3)]
        public bool FailIfMarginEstimateMissing { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "No-Money Retry Shrink", GroupName = "07 Margin", Order = 4)]
        public bool NoMoneyRetryShrink { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, 100000.0)]
        [Display(Name = "Max Spread Ticks (0=off)", GroupName = "08 Market", Order = 0)]
        public double MaxSpreadTicks { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Manage HCBE", GroupName = "09 HCBE", Order = 0)]
        public bool ManageHalfCloseBe { get; set; }

        [NinjaScriptProperty]
        [Range(0.01, 0.99)]
        [Display(Name = "Half Close Fraction", GroupName = "09 HCBE", Order = 1)]
        public double HalfCloseFraction { get; set; }

        [NinjaScriptProperty]
        [Range(1, 3600)]
        [Display(Name = "HCBE Retry Sec", GroupName = "09 HCBE", Order = 2)]
        public int HalfBeRetrySeconds { get; set; }

        [NinjaScriptProperty]
        [Range(5, 86400)]
        [Display(Name = "HCBE Volume Retry Sec", GroupName = "09 HCBE", Order = 3)]
        public int HalfBeVolumeRetrySeconds { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Audit Enabled", GroupName = "10 Diagnostics", Order = 0)]
        public bool AuditEnabled { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Audit File Prefix", GroupName = "10 Diagnostics", Order = 1)]
        public string AuditFilePrefix { get; set; }

        [NinjaScriptProperty]
        [Range(0, 86400)]
        [Display(Name = "Poll Heartbeat Sec", GroupName = "10 Diagnostics", Order = 2)]
        public int PollHeartbeatSeconds { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Show Dashboard", GroupName = "10 Diagnostics", Order = 3)]
        public bool ShowDashboard { get; set; }
        #endregion

        private readonly Dictionary<string, TradeState> trades = new Dictionary<string, TradeState>(StringComparer.Ordinal);
        private readonly Dictionary<string, DateTime> retryBlockedUntil = new Dictionary<string, DateTime>(StringComparer.Ordinal);
        private readonly Dictionary<string, DateTime> auditThrottle = new Dictionary<string, DateTime>(StringComparer.Ordinal);
        private System.Timers.Timer pollTimer;
        private int pollQueued;
        private bool initialized;
        private bool terminating;
        private bool lifecycleFault;
        private string lifecycleFaultDetail = string.Empty;
        private string resolvedBridgePath = string.Empty;
        private string instanceToken = string.Empty;
        private string orderScopePrefix = string.Empty;
        private string stateDir = string.Empty;
        private string lockDir = string.Empty;
        private string auditDir = string.Empty;
        private string lastSeenEventId = string.Empty;
        private string lastRejectedEventId = string.Empty;
        private string lastAction = "boot";
        private string lastDetail = string.Empty;
        private string lastSignal = "none";
        private DateTime lastHeartbeat = DateTime.MinValue;
        private DateTime lastReadAudit = DateTime.MinValue;
        private BridgeSignal? deferredSignal;
        private static readonly object AuditWriteSync = new object();

        protected override void OnStateChange()
        {
            if (State == State.SetDefaults)
            {
                Description = ListenerTitle + " - MT bridge execution listener. No signal generation.";
                Name = ListenerTitle;
                Calculate = Calculate.OnEachTick;
                IsOverlay = true;
                BarsRequiredToTrade = 0;
                IsExitOnSessionCloseStrategy = false;
                IncludeCommission = true;
                StartBehavior = StartBehavior.ImmediatelySubmit;
                RealtimeErrorHandling = RealtimeErrorHandling.IgnoreAllErrors;
                ConnectionLossHandling = ConnectionLossHandling.KeepRunning;
                DisconnectDelaySeconds = 60;
                NumberRestartAttempts = 10;
                RestartsWithinMinutes = 10;
                IsAdoptAccountPositionAware = true;
                IsInstantiatedOnEachOptimizationIteration = false;

                ExecutorEnabled = true;
                BridgeLatestPath = DefaultBridgeLatestPath;
                PreferScopedLatest = true;
                PollMilliseconds = 500;
                MaxSignalAgeSeconds = 900;
                IgnoreExistingSignalOnInit = true;
                SourceTimeframeFilter = DefaultSourceTimeframeFilter;
                DefaultSourceTfToChartPeriod = DefaultSourceTfToChartPeriodSetting;
                SourceFilter = DefaultSourceNamespace.TrimEnd('|');
                SourceSymbolAliasesCsv = DefaultSourceSymbolAliasesCsv;
                RequireSourceMatchesChart = true;
                RebaseMappedLevelsToLiveEntry = DefaultRebaseMappedLevelsToLiveEntry;
                RebaseOnlyWhenSourceDiffers = true;
                MappedBasisGuardPctRisk = 25.0;
                FailIfExactProtectionFails = true;
                CloseReverse = true;
                CloseReverseAcrossSourceTf = false;
                EnableCloseOnlySignals = true;
                PermanentRejectGuard = true;
                MarketClosedRetrySeconds = 900;
                OrderFailureRetrySeconds = 60;
                UseRiskContracts = true;
                LocalRiskPct = 1.0;
                UseBridgeRiskPct = true;
                UseCashValueForRisk = false;
                ManualContracts = 1;
                MaxContracts = 50;
                BlockIfMinContractExceedsRisk = true;
                PostFillRiskGuard = true;
                MaxRiskOvershootPct = 5.0;
                FailClosedOnRiskError = true;
                UseMarginGuard = true;
                EstimatedMarginPerContract = 0;
                MaxMarginUsagePct = 40.0;
                FailIfMarginEstimateMissing = false;
                NoMoneyRetryShrink = true;
                MaxSpreadTicks = 0;
                ManageHalfCloseBe = true;
                HalfCloseFraction = 0.5;
                HalfBeRetrySeconds = 5;
                HalfBeVolumeRetrySeconds = 60;
                AuditEnabled = true;
                AuditFilePrefix = DefaultAuditPrefix;
                PollHeartbeatSeconds = 300;
                ShowDashboard = true;
                SetTradeDayComplianceDefaults();
            }
            else if (State == State.Realtime)
            {
                InitializeRuntime();
            }
            else if (State == State.Terminated)
            {
                terminating = true;
                StopTimer();
                ShutdownTradeDayCompliance();
            }
        }

        protected override void OnBarUpdate()
        {
            if (State == State.Realtime && initialized)
                DrawDashboard();
        }

        private void InitializeRuntime()
        {
            if (initialized)
                return;

            resolvedBridgePath = ResolveBridgePath();
            auditDir = Path.GetDirectoryName(resolvedBridgePath) ?? NinjaTrader.Core.Globals.UserDataDir;
            instanceToken = Hash64(NormalizePath(resolvedBridgePath) + "|" + ExpectedSourceNamespace() + "|" + EffectiveSourceTf() + "|" + SafeAccountName() + "|" + Instrument.FullName).ToString("X16", CultureInfo.InvariantCulture);
            orderScopePrefix = BuildOrderScopePrefix();
            stateDir = Path.Combine(auditDir, "NinjaBridgeState", Sanitize(DefaultOrderPrefix), Sanitize(SafeAccountName()), instanceToken);
            lockDir = Path.Combine(stateDir, "locks");
            Directory.CreateDirectory(stateDir);
            Directory.CreateDirectory(lockDir);

            InitializeTradeDayCompliance();
            LoadTradeStates();
            ReconcileRestartState("init");
            initialized = true;
            AuditRaw("init", "build=" + CoreBuild + " bridge=" + resolvedBridgePath + " instrument=" + Instrument.FullName + " account=" + SafeAccountName() + " scope=" + instanceToken + " active_states=" + trades.Count);

            if (IgnoreExistingSignalOnInit)
                SeedExistingSignal();

            StartTimer();
            PollCycle("init");
            DrawDashboard();
        }

        private void StartTimer()
        {
            StopTimer();
            pollTimer = new System.Timers.Timer(Math.Max(100, PollMilliseconds));
            pollTimer.AutoReset = true;
            pollTimer.Elapsed += PollTimerElapsed;
            pollTimer.Start();
        }

        private void StopTimer()
        {
            var timer = pollTimer;
            pollTimer = null;
            if (timer == null)
                return;
            try
            {
                timer.Stop();
                timer.Elapsed -= PollTimerElapsed;
                timer.Dispose();
            }
            catch { }
        }

        private void PollTimerElapsed(object sender, System.Timers.ElapsedEventArgs args)
        {
            if (terminating || State != State.Realtime || Interlocked.Exchange(ref pollQueued, 1) != 0)
                return;
            try
            {
                TriggerCustomEvent(_ =>
                {
                    try { PollCycle("timer"); }
                    catch (Exception ex) { AuditRaw("poll_exception", ex.ToString()); }
                    finally { Interlocked.Exchange(ref pollQueued, 0); }
                }, null);
            }
            catch
            {
                Interlocked.Exchange(ref pollQueued, 0);
            }
        }

        private void PollCycle(string caller)
        {
            if (!initialized || terminating)
                return;

            EvaluateAndEnforceTradeDayCompliance();
            if (!TradeDayShouldSuspendManagedLifecycle())
                ProcessTradeStates();
            if ((DateTime.UtcNow - lastHeartbeat).TotalSeconds >= Math.Max(1, PollHeartbeatSeconds) && PollHeartbeatSeconds > 0)
            {
                lastHeartbeat = DateTime.UtcNow;
                AuditRaw("poll_heartbeat", "caller=" + caller + " states=" + trades.Count + " seen=" + ShortEvent(lastSeenEventId) + " rejected=" + ShortEvent(lastRejectedEventId));
            }

            if (deferredSignal.HasValue && !HasPendingExit() && !HasOppositeTrade(deferredSignal.Value.Direction, deferredSignal.Value.SourceTf))
            {
                var pending = deferredSignal.Value;
                deferredSignal = null;
                ExecuteSignal(pending, "deferred_after_reverse");
            }

            PollBridge(caller);
            CleanupOldLocks();
            DrawDashboard();
        }

        private void SeedExistingSignal()
        {
            BridgeSignal sig;
            string detail;
            if (!TryReadSignal(out sig, out detail) || !SignalIdentityMatches(sig, out detail))
                return;
            var age = (DateTime.UtcNow - sig.WrittenGmt).TotalSeconds;
            if (MaxSignalAgeSeconds > 0 && age > MaxSignalAgeSeconds)
            {
                lastSeenEventId = sig.EventId;
                Audit("init_baseline_existing_signal", sig, "seeded=1 age_sec=" + age.ToString("F0", CultureInfo.InvariantCulture));
            }
            else
            {
                Audit("init_existing_fresh_signal_pending", sig, "seeded=0 age_sec=" + age.ToString("F0", CultureInfo.InvariantCulture));
            }
        }

        private void PollBridge(string caller)
        {
            BridgeSignal sig;
            string readDetail;
            if (!TryReadSignal(out sig, out readDetail))
            {
                if ((DateTime.UtcNow - lastReadAudit).TotalSeconds >= 300)
                {
                    lastReadAudit = DateTime.UtcNow;
                    AuditRaw("read_failed", readDetail);
                }
                SetAction("read_failed", readDetail);
                return;
            }

            if (sig.EventId == lastSeenEventId || (PermanentRejectGuard && sig.EventId == lastRejectedEventId) || HasCommittedEvent(sig.EventId))
            {
                SetAction("idle_duplicate_latest", ShortEvent(sig.EventId));
                return;
            }

            string identityReason;
            if (!SignalIdentityMatches(sig, out identityReason))
            {
                if (PermanentRejectGuard)
                    lastRejectedEventId = sig.EventId;
                Audit("skip_filter", sig, identityReason + " " + readDetail);
                return;
            }

            DateTime blockedUntil;
            if (retryBlockedUntil.TryGetValue(sig.EventId, out blockedUntil) && DateTime.UtcNow < blockedUntil)
            {
                SetAction("order_retry_cooldown", "until=" + blockedUntil.ToString("O"));
                return;
            }
            retryBlockedUntil.Remove(sig.EventId);

            var age = (DateTime.UtcNow - sig.WrittenGmt).TotalSeconds;
            if (MaxSignalAgeSeconds > 0 && age > MaxSignalAgeSeconds)
            {
                if (PermanentRejectGuard)
                    lastRejectedEventId = sig.EventId;
                Audit("skip_stale", sig, "age_sec=" + age.ToString("F0", CultureInfo.InvariantCulture) + " max=" + MaxSignalAgeSeconds);
                return;
            }

            Audit("signal_received", sig, "caller=" + caller + " " + readDetail);
            if (!ExecutorEnabled)
            {
                lastSeenEventId = sig.EventId;
                CommitEvent(sig.EventId, "executor_off");
                Audit("skip_executor_off", sig, "executor disabled");
                return;
            }

            if (EnableCloseOnlySignals && IsCloseOnlySignal(sig))
            {
                ProcessCloseOnly(sig);
                return;
            }

            string complianceReason;
            if (!TradeDayCanOpenNewTrade(out complianceReason))
            {
                lastSeenEventId = sig.EventId;
                CommitEvent(sig.EventId, "tradeday_compliance_block");
                Audit("skip_tradeday_compliance", sig, complianceReason);
                return;
            }

            if (MaxSpreadTicks > 0 && CurrentSpreadTicks() > MaxSpreadTicks)
            {
                BlockRetry(sig.EventId, OrderFailureRetrySeconds, "spread");
                Audit("skip_spread_retry", sig, "spread_ticks=" + CurrentSpreadTicks().ToString("F2", CultureInfo.InvariantCulture) + " max=" + MaxSpreadTicks.ToString("F2", CultureInfo.InvariantCulture));
                return;
            }

            ExecuteSignal(sig, caller);
        }

        private void ExecuteSignal(BridgeSignal sig, string caller)
        {
            if (lifecycleFault)
            {
                BlockRetry(sig.EventId, OrderFailureRetrySeconds, "lifecycle_fault");
                Audit("skip_lifecycle_fault", sig, lifecycleFaultDetail);
                return;
            }

            var liveEntry = sig.Direction > 0 ? GetCurrentAsk() : GetCurrentBid();
            if (liveEntry <= 0)
            {
                BlockRetry(sig.EventId, OrderFailureRetrySeconds, "market_price_unavailable");
                Audit("skip_market_price", sig, "bid=" + GetCurrentBid() + " ask=" + GetCurrentAsk());
                return;
            }

            string geometryDetail;
            if (ShouldRebaseLevels(sig))
            {
                sig = RebaseLevels(sig, liveEntry, out geometryDetail);
                Audit("levels_rebased", sig, geometryDetail);
            }
            else if (!ValidateMappedPriceBasis(sig, liveEntry, out geometryDetail))
            {
                BlockRetry(sig.EventId, OrderFailureRetrySeconds, "mapped_price_basis");
                Audit("skip_mapped_price_basis", sig, geometryDetail);
                return;
            }

            sig.Sl = RoundPrice(sig.Sl);
            sig.Tp = RoundPrice(sig.Tp);
            if (sig.HalfTrigger > 0)
                sig.HalfTrigger = RoundPrice(sig.HalfTrigger);
            if (!ValidateGeometry(sig, liveEntry, out geometryDetail))
            {
                if (PermanentRejectGuard)
                    lastRejectedEventId = sig.EventId;
                Audit("skip_geometry", sig, geometryDetail);
                return;
            }

            if (CloseReverse && HasOppositeTrade(sig.Direction, sig.SourceTf))
            {
                if (BeginReverseClose(sig))
                {
                    deferredSignal = sig;
                    Audit("reverse_close_started", sig, "entry deferred until scoped reverse close fills");
                }
                else
                {
                    BlockRetry(sig.EventId, OrderFailureRetrySeconds, "reverse_close_failed");
                    Audit("skip_reverse_close_failed", sig, lastDetail);
                }
                return;
            }

            if (trades.Values.Any(t => t.Status == "ENTRY_PENDING" && t.EventId != sig.EventId))
            {
                BlockRetry(sig.EventId, 2, "another_entry_pending");
                AuditSignalThrottled("skip_entry_pending", sig, "another scoped market entry is not final yet", 10);
                return;
            }

            string ownershipDetail;
            if (!CanSafelyAddExposure(sig.Direction, out ownershipDetail))
            {
                BlockRetry(sig.EventId, OrderFailureRetrySeconds, "foreign_exposure_guard");
                Audit("skip_foreign_exposure", sig, ownershipDetail);
                return;
            }

            bool committedDuplicate;
            if (!ClaimEvent(sig.EventId, out committedDuplicate))
            {
                AuditSignalThrottled(committedDuplicate ? "skip_duplicate_global" : "event_claim_pending", sig, "claim unavailable", 10);
                if (committedDuplicate)
                    lastSeenEventId = sig.EventId;
                return;
            }

            string riskDetail;
            var quantity = ResolveContracts(sig, liveEntry, out riskDetail);
            if (quantity <= 0)
            {
                ReleaseEvent(sig.EventId);
                if (PermanentRejectGuard)
                    lastRejectedEventId = sig.EventId;
                Audit("skip_contracts", sig, riskDetail);
                return;
            }

            string tradeSlotDetail;
            if (!TradeDayReserveBridgeEntry(sig.EventId, out tradeSlotDetail))
            {
                ReleaseEvent(sig.EventId);
                lastRejectedEventId = sig.EventId;
                Audit("skip_daily_trade_cap", sig, tradeSlotDetail);
                return;
            }
            var trade = TradeState.FromSignal(sig, quantity);
            trade.EntryOrderName = OrderName("E", sig.EventId);
            trade.Status = "ENTRY_PENDING";
            trade.LastActionUtc = DateTime.UtcNow;
            trades[sig.EventId] = trade;
            SaveTradeState(trade);

            try
            {
                var action = sig.Direction > 0 ? OrderAction.Buy : OrderAction.SellShort;
                var order = Account.CreateOrder(Instrument, action, OrderType.Market, OrderEntry.Automated, TimeInForce.Day, quantity, 0, 0, string.Empty, trade.EntryOrderName, DateTime.MaxValue, null);
                Account.Submit(new[] { order });
                trade.EntryOrderId = order.OrderId ?? string.Empty;
                trade.LastActionUtc = DateTime.UtcNow;
                trades[sig.EventId] = trade;
                SaveTradeState(trade);
                Audit("entry_submitted", sig, "caller=" + caller + " qty=" + quantity + " order=" + trade.EntryOrderName + " " + riskDetail);
            }
            catch (Exception ex)
            {
                trades.Remove(sig.EventId);
                DeleteTradeState(sig.EventId);
                ReleaseEvent(sig.EventId);
                BlockRetry(sig.EventId, OrderFailureRetrySeconds, "submit_exception");
                Audit("entry_submit_exception", sig, ex.Message + " " + riskDetail);
            }
        }

        private void ProcessTradeStates()
        {
            ApplyPendingExitFills();
            foreach (var key in trades.Keys.ToArray())
            {
                TradeState trade;
                if (!trades.TryGetValue(key, out trade))
                    continue;
                try
                {
                    ProcessTradeState(trade);
                }
                catch (Exception ex)
                {
                    SetLifecycleFault("state_exception event=" + ShortEvent(trade.EventId) + " error=" + ex.Message);
                    AuditState("state_exception", trade, ex.ToString());
                }
            }
        }

        private void ProcessTradeState(TradeState trade)
        {
            if (trade.Status == "ENTRY_PENDING")
            {
                ProcessEntryPending(trade);
                return;
            }
            if (trade.Status == "PROTECTED" || trade.Status == "BE_PENDING")
            {
                ProcessProtectedTrade(trade);
                return;
            }
            if (trade.Status == "HALF_PENDING")
            {
                ProcessHalfPending(trade);
                return;
            }
            if (trade.Status == "EXIT_PENDING" || trade.Status == "EMERGENCY_PENDING")
            {
                ProcessExitPending(trade);
            }
        }

        private void ProcessEntryPending(TradeState trade)
        {
            var order = FindOrder(trade.EntryOrderName);
            if (order == null)
            {
                if ((DateTime.UtcNow - trade.LastActionUtc).TotalSeconds > OrderFailureRetrySeconds)
                    HandleEntryFailure(trade, "entry_order_missing", false);
                return;
            }

            var terminalWithFill = (order.OrderState == OrderState.Cancelled || order.OrderState == OrderState.Rejected) && order.Filled > 0;
            if ((order.OrderState == OrderState.PartFilled || order.OrderState == OrderState.Filled || terminalWithFill) && order.Filled > 0)
            {
                trade.Quantity = order.Filled;
                trade.FillEntry = order.AverageFillPrice > 0 ? order.AverageFillPrice : trade.BridgeEntry;
                trade.EntryOrderId = order.OrderId ?? trade.EntryOrderId;
                trade.LastActionUtc = DateTime.UtcNow;

                string riskDetail;
                if (!ValidatePostFillRisk(trade, out riskDetail))
                {
                    AuditState("post_fill_risk_violation", trade, riskDetail);
                    BeginEmergencyClose(trade, "post_fill_risk_guard");
                    return;
                }

                string protectionDetail;
                if (!EnsureExactProtection(ref trade, false, out protectionDetail))
                {
                    trades[trade.EventId] = trade;
                    SaveTradeState(trade);
                    AuditState("exact_protection_pending", trade, protectionDetail);
                    if (FailIfExactProtectionFails && IsProtectionPermanentlyFailed(trade))
                        BeginEmergencyClose(trade, "exact_protection_failed");
                    return;
                }

                var entryFinal = order.OrderState == OrderState.Filled || terminalWithFill;
                trade.Status = entryFinal ? "PROTECTED" : "ENTRY_PENDING";
                trade.LastActionUtc = DateTime.UtcNow;
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                if (entryFinal)
                {
                    TradeDayRegisterFilledEntry(trade.EventId);
                    CommitEvent(trade.EventId, terminalWithFill ? "entry_partial_terminal_protected" : "entry_filled_protected");
                    lastSeenEventId = trade.EventId;
                    AuditState(terminalWithFill ? "entry_partial_terminal_protected" : "entry_filled_protected", trade, protectionDetail + " " + riskDetail);
                }
                else
                {
                    AuditStateThrottled("entry_partial_fill_protected", trade, protectionDetail + " " + riskDetail, 10);
                }
                return;
            }

            if (order.OrderState == OrderState.Rejected || order.OrderState == OrderState.Cancelled)
            {
                var detail = OrderFailureText(order);
                HandleEntryFailure(trade, detail, IsMarketClosed(detail));
            }
        }

        private void HandleEntryFailure(TradeState trade, string detail, bool marketClosed)
        {
            if (NoMoneyRetryShrink && IsNoMoney(detail) && trade.RequestedQuantity > 1)
            {
                var newQuantity = trade.RequestedQuantity - 1;
                trade.RequestedQuantity = newQuantity;
                trade.Quantity = newQuantity;
                trade.EntryOrderName = OrderName("E", trade.EventId) + "R" + newQuantity.ToString(CultureInfo.InvariantCulture);
                trade.LastActionUtc = DateTime.UtcNow;
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                try
                {
                    var action = trade.Direction > 0 ? OrderAction.Buy : OrderAction.SellShort;
                    var retry = Account.CreateOrder(Instrument, action, OrderType.Market, OrderEntry.Automated, TimeInForce.Day, newQuantity, 0, 0, string.Empty, trade.EntryOrderName, DateTime.MaxValue, null);
                    Account.Submit(new[] { retry });
                    AuditState("entry_retry_smaller", trade, "qty=" + newQuantity + " original_error=" + detail);
                    return;
                }
                catch (Exception ex)
                {
                    detail += " retry_exception=" + ex.Message;
                }
            }

            trades.Remove(trade.EventId);
            DeleteTradeState(trade.EventId);
            ReleaseEvent(trade.EventId);
            BlockRetry(trade.EventId, marketClosed ? MarketClosedRetrySeconds : OrderFailureRetrySeconds, marketClosed ? "market_closed" : "order_failed");
            if (PermanentRejectGuard && IsPermanentFailure(detail) && !marketClosed)
                lastRejectedEventId = trade.EventId;
            AuditState("entry_failed", trade, "market_closed=" + (marketClosed ? 1 : 0) + " " + detail);
        }

        private void ProcessProtectedTrade(TradeState trade)
        {
            var stop = FindOrder(trade.StopOrderName);
            var target = FindOrder(trade.TargetOrderName);
            string fillDetail;
            if (ApplyProtectionFillDeltas(ref trade, stop, target, out fillDetail))
            {
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                AuditState("protection_partial_fill_accounted", trade, fillDetail);
            }

            if (trade.Quantity <= 0)
            {
                CancelIfWorking(IsFilled(target) ? stop : target);
                CompleteTrade(trade, IsFilled(target) ? "target_filled" : IsFilled(stop) ? "stop_filled" : "protection_filled_flat");
                return;
            }

            if (IsFilled(stop) || IsFilled(target))
            {
                AuditState("protection_filled_position_remains", trade, fillDetail);
                BeginEmergencyClose(trade, "protection_filled_position_remains");
                return;
            }

            if (!HasAccountExposureFor(trade))
            {
                CompleteTrade(trade, "account_position_flat_or_reduced");
                return;
            }

            string protectionDetail;
            var atBe = trade.HalfDone || trade.Status == "BE_PENDING";
            if (!EnsureExactProtection(ref trade, atBe, out protectionDetail))
            {
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                if (FailIfExactProtectionFails && IsProtectionPermanentlyFailed(trade))
                    BeginEmergencyClose(trade, "protection_repair_failed");
                else
                    AuditStateThrottled("protection_repair_pending", trade, protectionDetail, 10);
                return;
            }

            if (trade.Status == "BE_PENDING")
            {
                trade.HalfDone = true;
                trade.Status = "PROTECTED";
                trade.LastActionUtc = DateTime.UtcNow;
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                AuditState("halfbe_done", trade, protectionDetail);
            }

            if (ManageHalfCloseBe && !trade.HalfDone && !trade.HalfPartialClosed && trade.HalfTrigger > 0)
                TryStartHalfClose(trade);
        }

        private bool ApplyProtectionFillDeltas(ref TradeState trade, Order stop, Order target, out string detail)
        {
            var stopFilled = stop == null ? 0 : Math.Max(0, stop.Filled);
            var targetFilled = target == null ? 0 : Math.Max(0, target.Filled);
            var stopDelta = Math.Max(0, stopFilled - trade.StopFilledAccounted);
            var targetDelta = Math.Max(0, targetFilled - trade.TargetFilledAccounted);
            var delta = stopDelta + targetDelta;
            detail = "stop_filled=" + stopFilled + " target_filled=" + targetFilled + " accounted_stop=" + trade.StopFilledAccounted + " accounted_target=" + trade.TargetFilledAccounted;
            if (delta <= 0)
                return false;

            trade.StopFilledAccounted = Math.Max(trade.StopFilledAccounted, stopFilled);
            trade.TargetFilledAccounted = Math.Max(trade.TargetFilledAccounted, targetFilled);
            trade.Quantity = Math.Max(0, trade.Quantity - delta);
            trade.LastActionUtc = DateTime.UtcNow;
            detail += " delta=" + delta + " remaining_qty=" + trade.Quantity;
            return true;
        }

        private void TryStartHalfClose(TradeState trade)
        {
            if (DateTime.UtcNow < trade.NextRetryUtc)
                return;
            var triggerPrice = trade.Direction > 0 ? GetCurrentBid() : GetCurrentAsk();
            var reached = trade.Direction > 0 ? triggerPrice >= trade.HalfTrigger : triggerPrice <= trade.HalfTrigger;
            if (!reached)
                return;

            var closeQty = (int)Math.Floor(trade.Quantity * Math.Max(0.01, Math.Min(0.99, HalfCloseFraction)));
            if (closeQty <= 0 || closeQty >= trade.Quantity)
            {
                trade.NextRetryUtc = DateTime.UtcNow.AddSeconds(HalfBeVolumeRetrySeconds);
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                AuditStateThrottled("halfbe_blocked_contracts", trade, "qty=" + trade.Quantity + " fraction=" + HalfCloseFraction.ToString("F2", CultureInfo.InvariantCulture), HalfBeVolumeRetrySeconds);
                return;
            }

            trade.HalfCloseQuantity = closeQty;
            trade.HalfOrderName = OrderName("H", trade.EventId);
            trade.Status = "HALF_PENDING";
            trade.LastActionUtc = DateTime.UtcNow;
            trades[trade.EventId] = trade;
            SaveTradeState(trade);
            try
            {
                var action = trade.Direction > 0 ? OrderAction.Sell : OrderAction.BuyToCover;
                var order = Account.CreateOrder(Instrument, action, OrderType.Market, OrderEntry.Automated, TimeInForce.Day, closeQty, 0, 0, string.Empty, trade.HalfOrderName, DateTime.MaxValue, null);
                Account.Submit(new[] { order });
                AuditState("halfbe_partial_submitted", trade, "close_qty=" + closeQty + " trigger=" + triggerPrice);
            }
            catch (Exception ex)
            {
                trade.Status = "PROTECTED";
                trade.NextRetryUtc = DateTime.UtcNow.AddSeconds(HalfBeRetrySeconds);
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                AuditState("halfbe_partial_submit_failed", trade, ex.Message);
            }
        }

        private void ProcessHalfPending(TradeState trade)
        {
            var order = FindOrder(trade.HalfOrderName);
            if (order == null)
            {
                if ((DateTime.UtcNow - trade.LastActionUtc).TotalSeconds > HalfBeRetrySeconds)
                {
                    trade.Status = "PROTECTED";
                    trade.NextRetryUtc = DateTime.UtcNow.AddSeconds(HalfBeRetrySeconds);
                    trades[trade.EventId] = trade;
                    SaveTradeState(trade);
                }
                return;
            }

            var filled = Math.Max(0, order.Filled);
            var fillDelta = Math.Max(0, filled - trade.HalfFilledAccounted);
            if (fillDelta > 0)
            {
                trade.HalfFilledAccounted = filled;
                trade.Quantity = Math.Max(0, trade.Quantity - fillDelta);
                trade.HalfPartialClosed = true;
                trade.LastActionUtc = DateTime.UtcNow;
                trades[trade.EventId] = trade;
                SaveTradeState(trade);

                if (trade.Quantity <= 0)
                {
                    CompleteTrade(trade, "half_close_closed_position");
                    return;
                }

                if (order.OrderState == OrderState.PartFilled && IsWorking(order))
                {
                    string resizeDetail;
                    var resized = EnsureExactProtection(ref trade, false, out resizeDetail);
                    trades[trade.EventId] = trade;
                    SaveTradeState(trade);
                    AuditStateThrottled("halfbe_partial_fill_waiting", trade, "filled=" + filled + " remaining_qty=" + trade.Quantity + " " + resizeDetail, 5);
                    if (!resized && FailIfExactProtectionFails && IsProtectionPermanentlyFailed(trade))
                        BeginEmergencyClose(trade, "half_partial_protection_failed");
                    return;
                }
            }

            var terminalWithFill = (order.OrderState == OrderState.Filled
                || order.OrderState == OrderState.Cancelled
                || order.OrderState == OrderState.Rejected) && trade.HalfFilledAccounted > 0;
            if (terminalWithFill)
            {
                trade.Status = "BE_PENDING";
                trade.LastActionUtc = DateTime.UtcNow;
                trades[trade.EventId] = trade;
                SaveTradeState(trade);

                string protectionDetail;
                var exact = EnsureExactProtection(ref trade, true, out protectionDetail);
                if (exact)
                {
                    trade.HalfDone = true;
                    trade.Status = "PROTECTED";
                }
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                AuditState(exact ? "halfbe_done" : "halfbe_partial_filled_be_pending", trade, "closed_qty=" + trade.HalfFilledAccounted + " remaining_qty=" + trade.Quantity + " " + protectionDetail);
                return;
            }

            if ((order.OrderState == OrderState.Rejected || order.OrderState == OrderState.Cancelled) && trade.HalfFilledAccounted <= 0)
            {
                trade.Status = "PROTECTED";
                trade.NextRetryUtc = DateTime.UtcNow.AddSeconds(HalfBeRetrySeconds);
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                AuditState("halfbe_partial_failed", trade, OrderFailureText(order));
            }
        }

        private bool EnsureExactProtection(ref TradeState trade, bool atBreakEven, out string detail)
        {
            detail = string.Empty;
            if (trade.Quantity <= 0 || trade.FillEntry <= 0)
            {
                detail = "invalid_trade_state qty=" + trade.Quantity + " fill=" + trade.FillEntry;
                return false;
            }

            var expectedStop = RoundPrice(atBreakEven ? trade.FillEntry : trade.StopLoss);
            var expectedTarget = RoundPrice(trade.TakeProfit);
            var market = trade.Direction > 0 ? GetCurrentBid() : GetCurrentAsk();
            if (!ProtectionGeometryValid(trade.Direction, market, expectedStop, expectedTarget, out detail))
            {
                trade.ProtectionFailures++;
                return false;
            }

            var stop = FindOrder(trade.StopOrderName);
            var target = FindOrder(trade.TargetOrderName);
            if (IsFilled(stop) || IsFilled(target))
            {
                detail = "protection_already_filled";
                return true;
            }

            if (IsRejected(stop) || IsRejected(target))
            {
                trade.ProtectionFailures++;
                detail = "protection_rejected stop=" + OrderFailureText(stop) + " target=" + OrderFailureText(target);
                return false;
            }

            if (stop == null || target == null || IsTerminalWithoutFill(stop) || IsTerminalWithoutFill(target))
            {
                var stopStillWorking = stop != null && IsWorking(stop);
                var targetStillWorking = target != null && IsWorking(target);
                CancelIfWorking(stop);
                CancelIfWorking(target);
                if (((stop == null || IsTerminalWithoutFill(stop)) && targetStillWorking)
                    || ((target == null || IsTerminalWithoutFill(target)) && stopStillWorking))
                {
                    detail = "waiting_orphan_protection_cancel";
                    return false;
                }
                var oco = OrderName("O", trade.EventId) + DateTime.UtcNow.Ticks.ToString("X").Substring(8);
                trade.Oco = oco;
                trade.StopOrderName = OrderName("S", trade.EventId);
                trade.TargetOrderName = OrderName("T", trade.EventId);
                try
                {
                    var exitAction = trade.Direction > 0 ? OrderAction.Sell : OrderAction.BuyToCover;
                    var stopOrder = Account.CreateOrder(Instrument, exitAction, OrderType.StopMarket, OrderEntry.Automated, TimeInForce.Gtc, trade.Quantity, 0, expectedStop, oco, trade.StopOrderName, DateTime.MaxValue, null);
                    var targetOrder = Account.CreateOrder(Instrument, exitAction, OrderType.Limit, OrderEntry.Automated, TimeInForce.Gtc, trade.Quantity, expectedTarget, 0, oco, trade.TargetOrderName, DateTime.MaxValue, null);
                    Account.Submit(new[] { stopOrder, targetOrder });
                    trade.StopOrderId = stopOrder.OrderId ?? string.Empty;
                    trade.TargetOrderId = targetOrder.OrderId ?? string.Empty;
                    trade.ExpectedStop = expectedStop;
                    trade.ExpectedTarget = expectedTarget;
                    trade.LastActionUtc = DateTime.UtcNow;
                    detail = "protection_submitted sl=" + expectedStop + " tp=" + expectedTarget + " qty=" + trade.Quantity;
                    return IsAcceptedOrWorking(stopOrder) && IsAcceptedOrWorking(targetOrder);
                }
                catch (Exception ex)
                {
                    trade.ProtectionFailures++;
                    detail = "protection_submit_exception=" + ex.Message;
                    return false;
                }
            }

            var stopExact = Math.Max(0, stop.Quantity - stop.Filled) == trade.Quantity && PriceEqual(stop.StopPrice, expectedStop) && IsAcceptedOrWorking(stop);
            var targetExact = Math.Max(0, target.Quantity - target.Filled) == trade.Quantity && PriceEqual(target.LimitPrice, expectedTarget) && IsAcceptedOrWorking(target);
            if (stopExact && targetExact)
            {
                trade.ExpectedStop = expectedStop;
                trade.ExpectedTarget = expectedTarget;
                detail = "protection_exact sl=" + expectedStop + " tp=" + expectedTarget + " qty=" + trade.Quantity;
                return true;
            }

            if ((DateTime.UtcNow - trade.LastProtectionChangeUtc).TotalSeconds < Math.Max(1, HalfBeRetrySeconds))
            {
                detail = "protection_change_pending";
                return false;
            }

            try
            {
                stop.QuantityChanged = stop.Filled + trade.Quantity;
                stop.StopPriceChanged = expectedStop;
                target.QuantityChanged = target.Filled + trade.Quantity;
                target.LimitPriceChanged = expectedTarget;
                Account.Change(new[] { stop, target });
                trade.LastProtectionChangeUtc = DateTime.UtcNow;
                trade.ExpectedStop = expectedStop;
                trade.ExpectedTarget = expectedTarget;
                detail = "protection_change_submitted sl=" + expectedStop + " tp=" + expectedTarget + " qty=" + trade.Quantity;
            }
            catch (Exception ex)
            {
                trade.ProtectionFailures++;
                detail = "protection_change_exception=" + ex.Message;
            }
            return false;
        }

        private void BeginEmergencyClose(TradeState trade, string reason)
        {
            CancelTradeProtection(trade);
            if (trade.Status == "EMERGENCY_PENDING" && (DateTime.UtcNow - trade.LastActionUtc).TotalSeconds < EmergencyRetrySeconds)
                return;
            trade.Status = "EMERGENCY_PENDING";
            trade.ExitOrderName = OrderName("X", trade.EventId) + DateTime.UtcNow.Second.ToString("D2");
            trade.ExitFilledAccounted = 0;
            trade.NextRetryUtc = DateTime.MinValue;
            trade.LastActionUtc = DateTime.UtcNow;
            trades[trade.EventId] = trade;
            SaveTradeState(trade);
            try
            {
                var qty = Math.Min(trade.Quantity, AccountPositionQuantity());
                if (qty <= 0)
                {
                    CompleteTrade(trade, "emergency_no_position");
                    return;
                }
                var action = trade.Direction > 0 ? OrderAction.Sell : OrderAction.BuyToCover;
                var close = Account.CreateOrder(Instrument, action, OrderType.Market, OrderEntry.Automated, TimeInForce.Day, qty, 0, 0, string.Empty, trade.ExitOrderName, DateTime.MaxValue, null);
                Account.Submit(new[] { close });
                AuditState("emergency_close_submitted", trade, "reason=" + reason + " qty=" + qty);
            }
            catch (Exception ex)
            {
                AuditState("emergency_close_submit_failed", trade, "reason=" + reason + " error=" + ex.Message);
            }
        }

        private void ProcessExitPending(TradeState trade)
        {
            if (trade.Quantity <= 0)
            {
                CompleteTrade(trade, "exit_quantity_fully_accounted");
                return;
            }

            var order = FindOrder(trade.ExitOrderName);
            if (order != null && order.OrderState == OrderState.Filled)
            {
                CompleteTrade(trade, trade.Status == "EMERGENCY_PENDING" ? "emergency_close_filled" : "reverse_close_filled");
                return;
            }
            if (!HasAccountExposureFor(trade))
            {
                CompleteTrade(trade, "exit_position_already_flat");
                return;
            }
            if (order != null && order.OrderState != OrderState.Rejected && order.OrderState != OrderState.Cancelled)
                return;

            var failure = OrderFailureText(order);
            var retrySeconds = IsMarketClosed(failure) ? MarketClosedRetrySeconds : EmergencyRetrySeconds;
            if (trade.NextRetryUtc == DateTime.MinValue)
            {
                trade.NextRetryUtc = DateTime.UtcNow.AddSeconds(retrySeconds);
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                AuditStateThrottled("exit_retry_scheduled", trade, failure + " retry_sec=" + retrySeconds, retrySeconds);
                return;
            }
            if (DateTime.UtcNow < trade.NextRetryUtc)
                return;

            RetryExitGroup(trade, failure);
        }

        private void ApplyPendingExitFills()
        {
            var groups = trades.Values
                .Where(t => (t.Status == "EXIT_PENDING" || t.Status == "EMERGENCY_PENDING") && !string.IsNullOrWhiteSpace(t.ExitOrderName))
                .GroupBy(t => t.ExitOrderName, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            foreach (var group in groups)
            {
                var order = FindOrder(group.Key);
                if (order == null || order.Filled <= 0)
                    continue;
                var states = group.OrderBy(t => t.SignalTime).ThenBy(t => t.EventId, StringComparer.Ordinal).ToArray();
                var accounted = states.Sum(t => t.ExitFilledAccounted);
                var delta = Math.Max(0, order.Filled - accounted);
                if (delta <= 0)
                    continue;

                var remainingDelta = delta;
                foreach (var state in states)
                {
                    if (remainingDelta <= 0)
                        break;
                    var trade = state;
                    var applied = Math.Min(trade.Quantity, remainingDelta);
                    trade.Quantity -= applied;
                    trade.ExitFilledAccounted += applied;
                    trade.LastActionUtc = DateTime.UtcNow;
                    trades[trade.EventId] = trade;
                    SaveTradeState(trade);
                    remainingDelta -= applied;
                    AuditState("exit_partial_fill_accounted", trade, "order=" + group.Key + " cumulative_filled=" + order.Filled + " applied=" + applied + " remaining_qty=" + trade.Quantity);
                }
                if (remainingDelta > 0)
                    SetLifecycleFault("exit fill exceeds persisted group quantity order=" + group.Key + " excess=" + remainingDelta);
            }
        }

        private void RetryExitGroup(TradeState seed, string failure)
        {
            var group = trades.Values
                .Where(t => (t.Status == "EXIT_PENDING" || t.Status == "EMERGENCY_PENDING") && SameText(t.ExitOrderName, seed.ExitOrderName))
                .OrderBy(t => t.EventId, StringComparer.Ordinal)
                .ToArray();
            if (group.Length == 0 || !SameText(group[0].EventId, seed.EventId))
                return;

            var quantity = Math.Min(group.Sum(t => t.Quantity), AccountPositionQuantity());
            if (quantity <= 0)
            {
                foreach (var state in group)
                    CompleteTrade(state, "exit_retry_no_position");
                return;
            }

            var name = OrderName("X", seed.EventId) + DateTime.UtcNow.Ticks.ToString("X").Substring(10);
            foreach (var state in group)
            {
                var trade = state;
                CancelTradeProtection(trade);
                trade.Status = "EMERGENCY_PENDING";
                trade.ExitOrderName = name;
                trade.ExitFilledAccounted = 0;
                trade.NextRetryUtc = DateTime.UtcNow.AddSeconds(EmergencyRetrySeconds);
                trade.LastActionUtc = DateTime.UtcNow;
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
            }

            try
            {
                var action = group[0].Direction > 0 ? OrderAction.Sell : OrderAction.BuyToCover;
                var close = Account.CreateOrder(Instrument, action, OrderType.Market, OrderEntry.Automated, TimeInForce.Day, quantity, 0, 0, string.Empty, name, DateTime.MaxValue, null);
                Account.Submit(new[] { close });
                AuditState("exit_group_retry_submitted", group[0], "qty=" + quantity + " states=" + group.Length + " previous=" + failure);
            }
            catch (Exception ex)
            {
                AuditState("exit_group_retry_failed", group[0], "qty=" + quantity + " previous=" + failure + " error=" + ex.Message);
            }
        }

        private bool BeginReverseClose(BridgeSignal incoming)
        {
            var scoped = ScopedTrades(incoming.SourceTf).Where(t => t.Direction != incoming.Direction && t.Status != "EXIT_PENDING" && t.Status != "EMERGENCY_PENDING").ToArray();
            if (scoped.Length == 0)
                return true;
            if (!CanSafelyManageAccountPosition(out var ownershipDetail))
            {
                SetAction("reverse_foreign_exposure", ownershipDetail);
                return false;
            }

            var qty = Math.Min(scoped.Sum(t => t.Quantity), AccountPositionQuantity());
            if (qty <= 0)
                return false;
            var name = OrderName("R", incoming.EventId);
            foreach (var state in scoped)
            {
                var trade = state;
                CancelTradeProtection(trade);
                trade.Status = "EXIT_PENDING";
                trade.ExitOrderName = name;
                trade.ExitFilledAccounted = 0;
                trade.NextRetryUtc = DateTime.MinValue;
                trade.LastActionUtc = DateTime.UtcNow;
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
            }
            try
            {
                var direction = scoped[0].Direction;
                var action = direction > 0 ? OrderAction.Sell : OrderAction.BuyToCover;
                var close = Account.CreateOrder(Instrument, action, OrderType.Market, OrderEntry.Automated, TimeInForce.Day, qty, 0, 0, string.Empty, name, DateTime.MaxValue, null);
                Account.Submit(new[] { close });
                return true;
            }
            catch (Exception ex)
            {
                SetAction("reverse_submit_failed", ex.Message);
                foreach (var state in scoped)
                {
                    var trade = state;
                    trade.Status = "PROTECTED";
                    trades[trade.EventId] = trade;
                    SaveTradeState(trade);
                }
                return false;
            }
        }

        private void ProcessCloseOnly(BridgeSignal sig)
        {
            var sameDirection = ScopedTrades(sig.SourceTf).Where(t => t.Direction == sig.Direction).ToArray();
            if (sameDirection.Length == 0)
            {
                lastSeenEventId = sig.EventId;
                CommitEvent(sig.EventId, "close_only_no_position");
                Audit("close_only_no_position", sig, "no scoped same-direction trade");
                return;
            }
            if (BeginGroupedClose(sameDirection, sig.EventId, "C"))
            {
                lastSeenEventId = sig.EventId;
                CommitEvent(sig.EventId, "close_only_submitted");
                Audit("close_only_submitted", sig, "states=" + sameDirection.Length);
            }
            else
            {
                BlockRetry(sig.EventId, OrderFailureRetrySeconds, "close_only_failed");
                Audit("close_only_failed", sig, lastDetail);
            }
        }

        private bool BeginGroupedClose(TradeState[] scoped, string eventId, string role)
        {
            if (scoped.Length == 0)
                return true;
            string ownershipDetail;
            if (!CanSafelyManageAccountPosition(out ownershipDetail))
            {
                SetAction("group_close_foreign_exposure", ownershipDetail);
                return false;
            }
            var qty = Math.Min(scoped.Sum(t => t.Quantity), AccountPositionQuantity());
            if (qty <= 0)
                return false;
            var name = OrderName(role, eventId);
            foreach (var state in scoped)
            {
                var trade = state;
                CancelTradeProtection(trade);
                trade.Status = "EXIT_PENDING";
                trade.ExitOrderName = name;
                trade.ExitFilledAccounted = 0;
                trade.NextRetryUtc = DateTime.MinValue;
                trade.LastActionUtc = DateTime.UtcNow;
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
            }
            try
            {
                var action = scoped[0].Direction > 0 ? OrderAction.Sell : OrderAction.BuyToCover;
                var close = Account.CreateOrder(Instrument, action, OrderType.Market, OrderEntry.Automated, TimeInForce.Day, qty, 0, 0, string.Empty, name, DateTime.MaxValue, null);
                Account.Submit(new[] { close });
                return true;
            }
            catch (Exception ex)
            {
                SetAction("group_close_submit_failed", ex.Message);
                return false;
            }
        }

        private void CompleteTrade(TradeState trade, string reason)
        {
            CancelTradeProtection(trade);
            CancelIfWorking(FindOrder(trade.EntryOrderName));
            CancelIfWorking(FindOrder(trade.HalfOrderName));
            CancelIfWorking(FindOrder(trade.ExitOrderName));
            trades.Remove(trade.EventId);
            DeleteTradeState(trade.EventId);
            CommitEvent(trade.EventId, reason);
            AuditState("trade_completed", trade, "reason=" + reason);
        }

        private void CancelTradeProtection(TradeState trade)
        {
            CancelIfWorking(FindOrder(trade.StopOrderName));
            CancelIfWorking(FindOrder(trade.TargetOrderName));
        }

        private void CancelIfWorking(Order order)
        {
            if (order == null || !IsWorking(order))
                return;
            try { Account.Cancel(new[] { order }); }
            catch (Exception ex) { AuditRaw("cancel_failed", "order=" + order.Name + " error=" + ex.Message); }
        }

        private int ResolveContracts(BridgeSignal sig, double liveEntry, out string detail)
        {
            if (!UseRiskContracts)
            {
                var manual = MaxContracts > 0 ? Math.Min(ManualContracts, MaxContracts) : ManualContracts;
                string manualComplianceDetail;
                manual = TradeDayApplyContractCap(Math.Max(1, manual), out manualComplianceDetail);
                detail = "manual_contracts=" + manual + " " + manualComplianceDetail;
                return Math.Max(0, manual);
            }

            var riskPct = UseBridgeRiskPct && sig.RiskPct > 0 ? sig.RiskPct : LocalRiskPct;
            var capital = RiskCapital();
            var riskBudget = capital * Math.Max(0, riskPct) / 100.0;
            var pointValue = Instrument.MasterInstrument.PointValue;
            var riskPerContract = Math.Abs(liveEntry - sig.Sl) * pointValue;
            if (!IsFinitePositive(capital) || !IsFinitePositive(riskBudget) || !IsFinitePositive(riskPerContract))
            {
                detail = "risk_unavailable capital=" + capital + " risk_pct=" + riskPct + " entry=" + liveEntry + " sl=" + sig.Sl + " point_value=" + pointValue;
                return FailClosedOnRiskError ? 0 : Math.Max(1, ManualContracts);
            }

            var contracts = (int)Math.Floor(riskBudget / riskPerContract);
            if (contracts < 1)
            {
                detail = "one_contract_exceeds_risk budget=" + riskBudget.ToString("F2", CultureInfo.InvariantCulture) + " per_contract=" + riskPerContract.ToString("F2", CultureInfo.InvariantCulture);
                return BlockIfMinContractExceedsRisk ? 0 : 1;
            }
            if (MaxContracts > 0)
                contracts = Math.Min(contracts, MaxContracts);
            if (Account.MaxOrderSize > 0)
                contracts = Math.Min(contracts, Account.MaxOrderSize);
            if (Account.MaxPositionSize > 0)
            {
                var remainingPositionCapacity = Math.Max(0, Account.MaxPositionSize - AccountPositionQuantity());
                contracts = Math.Min(contracts, remainingPositionCapacity);
            }

            string marginDetail;
            contracts = ApplyMarginGuard(contracts, capital, out marginDetail);
            string complianceDetail;
            contracts = TradeDayApplyContractCap(contracts, out complianceDetail);
            detail = "risk_contracts pct=" + riskPct.ToString("F4", CultureInfo.InvariantCulture)
                   + " pct_source=" + (UseBridgeRiskPct && sig.RiskPct > 0 ? "bridge" : "local")
                   + " capital_source=" + (UseCashValueForRisk ? "ninja_cash" : "ninja_net_liq")
                   + " capital=" + capital.ToString("F2", CultureInfo.InvariantCulture)
                   + " budget=" + riskBudget.ToString("F2", CultureInfo.InvariantCulture)
                   + " risk_per_contract=" + riskPerContract.ToString("F2", CultureInfo.InvariantCulture)
                   + " contracts=" + contracts + " " + marginDetail + " " + complianceDetail;
            return contracts;
        }

        private int ApplyMarginGuard(int contracts, double capital, out string detail)
        {
            detail = "margin_guard_off";
            if (!UseMarginGuard || MaxMarginUsagePct <= 0)
                return contracts;
            if (EstimatedMarginPerContract <= 0)
            {
                detail = "margin_estimate_missing";
                return FailIfMarginEstimateMissing ? 0 : contracts;
            }
            var allowed = capital * MaxMarginUsagePct / 100.0;
            var current = SafeAccountValue(AccountItem.PositionMargin);
            if (!IsFiniteNonNegative(current))
                current = 0;
            var available = Math.Max(0, allowed - current);
            var byMargin = (int)Math.Floor(available / EstimatedMarginPerContract);
            var result = Math.Min(contracts, byMargin);
            detail = "margin_guard requested=" + contracts + " result=" + result + " current_margin=" + current.ToString("F2", CultureInfo.InvariantCulture) + " allowed=" + allowed.ToString("F2", CultureInfo.InvariantCulture) + " per_contract=" + EstimatedMarginPerContract.ToString("F2", CultureInfo.InvariantCulture);
            return Math.Max(0, result);
        }

        private bool ValidatePostFillRisk(TradeState trade, out string detail)
        {
            detail = "post_fill_guard_off";
            if (!PostFillRiskGuard || !UseRiskContracts)
                return true;
            var riskPct = UseBridgeRiskPct && trade.RiskPct > 0 ? trade.RiskPct : LocalRiskPct;
            var capital = RiskCapital();
            var allowed = capital * Math.Max(0, riskPct) / 100.0;
            var actual = Math.Abs(trade.FillEntry - trade.StopLoss) * Instrument.MasterInstrument.PointValue * trade.Quantity;
            var tolerated = allowed * (1.0 + Math.Max(0, MaxRiskOvershootPct) / 100.0);
            detail = "fill=" + trade.FillEntry + " sl=" + trade.StopLoss + " qty=" + trade.Quantity + " actual_risk=" + actual.ToString("F2", CultureInfo.InvariantCulture) + " allowed=" + allowed.ToString("F2", CultureInfo.InvariantCulture) + " tolerated=" + tolerated.ToString("F2", CultureInfo.InvariantCulture);
            if (!IsFinitePositive(actual) || !IsFinitePositive(allowed))
                return !FailClosedOnRiskError;
            return actual <= tolerated;
        }

        private double RiskCapital()
        {
            var item = UseCashValueForRisk ? AccountItem.CashValue : AccountItem.NetLiquidation;
            var value = SafeAccountValue(item);
            if (!IsFinitePositive(value) && item != AccountItem.CashValue)
                value = SafeAccountValue(AccountItem.CashValue);
            return value;
        }

        private double SafeAccountValue(AccountItem item)
        {
            try { return Account.Get(item, Account.Denomination); }
            catch { return double.NaN; }
        }

        private bool CanSafelyAddExposure(int direction, out string detail)
        {
            var position = AccountPosition();
            var expectedQty = trades.Values.Where(IsExposureState).Sum(t => t.Quantity);
            var expectedDirection = trades.Values.Where(IsExposureState).Select(t => t.Direction).Distinct().ToArray();
            if (position == null || position.MarketPosition == MarketPosition.Flat)
            {
                if (expectedQty > 0)
                {
                    detail = "state_exposure_without_account_position expected_qty=" + expectedQty;
                    return false;
                }
                if (HasForeignWorkingOrders())
                {
                    detail = "foreign_working_orders_on_chart_instrument";
                    return false;
                }
                detail = "flat_clean";
                return true;
            }

            var accountDirection = position.MarketPosition == MarketPosition.Long ? 1 : -1;
            if (expectedQty == 0)
            {
                detail = "foreign_account_position dir=" + accountDirection + " qty=" + position.Quantity;
                return false;
            }
            if (expectedDirection.Length != 1 || expectedDirection[0] != accountDirection || expectedQty != position.Quantity)
            {
                detail = "account_state_mismatch account_dir=" + accountDirection + " account_qty=" + position.Quantity + " expected_dir=" + string.Join("/", expectedDirection) + " expected_qty=" + expectedQty;
                return false;
            }
            if (accountDirection != direction)
            {
                detail = "opposite_account_position_not_closed";
                return false;
            }
            if (HasForeignWorkingOrders())
            {
                detail = "foreign_working_orders_on_chart_instrument";
                return false;
            }
            detail = "owned_position_match";
            return true;
        }

        private bool CanSafelyManageAccountPosition(out string detail)
        {
            var position = AccountPosition();
            var expected = trades.Values.Where(IsExposureState).Sum(t => t.Quantity);
            if (position == null || position.MarketPosition == MarketPosition.Flat)
            {
                detail = "account_flat";
                return expected == 0;
            }
            var dirs = trades.Values.Where(IsExposureState).Select(t => t.Direction).Distinct().ToArray();
            var actualDir = position.MarketPosition == MarketPosition.Long ? 1 : -1;
            var ok = dirs.Length == 1 && dirs[0] == actualDir && expected == position.Quantity && !HasForeignWorkingOrders();
            detail = "actual_dir=" + actualDir + " actual_qty=" + position.Quantity + " expected_dirs=" + string.Join("/", dirs) + " expected_qty=" + expected + " foreign_orders=" + (HasForeignWorkingOrders() ? 1 : 0);
            return ok;
        }

        private bool HasForeignWorkingOrders()
        {
            return Account.Orders.Any(o => SameInstrument(o.Instrument) && IsWorking(o) && !IsOurOrder(o));
        }

        private bool IsOurOrder(Order order)
        {
            return order != null && !string.IsNullOrWhiteSpace(order.Name) && order.Name.StartsWith(orderScopePrefix, StringComparison.Ordinal);
        }

        private void ReconcileRestartState(string reason)
        {
            foreach (var key in trades.Keys.ToArray())
            {
                var trade = trades[key];
                if (trade.Status != "ENTRY_PENDING")
                    continue;
                var entryOrder = FindOrder(trade.EntryOrderName);
                if (entryOrder != null && entryOrder.Filled > 0)
                {
                    trade.Quantity = entryOrder.Filled;
                    trade.FillEntry = entryOrder.AverageFillPrice > 0 ? entryOrder.AverageFillPrice : trade.BridgeEntry;
                    trades[key] = trade;
                    SaveTradeState(trade);
                }
            }

            HydrateRestartFills();
            ApplyPendingExitFills();

            var position = AccountPosition();
            if (trades.Count == 0)
            {
                if (position != null && position.MarketPosition != MarketPosition.Flat)
                    SetLifecycleFault("orphan account position on " + Instrument.FullName + "; no persisted listener state. Manual reconciliation required.");
                return;
            }

            if (position == null || position.MarketPosition == MarketPosition.Flat)
            {
                foreach (var trade in trades.Values.ToArray())
                {
                    var pendingOrder = trade.Status == "ENTRY_PENDING" ? FindOrder(trade.EntryOrderName) : null;
                    if (trade.Status == "ENTRY_PENDING" && pendingOrder != null && IsWorking(pendingOrder))
                    {
                        AuditState("restart_pending_entry_adopted", trade, "reason=" + reason + " order_state=" + pendingOrder.OrderState);
                        continue;
                    }
                    CompleteTrade(trade, "restart_account_flat");
                }
                return;
            }

            var actualDir = position.MarketPosition == MarketPosition.Long ? 1 : -1;
            var expectedDir = trades.Values.Where(IsExposureState).Select(t => t.Direction).Distinct().ToArray();
            var expectedQty = trades.Values.Where(IsExposureState).Sum(t => t.Quantity);
            if (expectedDir.Length != 1 || expectedDir[0] != actualDir || expectedQty != position.Quantity)
            {
                SetLifecycleFault("restart account/state mismatch actual_dir=" + actualDir + " actual_qty=" + position.Quantity + " expected_dirs=" + string.Join("/", expectedDir) + " expected_qty=" + expectedQty);
                return;
            }

            foreach (var key in trades.Keys.ToArray())
            {
                var trade = trades[key];
                if (trade.HalfPartialClosed && !trade.HalfDone)
                    trade.Status = "BE_PENDING";
                else if (trade.Status != "ENTRY_PENDING" && trade.Status != "EXIT_PENDING" && trade.Status != "EMERGENCY_PENDING")
                    trade.Status = "PROTECTED";
                trades[key] = trade;
                SaveTradeState(trade);
                AuditState("restart_state_adopted", trade, "reason=" + reason + " status=" + trade.Status);
            }
        }

        private void HydrateRestartFills()
        {
            foreach (var key in trades.Keys.ToArray())
            {
                TradeState trade;
                if (!trades.TryGetValue(key, out trade))
                    continue;

                string protectionFillDetail;
                var protectionChanged = ApplyProtectionFillDeltas(ref trade, FindOrder(trade.StopOrderName), FindOrder(trade.TargetOrderName), out protectionFillDetail);

                var halfOrder = FindOrder(trade.HalfOrderName);
                var halfChanged = false;
                if (halfOrder != null && halfOrder.Filled > trade.HalfFilledAccounted)
                {
                    var delta = halfOrder.Filled - trade.HalfFilledAccounted;
                    trade.HalfFilledAccounted = halfOrder.Filled;
                    trade.Quantity = Math.Max(0, trade.Quantity - delta);
                    trade.HalfPartialClosed = true;
                    trade.LastActionUtc = DateTime.UtcNow;
                    halfChanged = true;
                    if (halfOrder.OrderState == OrderState.Filled || halfOrder.OrderState == OrderState.Cancelled || halfOrder.OrderState == OrderState.Rejected)
                        trade.Status = trade.Quantity > 0 ? "BE_PENDING" : "PROTECTED";
                }

                if (!protectionChanged && !halfChanged)
                    continue;
                trades[trade.EventId] = trade;
                SaveTradeState(trade);
                AuditState("restart_fills_hydrated", trade, protectionFillDetail + " half_filled=" + trade.HalfFilledAccounted + " remaining_qty=" + trade.Quantity);
            }
        }

        private void SetLifecycleFault(string detail)
        {
            lifecycleFault = true;
            lifecycleFaultDetail = detail;
            AuditRaw("lifecycle_fault", detail);
        }

        private bool TryReadSignal(out BridgeSignal sig, out string detail)
        {
            sig = new BridgeSignal();
            detail = string.Empty;
            var path = ResolveBridgeReadPath();
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            {
                detail = "file_not_found " + path;
                return false;
            }

            string text;
            try
            {
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var sr = new StreamReader(fs, Encoding.UTF8, true))
                    text = sr.ReadToEnd();
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
            if (SameText(fields[0], "version"))
            {
                offset = 17;
                if (fields.Count > 17 && SameText(fields[17], "risk_pct"))
                    offset = 18;
            }
            if (fields.Count < offset + 17)
            {
                detail = "not_enough_data_fields count=" + fields.Count + " offset=" + offset;
                return false;
            }

            sig.Version = fields[offset];
            sig.WrittenGmt = ParseDate(fields[offset + 1]);
            sig.SourceLogin = fields[offset + 2];
            sig.SourceSymbol = fields[offset + 3];
            sig.SourceTf = fields[offset + 4];
            sig.EventId = fields[offset + 5];
            sig.Source = fields[offset + 6];
            sig.Direction = SameText(fields[offset + 7], "BUY") ? 1 : SameText(fields[offset + 7], "SELL") ? -1 : 0;
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
            sig.Valid = !string.IsNullOrWhiteSpace(sig.EventId) && sig.Direction != 0 && sig.WrittenGmt != DateTime.MinValue;
            detail = "read_ok file=" + Path.GetFileName(path) + " fields=" + fields.Count + " offset=" + offset + " event=" + ShortEvent(sig.EventId) + " source=" + sig.Source + " risk_pct=" + sig.RiskPct.ToString("F3", CultureInfo.InvariantCulture);
            if (!sig.Valid)
            {
                var init = SameText(sig.Source, "bridge_initiated") || SameText(fields[offset + 7], "INIT");
                detail = (init ? "bridge_init_marker " : "invalid_parsed_signal ") + detail;
            }
            return sig.Valid;
        }

        private bool SignalIdentityMatches(BridgeSignal sig, out string reason)
        {
            reason = string.Empty;
            if (RequireSourceMatchesChart && !SourceSymbolMatches(sig.SourceSymbol))
            {
                reason = "symbol_filter source=" + sig.SourceSymbol + " chart=" + Instrument.FullName + " aliases=" + SourceSymbolAliasesCsv;
                return false;
            }
            var tf = EffectiveSourceTf();
            if (!string.IsNullOrWhiteSpace(tf) && !SameText(NormalizeTf(sig.SourceTf), tf))
            {
                reason = "tf_filter source=" + sig.SourceTf + " expected=" + tf;
                return false;
            }
            var expected = ExpectedSourceNamespace();
            if (string.IsNullOrWhiteSpace(sig.Source) || !sig.Source.StartsWith(expected, StringComparison.OrdinalIgnoreCase))
            {
                reason = "source_filter source=" + sig.Source + " expected=" + expected;
                return false;
            }
            return true;
        }

        private bool SourceSymbolMatches(string source)
        {
            var sourceCanonical = CanonicalSymbol(source);
            if (SameText(sourceCanonical, CanonicalChartSymbol()))
                return true;
            return SourceAliases().Any(a => SameText(CanonicalSymbol(a), sourceCanonical));
        }

        private IEnumerable<string> SourceAliases()
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var part in (SourceSymbolAliasesCsv ?? string.Empty).Replace(';', ',').Split(','))
            {
                var value = part.Trim();
                if (!string.IsNullOrWhiteSpace(value) && seen.Add(value))
                    yield return value;
            }
            foreach (var value in InferredSourceAliases())
                if (seen.Add(value))
                    yield return value;
        }

        private IEnumerable<string> InferredSourceAliases()
        {
            var canonical = CanonicalChartSymbol();
            if (!string.IsNullOrWhiteSpace(canonical))
            {
                yield return canonical;
                yield return canonical + "m";
            }
            if (canonical == "USTEC") { yield return "US100"; yield return "US100m"; yield return "NAS100"; yield return "USTECm"; }
            if (canonical == "US500") { yield return "SPX500"; yield return "SPX500m"; yield return "US500m"; }
            if (canonical == "US30") { yield return "DJ30"; yield return "US30m"; }
            if (canonical == "DE30") { yield return "GER30"; yield return "GER40"; yield return "DAX40"; yield return "DE30m"; }
            if (canonical == "JP225") { yield return "JP225m"; yield return "JPN225"; yield return "JPN225m"; }
            if (canonical == "UKOIL") { yield return "UKOILm"; yield return "XBRUSD"; }
            if (canonical == "USOIL") { yield return "USOILm"; yield return "XTIUSD"; }
        }

        private string ResolveBridgeReadPath()
        {
            if (!PreferScopedLatest || string.IsNullOrWhiteSpace(resolvedBridgePath))
                return resolvedBridgePath;
            var name = Path.GetFileName(resolvedBridgePath) ?? string.Empty;
            const string suffix = "_Latest.csv";
            if (!name.EndsWith(suffix, StringComparison.OrdinalIgnoreCase))
                return resolvedBridgePath;
            var tf = EffectiveSourceTf();
            if (string.IsNullOrWhiteSpace(tf))
                return resolvedBridgePath;
            var prefix = name.Substring(0, name.Length - suffix.Length) + "_Latest_";
            var dir = Path.GetDirectoryName(resolvedBridgePath) ?? string.Empty;
            string newest = null;
            var newestTime = DateTime.MinValue;
            foreach (var alias in SourceAliases())
            {
                var candidate = Path.Combine(dir, prefix + Sanitize(alias) + "_" + tf + ".csv");
                if (!File.Exists(candidate))
                    continue;
                DateTime write;
                try { write = File.GetLastWriteTimeUtc(candidate); }
                catch { continue; }
                if (newest == null || write > newestTime)
                {
                    newest = candidate;
                    newestTime = write;
                }
            }
            return newest ?? resolvedBridgePath;
        }

        private string ResolveBridgePath()
        {
            return string.IsNullOrWhiteSpace(BridgeLatestPath) ? DefaultBridgeLatestPath : BridgeLatestPath.Trim();
        }

        private string ExpectedSourceNamespace()
        {
            var value = string.IsNullOrWhiteSpace(SourceFilter) ? DefaultSourceNamespace : SourceFilter.Trim();
            return value.EndsWith("|", StringComparison.Ordinal) ? value : value + "|";
        }

        private string EffectiveSourceTf()
        {
            var value = NormalizeTf(SourceTimeframeFilter);
            return string.IsNullOrWhiteSpace(value) && DefaultSourceTfToChartPeriod ? ChartTfString() : value;
        }

        private string ChartTfString()
        {
            if (BarsPeriod == null)
                return string.Empty;
            if (BarsPeriod.BarsPeriodType == BarsPeriodType.Minute)
                return BarsPeriod.Value.ToString(CultureInfo.InvariantCulture);
            if (BarsPeriod.BarsPeriodType == BarsPeriodType.Day)
                return (BarsPeriod.Value * 1440).ToString(CultureInfo.InvariantCulture);
            return string.Empty;
        }

        private bool ShouldRebaseLevels(BridgeSignal sig)
        {
            if (!RebaseMappedLevelsToLiveEntry || sig.BridgeEntry <= 0 || sig.Sl <= 0 || sig.Tp <= 0)
                return false;
            if (RebaseOnlyWhenSourceDiffers && SameText(CanonicalSymbol(sig.SourceSymbol), CanonicalChartSymbol()))
                return false;
            return true;
        }

        private BridgeSignal RebaseLevels(BridgeSignal sig, double liveEntry, out string detail)
        {
            var oldEntry = sig.BridgeEntry;
            var oldSl = sig.Sl;
            var oldTp = sig.Tp;
            var oldHalf = sig.HalfTrigger;
            if (sig.Direction > 0)
            {
                sig.Sl = liveEntry - Math.Abs(oldEntry - oldSl);
                sig.Tp = liveEntry + Math.Abs(oldTp - oldEntry);
                if (oldHalf > 0) sig.HalfTrigger = liveEntry + Math.Abs(oldHalf - oldEntry);
            }
            else
            {
                sig.Sl = liveEntry + Math.Abs(oldSl - oldEntry);
                sig.Tp = liveEntry - Math.Abs(oldEntry - oldTp);
                if (oldHalf > 0) sig.HalfTrigger = liveEntry - Math.Abs(oldEntry - oldHalf);
            }
            detail = "source_entry=" + oldEntry + " live_entry=" + liveEntry + " old_sl=" + oldSl + " old_tp=" + oldTp + " old_half=" + oldHalf + " new_sl=" + sig.Sl + " new_tp=" + sig.Tp + " new_half=" + sig.HalfTrigger;
            return sig;
        }

        private bool ValidateMappedPriceBasis(BridgeSignal sig, double liveEntry, out string detail)
        {
            detail = "basis_guard_not_required";
            if (MappedBasisGuardPctRisk <= 0 || sig.BridgeEntry <= 0 || sig.Sl <= 0 || SameText(CanonicalSymbol(sig.SourceSymbol), CanonicalChartSymbol()))
                return true;
            var sourceRisk = Math.Abs(sig.BridgeEntry - sig.Sl);
            if (sourceRisk <= TickSize)
                return true;
            var offset = Math.Abs(liveEntry - sig.BridgeEntry);
            var pct = offset * 100.0 / sourceRisk;
            detail = "source_entry=" + sig.BridgeEntry + " live_entry=" + liveEntry + " source_sl=" + sig.Sl + " basis_offset=" + offset + " source_risk=" + sourceRisk + " basis_pct_risk=" + pct.ToString("F2", CultureInfo.InvariantCulture) + " max=" + MappedBasisGuardPctRisk.ToString("F2", CultureInfo.InvariantCulture);
            return pct <= MappedBasisGuardPctRisk;
        }

        private bool ValidateGeometry(BridgeSignal sig, double entry, out string detail)
        {
            if (sig.Sl <= 0 || sig.Tp <= 0 || entry <= 0)
            {
                detail = "missing_levels entry=" + entry + " sl=" + sig.Sl + " tp=" + sig.Tp;
                return false;
            }
            return ProtectionGeometryValid(sig.Direction, entry, sig.Sl, sig.Tp, out detail);
        }

        private bool ProtectionGeometryValid(int direction, double market, double sl, double tp, out string detail)
        {
            var valid = direction > 0 ? sl < market && tp > market : sl > market && tp < market;
            detail = "dir=" + direction + " market=" + market + " sl=" + sl + " tp=" + tp + " tick=" + TickSize;
            return valid;
        }

        private bool HasOppositeTrade(int direction, string sourceTf)
        {
            return ScopedTrades(sourceTf).Any(t => IsExposureState(t) && t.Direction != direction);
        }

        private IEnumerable<TradeState> ScopedTrades(string sourceTf)
        {
            var tf = NormalizeTf(sourceTf);
            foreach (var trade in trades.Values)
            {
                if (!CloseReverseAcrossSourceTf && !string.IsNullOrWhiteSpace(tf) && !SameText(tf, NormalizeTf(trade.SourceTf)))
                    continue;
                yield return trade;
            }
        }

        private bool HasPendingExit()
        {
            return trades.Values.Any(t => t.Status == "EXIT_PENDING" || t.Status == "EMERGENCY_PENDING");
        }

        private bool HasAccountExposureFor(TradeState trade)
        {
            var position = AccountPosition();
            if (position == null || position.MarketPosition == MarketPosition.Flat || position.Quantity <= 0)
                return false;
            var direction = position.MarketPosition == MarketPosition.Long ? 1 : -1;
            return direction == trade.Direction;
        }

        private Position AccountPosition()
        {
            return Account.Positions.FirstOrDefault(p => SameInstrument(p.Instrument) && p.MarketPosition != MarketPosition.Flat);
        }

        private int AccountPositionQuantity()
        {
            var position = AccountPosition();
            return position == null ? 0 : position.Quantity;
        }

        private bool SameInstrument(Instrument other)
        {
            return other != null && SameText(other.FullName, Instrument.FullName);
        }

        private Order FindOrder(string name)
        {
            if (string.IsNullOrWhiteSpace(name))
                return null;
            return Account.Orders.Where(o => SameInstrument(o.Instrument) && SameText(o.Name, name)).OrderByDescending(o => o.Time).FirstOrDefault();
        }

        private string BuildOrderScopePrefix()
        {
            var basePrefix = Sanitize(DefaultOrderPrefix).ToUpperInvariant();
            if (basePrefix.Length > 8)
                basePrefix = basePrefix.Substring(0, 8);
            return basePrefix + instanceToken.Substring(0, 6);
        }

        private string OrderName(string role, string eventId)
        {
            return orderScopePrefix + role + Hash64(eventId).ToString("X16", CultureInfo.InvariantCulture).Substring(0, 12);
        }

        private bool ClaimEvent(string eventId, out bool committedDuplicate)
        {
            committedDuplicate = false;
            var path = EventLockPath(eventId);
            if (File.Exists(path))
            {
                try
                {
                    var payload = File.ReadAllText(path);
                    if (payload.StartsWith("committed\t", StringComparison.Ordinal) && payload.Contains("\t" + eventId))
                    {
                        committedDuplicate = true;
                        return false;
                    }
                    if (trades.ContainsKey(eventId))
                        return false;
                    if ((DateTime.UtcNow - File.GetLastWriteTimeUtc(path)).TotalSeconds < PendingLockSeconds)
                        return false;
                    File.Delete(path);
                }
                catch { return false; }
            }
            try
            {
                using (var fs = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (var sw = new StreamWriter(fs, new UTF8Encoding(false)))
                    sw.Write("pending\t" + DateTime.UtcNow.ToString("O") + "\t" + eventId);
                return true;
            }
            catch (IOException) { return false; }
        }

        private bool HasCommittedEvent(string eventId)
        {
            try
            {
                var path = EventLockPath(eventId);
                return File.Exists(path) && File.ReadAllText(path).StartsWith("committed\t", StringComparison.Ordinal);
            }
            catch { return false; }
        }

        private void CommitEvent(string eventId, string outcome)
        {
            try { WriteAtomically(EventLockPath(eventId), "committed\t" + DateTime.UtcNow.ToString("O") + "\t" + eventId + "\t" + outcome); }
            catch (Exception ex) { AuditRaw("event_commit_failed", "event=" + ShortEvent(eventId) + " error=" + ex.Message); }
        }

        private void ReleaseEvent(string eventId)
        {
            try
            {
                var path = EventLockPath(eventId);
                if (File.Exists(path)) File.Delete(path);
            }
            catch { }
        }

        private string EventLockPath(string eventId)
        {
            return Path.Combine(lockDir, Hash64(eventId).ToString("X16", CultureInfo.InvariantCulture) + ".lock");
        }

        private void CleanupOldLocks()
        {
            var key = "lock_cleanup";
            DateTime last;
            if (auditThrottle.TryGetValue(key, out last) && (DateTime.UtcNow - last).TotalHours < 24)
                return;
            auditThrottle[key] = DateTime.UtcNow;
            try
            {
                foreach (var path in Directory.GetFiles(lockDir, "*.lock"))
                    if ((DateTime.UtcNow - File.GetLastWriteTimeUtc(path)).TotalDays > 60)
                        File.Delete(path);
            }
            catch (Exception ex) { AuditRaw("lock_cleanup_failed", ex.Message); }
        }

        private void SaveTradeState(TradeState trade)
        {
            var fields = new Dictionary<string, string>
            {
                { "event", trade.EventId }, { "source", trade.Source }, { "symbol", trade.SourceSymbol }, { "tf", trade.SourceTf },
                { "dir", trade.Direction.ToString(CultureInfo.InvariantCulture) }, { "signal_time", trade.SignalTime.ToString("O") },
                { "written", trade.WrittenGmt.ToString("O") }, { "bridge_entry", G17(trade.BridgeEntry) }, { "fill_entry", G17(trade.FillEntry) },
                { "sl", G17(trade.StopLoss) }, { "tp", G17(trade.TakeProfit) }, { "half", G17(trade.HalfTrigger) },
                { "risk_pct", G17(trade.RiskPct) }, { "requested_qty", trade.RequestedQuantity.ToString(CultureInfo.InvariantCulture) },
                { "qty", trade.Quantity.ToString(CultureInfo.InvariantCulture) }, { "status", trade.Status ?? string.Empty },
                { "entry_name", trade.EntryOrderName ?? string.Empty }, { "entry_id", trade.EntryOrderId ?? string.Empty },
                { "stop_name", trade.StopOrderName ?? string.Empty }, { "stop_id", trade.StopOrderId ?? string.Empty },
                { "target_name", trade.TargetOrderName ?? string.Empty }, { "target_id", trade.TargetOrderId ?? string.Empty },
                { "half_name", trade.HalfOrderName ?? string.Empty }, { "half_qty", trade.HalfCloseQuantity.ToString(CultureInfo.InvariantCulture) }, { "half_filled_accounted", trade.HalfFilledAccounted.ToString(CultureInfo.InvariantCulture) },
                { "exit_name", trade.ExitOrderName ?? string.Empty }, { "exit_filled_accounted", trade.ExitFilledAccounted.ToString(CultureInfo.InvariantCulture) }, { "oco", trade.Oco ?? string.Empty },
                { "expected_stop", G17(trade.ExpectedStop) }, { "expected_target", G17(trade.ExpectedTarget) },
                { "half_partial", trade.HalfPartialClosed ? "1" : "0" }, { "half_done", trade.HalfDone ? "1" : "0" }, { "stop_filled_accounted", trade.StopFilledAccounted.ToString(CultureInfo.InvariantCulture) }, { "target_filled_accounted", trade.TargetFilledAccounted.ToString(CultureInfo.InvariantCulture) },
                { "protection_failures", trade.ProtectionFailures.ToString(CultureInfo.InvariantCulture) },
                { "last_action", trade.LastActionUtc.ToString("O") }, { "next_retry", trade.NextRetryUtc.ToString("O") },
                { "last_protection_change", trade.LastProtectionChangeUtc.ToString("O") }
            };
            var payload = string.Join("\n", fields.Select(kv => kv.Key + "=" + Convert.ToBase64String(Encoding.UTF8.GetBytes(kv.Value ?? string.Empty))));
            WriteAtomically(TradeStatePath(trade.EventId), payload);
        }

        private void LoadTradeStates()
        {
            trades.Clear();
            foreach (var path in Directory.GetFiles(stateDir, "trade_*.state"))
            {
                try
                {
                    var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    foreach (var line in File.ReadAllLines(path))
                    {
                        var index = line.IndexOf('=');
                        if (index <= 0) continue;
                        var key = line.Substring(0, index);
                        var raw = line.Substring(index + 1);
                        map[key] = Encoding.UTF8.GetString(Convert.FromBase64String(raw));
                    }
                    var trade = TradeState.FromMap(map);
                    if (!string.IsNullOrWhiteSpace(trade.EventId))
                        trades[trade.EventId] = trade;
                }
                catch (Exception ex)
                {
                    AuditRaw("state_load_failed", "file=" + Path.GetFileName(path) + " error=" + ex.Message);
                }
            }
        }

        private string TradeStatePath(string eventId)
        {
            return Path.Combine(stateDir, "trade_" + Hash64(eventId).ToString("X16", CultureInfo.InvariantCulture) + ".state");
        }

        private void DeleteTradeState(string eventId)
        {
            try
            {
                var path = TradeStatePath(eventId);
                if (File.Exists(path)) File.Delete(path);
            }
            catch (Exception ex) { AuditRaw("state_delete_failed", ex.Message); }
        }

        private static void WriteAtomically(string path, string content)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            Exception lastError = null;
            for (var attempt = 0; attempt < 4; attempt++)
            {
                var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
                try
                {
                    File.WriteAllText(temp, content, new UTF8Encoding(false));
                    try
                    {
                        if (File.Exists(path)) File.Replace(temp, path, null);
                        else File.Move(temp, path);
                    }
                    catch
                    {
                        File.Copy(temp, path, true);
                        if (File.Exists(temp)) File.Delete(temp);
                    }
                    return;
                }
                catch (IOException ex)
                {
                    lastError = ex;
                    try { if (File.Exists(temp)) File.Delete(temp); } catch { }
                    Thread.Sleep(20 * (attempt + 1));
                }
            }
            throw new IOException("Atomic state write failed after retries", lastError);
        }

        private void DrawDashboard()
        {
            if (!ShowDashboard || ChartControl == null)
                return;
            var position = AccountPosition();
            var posText = position == null ? "FLAT" : position.MarketPosition + " " + position.Quantity + " @ " + position.AveragePrice.ToString(CultureInfo.InvariantCulture);
            var text = ListenerTitle + "\n"
                     + "Build=" + CoreBuild + " Executor=" + (ExecutorEnabled ? "ON" : "OFF") + " Account=" + SafeAccountName() + "\n"
                     + "Instrument=" + Instrument.FullName + " SourceTF=" + EffectiveSourceTf() + " File=" + Path.GetFileName(ResolveBridgeReadPath()) + "\n"
                     + "Risk=" + (UseBridgeRiskPct ? "BRIDGE" : LocalRiskPct.ToString("F3", CultureInfo.InvariantCulture) + "%") + " Capital=" + (UseCashValueForRisk ? "CASH" : "NET LIQ") + " Value=" + RiskCapital().ToString("F2", CultureInfo.InvariantCulture) + "\n"
                     + "AccountPosition=" + posText + " States=" + trades.Count + " Fault=" + (lifecycleFault ? "YES" : "NO") + "\n"
                     + "Seen=" + ShortEvent(lastSeenEventId) + " Rejected=" + ShortEvent(lastRejectedEventId) + "\n"
                     + TradeDayDashboardText() + "\n"
                     + "Last=" + lastAction + " " + Truncate(lastDetail, 180) + "\nSignal=" + lastSignal;
            Draw.TextFixed(this, "NT_BRIDGE_DASH_" + instanceToken, text, TextPosition.TopLeft, Brushes.LightSkyBlue, new SimpleFont("Consolas", 12), Brushes.Transparent, Brushes.Black, 15);
        }

        private void Audit(string eventName, BridgeSignal sig, string detail)
        {
            lastSignal = sig.SourceSymbol + " " + sig.SourceTf + " " + (sig.Direction > 0 ? "BUY" : "SELL") + " " + ShortEvent(sig.EventId);
            SetAction(eventName, detail);
            WriteAudit(eventName, sig.SourceSymbol, sig.SourceTf, sig.EventId, sig.Source, sig.Direction > 0 ? "BUY" : "SELL", sig.BridgeEntry, sig.Sl, sig.Tp, sig.HalfTrigger, detail);
        }

        private void AuditState(string eventName, TradeState trade, string detail)
        {
            SetAction(eventName, detail);
            WriteAudit(eventName, trade.SourceSymbol, trade.SourceTf, trade.EventId, trade.Source, trade.Direction > 0 ? "BUY" : "SELL", trade.FillEntry > 0 ? trade.FillEntry : trade.BridgeEntry, trade.StopLoss, trade.TakeProfit, trade.HalfTrigger, detail);
        }

        private void AuditStateThrottled(string eventName, TradeState trade, string detail, int seconds)
        {
            var key = eventName + "|" + trade.EventId;
            DateTime last;
            if (auditThrottle.TryGetValue(key, out last) && (DateTime.UtcNow - last).TotalSeconds < seconds)
                return;
            auditThrottle[key] = DateTime.UtcNow;
            AuditState(eventName, trade, detail);
        }

        private void AuditSignalThrottled(string eventName, BridgeSignal sig, string detail, int seconds)
        {
            var key = eventName + "|" + sig.EventId;
            DateTime last;
            if (auditThrottle.TryGetValue(key, out last) && (DateTime.UtcNow - last).TotalSeconds < seconds)
            {
                SetAction(eventName, detail);
                return;
            }
            auditThrottle[key] = DateTime.UtcNow;
            Audit(eventName, sig, detail);
        }

        private void AuditRaw(string eventName, string detail)
        {
            SetAction(eventName, detail);
            WriteAudit(eventName, string.Empty, string.Empty, string.Empty, string.Empty, "-", 0, 0, 0, 0, detail);
        }

        private void WriteAudit(string eventName, string sourceSymbol, string sourceTf, string eventId, string source, string direction, double entry, double sl, double tp, double half, string detail)
        {
            if (!AuditEnabled || string.IsNullOrWhiteSpace(auditDir))
                return;
            var file = Path.Combine(auditDir, AuditFilePrefix + Sanitize(SafeAccountName()) + "_" + Sanitize(Instrument.FullName) + "_TF" + Sanitize(EffectiveSourceTf()) + "_" + DateTime.UtcNow.ToString("yyyyMMdd") + ".csv");
            Exception lastError = null;
            for (var attempt = 0; attempt < 4; attempt++)
            {
                try
                {
                    lock (AuditWriteSync)
                    {
                        using (var fs = new FileStream(file, FileMode.OpenOrCreate, FileAccess.Write, FileShare.ReadWrite))
                        {
                            var header = fs.Length == 0;
                            fs.Seek(0, SeekOrigin.End);
                            using (var sw = new StreamWriter(fs, new UTF8Encoding(false)))
                            {
                                if (header)
                                    sw.WriteLine("time_gmt,build,event,account,instrument,source_symbol,source_tf,event_id,source,dir,entry,sl,tp,half,detail");
                                sw.WriteLine(string.Join(",", Escape(DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss")), Escape(CoreBuild), Escape(eventName), Escape(SafeAccountName()), Escape(Instrument.FullName), Escape(sourceSymbol), Escape(sourceTf), Escape(eventId), Escape(source), Escape(direction), G17(entry), G17(sl), G17(tp), G17(half), Escape(detail)));
                            }
                        }
                    }
                    return;
                }
                catch (IOException ex)
                {
                    lastError = ex;
                    Thread.Sleep(20 * (attempt + 1));
                }
                catch (Exception ex)
                {
                    lastError = ex;
                    break;
                }
            }
            Print(string.Format(CultureInfo.InvariantCulture, "{0} audit write failed: {1}", ListenerTitle, lastError == null ? "unknown" : lastError.Message));
        }

        private void BlockRetry(string eventId, int seconds, string reason)
        {
            retryBlockedUntil[eventId] = DateTime.UtcNow.AddSeconds(Math.Max(5, seconds));
            SetAction("retry_blocked", "event=" + ShortEvent(eventId) + " reason=" + reason + " seconds=" + seconds);
        }

        private bool IsCloseOnlySignal(BridgeSignal sig)
        {
            return ContainsText(sig.Source, "CloseOnly") || ContainsText(sig.EventId, "invalidate_close");
        }

        private bool IsProtectionPermanentlyFailed(TradeState trade)
        {
            return trade.ProtectionFailures >= 2;
        }

        private bool HasForeignExposureMismatch()
        {
            string detail;
            return !CanSafelyManageAccountPosition(out detail);
        }

        private static bool IsExposureState(TradeState trade)
        {
            return trade.Status != "ENTRY_PENDING" || trade.FillEntry > 0;
        }

        private static bool IsWorking(Order order)
        {
            if (order == null) return false;
            return order.OrderState == OrderState.Accepted || order.OrderState == OrderState.AcceptedByRisk || order.OrderState == OrderState.Submitted || order.OrderState == OrderState.Working || order.OrderState == OrderState.PartFilled || order.OrderState == OrderState.TriggerPending || order.OrderState == OrderState.ChangePending || order.OrderState == OrderState.ChangeSubmitted || order.OrderState == OrderState.CancelPending || order.OrderState == OrderState.CancelSubmitted;
        }

        private static bool IsAcceptedOrWorking(Order order)
        {
            return order != null && (IsWorking(order) || order.OrderState == OrderState.Filled);
        }

        private static bool IsFilled(Order order) { return order != null && order.OrderState == OrderState.Filled; }
        private static bool IsRejected(Order order) { return order != null && order.OrderState == OrderState.Rejected; }
        private static bool IsTerminalWithoutFill(Order order) { return order != null && (order.OrderState == OrderState.Cancelled || order.OrderState == OrderState.Rejected) && order.Filled <= 0; }

        private static string OrderFailureText(Order order)
        {
            return order == null ? "order_null" : "state=" + order.OrderState + " text=" + (order.Text ?? string.Empty) + " id=" + (order.OrderId ?? string.Empty);
        }

        private static bool IsMarketClosed(string detail)
        {
            var value = (detail ?? string.Empty).ToLowerInvariant();
            return value.Contains("market is closed") || value.Contains("market closed") || value.Contains("trading is not available") || value.Contains("outside trading hours");
        }

        private static bool IsNoMoney(string detail)
        {
            var value = (detail ?? string.Empty).ToLowerInvariant();
            return value.Contains("margin") || value.Contains("buying power") || value.Contains("insufficient") || value.Contains("not enough") || value.Contains("risk rejected");
        }

        private static bool IsPermanentFailure(string detail)
        {
            var value = (detail ?? string.Empty).ToLowerInvariant();
            return value.Contains("invalid") || value.Contains("quantity") || value.Contains("price") || value.Contains("stop") || value.Contains("instrument");
        }

        private double CurrentSpreadTicks()
        {
            var bid = GetCurrentBid();
            var ask = GetCurrentAsk();
            return bid > 0 && ask >= bid && TickSize > 0 ? (ask - bid) / TickSize : double.MaxValue;
        }

        private double RoundPrice(double value)
        {
            return Instrument.MasterInstrument.RoundToTickSize(value);
        }

        private bool PriceEqual(double a, double b)
        {
            return Math.Abs(a - b) <= Math.Max(TickSize * 0.25, 0.000000001);
        }

        private string CanonicalChartSymbol()
        {
            var master = CanonicalSymbol(Instrument.MasterInstrument.Name);
            if (master == "ES" || master == "MES") return "US500";
            if (master == "NQ" || master == "MNQ") return "USTEC";
            if (master == "YM" || master == "MYM") return "US30";
            if (master == "FDAX" || master == "FDXM" || master == "DAX") return "DE30";
            if (master == "NKD" || master == "MNK" || master == "NIY") return "JP225";
            if (master == "CL" || master == "MCL") return "USOIL";
            if (master == "BZ" || master == "BRN") return "UKOIL";
            return CanonicalSymbol(Instrument.FullName);
        }

        private static string CanonicalSymbol(string value)
        {
            var source = new string((value ?? string.Empty).Trim().Where(char.IsLetterOrDigit).ToArray()).ToUpperInvariant();
            while (source.Length > 0 && char.IsDigit(source[source.Length - 1]))
                source = source.Substring(0, source.Length - 1);
            if (source.EndsWith("M", StringComparison.Ordinal) && source.Length > 1 && !new[] { "MES", "MNQ", "MYM", "MCL", "MNK", "FDXM" }.Contains(source))
                source = source.Substring(0, source.Length - 1);
            if (source == "USTEC" || source == "US100" || source == "NAS100" || source == "USTECH100" || source == "TECH100") return "USTEC";
            if (source == "US500" || source == "SPX500" || source == "SP500") return "US500";
            if (source == "US30" || source == "DJ30" || source == "WALLSTREET30" || source == "DOW30") return "US30";
            if (source == "DE30" || source == "GER30" || source == "GER40" || source == "DAX40" || source == "GERMANY40") return "DE30";
            if (source == "JP225" || source == "JPN225" || source == "NIKKEI225") return "JP225";
            if (source == "UKOIL" || source == "XBRUSD" || source == "BRENT") return "UKOIL";
            if (source == "USOIL" || source == "XTIUSD" || source == "WTI") return "USOIL";
            return source;
        }

        private static string NormalizeTf(string tf)
        {
            var value = (tf ?? string.Empty).Trim().ToUpperInvariant().Replace("PERIOD_", string.Empty);
            if (value == "H1") return "60";
            if (value == "H2") return "120";
            if (value == "H4") return "240";
            if (value == "D1") return "1440";
            if (value.StartsWith("M", StringComparison.Ordinal) && value.Length > 1) return value.Substring(1);
            return value;
        }

        private string SafeAccountName()
        {
            return Account == null ? "NO_ACCOUNT" : (string.IsNullOrWhiteSpace(Account.Name) ? Account.DisplayName : Account.Name);
        }

        private void SetAction(string action, string detail)
        {
            lastAction = action;
            lastDetail = detail ?? string.Empty;
        }

        private static string NormalizePath(string path)
        {
            try { return Path.GetFullPath(path ?? string.Empty).Trim().ToUpperInvariant(); }
            catch { return (path ?? string.Empty).Trim().ToUpperInvariant(); }
        }

        private static List<string> ParseCsvFlat(string text)
        {
            var result = new List<string>();
            var builder = new StringBuilder();
            var inQuotes = false;
            for (var i = 0; i < (text ?? string.Empty).Length; i++)
            {
                var ch = text[i];
                if (ch == '"')
                {
                    if (inQuotes && i + 1 < text.Length && text[i + 1] == '"') { builder.Append('"'); i++; }
                    else inQuotes = !inQuotes;
                    continue;
                }
                if (!inQuotes && (ch == ',' || ch == ';' || ch == '\r' || ch == '\n'))
                {
                    if (ch == '\r' && i + 1 < text.Length && text[i + 1] == '\n') i++;
                    result.Add(builder.ToString().Trim());
                    builder.Clear();
                    continue;
                }
                builder.Append(ch);
            }
            if (builder.Length > 0) result.Add(builder.ToString().Trim());
            return result;
        }

        private static DateTime ParseDate(string value)
        {
            DateTime parsed;
            return DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out parsed) ? parsed : DateTime.MinValue;
        }

        private static double ParseDouble(string value)
        {
            double parsed;
            return double.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out parsed) ? parsed : 0;
        }

        private static int ParseInt(string value)
        {
            int parsed;
            return int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out parsed) ? parsed : 0;
        }

        private static bool ParseBool(string value) { return value == "1" || SameText(value, "true"); }
        private static bool SameText(string a, string b) { return string.Equals((a ?? string.Empty).Trim(), (b ?? string.Empty).Trim(), StringComparison.OrdinalIgnoreCase); }
        private static bool ContainsText(string value, string needle) { return (value ?? string.Empty).IndexOf(needle ?? string.Empty, StringComparison.OrdinalIgnoreCase) >= 0; }
        private static bool IsFinitePositive(double value) { return !double.IsNaN(value) && !double.IsInfinity(value) && value > 0; }
        private static bool IsFiniteNonNegative(double value) { return !double.IsNaN(value) && !double.IsInfinity(value) && value >= 0; }
        private static string G17(double value) { return value.ToString("G17", CultureInfo.InvariantCulture); }
        private static string Sanitize(string value) { return new string((value ?? "_").Select(ch => char.IsLetterOrDigit(ch) ? ch : '_').ToArray()); }
        private static string ShortEvent(string value) { return string.IsNullOrEmpty(value) || value.Length <= 36 ? value : value.Substring(0, 20) + "..." + value.Substring(value.Length - 12); }
        private static string Truncate(string value, int length) { return string.IsNullOrEmpty(value) || value.Length <= length ? value : value.Substring(0, length) + "..."; }
        private static string Escape(string value) { value = value ?? string.Empty; return value.Contains(",") || value.Contains("\"") || value.Contains("\n") ? "\"" + value.Replace("\"", "\"\"") + "\"" : value; }

        private static ulong Hash64(string value)
        {
            unchecked
            {
                ulong hash = 14695981039346656037UL;
                foreach (var ch in value ?? string.Empty) { hash ^= ch; hash *= 1099511628211UL; }
                return hash;
            }
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

        private struct TradeState
        {
            public string EventId;
            public string Source;
            public string SourceSymbol;
            public string SourceTf;
            public int Direction;
            public DateTime SignalTime;
            public DateTime WrittenGmt;
            public double BridgeEntry;
            public double FillEntry;
            public double StopLoss;
            public double TakeProfit;
            public double HalfTrigger;
            public double RiskPct;
            public int RequestedQuantity;
            public int Quantity;
            public string Status;
            public string EntryOrderName;
            public string EntryOrderId;
            public string StopOrderName;
            public string StopOrderId;
            public string TargetOrderName;
            public string TargetOrderId;
            public string HalfOrderName;
            public int HalfCloseQuantity;
            public int HalfFilledAccounted;
            public string ExitOrderName;
            public int ExitFilledAccounted;
            public string Oco;
            public double ExpectedStop;
            public double ExpectedTarget;
            public bool HalfPartialClosed;
            public bool HalfDone;
            public int StopFilledAccounted;
            public int TargetFilledAccounted;
            public int ProtectionFailures;
            public DateTime LastActionUtc;
            public DateTime NextRetryUtc;
            public DateTime LastProtectionChangeUtc;

            public static TradeState FromSignal(BridgeSignal sig, int quantity)
            {
                return new TradeState
                {
                    EventId = sig.EventId, Source = sig.Source, SourceSymbol = sig.SourceSymbol, SourceTf = NormalizeTf(sig.SourceTf),
                    Direction = sig.Direction, SignalTime = sig.SignalTime, WrittenGmt = sig.WrittenGmt, BridgeEntry = sig.BridgeEntry,
                    StopLoss = sig.Sl, TakeProfit = sig.Tp, HalfTrigger = sig.HalfTrigger, RiskPct = sig.RiskPct,
                    RequestedQuantity = quantity, Quantity = quantity, LastActionUtc = DateTime.UtcNow
                };
            }

            public static TradeState FromMap(Dictionary<string, string> map)
            {
                Func<string, string> get = key => map.ContainsKey(key) ? map[key] : string.Empty;
                return new TradeState
                {
                    EventId = get("event"), Source = get("source"), SourceSymbol = get("symbol"), SourceTf = get("tf"),
                    Direction = ParseInt(get("dir")), SignalTime = ParseDate(get("signal_time")), WrittenGmt = ParseDate(get("written")),
                    BridgeEntry = ParseDouble(get("bridge_entry")), FillEntry = ParseDouble(get("fill_entry")), StopLoss = ParseDouble(get("sl")),
                    TakeProfit = ParseDouble(get("tp")), HalfTrigger = ParseDouble(get("half")), RiskPct = ParseDouble(get("risk_pct")),
                    RequestedQuantity = ParseInt(get("requested_qty")), Quantity = ParseInt(get("qty")), Status = get("status"),
                    EntryOrderName = get("entry_name"), EntryOrderId = get("entry_id"), StopOrderName = get("stop_name"), StopOrderId = get("stop_id"),
                    TargetOrderName = get("target_name"), TargetOrderId = get("target_id"), HalfOrderName = get("half_name"), HalfCloseQuantity = ParseInt(get("half_qty")), HalfFilledAccounted = ParseInt(get("half_filled_accounted")),
                    ExitOrderName = get("exit_name"), ExitFilledAccounted = ParseInt(get("exit_filled_accounted")), Oco = get("oco"), ExpectedStop = ParseDouble(get("expected_stop")), ExpectedTarget = ParseDouble(get("expected_target")),
                    HalfPartialClosed = ParseBool(get("half_partial")), HalfDone = ParseBool(get("half_done")), StopFilledAccounted = ParseInt(get("stop_filled_accounted")), TargetFilledAccounted = ParseInt(get("target_filled_accounted")), ProtectionFailures = ParseInt(get("protection_failures")),
                    LastActionUtc = ParseDate(get("last_action")), NextRetryUtc = ParseDate(get("next_retry")), LastProtectionChangeUtc = ParseDate(get("last_protection_change"))
                };
            }
        }
    }
}
