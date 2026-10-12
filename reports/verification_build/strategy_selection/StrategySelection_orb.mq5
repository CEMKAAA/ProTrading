#property strict
#define SELECTION_ORB
#define SELECTION_NAME "orb"
#define OnInit SelectionUnusedOnInit
#define OnDeinit SelectionUnusedOnDeinit
#define OnTick SelectionUnusedOnTick
#define OnTimer SelectionUnusedOnTimer
#define OnChartEvent SelectionUnusedOnChartEvent
#define OnTradeTransaction SelectionUnusedOnTradeTransaction
#include "../../../IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "../../../tests/mql5/StrategySelectionFilterChecks.mqh"
