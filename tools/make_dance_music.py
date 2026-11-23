"""Figure Worlds: a little dance tune for each place, synthesised here (no samples, no licences).
python3 tools/make_dance_music.py  ->  FigureWorlds.swiftpm/Resources/Sounds/sfx_dance_<place>.m4a

Same rules as Figure Shelf's models/make_sounds.py: gentle, quiet (peak -12 dBFS), soft attacks,
no sharp highs, and exactly as long as the dance (4.0 s), so "Again" repeats it in time.

  village   bouncy plucked tune with a soft oom-pah bass and quiet claps (town square)
  pond      wooden flute over a harp arpeggio, two bird chirps and a water "plip" (forest)
  snow      music-box waltz with sleigh bells (snowy hill)
  workshop  friendly robot arpeggio on a soft square synth, wood-block clanks, beep-boops
  carnival  calliope waltz (oom-pah-pah) with a glockenspiel sparkle (night carnival)
"""
import math, random, struct, wave, os, subprocess
SR = 22050
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "FigureWorlds.swiftpm", "Resources", "Sounds")
os.makedirs(OUT, exist_ok=True)
random.seed(11)
LEN = 4.0


def silence(sec): return [0.0] * int(sec * SR)


def add(buf, snd, at):
    i0 = int(at * SR)
    for i, v in enumerate(snd):
        if 0 <= i0 + i < len(buf): buf[i0 + i] += v


def env(n, a, r):
    out = []
    for i in range(n):
        e = 1.0
        if i < a: e = 0.5 - 0.5 * math.cos(math.pi * i / a)
        if i > n - r: e *= 0.5 - 0.5 * math.cos(math.pi * (n - i) / r)
        out.append(e)
    return out


def tone(f0, f1, sec, vol, harm=(1.0,), decay=None, attack=0.01, release=0.06, vib=0.0):
    n = int(sec * SR); e = env(n, max(1, int(attack * SR)), max(1, int(release * SR))); out = []; ph = 0.0
    for i in range(n):
        t = i / n; f = f0 * (f1 / f0) ** t
        if vib: f *= 1 + vib * math.sin(2 * math.pi * 5.2 * i / SR)
        ph += 2 * math.pi * f / SR
        v = sum(h * math.sin(ph * (k + 1)) for k, h in enumerate(harm))
        d = math.exp(-t * decay) if decay else 1.0
        out.append(vol * v * e[i] * d)
    return out


# ---- instruments
def mallet(f, sec, vol): return tone(f, f, sec, vol, harm=(1.0, 0.0, 0.0, 0.18), decay=6.0)
def bass(f, sec, vol): return tone(f, f, sec, vol, harm=(1.0, 0.3), decay=3.0, attack=0.008)
def flute(f, sec, vol): return tone(f, f, sec, vol, harm=(1.0, 0.12, 0.04), attack=0.06, release=0.12, vib=0.006)
def calliope(f, sec, vol): return tone(f, f, sec, vol, harm=(1.0, 0.5, 0.25, 0.12), decay=1.5)
def square(f, sec, vol): return tone(f, f, sec, vol, harm=(1.0, 0, 1 / 3, 0, 1 / 5, 0, 1 / 7), decay=4.0, attack=0.005)


def pluck(f, sec, vol):
    """Karplus-Strong plucked string, softened."""
    n = int(sec * SR); p = max(2, int(SR / f))
    buf = [random.uniform(-1, 1) for _ in range(p)]
    out = []
    for i in range(n):
        v = buf[i % p]
        nxt = 0.5 * (v + buf[(i + 1) % p]) * 0.996
        buf[i % p] = nxt
        out.append(vol * v)
    e = env(n, int(0.003 * SR), int(0.05 * SR))
    return [o * k for o, k in zip(out, e)]


def bell(f, sec, vol):
    """music-box / celesta: a few inharmonic partials that fade at different speeds"""
    n = int(sec * SR); out = []
    parts = [(1.0, 1.0, 3.0), (2.0, 0.35, 5.0), (2.76, 0.18, 7.0), (5.4, 0.06, 11.0)]
    e = env(n, int(0.004 * SR), int(0.05 * SR))
    for i in range(n):
        t = i / SR
        v = sum(a * math.sin(2 * math.pi * f * m * t) * math.exp(-t * d) for m, a, d in parts)
        out.append(vol * v * e[i])
    return out


def noise(sec, vol, fc, decay):
    n = int(sec * SR); out = []; y = 0.0
    a = 1 - math.exp(-2 * math.pi * fc / SR)
    for i in range(n):
        y += a * (random.uniform(-1, 1) - y)
        out.append(vol * y * math.exp(-i / (decay * SR)))
    return out


def clap(vol): return noise(0.12, vol, 2400, 0.025)
def woodblock(f, vol): return tone(f, f * 0.96, 0.09, vol, harm=(1.0, 0.4), decay=22.0, attack=0.002)


def jingle(vol):
    """one shake of sleigh bells: a few tiny high bells plus a breath of noise"""
    out = noise(0.18, vol * 0.5, 5200, 0.05)
    for k in range(4):
        add(out, tone(2600 + 180 * k, 2600 + 180 * k, 0.12, vol * 0.18, decay=18.0, attack=0.002), 0.012 * k)
    return out


def chirp(vol):   # a small bird: two quick upward whistles
    out = tone(2200, 3100, 0.07, vol, decay=4.0, attack=0.005, release=0.02)
    add(out, tone(2400, 3400, 0.08, vol, decay=4.0, attack=0.005, release=0.02), 0.1)
    return out


