//+------------------------------------------------------------------+
//| Ultimate Indicator MT5 Debug Scanner EA                          |
//| Generic diagnostic scanner for chart objects and iCustom buffers. |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

input string          InpIndicatorName = "";
input string          InpICustomParamsCsv = "";
input ENUM_TIMEFRAMES InpIndicatorTimeframe = PERIOD_CURRENT;
input int             InpScanBufferMax = 128;
input int             InpScanShiftMax = 120;
input int             InpBufferCandidateShiftMax = 300;
input int             InpBufferCandidatePrintLimit = 80;
input int             InpBufferPairTopN = 18;
input double          InpSignalAbsMin = 0.0000001;
input double          InpPriceMinFactor = 0.20;
input double          InpPriceMaxFactor = 5.00;
input string          InpIgnoreNamePatterns = "autotrade,->,btn_scan,ultimate_scan";
input string          InpObjectNameFilterCsv = "signal,buy,sell,long,short,entry,open,tp,take,target,profit,sl,stop,loss,arrow,dot,circle,zone,level,fib";
input bool            InpLogAllObjects = true;
input bool            InpLogOnlyFilteredObjects = false;
input int             InpObjectPrintLimit = 900;
input int             InpCandidateLookbackSeconds = 172800;
input int             InpNeighborhoodBars = 12;
input int             InpNeighborhoodMaxRows = 220;
input bool            InpPrintFullActiveBuffers = true;
input bool            InpAutoScanOnInit = false;
input bool            InpAutoScanOnTimer = false;
input int             InpAutoScanSeconds = 30;
input string          InpButtonName = "BTN_SCAN_ULTIMATE_MT5";
input int             InpButtonX = 20;
input int             InpButtonY = 170;

#define MAX_PARAMS 24
#define MAX_CAND   64

double g_params[];
int    g_paramCount = 0;
int    g_scanSeq = 0;
int    g_indicatorHandle = INVALID_HANDLE;
ENUM_TIMEFRAMES g_tf = PERIOD_CURRENT;

struct BufferCandidate
{
   int    buffer;
   int    priceCount;
   int    signalCount;
   int    stateCount;
   int    transitions;
   int    freshestShift;
   double firstValue;
   double lastValue;
   double minValue;
   double maxValue;
   double score;
   string quality;
   string roleGuess;
   string sideGuess;
};

BufferCandidate g_candidates[MAX_CAND];
int g_candidateCount = 0;

string _trim(string s){ StringTrimLeft(s); StringTrimRight(s); return s; }

bool _contains_ci(string h,string n)
{
   string hh=h, nn=n;
   StringToLower(hh);
   StringToLower(nn);
   return StringLen(nn)>0 && StringFind(hh,nn)>=0;
}

bool _csv_has_tokens(string csv)
{
   string raw=_trim(csv);
   StringReplace(raw,";",",");
   StringReplace(raw,"|",",");
   string parts[];
   int n=StringSplit(raw,44,parts);
   for(int i=0;i<n;i++) if(StringLen(_trim(parts[i]))>0) return true;
   return false;
}

bool _csv_hit(string csv,string blob)
{
   string raw=_trim(csv);
   StringReplace(raw,";",",");
   StringReplace(raw,"|",",");
   string parts[];
   int n=StringSplit(raw,44,parts);
   for(int i=0;i<n;i++)
   {
      string t=_trim(parts[i]);
      if(StringLen(t)>0 && _contains_ci(blob,t)) return true;
   }
   return false;
}

string _safe(string s)
{
   StringReplace(s,"\r"," ");
   StringReplace(s,"\n"," ");
   StringReplace(s,"'","`");
   return s;
}

string _fmt_time(datetime t){ return (t>0 ? TimeToString(t,TIME_DATE|TIME_SECONDS) : "-"); }

string _fmt_price(double p)
{
   if(!MathIsValidNumber(p) || p==EMPTY_VALUE || p==2147483647.0 || p==0.0) return "-";
   return DoubleToString(p,_Digits);
}

string _color_hex(color c)
{
   int r=((int)c)&0xFF;
   int g=(((int)c)>>8)&0xFF;
   int b=(((int)c)>>16)&0xFF;
   return StringFormat("#%02X%02X%02X",r,g,b);
}

double _bid()
{
   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick) && tick.bid>0.0) return tick.bid;
   return iClose(_Symbol,g_tf,0);
}

double _ask()
{
   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick) && tick.ask>0.0) return tick.ask;
   return _bid();
}

