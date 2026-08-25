// Production MT5 CSV bridge listener core for Quantower.
// Signal generation remains entirely on the MT5 publisher side.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using TradingPlatform.BusinessLayer;

namespace ProTradingSystem.Quantower
{
    public abstract class ProductionFileBridgeQuantowerCore : Strategy, ICurrentSymbol, ICurrentAccount
    {
        private const string CoreBuild = "2026-08-24.quantower-production-v3-accepted-signal-seal";

        protected virtual bool RequireAcceptedSignalSeal { get { return false; } }
        private static readonly object GlobalEntrySync = new object();
        private static readonly Dictionary<string, string> GlobalEntryOwners = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly object sync = new object();
        private readonly Dictionary<string, PositionState> states = new Dictionary<string, PositionState>(StringComparer.Ordinal);
        private readonly Dictionary<string, DateTime> retryAfter = new Dictionary<string, DateTime>(StringComparer.Ordinal);
        private Timer pollTimer;
        private FileStream scopeLease;
        private PendingEntry pendingEntry;
        private string resolvedBridgePath;
        private string stateDirectory;
        private string eventLockDirectory;
        private string auditDirectory;
        private string scopeToken;
        private string lastSeenEventId = string.Empty;
        private string lastRejectedIdentity = string.Empty;
        private string lastAction = "created";
        private string lastDetail = string.Empty;
        private DateTime lastHeartbeatUtc = DateTime.MinValue;
        private DateTime lastReadFailureAuditUtc = DateTime.MinValue;
        private bool running;
        private int pollActive;

        [InputParameter("Symbol", 0)]
        public Symbol CurrentSymbol { get; set; }

        [InputParameter("Account", 1)]
        public Account CurrentAccount { get; set; }

        [InputParameter("Executor Enabled", 10)]
        public bool ExecutorEnabled { get; set; }

        [InputParameter("Bridge Latest Path", 11)]
        public string BridgeLatestPath { get; set; }

        [InputParameter("Prefer Scoped Latest", 12)]
        public bool PreferScopedLatest { get; set; }

        [InputParameter("Source TF Filter", 13)]
        public string SourceTimeframeFilter { get; set; }

        [InputParameter("Bridge Channel (0=standard)", 14, 0, 9999, 1, 0)]
        public int BridgeChannel { get; set; }

        [InputParameter("Source Filter", 15)]
        public string SourceFilter { get; set; }

        [InputParameter("Source Symbol Aliases CSV", 16)]
        public string SourceSymbolAliasesCsv { get; set; }

        [InputParameter("Require Source Symbol", 17)]
        public bool RequireSourceMatchesTarget { get; set; }

        [InputParameter("Poll Milliseconds", 18, 250, 10000, 250, 0)]
        public int PollMilliseconds { get; set; }

        [InputParameter("Max Signal Age Seconds", 19, 0, 86400, 30, 0)]
        public int MaxSignalAgeSeconds { get; set; }

        [InputParameter("Ignore Existing On Start", 20)]
        public bool IgnoreExistingOnStart { get; set; }

        [InputParameter("Use Risk Quantity", 30)]
        public bool UseRiskQuantity { get; set; }

        [InputParameter("Use Bridge Risk %", 31)]
        public bool UseBridgeRiskPercent { get; set; }

        [InputParameter("Local Risk %", 32, 0.01, 100.0, 0.01, 2)]
        public double LocalRiskPercent { get; set; }

        [InputParameter("Fixed Risk Capital (0=Balance)", 33, 0, 1000000000, 100, 2)]
        public double FixedRiskCapital { get; set; }

        [InputParameter("Manual Quantity", 34, 0.000001, 1000000, 1, 6)]
        public double ManualQuantity { get; set; }

        [InputParameter("Max Quantity (0=Symbol Max)", 35, 0, 1000000, 1, 6)]
        public double MaxQuantity { get; set; }

        [InputParameter("Block If Min Qty Exceeds Risk", 36)]
        public bool BlockIfMinimumExceedsRisk { get; set; }

        [InputParameter("Post Fill Risk Guard", 37)]
        public bool PostFillRiskGuard { get; set; }

        [InputParameter("Max Risk Overshoot %", 38, 0, 100, 0.5, 1)]
        public double MaxRiskOvershootPercent { get; set; }

        [InputParameter("Rebase Levels To Live", 40)]
        public bool RebaseLevelsToLive { get; set; }

        [InputParameter("Rebase Only If Symbol Differs", 41)]
        public bool RebaseOnlyIfSymbolDiffers { get; set; }

        [InputParameter("Fail If Exact Protection Fails", 42)]
        public bool FailIfExactProtectionFails { get; set; }

        [InputParameter("Use Reduce Only Protection", 43)]
        public bool UseReduceOnlyProtection { get; set; }

        [InputParameter("Allow Reduce Only Fallback", 44)]
        public bool AllowReduceOnlyFallback { get; set; }

        [InputParameter("Protection Verify Seconds", 45, 2, 60, 1, 0)]
        public int ProtectionVerifySeconds { get; set; }

        [InputParameter("Close Reverse", 50)]
        public bool CloseReverse { get; set; }

        [InputParameter("Fail If Reverse Close Fails", 51)]
        public bool FailIfReverseCloseFails { get; set; }

        [InputParameter("Enable Close Only Signals", 52)]
        public bool EnableCloseOnlySignals { get; set; }

        [InputParameter("Manage HCBE", 53)]
        public bool ManageHalfCloseBe { get; set; }

        [InputParameter("Half Close Fraction", 54, 0.05, 0.95, 0.05, 2)]
        public double HalfCloseFraction { get; set; }

        [InputParameter("Fail Closed On HCBE Repair", 55)]
        public bool FailClosedOnHcbeRepair { get; set; }

        [InputParameter("Block Netting Scope Conflict", 56)]
        public bool BlockNettingScopeConflict { get; set; }

        [InputParameter("Market Closed Retry Seconds", 60, 10, 3600, 10, 0)]
        public int MarketClosedRetrySeconds { get; set; }

        [InputParameter("Order Failure Retry Seconds", 61, 5, 3600, 5, 0)]
        public int OrderFailureRetrySeconds { get; set; }

        [InputParameter("Pending Lock Seconds", 62, 30, 3600, 30, 0)]
        public int PendingLockSeconds { get; set; }

        [InputParameter("Audit Enabled", 70)]
        public bool AuditEnabled { get; set; }

        [InputParameter("Heartbeat Seconds", 71, 60, 86400, 60, 0)]
        public int HeartbeatSeconds { get; set; }

        [InputParameter("Instance Label", 72)]
        public string InstanceLabel { get; set; }

        public override string[] MonitoringConnectionsIds
        {
            get { return CurrentSymbol == null ? new string[0] : new[] { CurrentSymbol.ConnectionId }; }
        }

        protected ProductionFileBridgeQuantowerCore()
        {
            ExecutorEnabled = true;
            PreferScopedLatest = true;
            BridgeChannel = 0;
            RequireSourceMatchesTarget = true;
            PollMilliseconds = 500;
            MaxSignalAgeSeconds = 900;
            IgnoreExistingOnStart = true;
            UseRiskQuantity = true;
            UseBridgeRiskPercent = true;
            LocalRiskPercent = 0.30;
            FixedRiskCapital = 0;
            ManualQuantity = 1;
            MaxQuantity = 0;
            BlockIfMinimumExceedsRisk = true;
            PostFillRiskGuard = true;
            MaxRiskOvershootPercent = 3.0;
            RebaseLevelsToLive = true;
            RebaseOnlyIfSymbolDiffers = true;
            FailIfExactProtectionFails = true;
            UseReduceOnlyProtection = true;
            AllowReduceOnlyFallback = true;
            ProtectionVerifySeconds = 10;
            CloseReverse = true;
            FailIfReverseCloseFails = true;
            EnableCloseOnlySignals = true;
            ManageHalfCloseBe = true;
            HalfCloseFraction = 0.50;
            FailClosedOnHcbeRepair = true;
            BlockNettingScopeConflict = true;
            MarketClosedRetrySeconds = 60;
            OrderFailureRetrySeconds = 30;
            PendingLockSeconds = 120;
            AuditEnabled = true;
            HeartbeatSeconds = 21600;
            InstanceLabel = "QW";
        }

        protected void ConfigureDefaults(string path, string source, string tf, string aliases, string label)
        {
            BridgeLatestPath = path;
            SourceFilter = source;
            SourceTimeframeFilter = tf;
            SourceSymbolAliasesCsv = aliases;
            InstanceLabel = label;
        }

