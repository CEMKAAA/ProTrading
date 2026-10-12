#property strict
#define SELECTION_MA
#define SELECTION_NAME "macross"
#define OnInit SelectionUnusedOnInit
#define OnDeinit SelectionUnusedOnDeinit
#define OnTick SelectionUnusedOnTick
#define OnTimer SelectionUnusedOnTimer
#define OnChartEvent SelectionUnusedOnChartEvent
#define OnTradeTransaction SelectionUnusedOnTradeTransaction
#include "../../../IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "../../../tests/mql5/StrategySelectionFilterChecks.mqh"
