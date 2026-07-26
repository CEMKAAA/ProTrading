// TradeDay account-compliance extension. Execution only; no signal generation.
#region Using declarations
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using NinjaTrader.Cbi;
using NinjaTrader.Data;
#endregion

namespace NinjaTrader.NinjaScript.Strategies
{
    public enum TradeDayProgramType { QuickPay, FastPass }
    public enum TradeDayDrawdownMode { EndOfDay, Intraday }

    public abstract partial class ProductionFileBridgeNinjaCore
    {
        private const string TradeDayComplianceBuild = "2026-07-26.tradeday-compliance-v1";
        private static readonly object TradeDaySync = new object();
        private static readonly Dictionary<string, TradeDayLedger> TradeDayLedgers = new Dictionary<string, TradeDayLedger>(StringComparer.OrdinalIgnoreCase);
        private static readonly Dictionary<string, int> TradeDayActiveInstances = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        private static readonly HashSet<string> TradeDayKnownOrderPrefixes = new HashSet<string>(StringComparer.Ordinal);
        private static readonly HashSet<string> MicroContracts = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        { "MES", "MNQ", "MYM", "M2K", "MCL", "MGC", "SIL", "M6A", "M6B", "M6E", "M6J", "M6S", "MCD", "MBT", "MET", "MNG", "MHO", "FDXM" };