        protected override void OnRun()
        {
            lock (sync)
            {
                if (CurrentSymbol == null || CurrentAccount == null)
                {
                    LogStatus("start_failed", "Symbol and Account are required");
                    return;
                }
                if (!SameText(CurrentSymbol.ConnectionId, CurrentAccount.ConnectionId))
                {
                    LogStatus("start_failed", "Symbol and Account must belong to the same Quantower connection");
                    return;
                }

                CurrentSymbol = Core.Instance.GetSymbol(CurrentSymbol.CreateInfo());
                CurrentAccount = Core.Instance.GetAccount(CurrentAccount.CreateInfo());
                resolvedBridgePath = ExpandPath(BridgeLatestPath);
                scopeToken = HashText(ScopeIdentity()).Substring(0, 16);
                var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ProTradingSystem", "QuantowerBridge");
                Directory.CreateDirectory(root);
                if (!TryAcquireScopeLease(root))
                {
                    LogStatus("start_failed", "another listener already owns scope=" + scopeToken);
                    return;
                }
                stateDirectory = Path.Combine(root, "state", scopeToken);
                eventLockDirectory = Path.Combine(root, "event-locks", scopeToken);
                auditDirectory = Path.Combine(root, "audit");
                Directory.CreateDirectory(stateDirectory);
                Directory.CreateDirectory(eventLockDirectory);
                Directory.CreateDirectory(auditDirectory);

                Core.Instance.PositionAdded += OnPositionAdded;
                Core.Instance.PositionRemoved += OnPositionRemoved;
                Core.Instance.TradeAdded += OnTradeAdded;
                LoadPositionStates();
                RepairTrackedPositions("start");
                running = true;

                BridgeSignal baseline;
                string baselineDetail;
                if (IgnoreExistingOnStart && TryReadSignal(out baseline, out baselineDetail) && SignalIdentityMatches(baseline, out baselineDetail))
                {
                    lastSeenEventId = baseline.EventId;
                    Audit("init_baseline", baseline, "existing latest ignored");
                }
                else
                {
                    AuditRaw("init", "no baseline or baseline disabled");
                }

                pollTimer = new Timer(PollTimerCallback, null, 0, Timeout.Infinite);
                LogStatus("running", "scope=" + scopeToken + " file=" + ResolveBridgeReadPath() + " channel=" + BridgeChannel
                    + " target=" + CurrentSymbol.Name + " canonical_target=" + CanonicalTargetSymbol());
            }
        }

        protected override void OnStop()
        {
            StopCore("stop");
        }

        protected override void OnRemove()
        {
            StopCore("remove");
        }

        private void StopCore(string reason)
        {
            lock (sync)
            {
                running = false;
                ReleaseGlobalEntryOwnership();
                if (pollTimer != null)
                {
                    pollTimer.Dispose();
                    pollTimer = null;
                }
                Core.Instance.PositionAdded -= OnPositionAdded;
                Core.Instance.PositionRemoved -= OnPositionRemoved;
                Core.Instance.TradeAdded -= OnTradeAdded;
                AuditRaw("stopped", "reason=" + reason);
                if (scopeLease != null)
                {
                    scopeLease.Dispose();
                    scopeLease = null;
                }
            }
        }

        private bool TryAcquireScopeLease(string root)
        {
            try
            {
                var directory = Path.Combine(root, "scope-locks");
                Directory.CreateDirectory(directory);
                var path = Path.Combine(directory, scopeToken + ".lock");
                scopeLease = new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
                scopeLease.SetLength(0);
                using (var writer = new StreamWriter(scopeLease, new UTF8Encoding(false), 1024, true))
                {
                    writer.Write(DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture));
                    writer.Flush();
                }
                scopeLease.Flush(true);
                return true;
            }
            catch (IOException)
            {
                if (scopeLease != null)
                {
                    scopeLease.Dispose();
                    scopeLease = null;
                }
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                if (scopeLease != null)
                {
                    scopeLease.Dispose();
                    scopeLease = null;
                }
                return false;
            }
        }

        private void PollTimerCallback(object ignored)
        {
            if (!running || Interlocked.Exchange(ref pollActive, 1) != 0)
                return;
            try
            {
                lock (sync)
                {
                    PollBridge();
                    RepairPendingEntry();
                    VerifyProtectionAndRisk();
                    ManageHcbe();
                    ManageEmergencyCloses();
                    Heartbeat();
                }
            }
            catch (Exception ex)
            {
                AuditRaw("poll_exception", ex.ToString());
            }
            finally
            {
                Interlocked.Exchange(ref pollActive, 0);
                if (running && pollTimer != null)
                    pollTimer.Change(Math.Max(250, PollMilliseconds), Timeout.Infinite);
            }
        }

        private void PollBridge()
        {
            BridgeSignal signal;
            string detail;
            if (!TryReadSignal(out signal, out detail))
            {
                if ((DateTime.UtcNow - lastReadFailureAuditUtc).TotalMinutes >= 5)
                {
                    lastReadFailureAuditUtc = DateTime.UtcNow;
                    AuditRaw("read_wait", detail);
                }
                SetAction("read_wait", detail);
                return;
            }

            if (SameText(signal.EventId, lastSeenEventId))
            {
                SetAction("idle", ShortEvent(signal.EventId));
                return;
            }

            if (!SignalIdentityMatches(signal, out detail))
            {
                var key = signal.EventId + "|" + detail;
                if (!SameText(key, lastRejectedIdentity))
                {
                    lastRejectedIdentity = key;
                    Audit("identity_rejected", signal, detail);
                }
                return;
            }
            lastRejectedIdentity = string.Empty;

            DateTime blockedUntil;
            if (retryAfter.TryGetValue(signal.EventId, out blockedUntil) && DateTime.UtcNow < blockedUntil)
            {
                SetAction("retry_wait", blockedUntil.ToString("O", CultureInfo.InvariantCulture));
                return;
            }

            var ageSeconds = (DateTime.UtcNow - signal.WrittenGmt).TotalSeconds;
            if (MaxSignalAgeSeconds > 0 && ageSeconds > MaxSignalAgeSeconds)
            {
                lastSeenEventId = signal.EventId;
                Audit("stale_rejected", signal, "age_sec=" + ageSeconds.ToString("F0", CultureInfo.InvariantCulture));
                return;
            }

            if (!ExecutorEnabled)
            {
                lastSeenEventId = signal.EventId;
                Audit("executor_off", signal, "signal consumed without execution");
                return;
            }

            if (EnableCloseOnlySignals && IsCloseOnlySignal(signal))
            {
                if (ProcessCloseOnly(signal, out detail))
                    lastSeenEventId = signal.EventId;
                Audit("close_only", signal, detail);
                return;
            }

            if (pendingEntry != null)
            {
                SetAction("entry_pending", ShortEvent(pendingEntry.Signal.EventId));
                return;
            }

            if (ExecuteSignal(signal, out detail))
                lastSeenEventId = signal.EventId;
        }

        private bool ExecuteSignal(BridgeSignal signal, out string detail)
        {
            detail = string.Empty;
            if (!CurrentSymbol.IsTradingAllowed(CurrentAccount))
            {
                BlockRetry(signal.EventId, MarketClosedRetrySeconds);
                Audit("trading_not_allowed", signal, "symbol/account currently rejects trading");
                return false;
            }

            var side = signal.Direction > 0 ? Side.Buy : Side.Sell;
            var liveEntry = side == Side.Buy ? CurrentSymbol.Ask : CurrentSymbol.Bid;
            if (liveEntry <= 0)
            {
                BlockRetry(signal.EventId, OrderFailureRetrySeconds);
                Audit("quote_invalid", signal, "bid=" + CurrentSymbol.Bid + " ask=" + CurrentSymbol.Ask);
                return false;
            }

            if (ShouldRebase(signal))
            {
                var oldEntry = signal.BridgeEntry;
                signal = Rebase(signal, liveEntry);
                Audit("levels_rebased", signal, "source_entry=" + oldEntry + " live_entry=" + liveEntry);
            }
            signal.Sl = RoundPrice(signal.Sl);
            signal.Tp = RoundPrice(signal.Tp);
            if (signal.HalfTrigger > 0)
                signal.HalfTrigger = RoundPrice(signal.HalfTrigger);

            if (!ValidGeometry(signal.Direction, liveEntry, signal.Sl, signal.Tp))
            {
                lastSeenEventId = signal.EventId;
                Audit("geometry_rejected", signal, "live_entry=" + liveEntry);
                return true;
            }

            bool committed;
            if (!ClaimEvent(signal.EventId, out committed))
            {
                if (committed)
                    lastSeenEventId = signal.EventId;
                Audit(committed ? "duplicate_committed" : "claim_pending", signal, "scope=" + scopeToken);
                return committed;
            }

            if (CloseReverse && !CloseReversePositions(signal, out detail))
            {
                if (FailIfReverseCloseFails)
                {
                    ReleaseEvent(signal.EventId);
                    BlockRetry(signal.EventId, ContainsText(detail, "pending") ? 5 : OrderFailureRetrySeconds);
                    Audit("reverse_close_failed", signal, detail);
                    return false;
                }
                Audit("reverse_close_failed_continue", signal, detail);
            }

            if (BlockNettingScopeConflict && IsNettingAccount() && HasUnownedExposure())
            {
                ReleaseEvent(signal.EventId);
                lastSeenEventId = signal.EventId;
                Audit("netting_scope_conflict", signal, "unowned position exists on target account/symbol");
                return true;
            }

            double estimatedRisk;
            var quantity = ResolveQuantity(signal, liveEntry, out estimatedRisk, out detail);
            if (quantity <= 0)
            {
                ReleaseEvent(signal.EventId);
                lastSeenEventId = signal.EventId;
                Audit("quantity_rejected", signal, detail);
                return true;
            }

            var tag = BuildOrderTag(signal);
            if (!TryAcquireGlobalEntryOwnership())
            {
                ReleaseEvent(signal.EventId);
                BlockRetry(signal.EventId, 5);
                Audit("entry_serialization_wait", signal, "another listener is awaiting a fill on this account/symbol");
                return false;
            }
            pendingEntry = new PendingEntry
            {
                Signal = signal,
                Side = side,
                Quantity = quantity,
                SubmittedUtc = DateTime.UtcNow,
                Tag = tag,
                EstimatedRisk = estimatedRisk
            };
            var submittedEntry = pendingEntry;

            var request = new PlaceOrderRequestParameters
            {
                Account = CurrentAccount,
                Symbol = CurrentSymbol,
                Side = side,
                Quantity = quantity,
                OrderTypeId = OrderType.Market,
                TimeInForce = TimeInForce.Default,
                Comment = tag
            };
            var result = Core.Instance.PlaceOrder(request);
            if (result.Status == TradingOperationResultStatus.Failure)
            {
                // Some connectors can publish the fill event synchronously before
                // returning the operation result. Never discard an adopted fill.
                if (submittedEntry.PositionAttached)
                    return true;
                pendingEntry = null;
                ReleaseGlobalEntryOwnership();
                ReleaseEvent(signal.EventId);
                var retry = IsMarketClosed(result.Message) ? MarketClosedRetrySeconds : OrderFailureRetrySeconds;
                BlockRetry(signal.EventId, retry);
                Audit("entry_failed", signal, "message=" + Safe(result.Message) + " qty=" + quantity);
                return false;
            }

            if (pendingEntry != null)
            {
                pendingEntry.Accepted = true;
                pendingEntry.AcceptedUtc = DateTime.UtcNow;
            }
            Audit("entry_accepted", signal, "qty=" + quantity + " estimated_risk=" + estimatedRisk.ToString("F2", CultureInfo.InvariantCulture));
            RepairPendingEntry();
            return true;
        }

