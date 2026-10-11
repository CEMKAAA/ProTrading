# DECKCRAFT_BRIEF_TR



## Tanıtım için iddia ve kanıt tablosu

Bir cümleye kanıt kartı bağlanamıyorsa kesin teknik veya finansal iddia olarak kullanma.

| Kullanılabilir ifade | Kanıt | Eklenmesi gereken sınır |
| --- | --- | --- |
| Dört motor ailesi tek bağlantı üzerinden | Universal kaynak/roundtrip | Her strateji için exhaustive parite değil. |
| Kural tabanlı BUY/SELL builder | Native 44 feature + web v2 rules | Sınırsız feature/derinlik veya proprietary ORB/Sol tarifini paylaşma değil. |
| 191 kayıtlı katalog stratejisi | Native/web mapping 191/191 | Kullanıcı adminin açtıklarını görür; üçünde MEGA yok. |
| 188 strateji, dokuz kampanya penceresi | 1.692 durum kaydı | 1.616 available; 76 unavailable. |
| Ölçülen yeniden hesaplamalarda 5-8× hız | 3 Ekim frozen/optimized timing | Hazır geçmiş; workload örnekleri; bütün işler aynı değil. |
| 14.177 trade trace eşleşti | Exact acceleration regression | Eski motoru referansla eşlemek kusursuz market truth değil. |
| 41 işlemde native/universal eşdeğerlik | MaCross JP225m seçili preset | Bir kontrollü örnek; live execution garantisi yok. |
| 7 günlük login, ayrı canlı yetki | 118 auth/policy test | Yeni login; kısa grants; geçerli erişim/helper/MT5 gerekir. |
| Tarihsel pozitif strateji örnekleri | Donmuş MEGA değerleri | Geriye dönük seçilmiş, forward/holdout başarı vaadi değil. |

**Yasak / desteklenmeyen sloganlar**
Kâr garantisi; risksiz; bütün brokerlarda 5Y exact M1; L2/L3 smart-money detector; kırılamaz lisans; hiçbir bug yok; yüzde yüz live/backtest aynı; mutlak inversion; 742 bağımsız simülatör; Borsa İstanbul resmî ortağımız. Bunların kanıtı bu pakette yok.

Daha güçlü ve dürüst alternatif: 'Fikrini kur. Kendi broker geçmişinde test et. İşlem izini gör. Yetkiyi sen ver.' Başarıyı yalnız W/L değil; doğru provenance, coverage, tekrar üretim, işlem trace paritesi ve ölçülen araştırma süresiyle anlatın.

Kaynaklar: S02, S07, S29, S40, S41


## Görsel dil ve düzen şablonları

Parlak araştırma stüdyosu, koyu native chart ve altın aksanı aynı ürün ailesine bağla; her kutuya ayrı stil icat etme.

![Şema: layout_templates](assets/layout_templates.svg)

| Öğe | Önerilen kural | Dosya / kullanım |
| --- | --- | --- |
| Renk | Ink #17313F; gold #E4AD31; ice #EAF3F6; mint #2C8F7D | style_tokens.json; aynı palette tut. |
| Başlık | Kısa, güçlü; bir sahnede tek ana fikir | 16:9 deck'te 36-44 pt; body 22-26 pt. |
| Sayısal kanıt | Büyük değer + koşul + kaynak + tarih | Tek başına '8×' değil: hangi audit, veri hazır mı? |
| UI screenshot | Kendi oranında; okunacak kontrolü close-up göster | Stretch yapma, dashboard minik yazı duvarına dönüşmesin. |
| Diagram | 4-6 düğüm; açık oklar ve trust sınırı | SVG kaynakları düzenlenebilir; screenshot üstüne rastgele ok değil. |
| Motion | 180-280 ms UI pop; 450-700 ms diagram reveal | Mühendislik cümlesini dikkat dağıtan loop ile örtme. |
| Footer | Kaynak/tarih, historical/synthetic etiketi | Risk notu final frame ve finansal sonuç karesinde. |
| Ses | Net uzman ton; sakin ama canlı | Kazanç rakamında casino/confetti efekti kullanma. |

Tasarım önerileri üretim UI'sına yeni özellik eklenmiş gibi sunulmaz. SVG storyboard çerçeveleri içerik yerleşim şablonudur; uygulamadaki gerçek ekranlar PNG varlıklarıdır. DeckCraft'ta editlenebilir metin/şekil kullan; her slaytı tek flatten PNG yapma.

Kaynaklar: 


## DeckCraft: 14 slaytlık ana sunum

12-15 dakikalık ürün ve mühendislik sunumu. Her slayt bir iddia, bir görsel ve bir kanıt sınırı taşır.

| Slayt | Başlık / ana mesaj | Görsel / kanıt |
| --- | --- | --- |
| 01 | Fikrinden sistemine: STRATUM | Hero, product loop, kısa research mesajı. |
| 02 | Problem: fikir var, tekrar üretim zor | Teknik kokpit → odaklı oda şablonu; kullanıcı akışı. |
| 03 | Web + senin MT5'in | Architecture SVG; cloud izin/native hesap ayrımı. |
| 04 | Dört aile, tek bağlantı | Family bundle; ORB/Ma/Sol/Lab rol tablosu. |
| 05 | Kural oluşturma özgürlüğü | Builder diagram; BUY/SELL ayrı; 44 feature. |
| 06 | Geometri, risk, exits senin kontrolünde | Geometry + Positions; pip/risk % ayrımı. |
| 07 | Setup bağlamını ölç | NAS ve quote-proxy OF; L2/L3 olmadığını küçük notla. |
| 08 | Ne zaman trade edeceğini belirle | Time Matrix SVG; seçili pencere + MIN N. |
| 09 | Sonucu parçala, yalnız WR'ye bakma | Gerçek MEGA örnek tablosu; retrospective seçimi yaz. |
| 10 | Hızlı research, değişmeyen trace | Benchmark SVG; hazır geçmiş ve workload notu. |
| 11 | Güven zinciri kullanıcıya bağlı | Authority SVG; tek controller ve kısa grant. |
| 12 | Native ile subscriber sonucu eşleşiyor mu? | 41-trade parity curve/table; kapsamı açık. |
| 13 | İlk auditin sekiz adımı | Activation screenshot + 8-step checklist. |
| 14 | Test et, anla, kararını ver | Live review ayrı; çağrı: demo research workspace. |