double _spread_points()
{
   MqlTick tick;
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0) point=_Point;
   if(SymbolInfoTick(_Symbol,tick) && tick.ask>0.0 && tick.bid>0.0) return (tick.ask-tick.bid)/point;
   long spread=0;
   if(SymbolInfoInteger(_Symbol,SYMBOL_SPREAD,spread)) return (double)spread;
   return 0.0;
}

double _ref_price()
{
   double b=_bid();
   if(b<=0.0) b=iClose(_Symbol,g_tf,0);
   return b;
}

int _bars(){ return Bars(_Symbol,g_tf); }

double _close(int sh){ return iClose(_Symbol,g_tf,sh); }
double _high(int sh){ return iHigh(_Symbol,g_tf,sh); }
double _low(int sh){ return iLow(_Symbol,g_tf,sh); }

bool _is_empty_like(double v)
{
   return (!MathIsValidNumber(v) || v==EMPTY_VALUE || v==2147483647.0 || v==-2147483647.0);
}

bool _is_signal_value(double v)
{
   return !_is_empty_like(v) && MathAbs(v)>=InpSignalAbsMin;
}

bool _valid_price_like(double v)
{
   if(_is_empty_like(v) || v<=0.0) return false;
   double p=_ref_price();
   if(p<=0.0) return true;
   return (v > p*MathMax(0.01,InpPriceMinFactor) && v < p*MathMax(0.02,InpPriceMaxFactor));
}

bool _is_state_like(double v)
{
   if(_is_empty_like(v)) return false;
   double av=MathAbs(v);
   if(av < InpSignalAbsMin) return false;
   if(_valid_price_like(v)) return false;
   if(av <= 10000.0) return true;
   return false;
}

bool _parse_params()
{
   ArrayResize(g_params,0);
   g_paramCount=0;
   string raw=_trim(InpICustomParamsCsv);
   if(StringLen(raw)==0) return true;
   StringReplace(raw,";",",");
   StringReplace(raw,"|",",");
   string toks[];
   int n=StringSplit(raw,44,toks);
   for(int i=0;i<n && g_paramCount<MAX_PARAMS;i++)
   {
      string t=_trim(toks[i]);
      if(StringLen(t)<=0) continue;
      string tl=t;
      StringToLower(tl);
      ArrayResize(g_params,g_paramCount+1);
      if(tl=="true") g_params[g_paramCount++]=1.0;
      else if(tl=="false") g_params[g_paramCount++]=0.0;
      else g_params[g_paramCount++]=StringToDouble(t);
   }
   return true;
}

void _release_handle()
{
   if(g_indicatorHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_indicatorHandle);
      g_indicatorHandle=INVALID_HANDLE;
   }
}

bool _create_handle()
{
   _release_handle();
   string ind=_trim(InpIndicatorName);
   if(StringLen(ind)<=0) return false;
   int c=g_paramCount;
   ResetLastError();
   if(c<=0) g_indicatorHandle=iCustom(_Symbol,g_tf,ind);
   else if(c==1) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0]);
   else if(c==2) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1]);
   else if(c==3) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2]);
   else if(c==4) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3]);
   else if(c==5) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4]);
   else if(c==6) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5]);
   else if(c==7) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6]);
   else if(c==8) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7]);
   else if(c==9) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7],g_params[8]);
   else if(c==10) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7],g_params[8],g_params[9]);
   else if(c==11) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7],g_params[8],g_params[9],g_params[10]);
   else if(c==12) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7],g_params[8],g_params[9],g_params[10],g_params[11]);
   else if(c==13) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7],g_params[8],g_params[9],g_params[10],g_params[11],g_params[12]);
   else if(c==14) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7],g_params[8],g_params[9],g_params[10],g_params[11],g_params[12],g_params[13]);
   else if(c==15) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7],g_params[8],g_params[9],g_params[10],g_params[11],g_params[12],g_params[13],g_params[14]);
   else if(c==16) g_indicatorHandle=iCustom(_Symbol,g_tf,ind,g_params[0],g_params[1],g_params[2],g_params[3],g_params[4],g_params[5],g_params[6],g_params[7],g_params[8],g_params[9],g_params[10],g_params[11],g_params[12],g_params[13],g_params[14],g_params[15]);
   else g_indicatorHandle=iCustom(_Symbol,g_tf,ind);
   if(g_indicatorHandle==INVALID_HANDLE)
   {
      Print("ULTIMATE_MT5 handle_create_failed indicator='",ind,"' err=",GetLastError()," params_count=",g_paramCount);
      return false;
   }
   return true;
}