        private void OnPositionAdded(Position position)
        {
            lock (sync)
            {
                TryAttachPendingPosition(position, "position_added");
            }
        }

        private void OnTradeAdded(Trade trade)
        {
            lock (sync)
            {
                if (pendingEntry == null || trade == null || string.IsNullOrWhiteSpace(trade.PositionId))
                    return;
                var position = Core.Instance.GetPositionById(trade.PositionId, CurrentSymbol.ConnectionId);
                if (position != null)
                    TryAttachPendingPosition(position, "trade_added");
            }
        }

        private void RepairPendingEntry()
        {
            if (pendingEntry == null || pendingEntry.PositionAttached)
                return;
            var candidates = Core.Instance.Positions.Where(PositionMatchesPending).ToArray();
            if (candidates.Length == 1)
            {
                TryAttachPendingPosition(candidates[0], "pending_scan");
                return;
            }
            if ((DateTime.UtcNow - pendingEntry.SubmittedUtc).TotalSeconds > 30 && candidates.Length > 1)
            {
                Audit("fill_ambiguous", pendingEntry.Signal, "candidate_count=" + candidates.Length + " fail_closed_no_adoption");
                CommitEvent(pendingEntry.Signal.EventId, string.Empty, "ambiguous_fill_not_adopted");
                pendingEntry = null;
                ReleaseGlobalEntryOwnership();
                return;
            }
            if ((DateTime.UtcNow - pendingEntry.SubmittedUtc).TotalSeconds > 60 && candidates.Length == 0)
            {
                Audit("fill_timeout", pendingEntry.Signal, "accepted order produced no discoverable position; event consumed to prevent duplicate entry");
                CommitEvent(pendingEntry.Signal.EventId, string.Empty, "accepted_no_position_timeout");
                pendingEntry = null;
                ReleaseGlobalEntryOwnership();
            }
        }

        private bool PositionMatchesPending(Position position)
        {
            if (pendingEntry == null || position == null)
                return false;
            if (!SameAccount(position.Account) || !SameSymbol(position.Symbol) || position.Side != pendingEntry.Side)
                return false;
            var positionComment = ReadStringProperty(position, "Comment");
            if (!string.IsNullOrWhiteSpace(positionComment) && positionComment.IndexOf(pendingEntry.Tag, StringComparison.OrdinalIgnoreCase) < 0)
                return false;
            if (Math.Abs(position.Quantity - pendingEntry.Quantity) > QuantityTolerance())
                return false;
            return position.OpenTime.ToUniversalTime() >= pendingEntry.SubmittedUtc.AddSeconds(-3);
        }

        private void TryAttachPendingPosition(Position position, string reason)
        {
            if (pendingEntry == null || pendingEntry.PositionAttached || !PositionMatchesPending(position))
                return;
            pendingEntry.PositionAttached = true;
            var signal = pendingEntry.Signal;
            var state = new PositionState
            {
                EventId = signal.EventId,
                PositionId = position.Id,
                SourceTf = NormalizeTf(signal.SourceTf),
                Direction = signal.Direction,
                Entry = position.OpenPrice,
                Sl = signal.Sl,
                Tp = signal.Tp,
                HalfTrigger = signal.HalfTrigger,
                InitialQuantity = position.Quantity,
                OpenedUtc = position.OpenTime.ToUniversalTime(),
                ProtectionDeadlineUtc = DateTime.UtcNow.AddSeconds(Math.Max(2, ProtectionVerifySeconds)),
                LastKnownQuantity = position.Quantity
            };
            states[position.Id] = state;
            SaveState(state);

            string protectionDetail;
            if (!PlaceExactProtection(position, state, out protectionDetail))
            {
                state.EmergencyClose = FailIfExactProtectionFails;
                state.EmergencyReason = "initial_protection_failed";
                SaveState(state);
                Audit("protection_place_failed", signal, protectionDetail);
                if (state.EmergencyClose)
                    TryEmergencyClose(position, state);
            }
            else
            {
                state.ProtectionSubmitted = true;
                SaveState(state);
                Audit("position_adopted", signal, "reason=" + reason + " position=" + position.Id + " fill=" + position.OpenPrice + " " + protectionDetail);
            }

            if (PostFillRiskGuard && !PostFillRiskValid(position, state, signal.RiskPct, out protectionDetail))
            {
                state.EmergencyClose = true;
                state.EmergencyReason = "post_fill_risk";
                SaveState(state);
                Audit("post_fill_risk_failed", signal, protectionDetail);
                TryEmergencyClose(position, state);
            }

            CommitEvent(signal.EventId, position.Id, state.EmergencyClose ? "emergency_close" : "position_opened");
            pendingEntry = null;
            ReleaseGlobalEntryOwnership();
        }

        private bool PlaceExactProtection(Position position, PositionState state, out string detail)
        {
            detail = string.Empty;
            CancelPositionProtectionOrders(position.Id);
            var closeSide = position.Side == Side.Buy ? Side.Sell : Side.Buy;
            var stopType = CurrentSymbol.GetAlowedOrderTypes(OrderTypeUsage.CloseOrder).FirstOrDefault(x => x.Behavior == OrderTypeBehavior.Stop);
            var limitType = CurrentSymbol.GetAlowedOrderTypes(OrderTypeUsage.CloseOrder).FirstOrDefault(x => x.Behavior == OrderTypeBehavior.Limit);
            if (stopType == null || limitType == null)
            {
                detail = "close order types unavailable stop=" + (stopType != null) + " limit=" + (limitType != null);
                return false;
            }

            var stopRequest = ProtectionRequest(position, closeSide, stopType.Id, state, "SL");
            stopRequest.TriggerPrice = state.Sl;
            var stopResult = PlaceProtectionWithFallback(stopRequest);
            if (stopResult.Status == TradingOperationResultStatus.Failure)
            {
                detail = "sl_failed=" + Safe(stopResult.Message);
                return false;
            }

            var tpRequest = ProtectionRequest(position, closeSide, limitType.Id, state, "TP");
            tpRequest.Price = state.Tp;
            var tpResult = PlaceProtectionWithFallback(tpRequest);
            if (tpResult.Status == TradingOperationResultStatus.Failure)
            {
                CancelPositionProtectionOrders(position.Id);
                detail = "tp_failed=" + Safe(tpResult.Message);
                return false;
            }
            detail = "exact_sl=" + state.Sl + " exact_tp=" + state.Tp + " qty=" + position.Quantity;
            return true;
        }

        private PlaceOrderRequestParameters ProtectionRequest(Position position, Side side, string orderTypeId, PositionState state, string role)
        {
            var request = new PlaceOrderRequestParameters
            {
                Account = CurrentAccount,
                Symbol = CurrentSymbol,
                Side = side,
                Quantity = position.Quantity,
                PositionId = position.Id,
                OrderTypeId = orderTypeId,
                // Let the active Quantower connector choose its supported protection TIF.
                TimeInForce = TimeInForce.Default,
                Comment = BuildStateTag(state, role)
            };
            if (UseReduceOnlyProtection)
            {
                request.AdditionalParameters = new List<SettingItem>
                {
                    new SettingItemBoolean(OrderType.REDUCE_ONLY, true)
                };
            }
            return request;
        }

