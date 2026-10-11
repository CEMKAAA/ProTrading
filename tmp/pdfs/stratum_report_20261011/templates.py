from pathlib import Path
from html import escape

INK = '#17313F'
GOLD = '#E4AD31'
MINT = '#2C8F7D'
ICE = '#EAF3F6'


def write_templates(target: Path):
    """Editable 16:9 layouts. Brackets are content placeholders, never actual results."""
    for index, name, title in [
        ('T01', 'evidence_card', 'Bir iddia. Bir kanıt. Açık bir sınır.'),
        ('T02', 'ui_walkthrough', 'Kullanıcının yapacağı tek adım'),
        ('T03', 'trust_boundary', 'Bulut yetkilendirir. MT5 hesaplar.'),
        ('T04', 'before_after', 'Aynı iş yükü. Ölçülmüş fark.'),
        ('T05', 'strategy_evidence', 'Stratejiyi yalnız WR ile değerlendirme'),
        ('T06', 'error_clinic', 'Mesajı oku. Kontrol et. Sonucu doğrula.'),
    ]:
        elements = []

        def box(x, y, w, h, fill=ICE, stroke='#CFDCE2', radius=22):
            elements.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}"/>')

        def text(x, y, value, size=30, fill=INK, weight='400'):
            elements.append(f'<text x="{x}" y="{y}" font-family="Candara, sans-serif" font-size="{size}" font-weight="{weight}" fill="{fill}">{escape(value)}</text>')

        def arrow(x1, y1, x2, y2):
            elements.append(f'<path d="M{x1} {y1} L{x2} {y2}" stroke="{MINT}" stroke-width="5" fill="none" marker-end="url(#arrow)"/>')

        box(0, 0, 1920, 1080, '#FAFBFA', '#FAFBFA', 0)
        box(0, 0, 1920, 12, GOLD, GOLD, 0)
        text(82, 70, 'STRATUM / '+index+' / EDITLENEBİLİR YERLEŞİM ŞABLONU', 23)
        text(82, 168, title, 56, weight='700')
        if index == 'T01':
            box(82, 244, 1100, 620)
            text(128, 321, '[KANITLANMIŞ İDDIA]', 31, weight='700')
            text(128, 515, '[METRİK]', 118, weight='700')
            text(128, 618, '[Birim + iş yükü + sembol / TF / pencere]', 32)
            text(128, 699, '[Tarih / veri hazır mı / ölçüm yöntemi]', 29)
            box(1226, 244, 612, 620, '#F8F2E4')
            text(1265, 321, 'KANIT SINIRI', 31, weight='700')
            for y, value in [(404, '[Ne ölçüldü?]'), (477, '[Ne ölçülmedi?]'), (550, '[Kaynak ID / rapor]'), (623, '[Genelleme sınırı]')]:
                text(1265, y, value, 29)
        elif index == 'T02':
            box(82, 244, 1200, 650, '#EAF3F6')
            text(125, 332, '[GERÇEK UI GÖRSELİ: oranını koru]', 31, weight='700')
            for i, (x, y) in enumerate([(240, 440), (830, 526), (1030, 730)], 1):
                elements.append(f'<circle cx="{x}" cy="{y}" r="32" fill="{GOLD}"/>')
                text(x-9, y+11, str(i), 29, weight='700')
            box(1320, 244, 518, 650, '#F8F2E4')
            for y, v in [(335, '1 / [Kullanıcı aksiyonu]'), (449, '2 / [Değişen kontrol]'), (563, '3 / [Başarı kontrolü]'), (767, '[Hata / güvenli çıkış]')]:
                text(1356, y, v, 28, weight='700')
        elif index == 'T03':
            labels = [('BROWSER', 'Taslak + açık kullanıcı onayı'), ('SUPABASE', 'Erişim + imzalı komut'), ('YEREL HELPER', 'Cihaz proof + kısa lease'), ('MT5 / BROKER', 'Audit + quote + execution')]
            for i, (label, sub) in enumerate(labels):
                x = 82 + 446*i
                box(x, 304, 418, 480, '#F8F2E4' if i == 0 else ICE)
                text(x+29, 385, label, 29, weight='700')
                for j, piece in enumerate(sub.split(' + ')):
                    text(x+29, 493+70*j, piece, 27)
                if i < 3:
                    arrow(x+418, 740, x+446, 740)
                if i > 0:
                    elements.append(f'<path d="M{x-14} 253 V849" stroke="#B74C43" stroke-width="2" stroke-dasharray="9 8"/>')
            text(82, 915, 'LOGIN ≠ TRADING ON    /    kısa yetki, canlı erişim ve açık helper gerekir', 30, weight='700')
        elif index == 'T04':
            for x, label, fill in [(82, 'BASELINE', ICE), (982, 'OPTIMIZED', '#E7F4EF')]:
                box(x, 244, 856, 500, fill)
                text(x+43, 323, label, 30, weight='700')
                text(x+43, 496, '[DEĞER + BİRİM]', 67, weight='700')
                text(x+43, 606, '[Aynı config / aynı broker geçmişi]', 28)
            box(82, 782, 1756, 133, '#F8F2E4')
            text(125, 840, '[Parity sonucu] / [Veri hazır] / [Workload] / [Tarih + source ID]', 30, weight='700')
            text(125, 886, 'Sonuçlar değiştiyse performans iddiasından önce farkı açıklayın.', 27)
        elif index == 'T05':
            box(82, 244, 1756, 138, '#F8F2E4')
            text(123, 302, '[STRATEJİ ADI] / [AİLE] / [SEMBOL + TF]', 34, weight='700')
            text(123, 350, '[Pencere + cutoff] / [Legacy veya Independent] / [MEGA veya Current]', 28)
            for i, label in enumerate(['W / L / O / DATA', 'WR + kapalı N', 'NET R + MINCUM']):
                x = 82 + i*595
                box(x, 430, 566, 300)
                text(x+30, 495, label, 28, weight='700')
                text(x+30, 617, '[DEĞER]', 64, weight='700')
            box(82, 774, 1756, 138, '#E7F4EF')
            text(123, 834, '[Seçim kuralı + gerçek/benzetim + kaynak + sınır]', 31, weight='700')
            text(123, 879, 'Geriye dönük örnek seçimi, bağımsız forward başarı kanıtı değildir.', 29)
        else:
            box(82, 244, 1756, 150, '#F8F2E4')
            text(123, 307, '[GERÇEK HATA MESAJI]', 40, weight='700')
            text(123, 358, 'Başarı varsayma. Mesajı görünür tut.', 29)
            for i, (label, values) in enumerate([
                ('1 / OLASI SEBEP', ['[Kanıta bağlı hipotez]', '[Aynı görünüm, farklı neden]']),
                ('2 / KONTROL', ['[Somut kullanıcı adımı]', '[Gerekli kaynak / veri]']),
                ('3 / DOĞRULAMA', ['[Başarı göstergesi]', '[Çözülmediyse doğru durum]'])
            ]):
                x = 82+i*595
                box(x, 438, 566, 420)
                text(x+30, 512, label, 28, weight='700')
                for j, value in enumerate(values):
                    text(x+30, 622+j*95, value, 27)
        text(82, 1007, '[KAYNAK + TARİH]    /    [HISTORICAL, SENTETİK veya GERÇEK UI ETİKETİ]', 23)
        text(82, 1045, 'Yerleşim şablonudur. Köşeli parantezler doğrulanmış içerikle değiştirilmelidir.', 22)
        svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080"><title>'+escape(title)+'</title><defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0 0 L8 4 L0 8 Z" fill="'+MINT+'"/></marker></defs>'+''.join(elements)+'</svg>'
        (target / f'{index}_{name}.svg').write_text(svg, encoding='utf-8')
