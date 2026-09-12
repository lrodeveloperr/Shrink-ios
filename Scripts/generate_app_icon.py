#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw

size = 1024
image = Image.new("RGB", (size, size), "#312E81")
pixels = image.load()
for y in range(size):
    blend = y / (size - 1)
    start = (49, 46, 129)
    end = (79, 70, 229)
    color = tuple(round(start[i] * (1 - blend) + end[i] * blend) for i in range(3))
    for x in range(size):
        pixels[x, y] = color

draw = ImageDraw.Draw(image)
white = (255, 255, 255)
soft = (224, 231, 255)

# Barcode: an instantly legible scan cue without placing a logo inside the app UI.
widths = [18, 10, 28, 12, 16, 34, 10, 24, 14, 18, 30, 10, 20, 12, 34, 16, 10]
x = 205
for index, width in enumerate(widths):
    if index % 2 == 0:
        draw.rounded_rectangle((x, 250, x + width, 650), radius=5, fill=white)
    x += width + 12

# A compact downward marker communicates package reduction.
draw.rounded_rectangle((366, 706, 658, 770), radius=32, fill=soft)
draw.polygon([(448, 752), (576, 752), (512, 834)], fill=soft)

destination = Path(__file__).resolve().parents[1] / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
destination.mkdir(parents=True, exist_ok=True)
image.save(destination / "AppIcon.png", optimize=True)