        private TradingOperationResult PlaceProtectionWithFallback(PlaceOrderRequestParameters request)
        {
            var result = Core.Instance.PlaceOrder(request);
            if (result.Status != TradingOperationResultStatus.Failure || !UseReduceOnlyProtection || !AllowReduceOnlyFallback)
                return result;
            request.AdditionalParameters = null;
            return Core.Instance.PlaceOrder(request);
        }

        private void VerifyProtectionAndRisk()
        {
            foreach (var state in states.Values.ToArray())
            {
                var position = FindPosition(state.PositionId);
                if (position == null)
                    continue;
                state.LastKnownQuantity = position.Quantity;
                if (state.EmergencyClose)
                    continue;
                if (DateTime.UtcNow < state.ProtectionDeadlineUtc)
                    continue;
                string detail;
                if (ProtectionIsExact(position, state, out detail))
                {
                    if (!state.ProtectionVerified)
                    {
                        state.ProtectionVerified = true;
                        SaveState(state);
                        AuditState("protection_verified", state, detail);
                    }
                    continue;
                }

                if (state.ProtectionRepairAttempts < 2)
                {
                    state.ProtectionRepairAttempts++;
                    state.ProtectionDeadlineUtc = DateTime.UtcNow.AddSeconds(Math.Max(2, ProtectionVerifySeconds));
                    if (PlaceExactProtection(position, state, out detail))
                    {
                        SaveState(state);
                        AuditState("protection_repair_submitted", state, detail);
                        continue;
                    }
                    SaveState(state);
                }

                if (FailIfExactProtectionFails)
                {
                    state.EmergencyClose = true;
                    state.EmergencyReason = "protection_verification_failed";
                    SaveState(state);
                    AuditState("protection_verification_failed", state, detail);
                }
            }
        }

        private bool ProtectionIsExact(Position position, PositionState state, out string detail)
        {
            var slOrder = position.StopLoss;
            var tpOrder = position.TakeProfit;
            var tolerance = Math.Max(CurrentSymbol.GetTickSize(position.OpenPrice), 0.00000001) * 1.1;
            var slPrice = slOrder == null ? 0 : slOrder.TriggerPrice;
            var tpPrice = tpOrder == null ? 0 : tpOrder.Price;
            var valid = slOrder != null && tpOrder != null && Math.Abs(slPrice - state.Sl) <= tolerance && Math.Abs(tpPrice - state.Tp) <= tolerance;
            detail = "position=" + position.Id + " sl_actual=" + slPrice + " sl_expected=" + state.Sl + " tp_actual=" + tpPrice + " tp_expected=" + state.Tp;
            return valid;
        }

        private void ManageHcbe()
        {
            if (!ManageHalfCloseBe)
                return;
            foreach (var state in states.Values.ToArray())
            {
                if (state.Done || state.EmergencyClose || state.HalfTrigger <= 0)
                    continue;
                var position = FindPosition(state.PositionId);
                if (position == null)
                    continue;

                var triggerHit = state.Direction > 0 ? CurrentSymbol.Bid >= state.HalfTrigger : CurrentSymbol.Ask <= state.HalfTrigger;
                if (!state.PartialClosed && !triggerHit)
                    continue;

                if (!state.PartialClosed)
                {
                    var closeQuantity = NormalizeQuantity(position.Quantity * Clamp(HalfCloseFraction, 0.05, 0.95));
                    var remainder = NormalizeQuantity(position.Quantity - closeQuantity);
                    if (closeQuantity < CurrentSymbol.MinLot || remainder < CurrentSymbol.MinLot)
                    {
                        state.PartialClosed = true;
                        state.PartialSkipped = true;
                    }
                    else
                    {
                        var closeResult = Core.Instance.ClosePosition(position, closeQuantity);
                        if (closeResult.Status == TradingOperationResultStatus.Failure)
                        {
                            AuditState("hcbe_half_close_failed", state, Safe(closeResult.Message));
                            continue;
                        }
                        state.PartialClosed = true;
                        state.PartialClosedUtc = DateTime.UtcNow;
                    }
                    SaveState(state);
                    if (!state.PartialSkipped)
                        continue;
                }

                if (!state.PartialSkipped && position.Quantity >= state.InitialQuantity - QuantityTolerance())
                {
                    if ((DateTime.UtcNow - state.PartialClosedUtc).TotalSeconds <= 10)
                        continue;
                    state.HcbeRepairAttempts++;
                    SaveState(state);
                    if (FailClosedOnHcbeRepair && state.HcbeRepairAttempts >= 5)
                    {
                        state.EmergencyClose = true;
                        state.EmergencyReason = "partial_close_not_reflected";
                        SaveState(state);
                    }
                    continue;
                }

                string repairDetail;
                if (RepairAfterHalfClose(position, state, out repairDetail))
                {
                    state.Done = true;
                    state.BeApplied = true;
                    SaveState(state);
                    AuditState("hcbe_complete", state, repairDetail);
                }
                else
                {
                    state.HcbeRepairAttempts++;
                    SaveState(state);
                    AuditState("hcbe_repair_pending", state, repairDetail);
                    if (FailClosedOnHcbeRepair && state.HcbeRepairAttempts >= 5)
                    {
                        state.EmergencyClose = true;
                        state.EmergencyReason = "hcbe_repair_failed";
                        SaveState(state);
                    }
                }
            }
        }

        private bool RepairAfterHalfClose(Position position, PositionState state, out string detail)
        {
            detail = string.Empty;
            var remaining = position.Quantity;
            if (remaining <= 0)
                return true;
            if (position.StopLoss == null || position.TakeProfit == null)
            {
                state.Sl = RoundPrice(position.OpenPrice);
                return PlaceExactProtection(position, state, out detail);
            }

            var be = RoundPrice(position.OpenPrice);
            var slResult = Core.Instance.ModifyOrder(position.StopLoss, TimeInForce.Default, remaining, -1, be, -1);
            if (slResult.Status == TradingOperationResultStatus.Failure)
            {
                detail = "be_modify_failed=" + Safe(slResult.Message);
                return false;
            }
            var tpResult = Core.Instance.ModifyOrder(position.TakeProfit, TimeInForce.Default, remaining, state.Tp, -1, -1);
            if (tpResult.Status == TradingOperationResultStatus.Failure)
            {
                detail = "tp_resize_failed=" + Safe(tpResult.Message);
                return false;
            }
            state.Sl = be;
            detail = "be=" + be + " remaining=" + remaining;
            return true;
        }

        private void ManageEmergencyCloses()
        {
            foreach (var state in states.Values.Where(x => x.EmergencyClose).ToArray())
            {
                var position = FindPosition(state.PositionId);
                if (position == null)
                    continue;
                if (DateTime.UtcNow < state.NextEmergencyAttemptUtc)
                    continue;
                TryEmergencyClose(position, state);
            }
        }

        private void TryEmergencyClose(Position position, PositionState state)
        {
            CancelPositionProtectionOrders(position.Id);
            var result = Core.Instance.ClosePosition(position);
            if (result.Status == TradingOperationResultStatus.Failure)
            {
                state.NextEmergencyAttemptUtc = DateTime.UtcNow.AddSeconds(2);
                SaveState(state);
                AuditState("emergency_close_failed", state, Safe(result.Message));
            }
            else
            {
                AuditState("emergency_close_sent", state, state.EmergencyReason);
            }
        }

        private bool ProcessCloseOnly(BridgeSignal signal, out string detail)
        {
            bool committed;
            if (!ClaimEvent(signal.EventId, out committed))
            {
                detail = committed ? "already_committed" : "claim_pending";
                return committed;
            }
            var targets = states.Values.Where(x => x.Direction == signal.Direction && SameText(x.SourceTf, NormalizeTf(signal.SourceTf))).ToArray();
            var failed = 0;
            foreach (var state in targets)
            {
                var position = FindPosition(state.PositionId);
                if (position == null)
                    continue;
                CancelPositionProtectionOrders(position.Id);
                var result = Core.Instance.ClosePosition(position);
                if (result.Status == TradingOperationResultStatus.Failure)
                    failed++;
                state.EmergencyClose = true;
                state.EmergencyReason = "close_only_followup";
                state.NextEmergencyAttemptUtc = DateTime.UtcNow.AddSeconds(2);
                SaveState(state);
            }
            detail = "found=" + targets.Length + " failed=" + failed;
            if (failed == 0)
                CommitEvent(signal.EventId, string.Empty, "close_only");
            else
                ReleaseEvent(signal.EventId);
            return failed == 0;
        }

        private bool CloseReversePositions(BridgeSignal signal, out string detail)
        {
            var targets = states.Values.Where(x => x.Direction != signal.Direction && SameText(x.SourceTf, NormalizeTf(signal.SourceTf))).ToArray();
            var failed = 0;
            var pending = 0;
            foreach (var state in targets)
            {
                var position = FindPosition(state.PositionId);
                if (position == null)
                    continue;
                CancelPositionProtectionOrders(position.Id);
                var result = Core.Instance.ClosePosition(position);
                if (result.Status == TradingOperationResultStatus.Failure)
                    failed++;
                else
                {
                    state.EmergencyClose = true;
                    state.EmergencyReason = "reverse_close_followup";
                    state.NextEmergencyAttemptUtc = DateTime.UtcNow.AddSeconds(2);
                    SaveState(state);
                    pending++;
                }
            }
            detail = "reverse_found=" + targets.Length + " failed=" + failed + " pending=" + pending;
            return failed == 0 && pending == 0;
        }

