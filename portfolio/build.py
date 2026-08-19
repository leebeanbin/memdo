import base64
import io
from pathlib import Path

from PIL import Image

BUILD_DIR = Path(__file__).parent
SRC = BUILD_DIR / "screenshots"
TEMPLATE = BUILD_DIR / "page.html"
OUT = BUILD_DIR / "dist.html"

IMAGES = {
    "{{IMG_TODAY}}": "01-today.png",
    "{{IMG_NEW_EVENT}}": "02-new-event.png",
    "{{IMG_EVENT_DETAIL}}": "03-event-detail.png",
    "{{IMG_CALENDAR}}": "04-calendar.png",
    "{{IMG_SETTINGS}}": "05-settings.png",
    "{{IMG_AGENT}}": "06-agent.png",
}


def to_data_uri(path: Path, width: int = 640, quality: int = 84) -> str:
    im = Image.open(path).convert("RGB")
    if im.width > width:
        h = int(im.height * (width / im.width))
        im = im.resize((width, h), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, format="JPEG", quality=quality, optimize=True)
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    return f"data:image/jpeg;base64,{b64}"


def main() -> None:
    html = TEMPLATE.read_text(encoding="utf-8")
    total = 0
    for placeholder, filename in IMAGES.items():
        uri = to_data_uri(SRC / filename)
        total += len(uri)
        count = html.count(placeholder)
        html = html.replace(placeholder, uri)
        print(f"{filename}: {len(uri)/1024:.0f}KB x{count}")
    OUT.write_text(html, encoding="utf-8")
    print(f"wrote {OUT} ({OUT.stat().st_size/1024:.0f}KB, images {total/1024:.0f}KB)")


if __name__ == "__main__":
    main()