double _buffer_value(int b,int sh)
{
   if(g_indicatorHandle==INVALID_HANDLE) return EMPTY_VALUE;
   double arr[];
   ArraySetAsSeries(arr,true);
   ResetLastError();
   int copied=CopyBuffer(g_indicatorHandle,b,sh,1,arr);
   if(copied<=0) return EMPTY_VALUE;
   return arr[0];
}

string _buffer_row(int bufferIndex,int maxShift,int mode)
{
   string row="";
   int n=MathMax(1,MathMin(60,maxShift));
   int bars=_bars();
   for(int sh=0; sh<n && sh<bars; sh++)
   {
      double v=_buffer_value(bufferIndex,sh);
      bool mark=false;
      if(mode==1) mark=_valid_price_like(v);
      else if(mode==2) mark=_is_state_like(v);
      else mark=_is_signal_value(v);
      row += StringFormat(" sh%d=%s%s",sh,DoubleToString(v,_Digits),(mark?"*":""));
   }
   return row;
}

string _object_blob(string name)
{
   string text=ObjectGetString(0,name,OBJPROP_TEXT);
   string tip=ObjectGetString(0,name,OBJPROP_TOOLTIP);
   return name+" "+text+" "+tip;
}

string _direction_guess_from_blob(string blob,int type,long code,color c)
{
   string lc=blob;
   StringToLower(lc);
   bool buy=(StringFind(lc,"buy")>=0 || StringFind(lc,"long")>=0 || StringFind(lc,"bull")>=0 || StringFind(lc,"up")>=0);
   bool sell=(StringFind(lc,"sell")>=0 || StringFind(lc,"short")>=0 || StringFind(lc,"bear")>=0 || StringFind(lc,"down")>=0);
   if(buy && !sell) return "BUY";
   if(sell && !buy) return "SELL";
   if(type==OBJ_ARROW)
   {
      if(code==233 || code==241 || code==225 || code==217) return "BUY_ARROW_GUESS";
      if(code==234 || code==242 || code==226 || code==218) return "SELL_ARROW_GUESS";
   }
   int r=((int)c)&0xFF;
   int g=(((int)c)>>8)&0xFF;
   int b=(((int)c)>>16)&0xFF;
   if(g>140 && r<120) return "BUY_COLOR_GUESS";
   if(r>140 && g<120) return "SELL_COLOR_GUESS";
   return "";
}

string _role_guess_from_blob(string blob,int type,double p0,double p1)
{
   string lc=blob;
   StringToLower(lc);
   if(StringFind(lc,"tp3")>=0 || StringFind(lc,"target3")>=0 || StringFind(lc,"take3")>=0) return "TP3";
   if(StringFind(lc,"tp2")>=0 || StringFind(lc,"target2")>=0 || StringFind(lc,"take2")>=0) return "TP2";
   if(StringFind(lc,"tp1")>=0 || StringFind(lc,"target1")>=0 || StringFind(lc,"take1")>=0) return "TP1";
   if(StringFind(lc,"tp")>=0 || StringFind(lc,"target")>=0 || StringFind(lc,"take profit")>=0 || StringFind(lc,"profit")>=0) return "TP";
   if(StringFind(lc,"sl")>=0 || StringFind(lc,"stop")>=0 || StringFind(lc,"loss")>=0) return "SL";
   if(StringFind(lc,"entry")>=0 || StringFind(lc,"open")>=0 || StringFind(lc,"price")>=0) return "ENTRY";
   if(StringFind(lc,"crab")>=0 || StringFind(lc,"shark")>=0 || StringFind(lc,"gartley")>=0 || StringFind(lc,"bat")>=0 || StringFind(lc,"butterfly")>=0 || StringFind(lc,"cypher")>=0 || StringFind(lc,"abcd")>=0 || StringFind(lc,"harmonic")>=0 || StringFind(lc,"pattern")>=0) return "SIGNAL";
   if(StringFind(lc,"signal")>=0 || StringFind(lc,"arrow")>=0 || StringFind(lc,"buy")>=0 || StringFind(lc,"sell")>=0 || StringFind(lc,"long")>=0 || StringFind(lc,"short")>=0) return "SIGNAL";
   if(type==OBJ_ARROW) return "SIGNAL_ARROW";
   if(type==OBJ_HLINE || type==OBJ_TREND || type==OBJ_RECTANGLE || type==OBJ_RECTANGLE_LABEL)
   {
      if(_valid_price_like(p0) || _valid_price_like(p1)) return "LEVEL_OR_ZONE";
   }
   return "";
}