        private void OnPositionRemoved(Position position)
        {
            lock (sync)
            {
                if (position == null)
                    return;
                PositionState state;
                if (!states.TryGetValue(position.Id, out state))
                    return;
                AuditState("position_removed", state, "position=" + position.Id);
                states.Remove(position.Id);
                DeleteState(state);
            }
        }

        private double ResolveQuantity(BridgeSignal signal, double entry, out double estimatedRisk, out string detail)
        {
            estimatedRisk = 0;
            if (!UseRiskQuantity)
            {
                var manual = NormalizeQuantity(ManualQuantity);
                detail = "manual_quantity=" + manual;
                return manual;
            }

            var riskPercent = UseBridgeRiskPercent && signal.RiskPct > 0 ? signal.RiskPct : LocalRiskPercent;
            var capital = FixedRiskCapital > 0 ? FixedRiskCapital : CurrentAccount.Balance;
            var riskMoney = capital * Math.Max(0, riskPercent) / 100.0;
            var riskPerUnit = RiskForQuantity(entry, signal.Sl, 1.0);
            if (riskMoney <= 0 || riskPerUnit <= 0 || double.IsNaN(riskPerUnit) || double.IsInfinity(riskPerUnit))
            {
                detail = "risk_unavailable capital=" + capital + " risk_pct=" + riskPercent + " risk_per_unit=" + riskPerUnit;
                return 0;
            }
            var raw = riskMoney / riskPerUnit;
            var quantity = NormalizeQuantity(raw);
            if (MaxQuantity > 0)
                quantity = Math.Min(quantity, NormalizeQuantity(MaxQuantity));
            if (CurrentSymbol.MaxLot > 0)
                quantity = Math.Min(quantity, CurrentSymbol.MaxLot);

            var minimumRisk = RiskForQuantity(entry, signal.Sl, CurrentSymbol.MinLot);
            if (quantity < CurrentSymbol.MinLot || (BlockIfMinimumExceedsRisk && minimumRisk > riskMoney * 1.001))
            {
                detail = "minimum_exceeds_risk raw=" + raw + " min=" + CurrentSymbol.MinLot + " min_risk=" + minimumRisk + " allowed=" + riskMoney;
                return 0;
            }
            estimatedRisk = RiskForQuantity(entry, signal.Sl, quantity);
            detail = "capital=" + capital + " risk_pct=" + riskPercent + " allowed=" + riskMoney + " qty=" + quantity + " estimated=" + estimatedRisk;
            return quantity;
        }

        private bool PostFillRiskValid(Position position, PositionState state, double bridgeRiskPercent, out string detail)
        {
            var riskPercent = UseBridgeRiskPercent && bridgeRiskPercent > 0 ? bridgeRiskPercent : LocalRiskPercent;
            var capital = FixedRiskCapital > 0 ? FixedRiskCapital : CurrentAccount.Balance;
            var allowed = capital * Math.Max(0, riskPercent) / 100.0;
            var actual = RiskForQuantity(position.OpenPrice, state.Sl, position.Quantity);
            var maximum = allowed * (1.0 + Math.Max(0, MaxRiskOvershootPercent) / 100.0);
            detail = "allowed=" + allowed.ToString("F2", CultureInfo.InvariantCulture) + " actual=" + actual.ToString("F2", CultureInfo.InvariantCulture) + " max=" + maximum.ToString("F2", CultureInfo.InvariantCulture);
            return allowed > 0 && actual > 0 && actual <= maximum;
        }

        private double RiskForQuantity(double entry, double sl, double quantity)
        {
            try
            {
                var pnl = Core.Instance.CalculatePnL(new PnLRequestParameters
                {
                    Account = CurrentAccount,
                    Symbol = CurrentSymbol,
                    Side = sl < entry ? Side.Buy : Side.Sell,
                    Quantity = quantity,
                    OpenPrice = entry,
                    ClosePrice = sl
                });
                var calculated = pnl == null || pnl.GrossPnL == null ? 0 : Math.Abs(pnl.GrossPnL.Value);
                if (calculated > 0 && !double.IsNaN(calculated) && !double.IsInfinity(calculated))
                    return calculated;
            }
            catch
            {
                // Some connectors do not expose pre-trade PnL conversion.
            }

            var tickSize = CurrentSymbol.GetTickSize(entry);
            var tickCost = Math.Abs(CurrentSymbol.GetTickCost(entry));
            if (tickSize <= 0 || tickCost <= 0 || quantity <= 0)
                return 0;
            return Math.Abs(entry - sl) / tickSize * tickCost * quantity;
        }

        private double NormalizeQuantity(double quantity)
        {
            var min = Math.Max(0, CurrentSymbol.MinLot);
            var step = CurrentSymbol.LotStep > 0 ? CurrentSymbol.LotStep : (min > 0 ? min : 1);
            if (quantity < min)
                return 0;
            var normalized = min + Math.Floor((quantity - min + 1e-12) / step) * step;
            if (CurrentSymbol.MaxLot > 0)
                normalized = Math.Min(normalized, CurrentSymbol.MaxLot);
            return Math.Max(0, normalized);
        }

        private bool HasUnownedExposure()
        {
            var owned = new HashSet<string>(states.Keys, StringComparer.Ordinal);
            return Core.Instance.Positions.Any(x => SameAccount(x.Account) && SameSymbol(x.Symbol) && !owned.Contains(x.Id));
        }

        private bool IsNettingAccount()
        {
            var value = CurrentAccount.NettingType.ToString();
            if (ContainsText(value, "hedg") || ContainsText(value, "multiple"))
                return false;
            return true;
        }

        private string GlobalEntryKey()
        {
            return CurrentAccount.ConnectionId + "|" + CurrentAccount.Id + "|" + CurrentSymbol.ConnectionId + "|" + CurrentSymbol.Id;
        }

        private bool TryAcquireGlobalEntryOwnership()
        {
            lock (GlobalEntrySync)
            {
                var key = GlobalEntryKey();
                string owner;
                if (GlobalEntryOwners.TryGetValue(key, out owner) && !SameText(owner, scopeToken))
                    return false;
                GlobalEntryOwners[key] = scopeToken;
                return true;
            }
        }

        private void ReleaseGlobalEntryOwnership()
        {
            if (CurrentAccount == null || CurrentSymbol == null || string.IsNullOrWhiteSpace(scopeToken))
                return;
            lock (GlobalEntrySync)
            {
                var key = GlobalEntryKey();
                string owner;
                if (GlobalEntryOwners.TryGetValue(key, out owner) && SameText(owner, scopeToken))
                    GlobalEntryOwners.Remove(key);
            }
        }

        private void CancelPositionProtectionOrders(string positionId)
        {
            foreach (var order in Core.Instance.Orders.Where(x => SameText(x.PositionId, positionId)).ToArray())
                Core.Instance.CancelOrder((IOrder)order);
        }

        private Position FindPosition(string id)
        {
            if (string.IsNullOrWhiteSpace(id))
                return null;
            var position = Core.Instance.GetPositionById(id, CurrentSymbol.ConnectionId);
            return position != null && SameAccount(position.Account) && SameSymbol(position.Symbol) ? position : null;
        }

        private void RepairTrackedPositions(string reason)
        {
            foreach (var state in states.Values.ToArray())
            {
                var position = FindPosition(state.PositionId);
                if (position == null)
                {
                    states.Remove(state.PositionId);
                    DeleteState(state);
                    AuditState("stale_state_removed", state, reason);
                }
            }
        }

        private void LoadPositionStates()
        {
            states.Clear();
            foreach (var path in Directory.GetFiles(stateDirectory, "*.state"))
            {
                try
                {
                    var state = PositionState.Parse(File.ReadAllText(path));
                    if (state != null && !string.IsNullOrWhiteSpace(state.PositionId))
                        states[state.PositionId] = state;
                }
                catch (Exception ex)
                {
                    AuditRaw("state_load_failed", Path.GetFileName(path) + " " + ex.Message);
                }
            }
        }

        private void SaveState(PositionState state)
        {
            AtomicWrite(StatePath(state), state.Serialize());
        }

        private void DeleteState(PositionState state)
        {
            try { File.Delete(StatePath(state)); } catch { }
        }

        private string StatePath(PositionState state)
        {
            return Path.Combine(stateDirectory, HashText(state.PositionId).Substring(0, 20) + ".state");
        }

        private bool ClaimEvent(string eventId, out bool committed)
        {
            committed = false;
            var path = EventPath(eventId);
            if (File.Exists(path))
            {
                try
                {
                    var payload = File.ReadAllText(path);
                    if (payload.StartsWith("committed\t", StringComparison.Ordinal) && payload.Contains("\t" + eventId))
                    {
                        committed = true;
                        return false;
                    }
                    if ((DateTime.UtcNow - File.GetLastWriteTimeUtc(path)).TotalSeconds < PendingLockSeconds)
                        return false;
                    File.Delete(path);
                }
                catch { return false; }
            }
            try
            {
                using (var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
                    writer.Write("pending\t" + DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture) + "\t" + eventId);
                return true;
            }
            catch (IOException) { return false; }
        }

