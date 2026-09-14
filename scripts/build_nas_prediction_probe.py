"""Verify NAS portable inference on real candidate vectors, never activate it."""
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]
REPORT=ROOT/'logs/NasStrategyLibrary_20260912'
STAGE=ROOT/'.tmp/orb_jp225_full_worker/MQL5/Scripts/NasPredictionProbe'
FILES=ROOT/'.tmp/orb_jp225_full_worker/MQL5/Files/NasPredictionProbe'

def main():
    STAGE.mkdir(parents=True,exist_ok=True);FILES.mkdir(parents=True,exist_ok=True)
    shutil.copy2(ROOT/'IndicatorCodeExamples/NasStrategyMLCore.mqh',STAGE/'NasStrategyMLCore.mqh')
    campaign=REPORT/'campaign_current/campaign.json'
    if not campaign.exists():campaign=REPORT/'campaign/campaign.json'
    report=json.loads(campaign.read_text());calls=[]
    for row in report['results']:
        if 'dataset' not in row:continue
        info=row['dataset'];base=Path(row['csv']).parents[1]
        for mode,model in row['models'].items():
            if 'model_sha256' not in model:continue
            key=info['config_hash'];name=f'm{len(calls)}';source=base/'Models'/mode
            shutil.copy2(source/(key+'.candidate.model'),FILES/(name+'.model'))
            shutil.copy2(source/(key+'.vectors.csv'),FILES/(name+'.csv'))
            calls.append(f'   Check("{name}","{key}");')
    code=r'''#property strict
#include "NasStrategyMLCore.mqh"
int failed=0,models=0,vectors=0;double worst=0;
void Check(string name,string config)
{
   int h=FileOpen("NasPredictionProbe\\"+name+".model",FILE_READ|FILE_BIN);
   if(h==INVALID_HANDLE){failed++;return;}
   uchar bytes[];FileReadArray(h,bytes);FileClose(h);
   string text=CharArrayToString(bytes,0,ArraySize(bytes),CP_UTF8),reason;
   NasMlNetwork model;
   if(!NasMlParseModel(text,config,model,reason)){failed++;return;}
   models++;
   h=FileOpen("NasPredictionProbe\\"+name+".csv",FILE_READ|FILE_CSV|FILE_ANSI,',',CP_UTF8);
   if(h==INVALID_HANDLE){failed++;return;}
   for(int k=0;k<41;k++)FileReadString(h);
   while(!FileIsEnding(h))
   {
      double x[];ArrayResize(x,40);
      for(int k=0;k<40;k++)x[k]=FileReadNumber(h);
      double expected=FileReadNumber(h),actual=0;
      if(!NasMlPredict(model,x,actual)){failed++;break;}
      double error=MathAbs(expected-actual);worst=MathMax(worst,error);
      if(error>1e-10)failed++;vectors++;
   }
   FileClose(h);
   if(NasMlParseModel(text,"wrong-strategy",model,reason))failed++;
}
void OnStart()
{
   if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
__CALLS__
   int h=FileOpen("NasPredictionProbe\\result.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   string result="{\"failed\":"+(string)failed+",\"models\":"+(string)models+",\"vectors\":"+(string)vectors+",\"max_error\":"+DoubleToString(worst,16)+"}";
   if(h!=INVALID_HANDLE){FileWriteString(h,result);FileClose(h);}Print(result);
}
'''.replace('__CALLS__','\n'.join(calls))
    (STAGE/'NasPredictionProbe.mq5').write_text(code,encoding='ascii')
    (REPORT/'prediction.ini').write_text('[Experts]\nEnabled=0\nAllowDllImport=0\n[StartUp]\nScript=NasPredictionProbe\\NasPredictionProbe\nSymbol=BTCUSDm\nPeriod=M5\nShutdownTerminal=1\n',encoding='ascii')
    print('Prediction fixtures:',len(calls))

if __name__=='__main__':main()
