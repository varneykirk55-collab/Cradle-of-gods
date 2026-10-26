# Audio credits and provenance

**Every sound in `assets/audio/` is original and procedurally synthesised** by
`tools/make_audio.py` (Python + numpy + scipy, encoded with ffmpeg/libvorbis).
No recordings, sample libraries, sound packs, third-party audio or AI audio
models were used, and nothing was sourced from other games, YouTube or
"royalty free" sites.

- **Author:** generated for the Cradle of Gods project by Claude Code (the
  synthesis code was written for this repository).
- **License:** the same terms as the rest of this repository. These files carry
  no third-party rights, so no attribution is required.
- **Reproduce:** `pip install numpy scipy` and have `ffmpeg` with libvorbis on the PATH, then run
  `python3 tools/make_audio.py assets/audio`. Output is deterministic (seeded RNG).
- **Formats:** ambience loops and music are 44.1 kHz stereo Ogg Vorbis (q4).
  Effects are 44.1 kHz mono 16-bit WAV, positioned in 3D in game.

| File(s) | How it is made |
|---|---|
| `ambience/forest.ogg` | Gust-modulated pink-noise wind through a moving low-pass, plus leaf rustle (2–9 kHz noise gated by a fast irregular flutter and by the gusts) and sparse leaf "ticks"; 48 s seamless loop. |
| `ambience/meadow.ogg` | Lighter, lower wind with an airy dry-grass swish and no leaf ticks; 48 s loop. |
| `ambience/coast.ogg` | Low surf bed, continuous distant wash, and individual waves at irregular 3–8 s intervals. Each wave is a swell, a soft break whose low-pass sweeps down as it spreads, and lingering foam fizz from sparse filtered clicks, panned across the stereo field. 56 s loop. |
| `ambience/high_wind.ogg` | Wind with two soft, drifting resonances (hollow wind over ridges), heard when zoomed out; 40 s loop. |
| `ambience/rain.ogg` | Thousands of tiny filtered drop impulses, larger "plops" through resonant filters, and a quiet hiss bed, soft-limited; 20 s loop. |
| `ambience/fire.ogg` | Flickering low roar (brown noise) with random crackles and resonant pops; 12 s loop. |
| `ambience/village.ogg` | Distant murmur from 9 synthetic voices: a harmonic glottal source with prosodic pitch contours, syllable and phrase envelopes with pauses, and drifting vowel formants. Heavily low-passed with outdoor reverb so no words are intelligible. 30 s loop. |
| `sfx/bird_01..10.wav` | Songbird phrases from pure tones with frequency glides: descending trill with a flourish, two-tone whistles, arched warble notes, a rapid trill, chip calls, and a low three-note dove coo. Short outdoor reverb. |
| `sfx/wolf_howl_1..3.wav` | Mostly-fundamental harmonic voice on a rise–hold–fall pitch contour with slow vibrato, a vowel filter opening from "oo" to "ow", breath noise, and distant reverb. |
| `sfx/rustle_1..3.wav`, `deer_huff.wav`, `rabbit_thump.wav` | Footfalls and brush rustle from filtered noise bursts; a breathy deer snort; soft low thumps. |
| `sfx/chop_*.wav`, `hammer_*.wav`, `build_complete.wav`, `collapse.wav` | Modal synthesis of struck wood (decaying sinusoid modes plus a contact click and a low thud), a pulse-train timber creak, and a cluster of falling timbers over a rumble. |
| `sfx/hand_grab_*.wav`, `hand_place_*.wav`, `hand_throw_*.wav` | Soft pitched-down "whump" with a grip rustle and faint shimmer; a settling thud; a resonant swept air swish. |
| `sfx/impact_light.wav`, `impact_heavy.wav`, `splash.wav` | Falling-pitch thump, low-passed burst and debris patter; water burst with rising bubble chirps. |
| `sfx/earth_rumble_loop.wav`, `drain_loop.wav`, `tile_thunk.wav` | Land creation/raise/lower rumble (sub-bass, brown noise, gravel grains); land removal (rumble with draining bubbles); tile placement thunk with gravel spill. |
| `sfx/life.wav`, `forest_grow.wav`, `plenty.wav`, `rain_gather.wav` | Detuned additive major chord with shimmer and a large reverb; Karplus–Strong plucked pentatonic arpeggio with a leaf-rustle swell; FM bells with pouring grain; a gathering low swell for the rain cloud. |
| `sfx/lightning.wav` | Stepped-leader clicks, a broadband snap and a short tearing burst, then several overlapping rolling thunder rumbles that darken over time. |
| `sfx/meteor_incoming.wav`, `meteor_impact.wav` | A rising roar with a falling whistle and crackle; a sub-bass boom sweep, broadband blast, debris rain and a rumbling tail. |
| `sfx/ignite.wav`, `ui_click.wav`, `ui_select.wav` | Fire "whoomph"; soft wooden tick; quiet FM bell. |
| `music/dawn_of_valleys.ogg` | About 100 s, D Dorian, 66 bpm. Soft additive pads (odd-harmonic, slowly filtered), a gentle bass, and a sparse Karplus–Strong plucked melody built from motif variations, in a synthetic hall reverb. Not modelled on any existing recording or artist. |
| `music/quiet_shores.ogg` | About 96 s, A Aeolian, 60 bpm, with the same instrumentation, a darker pluck and a different progression. |

## How quality was checked

I couldn't listen to the audio in the build environment. Each sound was
checked in three ways instead:
- **Spectrograms and waveforms**, inspected for clicks, aliasing, buzzy FM
  sidebands and unnatural steadiness. This led to several revisions: smooth
  harmonic roll-off, arched bird notes, purer wolf tone with less reverb
  beating, stronger wind gusts, gradual wave breaks with a continuous wash,
  rain patter over hiss, softer music pads with the melody in front, and a
  resonant throw swish.
- **Peak and RMS levels:** every file peaks at or below −0.8 dBFS (no
  clipping), and loops are level-matched.
- **Seamless loop crossfades.**

How natural the sounds are should still be judged by ear. The weakest
candidates are the village murmur (synthetic voices) and the wolf howls.
