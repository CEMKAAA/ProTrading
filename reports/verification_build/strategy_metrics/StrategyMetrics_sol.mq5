#property strict
#define METRICS_SOL
#define METRICS_NAME "sol"
#define METRICS_FOLDER "LiqStrategies\\WindowMetrics"
#define METRICS_LIBRARY "LiqStrategies"
#define OnInit MetricsUnusedOnInit
#define OnDeinit MetricsUnusedOnDeinit
#define OnTick MetricsUnusedOnTick
#define OnTimer MetricsUnusedOnTimer
#define OnChartEvent MetricsUnusedOnChartEvent
#define OnTradeTransaction MetricsUnusedOnTradeTransaction
#include "../../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "../../../tests/mql5/StrategyMetricsPersistenceChecks.mqh"
