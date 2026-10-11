from pathlib import Path
import json
import fitz
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
PDF = ROOT / 'output/pdf/STRATUM_Teknik_Referans_20261011.pdf'
RENDER = WORK / 'render'
RENDER.mkdir(exist_ok=True)
doc = fitz.open(PDF)
pages = []
issues = []
for number, page in enumerate(doc, 1):
    pix = page.get_pixmap(matrix=fitz.Matrix(1.6, 1.6), alpha=False)
    path = RENDER / f'page-{number:03}.png'
    pix.save(path)
    texts = page.get_text('dict')['blocks']
    for block in texts:
        if block['type'] != 0:
            continue
        for line in block['lines']:
            for span in line['spans']:
                x0, y0, x1, y1 = span['bbox']
                if x0 < 0 or y0 < 0 or x1 > page.rect.width + 0.5 or y1 > page.rect.height + 0.5:
                    issues.append({'page': number, 'type': 'outside_page', 'text': span['text']})
                if '\ufffd' in span['text']:
                    issues.append({'page': number, 'type': 'replacement_glyph', 'text': span['text']})
    pages.append({'page': number, 'textCharacters': len(page.get_text()), 'images': len(page.get_images()), 'head': page.get_text()[:170]})
font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 17)
for start in range(0, len(doc), 16):
    sheet = Image.new('RGB', (4 * 300, 4 * 450), '#d4dce0')
    draw = ImageDraw.Draw(sheet)
    for offset in range(min(16, len(doc) - start)):
        number = start + offset + 1
        im = Image.open(RENDER / f'page-{number:03}.png')
        im.thumbnail((286, 416))
        x, y = (offset % 4) * 300 + 7, (offset // 4) * 450 + 26
        sheet.paste(im, (x, y))
        draw.text((x, y - 22), f'{number:03}', font=font, fill='#17313f')
    sheet.save(RENDER / f'contact-{start // 16 + 1:02}.png')
report = {'pages': len(doc), 'issues': issues, 'pageDetails': pages, 'bookmarks': len(doc.get_toc()), 'links': sum(len(p.get_links()) for p in doc)}
(WORK / 'layout_check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'pages': len(doc), 'issues': issues, 'bookmarks': report['bookmarks'], 'links': report['links']}, ensure_ascii=False))
