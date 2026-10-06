#ifndef UNIVERSAL_AUTHORITY_MQH
#define UNIVERSAL_AUTHORITY_MQH
// Verification-only RSA-2048 / e=65537, strict RFC 8017 EMSA-PKCS1-v1_5 SHA256.
// No private key, signing, encryption or secret arithmetic lives in the EA.
struct UcRsaNumber { uint word[64]; };
int UcRsaCompare(const UcRsaNumber &a,const UcRsaNumber &b)
{
   for(int i=63;i>=0;i--){if(a.word[i]>b.word[i])return 1;if(a.word[i]<b.word[i])return -1;}
   return 0;
}
int UcHexNibble(ushort c){if(c>='0'&&c<='9')return (int)(c-'0');if(c>='a'&&c<='f')return (int)(c-'a'+10);return -1;}
bool UcRsaParse(string hex,UcRsaNumber &a)
{
   if(StringLen(hex)!=512)return false;ArrayInitialize(a.word,0);
   for(int i=0;i<512;i++){int v=UcHexNibble(StringGetCharacter(hex,i));if(v<0)return false;int w=(511-i)/8;a.word[w]=(a.word[w]<<4)|(uint)v;}
   return true;
}
void UcRsaAdd(const UcRsaNumber &a,const UcRsaNumber &b,const UcRsaNumber &n,UcRsaNumber &out)
{
   ulong carry=0;
   for(int i=0;i<64;i++){ulong sum=(ulong)a.word[i]+(ulong)b.word[i]+carry;out.word[i]=(uint)sum;carry=sum>>32;}
   if(carry!=0||UcRsaCompare(out,n)>=0){ulong borrow=0;
      for(int i=0;i<64;i++){ulong x=out.word[i],y=(ulong)n.word[i]+borrow;out.word[i]=(uint)(x-y);borrow=x<y?1:0;}}
}
void UcRsaMultiply(const UcRsaNumber &a,const UcRsaNumber &b,const UcRsaNumber &n,UcRsaNumber &out)
{
   UcRsaNumber value;ArrayInitialize(value.word,0);
   for(int i=63;i>=0;i--)for(int bit=31;bit>=0;bit--){
      UcRsaAdd(value,value,n,value);if(((a.word[i]>>bit)&1)!=0)UcRsaAdd(value,b,n,value);}
   out=value;
}
bool UcRsaVerify(string body,string signature,string modulus)
{
   UcRsaNumber s,n,value,next;
   if(!UcRsaParse(signature,s)||!UcRsaParse(modulus,n)||n.word[63]<0x80000000||(n.word[0]&1)==0||UcRsaCompare(s,n)>=0)return false;
   value=s;for(int i=0;i<16;i++){UcRsaMultiply(value,value,n,next);value=next;}UcRsaMultiply(value,s,n,next);
   uchar bytes[],digest[],empty[];int size=StringToCharArray(body,bytes,0,WHOLE_ARRAY,CP_UTF8)-1;ArrayResize(bytes,size);
   if(CryptEncode(CRYPT_HASH_SHA256,bytes,empty,digest)!=32)return false;
   string expected="0001";for(int i=0;i<202;i++)expected+="ff";expected+="003031300d060960864801650304020105000420";
   for(int i=0;i<32;i++)expected+=StringFormat("%02x",digest[i]);
   UcRsaNumber encoded;return UcRsaParse(expected,encoded)&&UcRsaCompare(next,encoded)==0;
}
string UcField(string body,string key)
{
   string lines[];int n=StringSplit(body,'\n',lines),size=StringLen(key);
   for(int i=0;i<n;i++)if(StringSubstr(lines[i],0,size+1)==key+"=")return StringSubstr(lines[i],size+1);
   return "";
}
bool UcAuthorityScope(string body,string installation,string login,string symbol,string broker,datetime now,long floorSequence)
{
   datetime issued=(datetime)StringToInteger(UcField(body,"issued")),expires=(datetime)StringToInteger(UcField(body,"expires"));
   string mode=UcField(body,"command");long sequence=StringToInteger(UcField(body,"sequence"));
   return (mode=="audit"||mode=="live")&&UcField(body,"installationId")==installation&&UcField(body,"accountLogin")==login
      &&UcField(body,"symbol")==symbol&&UcField(body,"brokerServer")==broker&&sequence>floorSequence
      &&issued<=now+5&&issued>=now-20&&expires>now&&expires>issued&&expires-issued<=15
      &&StringLen(UcField(body,"accountId"))==36&&StringLen(UcField(body,"generation"))==36;
}
bool UcIdentityScope(string body,string installation,string login,string symbol,string broker,datetime now,long floorSequence)
{
   datetime issued=(datetime)StringToInteger(UcField(body,"issued")),expires=(datetime)StringToInteger(UcField(body,"expires"));
   string name=UcField(body,"subscriberName"),active=UcField(body,"subscriptionActive"),controller=UcField(body,"controllerActive");
   string access=UcField(body,"accessMode");
   bool demo=access=="demo"&&active=="true"&&StringToInteger(UcField(body,"trialUntil"))>(long)now;
   return UcField(body,"command")=="identity"&&UcField(body,"installationId")==installation
      &&UcField(body,"accountLogin")==login&&UcField(body,"symbol")==symbol&&UcField(body,"brokerServer")==broker
      &&StringToInteger(UcField(body,"sequence"))>floorSequence&&issued<=now+5&&issued>=now-20
      &&expires>now&&expires>issued&&expires-issued<=15&&StringLen(UcField(body,"accountId"))==36
      &&StringLen(name)>0&&StringLen(name)<=60&&(active=="true"||active=="false")&&(controller=="true"||controller=="false")
      &&(demo||(access=="paid"&&active=="true")||(access=="inactive"&&active=="false"));
}
#endif
