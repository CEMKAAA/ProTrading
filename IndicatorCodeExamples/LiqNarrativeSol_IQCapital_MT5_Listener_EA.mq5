#property strict
#property version "1.00"

#define IQC_LISTENER_BUILD "2026-07-26.iq-sol-mt5-listener-v1"
#define IQC_PIPELINE_ID "IQSolVersionMT5"
#define IQC_DEFAULT_FILE "LiqNarrativeSolBridge_Latest_JP225m_60.csv"
#define IQC_DEFAULT_SOURCE_FILTER "LiqNarrativeSol|"
#define IQC_DEFAULT_SOURCE_TF "60"
#define IQC_DEFAULT_MAGIC 9810601
#define IQC_DEFAULT_RISK_PCT 0.50
#define IQC_DEFAULT_AUDIT_PREFIX "LiqNarrativeSol_IQCapital_MT5_Audit_"
#define IQC_DASH_PREFIX "IQ_SOL_MT5_DASH_"

#include "IQCapital_MT5_Listener_Core.mqh"
