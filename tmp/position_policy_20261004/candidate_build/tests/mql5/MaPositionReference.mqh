struct PolicyMaEvent {datetime signalTime;int direction;};
datetime ReferenceMaKernelExitAt(const PolicyMaEvent &events[],datetime opened,int direction,
                       datetime until,int waitMinutes,int seconds,bool invert)
{
   datetime eligible=opened+(datetime)(MathMax(0,waitMinutes)*60);
   int lo=0,hi=ArraySize(events);
   while(lo<hi){int mid=(lo+hi)/2;if(events[mid].signalTime+seconds<=opened)lo=mid+1;else hi=mid;}
   int state=0;
   for(int i=lo;i<ArraySize(events);i++)
   {
      datetime at=events[i].signalTime+seconds;
      if(at>until)break;
      int dir=events[i].direction*(invert?-1:1);
      if(at<=eligible){state=dir;continue;}
      if(state==-direction&&eligible<=until)return eligible;
      if(dir==-direction)return at;
      state=dir;
   }
   return state==-direction&&eligible<=until?eligible:0;
}
bool ReferenceMaOpenCapacityAllows(int opened,int maximum){return maximum>=1&&maximum<=1000&&opened>=0&&opened<maximum;}
