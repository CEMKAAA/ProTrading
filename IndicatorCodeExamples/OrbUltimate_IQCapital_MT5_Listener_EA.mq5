#property strict
#property version "1.00"

#define IQC_LISTENER_BUILD "2026-07-26.iq-orb-mt5-listener-v1"
#define IQC_PIPELINE_ID "IQOrbUltimateMT5"
#define IQC_DEFAULT_FILE "OrbUltimateBridge_Latest_JP225m_15.csv"
#define IQC_DEFAULT_SOURCE_FILTER "OrbUltimate|"
#define IQC_DEFAULT_SOURCE_TF "15"
#define IQC_DEFAULT_MAGIC 9811503
#define IQC_DEFAULT_RISK_PCT 1.00
#define IQC_DEFAULT_AUDIT_PREFIX "OrbUltimate_IQCapital_MT5_Audit_"
#define IQC_DASH_PREFIX "IQ_ORB_MT5_DASH_"

#include "IQCapital_MT5_Listener_Core.mqh"
