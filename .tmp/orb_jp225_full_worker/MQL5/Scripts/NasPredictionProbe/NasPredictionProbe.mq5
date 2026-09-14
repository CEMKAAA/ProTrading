#property strict
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
   Check("m0","0272ae0e8437ecdb4a41c1fd531ec7a353260dc0e9f6da5d1e3bc91aef203fa4");
   Check("m1","0272ae0e8437ecdb4a41c1fd531ec7a353260dc0e9f6da5d1e3bc91aef203fa4");
   Check("m2","030d8d172b47ccfa0dda0bc5157134e050a2d4f893d734635098b7fb21412ce9");
   Check("m3","030d8d172b47ccfa0dda0bc5157134e050a2d4f893d734635098b7fb21412ce9");
   Check("m4","26bbc78570aa51bb11c79a236bc101241d43e5213d47bfc98ab297686bab92ba");
   Check("m5","26bbc78570aa51bb11c79a236bc101241d43e5213d47bfc98ab297686bab92ba");
   Check("m6","27992e2e9efc6e2059cfde8fa35b64d13079367c7f10636facd76f4479836885");
   Check("m7","27992e2e9efc6e2059cfde8fa35b64d13079367c7f10636facd76f4479836885");
   Check("m8","2adc3e9d22823b2088d6163d9e60bda50d57e6ef88474c5317a901fece046908");
   Check("m9","2adc3e9d22823b2088d6163d9e60bda50d57e6ef88474c5317a901fece046908");
   Check("m10","652bc95f8388dbdfbbd3cff933dfab24b29e9989cf6f831318c5aef49f752a7f");
   Check("m11","652bc95f8388dbdfbbd3cff933dfab24b29e9989cf6f831318c5aef49f752a7f");
   Check("m12","6623e262ae143b91d04651dea69078ce02679ba440185c4bca8ee0f4d76d6755");
   Check("m13","6623e262ae143b91d04651dea69078ce02679ba440185c4bca8ee0f4d76d6755");
   Check("m14","693e992309bbbb83d85bd6ad3686be1f0408ec80822236743dad6d4ffd3c7127");
   Check("m15","693e992309bbbb83d85bd6ad3686be1f0408ec80822236743dad6d4ffd3c7127");
   Check("m16","79358ffcddb456ac963b90e368969c90208602354e42a7391bcb20a1c7315690");
   Check("m17","79358ffcddb456ac963b90e368969c90208602354e42a7391bcb20a1c7315690");
   Check("m18","7e2957e2a4071a6d00e807cc508fe0c1931a94642c0cf0300f5c8515d1621370");
   Check("m19","7e2957e2a4071a6d00e807cc508fe0c1931a94642c0cf0300f5c8515d1621370");
   Check("m20","86dff2f5b281193f4a8c58a5b35f780ce20cdfb7b1f18decd9029477ab278bdb");
   Check("m21","86dff2f5b281193f4a8c58a5b35f780ce20cdfb7b1f18decd9029477ab278bdb");
   Check("m22","95c88332401a7df5fefbe4eb9cace3efe79cdfb8c8e5d00764edeb196e82b783");
   Check("m23","95c88332401a7df5fefbe4eb9cace3efe79cdfb8c8e5d00764edeb196e82b783");
   Check("m24","989073463d561dea2b46ce52013c89da916454303dc43ba73cdf68f346c86932");
   Check("m25","989073463d561dea2b46ce52013c89da916454303dc43ba73cdf68f346c86932");
   Check("m26","9a29ba934e1e2fc5d9a432793db91ce1cf30c8790b773ba3efd840f08833a463");
   Check("m27","9a29ba934e1e2fc5d9a432793db91ce1cf30c8790b773ba3efd840f08833a463");
   Check("m28","a04328c5f2a5937b29e8ce50e9c30970fa18d7f48e8b53fd357bd578484d9775");
   Check("m29","a04328c5f2a5937b29e8ce50e9c30970fa18d7f48e8b53fd357bd578484d9775");
   Check("m30","cc5ea5f628e6a1a4d8ac331dd808fe2326b8da1bce20131120e81aabb0f245ee");
   Check("m31","cc5ea5f628e6a1a4d8ac331dd808fe2326b8da1bce20131120e81aabb0f245ee");
   Check("m32","d4dfa61f4ef3ef144dc839470c0e5d9b0a021205a292f807328f0e7720757f33");
   Check("m33","d4dfa61f4ef3ef144dc839470c0e5d9b0a021205a292f807328f0e7720757f33");
   Check("m34","e6449dff92d83a837c8fb9394d296a96c4997325d31eb3388159f494a9f577e9");
   Check("m35","e6449dff92d83a837c8fb9394d296a96c4997325d31eb3388159f494a9f577e9");
   Check("m36","f813db757278244e4ae05a183bf0380b36f360ee8486f3213c185996c92c5171");
   Check("m37","f813db757278244e4ae05a183bf0380b36f360ee8486f3213c185996c92c5171");
   int h=FileOpen("NasPredictionProbe\\result.json",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   string result="{\"failed\":"+(string)failed+",\"models\":"+(string)models+",\"vectors\":"+(string)vectors+",\"max_error\":"+DoubleToString(worst,16)+"}";
   if(h!=INVALID_HANDLE){FileWriteString(h,result);FileClose(h);}Print(result);
}
