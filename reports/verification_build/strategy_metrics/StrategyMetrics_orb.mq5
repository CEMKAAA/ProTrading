#property strict
#define METRICS_ORB
#define METRICS_NAME "orb"
#define METRICS_FOLDER "OrbStrategyUserLibrary\\WindowMetrics"
#define METRICS_LIBRARY "OrbStrategyUserLibrary"
#define OnInit MetricsUnusedOnInit
#define OnDeinit MetricsUnusedOnDeinit
#define OnTick MetricsUnusedOnTick
#define OnTimer MetricsUnusedOnTimer
#define OnChartEvent MetricsUnusedOnChartEvent
#define OnTradeTransaction MetricsUnusedOnTradeTransaction
#include "../../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "../../../tests/mql5/StrategyMetricsPersistenceChecks.mqh"
