#property strict
#define METRICS_LAB
#define METRICS_NAME "entrylab"
#define METRICS_FOLDER "EntryEngineLabStrategyLibrary\\WindowMetrics"
#define METRICS_LIBRARY "EntryEngineLabStrategyLibrary"
#define OnInit MetricsUnusedOnInit
#define OnDeinit MetricsUnusedOnDeinit
#define OnTick MetricsUnusedOnTick
#define OnTimer MetricsUnusedOnTimer
#define OnChartEvent MetricsUnusedOnChartEvent
#define OnTradeTransaction MetricsUnusedOnTradeTransaction
#include "../../../IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "../../../tests/mql5/StrategyMetricsPersistenceChecks.mqh"
