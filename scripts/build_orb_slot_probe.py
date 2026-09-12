"""Generate isolated, no-order MQL tests for the actual slot parser/dispatch."""
from pathlib import Path
import json
import shutil
import random
import math
import orb_model_slot as s

ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT/'logs/OrbModelSlots_20260912'
WORKER = ROOT/'.tmp/orb_jp225_full_worker'
DEST = WORKER/'MQL5/Scripts/OrbSlotProbe'
FILES = WORKER/'MQL5/Files/OrbSlotProbe'


def build():
    DEST.mkdir(parents=True, exist_ok=True); FILES.mkdir(parents=True, exist_ok=True)
    for name in ('OrbStrategyMLCore.mqh','OrbStrategyR7Core.mqh','OrbStrategyModelSlot.mqh'):
        shutil.copyfile(ROOT/'IndicatorCodeExamples'/name, DEST/name)
    s.migrate(ROOT/'logs/OrbR7Runtime_20260912', REPORT/'Slots')
    ids = []
    for p in sorted((REPORT/'Slots').glob('*/active.slot')):
        m = s.parse(p.read_bytes(), p.parent.name); ids.append(m['id'])
        shutil.copyfile(p, FILES/(m['id']+'.slot'))
        shutil.copyfile(REPORT/'Slots/Artifacts'/(m['artifact']+'.model'), FILES/(m['id']+'.model'))
    shutil.copyfile(ROOT/'logs/OrbR7Runtime_20260912/probe_vectors.txt', FILES/'vectors.txt')
    # Independent MLP arithmetic with nonzero input, hidden and output weights.
    m = s.parse((FILES/(ids[0]+'.slot')).read_bytes(), ids[0])
    m.update(id='probe_mlp',revision='mlp-test',provider='ORB_MLP1',valid_from=200000,valid_until=300000,
             evaluation='NONE',metric_from=0,metric_until=0,n=0,wr=0,net_r=0,dd=0)
    rng = random.Random(1984)
    means=[rng.uniform(-1,1) for _ in range(40)]; scales=[rng.uniform(.5,2) for _ in range(40)]
    weights=[rng.uniform(-.2,.2) for _ in range(640)]
    bias=[rng.uniform(-.2,.2) for _ in range(16)]; out=[rng.uniform(-.2,.2) for _ in range(16)]
    values=['ORB_MLP1',s.SCHEMA,m['config'],s.feature_hash(),m['dataset'],'100000','0.55','40,16']
    for i in range(40): values += [format(means[i],'.17g'),format(scales[i],'.17g')]
    values += [format(v,'.17g') for v in weights+bias+out+[.1]]
    payload=('\n'.join(values)+'\n').encode(); data=payload+s.sha(payload).encode()+b'\n'
    m['artifact']=s.sha(data); s.validate_artifact(m,data)
    (FILES/'probe_mlp.slot').write_bytes(s.encode(m)); (FILES/'probe_mlp.model').write_bytes(data)
    vectors=[]
    for j in range(32):
        x=[rng.uniform(-3,3) for _ in range(40)]; z=.1
        for h in range(16):
            value=bias[h]
            for i in range(40): value+=(x[i]-means[i])/scales[i]*weights[i*16+h]
            z+=max(0,value)*out[h]
        prob=1/(1+math.exp(-z)) if z>=0 else math.exp(z)/(1+math.exp(z))
        vectors.append(';'.join(['probe_mlp','220000',format(prob,'.17g')]+[format(t,'.17g') for t in x]))
    with (FILES/'vectors.txt').open('ab') as f: f.write(('\n'.join(vectors)+'\n').encode())
    # Canonically checksummed malformed manifests, not merely corrupted bytes.
    bad=[]
    original=s.encode(m).decode().splitlines()[:-1]
    for index,value in [(1,'wrong_schema'),(2,'f'*64),(12,'ORB_UNKNOWN'),(13,'../evil'),(14,'../../evil'),
                        (16,'100'),(20,'NaN'),(23,'OOS'),(11,'0'),(19,'2'),(4,'bad_hash'),(3,'other_strategy')]:
        v=original.copy();v[index]=value
        payload=('\n'.join(v)+'\n').encode(); raw=payload+s.sha(payload).encode()+b'\n'
        name='bad_'+str(len(bad))+'.slot';(FILES/name).write_bytes(raw);bad.append(name)
    (FILES/'bad.txt').write_text('\n'.join(bad)+'\n')
    (DEST/'OrbSlotProbe.mq5').write_text(SOURCE,encoding='utf8')
    (REPORT/'probe.ini').write_text('[Experts]\nEnabled=0\nAllowDllImport=0\n[StartUp]\nScript=OrbSlotProbe\\OrbSlotProbe\nSymbol=JP225m\nPeriod=M5\nShutdownTerminal=1\n')
    print('No-order slot probe prepared: 52 logistic archives + MLP, 4143 vectors, 12 malformed contracts.')


