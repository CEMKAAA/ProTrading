#ifndef AUDIT_MEMO_INDEX_MQH
#define AUDIT_MEMO_INDEX_MQH

// Instance-local, bounded index. Hash collisions always compare the full key.
// Callers may store only completed, valid replays; never OPEN/DATA/pending work.
class AuditMemoIndex
{
private:
   string m_keys[];
   int m_values[];
   int m_count;
   string m_epoch;
   uint Hash(const string key)
   {
      uint h=2166136261;
      for(int i=0;i<StringLen(key);i++){h^=(uint)StringGetCharacter(key,i);h*=16777619;}
      return h;
   }
   void Grow(const int capacity)
   {
      string oldKeys[];int oldValues[];
      ArrayCopy(oldKeys,m_keys);ArrayCopy(oldValues,m_values);
      ArrayResize(m_keys,capacity);ArrayResize(m_values,capacity);
      for(int i=0;i<capacity;i++){m_keys[i]="";m_values[i]=-1;}
      for(int i=0;i<ArraySize(oldValues);i++)
      {
         if(oldValues[i]<0)continue;
         int slot=(int)(Hash(oldKeys[i])%(uint)capacity);
         while(m_values[slot]>=0)slot=(slot+1)%capacity;
         m_keys[slot]=oldKeys[i];m_values[slot]=oldValues[i];
      }
   }
public:
   AuditMemoIndex(){m_count=0;m_epoch="";}
   void Reset(const string epoch)
   {
      if(m_epoch==epoch)return;
      m_epoch=epoch;m_count=0;
      for(int i=0;i<ArraySize(m_values);i++){m_values[i]=-1;m_keys[i]="";}
   }
   int Find(const string key)
   {
      int capacity=ArraySize(m_values);if(capacity==0)return -1;
      int slot=(int)(Hash(key)%(uint)capacity);
      for(int n=0;n<capacity;n++,slot=(slot+1)%capacity)
      {
         if(m_values[slot]<0)return -1;
         if(m_keys[slot]==key)return m_values[slot];
      }
      return -1;
   }
   int Add(const string key)
   {
      int existing=Find(key);if(existing>=0)return existing;
      if(m_count>=65536)return -1;
      int capacity=ArraySize(m_values);
      if(capacity==0){Grow(4096);capacity=4096;}
      else if((m_count+1)*2>capacity){Grow(capacity*2);capacity*=2;}
      int slot=(int)(Hash(key)%(uint)capacity);
      while(m_values[slot]>=0)slot=(slot+1)%capacity;
      m_keys[slot]=key;m_values[slot]=m_count++;
      return m_values[slot];
   }
};

string AuditMemoPrice(const double value){return StringFormat("%.17g",value);}

// Conservative market-data epoch: refresh after a new closed M1 bar or history
// extension. No disk cache survives a restart, broker change or source reload.
string AuditMemoDataEpoch(const string symbol)
{
   return AccountInfoString(ACCOUNT_SERVER)+"|"+symbol+"|"
      +(string)SeriesInfoInteger(symbol,PERIOD_M1,SERIES_BARS_COUNT)+"|"
      +(string)SeriesInfoInteger(symbol,PERIOD_M1,SERIES_FIRSTDATE)+"|"
      +(string)SeriesInfoInteger(symbol,PERIOD_M1,SERIES_LASTBAR_DATE)+"|"
      +(string)SeriesInfoInteger(symbol,PERIOD_M1,SERIES_SYNCHRONIZED);
}
#endif
