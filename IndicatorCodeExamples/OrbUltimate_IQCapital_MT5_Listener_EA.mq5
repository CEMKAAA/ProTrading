#property strict
#property version "1.01"

#define IQC_LISTENER_BUILD "2026-08-30.iq-orb-mt5-listener-channel-safe-v2"
#define IQC_PIPELINE_ID "IQOrbUltimateMT5"
#define IQC_DEFAULT_FILE "OrbUltimateBridge_Latest_C1.csv"
#define IQC_DEFAULT_SOURCE_FILTER "OrbUltimate|"
#define IQC_DEFAULT_SOURCE_TF "15"
#define IQC_DEFAULT_BRIDGE_CHANNEL 1
#define IQC_DEFAULT_PREFER_SCOPED_LATEST true
#define IQC_DEFAULT_FAIL_IF_SCOPED_MISSING true
#define IQC_DEFAULT_MAGIC 9811503
#define IQC_DEFAULT_RISK_PCT 1.00
#define IQC_DEFAULT_AUDIT_PREFIX "OrbUltimate_IQCapital_MT5_Audit_"
#define IQC_DASH_PREFIX "IQ_ORB_MT5_DASH_"

#include "IQCapital_MT5_Listener_Core.mqh"
