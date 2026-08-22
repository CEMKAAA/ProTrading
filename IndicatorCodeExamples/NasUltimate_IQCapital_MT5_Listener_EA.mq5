#property strict
#property version "1.10"

#define IQC_LISTENER_BUILD "2026-08-21.iq-nas-mt5-listener-v2-scoped"
#define IQC_PIPELINE_ID "IQNasUltimateMT5"
#define IQC_DEFAULT_FILE "NasUltimateBridge_Latest.csv"
#define IQC_DEFAULT_SOURCE_FILTER "NasUltimate|"
#define IQC_DEFAULT_SOURCE_TF "5"
#define IQC_DEFAULT_PREFER_SCOPED_LATEST true
#define IQC_DEFAULT_FAIL_IF_SCOPED_MISSING true
#define IQC_DEFAULT_SOURCE_SYMBOL_ALIASES ""
#define IQC_DEFAULT_MAGIC 9810504
#define IQC_DEFAULT_RISK_PCT 1.00
#define IQC_DEFAULT_AUDIT_PREFIX "NasUltimate_IQCapital_MT5_Audit_"
#define IQC_DASH_PREFIX "IQ_NAS_MT5_DASH_"

#include "IQCapital_MT5_Listener_Core.mqh"
