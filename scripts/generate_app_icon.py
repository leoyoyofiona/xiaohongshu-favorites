#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
MASTER = RESOURCES / "AppIcon-1024.png"


def rounded_rectangle(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def vertical_gradient(size, top, bottom):
    width, height = size
    image = Image.new("RGBA", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(height - 1, 1)
        color = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(4))
        draw.line((0, y, width, y), fill=color)
    return image


def build_master_icon():
    size = 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    rounded_rectangle(shadow_draw, (86, 98, 938, 950), 210, (10, 16, 24, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(42))
    canvas.alpha_composite(shadow)

    base_mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(base_mask)
    rounded_rectangle(mask_draw, (72, 72, 952, 952), 220, 255)

    gradient = vertical_gradient((size, size), (255, 130, 91, 255), (233, 58, 107, 255))
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    base.alpha_composite(gradient)

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((120, 90, 760, 690), fill=(255, 214, 166, 88))
    glow_draw.ellipse((320, 420, 980, 1020), fill=(255, 117, 171, 82))
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    base.alpha_composite(glow)

    pattern = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pattern_draw = ImageDraw.Draw(pattern)
    for offset in range(-200, 1200, 170):
        pattern_draw.line((offset, 0, offset + 360, size), fill=(255, 255, 255, 18), width=10)
    pattern = pattern.filter(ImageFilter.GaussianBlur(3))
    base.alpha_composite(pattern)

    clipped = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    clipped.paste(base, mask=base_mask)
    canvas.alpha_composite(clipped)

    cards = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cards_draw = ImageDraw.Draw(cards)

    rounded_rectangle(cards_draw, (258, 220, 758, 808), 88, (255, 255, 255, 95))
    rounded_rectangle(cards_draw, (300, 186, 806, 782), 88, (255, 255, 255, 150))
    rounded_rectangle(cards_draw, (228, 250, 724, 838), 88, (248, 244, 238, 255))

    cards = cards.filter(ImageFilter.GaussianBlur(0.5))
    canvas.alpha_composite(cards)

    details = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(details)

    rounded_rectangle(d, (286, 318, 662, 404), 34, (255, 111, 76, 255))
    rounded_rectangle(d, (688, 318, 768, 404), 28, (255, 255, 255, 230))
    rounded_rectangle(d, (794, 318, 846, 404), 24, (255, 255, 255, 210))

    rounded_rectangle(d, (300, 452, 652, 510), 22, (42, 49, 61, 235))
    rounded_rectangle(d, (300, 536, 700, 584), 22, (255, 130, 91, 230))
    rounded_rectangle(d, (300, 610, 614, 658), 22, (110, 128, 152, 210))

    for i, color in enumerate([(255, 208, 116, 255), (255, 130, 91, 255), (64, 193, 162, 255), (83, 116, 255, 255)]):
        x = 302 + i * 118
        rounded_rectangle(d, (x, 706, x + 88, 790), 26, color)

    d.polygon([(640, 258), (710, 258), (710, 358), (675, 330), (640, 358)], fill=(255, 250, 244, 245))

    d.ellipse((724, 182, 836, 294), fill=(255, 248, 242, 240))
    d.ellipse((754, 212, 806, 264), outline=(235, 83, 102, 255), width=14)
    d.line((798, 256, 836, 292), fill=(235, 83, 102, 255), width=16)

    canvas.alpha_composite(details)

    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rim_draw = ImageDraw.Draw(rim)
    rounded_rectangle(rim_draw, (72, 72, 952, 952), 220, (255, 255, 255, 22))
    rounded_rectangle(rim_draw, (84, 84, 940, 940), 208, (0, 0, 0, 0))
    canvas.alpha_composite(rim)

    return canvas


def save_iconset(master):
    RESOURCES.mkdir(parents=True, exist_ok=True)
    ICONSET.mkdir(parents=True, exist_ok=True)
    master.save(MASTER)

    mappings = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    for filename, px in mappings.items():
        resized = master.resize((px, px), Image.Resampling.LANCZOS)
        resized.save(ICONSET / filename)


if __name__ == "__main__":
    save_iconset(build_master_icon())
    print(ICONSET)
