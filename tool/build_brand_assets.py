"""Render the app's geometric vector mark at each iOS asset-catalog size."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
catalog = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
brand = root / 'assets/brand'
brand.mkdir(parents=True, exist_ok=True)
cream, brown = '#F3F0EC', '#765440'
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">',
       f'<rect width="1024" height="1024" fill="{cream}"/>',
       f'<rect x="192" y="246" width="640" height="532" rx="100" fill="{brown}"/>',
       f'<rect x="238" y="339" width="548" height="346" rx="45" fill="{cream}"/>',
       f'<path d="M448 408 L448 616 L620 512 Z" fill="{brown}"/>']
image = Image.new('RGB', (4096, 4096), cream)
draw = ImageDraw.Draw(image)
def box(rect, fill, radius):
    draw.rounded_rectangle(tuple(int(x * 4) for x in rect), radius=int(radius * 4), fill=fill)
box((192, 246, 832, 778), brown, 100)
box((238, 339, 786, 685), cream, 45)
draw.polygon([(448 * 4, 408 * 4), (448 * 4, 616 * 4), (620 * 4, 512 * 4)], fill=brown)
for y in [284, 722]:
    for x in [272, 376, 480, 584, 688]:
        box((x, y, x + 64, y + 18), cream, 7)
        svg.append(f'<rect x="{x}" y="{y}" width="64" height="18" rx="7" fill="{cream}"/>')
svg.append('</svg>')
(brand / 'cinema-mark.svg').write_text('\n'.join(svg) + '\n', encoding='utf-8')
for entry in json.loads((catalog / 'Contents.json').read_text())['images']:
    name = entry.get('filename')
    if not name:
        continue
    pixels = round(float(entry['size'].split('x')[0]) * float(entry['scale'].removesuffix('x')))
    image.resize((pixels, pixels), Image.Resampling.LANCZOS).save(catalog / name)
print('Rendered iOS Cinema mark at all declared sizes (RGB, no alpha).')
