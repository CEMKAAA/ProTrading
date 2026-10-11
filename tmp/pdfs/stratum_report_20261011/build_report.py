from pathlib import Path
from templates import write_templates
import json, math, hashlib, shutil, textwrap, html
from xml.sax.saxutils import escape
from reportlab.pdfgen import canvas
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer,
    PageBreak, Table, TableStyle, Image, KeepTogether, Flowable)
from reportlab.platypus.tableofcontents import TableOfContents
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.colors import HexColor, Color, white
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

ROOT=Path(__file__).resolve().parents[3]
WORK=Path(__file__).resolve().parent
OUT=ROOT/'output/pdf/STRATUM_Referans_Paketi_20261011'
ASSETS=OUT/'assets';ASSETS.mkdir(parents=True,exist_ok=True)
PDF=ROOT/'output/pdf/STRATUM_Teknik_Referans_20261011.pdf'
FACTS=json.loads((OUT/'evidence_summary.json').read_text(encoding='utf-8'))
DATA=json.loads((WORK/'content.json').read_text(encoding='utf-8'))
for file in ['content2.json','content3.json']:
    DATA['sections']+=json.loads((WORK/file).read_text(encoding='utf-8'))['sections']

COLORS={'ink':'#17313F','gold':'#E4AD31','ice':'#EAF3F6','mint':'#2C8F7D',
        'red':'#B74C43','muted':'#536C77','line':'#CFDCE2','paper':'#FAFBFA','ivory':'#F8F2E4'}
INK=HexColor(COLORS['ink']);GOLD=HexColor(COLORS['gold']);MUTED=HexColor(COLORS['muted'])
for name,file in [('Body','Candara.ttf'),('BodyBold','Candarab.ttf'),('BodyItalic','Candarai.ttf'),
                  ('Display','GeorgiaPro-SemiBold.ttf'),('Mono','consola.ttf')]:
    pdfmetrics.registerFont(TTFont(name,str(Path('C:/Windows/Fonts')/file)))
pdfmetrics.registerFontFamily('Body',normal='Body',bold='BodyBold',italic='BodyItalic',boldItalic='BodyBold')
W,H=A4;M=43;CW=W-2*M
S={
 'body':ParagraphStyle('body',fontName='Body',fontSize=10.5,leading=14.3,textColor=INK,spaceAfter=8),
 'lead':ParagraphStyle('lead',fontName='Body',fontSize=12.2,leading=16.5,textColor=MUTED,spaceAfter=14),
 'title':ParagraphStyle('title',fontName='Display',fontSize=23,leading=28,textColor=INK,spaceAfter=11),
 'kicker':ParagraphStyle('kicker',fontName='Mono',fontSize=8.8,leading=12,textColor=MUTED,spaceAfter=9),
 'small':ParagraphStyle('small',fontName='Body',fontSize=8.6,leading=11.5,textColor=MUTED,spaceAfter=6),
 'table':ParagraphStyle('table',fontName='Body',fontSize=9.1,leading=12,textColor=INK),
 'thead':ParagraphStyle('thead',fontName='BodyBold',fontSize=9.2,leading=12,textColor=INK),
 'calltitle':ParagraphStyle('calltitle',fontName='BodyBold',fontSize=10.2,leading=13.5,textColor=INK,spaceAfter=4),
 'call':ParagraphStyle('call',fontName='Body',fontSize=9.8,leading=13.2,textColor=INK),
 'ref':ParagraphStyle('ref',fontName='Body',fontSize=8.6,leading=11.7,textColor=INK,spaceAfter=10),
 'source':ParagraphStyle('source',fontName='Mono',fontSize=7.7,leading=10.2,textColor=MUTED,spaceBefore=10),
 'bullet':ParagraphStyle('bullet',fontName='Body',fontSize=10.3,leading=14,textColor=INK,leftIndent=12,firstLineIndent=-12,spaceAfter=7),
}
def p(text,kind='body'):
    return Paragraph(html.escape(str(text)).replace('\n','<br/>'),S[kind])
def callout(title,text):
    t=Table([[p(title,'calltitle')],[p(text,'call')]],colWidths=[CW-24])
    t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,-1),HexColor(COLORS['ivory'])),
        ('BOX',(0,0),(-1,-1),0.4,HexColor('#E8D8AB')),('LINEBEFORE',(0,0),(0,-1),3,GOLD),
        ('LEFTPADDING',(0,0),(-1,-1),12),('RIGHTPADDING',(0,0),(-1,-1),12),
        ('TOPPADDING',(0,0),(-1,0),10),('BOTTOMPADDING',(0,-1),(-1,-1),10)]))
    return [t,Spacer(1,11)]
def table(headers,rows,widths=None):
    n=len(headers)
    if widths is None:
        ratios=([0.29,0.33,0.38] if n==3 else [1/n]*n)
        widths=[CW*r for r in ratios]
    data=[[p(x,'thead') for x in headers]]+[[p(x,'table') for x in row] for row in rows]
    t=Table(data,colWidths=widths,repeatRows=1,hAlign='LEFT')
    style=[('VALIGN',(0,0),(-1,-1),'TOP'),('BACKGROUND',(0,0),(-1,0),HexColor(COLORS['ivory'])),
           ('LINEBELOW',(0,0),(-1,0),1.3,GOLD),('LEFTPADDING',(0,0),(-1,-1),8),
           ('RIGHTPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7)]
    for i in range(1,len(data)):
        if i%2==0:style.append(('BACKGROUND',(0,i),(-1,i),HexColor('#F3F6F6')))
        style.append(('LINEBELOW',(0,i),(-1,i),0.35,HexColor(COLORS['line'])))
    t.setStyle(TableStyle(style));return [t,Spacer(1,12)]
def stats(items):
    cells=[]
    for number,label in items:
        cells.append([Paragraph(html.escape(number),ParagraphStyle('number',fontName='Display',fontSize=27,leading=32,textColor=INK)),p(label,'small')])
    t=Table([cells],colWidths=[CW/len(cells)]*len(cells))
    t.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'TOP'),('BACKGROUND',(0,0),(-1,-1),HexColor(COLORS['ice'])),
                         ('LEFTPADDING',(0,0),(-1,-1),12),('TOPPADDING',(0,0),(-1,-1),12),('BOTTOMPADDING',(0,0),(-1,-1),11)]))
    return [t,Spacer(1,14)]

