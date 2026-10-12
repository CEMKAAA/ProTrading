#property strict
#define SELECTION_LAB
#define SELECTION_NAME "entrylab"
#define OnInit SelectionUnusedOnInit
#define OnDeinit SelectionUnusedOnDeinit
#define OnTick SelectionUnusedOnTick
#define OnTimer SelectionUnusedOnTimer
#define OnChartEvent SelectionUnusedOnChartEvent
#define OnTradeTransaction SelectionUnusedOnTradeTransaction
#include "../../../IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#include "../../../tests/mql5/StrategySelectionFilterChecks.mqh"
