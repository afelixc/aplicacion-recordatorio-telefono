"""Genera el ícono de Recordame: libreta con campanita (opción F de
docs/maqueta-logo.html), con 3 colores como máximo.

Uso: python3 tool/generar_iconos.py
Escribe res/mipmap-*/ic_launcher[_<color>].png (las 8 combinaciones de
Configuración → Colores, mismas que `appIcons` en lib/core/palette.dart) y
los íconos de web/.
"""

import os

from PIL import Image, ImageDraw

RES = 'android/app/src/main/res'
SIZES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}

# (archivo, fondo, libreta). Mismos colores que `appIcons`.
VARIANTS = [
    ('ic_launcher', '#2C3A66', '#E9A21F'),  # Clásico (la opción F tal cual)
    ('ic_launcher_rojo', '#C62828', '#FFFFFF'),
    ('ic_launcher_naranja', '#E8A33D', '#2B3A67'),
    ('ic_launcher_verde', '#2E6B4F', '#F5D76E'),
    ('ic_launcher_violeta', '#5B3F8C', '#F6B7D2'),
    ('ic_launcher_negro', '#1C1C1E', '#E0B84F'),
    ('ic_launcher_blanco', '#FFFFFF', '#2B3A67'),
    ('ic_launcher_celeste', '#3FA7D6', '#FFFFFF'),
]


def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def details_color(bg, book):
    """Espiral y campanita: blancas, salvo que la libreta sea muy clara (ahí
    van del color del fondo, para que se vean). Lo mismo hace
    `AppIcon.details` en palette.dart."""
    return bg if lum(book) > 0.5 else (255, 255, 255)


def cubic(p0, p1, p2, p3, n=24):
    out = []
    for i in range(1, n + 1):
        t = i / n
        u = 1 - t
        out.append((
            u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1],
        ))
    return out


def bell_points():
    # M57 36 c-8 0 -13 6 -13 14 v7 l-4 6 h34 l-4 -6 v-7 c0 -8 -5 -14 -13 -14 z
    pts = [(57, 36)]
    pts += cubic((57, 36), (49, 36), (44, 42), (44, 50))
    pts += [(44, 57), (40, 63), (74, 63), (70, 57), (70, 50)]
    pts += cubic((70, 50), (70, 42), (65, 36), (57, 36))
    return pts


def draw(size, bg, book, rounded=True):
    k = 8  # se dibuja grande y se achica, para que quede suave
    s = size * k
    f = s / 108
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    det = details_color(bg, book)

    def box(x, y, w, h, r, color):
        d.rounded_rectangle([x * f, y * f, (x + w) * f, (y + h) * f], radius=r * f, fill=color)

    if rounded:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=s * 0.22, fill=bg)
    else:
        d.rectangle([0, 0, s, s], fill=bg)
    box(28, 20, 54, 70, 8, book)
    # La espiral, blanca (en el ícono de fondo blanco, del color de la libreta).
    ring = book if lum(bg) > 0.8 else (255, 255, 255)
    for y in (30, 42, 54, 66, 78):
        box(22, y - 3, 14, 6, 3, ring)
    d.polygon([(x * f, y * f) for x, y in bell_points()], fill=det)
    r = 4.5
    d.ellipse([(57 - r) * f, (68 - r) * f, (57 + r) * f, (68 + r) * f], fill=det)
    return im.resize((size, size), Image.LANCZOS)


def main():
    for name, bg, book in VARIANTS:
        for density, px in SIZES.items():
            draw(px, rgb(bg), rgb(book)).save(os.path.join(RES, f'mipmap-{density}', f'{name}.png'))
    bg, book = rgb(VARIANTS[0][1]), rgb(VARIANTS[0][2])
    for px in (192, 512):
        draw(px, bg, book).save(f'web/icons/Icon-{px}.png')
        draw(px, bg, book, rounded=False).save(f'web/icons/Icon-maskable-{px}.png')
    draw(32, bg, book).save('web/favicon.png')


if __name__ == '__main__':
    main()
