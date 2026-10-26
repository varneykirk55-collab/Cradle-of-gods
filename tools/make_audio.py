# Procedural audio for Cradle of Gods -- every sound is synthesised here from
# seeded noise and oscillators (no recordings, samples or third-party audio).
#   python3 tools/make_audio.py assets/audio          (needs numpy, scipy, ffmpeg)
# Output layout:
#   ambience/*.ogg  stereo loops (seamless: the tail is crossfaded into the head)
#   music/*.ogg     stereo pieces with gentle fade in / out
#   sfx/*.wav       mono one-shots (positional in game), loops marked *_loop
# See AUDIO_CREDITS.md for the per-file description of how each one is made.
import os, sys, subprocess, tempfile
import numpy as np
from scipy import signal

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/audio"
ONLY = sys.argv[2].split(",") if len(sys.argv) > 2 else None
rng = np.random.default_rng(1026)


# ----------------------------------------------------------------- basics
def secs(d):
    return np.arange(int(d * SR)) / SR


def white(n):
    return rng.standard_normal(n)


def pink(n):
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    s = np.fft.rfft(white(n)) / np.sqrt(f)
    x = np.fft.irfft(s, n)
    return x / (np.std(x) + 1e-12)


def brown(n):
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    s = np.fft.rfft(white(n)) / np.maximum(f, 15.0)
    x = np.fft.irfft(s, n)
    return x / (np.std(x) + 1e-12)