int _object_score(string role,string dir,string blob,datetime t0,double p0)
{
   int score=0;
   if(StringLen(role)>0) score+=20;
   if(StringLen(dir)>0) score+=30;
   if(_valid_price_like(p0)) score+=12;
   if(t0>0) score+=12;
   if(_csv_hit(InpObjectNameFilterCsv,blob)) score+=18;
   if(role=="ENTRY" || role=="SL" || role=="TP" || role=="TP1" || role=="TP2" || role=="TP3") score+=20;
   if(role=="SIGNAL" || role=="SIGNAL_ARROW") score+=20;
   return score;
}

void _add_candidate(BufferCandidate &c)
{
   if(g_candidateCount<MAX_CAND){ g_candidates[g_candidateCount++]=c; return; }
   int worst=0;
   for(int i=1;i<MAX_CAND;i++) if(g_candidates[i].score<g_candidates[worst].score) worst=i;
   if(c.score>g_candidates[worst].score) g_candidates[worst]=c;
}

void _sort_candidates()
{
   for(int i=0;i<g_candidateCount-1;i++)
      for(int j=i+1;j<g_candidateCount;j++)
         if(g_candidates[j].score>g_candidates[i].score)
         {
            BufferCandidate tmp=g_candidates[i];
            g_candidates[i]=g_candidates[j];
            g_candidates[j]=tmp;
         }
}

void PrintBufferCandidates()
{
   g_candidateCount=0;
   if(g_indicatorHandle==INVALID_HANDLE)
   {
      Print("ULTIMATE_MT5_BUFFER_CANDIDATE summary seq=",g_scanSeq," candidates=0 reason=no_indicator_handle");
      return;
   }
   int maxB=MathMax(1,MathMin(512,InpScanBufferMax));
   int maxS=MathMax(5,MathMin(1000,InpBufferCandidateShiftMax));
   int bars=_bars();
   double ref=_ref_price();

   for(int b=0;b<maxB;b++)
   {
      int priceCount=0, signalCount=0, stateCount=0, transitions=0, lastActive=-1, freshest=999999;
      int aboveClose=0, belowClose=0, lowMarker=0, highMarker=0;
      double first=0,last=0,minV=0,maxV=0;
      for(int sh=0; sh<maxS && sh<bars; sh++)
      {
         double v=_buffer_value(b,sh);
         bool priceLike=_valid_price_like(v);
         bool stateLike=_is_state_like(v);
         bool signalLike=_is_signal_value(v);
         bool active=priceLike || stateLike || signalLike;
         if(active && sh<freshest) freshest=sh;
         if(priceLike)
         {
            if(priceCount==0){ first=v; minV=v; maxV=v; }
            last=v;
            if(v<minV) minV=v;
            if(v>maxV) maxV=v;
            priceCount++;
            double c=_close(sh);
            if(c>0.0)
            {
               if(v>c) aboveClose++;
               if(v<c) belowClose++;
            }
            if(v<=_low(sh)) lowMarker++;
            if(v>=_high(sh)) highMarker++;
         }
         else if(stateLike) stateCount++;
         else if(signalLike) signalCount++;
         int cur=active ? 1 : 0;
         if(lastActive>=0 && cur!=lastActive) transitions++;
         lastActive=cur;
      }
      if(priceCount<=0 && stateCount<=0 && signalCount<=0) continue;

      double denom=(double)MathMax(1,MathMin(maxS,bars));
      double priceCov=100.0*priceCount/denom;
      double stateCov=100.0*stateCount/denom;
      string quality="sparse_signal";
      if(priceCov>=80.0) quality="continuous_price_level";
      else if(priceCov>=25.0) quality="segmented_price_level";
      else if(priceCount>0) quality="sparse_price_signal";
      else if(stateCov>=50.0) quality="state_buffer";
      else if(stateCount>0) quality="sparse_state_signal";

      string side="MIXED";
      if(aboveClose>belowClose*2) side="ABOVE_PRICE";
      else if(belowClose>aboveClose*2) side="BELOW_PRICE";
      if(highMarker>lowMarker*2) side="ARROW_ABOVE_CANDLE_SELL_GUESS";
      else if(lowMarker>highMarker*2) side="ARROW_BELOW_CANDLE_BUY_GUESS";

      string role="UNKNOWN";
      if(priceCount>0 && priceCov>=25.0) role="LEVEL_BUFFER";
      else if(priceCount>0 && (lowMarker>0 || highMarker>0)) role="ARROW_PRICE_SIGNAL";
      else if(stateCount>0) role="STATE_SIGNAL";
      else role="RAW_SIGNAL";

      double score=priceCount*2.0 + stateCount*1.2 + signalCount + MathMax(0,50-freshest)*4 + transitions*0.6;
      if(StringFind(role,"SIGNAL")>=0) score+=25;
      if(priceCount>0 && priceCov<20.0) score+=18;

      BufferCandidate cnd;
      cnd.buffer=b; cnd.priceCount=priceCount; cnd.signalCount=signalCount; cnd.stateCount=stateCount; cnd.transitions=transitions;
      cnd.freshestShift=(freshest==999999 ? -1 : freshest); cnd.firstValue=first; cnd.lastValue=last; cnd.minValue=minV; cnd.maxValue=maxV;
      cnd.score=score; cnd.quality=quality; cnd.roleGuess=role; cnd.sideGuess=side;
      _add_candidate(cnd);

      if(g_candidateCount<=InpBufferCandidatePrintLimit || score>20)
      {
         PrintFormat("ULTIMATE_MT5_BUFFER_CANDIDATE seq=%d buffer=%d role=%s quality=%s side=%s score=%.1f price_valid=%d/%d state=%d raw_signal=%d coverage=%.1f%% transitions=%d freshest_shift=%d first=%s last=%s min=%s max=%s row=%s",
            g_scanSeq,b,role,quality,side,score,priceCount,(int)denom,stateCount,signalCount,priceCov,transitions,cnd.freshestShift,
            DoubleToString(first,_Digits),DoubleToString(last,_Digits),DoubleToString(minV,_Digits),DoubleToString(maxV,_Digits),
            _buffer_row(b,MathMin(30,maxS),(priceCount>0?1:(stateCount>0?2:0))));
      }
   }
   _sort_candidates();
   Print("ULTIMATE_MT5_BUFFER_CANDIDATE summary seq=",g_scanSeq," candidates=",g_candidateCount," buffers_scanned=",maxB," shifts=",maxS," ref=",DoubleToString(ref,_Digits));
}