SOURCE = r'''#property strict
#include "OrbStrategyModelSlot.mqh"
string Read(string name)
{
 int h=FileOpen("OrbSlotProbe\\"+name,FILE_READ|FILE_BIN);if(h==INVALID_HANDLE)return "";
 int n=(int)FileSize(h);uchar b[];ArrayResize(b,n);FileReadArray(h,b);FileClose(h);return CharArrayToString(b,0,n,CP_UTF8);
}
void OnStart()
{
 if(StringFind(TerminalInfoString(TERMINAL_DATA_PATH),"orb_jp225_full_worker")<0)return;
 string rows[];StringSplit(Read("vectors.txt"),'\n',rows);
 int tested=0,failed=0,packs=0,negative=0;double error=0;string current="",reason="";
 OrbSlotModel model;ZeroMemory(model);OrbSlotManifest manifest;ZeroMemory(manifest);
 for(int row=0;row<ArraySize(rows);row++)
 {
  if(rows[row]=="")continue;string a[];if(StringSplit(rows[row],';',a)!=43){failed++;continue;}
  if(current!=a[0])
  {
   current=a[0];packs++;
   string text=Read(current+".slot"),artifact=Read(current+".model");
   if(!OrbSlotParse(text,current,manifest,reason)||!OrbSlotModelParse(manifest,artifact,model,reason)){failed++;Print(current," ",reason);continue;}
   OrbSlotManifest bad;ZeroMemory(bad);OrbSlotModel badModel;ZeroMemory(badModel);
   negative++;if(OrbSlotParse(text,current+"wrong",bad,reason))failed++;
   negative++;if(OrbSlotParse(text+"corrupt",current,bad,reason))failed++;
   negative++;if(OrbSlotModelParse(manifest,artifact+"corrupt",badModel,reason))failed++;
   double x[];ArrayResize(x,40);ArrayInitialize(x,0);double score=0;
   negative++;if(OrbSlotScore(model,x,manifest.fromTime-1,score,reason))failed++;
   negative++;if(OrbSlotScore(model,x,manifest.untilTime,score,reason))failed++;
  }
  double x[];ArrayResize(x,40);for(int i=0;i<40;i++)x[i]=StringToDouble(a[i+3]);
  double actual=0,expected=StringToDouble(a[2]);
  if(!OrbSlotScore(model,x,(datetime)StringToInteger(a[1]),actual,reason)){failed++;continue;}
  double delta=MathAbs(actual-expected);error=MathMax(error,delta);
  double threshold=manifest.provider=="ORB_MLP1"?model.mlp.threshold:0;
  if(delta>1e-10||(actual>=threshold)!=(expected>=threshold))failed++;
  if((reason=="ALLOW")!=(expected>=threshold))failed++;
  tested++;
 }
 string bads[];StringSplit(Read("bad.txt"),'\n',bads);
 for(int i=0;i<ArraySize(bads);i++)if(bads[i]!="")
 {negative++;if(OrbSlotParse(Read(bads[i]),"probe_mlp",manifest,reason))failed++;}
 string result=StringFormat("{\"packs\":%d,\"vectors\":%d,\"negative\":%d,\"failed\":%d,\"max_error\":%.17g}",packs,tested,negative,failed,error);
 int o=FileOpen("OrbSlotProbe\\result.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
 if(o!=INVALID_HANDLE){FileWriteString(o,result);FileClose(o);}Print("SLOT_PROBE ",result);
}
'''

if __name__ == '__main__':
    build()