def _sos(kind, f, order):
    if kind == "bp":
        return signal.butter(order, [max(f[0], 10), min(f[1], SR / 2 - 100)], "bandpass", fs=SR, output="sos")
    return signal.butter(order, min(f, SR / 2 - 100), kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return signal.sosfilt(_sos("low", f, order), x)


def hp(x, f, order=2):
    return signal.sosfilt(_sos("high", f, order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bp", (lo, hi), order), x)


def reson(x, f, q):
    """Resonant band-pass (constant peak gain) at f with quality q."""
    b, a = signal.iirpeak(min(f, SR / 2 - 200), q, fs=SR)
    return signal.lfilter(b, a, x)


def tv_filter(x, kind, fc, block=256, order=2):
    """Time-varying Butterworth filter: coefficients updated every `block`
    samples (state carried over), cutoff given per sample in `fc`."""
    y = np.zeros_like(x)
    zi = None
    for i in range(0, len(x), block):
        f = float(np.clip(fc[min(i + block // 2, len(fc) - 1)], 20, SR / 2 - 500))
        sos = signal.butter(order, f, kind, fs=SR, output="sos")
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        y[i:i + block], zi = signal.sosfilt(sos, x[i:i + block], zi=zi)
    return y


def smooth_rand(n, rate_hz, lo=0.0, hi=1.0, octaves=2):
    """Smooth random control signal (band-limited noise) normalised to [lo, hi]."""
    acc = np.zeros(n)
    amp = 1.0
    for o in range(octaves):
        k = max(4, int(n / SR * rate_hz * 2 ** o) + 4)
        pts = rng.standard_normal(k)
        acc += np.interp(np.linspace(0, k - 1, n), np.arange(k), pts) * amp
        amp *= 0.5
    acc = signal.sosfiltfilt(signal.butter(1, rate_hz * 2, "low", fs=SR, output="sos"), acc)
    acc = (acc - acc.min()) / (acc.max() - acc.min() + 1e-12)
    return lo + acc * (hi - lo)


def env(n, a, d, shape=1.0):
    """Attack / exponential-ish decay envelope over n samples."""
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0)
    rel = np.clip((t - a) / max(d, 1e-4), 0, 1)
    return e * (1 - rel) ** shape


def expdecay(n, tau):
    return np.exp(-np.arange(n) / SR / tau)


def osc(freq, dur=None, phase=0.0):
    """Sine with a per-sample frequency array (or constant)."""
    if np.isscalar(freq):
        freq = np.full(int(dur * SR), freq)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR + phase)


def harmonic(freq, amps, dur=None):
    if np.isscalar(freq):
        freq = np.full(int(dur * SR), freq)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    out = np.zeros(len(freq))
    for k, a in enumerate(amps, 1):
        roll = np.clip((SR / 2 - 1500 - freq * k) / 3000.0, 0.0, 1.0)
        out += np.sin(ph * k) * a * roll
    return out


def place(dst, src, at, gain=1.0):
    i = int(at * SR)
    if i >= len(dst):
        return
    n = min(len(src), len(dst) - i)
    dst[i:i + n] += src[:n] * gain


def ir(decay, n_ch=1, damp=5000.0, predelay=0.012, density_lp=None):
    """Synthetic room / outdoor reverb impulse response: decaying noise that
    darkens over time (two layers), with a short pre-delay."""
    n = int((decay + predelay) * SR)
    t = np.arange(n) / SR
    outs = []
    for c in range(n_ch):
        nz = white(n)
        bright = lp(nz, damp) * np.exp(-6.9 * t / (decay * 0.5))
        dark = lp(nz, damp * 0.25) * np.exp(-6.9 * t / decay)
        h = bright * 0.6 + dark
        h[: int(predelay * SR)] = 0
        h /= np.sqrt(np.sum(h * h)) + 1e-12
        outs.append(h)
    return outs


def reverb(x, decay=1.2, wet=0.25, damp=5000.0, predelay=0.012, stereo=False):
    """Mono in -> mono out (or stereo pair when stereo=True)."""
    hs = ir(decay, 2 if stereo else 1, damp, predelay)
    if stereo:
        if x.ndim == 1:
            x = np.stack([x, x])
        outs = []
        for c in range(2):
            w = signal.fftconvolve(x[c], hs[c])[: x.shape[1]]
            outs.append(x[c] * (1 - wet) + w * wet * 2.0)
        return np.stack(outs)
    w = signal.fftconvolve(x, hs[0])[: len(x)]
    return x * (1 - wet) + w * wet * 2.0


def pad_tail(x, s):
    if x.ndim == 1:
        return np.concatenate([x, np.zeros(int(s * SR))])
    return np.concatenate([x, np.zeros((x.shape[0], int(s * SR)))], axis=1)


def fade(x, fin=0.005, fout=0.02):
    n = x.shape[-1]
    e = np.ones(n)
    a, b = int(fin * SR), int(fout * SR)
    if a: e[:a] = np.linspace(0, 1, a) ** 2
    if b: e[-b:] = np.linspace(1, 0, b) ** 2
    return x * e


def loopify(x, xfade):
    """x has length L + xfade: returns L samples whose end flows into the start
    (equal-power crossfade of the tail onto the head)."""
    n = int(xfade * SR)
    L = x.shape[-1] - n
    out = x[..., :L].copy()
    w = np.linspace(0, np.pi / 2, n)
    out[..., :n] = x[..., :n] * np.sin(w) + x[..., L:L + n] * np.cos(w)
    return out


def normalize(x, peak_db=-1.0):
    p = np.max(np.abs(x)) + 1e-12
    return x / p * 10 ** (peak_db / 20)


def rms_db(x):
    return 20 * np.log10(np.sqrt(np.mean(x ** 2)) + 1e-12)


def to_rms(x, target_db, peak_db=-1.0):
    """Scale to a target RMS, limited so the peak never exceeds peak_db."""
    g = 10 ** ((target_db - rms_db(x)) / 20)
    p = np.max(np.abs(x * g))
    lim = 10 ** (peak_db / 20)
    if p > lim:
        g *= lim / p
    return x * g


REPORT = []


def save(rel, x, ogg=False):
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.asarray(x, dtype=np.float64)
    data = x.T if x.ndim == 2 else x
    pk = np.max(np.abs(data))
    assert pk <= 1.0, f"{rel} clips ({pk})"
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    ch = 2 if x.ndim == 2 else 1
    wav = path if not ogg else tempfile.mktemp(suffix=".wav")
    import wave
    with wave.open(wav, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    if ogg:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", path], check=True)
        os.remove(wav)
    REPORT.append((rel, x.shape[-1] / SR, 20 * np.log10(pk + 1e-12), rms_db(data)))


def want(name):
    return ONLY is None or any(name.startswith(o) for o in ONLY)


# ================================================================ AMBIENCE
def wind_layer(n, lo, hi, gust, leaf=0.0, flutter_hz=12.0):
    """One channel of wind: pink noise through a gust-driven low-pass inside a
    band, plus (optionally) leaf rustle -- high noise amplitude-modulated by
    the gusts and a fast irregular flutter, with sparse leaf 'ticks'."""
    body = bp(pink(n), lo * 0.5, hi * 2.0)
    body = tv_filter(body, "low", lo + (hi - lo) * gust ** 1.5)
    body *= 0.12 + 0.88 * gust ** 1.6
    out = body
    if leaf > 0:
        flutter = np.abs(lp(white(n), flutter_hz)) * 3.0
        flutter = np.clip(flutter, 0, 1.5)
        rustle = lp(bp(white(n), 1500, 9000), 6500) * flutter * gust ** 3.0
        # sparse leaf ticks (tiny decaying clicks) -- denser in gusts
        ticks = np.zeros(n)
        dens = 10 + 300 * gust ** 3
        prob = dens / SR
        idx = np.nonzero(rng.random(n) < prob)[0]
        ticks[idx] = rng.standard_normal(len(idx))
        k = expdecay(int(0.004 * SR), 0.0012)
        ticks = bp(np.convolve(ticks, k)[:n], 2500, 8000)
        out = out + rustle * leaf * 0.45 + ticks * leaf * 0.5
    return out


def amb_forest(dur=48.0, xf=4.0):
    n = int((dur + xf) * SR)
    g = smooth_rand(n, 0.1, 0.05, 1.0, 3)
    chans = []
    for c in range(2):
        gc = np.clip(g * 0.85 + smooth_rand(n, 0.15, 0.0, 0.15), 0, 1)
        chans.append(wind_layer(n, 180, 900, gc, leaf=1.0, flutter_hz=14 + c * 3))
    x = loopify(np.stack(chans), xf)
    return to_rms(x, -21.0)


def amb_meadow(dur=48.0, xf=4.0):
    n = int((dur + xf) * SR)
    g = smooth_rand(n, 0.08, 0.05, 0.85, 3)
    chans = []
    for c in range(2):
        gc = np.clip(g + smooth_rand(n, 0.15, 0.0, 0.15), 0, 1)
        w = wind_layer(n, 150, 600, gc, leaf=0.0)
        # dry grass: soft, airy swish (no leaf ticks), slower flutter
        fl = np.clip(np.abs(lp(white(n), 5.0)) * 3.0, 0, 1.4)
        grass = bp(white(n), 2500, 11000) * fl * gc ** 2 * 0.18
        chans.append(w + grass)
    x = loopify(np.stack(chans), xf)
    return to_rms(x, -24.0)


def amb_coast(dur=56.0, xf=5.0):
    n = int((dur + xf) * SR)
    L = np.zeros(n)
    R = np.zeros(n)
    # distant surf bed
    for ch in (L, R):
        ch += lp(brown(n), 260) * 0.35 * smooth_rand(n, 0.05, 0.6, 1.0)
        ch += bp(pink(n), 300, 1500) * 0.05
        # the constant far-off wash of the surf along the whole shore
        ch += bp(pink(n), 500, 4500) * 0.06 * smooth_rand(n, 0.15, 0.5, 1.0)
    t = 0.0
    while t < dur + xf - 3:
        wd = rng.uniform(6.0, 9.5)
        m = int(wd * SR)
        tt = np.arange(m) / SR
        build = rng.uniform(1.4, 2.4)
        crash = build
        # swell: rising low noise
        sw = np.clip(tt / build, 0, 1) ** 2 * (tt < crash + 0.3)
        swell = tv_filter(pink(m), "low", 200 + 700 * np.clip(tt / build, 0, 1)) * sw * 0.5
        # break + wash: broadband burst whose low-pass sweeps down as it spreads
        after = np.clip(tt - crash, 0, None)
        rise = rng.uniform(0.45, 0.9)
        e_crash = (tt >= crash) * np.minimum(after / rise, 1) ** 1.5 * np.exp(-after / rng.uniform(1.6, 2.6))
        cut = 500 + 2200 * np.minimum(after / rise, 1) * np.exp(-after / 1.6)
        wash = tv_filter(white(m), "low", cut) * e_crash
        # foam fizz: sparse bubbles/crackle that linger as the wash recedes
        fz = np.zeros(m)
        pr = (tt >= crash) * 900 * np.exp(-after / 2.5) / SR
        idx = np.nonzero(rng.random(m) < pr)[0]
        fz[idx] = rng.standard_normal(len(idx))
        fz = hp(np.convolve(fz, expdecay(int(0.003 * SR), 0.0008))[:m], 3000) * 0.9
        wave = swell + wash * 0.9 + fz * 0.35
        wave *= rng.uniform(0.35, 1.0)
        pan = rng.uniform(0.2, 0.8)
        place(L, wave, t, np.sqrt(1 - pan))
        place(R, wave, t, np.sqrt(pan))
        t += rng.uniform(2.8, 8.0)
    x = loopify(np.stack([L, R]), xf)
    return to_rms(x, -20.0)


def amb_high_wind(dur=40.0, xf=4.0):
    n = int((dur + xf) * SR)
    g = smooth_rand(n, 0.07, 0.2, 1.0, 3)
    chans = []
    for c in range(2):
        base = wind_layer(n, 120, 700, g, leaf=0.0) * 0.8
        # two soft, slowly drifting resonances: hollow whistling over ridges
        w1 = reson(pink(n), 520 + 60 * c, 18) * g ** 2
        w1 = tv_filter(w1, "low", 500 + 600 * g)
        chans.append(base + w1 * 0.35)
    x = loopify(np.stack(chans), xf)
    return to_rms(x, -23.0)


def amb_rain(dur=20.0, xf=2.0):
    n = int((dur + xf) * SR)
    chans = []
    for c in range(2):
        hiss = bp(pink(n), 700, 7000) * 0.07
        drops = np.zeros(n)
        idx = np.nonzero(rng.random(n) < 2200 / SR)[0]
        drops[idx] = rng.standard_normal(len(idx)) * rng.random(len(idx)) ** 3
        small = lp(bp(np.convolve(drops, expdecay(int(0.008 * SR), 0.002))[:n], 1500, 9000), 6000)
        big = np.zeros(n)
        idx = np.nonzero(rng.random(n) < 45 / SR)[0]
        big[idx] = rng.standard_normal(len(idx))
        plop = np.zeros(n)
        for f0 in (900, 1300, 1800):
            plop += reson(big, f0 * rng.uniform(0.9, 1.1), 6)
        x = hiss + small * 1.0 + plop * 0.35
        x *= 0.85 + 0.15 * smooth_rand(n, 0.2)
        x = np.tanh(x / (np.std(x) * 3.5))      # soft-limit the loudest drops
        chans.append(x)
    x = loopify(np.stack(chans), xf)
    return to_rms(x, -21.0)


def amb_fire(dur=12.0, xf=1.5):
    n = int((dur + xf) * SR)
    flick = smooth_rand(n, 3.0, 0.5, 1.0, 2)
    roar = lp(brown(n), 380) * flick * 0.6 + bp(pink(n), 300, 1400) * flick * 0.12
    cr = np.zeros(n)
    idx = np.nonzero(rng.random(n) < 70 / SR)[0]
    cr[idx] = rng.standard_normal(len(idx)) * (rng.random(len(idx)) ** 3 * 3 + 0.2)
    crackle = bp(np.convolve(cr, expdecay(int(0.01 * SR), 0.002))[:n], 1000, 7000)
    pops = np.zeros(n)
    idx = np.nonzero(rng.random(n) < 2.5 / SR)[0]
    pops[idx] = 1.0
    pop = reson(pops, 1400, 10) + reson(pops, 2900, 14) * 0.5
    x = roar + crackle * 0.7 + pop * 0.6
    x = loopify(x, xf)
    return to_rms(x, -20.0)


def babble_voice(n, f0_base):
    """One distant voice: glottal-ish harmonic source with a prosodic pitch
    contour, syllable envelope with pauses, and moving vowel formants."""
    t = np.arange(n) / SR
    f0 = f0_base * (1 + 0.12 * (smooth_rand(n, 1.5) - 0.5)) * (1 + 0.05 * np.sin(t * 0.7))
    src = harmonic(f0, [1 / k ** 1.2 for k in range(1, 26)])
    src += white(n) * 0.04
    # syllables (3.5-6 Hz) grouped in phrases with pauses
    syl = np.zeros(n)
    pos = rng.uniform(0, 1.0)
    while pos < n / SR:
        phrase = rng.uniform(1.0, 3.2)
        end = pos + phrase
        while pos < end and pos < n / SR:
            d = rng.uniform(0.12, 0.28)
            i0, i1 = int(pos * SR), min(int((pos + d) * SR), n)
            syl[i0:i1] = np.sin(np.linspace(0, np.pi, i1 - i0)) ** 0.7 * rng.uniform(0.5, 1.0)
            pos += d + rng.uniform(0.0, 0.05)
        pos += rng.uniform(0.6, 2.5)
    syl = lp(syl, 25)
    # vowel formants drift per syllable-ish
    f1 = smooth_rand(n, 5.0, 300, 750)
    f2 = smooth_rand(n, 4.0, 900, 2100)
    v = tv_filter(src, "low", f2 * 1.3)
    out = reson(v, 500, 2.0) * 0.6 + tv_filter(hp(v, 250), "low", f1 * 1.8) * 0.6
    return out * syl


def amb_village(dur=30.0, xf=3.0):
    n = int((dur + xf) * SR)
    chans = [np.zeros(n), np.zeros(n)]
    for i in range(9):
        f0 = rng.choice([105, 120, 135, 190, 210, 230, 160])
        v = babble_voice(n, f0 * rng.uniform(0.93, 1.07)) * rng.uniform(0.4, 1.0)
        pan = rng.uniform(0.2, 0.8)
        chans[0] += v * np.sqrt(1 - pan)
        chans[1] += v * np.sqrt(pan)
    x = np.stack(chans)
    # distance: strong low-pass, soft room/outdoor reflections
    x = np.stack([lp(c, 1500, 2) for c in x])
    x = reverb(x, 1.1, 0.35, 3000, 0.02, stereo=True)
    # a little outdoor air underneath so it never sits on dead silence
    x += np.stack([lp(pink(n), 400) * 0.03, lp(pink(n), 400) * 0.03])
    x = loopify(x, xf)
    return to_rms(x, -26.0)


# ================================================================ WILDLIFE
def bird_note(f_start, f_end, dur, curve=1.0, vib=0.0, vib_rate=30.0, h2=0.06):
    n = int(dur * SR)
    t = np.linspace(0, 1, n)
    f = f_start + (f_end - f_start) * t ** curve
    if vib:
        f = f + vib * np.sin(2 * np.pi * vib_rate * np.arange(n) / SR)
    x = harmonic(f, [1.0, h2])
    a = min(0.012, dur * 0.3)
    e = np.minimum(np.arange(n) / SR / a, 1.0) * np.clip((1 - t) / 0.35, 0, 1) ** 1.5
    return x * e


def bird_finish(x, dist_lp=7500):
    x = lp(hp(x, 1200), dist_lp)
    x = pad_tail(x, 0.6)
    x = reverb(x, 0.55, 0.12, 6000, 0.015)
    return fade(normalize(x, -3.0), 0.002, 0.12)


def bird_trill_flourish():
    out = np.zeros(int(2.4 * SR))
    t = 0.05
    k = rng.integers(7, 11)
    for i in range(k):
        f = 5200 - i * rng.uniform(150, 220)
        place(out, bird_note(f, f - 900, 0.055, 0.7), t, 0.8 + 0.2 * rng.random())
        t += rng.uniform(0.07, 0.085)
    t += 0.05
    place(out, bird_note(2600, 4800, 0.09, 0.6), t)
    place(out, bird_note(4800, 2400, 0.16, 1.4), t + 0.09)
    return bird_finish(out[: int((t + 0.4) * SR)])


def bird_two_tone():
    out = np.zeros(int(1.6 * SR))
    f = rng.uniform(3800, 4500)
    place(out, bird_note(f, f * 1.02, 0.26, 1.0, vib=25, vib_rate=8), 0.03)
    place(out, bird_note(f * 0.78, f * 0.74, 0.32, 1.0, vib=20, vib_rate=7), 0.36, 0.8)
    if rng.random() < 0.5:
        place(out, bird_note(f * 0.78, f * 0.74, 0.3, 1.0, vib=20, vib_rate=7), 0.75, 0.6)
    return bird_finish(out)


def bird_warble():
    out = np.zeros(int(2.4 * SR))
    t = 0.03
    centre = rng.uniform(3300, 4600)
    for i in range(rng.integers(7, 12)):
        d = rng.uniform(0.05, 0.13)
        f0 = centre * rng.uniform(0.75, 1.3)
        peak = f0 * rng.uniform(1.05, 1.3)
        n = int(d * SR)
        u = np.linspace(0, 1, n)
        f = f0 + (peak - f0) * np.sin(np.pi * u) ** 1.2 - f0 * rng.uniform(0, 0.15) * u
        f = f + rng.uniform(0, 90) * np.sin(2 * np.pi * rng.uniform(25, 40) * np.arange(n) / SR)
        x = harmonic(f, [1.0, 0.05]) * np.minimum(u / 0.12, 1) * np.clip((1 - u) / 0.3, 0, 1) ** 1.5
        place(out, x, t, rng.uniform(0.5, 1.0))
        t += d + rng.uniform(0.015, 0.06)
    return bird_finish(out[: int((t + 0.3) * SR)])


def bird_trill():
    out = np.zeros(int(2.0 * SR))
    f = rng.uniform(3600, 4600)
    k = rng.integers(14, 24)
    t = 0.03
    for i in range(k):
        place(out, bird_note(f * 1.08, f * 0.92, 0.035, 1.0), t, 0.5 + 0.5 * np.sin(np.pi * i / k))
        t += 0.055
    return bird_finish(out[: int((t + 0.3) * SR)])


def bird_chips():
    out = np.zeros(int(1.2 * SR))
    t = 0.02
    for i in range(rng.integers(2, 5)):
        f = rng.uniform(4800, 6200)
        place(out, bird_note(f * 1.15, f * 0.85, 0.022, 0.8, h2=0.12), t, rng.uniform(0.6, 1.0))
        t += rng.uniform(0.12, 0.3)
    return bird_finish(out[: int((t + 0.2) * SR)])


def dove_coo():
    out = np.zeros(int(2.6 * SR))
    t = 0.05
    for d, f, g in [(0.35, 520, 0.6), (0.6, 560, 1.0), (0.4, 500, 0.7)]:
        n = int(d * SR)
        tt = np.linspace(0, 1, n)
        fr = f * (1 + 0.06 * np.sin(np.pi * tt)) * (1 - 0.04 * tt)
        x = harmonic(fr, [1.0, 0.25, 0.08]) * np.sin(np.pi * tt) ** 1.5
        x += lp(white(n), 900) * 0.04 * np.sin(np.pi * tt)
        place(out, x, t, g)
        t += d + 0.08
    x = lp(out, 2500)
    x = reverb(pad_tail(x, 0.5), 1.0, 0.2, 4000)
    return fade(normalize(x, -3.0), 0.005, 0.2)


def wolf_howl(kind=0):
    dur = [3.6, 4.2, 3.0][kind]
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    if kind == 0:   # rise, hold, fall
        f0 = 330 + 210 * np.clip(u / 0.18, 0, 1) ** 0.6 - 60 * np.clip((u - 0.25) / 0.6, 0, 1) - 120 * np.clip((u - 0.8) / 0.2, 0, 1) ** 2
    elif kind == 1:  # higher, with a break and second rise
        f0 = 380 + 230 * np.clip(u / 0.15, 0, 1) - 50 * np.clip((u - 0.3) / 0.25, 0, 1) + 70 * np.clip((u - 0.55) / 0.1, 0, 1) - 180 * np.clip((u - 0.8) / 0.2, 0, 1) ** 2
    else:            # shorter, lower
        f0 = 300 + 170 * np.clip(u / 0.25, 0, 1) ** 0.7 - 110 * np.clip((u - 0.7) / 0.3, 0, 1) ** 2
    f0 = f0 * (1 + 0.012 * np.sin(2 * np.pi * 5.2 * t) * np.clip((u - 0.2) * 3, 0, 1))
    src = harmonic(f0, [1.0, 0.3, 0.12, 0.05, 0.02])
    breath = bp(white(n), 300, 3000) * 0.035 * (0.6 + 0.4 * np.exp(-t / 0.4))
    x = src + breath
    # vowel: 'oo' at the start opening toward 'ow'
    x = tv_filter(x, "low", 700 + 900 * np.clip(u / 0.3, 0, 1) - 300 * np.clip((u - 0.75) / 0.25, 0, 1), block=64)
    e = np.clip(t / 0.3, 0, 1) ** 1.5 * np.clip((dur - t) / 0.7, 0, 1) ** 1.2
    x *= e
    x = pad_tail(x, 2.0)
    x = lp(x, 3000)
    x = reverb(x, 2.2, 0.22, 3500, 0.07)
    return fade(normalize(x, -3.0), 0.01, 0.4)


def rustle(steps=None, soft=1.0):
    steps = steps or rng.integers(3, 7)
    out = np.zeros(int(1.8 * SR))
    t = 0.02
    for i in range(steps):
        d = rng.uniform(0.04, 0.1)
        n = int(d * SR)
        x = bp(white(n), 700, 6000) * env(n, 0.006, d - 0.006, 1.5)
        x += lp(white(n), 300) * env(n, 0.002, 0.03, 2) * 0.6     # soft footfall
        place(out, x, t, rng.uniform(0.5, 1.0))
        t += rng.uniform(0.12, 0.3)
    x = out[: int((t + 0.2) * SR)]
    x = lp(x, 6000 * soft)
    return fade(normalize(x, -6.0), 0.002, 0.05)


def deer_huff():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    x = bp(white(n), 350, 2600) * np.exp(-t / 0.09) * np.minimum(t / 0.008, 1)
    x += reson(white(n), 700, 4) * np.exp(-t / 0.06) * 0.4
    x = reverb(pad_tail(x, 0.6), 0.8, 0.2, 4000)
    return fade(normalize(x, -4.0), 0.001, 0.1)


def rabbit_thump():
    out = np.zeros(int(0.9 * SR))
    for i, at in enumerate([0.02, 0.2, 0.36][: rng.integers(2, 4)]):
        n = int(0.12 * SR)
        x = osc(np.linspace(110, 60, n)) * expdecay(n, 0.025)
        x += lp(white(n), 900) * expdecay(n, 0.012) * 0.4
        place(out, x, at, 1.0 - 0.15 * i)
    return fade(normalize(out, -6.0), 0.001, 0.05)


# ================================================================ SETTLEMENT
def wood_hit(modes, decays, noise_amt=0.6, low=None):
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for f, d in zip(modes, decays):
        x += np.sin(2 * np.pi * f * rng.uniform(0.97, 1.03) * t + rng.uniform(0, 6)) * np.exp(-t / d) * rng.uniform(0.6, 1.0)
    clk = hp(white(n), 1500) * np.exp(-t / 0.004) * noise_amt
    x += clk
    if low:
        x += np.sin(2 * np.pi * low * t) * np.exp(-t / 0.05) * 0.5
    x *= np.minimum(t / 0.0008, 1)
    return x


def axe_chop():
    x = wood_hit([170, 410, 780, 1250, 2100], [0.06, 0.04, 0.03, 0.02, 0.012], 0.8, low=95)
    x = lp(x, 6000)
    x = reverb(pad_tail(x, 0.5), 0.9, 0.22, 4500, 0.03)
    return fade(normalize(x, -2.0), 0.0005, 0.1)


def hammer():
    out = np.zeros(int(1.2 * SR))
    hits = rng.integers(1, 3)
    for i in range(hits):
        x = wood_hit([620, 1150, 1900, 2700], [0.035, 0.025, 0.016, 0.01], 0.5, low=150)
        place(out, x, 0.01 + i * rng.uniform(0.28, 0.4), 1.0 - 0.2 * i)
    x = lp(out, 7000)
    x = reverb(x, 0.8, 0.2, 4500, 0.03)
    return fade(normalize(x, -3.0), 0.0005, 0.1)


def build_complete():
    # a final settling knock followed by a soft creak of timber
    out = np.zeros(int(1.6 * SR))
    place(out, wood_hit([140, 330, 610], [0.09, 0.05, 0.03], 0.4, low=80), 0.0)
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    f = 180 + 60 * np.sin(2 * np.pi * 0.8 * t) + 20 * smooth_rand(n, 8)
    pulses = (np.sin(2 * np.pi * np.cumsum(f) / SR) > 0.97).astype(float)
    creak = reson(pulses, 900, 8) + reson(pulses, 1700, 10) * 0.5
    place(out, creak * np.sin(np.pi * t / t[-1]) * 0.4, 0.25)
    x = reverb(lp(out, 5000), 1.0, 0.25, 4000)
    return fade(normalize(x, -3.0), 0.0005, 0.1)


def collapse():
    out = np.zeros(int(2.6 * SR))
    for i in range(9):
        place(out, wood_hit([120 * rng.uniform(0.8, 1.4), 300 * rng.uniform(0.8, 1.3), 650], [0.08, 0.05, 0.03], 0.6, 70), rng.uniform(0, 0.9), rng.uniform(0.4, 1.0))
    n = len(out)
    t = np.arange(n) / SR
    out += lp(brown(n), 300) * np.exp(-t / 0.7) * np.minimum(t / 0.05, 1) * 0.5
    x = reverb(lp(out, 5000), 1.4, 0.3, 3500)
    return fade(normalize(x, -2.0), 0.001, 0.3)


# ================================================================ GOD HAND
def hand_grab():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    x = osc(np.linspace(140, 70, n)) * env(n, 0.012, 0.25, 2) * 0.8
    x += bp(white(n), 300, 2500) * env(n, 0.004, 0.08, 2) * 0.35     # grip / cloth
    sh = np.zeros(n)
    for f in (1760, 2640, 3520):
        sh += np.sin(2 * np.pi * f * rng.uniform(0.99, 1.01) * t) * np.exp(-t / 0.18)
    x += sh * 0.03 * np.minimum(t / 0.02, 1)                          # faint divine shimmer
    x = reverb(pad_tail(x, 0.4), 0.7, 0.15, 5000)
    return fade(normalize(x, -4.0), 0.001, 0.1)


def hand_place():
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    x = osc(np.linspace(100, 55, n)) * env(n, 0.006, 0.22, 2) * 0.9
    x += lp(white(n), 1800) * env(n, 0.003, 0.12, 2) * 0.35          # grass / soil settling
    x = reverb(pad_tail(x, 0.3), 0.6, 0.12, 4000)
    return fade(normalize(x, -5.0), 0.001, 0.08)


def hand_throw():
    """Air swish: a resonant band sweeping up then down through the noise
    (like a fast arm or cloth moving past), fast rise and a softer tail."""
    d = rng.uniform(0.42, 0.55)
    n = int(d * SR)
    u = np.linspace(0, 1, n)
    peak = rng.uniform(0.3, 0.42)
    centre = 300 + 1400 * np.exp(-((u - peak) / 0.22) ** 2)
    src = pink(n)
    x = np.zeros(n)
    blk = 128
    zi = None
    for i in range(0, n, blk):
        fc = float(centre[min(i + blk // 2, n - 1)])
        sos = signal.butter(2, [fc * 0.7, fc * 1.45], "bandpass", fs=SR, output="sos")
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        x[i:i + blk], zi = signal.sosfilt(sos, src[i:i + blk], zi=zi)
    e = np.where(u < peak, (u / peak) ** 2.2, np.exp(-(u - peak) / 0.18))
    x *= e
    x += lp(white(n), 250) * e * 0.15
    return fade(normalize(x, -4.0), 0.002, 0.04)


def impact(heavy=False):
    n = int((1.3 if heavy else 0.7) * SR)
    t = np.arange(n) / SR
    x = osc(70 * np.exp(-t * 3) + 38) * np.exp(-t / (0.22 if heavy else 0.1)) * 1.0
    x += tv_filter(white(n), "low", 300 + 2500 * np.exp(-t / 0.05)) * np.exp(-t / (0.25 if heavy else 0.1)) * 0.8
    deb = np.zeros(n)
    idx = np.nonzero(rng.random(n) < (220 if heavy else 90) / SR * np.exp(-t / 0.25))[0]
    deb[idx] = rng.standard_normal(len(idx))
    deb = bp(np.convolve(deb, expdecay(int(0.01 * SR), 0.003))[:n], 600, 4000)
    x += deb * 0.5
    x *= np.minimum(t / 0.001, 1)
    x = reverb(pad_tail(x, 0.6), 1.0, 0.18, 3500)
    return fade(normalize(x, -1.5 if heavy else -3.0), 0.0005, 0.15)


def splash():
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    x = tv_filter(white(n), "low", 500 + 5000 * np.exp(-t / 0.08)) * np.exp(-t / 0.18) * np.minimum(t / 0.004, 1)
    bub = np.zeros(n)
    for i in range(40):
        at = rng.uniform(0.05, 0.9)
        d = rng.uniform(0.015, 0.05)
        f = rng.uniform(500, 1600)
        m = int(d * SR)
        b = osc(np.linspace(f, f * 1.6, m)) * np.sin(np.pi * np.linspace(0, 1, m)) * np.exp(-at * 2)
        place(bub, b, at, rng.uniform(0.1, 0.35))
    x += bub
    x = reverb(x, 0.8, 0.15, 5000)
    return fade(normalize(x, -3.0), 0.0005, 0.1)


# ================================================================ POWERS
def earth_rumble_loop(dur=4.0, xf=0.8):
    n = int((dur + xf) * SR)
    t = np.arange(n) / SR
    x = lp(brown(n), 170) * (0.75 + 0.25 * smooth_rand(n, 2.0))
    x += np.sin(2 * np.pi * 42 * t + 2 * np.sin(2 * np.pi * 0.7 * t)) * 0.25
    grit = np.zeros(n)
    idx = np.nonzero(rng.random(n) < 350 / SR)[0]
    grit[idx] = rng.standard_normal(len(idx))
    grit = bp(np.convolve(grit, expdecay(int(0.01 * SR), 0.003))[:n], 400, 3500)
    x += grit * 0.35 * smooth_rand(n, 3.0, 0.4, 1.0)
    x = loopify(x, xf)
    return to_rms(x, -14.0)


def drain_loop(dur=4.0, xf=0.8):
    n = int((dur + xf) * SR)
    x = lp(brown(n), 220) * 0.5
    x += bp(pink(n), 200, 1200) * 0.15 * smooth_rand(n, 1.5, 0.5, 1.0)
    for i in range(int(dur * 45)):
        at = rng.uniform(0, dur + xf - 0.1)
        d = rng.uniform(0.02, 0.07)
        f = rng.uniform(250, 900)
        m = int(d * SR)
        b = osc(np.linspace(f, f * rng.uniform(1.4, 2.2), m)) * np.sin(np.pi * np.linspace(0, 1, m)) ** 2
        place(x, b, at, rng.uniform(0.05, 0.25))
    x = loopify(x, xf)
    return to_rms(x, -15.0)


def tile_thunk():
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    x = osc(85 * np.exp(-t * 4) + 45) * np.exp(-t / 0.14)
    gr = np.zeros(n)
    idx = np.nonzero(rng.random(n) < 500 / SR * np.exp(-t / 0.2))[0]
    gr[idx] = rng.standard_normal(len(idx))
    x += bp(np.convolve(gr, expdecay(int(0.006 * SR), 0.002))[:n], 800, 5000) * 0.45
    x = reverb(x, 0.9, 0.2, 4000)
    return fade(normalize(x, -3.0), 0.0005, 0.1)


def chime_chord(freqs, dur, attack=0.35, bright=1.0, rev=2.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for i, f in enumerate(freqs):
        for det in (-0.004, 0.0, 0.005):
            ph = rng.uniform(0, 6.28)
            tone = np.sin(2 * np.pi * f * (1 + det) * t + ph) + 0.25 * bright * np.sin(4 * np.pi * f * (1 + det) * t + ph)
            x += tone * np.exp(-t / (dur * rng.uniform(0.35, 0.5)))
    x *= np.minimum(t / attack, 1) ** 2
    sh = np.zeros(n)
    for k in range(10):
        f = rng.uniform(2200, 5200)
        sh += np.sin(2 * np.pi * f * t) * np.exp(-((t - rng.uniform(0.1, dur * 0.6)) / 0.12) ** 2)
    x += sh * 0.08 * bright
    x = reverb(pad_tail(x, 1.0), rev, 0.4, 6000, 0.03)
    return fade(normalize(x, -3.0), 0.002, 0.4)


def ks_pluck(f, dur, bright=0.5, decay=0.996, sr=SR):
    """Karplus-Strong plucked string with an all-pass fractional delay, so
    every note is in tune. bright 0..1 shapes the excitation."""
    p = sr / f - 0.5
    N = int(np.floor(p - 0.1))
    d = p - N
    c = (1 - d) / (1 + d)
    n = int(dur * sr)
    exc = white(N + 2)
    exc = lp(exc, 800 + 7000 * bright)
    x = np.zeros(n)
    x[: N + 2] = exc
    g = decay
    a = np.zeros(N + 3)
    a[0] = 1.0
    a[1] = c
    a[N] += -g * c / 2
    a[N + 1] += -g * (1 + c) / 2
    a[N + 2] += -g / 2
    y = signal.lfilter([1.0, c], a, x)
    return y * np.minimum(np.arange(n) / sr / 0.002, 1)


def forest_grow():
    out = np.zeros(int(2.4 * SR))
    scale = [392, 440, 523.25, 587.33, 659.25, 784, 880]
    t = 0.0
    for i, k in enumerate([0, 2, 3, 4, 6]):
        place(out, ks_pluck(scale[k], 1.4, 0.35, 0.995) * (0.7 + 0.06 * i), t)
        t += 0.075
    n = len(out)
    tt = np.arange(n) / SR
    rust = bp(white(n), 1500, 7000) * np.sin(np.pi * np.clip(tt / 1.2, 0, 1)) ** 2 * 0.12
    out += rust * np.clip(np.abs(lp(white(n), 14)) * 3, 0, 1.4)
    x = reverb(out, 1.6, 0.3, 6000)
    return fade(normalize(x, -3.0), 0.002, 0.3)


def rain_gather():
    n = int(2.2 * SR)
    u = np.linspace(0, 1, n)
    x = tv_filter(pink(n), "low", 250 + 1400 * u ** 1.5) * np.sin(np.pi * u) ** 1.2
    x += lp(brown(n), 120) * np.sin(np.pi * u) * 0.5
    x = reverb(x, 1.5, 0.25, 4000)
    return fade(normalize(x, -4.0), 0.01, 0.3)


def fm_bell(f, dur, ratio=1.4, index=2.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    e = np.exp(-t / (dur * 0.35))
    mod = np.sin(2 * np.pi * f * ratio * t) * index * e
    return np.sin(2 * np.pi * f * t + mod) * e * np.minimum(t / 0.003, 1)


def plenty():
    out = np.zeros(int(2.6 * SR))
    place(out, fm_bell(659.25, 2.0, 2.0, 1.2), 0.0, 0.7)
    place(out, fm_bell(987.77, 1.8, 2.0, 1.0), 0.16, 0.55)
    place(out, fm_bell(1318.5, 1.5, 2.0, 0.8), 0.32, 0.4)
    n = len(out)
    t = np.arange(n) / SR
    gr = np.zeros(n)
    idx = np.nonzero(rng.random(n) < 900 / SR * np.clip(1 - (t - 0.3) / 1.6, 0, 1) * (t > 0.25))[0]
    gr[idx] = rng.standard_normal(len(idx))
    out += bp(np.convolve(gr, expdecay(int(0.004 * SR), 0.0012))[:n], 2000, 7000) * 0.3   # pouring grain
    x = reverb(out, 1.8, 0.3, 6000)
    return fade(normalize(x, -3.0), 0.001, 0.3)


def lightning():
    dur = 6.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    # crack: stepped-leader clicks, a violent broadband snap and a short tearing burst
    for i in range(6):
        at = rng.uniform(0, 0.03)
        m = int(0.004 * SR)
        place(x, hp(white(m), 2000) * np.exp(-np.arange(m) / SR / 0.0008), at, rng.uniform(0.4, 1.0))
    snap = hp(white(n), 600) * np.exp(-t / 0.05) * np.minimum(t / 0.0005, 1)
    tear = bp(white(n), 500, 6000) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 55 * t))) * np.exp(-((t - 0.12) / 0.12) ** 2)
    x += snap * 1.2 + tear * 0.45
    # thunder: several overlapping rumbles that roll and darken
    rum = np.zeros(n)
    for k in range(5):
        at = 0.15 + k * rng.uniform(0.35, 0.8)
        e = np.clip((t - at) / 0.15, 0, 1) * np.exp(-np.clip(t - at, 0, None) / rng.uniform(0.8, 1.8))
        rum += e * rng.uniform(0.5, 1.0)
    thunder = tv_filter(brown(n), "low", 120 + 900 * np.exp(-t / 0.8)) * rum
    thunder += lp(white(n), 60) * rum * 0.8
    x += thunder * 1.1
    x = reverb(x, 2.5, 0.3, 3000, 0.04)
    return fade(normalize(x, -1.0), 0.0002, 0.8)


def meteor_incoming():
    dur = 1.4
    n = int(dur * SR)
    u = np.linspace(0, 1, n)
    roar = tv_filter(pink(n), "low", 300 + 2500 * u ** 2) * u ** 2.2
    whistle = osc(1500 - 900 * u) * u ** 3 * 0.12
    crack = np.zeros(n)
    idx = np.nonzero(rng.random(n) < 150 * u / SR)[0]
    crack[idx] = rng.standard_normal(len(idx))
    crack = bp(np.convolve(crack, expdecay(int(0.006 * SR), 0.002))[:n], 1200, 6000) * u
    x = roar + whistle + crack * 0.3
    return fade(normalize(x, -2.0), 0.05, 0.01)


def meteor_impact():
    dur = 5.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    boom = osc(25 + 55 * np.exp(-t * 2.5)) * np.exp(-t / 0.9) * np.minimum(t / 0.004, 1)
    blast = tv_filter(white(n), "low", 250 + 5000 * np.exp(-t / 0.15)) * np.exp(-t / 0.6) * np.minimum(t / 0.002, 1)
    deb = np.zeros(n)
    idx = np.nonzero(rng.random(n) < 260 / SR * np.exp(-t / 1.0) * (t > 0.2))[0]
    deb[idx] = rng.standard_normal(len(idx)) * rng.random(len(idx)) ** 2 * 3
    deb = bp(np.convolve(deb, expdecay(int(0.015 * SR), 0.004))[:n], 300, 4000)
    tail = lp(brown(n), 200) * np.clip(t / 0.3, 0, 1) * np.exp(-t / 1.8) * 0.6
    x = boom * 1.0 + blast * 0.9 + deb * 0.5 + tail
    x = reverb(x, 2.8, 0.3, 2500, 0.05)
    return fade(normalize(x, -0.8), 0.0002, 0.8)


def ignite():
    n = int(1.0 * SR)
    t = np.arange(n) / SR
    x = tv_filter(pink(n), "low", 300 + 1500 * np.exp(-t / 0.2)) * np.minimum(t / 0.04, 1) * np.exp(-t / 0.35)
    return fade(normalize(reverb(x, 0.8, 0.15, 4000), -4.0), 0.001, 0.2)


def ui_click():
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 1250 * t) * np.exp(-t / 0.012) + np.sin(2 * np.pi * 2900 * t) * np.exp(-t / 0.006) * 0.4
    return fade(normalize(x, -8.0), 0.0005, 0.02)


def ui_select():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    x = fm_bell(880, 0.35, 2.0, 0.6) * 0.6
    place(x, fm_bell(1320, 0.3, 2.0, 0.4), 0.0, 0.3)
    return fade(normalize(x, -9.0), 0.0005, 0.05)


# ================================================================ MUSIC
def note_hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def pad_voice(f, dur, cutoff=900):
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for det in (-0.006, 0.0, 0.0055):
        x += harmonic(f * (1 + det), [(1.0 / k ** 2 if k % 2 else 0.15 / k ** 2) for k in range(1, 10)], dur)
    lfo = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(0.05, 0.12) * t + rng.uniform(0, 6))
    x = tv_filter(x, "low", cutoff * (0.7 + 0.6 * lfo))
    e = np.clip(t / 2.2, 0, 1) ** 2 * np.clip((dur - t) / 2.6, 0, 1) ** 1.5
    return x * e


def music_piece(seed, root, mode, prog, bars_per_chord, beat, length_s, pluck_bright, title):
    global rng
    rng = np.random.default_rng(seed)
    n = int((length_s + 6) * SR)
    L = np.zeros(n)
    R = np.zeros(n)
    chord_len = bars_per_chord * 4 * beat
    # pads + bass, one chord at a time with overlap
    t = 0.0
    ci = 0
    while t < length_s - 2:
        deg = prog[ci % len(prog)]
        chord = [root + mode[(deg + k) % 7] + 12 * ((deg + k) // 7) for k in (0, 2, 4, 6)]
        for k, m in enumerate(chord):
            v = pad_voice(note_hz(m), chord_len + 2.5, 650 + 80 * k) * (0.09 if k else 0.12)
            pan = 0.35 + 0.1 * k
            place(L, v, t, np.sqrt(1 - pan))
            place(R, v, t, np.sqrt(pan))
        bm = root - 12 + mode[deg % 7]
        bn = int((chord_len + 1.5) * SR)
        bt = np.arange(bn) / SR
        bass = harmonic(note_hz(bm), [1.0, 0.35, 0.1], chord_len + 1.5) * np.clip(bt / 0.6, 0, 1) * np.exp(-bt / (chord_len * 0.8))
        place(L, bass, t, 0.22)
        place(R, bass, t, 0.22)
        t += chord_len
        ci += 1
    # plucked melody: motif-based phrases on the mode, with rests
    scale = [root + 12 + s for s in mode] + [root + 24 + s for s in mode[:5]]
    motif = list(rng.integers(0, 7, 4))
    t = 4 * beat
    while t < length_s - 4:
        # each phrase: a variation of the motif, transposed toward the current chord
        ci = int(t // chord_len)
        deg = prog[ci % len(prog)]
        shift = deg % 7
        phrase = [(m + shift + rng.choice([0, 0, 0, 1, -1, 2])) % len(scale) for m in motif]
        if rng.random() < 0.4:
            phrase += [phrase[-1] + rng.choice([-2, -1, 1, 2])]
        for idx in phrase:
            idx = int(np.clip(idx, 0, len(scale) - 1))
            f = note_hz(scale[idx])
            d = rng.choice([1, 1, 2, 0.5, 1.5]) * beat
            nt = ks_pluck(f, 3.0, pluck_bright, 0.9965)
            pan = rng.uniform(0.35, 0.65)
            g = rng.uniform(0.3, 0.42)
            place(L, nt, t, g * np.sqrt(1 - pan))
            place(R, nt, t, g * np.sqrt(pan))
            t += d
        t += rng.choice([2, 3, 4]) * beat
        if rng.random() < 0.3:
            motif = list(rng.integers(0, 7, 4))
    x = np.stack([L, R])
    x = reverb(x, 3.6, 0.38, 5000, 0.03, stereo=True)
    x = x[:, : int((length_s + 4) * SR)]
    x = fade(x, 3.0, 5.0)
    return to_rms(x, -22.0, -3.0)


DORIAN = [0, 2, 3, 5, 7, 9, 10]
AEOLIAN = [0, 2, 3, 5, 7, 8, 10]
MIXOLYDIAN = [0, 2, 4, 5, 7, 9, 10]


# ================================================================ BUILD
def main():
    jobs = [
        ("ambience/forest.ogg", amb_forest, True),
        ("ambience/meadow.ogg", amb_meadow, True),
        ("ambience/coast.ogg", amb_coast, True),
        ("ambience/high_wind.ogg", amb_high_wind, True),
        ("ambience/rain.ogg", amb_rain, True),
        ("ambience/fire.ogg", amb_fire, True),
        ("ambience/village.ogg", amb_village, True),
    ]
    for i, f in enumerate([bird_trill_flourish, bird_trill_flourish, bird_two_tone, bird_two_tone, bird_warble,
                           bird_warble, bird_trill, bird_chips, bird_chips, dove_coo]):
        jobs.append((f"sfx/bird_{i + 1:02d}.wav", f, False))
    for i in range(3):
        jobs.append((f"sfx/wolf_howl_{i + 1}.wav", (lambda k=i: wolf_howl(k)), False))
    for i in range(3):
        jobs.append((f"sfx/rustle_{i + 1}.wav", rustle, False))
    jobs += [("sfx/deer_huff.wav", deer_huff, False), ("sfx/rabbit_thump.wav", rabbit_thump, False)]
    for i in range(3):
        jobs.append((f"sfx/chop_{i + 1}.wav", axe_chop, False))
        jobs.append((f"sfx/hammer_{i + 1}.wav", hammer, False))
    jobs += [
        ("sfx/build_complete.wav", build_complete, False),
        ("sfx/collapse.wav", collapse, False),
        ("sfx/hand_grab_1.wav", hand_grab, False), ("sfx/hand_grab_2.wav", hand_grab, False),
        ("sfx/hand_place_1.wav", hand_place, False), ("sfx/hand_place_2.wav", hand_place, False),
        ("sfx/hand_throw_1.wav", hand_throw, False), ("sfx/hand_throw_2.wav", hand_throw, False),
        ("sfx/impact_light.wav", impact, False), ("sfx/impact_heavy.wav", lambda: impact(True), False),
        ("sfx/splash.wav", splash, False),
        ("sfx/earth_rumble_loop.wav", earth_rumble_loop, False),
        ("sfx/drain_loop.wav", drain_loop, False),
        ("sfx/tile_thunk.wav", tile_thunk, False),
        ("sfx/life.wav", lambda: chime_chord([220.0, 277.18, 329.63, 440.0, 554.37], 3.2), False),
        ("sfx/forest_grow.wav", forest_grow, False),
        ("sfx/rain_gather.wav", rain_gather, False),
        ("sfx/plenty.wav", plenty, False),
        ("sfx/lightning.wav", lightning, False),
        ("sfx/meteor_incoming.wav", meteor_incoming, False),
        ("sfx/meteor_impact.wav", meteor_impact, False),
        ("sfx/ignite.wav", ignite, False),
        ("sfx/ui_click.wav", ui_click, False),
        ("sfx/ui_select.wav", ui_select, False),
        ("music/dawn_of_valleys.ogg", lambda: music_piece(7, 50, DORIAN, [0, 6, 3, 0, 5, 6, 4, 0], 2, 60 / 66, 100, 0.45, "a"), True),
        ("music/quiet_shores.ogg", lambda: music_piece(19, 45, AEOLIAN, [0, 5, 2, 6, 0, 3, 4, 0], 2, 60 / 60, 96, 0.3, "b"), True),
    ]
    for rel, fn, ogg in jobs:
        if not want(rel):
            continue
        save(rel, fn(), ogg)
        print(f"{rel:36s} {REPORT[-1][1]:6.2f}s  peak {REPORT[-1][2]:6.1f} dBFS  rms {REPORT[-1][3]:6.1f} dBFS", flush=True)


if __name__ == "__main__":
    main()
