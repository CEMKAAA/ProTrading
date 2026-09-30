#ifndef LIQ_IMAGE_PRESETS_MQH
#define LIQ_IMAGE_PRESETS_MQH
// Manually transcribed screenshot dashboard settings. See LIQ_IMAGE_PRESETS.md.
// Hidden Inputs, execution switches, risk and channel ownership are NOT imported.
struct LiqImagePreset
{
   string name,family,symbol;
   int htf,entry,target,duplicate,invert,pips,weeks;
   int regimeFilter,macroBlockedMask,rfAllowedMask;
};
LiqImagePreset g_liqImagePresets[]={
 {"LiqNarrative1.5RUstec","LiquidityNarrative_MT5_EA","USTECm",16386,15,2,1,0,20000,2},
 {"ustec1RLiqSetup","LiquidityNarrative_MT5_EA","USTECm",16386,15,1,1,0,30000,2},
 {"US500LIQNarrative","LiquidityNarrative_MT5_EA","US500m",16386,15,1,1,0,3000,20},
 {"US30ReverseWorthTrying","LiquidityNarrative_MT5_EA","US30m",16386,15,3,1,1,600,2},
 {"SPX5001.5R","LiqNarrativeSol_Advanced","US500m",16385,16385,2,0,0,2000,10},
 {"spx500AdvancedModelLiquidity","LiqNarrativeSol_Advanced","US500m",16385,16385,2,0,0,3000,2},
 {"btcgoon","LiqNarrativeSol_Advanced","BTCUSDm",16388,16385,1,1,0,30000,2},
 {"BTCUSDLiqNarrative","LiqNarrativeSol_Advanced","BTCUSDm",16386,16385,2,1,0,20000,2},
 {"MightBeNewEdge","LiqNarrativeSol_Advanced","JP225m",90,15,3,1,0,4000,10},
 // These are visible dashboard settings from the screenshot archive. Legacy_
 // records are migrations, not claims that Advanced reproduces old EA results.
 {"SolAdvanced_JP225_H2H1_2R","LiqNarrativeSol_Advanced","JP225m",16386,16385,3,1,0,4000,2,1,16,512},
 {"SolVersion_JP225_H2H1_2R","LiqNarrativeSol_Advanced","JP225m",16386,16385,3,1,0,4000,2,0,48,0},
 {"Legacy_JP225_H2M30_2R","LiqNarrativeSol_Advanced","JP225s",16386,30,3,0,0,7000,10},
 {"Legacy_JP225_H2H1_2R","LiqNarrativeSol_Advanced","JP225s",16386,16385,3,1,0,4000,2},
 {"Legacy_US500_H2M15_1R","LiqNarrativeSol_Advanced","US500m",16386,15,2,0,0,3000,2},
 {"Legacy_US500_H2M15_2R","LiqNarrativeSol_Advanced","US500m",16386,15,3,0,0,3000,2},
 {"Legacy_US500_H2M15_05R_DUP","LiqNarrativeSol_Advanced","US500m",16386,15,1,1,0,3000,20},
 {"Legacy_US500_H2M15_2R_DUP_2500","LiqNarrativeSol_Advanced","US500m",16386,15,3,1,0,2500,52},
 {"Legacy_US500_H2M15_1R_DUP","LiqNarrativeSol_Advanced","US500m",16386,15,2,1,0,3000,2},
 {"Legacy_USTEC_H2M15_1R_15000","LiqNarrativeSol_Advanced","USTECm",16386,15,2,0,0,15000,5},
 {"Legacy_USTEC_H2M15_1R_30000","LiqNarrativeSol_Advanced","USTECm",16386,15,2,0,0,30000,2},
 {"Legacy_USTEC_H2M15_1R_DUP","LiqNarrativeSol_Advanced","USTECm",16386,15,2,1,0,30000,5},
 {"Legacy_USTEC_H2M15_2R_DUP","LiqNarrativeSol_Advanced","USTECm",16386,15,3,1,0,30000,2},
 {"Legacy_USTEC_H2M30_2R","LiqNarrativeSol_Advanced","USTECm",16386,30,3,0,0,30000,2},
 {"Legacy_US30_H2M15_1R_DUP","LiqNarrativeSol_Advanced","US30m",16386,15,2,1,0,600,2},
 {"Legacy_EURUSD_H2M30_05R","LiqNarrativeSol_Advanced","EURUSDm",16386,30,1,0,0,10,5},
 {"Legacy_UKOIL_H2H1_1R","LiqNarrativeSol_Advanced","UKOILm",16386,16385,2,0,0,150,2}
};
bool LiqImageCompatible(int i)
{
   string family=LiqLibraryFamily();StringReplace(family,"_Channel","");
   return i>=0&&i<ArraySize(g_liqImagePresets)&&family==g_liqImagePresets[i].family&&_Symbol==g_liqImagePresets[i].symbol;
}
string LiqImagePath(int i){return LiqLibraryFolder()+"\\image_"+LiqLibraryHash(g_liqImagePresets[i].name)+".lns";}
bool LiqImageRead(string path,string &name,double &v[])
{
   for(int i=0;i<ArraySize(g_liqImagePresets);i++)
   {
      if(!LiqImageCompatible(i)||path!=LiqImagePath(i))continue;
      int count=LiqLibraryCapture(v);if(count!=22&&count!=41&&count!=42)return false;
      ArrayInitialize(v,0);LiqImagePreset p=g_liqImagePresets[i];
      name=p.name;v[0]=p.htf;v[1]=p.entry;v[2]=5;v[3]=p.target;
      v[7]=1;v[13]=1;v[15]=p.duplicate;v[16]=p.invert;
      v[17]=100;v[18]=10;v[19]=1;v[20]=p.pips;v[21]=p.weeks;
      // All photographed Advanced presets: RF master OFF, macro ALLOW, RF rules BLOCK.
      if(count>=41)
      {
         for(int j=23;j<41;j++)v[j]=1;
         v[22]=p.regimeFilter;
         for(int j=0;j<6;j++)if((p.macroBlockedMask&(1<<j))!=0)v[23+j]=0;
         for(int j=0;j<12;j++)if((p.rfAllowedMask&(1<<j))!=0)v[29+j]=0;
      }
      if(count>=42)v[41]=100.0;
      return true;
   }
   return false;
}
#endif
