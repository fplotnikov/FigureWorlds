"""Renders a few free (MIT) Bencho sounds to WAV. Recipes (note lists) are copied from
github.com/cabralorenzo/bencho sounds/sounds.ts, MIT, (c) 2026 Lorenzo Cabra; Plop is rebuilt
from cuelume by Daniel Belyi (MIT). The synthesis follows the Web Audio graph described there:
oscillator (optional exponential glide) -> optional 2-pole lowpass -> exponential envelope."""
import math, struct, sys, wave

SR = 44100
SOUNDS = {
  "landed": [dict(hz=330,to=620,ms=120,gain=0.018,wave="triangle",cut=1400,atk=30),
             dict(hz=784,ms=120,gain=0.04,cut=2600,atk=4,at=70),
             dict(hz=1047,ms=130,gain=0.04,cut=2800,atk=4,at=140),
             dict(hz=1319,ms=520,gain=0.044,cut=3000,atk=5,at=210),
             dict(hz=2638,ms=320,gain=0.007,atk=8,at=215)],
  "plop":   [dict(hz=480,to=300,glide=18,ms=23,gain=0.064,atk=1),
             dict(hz=600,to=900,glide=40,ms=61,gain=0.015,atk=12),
             dict(hz=960,to=600,glide=18,ms=18,gain=0.016,atk=1)],
  "wisp":   [dict(hz=660,to=720,ms=38,gain=0.028)],
  "perk":   [dict(hz=330,ms=360,gain=0.053,cut=560,atk=90)],
  "whisk":  [dict(hz=124,to=65,ms=130,gain=0.067,cut=560,atk=50)],
  "float":  [dict(hz=262,ms=322,gain=0.052,cut=820,atk=16)],
  "glide":  [dict(hz=397,to=276,ms=205,gain=0.065,cut=820,atk=90)],
  "step":   [dict(hz=227,to=114,ms=311,gain=0.051,cut=820,atk=90)],
  "tick":   [dict(hz=196,to=130,ms=150,gain=0.07,cut=900)],
  "latch":  [dict(hz=256,ms=90,gain=0.058,wave="square",cut=2400,atk=10)],
  "hail":   [dict(hz=392,ms=360,gain=0.051,cut=560,atk=90)],
  "drape":  [dict(hz=220,ms=215,gain=0.059,cut=560,atk=8)],
  "drift":  [dict(hz=174,to=155,ms=250,gain=0.034,cut=640,atk=28)],
}

def osc(wave, ph):
    x = ph % 1.0
    if wave == "triangle": return 4*abs(x-0.5)-1
    if wave == "square": return 1.0 if x < 0.5 else -1.0
    return math.sin(2*math.pi*x)

def lowpass(sig, cut):   # RBJ biquad, Q = 1/sqrt(2) like a Web Audio default-ish lowpass
    w = 2*math.pi*cut/SR; a = math.sin(w)/(2*0.7071); c = math.cos(w)
    b0=(1-c)/2; b1=1-c; b2=b0; a0=1+a; a1=-2*c; a2=1-a
    b0/=a0; b1/=a0; b2/=a0; a1/=a0; a2/=a0
    out=[0.0]*len(sig); x1=x2=y1=y2=0.0
    for i,x in enumerate(sig):
        y=b0*x+b1*x1+b2*x2-a1*y1-a2*y2; x2,x1=x1,x; y2,y1=y1,y; out[i]=y
    return out

def render(notes):
    end = max((n.get("at",0)+n["ms"])/1000 for n in notes) + 0.08
    mix = [0.0]*int(end*SR)
    for n in notes:
        t0 = 0.005 + n.get("at",0)/1000; dur = n["ms"]/1000
        tg = n["glide"]/1000 if "glide" in n else dur
        atk = min(n.get("atk",4)/1000, dur*0.6); peak = n.get("gain",0.05)
        frames = int((dur+0.02)*SR); sig=[0.0]*frames; ph=0.0
        for i in range(frames):
            t = i/SR
            f = n["hz"]
            if "to" in n: f = n["hz"]*(n["to"]/n["hz"])**min(1.0, t/tg)
            ph += f/SR
            if t < atk: g = 0.0001*(peak/0.0001)**(t/atk)
            elif t < dur: g = peak*(0.0001/peak)**((t-atk)/(dur-atk))
            else: g = 0.0
            sig[i] = osc(n.get("wave","sine"), ph)*g
        if "cut" in n: sig = lowpass(sig, n["cut"])
        s = int(t0*SR)
        for i,v in enumerate(sig):
            if s+i < len(mix): mix[s+i] += v
    return mix

def write(path, sig, peak_db=-6.0):
    m = max(abs(v) for v in sig) or 1
    k = 10**(peak_db/20)/m
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1,min(1,v*k))*32767)) for v in sig))

if __name__ == "__main__":
    out = sys.argv[1]
    for name, notes in SOUNDS.items():
        write(f"{out}/bencho_{name}.wav", render(notes))
        print(name)
