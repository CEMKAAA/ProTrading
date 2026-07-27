#property strict
#property version "1.00"

#define IQC_LISTENER_BUILD "2026-07-27.iq-nas-mt5-listener-v1"
#define IQC_PIPELINE_ID "IQNasUltimateMT5"
#define IQC_DEFAULT_FILE "NasUltimateBridge_Latest_DE30_5.csv"
#define IQC_DEFAULT_SOURCE_FILTER "NasUltimate|"
#define IQC_DEFAULT_SOURCE_TF "5"
#define IQC_DEFAULT_MAGIC 9810504
#define IQC_DEFAULT_RISK_PCT 1.00
#define IQC_DEFAULT_AUDIT_PREFIX "NasUltimate_IQCapital_MT5_Audit_"
#define IQC_DASH_PREFIX "IQ_NAS_MT5_DASH_"

#include "IQCapital_MT5_Listener_Core.mqh"