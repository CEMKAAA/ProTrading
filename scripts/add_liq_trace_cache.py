"""Extend Advanced's existing closed-result cache with its complete draw trace."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def main():
    for name in ('LiqNarrativeSol_Advanced.mq5','LiqNarrativeSol_Advanced_Channel.mq5'):
        path=ROOT/'IndicatorCodeExamples'/name;raw=path.read_bytes();text=raw.decode('utf-8-sig')
        nl='\r\n' if '\r\n' in text else '\n';text=text.replace('\r\n','\n')
        if 'int      traceDir;' in text:continue
        a=text.index('struct SimCacheEntry');b=text.index('\n};',a)
        text=text[:b]+'''
   int      traceDir;
   double   traceEntry,traceSl,traceTp,traceHalf;
   datetime traceExitTime;
   string   traceExitReason;
'''.rstrip()+text[b:]
        old='''         valid = g_simCache[i].valid;
         return true;'''
        new='''         valid = g_simCache[i].valid;
         g_lastSimInvalidReason = "";
         g_lastSimExecDir = g_simCache[i].traceDir;
         g_lastSimExecEntry = g_simCache[i].traceEntry;
         g_lastSimExecSl = g_simCache[i].traceSl;
         g_lastSimExecTp = g_simCache[i].traceTp;
         g_lastSimExecHalf = g_simCache[i].traceHalf;
         g_lastSimExitTime = g_simCache[i].traceExitTime;
         g_lastSimExitReason = g_simCache[i].traceExitReason;
         return true;'''
        if text.count(old)!=1:raise ValueError('Cache get drift: '+name)
        text=text.replace(old,new)
        old='   g_simCache[n].valid = valid;'
        new=old+'''
   g_simCache[n].traceDir = g_lastSimExecDir;
   g_simCache[n].traceEntry = g_lastSimExecEntry;
   g_simCache[n].traceSl = g_lastSimExecSl;
   g_simCache[n].traceTp = g_lastSimExecTp;
   g_simCache[n].traceHalf = g_lastSimExecHalf;
   g_simCache[n].traceExitTime = g_lastSimExitTime;
   g_simCache[n].traceExitReason = g_lastSimExitReason;'''
        if text.count(old)!=1:raise ValueError('Cache put drift: '+name)
        text=text.replace(old,new)
        old='''      // Always run the visible audit row so its effective execution geometry
      // and exit reason match the lines drawn on chart. Aggregate RF scans may
      // still use the compact result cache.
      double r = SimulateSignal(g_histSignals[i], g_target, g_hc, g_targetModel, g_entryTf, nextSignalTime, closed, won, valid);'''
        new='''      // Restore the full trace with terminal outcomes; never freeze DATA/OPEN.
      string simKey = SimCacheKey(g_histSignals[i], g_target, g_hc, g_targetModel, g_entryTf, nextSignalTime);
      double r = 0.0;
      if(!SimCacheGet(simKey, r, closed, won, valid))
      {
         r = SimulateSignal(g_histSignals[i], g_target, g_hc, g_targetModel, g_entryTf, nextSignalTime, closed, won, valid);
         if(valid && closed) SimCachePut(simKey, r, closed, won, valid);
      }'''
        if text.count(old)!=1:raise ValueError('Visible replay drift: '+name)
        text=text.replace(old,new)
        data=text.replace('\n',nl).encode('utf-8')
        if raw.startswith(b'\xef\xbb\xbf'):data=b'\xef\xbb\xbf'+data
        path.write_bytes(data);print(name)

if __name__=='__main__':main()