# Drawing primitives are also exported as editable SVG; no screenshot pixels are changed.
class Diagram(Flowable):
    def __init__(self,name,height=205):
        super().__init__();self.name=name;self.width=CW;self.height=height;self.ops=[]
        self.compose();self.export_svg()
    def rect(self,x,y,w,h,fill='#EAF3F6',stroke='#CFDCE2',radius=8):self.ops.append(('rect',x,y,w,h,fill,stroke,radius))
    def line(self,x1,y1,x2,y2,color='#536C77',width=1.2,dash=False):self.ops.append(('line',x1,y1,x2,y2,color,width,dash))
    def text(self,x,y,text,size=9,font='Body',color='#17313F',anchor='left'):self.ops.append(('text',x,y,str(text),size,font,color,anchor))
    def node(self,x,y,w,h,title,sub='',tone='#EAF3F6'):
        self.rect(x,y,w,h,tone)
        self.text(x+10,y+h-19,title,9.9,'BodyBold')
        lines=textwrap.wrap(sub,width=max(10,int((w-20)/4.2)))
        for i,line in enumerate(lines[:4]):self.text(x+10,y+h-35-i*11,line,8.5,color='#536C77')
    def arrow(self,x1,y1,x2,y2,color='#2C8F7D'):
        self.line(x1,y1,x2,y2,color,1.8);a=math.atan2(y2-y1,x2-x1)
        for side in [-1,1]:
            aa=a+side*0.5;self.line(x2,y2,x2-6*math.cos(aa),y2-6*math.sin(aa),color,1.8)
    def compose(self):
        n=self.name;w=self.width;h=self.height
        self.rect(0,0,w,h,'#F7F9F9',radius=9)
        if n in ['benchmark','parity_equity']:
            self.chart(n);return
        if n=='architecture':
            self.node(15,120,145,68,'WEB / STUDIO','Ayar taslağı + review',' #F8F2E4'.strip())
            self.node(181,120,145,68,'SUPABASE','Auth + private DB + Edge')
            self.node(347,120,145,68,'YEREL HELPER','Cihaz proof + IPC')
            self.node(181,19,145,68,'BROKER','Fiyat, tick, execution')
            self.node(347,19,145,68,'UNIVERSAL MT5','Native audit + risk + trade')
            self.arrow(160,151,181,151);self.arrow(326,151,347,151);self.arrow(420,120,420,87);self.arrow(347,54,326,54)
            self.text(15,90,'Ayar / imzalı komut →',8.5);self.text(15,74,'← terminal-reported sonuç',8.5)
        elif n=='authority':
            labels=[('KİMLİK','Supabase hesabı'),('ERİŞİM','Demo / abonelik'),('CİHAZ','Fingerprint onayı'),('KONTROL','Aktif generation')]
            for i,(title,sub) in enumerate(labels):
                x=13+i*126;self.node(x,132,113,56,title,sub,'#F8F2E4' if i==0 else '#EAF3F6')
                if i<3:self.arrow(x+113,160,x+126,160)
            self.node(22,25,207,69,'AUDIT / RESEARCH','Snapshot + imza + context checks')
            self.node(276,25,207,69,'TRADING ON','Ayrı onay + matching audit + kısa grant','#E7F4EF')
            self.arrow(451,132,451,94);self.arrow(60,132,60,94)
            self.text(151,109,'LOGIN ≠ CANLI İZİN',9,'BodyBold')
        elif n=='positions':
            self.node(16,122,222,63,'LEGACY','Bir aktif lifecycle / pozisyon','#F8F2E4')
            self.node(270,122,222,63,'INDEPENDENT','Toplam native kapasite: BUY + SELL')
            for i in range(10):
                self.rect(275+(i%5)*40,56+(i//5)*24,30,18,'#2C8F7D' if i<6 else '#B74C43',radius=3)
                self.text(290+(i%5)*40,61+(i//5)*24,'B' if i<6 else 'S',8,'BodyBold','#FFFFFF','center')
            self.text(277,29,'6 BUY + 4 SELL = 10 / 10',9,'BodyBold')
            self.text(28,80,'Yeni reverse signal',9);self.arrow(29,68,220,68);self.text(28,40,'open sonrası → wait → izinli exit',8.5)
        elif n=='geometry':
            for y,label,col in [(159,'TP: hedef fiyat','#2C8F7D'),(107,'ENTRY: executable fill','#17313F'),(56,'SL: ilk risk sınırı','#B74C43')]:
                self.line(24,y,279,y,col,2);self.text(296,y-3,label,10,'BodyBold',col)
            self.arrow(230,112,230,154);self.arrow(230,102,230,61)
            self.text(35,126,'Hedef R = TP mesafesi / ilk stop',9)
            self.text(35,22,'Örnek şema; gerçek fiyat serisi değildir.',8.5,color='#536C77')
        elif n=='builder':
            self.node(15,131,143,56,'BUY A','RSI(14) > 50','#F8F2E4');self.node(189,131,143,56,'BUY B','EMA(12) > EMA(26)');self.node(365,131,127,56,'KAPANMIŞ BAR','Causal state')
            self.arrow(158,159,189,159);self.text(169,175,'AND',8,'BodyBold');self.arrow(332,159,365,159)
            self.node(15,33,221,65,'SELL / EXIT AYRI','Ters kural otomatik varsayılmaz')
            self.node(270,33,222,65,'PREVIEW → KAYDET','Audit ve live izin ayrı','#E7F4EF')
            self.arrow(423,131,423,98);self.text(25,110,'((A OR B) AND C): soldan sağa',8.5)
        elif n=='order_flow':
            heights=[20,33,47,69,104,92,58,37,24]
            for i,hh in enumerate(heights):self.rect(30+i*27,50,19,hh,'#E4AD31' if i==4 else '#91BCC6',radius=2)
            self.text(28,174,'FİYAT BÖLGESİ AKTİVİTESİ',10,'BodyBold')
            self.node(310,107,178,70,'PROFILE / POC / VA','Referans quote histogramı')
            self.node(310,25,178,65,'ACTIVITY / DELTA','Signal candle quote proxy','#E7F4EF')
            self.text(28,22,'Temsilî histogram; market tape / L2 değildir.',8.1)
        elif n=='time_matrix':
            labels=['Pzt','Sal','Çar','Per','Cum','Cmt','Paz']
            for row,label in enumerate(labels):
                self.text(20,172-row*21,label,8.5)
                for col in range(12):self.rect(63+col*22,164-row*21,17,14,'#2C8F7D' if (row,col) in [(0,3),(1,6),(2,9),(4,6)] else '#DFE9ED',radius=2)
            self.text(64,191,'Her gün için bağımsız 24 saat maskesi',9,'BodyBold')
            self.node(351,104,140,73,'WR + N','Düşük örnek, yüksek belirsizlik','#F8F2E4');self.node(351,22,140,63,'TRAIN → TEST','Seçimi testte dondur')
            self.text(17,12,'Temsilî maske; gerçek leaderboard sonucu değil.',8)
        elif n=='timezone':
            for i,(title,sub) in enumerate([('NEW YORK','09:30 yerel açılış'),('UTC / GMT0','13:30 yaz / 14:30 kış'),('BROKER UTC+2','15:30 yaz / 16:30 kış')]):
                self.node(15+i*167,111,148,73,title,sub,'#F8F2E4' if i==0 else '#EAF3F6')
                if i<2:self.arrow(163+i*167,148,182+i*167,148)
            self.node(34,24,439,61,'BROKER DST ≠ EXCHANGE DST','Aynı UTC anı, farklı chart saatleri. Tarihsel policy açık olmalı.')
        elif n=='orb':
            self.rect(43,63,126,90,'#F8F2E4');self.line(25,153,450,153,'#2C8F7D',1.5);self.line(25,63,450,63,'#B74C43',1.5)
            pts=[(30,101),(57,120),(88,85),(120,128),(149,109),(187,146),(225,158),(253,170),(289,151),(334,183),(375,177),(437,190)]
            for a,b in zip(pts,pts[1:]):self.line(*a,*b,'#17313F',2)
            self.text(45,39,'OPENING RANGE',9,'BodyBold');self.text(263,103,'breakout / retest adayları',9)
            self.text(25,17,'Temsilî fiyat yolu; kendi başına audit sonucu değil.',8.5)
        elif n=='layout_templates' or n=='slide_wireframe':
            self.rect(20,29,468,157,'#FFFFFF',radius=3)
            self.rect(33,146,337,24,'#F8F2E4',radius=3);self.text(41,153,'TEK ANA MESAJ / BAŞLIK',10,'BodyBold')
            self.rect(33,55,265,80,'#EAF3F6',radius=4);self.text(165,96,'GERÇEK UI / DİAGRAM',11,'BodyBold',anchor='center')
            self.rect(311,55,163,80,'#E7F4EF',radius=4);self.text(319,111,'KANIT KARTI',10,'BodyBold');self.text(319,91,'metric + workload + tarih',8.5);self.text(319,72,'source + sınır',8.5)
            self.text(34,36,'KAYNAK / SYNTHETIC-HISTORICAL NOTU / RİSK',8,'Mono')
        else:
            flows={
             'product_loop':[('FİKİR','Kullanıcı hipotezi'),('KURAL','Açık koşullar'),('AUDIT','Broker geçmişi'),('KARAR','Ayrı canlı izin')],
             'family_bundle':[('ORB','Seans / range'),('MACROSS','MA / trend'),('SOL','Liquidity narrative'),('ENTRY LAB','44 feature + logic')],
             'strategy_snapshot':[('MOTOR','Setup kuralları'),('POLICY','SL/TP + exits'),('FİLTRE','NAS/OF/time'),('RİSK','Sizing + güvenlik')],
             'audit_pipeline':[('SNAPSHOT','Hash + context'),('HAZIRLIK','Coverage / history'),('REPLAY','Chronological exit'),('SONUÇ','Trade trace / DATA')],
             'csv_asof':[('AUDIT BİTER','Accepted records'),('EXPORT İSTEĞİ','Feature prep başlar'),('ENTRY CUTOFF','Kapalı bar replay'),('CSV DOSYASI','1 accepted trade = row')],
             'agent':[('KULLANICI','Natural language'),('MODEL','Typed proposal'),('VALIDATION','Schema + diff'),('KULLANICI','İncele ve uygula')],
            }
            seq=flows[n]
            for i,(title,sub) in enumerate(seq):
                self.node(13+i*126,111,113,73,title,sub,'#F8F2E4' if i==0 else '#EAF3F6')
                if i<3:self.arrow(126+i*126,148,139+i*126,148)
            foot={
              'product_loop':'Sonuçları öğren; hipotezi kayıtlı ve tekrar üretilebilir biçimde geliştir.',
              'family_bundle':'UniversalConnectionEA: dört ailenin mevcut implementasyonlarını taşır.',
              'strategy_snapshot':'Kaydet = motor + bütün etkin ayarlar + clock/maskeler + fingerprint.',
              'audit_pipeline':'Apply araştırmadır. Trading ON ayrı onay ve geçerli yetki gerektirir.',
              'csv_asof':'label_* sonuçtur; f_* as-of özelliktir. Missing veri sıfıra çevrilmez.',
              'agent':'AI Trading ON, pairing onayı veya risk acknowledgement yapamaz.'
            }[n]
            self.node(24,23,460,61,'KRİTİK AYRIM',foot,'#E7F4EF')
    def chart(self,n):
        if n=='benchmark':
            rows=[('MA / 20W',149.563,24.671),('LAB / 20W',159.453,18.422),('SOL / 20W',13.140,2.172),('SOL / 5Y',38.453,7.109)]
            self.text(15,185,'HAZIR BROKER GEÇMİŞİ / FIRST AUDIT',9,'BodyBold')
            for i,(label,a,b) in enumerate(rows):
                y=145-i*34;self.text(16,y+2,label,8.7,'BodyBold');self.rect(104,y,300*a/165,9,'#B8C6CD',radius=2);self.rect(104,y-12,300*b/165,9,'#2C8F7D',radius=2);self.text(422,y-4,f'{a/b:.2f}x',11,'BodyBold')
            self.text(17,15,'Gri: frozen baseline   Yeşil: optimized   Süreler saniye',8.5)
        else:
            closed=sorted([t for t in FACTS['trace'] if t['netR'] is not None and t['exitUtc']],key=lambda t:t['exitUtc'])
            vals=[0];
            for t in closed:vals.append(vals[-1]+t['netR'])
            lo=min(vals)-0.25;hi=max(vals)+0.25;span=hi-lo
            self.text(16,184,'GERÇEK NATIVE TRACE / KAPALI KÜMÜLATİF R',9,'BodyBold')
            x0,y0,ww,hh=45,37,424,128
            for k in range(5):
                v=lo+(hi-lo)*k/4;y=y0+hh*k/4;self.line(x0,y,x0+ww,y,'#DFE6E9',0.8);self.text(39,y-3,f'{v:.1f}',7.9,anchor='right')
            pts=[(x0+ww*i/(len(vals)-1),y0+hh*(v-lo)/span) for i,v in enumerate(vals)]
            for a,b in zip(pts,pts[1:]):self.line(*a,*b,'#2C8F7D',2)
            self.text(16,14,'Native ve Universal eğrisi eşleşti; 40 kapalı + 1 OPEN.',8.5)
    def draw(self):
        c=self.canv
        for o in self.ops:
            if o[0]=='rect':
                _,x,y,w,h,fill,stroke,r=o;c.setFillColor(HexColor(fill));c.setStrokeColor(HexColor(stroke));c.setLineWidth(0.6);c.roundRect(x,y,w,h,r,fill=1,stroke=1)
            elif o[0]=='line':
                _,x,y,xx,yy,color,width,dash=o;c.setStrokeColor(HexColor(color));c.setLineWidth(width);c.setDash([3,3] if dash else []);c.line(x,y,xx,yy);c.setDash([])
            else:
                _,x,y,t,size,font,col,anchor=o;c.setFont(font,size);c.setFillColor(HexColor(col));getattr(c,'drawString' if anchor=='left' else 'drawCentredString' if anchor=='center' else 'drawRightString')(x,y,t)
    def export_svg(self):
        lines=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="{int(1600*self.height/self.width)}" viewBox="0 0 {self.width:.3f} {self.height}">',
               '<title>'+escape(self.name)+'</title><desc>STRATUM teknik rapor; düzenlenebilir vektör şema. Temsilî şemalar piyasa sonucu değildir.</desc>']
        for o in self.ops:
            if o[0]=='rect':
                _,x,y,w,h,fill,stroke,r=o;lines.append(f'<rect x="{x}" y="{self.height-y-h}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="0.6"/>')
            elif o[0]=='line':
                _,x,y,xx,yy,col,width,dash=o;lines.append(f'<line x1="{x}" y1="{self.height-y}" x2="{xx}" y2="{self.height-yy}" stroke="{col}" stroke-width="{width}"/>')
            else:
                _,x,y,t,size,font,col,anchor=o;family='Consolas, monospace' if font=='Mono' else 'Candara, sans-serif';weight='700' if font=='BodyBold' else '400';anc={'left':'start','center':'middle','right':'end'}[anchor]
                lines.append(f'<text x="{x}" y="{self.height-y}" fill="{col}" font-family="{family}" font-size="{size}" font-weight="{weight}" text-anchor="{anc}">{escape(t)}</text>')
        lines.append('</svg>');(ASSETS/(self.name+'.svg')).write_text('\n'.join(lines),encoding='utf-8')

SOURCES=[
 ('S01','Ürün ve web konumlandırması','web-mvp/components/launch-page.tsx'),
 ('S02','191 katalog / 188 kampanya doğrulaması','reports/admin_campaign/VERIFICATION.md'),
 ('S03','Universal v2 input/runtime/builder sözleşmesi','web-mvp/lib/universal-contract.ts'),
 ('S04','Result/trade/coverage ve summarize sözleşmesi','web-mvp/lib/control-contract.ts'),
 ('S05','Ana sayfa görünümü ve current sunum metni','web-mvp/components/launch-page.tsx'),
 ('S06','DB readback ve katalog metrik karşılaştırması','reports/admin_campaign/final-db-verification.json'),
 ('S07','11 Ekim canlı oturum/yetki dağıtım doğrulaması','reports/session_continuity_20261011/verification.md'),
 ('S08','Native auth zinciri ve test sınırları (eski deploy bölümü güncel değil)','web-mvp/docs/MT5_AUTHORIZATION_VERIFICATION.md'),
 ('S09','Studio kontrol odaları, apply, result ve review','web-mvp/components/universal-dashboard.tsx'),
 ('S10','742 input/runtime definition kataloğu','web-mvp/lib/ea-controls.json'),
 ('S11','ORB kanonik davranış ve deployment kuralları','IndicatorCodeExamples/orb/README.md'),
 ('S12','MaCross kanonik davranış ve export','IndicatorCodeExamples/macrossover_orb/README.md'),
 ('S13','Sol Advanced position/apply ve export','IndicatorCodeExamples/SolAdvanced/README.md'),
 ('S14','Entry Lab şablon, builder ve policy semantiği','IndicatorCodeExamples/entry_engine_lab/README.md'),
 ('S15','Broker/exchange clock profile, limits ve test','IndicatorCodeExamples/DocumentsForAi/ORB_Broker_Timezone.md'),
 ('S16','Sol Apply / ORB layout 5 Ekim doğrulaması','reports/sol_apply_orb_layout_20261005.md'),
 ('S17','Sol NAS politikası ve native entegrasyon','IndicatorCodeExamples/SolAdvanced/LiqSolAdvancedNas.mqh'),
 ('S18','Native builder mantığı ve serialization','IndicatorCodeExamples/entry_engine_lab/LabEntryLogic.mqh'),
 ('S19','Entry-time CSV ve Pine kaynak mapping sözleşmesi','research/kivanc/README.md'),
 ('S20','OF quote-proxy, coverage, histogram ve gates','IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlowCore.mqh'),
 ('S21','OF worker/cache adaptasyonu','IndicatorCodeExamples/macrossover_orb/MaCrossOrderFlow.mqh'),
 ('S22','TIME MATRIX betimleme ve native saat maskeleri','docs/TradeCalendarMatrix.md'),
 ('S23','30 Eylül CSV/TIME MATRIX 5 yama doğrulaması','research/kivanc/CSV_TIME_MATRIX_FIXES_20260930_TR.md'),
 ('S24','CSV entry records, as-of writer ve path','IndicatorCodeExamples/macrossover_orb/AuditTradeCsv.mqh'),
 ('S25','Web katalog, window ve multi-sort davranışı','web-mvp/components/shared-strategy-library.tsx'),
 ('S26','Rolling campaign tasarım notları (progress tarihli)','reports/strategy_audit_20261009_rolling/README.md'),
 ('S27','Mühürlü campaign metrik nesneleri (özel tarif içermez)','reports/admin_campaign/campaign.private.json'),
 ('S28','Audit progress bileşeni test kaydı','web-mvp/scripts/test-audit-progress-ui.mjs'),
 ('S29','Frozen/optimized hız ve trace karşılaştırması','reports/audit_acceleration_20261003.md'),
 ('S30','24 Pine source manifest / SHA kayıtları','research/kivanc/source_manifest.json'),
 ('S31','Uygulanmamış literatür feature adayları','research/kivanc/FINANCIAL_FEATURE_RESEARCH_TR.md'),
 ('S32','ORB ML deney ve leakage/purge protokolü','docs/ORB_ML_Research_And_Validation.md'),
 ('S33','Private kontrol düzlemi ve live authority policy','web-mvp/control-service/control-plane.mjs'),
 ('S34','Supabase BFF oturum ve refresh uygulaması','web-mvp/control-service/supabase-auth.mjs'),
 ('S35','Üç dilli sekiz adım activation içeriği','web-mvp/lib/activation-guide.ts'),
 ('S36','Kişisel kurulum ve local helper state','web-mvp/control-service/personal-setup.mjs'),
 ('S37','AI typed tool sözleşmesi ve plan doğrulama','web-mvp/lib/studio-agent.ts'),
 ('S38','AI persona, lesson, voice sınırları (eski deploy notları güncel değil)','web-mvp/docs/STUDIO_AGENT.md'),
 ('S39','Agent chat/history/voice bileşeni','web-mvp/components/studio-agent.tsx'),
 ('S40','41-trade native/universal parity kaydı','tmp/universal_connection_validation/canonical-parity-report.json'),
 ('S41','Dört aile gerçek EX5 roundtrip sonuç ve chart kontrolleri','tmp/universal_connection_validation/roundtrip-report.json'),
 ('S42','Admin per-user strateji erişimi','web-mvp/ADMIN_STRATEGIES.md'),
]
EXTERNAL=[
 ('E01','MQL5 CopyTicksRange: tick isteme ve hata durumları','https://www.mql5.com/en/docs/series/copyticksrange'),
 ('E02','MQL5 OrderCalcMargin: teminat hesabı','https://www.mql5.com/en/docs/trading/ordercalcmargin'),
 ('E03','MQL5 OrderCalcProfit: hesap para biriminde PnL','https://www.mql5.com/en/docs/trading/ordercalcprofit'),
 ('E04','GitHub Pages statik site barındırma','https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages'),
 ('E05','Supabase Auth ürün dokümantasyonu','https://supabase.com/docs/guides/auth'),
 ('E06','Supabase RLS ve veri erişimi sınırları','https://supabase.com/docs/guides/database/postgres/row-level-security'),
]

class ReportDoc(BaseDocTemplate):
    def __init__(self,path):
        super().__init__(str(path),pagesize=A4,leftMargin=M,rightMargin=M,topMargin=48,bottomMargin=42,
                         title='STRATUM Teknik Referans ve Tanıtım Üretim Paketi',author='STRATUM / ProTradingSystem',
                         subject='Web + Supabase + native MT5: teknik context, kanıt, sunum ve video şablonları')
        frame=Frame(M,42,CW,H-90,leftPadding=0,rightPadding=0,topPadding=0,bottomPadding=0)
        self.addPageTemplates(PageTemplate('main',frames=[frame],onPage=self.chrome))
    def chrome(self,c,doc):
        c.saveState();c.setFillColor(GOLD);c.rect(0,H-4,W,4,fill=1,stroke=0)
        c.setFont('Mono',7.2);c.setFillColor(MUTED);c.drawString(M,H-28,'STRATUM / TEKNİK CONTEXT VE ÜRETİM REHBERİ')
        c.drawRightString(W-M,H-28,'11.10.2026 / İÇ KULLANIM')
        c.setStrokeColor(HexColor(COLORS['line']));c.setLineWidth(0.5);c.line(M,32,W-M,32)
        c.setFont('Body',7.5);c.drawString(M,20,'Kanıtın kapsamını koru. Geçmiş sonuç, gelecek getiri vaadi değildir.')
        c.setFont('Mono',8);c.drawRightString(W-M,20,f'{doc.page:02d}');c.restoreState()
    def afterFlowable(self,flowable):
        if isinstance(flowable,Paragraph) and hasattr(flowable,'bookmark'):
            key=flowable.bookmark;self.canv.bookmarkPage(key)
            self.canv.addOutlineEntry(flowable.getPlainText(),key,0,False)
            self.notify('TOCEntry',(0,flowable.getPlainText(),self.page,key))

def heading(title,bookmark):
    q=p(title,'title');q.bookmark=bookmark;return q
def markdown():
    lines=['# STRATUM Teknik Referans ve Tanıtım Üretim Rehberi','',DATA['date'],'',
           'İç kullanım. Kaynak-backed technical context; yeni audit veya live trading testi değildir.','']
    for s in DATA['sections']:
        lines+=['## '+s['title'],'',s['lead'],'']
        for b in s['blocks']:
            ty=b['type']
            if ty=='paragraph':lines+=[b['text'],'']
            elif ty=='bullets':lines+=['- '+x for x in b['items']]+['']
            elif ty=='callout':lines+=['**'+b['title']+'**',b['text'],'']
            elif ty=='table':
                lines+=['| '+' | '.join(b['headers'])+' |','| '+' | '.join(['---']*len(b['headers']))+' |']
                lines+=['| '+' | '.join(row)+' |' for row in b['rows']]+['']
            elif ty=='image':lines+=['![ '+b['caption']+' ](assets/'+b['asset']+'.png)','','**Görsel kapsamı:** '+b['caption'],'']
            elif ty=='diagram':lines+=['![Şema: '+b['name']+'](assets/'+b['name']+'.svg)','']
            elif ty=='stats':lines+=['; '.join(n+' '+label for n,label in b['items']),'']
            elif ty=='examples':
                for x in FACTS['examples']:lines.append(f"- {x['family']} / {x['name']} / {x['symbol']} / M{x['timeframe']} / 5Y: {x['metrics']['wins']}W, {x['metrics']['losses']}L, {x['metrics']['netR']:.4f}R")
                lines+=['']
        lines+=['Kaynaklar: '+', '.join(s.get('sources',[])),'']
    lines+=['## Kaynaklar','']+['- '+sid+' / '+title+' / `'+path+'`' for sid,title,path in SOURCES]
    lines+=['']+['- '+sid+' / ['+title+']('+url+')' for sid,title,url in EXTERNAL]
    return '\n'.join(lines)

def make_story():
    story=[]
    story+=[Spacer(1,44),p('ÜRÜN + MÜHENDİSLİK + TANITIM ÜRETİMİ','kicker'),
            Paragraph('STRATUM',ParagraphStyle('cover',fontName='Display',fontSize=50,leading=60,textColor=INK)),Spacer(1,15),
            Paragraph(DATA['subtitle'],ParagraphStyle('coversub',fontName='BodyBold',fontSize=23,leading=29,textColor=INK)),Spacer(1,17),
            p('Dört native motor ailesi. Bir web çalışma alanı. Kullanıcıya bağlı MT5 yürütmesi.','lead'),Spacer(1,12),Diagram('product_loop',205),Spacer(1,22)]
    story+=stats([('191','strateji kataloğu'),('188 × 9','tarihli kampanya kaydı'),('4','native motor ailesi')])
    story+=[p('Teknik referans ve agent context paketi','calltitle'),p('DeckCraft sunumları, FilmCraft videoları ve güvenilir ürün anlatımı için hazırlanmıştır. Mimari, veri sözleşmeleri, doğrulama kapsamı, görsel varlıklar ve düzenlenebilir şablonlar içerir.'),p('Sürüm kesiti: 11 Ekim 2026. Bu belge yatırım tavsiyesi, kâr garantisi veya bütün sistemin kusursuzluk sertifikası değildir.','small'),PageBreak()]
    story+=[heading('İçindekiler','contents'),p('Teknik incelemeyi, ürün anlatımını ve üretim planını aynı kaynak kimlikleriyle bağlayan referans. PDF yer imleri ve sayfa bağlantıları kullanılabilir.','lead')]
    toc=TableOfContents();toc.levelStyles=[ParagraphStyle('toc0',fontName='Body',fontSize=9.8,leading=11.8,textColor=INK,spaceBefore=1,leftIndent=0,firstLineIndent=0)]
    story+=[toc,PageBreak()]
    for s in DATA['sections']:
        story+=[p(s['kicker'],'kicker'),heading(s['title'],s['id']),p(s['lead'],'lead')]
        for b in s['blocks']:
            ty=b['type']
            if ty=='paragraph':story.append(p(b['text']))
            elif ty=='bullets':story.extend(p('- '+x,'bullet') for x in b['items'])
            elif ty=='callout':story+=callout(b['title'],b['text'])
            elif ty=='table':story+=table(b['headers'],b['rows'])
            elif ty=='stats':story+=stats(b['items'])
            elif ty=='diagram':story+=[Diagram(b['name'],180 if b['name']=='geometry' else 205),Spacer(1,13)]
            elif ty=='image':
                path=ASSETS/(b['asset']+'.png')
                if not path.exists():raise FileNotFoundError('Required visual missing: '+str(path))
                im=Image(str(path));scale=min(CW/im.imageWidth,b['height']/im.imageHeight)
                im.drawWidth=im.imageWidth*scale;im.drawHeight=im.imageHeight*scale;im.hAlign='LEFT'
                story+=[KeepTogether([im,Spacer(1,5),p(b['caption'],'small')]),Spacer(1,8)]
            elif ty=='examples':
                rows=[]
                for x in FACTS['examples']:
                    m=x['metrics'];rows.append([f"{x['family'].upper()} / {x['name']}",f"{x['symbol']} / M{x['timeframe']} / 5Y\n{x['mode']}",f"{m['wins']}W / {m['losses']}L / {m['open']}O\nWR {m['winRate']:.2f}%",f"Net {m['netR']:+.4f}R\nMinCum {m['minCumR']:.4f}R"])
                story+=table(['Örnek strateji','Bağlam','İşlem / WR','Sonuç'],rows,[CW*.29,CW*.23,CW*.23,CW*.25])
                story.append(p('Tarih kesiti: broker wall-clock 09.10.2026 19:46:57. Değerler mühürlü MEGA arşivinden; yeni canlı/backtest çalışması değil.','small'))
        if s.get('sources'):story.append(p('KANIT / '+', '.join(s['sources']),'source'))
        story.append(PageBreak())
    atlas=[('web_strategy_result_card','Strateji kartı: metriklerin okunması',"Üretim arayüzü + mevcut 5Y MEGA arşivi. Yeni audit çalıştırılmadı; erişim/kimlik test verisidir. Total, W/L/O/F, WR, Net R ve MinCum seçili pencerenin değerleridir. Kartın orijinal PNG dosyası ayrı verilir."),
           ('web_entry_builder','Builder ekranı: ayrı BUY ve SELL kuralları','Üretim arayüzünde RSI(14) için eğitim taslağı. Bu örnek yatırım önerisi değildir; ayarlar sunucuya uygulanmadı ve emir açılmadı. Comparator, mantık kapısı, sağ operand ve NOT kontrollerinin yerleri görülür.'),
           ('web_nas_controls','NAS odası: görünür parametreler','Üretim arayüzü kaydı; varsayılan taslak. Entry/state gate, exit seçenekleri, ayrı state/flow hacim ayarları ve wait/age alanları ayrı davranışları temsil eder.'),
           ('web_activation_guide','Aktivasyon rehberi: kullanıcıya gösterilen ekran','Üretim rehberi kaydı. Demo süreleri görsel test verisidir. Bu kayıtta yeni cihaz eşleştirilmedi; gerçek pairing code ve özel kurulum anahtarları kullanılmadı.')]
    for i,(asset,title,caption) in enumerate(atlas):
        story+=[p('EK / EKRAN ATLASI','kicker'),heading(title,'atlas-'+str(i)),p(caption,'lead')]
        im=Image(str(ASSETS/(asset+'.png')));scale=min(CW/im.imageWidth,565/im.imageHeight)
        im.drawWidth=im.imageWidth*scale;im.drawHeight=im.imageHeight*scale;im.hAlign='LEFT'
        story+=[im,Spacer(1,12),p('Tam çözünürlüklü dosya: assets/'+asset+'.png','small'),PageBreak()]
    story+=[p('49 / VARLIK ENVANTERİ','kicker'),heading('Görsel ve şablon dosyaları','asset-index'),p('PNG gerçek UI kaydı; SVG editlenebilir teknik şema. Her görüntünün gerçek, tarihsel veya sentetik kapsamı etiketlidir.','lead')]
    image_map={x['id']:x for x in FACTS.get('screenshots',[])}
    for path in sorted(ASSETS.iterdir()):
        if path.suffix.lower() not in ['.png','.svg']:continue
        cap=image_map.get(path.stem,{}).get('caption','Vektör şema / yerleşim şablonu; fiyat yolu veya maskeler aksi belirtilmedikçe temsilîdir.')
        if path.stem=='legacy_sol_jp225':cap='Eski Temmuz 2026 native Sol ekranı; güncel UI / kampanya kanıtı değil.'
        if path.stem=='download_progress':cap="Mevcut progress UI'nin test kaydı; gerçek indirme/audit olmadığı etiketli."
        story.append(KeepTogether([p(path.name,'calltitle'),p(cap,'small')]))
    story.append(PageBreak())
    story+=[p('50 / İZLENEBİLİRLİK','kicker'),heading('Kaynak kayıtları ve öncelik','sources'),p("İç kaynaklar mevcut workspace'e göre relatif verilmiştir. Tarihli doğrulama kapsamı genel kusursuzluk iddiasına yükseltilmez.",'lead')]
    for sid,title,path in SOURCES:
        story.append(Paragraph(f'<b>{sid} / {html.escape(title)}</b><br/>{html.escape(path)}',S['ref']))
    story+=[p('Resmî dış kaynaklar / 11.10.2026 erişimi','calltitle')]
    for sid,title,url in EXTERNAL:
        story.append(Paragraph(f'<b>{sid} / {html.escape(title)}</b><br/><a href="{url}" color="#2C8F7D">{html.escape(url)}</a>',S['ref']))
    story+=callout('Güncellik kuralı','11 Ekim oturum/yayımlama raporu, eski local-pilot ifadelerinin önüne geçer. Katalog için 10 Ekim DB verification; hız için 3 Ekim frozen/optimized kanıtı; CSV şema için 30 Eylül test kapsamı. Tarihler veya source/config fingerprint değişince ilgili iddia yeniden doğrulanmalı.')
    return story

def bundle():
    write_templates(ASSETS)
    shutil.copy2(ROOT/'IndicatorCodeExamples/OptimalSettingsForLiqNarrative/jp225OptimalLiqNarrative.png',ASSETS/'legacy_sol_jp225.png')
    shutil.copy2(ROOT/'reports/verification_build/audit_progress_20261011/download-progress-desktop.png',ASSETS/'download_progress.png')
    shutil.copy2(ROOT/'web-mvp/lib/ea-controls.json',OUT/'controls_catalog.json')
    shutil.copy2(ROOT/'research/kivanc/source_manifest.json',OUT/'pine_source_manifest.json')
    (OUT/'style_tokens.json').write_text(json.dumps({'palette':COLORS,'deck':'16:9 / 1920x1080','bodyMinPt':22,'headingPt':'36-44','motion':'180-280ms UI / 450-700ms diagram','sourceFootnoteRequired':True,'financialResults':'historical/simulated label'},ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'RAPOR_KAYNAGI_TR.md').write_text(markdown(),encoding='utf-8')
    brief='''# STRATUM - agent başlangıç bağlamı\n\n1. Bu paket bir kod değişikliği veya yeni audit kampanyası değildir.\n2. Web ayarları oluşturur; imzalı yetki buluttan; audit/trade kullanıcının MT5'inde.\n3. ORB, MaCross, Sol Advanced, Entry Lab tek subscriber UniversalConnectionEA içindedir.\n4. Apply araştırma. Trading ON ayrı explicit review.\n5. 191 katalog kaydı; 188 kampanya stratejisi; 1692 pencere durumu: 1616 available, 76 unavailable.\n6. MEGA tarihli frozen kanıttır. CURRENT farklı endpoint/clock/config'le otomatik aynı sayı olamaz.\n7. Benchmark 5-8x örnekler hazır broker history üzerinde actual recalculation işleridir; download SLA değil.\n8. 41-trade native/universal parity kontrollü bir preset örneğidir, all-strategy guarantee değil.\n9. 7 günlük login kısa native grant/valid subscription/helper gereksinimini kaldırmaz.\n10. OF quote proxy. AI önerisi UI review olmadan uygulanmaz; AI trade on yapamaz.\n11. PNG'lerin fixture/tarihsel/sentetik kapsamlarını oku. UI kartında gösterilen sayı değiştirilmez.\n12. Yeni haber pipeline, JEV/RLCD, strateji marketi, hardware attestation ve full billing doğrulanmış mevcut özellikler değildir.\n\n## Dosyalar\n- STRATUM_Teknik_Referans_20261011.pdf: ana rapor.\n- RAPOR_KAYNAGI_TR.md: aranabilir tam içerik.\n- DECKCRAFT_BRIEF_TR.md / FILMCRAFT_BRIEF_TR.md: hazır üretim planları.\n- assets/: gerçek UI PNG'leri ve editlenebilir SVG şemaları.\n- evidence_summary.json: kaynak-backed sayılar ve gerçek native trade trace örneği.\n- campaign_metrics.json: metrik-only 188 strateji arşivi; özel tarif/kişisel hesap bilgisi yok.\n- controls_catalog.json: public frontend'in 742 aile input/runtime tanımı.\n- manifest.json: paket dosya hash'leri ve kaynak provenance.\n\n## Güvenlik\nKurulum video kaydında .state, private key, download ticket, pairing code/fingerprint ve gerçek broker account login gösterilmez. Native motor kaynakları bu pakette yoktur.\n'''
    brief+='''\n## Okuma rotası\n- Önce bu kısa bağlam dosyasını, sonra PDF başlangıç özetini ve kendi üretim briefini oku.\n- Mimari ve motorlar: PDF 4-14; kontrol davranışları: 15-24.\n- Kütüphane, kampanya, audit, hız, CSV ve araştırma: 25-34.\n- Kimlik, kurulum, agent, test kapsamı: 35-44.\n- Görsel dil, sunum/video planı ve sahne şablonları: 45-50.\n- Terimler ve okunabilir ekran atlası: 51-55. Kaynaklar: son bölüm.\n- Bir sayı veya özellik eklemeden source ID ve kanıt sınırını kontrol et.\n- Canlı site: https://cemkaaa.github.io/CemkaCapital/\n- Studio: https://cemkaaa.github.io/CemkaCapital/studio/\n- Bu ZIP, çalıştırılabilir abone kurulumu değil, iç üretim/context paketidir.\n'''
    (OUT/'HIZLI_BAGLAM.md').write_text(brief,encoding='utf-8')
    md=markdown()
    for fname,ids in [('DECKCRAFT_BRIEF_TR.md',['claims','visual_system','deckcraft','templates','handoff']),('FILMCRAFT_BRIEF_TR.md',['claims','visual_system','film_promo','film_tutorial','templates','handoff'])]:
        selected=[s for s in DATA['sections'] if s['id'] in ids];parts=['# '+fname.removesuffix('.md'),'']
        for s in selected:
            start=md.index('## '+s['title']);end=md.find('\n## ',start+4);parts.append(md[start:end if end!=-1 else len(md)])
        (OUT/fname).write_text('\n\n'.join(parts),encoding='utf-8')
    for name in ['layout_templates','slide_wireframe','benchmark','parity_equity']:
        Diagram(name)
    manifest={'created':'2026-10-11','scope':'Internal technical context / no new live orders or campaign','sources':[],'assets':[]}
    for sid,title,path in SOURCES:
        source=ROOT/path
        if not source.is_file():raise FileNotFoundError('Source missing '+path)
        manifest['sources'].append({'id':sid,'title':title,'workspacePath':path,'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'reviewScope':'relevant source sections and dated verification, not a full fresh code audit'})
    manifest['externalSources']=[{'id':sid,'title':title,'url':url,'accessed':'2026-10-11'} for sid,title,url in EXTERNAL]
    for path in sorted(OUT.rglob('*')):
        if path.is_file() and path.name not in ['manifest.json']:
            manifest['assets'].append({'path':path.relative_to(OUT).as_posix(),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

if __name__=='__main__':
    bundle()
    ReportDoc(PDF).multiBuild(make_story())
    shutil.copy2(PDF,OUT/PDF.name)
    bundle()
    print(json.dumps({'pdf':str(PDF),'bytes':PDF.stat().st_size,'sections':len(DATA['sections']),'assets':len(list(ASSETS.iterdir()))},ensure_ascii=False))
