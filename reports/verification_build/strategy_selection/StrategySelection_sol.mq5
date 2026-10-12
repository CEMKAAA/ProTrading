#property strict
#define SELECTION_SOL
#define SELECTION_NAME "sol"
#define OnInit SelectionUnusedOnInit
#define OnDeinit SelectionUnusedOnDeinit
#define OnTick SelectionUnusedOnTick
#define OnTimer SelectionUnusedOnTimer
#define OnChartEvent SelectionUnusedOnChartEvent
#define OnTradeTransaction SelectionUnusedOnTradeTransaction
#include "../../../IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "../../../tests/mql5/StrategySelectionFilterChecks.mqh"
