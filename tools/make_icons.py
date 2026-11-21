"""生成应用图标（Android mipmap + Windows ico）。"""
from PIL import Image, ImageDraw, ImageFilter
import os

BASE = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_icon(size=BASE):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    top = (98, 156, 255)
    bottom = (24, 66, 210)
    grad = Image.new("RGBA", (size, size))
    gd = ImageDraw.Draw(grad)
    for y in range(size):
        gd.line([(0, y), (size, y)], fill=lerp(top, bottom, y / size) + (255,))

    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    radius = int(size * 0.235)
    md.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # 顶部高光
    gloss = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gld = ImageDraw.Draw(gloss)
    gld.rounded_rectangle([int(size * 0.02), int(size * 0.02), size - int(size * 0.02), int(size * 0.52)],
                          radius=int(size * 0.22), fill=(255, 255, 255, 46))
    gloss = gloss.filter(ImageFilter.GaussianBlur(size * 0.03))
    img.alpha_composite(Image.composite(gloss, Image.new("RGBA", (size, size), (0, 0, 0, 0)), mask))

    d = ImageDraw.Draw(img)
    stroke = int(size * 0.066)
    left, right = int(size * 0.265), int(size * 0.735)
    top_y, bottom_y = int(size * 0.215), int(size * 0.785)
    box = [left, top_y, right, bottom_y]
    d.rounded_rectangle(box, radius=int(size * 0.115), outline=(255, 255, 255, 255), width=stroke)

    for fy in (0.405, 0.595):
        y = int(size * fy)
        d.line([int(size * 0.375), y, int(size * 0.585), y], fill=(255, 255, 255, 235), width=int(size * 0.056))
        dot_r = int(size * 0.03)
        cx = int(size * 0.655)
        d.ellipse([cx - dot_r, y - dot_r, cx + dot_r, y + dot_r], fill=(198, 220, 255, 255))

    return img


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icon = make_icon()
    icon.save(os.path.join(root, "assets", "app_icon.png"))
    android = os.path.join(root, "android", "app", "src", "main", "res")
    for folder, px in [("mipmap-mdpi", 48), ("mipmap-hdpi", 72), ("mipmap-xhdpi", 96),
                       ("mipmap-xxhdpi", 144), ("mipmap-xxxhdpi", 192)]:
        target = os.path.join(android, folder)
        os.makedirs(target, exist_ok=True)
        icon.resize((px, px), Image.LANCZOS).save(os.path.join(target, "ic_launcher.png"))

    ico = os.path.join(root, "windows", "runner", "resources", "app_icon.ico")
    icon.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icons generated")


if __name__ == "__main__":
    main()
