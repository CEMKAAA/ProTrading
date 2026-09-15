// Generated from OrbStrategyMLCore.mqh; regenerate, do not fork.
#ifndef NAS_STRATEGY_ML_CORE_MQH
#define NAS_STRATEGY_ML_CORE_MQH

// Bump the contract when feature semantics, ordering or warm-up change.
#define NAS_ML_SCHEMA "nas.closed256.v1"
#define NAS_ML_FEATURES 40
#define NAS_ML_HIDDEN 16
string NasMlFeatureNames()
{
   return "f_direction,f_body_atr,f_range_atr,f_upper_wick_atr,f_lower_wick_atr,f_return1_atr,f_return5_atr,f_return20_atr,f_rsi14,f_close_ema20_atr,f_close_ema50_atr,f_ema20_50_atr,f_ema_cross,f_volume_ratio20,f_atr_ratio64,f_efficiency20,f_spread_atr,f_hour_sin,f_hour_cos,f_weekday_sin,f_weekday_cos,f_regime_valid,f_regime0,f_regime1,f_regime2,f_regime3,f_regime4,f_regime5,f_regime_trend_depth,f_regime_vol_depth,f_regime_age,f_regime_transition_conf,f_regime_pending,f_sma8_atr,f_sma9_atr,f_sma13_atr,f_supertrend_atr,f_nas_direction,f_ema20_slope_atr,f_invert";
}

string NasMlBytesSha256(const uchar &bytes[])
{
   uchar key[],digest[];
   if(CryptEncode(CRYPT_HASH_SHA256,bytes,key,digest)!=32)return "";
   string result="";
   for(int i=0;i<32;i++)result+=StringFormat("%02x",(uint)digest[i]);
   return result;
}

string NasMlSha256(string value)
{
   uchar bytes[];int n=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(n<=0)return "";
   ArrayResize(bytes,n-1);return NasMlBytesSha256(bytes);
}

bool NasMlNumber(string text,double &value)
{
   int n=StringLen(text);if(n==0)return false;
   int i=0,digits=0;
   if(StringGetCharacter(text,i)=='-'||StringGetCharacter(text,i)=='+')i++;
   while(i<n&&StringGetCharacter(text,i)>='0'&&StringGetCharacter(text,i)<='9'){digits++;i++;}
   if(i<n&&StringGetCharacter(text,i)=='.')
   {
      i++;
      while(i<n&&StringGetCharacter(text,i)>='0'&&StringGetCharacter(text,i)<='9'){digits++;i++;}
   }
   if(digits==0)return false;
   if(i<n&&(StringGetCharacter(text,i)=='e'||StringGetCharacter(text,i)=='E'))
   {
      i++;digits=0;
      if(i<n&&(StringGetCharacter(text,i)=='-'||StringGetCharacter(text,i)=='+'))i++;
      while(i<n&&StringGetCharacter(text,i)>='0'&&StringGetCharacter(text,i)<='9'){digits++;i++;}
      if(digits==0)return false;
   }
   if(i!=n)return false;
   value=StringToDouble(text);
   return MathIsValidNumber(value)&&MathAbs(value)<1e12;
}

struct NasMlNetwork
{
   bool ready;
   string config;
   string dataset;
   datetime lastLabelTime;
   double threshold;
   double mean[NAS_ML_FEATURES];
   double scale[NAS_ML_FEATURES];
   double weights[NAS_ML_FEATURES*NAS_ML_HIDDEN];
   double bias[NAS_ML_HIDDEN];
   double output[NAS_ML_HIDDEN];
   double outputBias;
};

bool NasMlParseModel(string text,const string config,NasMlNetwork &model,string &reason)
{
   model.ready=false;reason="MODEL_FORMAT";
   // Canonical LF serialization is covered by the checksum, including the final payload LF.
   string lines[];int count=StringSplit(text,'\n',lines);
   int expected=8+2*NAS_ML_FEATURES+NAS_ML_FEATURES*NAS_ML_HIDDEN+2*NAS_ML_HIDDEN+1;
   if(count!=expected+2||lines[count-1]!="")return false;
   string payload="";for(int i=0;i<expected;i++)payload+=lines[i]+"\n";
   if(StringLen(lines[expected])!=64||NasMlSha256(payload)!=lines[expected]){reason="MODEL_CHECKSUM";return false;}
   if(lines[0]!="ORB_MLP1"||lines[1]!=NAS_ML_SCHEMA||lines[2]!=config
      ||lines[3]!=NasMlSha256(NasMlFeatureNames())){reason="MODEL_BINDING";return false;}
   if(StringLen(lines[4])!=64)return false;
   double cutoff=0,threshold=0;
   if(!NasMlNumber(lines[5],cutoff)||cutoff<=0||cutoff!=MathFloor(cutoff)
      ||!NasMlNumber(lines[6],threshold)||threshold<=0||threshold>=1||lines[7]!="40,16")return false;
   int pos=8;
   for(int i=0;i<NAS_ML_FEATURES;i++)
   {
      if(!NasMlNumber(lines[pos++],model.mean[i])||!NasMlNumber(lines[pos++],model.scale[i])||model.scale[i]<=1e-12)return false;
   }
   for(int i=0;i<NAS_ML_FEATURES*NAS_ML_HIDDEN;i++)if(!NasMlNumber(lines[pos++],model.weights[i]))return false;
   for(int i=0;i<NAS_ML_HIDDEN;i++)if(!NasMlNumber(lines[pos++],model.bias[i]))return false;
   for(int i=0;i<NAS_ML_HIDDEN;i++)if(!NasMlNumber(lines[pos++],model.output[i]))return false;
   if(!NasMlNumber(lines[pos++],model.outputBias))return false;
   model.config=config;model.dataset=lines[4];model.threshold=threshold;
   model.lastLabelTime=(datetime)cutoff;model.ready=true;reason="MODEL_READY";return true;
}

bool NasMlPredict(const NasMlNetwork &model,const double &x[],double &probability)
{
   probability=0;if(!model.ready||ArraySize(x)!=NAS_ML_FEATURES)return false;
   double score=model.outputBias;
   for(int j=0;j<NAS_ML_HIDDEN;j++)
   {
      double value=model.bias[j];
      for(int i=0;i<NAS_ML_FEATURES;i++)
      {
         if(!MathIsValidNumber(x[i]))return false;
         value+=(x[i]-model.mean[i])/model.scale[i]*model.weights[i*NAS_ML_HIDDEN+j];
      }
      if(!MathIsValidNumber(value))return false;
      score+=MathMax(0.0,value)*model.output[j];
   }
   if(!MathIsValidNumber(score))return false;
   probability=score>=0?1.0/(1.0+MathExp(-score)):MathExp(score)/(1.0+MathExp(score));
   return MathIsValidNumber(probability);
}
#endif