def plip(vol): return tone(900, 420, 0.14, vol, harm=(1.0, 0.2), decay=10.0, attack=0.003)
def blip(f0, f1, vol): return tone(f0, f1, 0.11, vol, harm=(1.0, 0, 0.2), decay=6.0, attack=0.004)


def note(name):
    """note name like C4, F#5 -> Hz"""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    semi = names[name[0]] + (1 if "#" in name else 0) + 12 * (int(name[-1]) - 4)
    return 440 * 2 ** (semi / 12)


def save(name, buf):
    # soft fade at both ends so repeats never click
    f = int(0.03 * SR)
    for i in range(f):
        buf[i] *= i / f; buf[-1 - i] *= i / f
    peak = max(1e-9, max(abs(v) for v in buf))
    k = 0.25 / peak
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * k)) * 32767)) for v in buf))
    m4a = os.path.join(OUT, "sfx_%s.m4a" % name)
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", wav, m4a], check=True)
    os.remove(wav)
    print(name, os.path.getsize(m4a), "bytes")


# ---- village: bouncy plucked tune, 120 bpm (beat 0.5 s), oom-pah bass, claps on 2 and 4
d = silence(LEN)
mel = ["E5", "G5", "C6", "G5", "A5", "G5", "E5", "D5", "C5", "E5", "G5", "E5", "F5", "D5", "C5", None]
for i, n_ in enumerate(mel):
    if n_: add(d, pluck(note(n_), 0.45, 0.32), 0.04 + i * 0.25)
for i in range(8):
    add(d, bass(note(["C3", "G3", "F3", "G3"][(i // 2) % 4] if i % 2 == 0 else "C4"), 0.4, 0.3), 0.04 + i * 0.5)
    if i % 2 == 1: add(d, clap(0.16), 0.04 + i * 0.5)
save("dance_village", d)

# ---- pond: wooden flute over a harp arpeggio, birds and a water plip
d = silence(LEN)
flute_line = [("D5", 0.5), ("E5", 0.25), ("G5", 0.25), ("A5", 0.75), ("G5", 0.25),
              ("E5", 0.5), ("D5", 0.5), ("E5", 0.5), ("D5", 0.5)]
t = 0.05
for n_, dur in flute_line:
    add(d, flute(note(n_), dur * 0.95, 0.28), t); t += dur
arp = ["G3", "D4", "G4", "B4", "D4", "G4", "B4", "D5", "C4", "G4", "C5", "E5", "D4", "A4", "D5", "F#5"]
for i, n_ in enumerate(arp):
    add(d, pluck(note(n_), 0.6, 0.16), 0.05 + i * 0.25)
add(d, chirp(0.07), 0.9); add(d, chirp(0.06), 2.85); add(d, plip(0.2), 2.05)
save("dance_pond", d)

# ---- snow: music-box waltz (3/4, beat 0.444 s = 9 beats) with sleigh bells on each beat
d = silence(LEN)
beat = 4.0 / 9
waltz = ["G5", "B5", "D6", "C6", "B5", "A5", "G5", "A5", "B5"]
for i, n_ in enumerate(waltz):
    add(d, bell(note(n_), 0.9, 0.3), 0.03 + i * beat)
    if i % 3 == 0:
        add(d, bell(note(["G3", "D4", "G3"][i // 3]), 1.2, 0.22), 0.03 + i * beat)
    else:
        add(d, bell(note(["B4", "D5"][i % 3 - 1]), 0.5, 0.1), 0.03 + i * beat)
    add(d, jingle(0.22 if i % 3 == 0 else 0.13), 0.03 + i * beat)
save("dance_snow", d)

# ---- workshop: robot arpeggio on a soft square synth, wood-block clanks, beep-boops
d = silence(LEN)
seq = ["C4", "G4", "C5", "G4", "D#4", "A#4", "D#5", "A#4", "F4", "C5", "F5", "C5", "G4", "D5", "G5", "D5"]
for i, n_ in enumerate(seq):
    add(d, square(note(n_), 0.22, 0.2), 0.03 + i * 0.25)
for i in range(8):
    add(d, square(note(["C3", "D#3", "F3", "G3"][i // 2]), 0.4, 0.18), 0.03 + i * 0.5)
    add(d, woodblock(780 if i % 2 == 0 else 620, 0.22), 0.03 + i * 0.5)
add(d, blip(700, 1100, 0.1), 1.0); add(d, blip(1100, 700, 0.1), 1.15)
add(d, blip(600, 1300, 0.1), 3.0); add(d, blip(1300, 900, 0.1), 3.15)
save("dance_workshop", d)

# ---- carnival: calliope waltz (oom-pah-pah), glockenspiel sparkle on the bar starts
d = silence(LEN)
beat = 4.0 / 9
tune = ["C5", "E5", "G5", "A5", "G5", "E5", "F5", "D5", "C5"]
for i, n_ in enumerate(tune):
    add(d, calliope(note(n_), beat * 0.95, 0.3), 0.03 + i * beat)
    add(d, calliope(note("C3") if i % 3 == 0 else note(["E4", "G4"][i % 2]), beat * 0.8,
                    0.24 if i % 3 == 0 else 0.13), 0.03 + i * beat)
    if i % 3 == 0:
        add(d, bell(note(["C6", "E6", "G6"][i // 3]), 0.6, 0.12), 0.03 + i * beat)
save("dance_carnival", d)