        #region TradeDay inputs
        [NinjaScriptProperty]
        [Display(Name = "TradeDay Compliance Enabled", GroupName = "11 TradeDay", Order = 0)]
        public bool TradeDayComplianceEnabled { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Program", GroupName = "11 TradeDay", Order = 1)]
        public TradeDayProgramType TradeDayProgram { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Drawdown Mode", GroupName = "11 TradeDay", Order = 2)]
        public TradeDayDrawdownMode TradeDayDrawdownType { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, double.MaxValue)]
        [Display(Name = "Challenge Starting Balance", GroupName = "11 TradeDay", Order = 3)]
        public double TradeDayStartingBalance { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, double.MaxValue)]
        [Display(Name = "Maximum Drawdown Amount", GroupName = "11 TradeDay", Order = 4)]
        public double TradeDayMaximumDrawdown { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, double.MaxValue)]
        [Display(Name = "Current Drawdown Floor Override", GroupName = "11 TradeDay", Order = 5)]
        public double TradeDayCurrentFloorOverride { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, double.MaxValue)]
        [Display(Name = "Drawdown Safety Buffer Cash", GroupName = "11 TradeDay", Order = 6)]
        public double TradeDayDrawdownSafetyBuffer { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Use Broker Trailing Floor", GroupName = "11 TradeDay", Order = 7)]
        public bool TradeDayUseBrokerTrailingFloor { get; set; }

        [NinjaScriptProperty]
        [Range(0.01, 1000.0)]
        [Display(Name = "Position Limit Full Equiv", GroupName = "11 TradeDay", Order = 8)]
        public double TradeDayPositionLimitFullContracts { get; set; }

        [NinjaScriptProperty]
        [Range(1, 100)]
        [Display(Name = "Micros Per Full", GroupName = "11 TradeDay", Order = 9)]
        public int TradeDayMicrosPerFull { get; set; }

        [NinjaScriptProperty]
        [Range(1, 200)]
        [Display(Name = "Max Trades Per Day", GroupName = "11 TradeDay", Order = 10)]
        public int TradeDayMaxTradesPerDay { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Consistency Guard Enabled", GroupName = "11 TradeDay", Order = 11)]
        public bool TradeDayConsistencyGuardEnabled { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, double.MaxValue)]
        [Display(Name = "Evaluation Profit Target", GroupName = "11 TradeDay", Order = 12)]
        public double TradeDayProfitTarget { get; set; }

        [NinjaScriptProperty]
        [Range(0.0, double.MaxValue)]
        [Display(Name = "Consistency Buffer Cash", GroupName = "11 TradeDay", Order = 13)]
        public double TradeDayConsistencyBuffer { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Session Close Guard Enabled", GroupName = "12 TradeDay Time", Order = 0)]
        public bool TradeDaySessionCloseGuardEnabled { get; set; }

        [NinjaScriptProperty]
        [Range(1, 120)]
        [Display(Name = "Minutes Before Product Close", GroupName = "12 TradeDay Time", Order = 1)]
        public int TradeDayMinutesBeforeProductClose { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Tier1 News Guard Enabled", GroupName = "12 TradeDay Time", Order = 2)]
        public bool TradeDayNewsGuardEnabled { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Tier1 News Calendar CSV", GroupName = "12 TradeDay Time", Order = 3)]
        public string TradeDayNewsCalendarPath { get; set; }

        [NinjaScriptProperty]
        [Range(1, 30)]
        [Display(Name = "News Minutes Before", GroupName = "12 TradeDay Time", Order = 4)]
        public int TradeDayNewsMinutesBefore { get; set; }

        [NinjaScriptProperty]
        [Range(1, 30)]
        [Display(Name = "News Minutes After", GroupName = "12 TradeDay Time", Order = 5)]
        public int TradeDayNewsMinutesAfter { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Fail Closed If Calendar Missing", GroupName = "12 TradeDay Time", Order = 6)]
        public bool TradeDayFailClosedNewsCalendar { get; set; }

        [NinjaScriptProperty]
        [Display(Name = "Compliance Reset Token", GroupName = "12 TradeDay Time", Order = 7)]
        public string TradeDayComplianceResetToken { get; set; }
        #endregion

        private SessionIterator tradeDaySessionIterator;
        private TradeDayLedger tradeDayLedger;
        private string tradeDayLedgerPath = string.Empty;
        private string tradeDayConfigFingerprint = string.Empty;
        private string tradeDayBlockReason = string.Empty;
        private string tradeDaySessionStatus = "not_initialized";
        private string tradeDayNewsStatus = "not_loaded";
        private DateTime tradeDayNextSessionEnd = DateTime.MinValue;
        private DateTime tradeDayLastInstrumentFlattenUtc = DateTime.MinValue;
        private DateTime tradeDayNewsFileWriteUtc = DateTime.MinValue;
        private DateTime tradeDayNewsLoadedUtc = DateTime.MinValue;
        private List<TradeDayNewsEvent> tradeDayNewsEvents = new List<TradeDayNewsEvent>();

        private void SetTradeDayComplianceDefaults()
        {
            TradeDayComplianceEnabled = true;
            TradeDayProgram = TradeDayProgramType.QuickPay;
            TradeDayDrawdownType = TradeDayDrawdownMode.EndOfDay;
            TradeDayStartingBalance = 0;
            TradeDayMaximumDrawdown = 0;
            TradeDayCurrentFloorOverride = 0;
            TradeDayDrawdownSafetyBuffer = 100;
            TradeDayUseBrokerTrailingFloor = true;
            TradeDayPositionLimitFullContracts = 5;
            TradeDayMicrosPerFull = 10;
            TradeDayMaxTradesPerDay = 200;
            TradeDayConsistencyGuardEnabled = true;
            TradeDayProfitTarget = 0;
            TradeDayConsistencyBuffer = 0;
            TradeDaySessionCloseGuardEnabled = true;
            TradeDayMinutesBeforeProductClose = 10;
            TradeDayNewsGuardEnabled = true;
            TradeDayNewsCalendarPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MetaQuotes", "Terminal", "Common", "Files", "TradeDay_Tier1_News_GMT.csv");
            TradeDayNewsMinutesBefore = 2;
            TradeDayNewsMinutesAfter = 2;
            TradeDayFailClosedNewsCalendar = true;
            TradeDayComplianceResetToken = "CHANGE_FOR_NEW_CHALLENGE";
        }

        private void InitializeTradeDayCompliance()
        {
            if (!TradeDayComplianceEnabled) return;
            try { if (Bars != null) tradeDaySessionIterator = new SessionIterator(Bars); }
            catch (Exception ex) { tradeDaySessionStatus = "session_init_failed:" + ex.Message; }

            var root = Path.Combine(NinjaTrader.Core.Globals.UserDataDir, "NinjaBridgeState", "TradeDayCompliance");
            Directory.CreateDirectory(root);
            tradeDayLedgerPath = Path.Combine(root, Sanitize(SafeAccountName()) + ".state");
            tradeDayConfigFingerprint = BuildTradeDayConfigFingerprint();
            lock (TradeDaySync)
            {
                var accountKey = SafeAccountName();
                TradeDayLedger existing;
                var firstActiveInstance = !TradeDayLedgers.TryGetValue(accountKey, out existing);
                if (firstActiveInstance)
                {
                    existing = LoadTradeDayLedger(tradeDayLedgerPath) ?? NewTradeDayLedger();
                    TradeDayLedgers[accountKey] = existing;
                }
                tradeDayLedger = existing;
                ApplyTradeDayConfigurationLocked(firstActiveInstance);
                int activeCount;
                TradeDayActiveInstances.TryGetValue(accountKey, out activeCount);
                TradeDayActiveInstances[accountKey] = activeCount + 1;
                TradeDayKnownOrderPrefixes.Add(orderScopePrefix);
            }
            ReloadTradeDayNewsCalendar(true);
            Account.ExecutionUpdate += TradeDayOnExecutionUpdate;
            HydrateTradeDayEntryCount();
            AuditRaw("tradeday_compliance_init", "build=" + TradeDayComplianceBuild + " " + TradeDayDashboardText());
        }

        private void ShutdownTradeDayCompliance()
        {
            if (!TradeDayComplianceEnabled || tradeDayLedger == null) return;
            try { if (Account != null) Account.ExecutionUpdate -= TradeDayOnExecutionUpdate; } catch { }
            lock (TradeDaySync)
            {
                SaveTradeDayLedgerLocked();
                var accountKey = SafeAccountName();
                int activeCount;
                if (TradeDayActiveInstances.TryGetValue(accountKey, out activeCount))
                {
                    activeCount--;
                    if (activeCount <= 0)
                    {
                        TradeDayActiveInstances.Remove(accountKey);
                        TradeDayLedgers.Remove(accountKey);
                    }
                    else TradeDayActiveInstances[accountKey] = activeCount;
                }
            }
        }

        private void ApplyTradeDayConfigurationLocked(bool allowReset)
        {
            var token = (TradeDayComplianceResetToken ?? string.Empty).Trim();
            if (!string.Equals(tradeDayLedger.ResetToken, token, StringComparison.Ordinal))
            {
                if (!allowReset)
                {
                    tradeDayLedger.ConfigConflict = true;
                    tradeDayLedger.ConfigConflictDetail = "Compliance Reset Token differs across active listeners";
                    return;
                }
                tradeDayLedger = NewTradeDayLedger();
                tradeDayLedger.ResetToken = token;
                tradeDayLedger.ConfigFingerprint = tradeDayConfigFingerprint;
                TradeDayLedgers[SafeAccountName()] = tradeDayLedger;
                SaveTradeDayLedgerLocked();
                return;
            }
            if (string.IsNullOrWhiteSpace(tradeDayLedger.ConfigFingerprint))
            {
                tradeDayLedger.ConfigFingerprint = tradeDayConfigFingerprint;
                SaveTradeDayLedgerLocked();
            }
            else if (!string.Equals(tradeDayLedger.ConfigFingerprint, tradeDayConfigFingerprint, StringComparison.Ordinal))
            {
                tradeDayLedger.ConfigConflict = true;
                tradeDayLedger.ConfigConflictDetail = "TradeDay settings differ across listeners or changed without a new Compliance Reset Token";
            }
        }

        private TradeDayLedger NewTradeDayLedger()
        {
            var equity = TradeDayCurrentEquity();
            var sod = SafeAccountValue(AccountItem.SodLiquidatingValue);
            var floor = TradeDayStartingBalance > 0 && TradeDayMaximumDrawdown > 0 ? TradeDayStartingBalance - TradeDayMaximumDrawdown : 0;
            if (TradeDayCurrentFloorOverride > 0) floor = Math.Max(floor, TradeDayCurrentFloorOverride);
            if (TradeDayStartingBalance > 0) floor = Math.Min(TradeDayStartingBalance, floor);
            return new TradeDayLedger
            {
                ResetToken = (TradeDayComplianceResetToken ?? string.Empty).Trim(),
                ConfigFingerprint = tradeDayConfigFingerprint,
                TradingDayKey = TradeDayTradingDayKey(DateTime.UtcNow),
                StartingBalance = TradeDayStartingBalance,
                ActiveFloor = floor,
                HighestIntradayEquity = equity,
                HighestEodEquity = Math.Max(TradeDayStartingBalance, IsFinitePositive(sod) ? sod : TradeDayStartingBalance),
                SessionStartEquity = IsFinitePositive(sod) ? sod : 0,
                LastEquity = equity
            };
        }

        private void EvaluateAndEnforceTradeDayCompliance()
        {
            if (!TradeDayComplianceEnabled || tradeDayLedger == null) return;
            ReloadTradeDayNewsCalendar(false);
            var equity = TradeDayCurrentEquity();
            var flattenAccount = false;
            var flattenInstrument = false;
            var accountReason = string.Empty;
            var instrumentReason = string.Empty;

            lock (TradeDaySync)
            {
                RollTradeDayLedgerLocked(DateTime.UtcNow, equity);
                if (!ValidTradeDayConfiguration(out tradeDayBlockReason))
                    SaveTradeDayLedgerLocked();
                else
                {
                    tradeDayLedger.LastEquity = equity;
                    if (TradeDayDrawdownType == TradeDayDrawdownMode.Intraday && equity > tradeDayLedger.HighestIntradayEquity)
                        tradeDayLedger.HighestIntradayEquity = equity;
                    var anchor = TradeDayDrawdownType == TradeDayDrawdownMode.Intraday ? tradeDayLedger.HighestIntradayEquity : tradeDayLedger.HighestEodEquity;
                    var floor = Math.Min(TradeDayStartingBalance, anchor - TradeDayMaximumDrawdown);
                    floor = Math.Max(floor, TradeDayStartingBalance - TradeDayMaximumDrawdown);
                    if (TradeDayCurrentFloorOverride > 0) floor = Math.Max(floor, TradeDayCurrentFloorOverride);
                    if (TradeDayUseBrokerTrailingFloor)
                    {
                        var brokerFloor = SafeAccountValue(AccountItem.TrailingMaxDrawdown);
                        if (IsPlausibleAbsoluteFloor(brokerFloor)) floor = Math.Max(floor, brokerFloor);
                    }
                    floor = Math.Min(TradeDayStartingBalance, floor);
                    tradeDayLedger.ActiveFloor = Math.Min(TradeDayStartingBalance, Math.Max(tradeDayLedger.ActiveFloor, floor));

                    if (!IsFinitePositive(equity))
                        tradeDayBlockReason = "net_liquidation_unavailable";
                    else if (equity <= tradeDayLedger.ActiveFloor + Math.Max(0, TradeDayDrawdownSafetyBuffer))
                    {
                        tradeDayLedger.HardStopped = true;
                        tradeDayLedger.HardStopReason = "drawdown_guard equity=" + F2(equity) + " floor=" + F2(tradeDayLedger.ActiveFloor) + " buffer=" + F2(TradeDayDrawdownSafetyBuffer);
                        tradeDayBlockReason = tradeDayLedger.HardStopReason;
                        flattenAccount = true;
                        accountReason = tradeDayBlockReason;
                    }
                    else if (tradeDayLedger.HardStopped)
                    {
                        tradeDayBlockReason = tradeDayLedger.HardStopReason;
                        flattenAccount = true;
                        accountReason = tradeDayBlockReason;
                    }
                    else
                    {
                        ApplyConsistencyGuardLocked(equity, ref flattenAccount, ref accountReason);
                        tradeDayBlockReason = tradeDayLedger.DailyStopped ? tradeDayLedger.DailyStopReason : string.Empty;
                    }
                    SaveTradeDayLedgerLocked();
                }
            }

            string sessionReason;
            if (EvaluateProductSessionGuard(out sessionReason)) { flattenInstrument = true; instrumentReason = sessionReason; }
            string newsReason; bool all;
            if (EvaluateNewsGuard(out newsReason, out all))
            {
                if (all) { flattenAccount = true; accountReason = newsReason; }
                else { flattenInstrument = true; instrumentReason = newsReason; }
            }
            if (flattenAccount) EnforceAccountFlatten(accountReason);
            else if (flattenInstrument) EnforceInstrumentFlatten(instrumentReason);
        }

        private void ApplyConsistencyGuardLocked(double equity, ref bool flatten, ref string reason)
        {
            if (!TradeDayConsistencyGuardEnabled || tradeDayLedger.DailyStopped) return;
            var ratio = TradeDayProgram == TradeDayProgramType.QuickPay ? 0.30 : 0.45;
            var cap = TradeDayProfitTarget * ratio;
            var dayPnl = equity - tradeDayLedger.SessionStartEquity;
            if (cap > 0 && dayPnl >= Math.Max(0, cap - TradeDayConsistencyBuffer))
            {
                tradeDayLedger.DailyStopped = true;
                tradeDayLedger.DailyStopReason = "consistency_guard day_pnl=" + F2(dayPnl) + " cap=" + F2(cap) + " program=" + TradeDayProgram;
                flatten = true;
                reason = tradeDayLedger.DailyStopReason;
            }
        }

        private bool TradeDayCanOpenNewTrade(out string reason)
        {
            reason = string.Empty;
            if (!TradeDayComplianceEnabled) return true;
            if (tradeDayLedger == null) { reason = "compliance_not_initialized"; return false; }
            EvaluateAndEnforceTradeDayCompliance();
            if (!string.IsNullOrWhiteSpace(tradeDayBlockReason)) { reason = tradeDayBlockReason; return false; }
            if (tradeDayLedger.ConfigConflict) { reason = tradeDayLedger.ConfigConflictDetail; return false; }
            if (tradeDayLedger.HardStopped || tradeDayLedger.DailyStopped)
            { reason = tradeDayLedger.HardStopped ? tradeDayLedger.HardStopReason : tradeDayLedger.DailyStopReason; return false; }
            if (tradeDayLedger.TradeCount >= Math.Min(200, Math.Max(1, TradeDayMaxTradesPerDay)))
            { reason = "daily_trade_cap count=" + tradeDayLedger.TradeCount; return false; }
            if (TradeDaySessionCloseGuardEnabled && tradeDaySessionStatus != "OPEN")
            { reason = "session_guard " + tradeDaySessionStatus; return false; }
            if (TradeDayNewsGuardEnabled && tradeDayNewsStatus != "CLEAR")
            { reason = "news_guard " + tradeDayNewsStatus; return false; }
            return true;
        }

        private int TradeDayApplyContractCap(int requested, out string detail)
        {
            detail = "tradeday_cap_off";
            if (!TradeDayComplianceEnabled) return requested;
            if (requested <= 0 || TradeDayPositionLimitFullContracts <= 0)
            { detail = "tradeday_contract_cap_invalid"; return 0; }

            var existing = 0.0;
            foreach (var position in Account.Positions)
            {
                if (position == null || position.MarketPosition == MarketPosition.Flat || position.Quantity <= 0) continue;
                existing += position.Quantity / ContractUnitsPerFull(position.Instrument);
            }
            foreach (var order in Account.Orders)
            {
                if (order == null || !IsWorking(order) || order.Quantity <= order.Filled) continue;
                if (order.OrderAction != OrderAction.Buy && order.OrderAction != OrderAction.SellShort) continue;
                existing += (order.Quantity - order.Filled) / ContractUnitsPerFull(order.Instrument);
            }
            var units = ContractUnitsPerFull(Instrument);
            var allowed = (int)Math.Floor(Math.Max(0, TradeDayPositionLimitFullContracts - existing) * units + 1e-9);
            var result = Math.Min(requested, allowed);
            detail = "tradeday_contract_cap requested=" + requested + " result=" + result + " existing_full_eq=" + existing.ToString("F2", CultureInfo.InvariantCulture) + " limit=" + TradeDayPositionLimitFullContracts.ToString("F2", CultureInfo.InvariantCulture);
            return Math.Max(0, result);
        }

        private bool TradeDayReserveBridgeEntry(string eventId, out string detail)
        {
            detail = string.Empty;
            if (!TradeDayComplianceEnabled) return true;
            if (tradeDayLedger == null) { detail = "compliance_not_initialized"; return false; }
            lock (TradeDaySync)
            {
                RollTradeDayLedgerLocked(DateTime.UtcNow, TradeDayCurrentEquity());
                var key = "EVENT:" + eventId;
                if (tradeDayLedger.CountedEntryEvents.Contains(key)) return true;
                var cap = Math.Min(200, Math.Max(1, TradeDayMaxTradesPerDay));
                if (tradeDayLedger.TradeCount >= cap)
                { detail = "daily_trade_cap count=" + tradeDayLedger.TradeCount + " cap=" + cap; return false; }
                tradeDayLedger.CountedEntryEvents.Add(key);
                tradeDayLedger.TradeCount++;
                SaveTradeDayLedgerLocked();
                detail = "trade_slot_reserved count=" + tradeDayLedger.TradeCount + " cap=" + cap;
                return true;
            }
        }

        private static bool IsTradeDayBridgeOrder(Order order)
        {
            if (order == null || string.IsNullOrWhiteSpace(order.Name)) return false;
            lock (TradeDaySync) return TradeDayKnownOrderPrefixes.Any(prefix => order.Name.StartsWith(prefix, StringComparison.Ordinal));
        }
        private void TradeDayOnExecutionUpdate(object sender, ExecutionEventArgs args)
        {
            try
            {
                var execution = args == null ? null : args.Execution;
                if (!TradeDayComplianceEnabled || tradeDayLedger == null || execution == null || execution.IsSod || !execution.IsEntry || IsTradeDayBridgeOrder(execution.Order)) return;
                var orderKey = !string.IsNullOrWhiteSpace(execution.OrderId) ? execution.OrderId : execution.ExecutionId;
                RegisterTradeDayEntryKey("ORDER:" + orderKey, "account_execution");
            }
            catch (Exception ex) { AuditRaw("tradeday_execution_count_failed", ex.Message); }
        }

        private void HydrateTradeDayEntryCount()
        {
            if (Account == null || tradeDayLedger == null) return;
            try
            {
                foreach (var execution in Account.Executions)
                {
                    if (execution == null || execution.IsSod || !execution.IsEntry || IsTradeDayBridgeOrder(execution.Order)) continue;
                    var utc = execution.Time.Kind == DateTimeKind.Utc ? execution.Time : execution.Time.ToUniversalTime();
                    if (TradeDayTradingDayKey(utc) != tradeDayLedger.TradingDayKey) continue;
                    var orderKey = !string.IsNullOrWhiteSpace(execution.OrderId) ? execution.OrderId : execution.ExecutionId;
                    RegisterTradeDayEntryKey("ORDER:" + orderKey, "history_hydration");
                }
            }
            catch (Exception ex) { AuditRaw("tradeday_execution_hydration_failed", ex.Message); }
        }

        private void RegisterTradeDayEntryKey(string key, string source)
        {
            if (string.IsNullOrWhiteSpace(key) || tradeDayLedger == null) return;
            lock (TradeDaySync)
            {
                RollTradeDayLedgerLocked(DateTime.UtcNow, TradeDayCurrentEquity());
                if (!tradeDayLedger.CountedEntryEvents.Add(key)) return;
                tradeDayLedger.TradeCount++;
                SaveTradeDayLedgerLocked();
                AuditRaw("tradeday_entry_counted", "source=" + source + " key=" + ShortEvent(key) + " count=" + tradeDayLedger.TradeCount);
            }
        }
        private void TradeDayRegisterFilledEntry(string orderOrEventId)
        {
            if (!TradeDayComplianceEnabled || string.IsNullOrWhiteSpace(orderOrEventId)) return;
            RegisterTradeDayEntryKey("EVENT:" + orderOrEventId, "protected_entry_fallback");
        }

        private bool EvaluateProductSessionGuard(out string reason)
        {
            reason = string.Empty;
            if (!TradeDaySessionCloseGuardEnabled) { tradeDaySessionStatus = "OPEN"; return false; }
            if (tradeDaySessionIterator == null) { tradeDaySessionStatus = "FAIL_CLOSED:no_session_iterator"; reason = "session_guard_no_iterator"; return true; }
            try
            {
                var now = DateTime.Now;
                tradeDaySessionIterator.GetNextSession(now.AddSeconds(-1), true);
                var inSession = tradeDaySessionIterator.IsInSession(now, true, true);
                tradeDayNextSessionEnd = tradeDaySessionIterator.ActualSessionEnd;
                if (!inSession)
                { tradeDaySessionStatus = "CLOSED next_end=" + tradeDayNextSessionEnd.ToString("yyyy-MM-dd HH:mm"); reason = "product_session_closed"; return true; }
                var flattenAt = tradeDayNextSessionEnd.AddMinutes(-Math.Max(1, TradeDayMinutesBeforeProductClose));
                if (now >= flattenAt)
                {
                    tradeDaySessionStatus = "FLATTEN close=" + tradeDayNextSessionEnd.ToString("HH:mm");
                    reason = "product_close_guard close=" + tradeDayNextSessionEnd.ToString("O") + " flatten_at=" + flattenAt.ToString("O");
                    return true;
                }
                tradeDaySessionStatus = "OPEN";
                return false;
            }
            catch (Exception ex) { tradeDaySessionStatus = "FAIL_CLOSED:" + ex.Message; reason = "session_guard_error=" + ex.Message; return true; }
        }

        private bool EvaluateNewsGuard(out string reason, out bool scopeAll)
        {
            reason = string.Empty; scopeAll = false;
            if (!TradeDayNewsGuardEnabled) { tradeDayNewsStatus = "CLEAR"; return false; }
            if (tradeDayNewsEvents.Count == 0)
            {
                tradeDayNewsStatus = TradeDayFailClosedNewsCalendar ? "FAIL_CLOSED:calendar_missing_or_empty" : "CLEAR";
                if (TradeDayFailClosedNewsCalendar) { reason = "tier1_news_calendar_unavailable"; scopeAll = true; return true; }
                return false;
            }
            var now = DateTime.UtcNow;
            foreach (var item in tradeDayNewsEvents)
            {
                if (!NewsScopeMatches(item.Scope)) continue;
                var begin = item.EventGmt.AddMinutes(-Math.Max(1, TradeDayNewsMinutesBefore));
                var end = item.EventGmt.AddMinutes(Math.Max(1, TradeDayNewsMinutesAfter));
                if (now < begin || now > end) continue;
                scopeAll = item.Scope.Equals("ALL", StringComparison.OrdinalIgnoreCase);
                tradeDayNewsStatus = "BLACKOUT " + item.Label + " until=" + end.ToString("HH:mm:ss") + "Z";
                reason = "tier1_news_blackout event=" + item.Label + " event_gmt=" + item.EventGmt.ToString("O") + " scope=" + item.Scope;
                return true;
            }
            tradeDayNewsStatus = "CLEAR";
            return false;
        }

        private void ReloadTradeDayNewsCalendar(bool force)
        {
            if (!TradeDayNewsGuardEnabled) { tradeDayNewsStatus = "CLEAR"; return; }
            try
            {
                var path = Environment.ExpandEnvironmentVariables(TradeDayNewsCalendarPath ?? string.Empty);
                if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
                {
                    tradeDayNewsEvents.Clear();
                    tradeDayNewsStatus = TradeDayFailClosedNewsCalendar ? "FAIL_CLOSED:calendar_missing" : "CLEAR";
                    return;
                }
                var write = File.GetLastWriteTimeUtc(path);
                if (!force && write == tradeDayNewsFileWriteUtc && (DateTime.UtcNow - tradeDayNewsLoadedUtc).TotalMinutes < 5) return;
                var loaded = new List<TradeDayNewsEvent>();
                foreach (var raw in File.ReadAllLines(path))
                {
                    var line = (raw ?? string.Empty).Trim();
                    if (line.Length == 0 || line.StartsWith("#") || line.StartsWith("event_gmt", StringComparison.OrdinalIgnoreCase)) continue;
                    var parts = ParseSimpleCsv(line);
                    if (parts.Count < 3) continue;
                    DateTime time;
                    if (!DateTime.TryParse(parts[0], CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out time)) continue;
                    loaded.Add(new TradeDayNewsEvent { EventGmt = time, Scope = parts[1].Trim().ToUpperInvariant(), Label = parts[2].Trim() });
                }
                tradeDayNewsEvents = loaded.OrderBy(x => x.EventGmt).ToList();
                tradeDayNewsFileWriteUtc = write;
                tradeDayNewsLoadedUtc = DateTime.UtcNow;
                tradeDayNewsStatus = loaded.Count > 0 ? "CLEAR" : (TradeDayFailClosedNewsCalendar ? "FAIL_CLOSED:calendar_empty" : "CLEAR");
            }
            catch (Exception ex)
            { tradeDayNewsEvents.Clear(); tradeDayNewsStatus = TradeDayFailClosedNewsCalendar ? "FAIL_CLOSED:" + ex.Message : "CLEAR"; }
        }

        private bool NewsScopeMatches(string scope)
        {
            var value = (scope ?? string.Empty).Trim().ToUpperInvariant();
            if (value == "ALL") return true;
            var master = Instrument != null && Instrument.MasterInstrument != null ? (Instrument.MasterInstrument.Name ?? string.Empty).ToUpperInvariant() : string.Empty;
            if (value == master || value == (Instrument.FullName ?? string.Empty).ToUpperInvariant()) return true;
            if (value == "OIL") return master == "CL" || master == "MCL" || master == "BZ" || master == "QM" || master == "HO" || master == "MHO" || master == "RB";
            if (value == "GAS") return master == "NG" || master == "MNG";
            if (value == "AGS") return master == "ZC" || master == "ZW" || master == "ZS" || master == "ZM" || master == "ZL" || master == "HE" || master == "LE" || master == "GF";
            return false;
        }

        private void EnforceAccountFlatten(string reason)
        {
            if (Account == null || !TradeDayHasAccountExposureOrOrders()) return;
            lock (TradeDaySync)
            {
                var now = DateTime.UtcNow;
                if (tradeDayLedger != null && (now - tradeDayLedger.LastAccountFlattenUtc).TotalSeconds < 10) return;
                if (tradeDayLedger != null) { tradeDayLedger.LastAccountFlattenUtc = now; SaveTradeDayLedgerLocked(); }
            }
            try { Account.FlattenEverything(); AuditRaw("tradeday_account_flatten", reason); }
            catch (Exception ex) { AuditRaw("tradeday_account_flatten_failed", reason + " error=" + ex.Message); }
        }

        private void EnforceInstrumentFlatten(string reason)
        {
            if (Account == null || Instrument == null || !TradeDayHasInstrumentExposureOrOrders() || (DateTime.UtcNow - tradeDayLastInstrumentFlattenUtc).TotalSeconds < 60) return;
            tradeDayLastInstrumentFlattenUtc = DateTime.UtcNow;
            try
            {
                Account.CancelAllOrders(Instrument);
                Account.Flatten(new[] { Instrument });
                AuditRaw("tradeday_instrument_flatten", reason);
            }
            catch (Exception ex) { AuditRaw("tradeday_instrument_flatten_failed", reason + " error=" + ex.Message); }
        }

        private bool TradeDayShouldSuspendManagedLifecycle()
        {
            if (!TradeDayComplianceEnabled || tradeDayLedger == null || !TradeDayHasInstrumentExposureOrOrders()) return false;
            var accountStop = tradeDayLedger.HardStopped || tradeDayLedger.DailyStopped
                || (TradeDayNewsGuardEnabled && tradeDayNewsStatus != "CLEAR" && tradeDayNewsStatus != "not_loaded");
            var productStop = TradeDaySessionCloseGuardEnabled && tradeDaySessionStatus != "OPEN" && tradeDaySessionStatus != "not_initialized";
            return accountStop || productStop;
        }
        private bool TradeDayHasAccountExposureOrOrders()
        {
            return Account.Positions.Any(p => p != null && p.MarketPosition != MarketPosition.Flat && p.Quantity > 0)
                || Account.Orders.Any(o => o != null && IsWorking(o));
        }

        private bool TradeDayHasInstrumentExposureOrOrders()
        {
            return Account.Positions.Any(p => p != null && SameInstrument(p.Instrument) && p.MarketPosition != MarketPosition.Flat && p.Quantity > 0)
                || Account.Orders.Any(o => o != null && SameInstrument(o.Instrument) && IsWorking(o));
        }
        private void RollTradeDayLedgerLocked(DateTime nowUtc, double equity)
        {
            var key = TradeDayTradingDayKey(nowUtc);
            if (tradeDayLedger.TradingDayKey == key) return;
            var priorPnl = tradeDayLedger.LastEquity - tradeDayLedger.SessionStartEquity;
            tradeDayLedger.BestDayProfit = Math.Max(tradeDayLedger.BestDayProfit, priorPnl);
            tradeDayLedger.HighestEodEquity = Math.Max(tradeDayLedger.HighestEodEquity, tradeDayLedger.LastEquity);
            tradeDayLedger.TradingDayKey = key;
            var sod = SafeAccountValue(AccountItem.SodLiquidatingValue);
            tradeDayLedger.SessionStartEquity = IsFinitePositive(sod) ? sod : 0;
            tradeDayLedger.HighestIntradayEquity = equity;
            tradeDayLedger.LastEquity = equity;
            tradeDayLedger.TradeCount = 0;
            tradeDayLedger.CountedEntryEvents.Clear();
            tradeDayLedger.DailyStopped = false;
            tradeDayLedger.DailyStopReason = string.Empty;
        }

        private bool ValidTradeDayConfiguration(out string reason)
        {
            if (tradeDayLedger.ConfigConflict) { reason = tradeDayLedger.ConfigConflictDetail; return false; }
            if (!IsFinitePositive(TradeDayStartingBalance) || !IsFinitePositive(TradeDayMaximumDrawdown))
            { reason = "FAIL_CLOSED:set Challenge Starting Balance and Maximum Drawdown Amount"; return false; }
            if (TradeDayConsistencyGuardEnabled && !IsFinitePositive(TradeDayProfitTarget))
            { reason = "FAIL_CLOSED:set Evaluation Profit Target or disable Consistency Guard"; return false; }
            if (TradeDayConsistencyGuardEnabled && !IsFinitePositive(tradeDayLedger.SessionStartEquity))
            { reason = "FAIL_CLOSED:SOD liquidating value unavailable for consistency guard"; return false; }
            if (TradeDayPositionLimitFullContracts <= 0 || TradeDayMaxTradesPerDay <= 0)
            { reason = "FAIL_CLOSED:invalid position/trade cap"; return false; }
            reason = string.Empty; return true;
        }

        private string TradeDayDashboardText()
        {
            if (!TradeDayComplianceEnabled) return "TradeDay=OFF";
            if (tradeDayLedger == null) return "TradeDay=INIT";
            var equity = TradeDayCurrentEquity();
            var dayPnl = equity - tradeDayLedger.SessionStartEquity;
            var consistency = TradeDayProgram == TradeDayProgramType.QuickPay ? 30 : 45;
            return "TradeDay=" + (string.IsNullOrWhiteSpace(tradeDayBlockReason) ? "READY" : "BLOCK")
                 + " DD=" + F2(equity) + "/" + F2(tradeDayLedger.ActiveFloor)
                 + " DayPnL=" + F2(dayPnl) + " Cons=" + consistency + "%"
                 + " Trades=" + tradeDayLedger.TradeCount + "/" + Math.Min(200, Math.Max(1, TradeDayMaxTradesPerDay))
                 + " PosCap=" + TradeDayPositionLimitFullContracts.ToString("F1", CultureInfo.InvariantCulture) + "F\n"
                 + "TD Session=" + tradeDaySessionStatus + " News=" + tradeDayNewsStatus
                 + (string.IsNullOrWhiteSpace(tradeDayBlockReason) ? string.Empty : " Reason=" + Truncate(tradeDayBlockReason, 120));
        }

        private double TradeDayCurrentEquity() { return SafeAccountValue(AccountItem.NetLiquidation); }
        private bool IsPlausibleAbsoluteFloor(double value)
        { return IsFinitePositive(value) && TradeDayStartingBalance > 0 && value >= TradeDayStartingBalance * 0.25 && value <= Math.Max(TradeDayStartingBalance * 3.0, TradeDayCurrentEquity() + TradeDayMaximumDrawdown); }
        private double ContractUnitsPerFull(Instrument instrument)
        {
            if (instrument == null || instrument.MasterInstrument == null) return 1.0;
            return MicroContracts.Contains(instrument.MasterInstrument.Name ?? string.Empty) ? Math.Max(1, TradeDayMicrosPerFull) : 1.0;
        }

        private string BuildTradeDayConfigFingerprint()
        {
            var raw = string.Join("|", TradeDayProgram, TradeDayDrawdownType,
                TradeDayStartingBalance.ToString("R", CultureInfo.InvariantCulture), TradeDayMaximumDrawdown.ToString("R", CultureInfo.InvariantCulture),
                TradeDayCurrentFloorOverride.ToString("R", CultureInfo.InvariantCulture), TradeDayPositionLimitFullContracts.ToString("R", CultureInfo.InvariantCulture),
                TradeDayDrawdownSafetyBuffer.ToString("R", CultureInfo.InvariantCulture), TradeDayUseBrokerTrailingFloor,
                TradeDayMicrosPerFull, TradeDayMaxTradesPerDay, TradeDayConsistencyGuardEnabled, TradeDayProfitTarget.ToString("R", CultureInfo.InvariantCulture),
                TradeDayConsistencyBuffer.ToString("R", CultureInfo.InvariantCulture), TradeDaySessionCloseGuardEnabled, TradeDayMinutesBeforeProductClose,
                TradeDayNewsGuardEnabled, TradeDayNewsMinutesBefore, TradeDayNewsMinutesAfter, TradeDayFailClosedNewsCalendar);
            return Hash64(raw).ToString("X16", CultureInfo.InvariantCulture);
        }

        private static string TradeDayTradingDayKey(DateTime utc)
        {
            try
            {
                var zone = TimeZoneInfo.FindSystemTimeZoneById("Central Standard Time");
                var ct = TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utc, DateTimeKind.Utc), zone);
                var date = ct.TimeOfDay >= TimeSpan.FromHours(17) ? ct.Date.AddDays(1) : ct.Date;
                return date.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
            }
            catch { return utc.ToString("yyyyMMdd", CultureInfo.InvariantCulture); }
        }

        private void SaveTradeDayLedgerLocked()
        {
            if (tradeDayLedger == null || string.IsNullOrWhiteSpace(tradeDayLedgerPath)) return;
            try
            {
                var lines = new[]
                {
                    "version=1", "reset_token=" + EncodeTd(tradeDayLedger.ResetToken), "config=" + EncodeTd(tradeDayLedger.ConfigFingerprint),
                    "day=" + EncodeTd(tradeDayLedger.TradingDayKey), "starting=" + G17(tradeDayLedger.StartingBalance), "floor=" + G17(tradeDayLedger.ActiveFloor),
                    "high_intraday=" + G17(tradeDayLedger.HighestIntradayEquity), "high_eod=" + G17(tradeDayLedger.HighestEodEquity),
                    "session_start=" + G17(tradeDayLedger.SessionStartEquity), "last_equity=" + G17(tradeDayLedger.LastEquity), "best_day=" + G17(tradeDayLedger.BestDayProfit),
                    "trade_count=" + tradeDayLedger.TradeCount.ToString(CultureInfo.InvariantCulture), "daily_stopped=" + (tradeDayLedger.DailyStopped ? "1" : "0"),
                    "daily_reason=" + EncodeTd(tradeDayLedger.DailyStopReason), "hard_stopped=" + (tradeDayLedger.HardStopped ? "1" : "0"),
                    "hard_reason=" + EncodeTd(tradeDayLedger.HardStopReason), "counted_events=" + EncodeTd(string.Join("\t", tradeDayLedger.CountedEntryEvents)),
                    "last_flatten=" + tradeDayLedger.LastAccountFlattenUtc.ToString("O", CultureInfo.InvariantCulture)
                };
                WriteAtomically(tradeDayLedgerPath, string.Join("\n", lines));
            }
            catch (Exception ex) { AuditRaw("tradeday_state_write_failed", ex.Message); }
        }

        private TradeDayLedger LoadTradeDayLedger(string path)
        {
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return null;
            try
            {
                var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (var line in File.ReadAllLines(path))
                {
                    var index = line.IndexOf('=');
                    if (index > 0) map[line.Substring(0, index)] = line.Substring(index + 1);
                }
                var ledger = new TradeDayLedger
                {
                    ResetToken = DecodeTd(GetTd(map, "reset_token")), ConfigFingerprint = DecodeTd(GetTd(map, "config")), TradingDayKey = DecodeTd(GetTd(map, "day")),
                    StartingBalance = ParseTdDouble(GetTd(map, "starting")), ActiveFloor = ParseTdDouble(GetTd(map, "floor")),
                    HighestIntradayEquity = ParseTdDouble(GetTd(map, "high_intraday")), HighestEodEquity = ParseTdDouble(GetTd(map, "high_eod")),
                    SessionStartEquity = ParseTdDouble(GetTd(map, "session_start")), LastEquity = ParseTdDouble(GetTd(map, "last_equity")), BestDayProfit = ParseTdDouble(GetTd(map, "best_day")),
                    TradeCount = ParseTdInt(GetTd(map, "trade_count")), DailyStopped = GetTd(map, "daily_stopped") == "1", DailyStopReason = DecodeTd(GetTd(map, "daily_reason")),
                    HardStopped = GetTd(map, "hard_stopped") == "1", HardStopReason = DecodeTd(GetTd(map, "hard_reason")), LastAccountFlattenUtc = ParseTdDate(GetTd(map, "last_flatten"))
                };
                foreach (var id in DecodeTd(GetTd(map, "counted_events")).Split(new[] { '\t' }, StringSplitOptions.RemoveEmptyEntries)) ledger.CountedEntryEvents.Add(id);
                return ledger;
            }
            catch (Exception ex) { AuditRaw("tradeday_state_load_failed", ex.Message); return null; }
        }

        private static List<string> ParseSimpleCsv(string line)
        {
            var fields = new List<string>(); var current = new StringBuilder(); var quoted = false;
            for (var i = 0; i < line.Length; i++)
            {
                var c = line[i];
                if (c == '"')
                {
                    if (quoted && i + 1 < line.Length && line[i + 1] == '"') { current.Append('"'); i++; }
                    else quoted = !quoted;
                }
                else if (c == ',' && !quoted) { fields.Add(current.ToString()); current.Clear(); }
                else current.Append(c);
            }
            fields.Add(current.ToString()); return fields;
        }

        private static string EncodeTd(string value) { return Convert.ToBase64String(Encoding.UTF8.GetBytes(value ?? string.Empty)); }
        private static string DecodeTd(string value) { try { return string.IsNullOrWhiteSpace(value) ? string.Empty : Encoding.UTF8.GetString(Convert.FromBase64String(value)); } catch { return string.Empty; } }
        private static string GetTd(Dictionary<string, string> map, string key) { string value; return map.TryGetValue(key, out value) ? value : string.Empty; }
        private static double ParseTdDouble(string value) { double parsed; return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out parsed) ? parsed : 0; }
        private static int ParseTdInt(string value) { int parsed; return int.TryParse(value, out parsed) ? parsed : 0; }
        private static DateTime ParseTdDate(string value) { DateTime parsed; return DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out parsed) ? parsed : DateTime.MinValue; }
        private static string F2(double value) { return value.ToString("F2", CultureInfo.InvariantCulture); }

        private sealed class TradeDayLedger
        {
            public string ResetToken = string.Empty, ConfigFingerprint = string.Empty, TradingDayKey = string.Empty;
            public double StartingBalance, ActiveFloor, HighestIntradayEquity, HighestEodEquity, SessionStartEquity, LastEquity, BestDayProfit;
            public int TradeCount;
            public bool DailyStopped, HardStopped, ConfigConflict;
            public string DailyStopReason = string.Empty, HardStopReason = string.Empty, ConfigConflictDetail = string.Empty;
            public DateTime LastAccountFlattenUtc = DateTime.MinValue;
            public readonly HashSet<string> CountedEntryEvents = new HashSet<string>(StringComparer.Ordinal);
        }

        private sealed class TradeDayNewsEvent
        { public DateTime EventGmt; public string Scope = string.Empty, Label = string.Empty; }
    }
}