bool _buffer_active_at(int b,int sh)
{
   double v=_buffer_value(b,sh);
   return _valid_price_like(v) || _is_state_like(v) || _is_signal_value(v);
}

void PrintBufferPairs()
{
   if(g_indicatorHandle==INVALID_HANDLE)
   {
      Print("ULTIMATE_MT5_BUFFER_PAIR summary seq=",g_scanSeq," printed=0 reason=no_indicator_handle");
      return;
   }
   int n=MathMin(g_candidateCount,MathMax(2,InpBufferPairTopN));
   int maxS=MathMax(5,MathMin(300,InpBufferCandidateShiftMax));
   int bars=_bars();
   int printed=0;
   for(int i=0;i<n;i++)
   {
      for(int j=i+1;j<n;j++)
      {
         int bi=g_candidates[i].buffer, bj=g_candidates[j].buffer;
         int both=0, onlyI=0, onlyJ=0, any=0, alternations=0, lastSide=0;
         for(int sh=0; sh<maxS && sh<bars; sh++)
         {
            bool ai=_buffer_active_at(bi,sh), aj=_buffer_active_at(bj,sh);
            if(ai||aj) any++;
            if(ai&&aj) both++; else if(ai) onlyI++; else if(aj) onlyJ++;
            int side=(ai&&!aj)?1:((aj&&!ai)?2:0);
            if(side>0 && lastSide>0 && side!=lastSide) alternations++;
            if(side>0) lastSide=side;
         }
         if(any<=0 || onlyI<=0 || onlyJ<=0) continue;
         double overlap=100.0*both/any;
         if(overlap>35.0 && alternations<1) continue;
         string hint="POSSIBLE_BUY_SELL_PAIR";
         if(StringFind(g_candidates[i].sideGuess,"BUY")>=0 || StringFind(g_candidates[j].sideGuess,"SELL")>=0) hint="bufferA_BUY_bufferB_SELL_GUESS";
         if(StringFind(g_candidates[i].sideGuess,"SELL")>=0 || StringFind(g_candidates[j].sideGuess,"BUY")>=0) hint="bufferA_SELL_bufferB_BUY_GUESS";
         PrintFormat("ULTIMATE_MT5_BUFFER_PAIR seq=%d buffer_a=%d buffer_b=%d hint=%s only_a=%d only_b=%d both=%d any=%d overlap=%.1f%% alternations=%d row_a=%s row_b=%s",
            g_scanSeq,bi,bj,hint,onlyI,onlyJ,both,any,overlap,alternations,_buffer_row(bi,MathMin(20,maxS),1),_buffer_row(bj,MathMin(20,maxS),1));
         if(++printed>=MathMax(4,InpBufferPairTopN))
         {
            Print("ULTIMATE_MT5_BUFFER_PAIR summary seq=",g_scanSeq," printed=",printed);
            return;
         }
      }
   }
   Print("ULTIMATE_MT5_BUFFER_PAIR summary seq=",g_scanSeq," printed=",printed);
}

