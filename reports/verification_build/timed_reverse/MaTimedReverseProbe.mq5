#define PROBE_PARITY
#property strict
#define OnInit ProbeInit
#define OnDeinit ProbeDeinit
#define OnTick ProbeTick
#define OnTimer ProbeTimer
#define OnChartEvent ProbeEvent
#define OnTradeTransaction ProbeTransaction
#include "C:/Users/Cem/Desktop/projeler/YapayZekaUygulamalari/ProTradingSystem/IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5"
#include "MaBefore.mqh"
#undef OnInit
#undef OnDeinit
#undef OnTick
#undef OnTimer
#undef OnChartEvent
#undef OnTradeTransaction
#define PROBE_FILE "MaTimedReverseProbe.json"
#include "MaTimedReverseProbe.mqh"
