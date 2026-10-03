#ifndef ORB_STRATEGY_ML_CORE_MQH
#define ORB_STRATEGY_ML_CORE_MQH

// Bump the contract when feature semantics, ordering or warm-up change.
#define ORB_ML_SCHEMA "orb.closed256.v1"
#define ORB_ML_FEATURES 40
#define ORB_ML_HIDDEN 16
string OrbMlFeatureNames()
{
   return "f_direction,f_body_atr,f_range_atr,f_upper_wick_atr,f_lower_wick_atr,"
      "f_return1_atr,f_return5_atr,f_return20_atr,f_rsi14,f_close_ema20_atr,"
      "f_close_ema50_atr,f_ema20_50_atr,f_ema_cross,f_volume_ratio20,f_atr_ratio64,"
      "f_efficiency20,f_spread_atr,f_hour_sin,f_hour_cos,f_weekday_sin,f_weekday_cos,"
      "f_regime_valid,f_regime0,f_regime1,f_regime2,f_regime3,f_regime4,f_regime5,"
      "f_regime_trend_depth,f_regime_vol_depth,f_regime_age,f_regime_transition_conf,"
      "f_regime_pending,f_rf_index,f_orb_range_atr,f_close_orb_high_atr,"
      "f_close_orb_low_atr,f_minutes_from_orb_end,f_ema20_slope_atr,f_invert";
}

string OrbMlBytesSha256(const uchar &bytes[])
{
   uchar key[],digest[];
   if(CryptEncode(CRYPT_HASH_SHA256,bytes,key,digest)!=32)return "";
   string result="";
   for(int i=0;i<32;i++)result+=StringFormat("%02x",(uint)digest[i]);
   return result;
}

string OrbMlSha256(string value)
{
   uchar bytes[];int n=StringToCharArray(value,bytes,0,WHOLE_ARRAY,CP_UTF8);
   if(n<=0)return "";
   ArrayResize(bytes,n-1);return OrbMlBytesSha256(bytes);
}

bool OrbMlNumber(string text,double &value,double maximum=1e12)
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
   return MathIsValidNumber(value)&&(maximum==DBL_MAX||MathAbs(value)<maximum);
}

struct OrbMlNetwork
{
   bool ready;
   string config;
   string dataset;
   datetime lastLabelTime;
   double threshold;
   double mean[ORB_ML_FEATURES];
   double scale[ORB_ML_FEATURES];
   double weights[ORB_ML_FEATURES*ORB_ML_HIDDEN];
   double bias[ORB_ML_HIDDEN];
   double output[ORB_ML_HIDDEN];
   double outputBias;
};

bool OrbMlParseModel(string text,const string config,OrbMlNetwork &model,string &reason)
{
   model.ready=false;reason="MODEL_FORMAT";
   // Canonical LF serialization is covered by the checksum, including the final payload LF.
   string lines[];int count=StringSplit(text,'\n',lines);
   int expected=8+2*ORB_ML_FEATURES+ORB_ML_FEATURES*ORB_ML_HIDDEN+2*ORB_ML_HIDDEN+1;
   if(count!=expected+2||lines[count-1]!="")return false;
   string payload="";for(int i=0;i<expected;i++)payload+=lines[i]+"\n";
   if(StringLen(lines[expected])!=64||OrbMlSha256(payload)!=lines[expected]){reason="MODEL_CHECKSUM";return false;}
   if(lines[0]!="ORB_MLP1"||lines[1]!=ORB_ML_SCHEMA||lines[2]!=config
      ||lines[3]!=OrbMlSha256(OrbMlFeatureNames())){reason="MODEL_BINDING";return false;}
   if(StringLen(lines[4])!=64)return false;
   double cutoff=0,threshold=0;
   if(!OrbMlNumber(lines[5],cutoff)||cutoff<=0||cutoff!=MathFloor(cutoff)
      ||!OrbMlNumber(lines[6],threshold)||threshold<=0||threshold>=1||lines[7]!="40,16")return false;
   int pos=8;
   for(int i=0;i<ORB_ML_FEATURES;i++)
   {
      if(!OrbMlNumber(lines[pos++],model.mean[i])||!OrbMlNumber(lines[pos++],model.scale[i])||model.scale[i]<=1e-12)return false;
   }
   for(int i=0;i<ORB_ML_FEATURES*ORB_ML_HIDDEN;i++)if(!OrbMlNumber(lines[pos++],model.weights[i]))return false;
   for(int i=0;i<ORB_ML_HIDDEN;i++)if(!OrbMlNumber(lines[pos++],model.bias[i]))return false;
   for(int i=0;i<ORB_ML_HIDDEN;i++)if(!OrbMlNumber(lines[pos++],model.output[i]))return false;
   if(!OrbMlNumber(lines[pos++],model.outputBias))return false;
   model.config=config;model.dataset=lines[4];model.threshold=threshold;
   model.lastLabelTime=(datetime)cutoff;model.ready=true;reason="MODEL_READY";return true;
}

bool OrbMlPredict(const OrbMlNetwork &model,const double &x[],double &probability)
{
   probability=0;if(!model.ready||ArraySize(x)!=ORB_ML_FEATURES)return false;
   double score=model.outputBias;
   for(int j=0;j<ORB_ML_HIDDEN;j++)
   {
      double value=model.bias[j];
      for(int i=0;i<ORB_ML_FEATURES;i++)
      {
         if(!MathIsValidNumber(x[i]))return false;
         value+=(x[i]-model.mean[i])/model.scale[i]*model.weights[i*ORB_ML_HIDDEN+j];
      }
      if(!MathIsValidNumber(value))return false;
      score+=MathMax(0.0,value)*model.output[j];
   }
   if(!MathIsValidNumber(score))return false;
   probability=score>=0?1.0/(1.0+MathExp(-score)):MathExp(score)/(1.0+MathExp(score));
   return MathIsValidNumber(probability);
}
#endif