void PrintObjectsAndCandidates(datetime &latestSignalTime,string &latestSignalName,string &latestSignalDir,double &latestSignalPrice)
{
   latestSignalTime=0; latestSignalName=""; latestSignalDir=""; latestSignalPrice=0.0;
   int total=ObjectsTotal(0,-1,-1);
   int typeCounts[128]; ArrayInitialize(typeCounts,0);
   int printed=0, ignored=0, candPrinted=0;
   datetime fallbackTime=0;
   string fallbackName="", fallbackDir="";
   double fallbackPrice=0.0;
   bool hasFilter=_csv_has_tokens(InpObjectNameFilterCsv);
   datetime minTime=TimeCurrent()-MathMax(60,InpCandidateLookbackSeconds);

   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(name==InpButtonName) continue;
      if(_csv_hit(InpIgnoreNamePatterns,name)){ ignored++; continue; }
      int type=(int)ObjectGetInteger(0,name,OBJPROP_TYPE);
      if(type>=0 && type<128) typeCounts[type]++;
      datetime t0=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
      datetime t1=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,1);
      double p0=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
      double p1=ObjectGetDouble(0,name,OBJPROP_PRICE,1);
      long code=ObjectGetInteger(0,name,OBJPROP_ARROWCODE);
      color c=(color)ObjectGetInteger(0,name,OBJPROP_COLOR);
      string text=ObjectGetString(0,name,OBJPROP_TEXT);
      string tip=ObjectGetString(0,name,OBJPROP_TOOLTIP);
      string blob=name+" "+text+" "+tip;
      string dir=_direction_guess_from_blob(blob,type,code,c);
      string role=_role_guess_from_blob(blob,type,p0,p1);
      int score=_object_score(role,dir,blob,t0,p0);
      bool candidate=(score>=30 || _csv_hit(InpObjectNameFilterCsv,blob));
      bool signalAnchor = (role=="SIGNAL" || role=="SIGNAL_ARROW");
      if(candidate && StringLen(dir)>0 && signalAnchor && t0>latestSignalTime)
      {
         latestSignalTime=t0; latestSignalName=name; latestSignalDir=dir; latestSignalPrice=p0;
      }
      if(candidate && StringLen(dir)>0 && t0>fallbackTime)
      {
         fallbackTime=t0; fallbackName=name; fallbackDir=dir; fallbackPrice=p0;
      }
      if(!InpLogAllObjects && !candidate) continue;
      if(InpLogOnlyFilteredObjects && hasFilter && !_csv_hit(InpObjectNameFilterCsv,blob)) continue;
      if(printed<MathMax(20,InpObjectPrintLimit))
      {
         PrintFormat("ULTIMATE_MT5_OBJECT seq=%d row=%03d score=%d role=%s dir=%s type=%d name='%s' time0=%s price0=%s time1=%s price1=%s code=%d color=%s text='%s' tip='%s'",
            g_scanSeq,i,score,role,dir,type,name,_fmt_time(t0),_fmt_price(p0),_fmt_time(t1),_fmt_price(p1),(int)code,_color_hex(c),_safe(text),_safe(tip));
         printed++;
      }
      if(candidate && t0>=minTime && candPrinted<MathMax(20,InpObjectPrintLimit))
      {
         PrintFormat("ULTIMATE_MT5_OBJECT_CANDIDATE seq=%d row=%03d score=%d role=%s dir=%s type=%d name='%s' time0=%s price0=%s time1=%s price1=%s code=%d color=%s text='%s' tip='%s'",
            g_scanSeq,i,score,role,dir,type,name,_fmt_time(t0),_fmt_price(p0),_fmt_time(t1),_fmt_price(p1),(int)code,_color_hex(c),_safe(text),_safe(tip));
         candPrinted++;
      }
   }
   if(latestSignalTime<=0 && fallbackTime>0)
   {
      latestSignalTime=fallbackTime;
      latestSignalName=fallbackName;
      latestSignalDir=fallbackDir;
      latestSignalPrice=fallbackPrice;
   }
   string typeSummary="";
   for(int tc=0;tc<128;tc++) if(typeCounts[tc]>0) typeSummary+=StringFormat(" type%d=%d",tc,typeCounts[tc]);
   Print("ULTIMATE_MT5_OBJECT summary seq=",g_scanSeq," printed=",printed," candidates=",candPrinted," ignored=",ignored," total=",total);
   Print("ULTIMATE_MT5_OBJECT type_summary seq=",g_scanSeq,typeSummary);
}