**Deck teslimat şartı**
Düzenlenebilir native DeckCraft proje + PPTX + PDF önizleme. Her slaytta source ID speaker note'a yazılsın. 16:9; hiçbir metin kadraj taşması, 20 pt altına kaçan ana body veya sahte live veri olmasın.

Önerilen açılış: 'Bir fikrin var. Peki o fikir hangi koşulda işlem olacak, nasıl test edilecek ve ne zaman duracak? STRATUM bu soruları görünür kurallara ve kendi MT5 terminalindeki ölçülebilir sonuçlara bağlar.'

Kaynaklar: S02, S29, S40


## Yeniden kullanılabilir sahne şablonları

Şablonlar editlenebilir SVG olarak pakette bulunur; içerik yerleşimini korurken farklı gerçek ekranlarla yeniden kullanılabilir.

![Şema: slide_wireframe](assets/slide_wireframe.svg)

| Şablon / asset | Alanlar | Ne zaman kullanılır? |
| --- | --- | --- |
| T01_evidence_card.svg | İddia, büyük metric, workload, tarih, source, limit | Benchmark, parite veya catalogue sayılarını anlatırken. |
| T02_ui_walkthrough.svg | Screenshot alanı, 1-3 callout, kullanıcı aksiyonu, başarı kontrolü | Activation ve audit tutorial. |
| T03_trust_boundary.svg | Browser/cloud/local/broker lane; signed arrows | Auth ve connection mimarisi. |
| T04_before_after.svg | Baseline/optimized değer; aynı config checklist | Hız veya filtre experiment; fake profitability değil. |
| T05_strategy_evidence.svg | Name, family, symbol/TF, window/as-of, W/L/O, Net R | Tarihsel örnek; seçilme kuralı ve sample N görünür. |
| T06_error_clinic.svg | Mesaj, sebep hipotezi, kontrol adımı, unresolved state | History ve pairing troubleshooting. |

FilmCraft katmanları: BG, UI_MAIN, FOCUS_FRAME, CALLOUT_01..03, SOURCE_FOOTNOTE, RISK_NOTE, CAPTIONS, VOICEOVER ve MUSIC. DeckCraft shape/text layer adları aynı varlık kimliklerine bağlanır. Logo/coin yalnız görsel marka katmanıdır; hareketli fiyat veya canlı market data iması üretmemeli.

**Agentın teslim raporu**
Kullandığı bütün kaynak/görsel ID'leri, içeriğe eklediği herhangi yeni iddiayı ve gerçek/sentetik ekran ayrımını teslimde belirtmeli. Render edilmiş bütün slayt ve video frame'lerini kadraj/okunabilirlik için doğrulamalı.

Kaynaklar: 


## Diğer agentlara hazır görev metinleri

Bu metinler paketi doğrudan DeckCraft/FilmCraft üretim görevine çevirmek için kullanılabilir.

**DeckCraft agent brief**
STRATUM teknik referans PDF'sini ve HIZLI_BAGLAM.md dosyasını oku. 14 slayt planını uygula; düzenlenebilir native sunum, PPTX ve PDF üret. assets altındaki gerçek UI PNG'leri ile SVG şemalarını kullan. Kanıt sayıları evidence_summary.json ve kaynak tablosuna bağlı kalsın. Kâr garantisi, mutlak inversion, sınırsız L2/L3 veya full production security iddiası ekleme. Eski native screenshot ve sentetik lesson'ı açık etiketle. Kaynak IDs speaker notes'ta. 16:9, büyük okunabilir yazı; bütün slaytları render ederek taşma kontrolü yap.

**FilmCraft agent brief**
90 saniyelik promo ve 8 dakikalık kurulum tutorial'ını ayrı editlenebilir projeler olarak hazırla. PDF'nin shot/timecode planını kullan; UI screenshot metriklerini değiştirme. Video tanıtım metni ve ekran alanları kullanıcıya 'fikir → kural → MT5 audit → ayrı canlı izin' yolunu anlatsın. Historical/synthetic sınırlarını ve broker-history koşullarını belirt. Özel .state, ticket, code, fingerprint ve hesap bilgisini açık gösterme. Trading ON'a basmadan live-review aşamasını öğret. 1080p ana output ve düzgün reframe dikey kısa versiyon; licensed audio, altyazı, kaynak listesi ve render doğrulaması teslim et.

İnternet bağlantısı veya gerçek demo hesabı yoksa mevcut PNG/diagram kayıtlarıyla labeled walkthrough üret. Yeni canlı ekran kaydı yaptığını, gerçek audit çalıştırdığını veya native engine formüllerini satır satır yeniden doğruladığını söyleme. Görsel kaydı elde edememek sahte bir sonuç üretmek için gerekçe değildir.

Paket paylaşımı iç teknik/üretim amaçlıdır. Yayına verilecek deck/video için özel kaynak yollarını ve güvenlik uygulama ayrıntılarını çıkar; public iddia/kanıt kartları ve güvenli ekranlar yeterlidir. Şirketin proprietary source veya tam strateji tarifleri bu pakette dağıtılmaz.

Kaynaklar: 
