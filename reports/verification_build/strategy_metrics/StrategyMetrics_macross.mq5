#property strict
#define METRICS_MA
#define METRICS_NAME "macross"
#define METRICS_FOLDER "MaCrossOrbStrategyLibrary\\WindowMetrics"
#define METRICS_LIBRARY "MaCrossOrbStrategyLibrary"
#define OnInit MetricsUnusedOnInit
#define OnDeinit MetricsUnusedOnDeinit
#define OnTick MetricsUnusedOnTick
#define OnTimer MetricsUnusedOnTimer
#define OnChartEvent MetricsUnusedOnChartEvent
#define OnTradeTransaction MetricsUnusedOnTradeTransaction
#include "../../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "../../../tests/mql5/StrategyMetricsPersistenceChecks.mqh"