void PrintSetupNeighborhood(datetime anchorTime,string anchorName,string anchorDir,double anchorPrice)
{
   if(anchorTime<=0)
   {
      Print("ULTIMATE_MT5_SETUP_GROUP none seq=",g_scanSeq," reason=no_directional_object_candidate");
      return;
   }
   int secPerBar=PeriodSeconds(g_tf);
   if(secPerBar<=0) secPerBar=60;
   int radiusSec=MathMax(secPerBar,MathMax(1,InpNeighborhoodBars)*secPerBar);
   datetime tMin=anchorTime-radiusSec, tMax=anchorTime+radiusSec;
   PrintFormat("ULTIMATE_MT5_SETUP_GROUP anchor seq=%d dir=%s time=%s price=%s name='%s' radius_bars=%d",
      g_scanSeq,anchorDir,_fmt_time(anchorTime),_fmt_price(anchorPrice),anchorName,MathMax(1,InpNeighborhoodBars));

   double entry=0, sl=0, tp1=0, tp2=0, tp3=0;
   string entryName="", slName="", tp1Name="", tp2Name="", tp3Name="";
   int total=ObjectsTotal(0,-1,-1), printed=0;
   for(int i=total-1;i>=0;i--)
   {
      string name=ObjectName(0,i,-1,-1);
      if(name==InpButtonName || _csv_hit(InpIgnoreNamePatterns,name)) continue;
      datetime t0=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
      datetime t1=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,1);
      if(t0<tMin || t0>tMax) continue;
      int type=(int)ObjectGetInteger(0,name,OBJPROP_TYPE);
      double p0=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
      double p1=ObjectGetDouble(0,name,OBJPROP_PRICE,1);
      long code=ObjectGetInteger(0,name,OBJPROP_ARROWCODE);
      color c=(color)ObjectGetInteger(0,name,OBJPROP_COLOR);
      string text=ObjectGetString(0,name,OBJPROP_TEXT);
      string tip=ObjectGetString(0,name,OBJPROP_TOOLTIP);
      string blob=_object_blob(name);
      string dir=_direction_guess_from_blob(blob,type,code,c);
      string role=_role_guess_from_blob(blob,type,p0,p1);
      int score=_object_score(role,dir,blob,t0,p0);
      PrintFormat("ULTIMATE_MT5_SETUP_GROUP row=%03d score=%d role=%s dir=%s type=%d name='%s' time0=%s price0=%s time1=%s price1=%s code=%d color=%s text='%s' tip='%s'",
         i,score,role,dir,type,name,_fmt_time(t0),_fmt_price(p0),_fmt_time(t1),_fmt_price(p1),(int)code,_color_hex(c),_safe(text),_safe(tip));
      if(_valid_price_like(p0))
      {
         if(role=="ENTRY" && entry==0){ entry=p0; entryName=name; }
         else if(role=="SL" && sl==0){ sl=p0; slName=name; }
         else if(role=="TP1" && tp1==0){ tp1=p0; tp1Name=name; }
         else if(role=="TP2" && tp2==0){ tp2=p0; tp2Name=name; }
         else if(role=="TP3" && tp3==0){ tp3=p0; tp3Name=name; }
         else if(role=="TP" && tp1==0){ tp1=p0; tp1Name=name; }
      }
      if(++printed>=MathMax(20,InpNeighborhoodMaxRows)) break;
   }
   PrintFormat("ULTIMATE_MT5_SETUP_RESOLVED seq=%d dir=%s signal_time=%s signal_name='%s' signal_price=%s entry=%s entry_name='%s' sl=%s sl_name='%s' tp1=%s tp1_name='%s' tp2=%s tp2_name='%s' tp3=%s tp3_name='%s' rows=%d",
      g_scanSeq,anchorDir,_fmt_time(anchorTime),anchorName,_fmt_price(anchorPrice),_fmt_price(entry),entryName,_fmt_price(sl),slName,_fmt_price(tp1),tp1Name,_fmt_price(tp2),tp2Name,_fmt_price(tp3),tp3Name,printed);
}