        private void CommitEvent(string eventId, string positionId, string status)
        {
            AtomicWrite(EventPath(eventId), "committed\t" + DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture) + "\t" + eventId + "\t" + positionId + "\t" + status);
        }

        private void ReleaseEvent(string eventId)
        {
            try { File.Delete(EventPath(eventId)); } catch { }
        }

        private string EventPath(string eventId)
        {
            return Path.Combine(eventLockDirectory, HashText(eventId).Substring(0, 24) + ".lock");
        }

        private void BlockRetry(string eventId, int seconds)
        {
            retryAfter[eventId] = DateTime.UtcNow.AddSeconds(Math.Max(5, seconds));
        }

        private bool TryReadSignal(out BridgeSignal signal, out string detail)
        {
            signal = new BridgeSignal();
            var path = ResolveBridgeReadPath();
            string text;
            if (!TryReadStable(path, out text, out detail))
                return false;
            var fields = ParseCsvFlat(text);
            if (fields.Count < 17)
            {
                detail = "not_enough_fields=" + fields.Count + " file=" + path;
                return false;
            }

            var offset = 0;
            if (SameText(fields[0], "version"))
            {
                offset = 17;
                if (fields.Count > 17 && SameText(fields[17], "risk_pct")) offset = 18;
                if (fields.Count > 18 && SameText(fields[18], "bridge_channel")) offset = 19;
            }
            if (fields.Count < offset + 17)
            {
                detail = "missing_data_row fields=" + fields.Count + " offset=" + offset;
                return false;
            }

            signal.Version = fields[offset];
            signal.WrittenGmt = ParseDate(fields[offset + 1]);
            signal.SourceLogin = fields[offset + 2];
            signal.SourceSymbol = fields[offset + 3];
            signal.SourceTf = fields[offset + 4];
            signal.EventId = fields[offset + 5];
            signal.Source = fields[offset + 6];
            var rawDirection = fields[offset + 7];
            signal.Direction = SameText(rawDirection, "BUY") ? 1 : SameText(rawDirection, "SELL") ? -1 : 0;
            signal.SignalTime = ParseDate(fields[offset + 8]);
            signal.BridgeEntry = ParseDouble(fields[offset + 9]);
            signal.Sl = ParseDouble(fields[offset + 10]);
            signal.Tp = ParseDouble(fields[offset + 11]);
            signal.HalfTrigger = ParseDouble(fields[offset + 12]);
            signal.HalfLabel = fields[offset + 13];
            signal.SourceBuild = fields[offset + 14];
            signal.SourceBid = ParseDouble(fields[offset + 15]);
            signal.SourceAsk = ParseDouble(fields[offset + 16]);
            signal.RiskPct = fields.Count > offset + 17 ? ParseDouble(fields[offset + 17]) : 0;
            signal.Channel = fields.Count > offset + 18 ? ParseInt(fields[offset + 18]) : 0;
            signal.ReadPath = path;

            if (signal.WrittenGmt == DateTime.MinValue || string.IsNullOrWhiteSpace(signal.EventId) || signal.Direction == 0)
            {
                detail = "invalid_or_init dir=" + rawDirection + " source=" + signal.Source + " file=" + Path.GetFileName(path);
                return false;
            }
            detail = "read_ok file=" + Path.GetFileName(path) + " event=" + ShortEvent(signal.EventId);
            return true;
        }

        private bool SignalIdentityMatches(BridgeSignal signal, out string reason)
        {
            if (signal.Channel != BridgeChannel)
            {
                reason = "channel source=" + signal.Channel + " expected=" + BridgeChannel;
                return false;
            }
            var expectedSource = ExpectedSourceNamespace();
            if (string.IsNullOrWhiteSpace(signal.Source) || !signal.Source.StartsWith(expectedSource, StringComparison.OrdinalIgnoreCase))
            {
                reason = "source=" + signal.Source + " expected=" + expectedSource;
                return false;
            }
            if (RequireAcceptedSignalSeal && !IsCloseOnlySignal(signal) && !ContainsText(signal.Source, "|ACCEPTED1"))
            {
                reason = "acceptance_seal_missing source=" + signal.Source;
                return false;
            }
            if (!string.IsNullOrWhiteSpace(SourceTimeframeFilter) && !SameText(NormalizeTf(signal.SourceTf), NormalizeTf(SourceTimeframeFilter)))
            {
                reason = "tf=" + signal.SourceTf + " expected=" + SourceTimeframeFilter;
                return false;
            }
            var sourceCanonical = CanonicalSymbol(signal.SourceSymbol);
            var targetCanonical = CanonicalTargetSymbol();
            if (RequireSourceMatchesTarget && (string.IsNullOrWhiteSpace(sourceCanonical)
                || string.IsNullOrWhiteSpace(targetCanonical)
                || !SameText(sourceCanonical, targetCanonical)))
            {
                reason = "symbol_filter source=" + signal.SourceSymbol + " canonical_source=" + sourceCanonical
                    + " target=" + CurrentSymbol.Name + " canonical_target=" + targetCanonical;
                return false;
            }
            reason = string.Empty;
            return true;
        }

        private string ResolveBridgeReadPath()
        {
            var configured = resolvedBridgePath ?? ExpandPath(BridgeLatestPath);
            if (string.IsNullOrWhiteSpace(configured))
                return configured;
            var directory = Path.GetDirectoryName(configured) ?? string.Empty;
            var fileName = Path.GetFileName(configured) ?? string.Empty;
            var extension = Path.GetExtension(fileName);
            var withoutExtension = Path.GetFileNameWithoutExtension(fileName);
            var latestIndex = withoutExtension.IndexOf("_Latest", StringComparison.OrdinalIgnoreCase);
            if (latestIndex < 0)
                return configured;
            var productStem = withoutExtension.Substring(0, latestIndex);
            var latestStem = productStem + "_Latest" + (BridgeChannel > 0 ? "_C" + BridgeChannel.ToString(CultureInfo.InvariantCulture) : string.Empty);
            var generic = Path.Combine(directory, latestStem + extension);
            if (!PreferScopedLatest || string.IsNullOrWhiteSpace(SourceTimeframeFilter))
                return generic;

            string newest = null;
            var newestWrite = DateTime.MinValue;
            foreach (var alias in SourceAliases())
            {
                var candidate = Path.Combine(directory, latestStem + "_" + Sanitize(alias) + "_" + NormalizeTf(SourceTimeframeFilter) + extension);
                if (!File.Exists(candidate))
                    continue;
                DateTime write;
                try { write = File.GetLastWriteTimeUtc(candidate); } catch { continue; }
                if (newest == null || write > newestWrite)
                {
                    newest = candidate;
                    newestWrite = write;
                }
            }
            return newest ?? generic;
        }

        private IEnumerable<string> SourceAliases()
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var part in (SourceSymbolAliasesCsv ?? string.Empty).Replace(';', ',').Split(','))
            {
                var value = part.Trim();
                if (value.Length > 0 && seen.Add(value)) yield return value;
            }
            var canonical = CanonicalTargetSymbol();
            foreach (var value in InferredAliases(canonical))
                if (seen.Add(value)) yield return value;
        }

        private static IEnumerable<string> InferredAliases(string canonical)
        {
            if (canonical == "BTCUSD") return new[] { "BTCUSDm", "BTCUSD", "BTCUSDT", "XBTUSD" };
            if (canonical == "JP225") return new[] { "JP225m", "JP225", "JPN225m", "JPN225" };
            if (canonical == "US500") return new[] { "US500m", "US500", "SPX500m", "SPX500" };
            if (canonical == "USTEC") return new[] { "USTECm", "USTEC", "US100m", "US100", "NAS100" };
            if (canonical == "US30") return new[] { "US30m", "US30", "DJ30" };
            if (canonical == "DE30") return new[] { "DE30m", "DE30", "GER40", "GER30", "DAX40" };
            if (canonical == "HK50") return new[] { "HK50m", "HK50", "HSI" };
            return new[] { canonical, canonical + "m" };
        }

        private bool ShouldRebase(BridgeSignal signal)
        {
            if (!RebaseLevelsToLive || signal.BridgeEntry <= 0 || signal.Sl <= 0 || signal.Tp <= 0)
                return false;
            if (!RebaseOnlyIfSymbolDiffers)
                return true;
            return !SameText(Sanitize(signal.SourceSymbol), Sanitize(CurrentSymbol.Name));
        }

        private static BridgeSignal Rebase(BridgeSignal signal, double liveEntry)
        {
            var oldEntry = signal.BridgeEntry;
            if (signal.Direction > 0)
            {
                signal.Sl = liveEntry - Math.Abs(oldEntry - signal.Sl);
                signal.Tp = liveEntry + Math.Abs(signal.Tp - oldEntry);
                if (signal.HalfTrigger > 0) signal.HalfTrigger = liveEntry + Math.Abs(signal.HalfTrigger - oldEntry);
            }
            else
            {
                signal.Sl = liveEntry + Math.Abs(signal.Sl - oldEntry);
                signal.Tp = liveEntry - Math.Abs(oldEntry - signal.Tp);
                if (signal.HalfTrigger > 0) signal.HalfTrigger = liveEntry - Math.Abs(oldEntry - signal.HalfTrigger);
            }
            signal.BridgeEntry = liveEntry;
            return signal;
        }

        private static bool ValidGeometry(int direction, double entry, double sl, double tp)
        {
            if (entry <= 0 || sl <= 0 || tp <= 0)
                return false;
            return direction > 0 ? sl < entry && tp > entry : sl > entry && tp < entry;
        }

        private double RoundPrice(double price)
        {
            return CurrentSymbol.RoundPriceToTickSize(price, CurrentSymbol.GetTickSize(price));
        }

        private bool SameAccount(Account account)
        {
            return account != null && CurrentAccount != null && SameText(account.ConnectionId, CurrentAccount.ConnectionId) && SameText(account.Id, CurrentAccount.Id);
        }

        private bool SameSymbol(Symbol symbol)
        {
            return symbol != null && CurrentSymbol != null && SameText(symbol.ConnectionId, CurrentSymbol.ConnectionId) && SameText(symbol.Id, CurrentSymbol.Id);
        }

        private string ScopeIdentity()
        {
            return CurrentAccount.ConnectionId + "|" + CurrentAccount.Id + "|" + CurrentSymbol.ConnectionId + "|" + CurrentSymbol.Id + "|" + ExpectedSourceNamespace() + "|" + NormalizeTf(SourceTimeframeFilter) + "|C" + BridgeChannel + "|" + (resolvedBridgePath ?? string.Empty).ToUpperInvariant();
        }

        private string ExpectedSourceNamespace()
        {
            var source = (SourceFilter ?? string.Empty).Trim();
            return source.EndsWith("|", StringComparison.Ordinal) ? source : source + "|";
        }

        private string BuildOrderTag(BridgeSignal signal)
        {
            return Sanitize(InstanceLabel).Substring(0, Math.Min(8, Sanitize(InstanceLabel).Length)) + "|" + scopeToken.Substring(0, 6) + "|" + HashText(signal.EventId).Substring(0, 10);
        }

        private string BuildStateTag(PositionState state, string role)
        {
            return Sanitize(InstanceLabel) + "|" + scopeToken.Substring(0, 6) + "|" + role + "|" + HashText(state.EventId).Substring(0, 8);
        }

        private static bool IsCloseOnlySignal(BridgeSignal signal)
        {
            return ContainsText(signal.Source, "CloseOnly") || ContainsText(signal.EventId, "invalidate_close");
        }

        private static bool IsMarketClosed(string message)
        {
            return ContainsText(message, "market is closed") || ContainsText(message, "market closed") || ContainsText(message, "trading is not available") || ContainsText(message, "not trading");
        }

        private string CanonicalTargetSymbol()
        {
            return CanonicalSymbol(CurrentSymbol == null ? string.Empty : CurrentSymbol.Name);
        }

        private static string CanonicalSymbol(string value)
        {
            var s = Sanitize(value).ToUpperInvariant();
            if (s.Contains("BTCUSD") || s.Contains("BTCUSDT") || s.Contains("XBTUSD")) return "BTCUSD";
            if (s.Contains("JP225") || s.Contains("JPN225")) return "JP225";
            if (s.Contains("US500") || s.Contains("SPX500") || s.Contains("SP500")) return "US500";
            if (s.Contains("USTEC") || s.Contains("US100") || s.Contains("NAS100")) return "USTEC";
            if (s.Contains("US30") || s.Contains("DJ30")) return "US30";
            if (s.Contains("DE30") || s.Contains("GER30") || s.Contains("GER40") || s.Contains("DAX40")) return "DE30";
            if (s.Contains("HK50")) return "HK50";
            if (s.Contains("USOIL") || s.Contains("WTI")) return "USOIL";
            if (s.Contains("UKOIL") || s.Contains("BRENT")) return "UKOIL";

            var root = FuturesContractRoot(value);
            if (root == "BTC" || root == "MBT") return "BTCUSD";
            if (root == "NKD" || root == "MNK" || root == "NIY") return "JP225";
            if (root == "ES" || root == "MES") return "US500";
            if (root == "NQ" || root == "MNQ") return "USTEC";
            if (root == "YM" || root == "MYM") return "US30";
            if (root == "FDAX" || root == "FDXM" || root == "DAX") return "DE30";
            if (root == "HSI" || root == "MHI") return "HK50";
            if (root == "CL" || root == "MCL") return "USOIL";
            if (root == "BZ" || root == "BRN") return "UKOIL";
            return s.EndsWith("M") && s.Length > 1 ? s.Substring(0, s.Length - 1) : s;
        }

        private static string FuturesContractRoot(string value)
        {
            var raw = (value ?? string.Empty).Trim().ToUpperInvariant();
            if (raw.Length == 0)
                return string.Empty;

            var tokens = raw.Split(new[] { ' ', '\t', '-', '_', '.', '/', '@', ':', '|' }, StringSplitOptions.RemoveEmptyEntries);
            var token = Sanitize(tokens.Length > 0 ? tokens[0] : raw).ToUpperInvariant();
            var roots = new[] { "FDXM", "FDAX", "MES", "MNQ", "MYM", "MCL", "MBT", "MNK", "MHI", "NKD", "NIY", "BRN", "BTC", "HSI", "DAX", "NQ", "ES", "YM", "CL", "BZ" };
            foreach (var root in roots)
            {
                if (!token.StartsWith(root, StringComparison.Ordinal))
                    continue;
                var suffix = token.Substring(root.Length);
                if (IsContractSuffix(suffix))
                    return root;
            }
            return string.Empty;
        }

        private static bool IsContractSuffix(string suffix)
        {
            if (string.IsNullOrEmpty(suffix))
                return true;
            if (suffix.All(char.IsDigit))
                return true;
            if ("FGHJKMNQUVXZ".IndexOf(suffix[0]) >= 0 && suffix.Substring(1).All(char.IsDigit))
                return true;
            var months = new[] { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };
            return months.Any(month => suffix.StartsWith(month, StringComparison.Ordinal)
                && suffix.Substring(month.Length).All(char.IsDigit));
        }

        private static string NormalizeTf(string value)
        {
            var s = (value ?? string.Empty).Trim().ToUpperInvariant();
            if (s.StartsWith("M")) s = s.Substring(1);
            if (s == "H1") return "60";
            if (s == "H2") return "120";
            if (s == "H4") return "240";
            if (s == "D1") return "1440";
            return s;
        }

        private void Heartbeat()
        {
            if (HeartbeatSeconds <= 0 || (DateTime.UtcNow - lastHeartbeatUtc).TotalSeconds < HeartbeatSeconds)
                return;
            lastHeartbeatUtc = DateTime.UtcNow;
            AuditRaw("heartbeat", "action=" + lastAction + " detail=" + lastDetail + " tracked=" + states.Count + " pending=" + (pendingEntry != null ? 1 : 0) + " file=" + ResolveBridgeReadPath());
        }

        private void SetAction(string action, string detail)
        {
            lastAction = action;
            lastDetail = detail ?? string.Empty;
        }

        private void LogStatus(string action, string detail)
        {
            SetAction(action, detail);
            Log("[" + CoreBuild + "] " + action + " " + detail);
            AuditRaw(action, detail);
        }

        private void Audit(string eventName, BridgeSignal signal, string detail)
        {
            SetAction(eventName, detail);
            AuditRaw(eventName, "source_symbol=" + signal.SourceSymbol + " source_tf=" + signal.SourceTf + " channel=" + signal.Channel + " event_id=" + signal.EventId + " dir=" + (signal.Direction > 0 ? "BUY" : "SELL") + " entry=" + signal.BridgeEntry + " sl=" + signal.Sl + " tp=" + signal.Tp + " half=" + signal.HalfTrigger + " " + detail);
        }

        private void AuditState(string eventName, PositionState state, string detail)
        {
            SetAction(eventName, detail);
            AuditRaw(eventName, "position=" + state.PositionId + " event_id=" + state.EventId + " tf=" + state.SourceTf + " dir=" + state.Direction + " entry=" + state.Entry + " sl=" + state.Sl + " tp=" + state.Tp + " half=" + state.HalfTrigger + " partial=" + state.PartialClosed + " be=" + state.BeApplied + " " + detail);
        }

        private void AuditRaw(string eventName, string detail)
        {
            if (!AuditEnabled || string.IsNullOrWhiteSpace(auditDirectory))
                return;
            try
            {
                var path = Path.Combine(auditDirectory, "QuantowerBridge_" + DateTime.UtcNow.ToString("yyyyMMdd", CultureInfo.InvariantCulture) + ".csv");
                var exists = File.Exists(path);
                using (var stream = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
                using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
                {
                    if (!exists)
                        writer.WriteLine("time_utc,build,scope,event,account,symbol,source,tf,channel,detail");
                    writer.WriteLine(Csv(DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)) + "," + Csv(CoreBuild) + "," + Csv(scopeToken) + "," + Csv(eventName) + "," + Csv(CurrentAccount == null ? "" : CurrentAccount.Id) + "," + Csv(CurrentSymbol == null ? "" : CurrentSymbol.Name) + "," + Csv(ExpectedSourceNamespace()) + "," + Csv(SourceTimeframeFilter) + "," + BridgeChannel.ToString(CultureInfo.InvariantCulture) + "," + Csv(detail));
                }
            }
            catch { }
        }

        private static bool TryReadStable(string path, out string text, out string detail)
        {
            text = string.Empty;
            detail = string.Empty;
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            {
                detail = "file_missing=" + path;
                return false;
            }
            for (var attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                    {
                        if (stream.Length <= 0 || stream.Length > 1024 * 1024)
                        {
                            detail = "invalid_file_size=" + stream.Length;
                            return false;
                        }
                        using (var reader = new StreamReader(stream, Encoding.UTF8, true))
                            text = reader.ReadToEnd();
                    }
                    if (!string.IsNullOrWhiteSpace(text)) return true;
                }
                catch (IOException) { Thread.Sleep(20); }
            }
            detail = "read_failed=" + path;
            return false;
        }

        internal static List<string> ParseCsvFlat(string text)
        {
            var fields = new List<string>();
            var current = new StringBuilder();
            var quoted = false;
            for (var i = 0; i < (text ?? string.Empty).Length; i++)
            {
                var ch = text[i];
                if (ch == '"')
                {
                    if (quoted && i + 1 < text.Length && text[i + 1] == '"') { current.Append('"'); i++; }
                    else quoted = !quoted;
                }
                else if (!quoted && (ch == ',' || ch == ';' || ch == '\n' || ch == '\r' || ch == '\t'))
                {
                    if (ch == '\r' && i + 1 < text.Length && text[i + 1] == '\n') i++;
                    fields.Add(current.ToString().Trim().TrimStart('\uFEFF'));
                    current.Clear();
                }
                else current.Append(ch);
            }
            if (current.Length > 0) fields.Add(current.ToString().Trim().TrimStart('\uFEFF'));
            return fields.Where((x, index) => x.Length > 0 || index < fields.Count - 1).ToList();
        }

        private static DateTime ParseDate(string value)
        {
            DateTime result;
            var formats = new[] { "yyyy.MM.dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "O", "s" };
            if (DateTime.TryParseExact(value, formats, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out result))
                return result;
            if (DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out result))
                return result;
            return DateTime.MinValue;
        }

        private static double ParseDouble(string value)
        {
            double result;
            return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out result) ? result : 0;
        }

        private static int ParseInt(string value)
        {
            int result;
            return int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out result) ? result : 0;
        }

        private static void AtomicWrite(string path, string content)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            var temp = path + ".tmp." + Guid.NewGuid().ToString("N");
            File.WriteAllText(temp, content ?? string.Empty, new UTF8Encoding(false));
            try
            {
                if (File.Exists(path))
                    File.Replace(temp, path, null);
                else
                    File.Move(temp, path);
            }
            catch
            {
                if (File.Exists(path)) File.Delete(path);
                File.Move(temp, path);
            }
            finally
            {
                try { if (File.Exists(temp)) File.Delete(temp); } catch { }
            }
        }

        private static string ExpandPath(string value)
        {
            return Environment.ExpandEnvironmentVariables((value ?? string.Empty).Trim());
        }

        private static string ReadStringProperty(object instance, string propertyName)
        {
            try
            {
                var property = instance == null ? null : instance.GetType().GetProperty(propertyName);
                var value = property == null ? null : property.GetValue(instance, null);
                return value == null ? string.Empty : value.ToString();
            }
            catch { return string.Empty; }
        }

        private static string HashText(string value)
        {
            using (var sha = SHA256.Create())
                return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(value ?? string.Empty))).Replace("-", string.Empty);
        }

        private static string Sanitize(string value)
        {
            var chars = (value ?? string.Empty).Where(char.IsLetterOrDigit).ToArray();
            return new string(chars);
        }

        private static string Csv(string value)
        {
            return "\"" + (value ?? string.Empty).Replace("\"", "\"\"").Replace("\r", " ").Replace("\n", " ") + "\"";
        }

        private static string Safe(string value) { return (value ?? string.Empty).Replace('\r', ' ').Replace('\n', ' '); }
        private static bool SameText(string a, string b) { return string.Equals(a ?? string.Empty, b ?? string.Empty, StringComparison.OrdinalIgnoreCase); }
        private static bool ContainsText(string value, string token) { return (value ?? string.Empty).IndexOf(token, StringComparison.OrdinalIgnoreCase) >= 0; }
        private static string ShortEvent(string value) { return string.IsNullOrWhiteSpace(value) ? "-" : value.Length <= 32 ? value : value.Substring(0, 32); }
        private static double Clamp(double value, double min, double max) { return Math.Max(min, Math.Min(max, value)); }
        private double QuantityTolerance() { return Math.Max(CurrentSymbol.LotStep, 0.00000001) * 0.25; }

        private sealed class PendingEntry
        {
            public BridgeSignal Signal;
            public Side Side;
            public double Quantity;
            public double EstimatedRisk;
            public DateTime SubmittedUtc;
            public DateTime AcceptedUtc;
            public string Tag;
            public bool Accepted;
            public bool PositionAttached;
        }

        internal sealed class BridgeSignal
        {
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
            public int Channel;
            public string ReadPath;
        }

        private sealed class PositionState
        {
            public string EventId = string.Empty;
            public string PositionId = string.Empty;
            public string SourceTf = string.Empty;
            public int Direction;
            public double Entry;
            public double Sl;
            public double Tp;
            public double HalfTrigger;
            public double InitialQuantity;
            public double LastKnownQuantity;
            public DateTime OpenedUtc;
            public bool ProtectionSubmitted;
            public bool ProtectionVerified;
            public int ProtectionRepairAttempts;
            public DateTime ProtectionDeadlineUtc;
            public bool PartialClosed;
            public bool PartialSkipped;
            public DateTime PartialClosedUtc;
            public bool BeApplied;
            public bool Done;
            public int HcbeRepairAttempts;
            public bool EmergencyClose;
            public string EmergencyReason = string.Empty;
            public DateTime NextEmergencyAttemptUtc;

            public string Serialize()
            {
                return string.Join("\t", new[]
                {
                    "v2", B64(EventId), B64(PositionId), B64(SourceTf), Direction.ToString(CultureInfo.InvariantCulture),
                    D(Entry), D(Sl), D(Tp), D(HalfTrigger), D(InitialQuantity), D(LastKnownQuantity), T(OpenedUtc),
                    B(ProtectionSubmitted), B(ProtectionVerified), ProtectionRepairAttempts.ToString(CultureInfo.InvariantCulture), T(ProtectionDeadlineUtc),
                    B(PartialClosed), B(PartialSkipped), T(PartialClosedUtc), B(BeApplied), B(Done), HcbeRepairAttempts.ToString(CultureInfo.InvariantCulture),
                    B(EmergencyClose), B64(EmergencyReason), T(NextEmergencyAttemptUtc)
                });
            }

            public static PositionState Parse(string text)
            {
                var p = (text ?? string.Empty).Split('\t');
                if (p.Length < 25 || p[0] != "v2") return null;
                return new PositionState
                {
                    EventId = UB64(p[1]), PositionId = UB64(p[2]), SourceTf = UB64(p[3]), Direction = I(p[4]),
                    Entry = N(p[5]), Sl = N(p[6]), Tp = N(p[7]), HalfTrigger = N(p[8]), InitialQuantity = N(p[9]), LastKnownQuantity = N(p[10]), OpenedUtc = DT(p[11]),
                    ProtectionSubmitted = Q(p[12]), ProtectionVerified = Q(p[13]), ProtectionRepairAttempts = I(p[14]), ProtectionDeadlineUtc = DT(p[15]),
                    PartialClosed = Q(p[16]), PartialSkipped = Q(p[17]), PartialClosedUtc = DT(p[18]), BeApplied = Q(p[19]), Done = Q(p[20]), HcbeRepairAttempts = I(p[21]),
                    EmergencyClose = Q(p[22]), EmergencyReason = UB64(p[23]), NextEmergencyAttemptUtc = DT(p[24])
                };
            }

            private static string B64(string x) { return Convert.ToBase64String(Encoding.UTF8.GetBytes(x ?? string.Empty)); }
            private static string UB64(string x) { return Encoding.UTF8.GetString(Convert.FromBase64String(x)); }
            private static string D(double x) { return x.ToString("R", CultureInfo.InvariantCulture); }
            private static double N(string x) { double v; return double.TryParse(x, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : 0; }
            private static string T(DateTime x) { return x == DateTime.MinValue ? "-" : x.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture); }
            private static DateTime DT(string x) { DateTime v; return x == "-" || !DateTime.TryParse(x, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out v) ? DateTime.MinValue : v.ToUniversalTime(); }
            private static string B(bool x) { return x ? "1" : "0"; }
            private static bool Q(string x) { return x == "1"; }
            private static int I(string x) { int v; return int.TryParse(x, NumberStyles.Integer, CultureInfo.InvariantCulture, out v) ? v : 0; }
        }
    }
}
