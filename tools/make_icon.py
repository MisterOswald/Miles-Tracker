from PIL import Image, ImageDraw

S = 1024
# Soft SaaS indigo, subtle vertical gradient (#6366E8 -> #4A4DCB)
top, bottom = (0x63, 0x66, 0xE8), (0x4A, 0x4D, 0xCB)
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
for y in range(S):
    t = y / (S - 1)
    d.line(
        [(0, y), (S, y)],
        fill=tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
    )

# Geometric "M" matching the brand mark, drawn as a thick stroked path.
w = 104
pts = [(272, 702), (272, 322), (512, 572), (752, 322), (752, 702)]
d.line(pts, fill="white", width=w, joint="curve")
# Round the four open ends.
for x, y in (pts[0], pts[-1], pts[1], pts[3]):
    r = w // 2
    d.ellipse([x - r, y - r, x + r, y + r], fill="white")

img.save(
    "/home/user/Miles-Tracker/ios/Miles/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    "PNG",
)
print("wrote 1024x1024 icon")

# Web favicon + apple touch icon, downscaled from the same source.
img.resize((512, 512), Image.LANCZOS).save("web/src/app/icon.png", "PNG")
img.resize((180, 180), Image.LANCZOS).save("web/src/app/apple-icon.png", "PNG")
print("wrote web icons")