void PrintFullActiveBuffers()
{
   if(!InpPrintFullActiveBuffers || g_indicatorHandle==INVALID_HANDLE) return;
   int maxB=MathMax(1,MathMin(512,InpScanBufferMax));
   int maxS=MathMax(1,MathMin(300,InpScanShiftMax));
   int bars=_bars();
   for(int b=0;b<maxB;b++)
   {
      bool active=false; int mode=0;
      for(int sh=0;sh<maxS && sh<bars;sh++)
      {
         double v=_buffer_value(b,sh);
         if(_valid_price_like(v)){ active=true; mode=1; break; }
         if(_is_state_like(v)){ active=true; mode=2; }
         else if(_is_signal_value(v)) active=true;
      }
      if(active) Print("ULTIMATE_MT5_BUFFER_ROW seq=",g_scanSeq," buffer=",b," mode=",mode," row=",_buffer_row(b,maxS,mode));
   }
}

void CreateButton()
{
   ObjectDelete(0,InpButtonName);
   ObjectCreate(0,InpButtonName,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,InpButtonName,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,InpButtonName,OBJPROP_XDISTANCE,InpButtonX);
   ObjectSetInteger(0,InpButtonName,OBJPROP_YDISTANCE,InpButtonY);
   ObjectSetInteger(0,InpButtonName,OBJPROP_XSIZE,220);
   ObjectSetInteger(0,InpButtonName,OBJPROP_YSIZE,30);
   ObjectSetString(0,InpButtonName,OBJPROP_TEXT,"ULTIMATE MT5 SCAN");
   ObjectSetInteger(0,InpButtonName,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,InpButtonName,OBJPROP_BGCOLOR,C'30,90,180');
   ObjectSetInteger(0,InpButtonName,OBJPROP_HIDDEN,true);
   ChartRedraw(0);
}

void RunScan(string reason)
{
   g_scanSeq++;
   Print("------------------------------------------------------------");
   PrintFormat("ULTIMATE_MT5_SCAN_BEGIN seq=%d reason=%s symbol=%s tf=%s indicator='%s' params='%s' time=%s bid=%s ask=%s spread_points=%.1f bars=%d objects=%d handle=%d",
      g_scanSeq,reason,_Symbol,EnumToString(g_tf),InpIndicatorName,InpICustomParamsCsv,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      DoubleToString(_bid(),_Digits),DoubleToString(_ask(),_Digits),_spread_points(),_bars(),ObjectsTotal(0,-1,-1),g_indicatorHandle);

   datetime latestTime; string latestName, latestDir; double latestPrice;
   PrintObjectsAndCandidates(latestTime,latestName,latestDir,latestPrice);
   PrintSetupNeighborhood(latestTime,latestName,latestDir,latestPrice);
   PrintBufferCandidates();
   PrintBufferPairs();
   PrintFullActiveBuffers();

   PrintFormat("ULTIMATE_MT5_SCAN_END seq=%d reason=%s symbol=%s tf=%s indicator='%s'",g_scanSeq,reason,_Symbol,EnumToString(g_tf),InpIndicatorName);
   Print("------------------------------------------------------------");
}

int OnInit()
{
   g_tf=(InpIndicatorTimeframe==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpIndicatorTimeframe);
   _parse_params();
   _create_handle();
   CreateButton();
   EventSetTimer(MathMax(1,InpAutoScanSeconds));
   Print("UltimateIndicator MT5 Scanner loaded. Attach target indicator if it draws chart objects, set InpIndicatorName for iCustom buffers, then press ULTIMATE MT5 SCAN.");
   Print("UltimateIndicator MT5 indicator='",InpIndicatorName,"' tf=",EnumToString(g_tf)," params_count=",g_paramCount," handle=",g_indicatorHandle," autoscan=",(InpAutoScanOnTimer?"true":"false"));
   if(InpAutoScanOnInit) RunScan("init");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectDelete(0,InpButtonName);
   _release_handle();
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==InpButtonName)
   {
      ObjectSetInteger(0,InpButtonName,OBJPROP_STATE,false);
      RunScan("button");
   }
}

void OnTimer()
{
   if(InpAutoScanOnTimer) RunScan("timer");
}

void OnTick(){}
