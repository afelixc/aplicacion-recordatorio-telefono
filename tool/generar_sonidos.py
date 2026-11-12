"""Genera los sonidos de las prioridades (media y alta) en res/raw.

Uso: python3 tool/generar_sonidos.py
Escribe los .wav en android/app/src/main/res/raw y la lista con sus
duraciones en lib/features/notifications/priority_sounds.dart.
"""

import os
import wave

import numpy as np

SR = 22050
RAW = 'android/app/src/main/res/raw'
DART = 'lib/features/notifications/priority_sounds.dart'


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, attack=0.005, release=0.03):
    e = np.ones(n)
    a = max(1, int(SR * attack))
    r = max(1, int(SR * release))
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def bell(f, d, decay=4.0):
    x = t(d)
    partials = [(1, 1), (2.0, .5), (2.76, .35), (5.4, .2), (8.9, .1)]
    s = sum(a * np.sin(2 * np.pi * f * k * x) * np.exp(-decay * k ** .5 * x) for k, a in partials)
    return s * env(len(x), .002, .02)


def tone(f, d, kind='sine', f2=None, vib=0.0):
    x = t(d)
    freq = np.full_like(x, f) if f2 is None else np.linspace(f, f2, len(x))
    if vib:
        freq = freq * (1 + .01 * np.sin(2 * np.pi * vib * x))
    ph = 2 * np.pi * np.cumsum(freq) / SR
    if kind == 'sine':
        s = np.sin(ph)
    elif kind == 'square':
        s = np.sign(np.sin(ph)) * .6 + .25 * np.sin(3 * ph)
    elif kind == 'saw':
        s = sum(np.sin(k * ph) / k for k in range(1, 9)) * .6
    elif kind == 'tri':
        s = 2 / np.pi * np.arcsin(np.sin(ph))
    else:
        raise ValueError(kind)
    return s * env(len(x))


def silence(d):
    return np.zeros(int(SR * d))


def seq(*parts):
    return np.concatenate(parts)


def rep(part, times, gap):
    return seq(*[seq(part, silence(gap)) for _ in range(times)])


def marimba(f, d=.3):
    x = t(d)
    s = (np.sin(2 * np.pi * f * x) + .3 * np.sin(2 * np.pi * f * 4 * x)) * np.exp(-9 * x)
    return s * env(len(x), .002, .02)


def chirp(f1, f2, d):
    return tone(f1, d, 'sine', f2) * np.hanning(int(SR * d))


MEDIA = [
    ('m_campanita_doble', 'Campanita doble', seq(bell(988, .45), bell(988, .9))),
    ('m_gotas', 'Gotas', seq(chirp(1300, 1700, .07), silence(.08), chirp(1100, 1500, .07),
                             silence(.08), chirp(1500, 2000, .09), silence(.3))),
    ('m_xilofon', 'Xilofón', seq(marimba(784, .18), marimba(988, .18), marimba(1175, .6))),
    ('m_ding_dong', 'Ding-dong', seq(bell(784, .55, 2.5), bell(622, 1.2, 2.0))),
    ('m_pajarito', 'Pajarito', seq(chirp(2000, 2600, .08), silence(.04), chirp(2200, 2900, .08),
                                   silence(.04), chirp(2400, 2000, .12), silence(.3))),
    ('m_marimba', 'Marimba', seq(marimba(523, .16), marimba(659, .16), marimba(784, .16), marimba(1047, .6))),
]

ALTA = [
    ('a_sirena', 'Sirena', seq(tone(700, .45, 'saw', 950), tone(950, .45, 'saw', 700), tone(700, .45, 'saw', 950))),
    ('a_despertador', 'Despertador', rep(tone(1200, .07, 'square'), 8, .05)),
    ('a_bocina', 'Bocina', rep(seq(tone(330, .3, 'saw') + tone(415, .3, 'saw')), 2, .1)),
    ('a_alarma_digital', 'Alarma digital', seq(rep(tone(2000, .1, 'square'), 4, .08), silence(.25))),
    ('a_melodia', 'Melodía rápida', seq(*[tone(f, .12, 'tri') for f in (659, 784, 988, 1319)], tone(1319, .3, 'tri'))),
    ('a_trompeta', 'Trompeta', seq(tone(523, .15, 'saw', vib=5), silence(.03), tone(523, .15, 'saw', vib=5),
                                   silence(.03), tone(784, .5, 'saw', vib=5))),
    ('a_policia', 'Sirena de policía', seq(tone(600, .6, 'saw', 1300), tone(1300, .6, 'saw', 600))),
    ('a_ambulancia', 'Sirena de ambulancia', rep(seq(tone(960, .4, 'square'), tone(770, .4, 'square')), 2, 0)),
    ('a_incendio', 'Alarma de incendio', rep(tone(880, .07, 'square'), 10, .03)),
    ('a_escuela', 'Campana de escuela', rep(bell(1500, .06, 8), 20, .005)),
    ('a_alerta_roja', 'Alerta roja', rep(tone(400, .35, 'saw', 1600), 2, .05)),
    ('a_barco', 'Bocina de barco', tone(150, 1.2, 'saw') + .6 * tone(152, 1.2, 'saw')),
    ('a_radar', 'Radar', rep(tone(1000, .12), 3, .25)),
    ('a_fanfarria', 'Fanfarria', seq(*[tone(f, .12, 'square') for f in (523, 659, 784)], tone(1047, .35, 'square'),
                                     silence(.05), tone(784, .12, 'square'), tone(1047, .5, 'square'))),
    ('a_gallo', 'Gallo', seq(tone(700, .12, 'saw', 1100), tone(1100, .55, 'saw', 800, vib=7))),
    ('a_pitido', 'Pitido urgente', seq(rep(tone(3000, .05, 'square'), 4, .04), silence(.2), rep(tone(3000, .05, 'square'), 3, .04))),
]


def write(name, data):
    data = data / max(1e-9, np.max(np.abs(data))) * .85
    pcm = (data * 32767).astype('<i2')
    with wave.open(os.path.join(RAW, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return int(round(len(pcm) / SR * 1000))


def main():
    lines = []

    def block(var, items, doc):
        lines.append(f'/// {doc}')
        lines.append(f'const {var} = [')
        for sid, label, data in items:
            ms = write(sid, data)
            lines.append(f"  PrioritySound('{sid}', '{label}', {ms}),")
        lines.append('];')
        lines.append('')

    lines += [
        '// Generado por tool/generar_sonidos.py: no editar a mano.',
        '',
        '/// Un sonido propio de las prioridades (`res/raw/<id>.wav`).',
        'class PrioritySound {',
        '  const PrioritySound(this.id, this.name, this.millis);',
        '',
        '  final String id;',
        '  final String name;',
        '',
        '  /// Lo que dura una vez (para "cuántas veces suena seguido").',
        '  final int millis;',
        '}',
        '',
    ]
    block('mediaSounds', MEDIA, 'Sonidos nuevos para la prioridad media.')
    block('altaSounds', ALTA, 'Musiquitas de la prioridad alta.')
    with open(DART, 'w') as f:
        f.write('\n'.join(lines))
    ids = [s[0] for s in MEDIA + ALTA]
    keep = ','.join(['@drawable/ic_notification'] + [f'@raw/{n}' for n in
                     ['campanita', 'timbre', 'suave', 'alerta'] + ids])
    with open(os.path.join(RAW, 'keep.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<!-- Evita que la compilación de release borre el ícono de la notificación y los sonidos propios.\n'
                '     Generado por tool/generar_sonidos.py. -->\n'
                '<resources xmlns:tools="http://schemas.android.com/tools"\n'
                f'    tools:keep="{keep}" />\n')


if __name__ == '__main__':
    main()
