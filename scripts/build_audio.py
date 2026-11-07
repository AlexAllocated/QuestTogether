#!/usr/bin/env python3
"""Build QT's original, quiet fantasy cues and independent gain variants.

Development requirements: Python 3 and ffmpeg with libvorbis. The addon has no
audio library dependency. No sampled game sounds or third-party recordings are
used. See Media/Audio/NOTICE.txt for provenance. Run --verify-only to inspect the
checked-in recordings.
"""

import argparse
from array import array
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
from pathlib import Path
import random
import shutil
import struct
import subprocess
import sys
import wave


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Media" / "Audio"
PREVIEWS = ROOT / ".local" / "audio-design"
RATE = 44100
TAU = math.tau
CUES = (
    ("scroll", "Parchment", 0.280, 0.160, 20),
    ("spellbook", "Arcane shimmer", 0.700, 0.370, 20),
    ("selection", "Focus chime", 0.360, 0.380, 20),
    ("chime", "Gentle bell", 0.640, 0.400, 30),
    ("progress", "Soft pluck", 0.280, 0.350, 15),
    ("completion", "Quest flourish", 0.790, 0.400, 25),
)


def smooth(value):
    return 0.5 - 0.5 * math.cos(math.pi * min(1.0, max(0.0, value)))


def note(samples, start, frequency, length, amplitude=1.0, decay=0.12,
         partials=((1.0, 1.0), (2.0, 0.15), (3.0, 0.04)), attack=0.006):
    """Add a soft struck/resonant tone. Higher partials decay sooner."""
    first = round(start * RATE)
    count = min(round(length * RATE), len(samples) - first)
    for index in range(max(0, count)):
        time = index / RATE
        envelope = smooth(time / attack) * smooth((count - index - 1) / (RATE * 0.045))
        tone = sum(
            weight * math.sin(TAU * frequency * ratio * time)
            * math.exp(-time / (decay / math.sqrt(ratio)))
            for ratio, weight in partials
        )
        samples[first + index] += amplitude * envelope * tone


def rustle(samples, start, length, amplitude, seed):
    """Two filtered noise bands give parchment texture without a sharp hiss."""
    rng = random.Random(seed)
    first = round(start * RATE)
    count = round(length * RATE)
    low = high = 0.0
    low_alpha = 1.0 - math.exp(-TAU * 350.0 / RATE)
    high_alpha = 1.0 - math.exp(-TAU * 2100.0 / RATE)
    for index in range(count):
        noise = rng.uniform(-1.0, 1.0)
        low += low_alpha * (noise - low)
        high += high_alpha * (noise - high)
        envelope = math.sin(math.pi * index / (count - 1)) ** 2
        flutter = 0.78 + 0.22 * math.sin(TAU * 28.0 * index / RATE)
        if first + index < len(samples):
            samples[first + index] += amplitude * (high - low) * envelope * flutter


def synthesize(key, duration, peak):
    samples = [0.0] * round(duration * RATE)
    if key == "scroll":
        rustle(samples, 0.012, 0.145, 1.0, 71604)
        rustle(samples, 0.110, 0.120, 0.57, 71605)
    elif key == "spellbook":
        partials = ((1.0, 1.0), (2.005, 0.10), (3.01, 0.025))
        note(samples, 0.014, 587.330, 0.590, 1.0, 0.22, partials, 0.025)
        note(samples, 0.082, 880.000, 0.540, 0.42, 0.18, partials, 0.035)
        note(samples, 0.156, 1174.659, 0.510, 0.20, 0.16, partials, 0.040)
        rustle(samples, 0.020, 0.175, 0.055, 71606)
    elif key == "selection":
        note(samples, 0.012, 587.330, 0.245, 0.64, 0.085)
        note(samples, 0.095, 880.000, 0.230, 0.83, 0.095)
    elif key == "chime":
        partials = ((1.0, 1.0), (2.003, 0.13), (2.758, 0.04), (4.01, 0.018))
        note(samples, 0.014, 659.255, 0.585, 1.0, 0.19, partials, 0.009)
        note(samples, 0.036, 987.767, 0.540, 0.19, 0.14, partials, 0.025)
    elif key == "progress":
        note(samples, 0.012, 293.665, 0.235, 1.0, 0.065,
             ((1.0, 1.0), (2.0, 0.25), (3.0, 0.09), (4.0, 0.025)), 0.004)
    elif key == "completion":
        for start, frequency, amplitude in (
            (0.012, 587.330, 0.65), (0.102, 739.989, 0.62),
            (0.192, 880.000, 0.58), (0.292, 1174.659, 0.52),
        ):
            note(samples, start, frequency, 0.755 - start, amplitude, 0.17)
        note(samples, 0.292, 587.330, 0.460, 0.25, 0.18)
    else:
        raise ValueError(key)

    # Cancel residual DC using a taper so both boundaries remain silent.
    weights = [smooth(i / (RATE * 0.010))
               * smooth((len(samples) - i - 1) / (RATE * 0.040))
               for i in range(len(samples))]
    correction = sum(samples) / sum(weights)
    samples = [sample - correction * weight for sample, weight in zip(samples, weights)]
    scale = peak / max(abs(sample) for sample in samples)
    return [sample * scale for sample in samples]


def pcm_float(samples, gain=1.0):
    pcm = array("f", (sample * gain for sample in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    return pcm.tobytes()


def write_wav(path, samples):
    pcm = array("h", (round(sample * 32767) for sample in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())


def statistics(samples):
    return {
        "samples": len(samples),
        "duration_seconds": round(len(samples) / RATE, 6),
        "peak_amplitude": round(max(abs(value) for value in samples), 8),
        "rms_amplitude": round(math.sqrt(sum(value * value for value in samples) / len(samples)), 8),
        "dc_amplitude": round(sum(samples) / len(samples), 10),
        "last_5ms_peak": round(max(abs(value) for value in samples[-round(RATE * 0.005):]), 8),
    }


def command(*args, input=None):
    return subprocess.run(args, input=input, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=True).stdout


def encode(job):
    key, gain, samples = job
    destination = OUTPUT / key / f"{gain:03d}.ogg"
    command("ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-threads", "1", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "pipe:0",
            "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "2", "-threads", "1",
            "-fflags", "+bitexact", "-flags:a", "+bitexact", "-serial_offset", "0",
            str(destination), input=pcm_float(samples, gain / 100))
    return destination


def verify_file(path):
    data = path.read_bytes()
    header = data.find(b"\x01vorbis")
    if data[:4] != b"OggS" or header < 0:
        raise ValueError(f"Not Ogg Vorbis: {path}")
    version, channels, rate = struct.unpack_from("<IBI", data, header + 7)
    if (version, channels, rate) != (0, 1, RATE):
        raise ValueError(f"Unexpected audio format: {path}")
    decoded = command("ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
                      "-threads", "1", "-i", str(path), "-f", "f32le", "-acodec", "pcm_f32le",
                      "-threads", "1", "pipe:1")
    samples = array("f")
    samples.frombytes(decoded)
    if sys.byteorder != "little":
        samples.byteswap()
    stats = statistics(samples)
    if stats["peak_amplitude"] >= 0.5:
        raise ValueError(f"Insufficient headroom: {path}")
    if abs(stats["dc_amplitude"]) > 0.0002:
        raise ValueError(f"Unexpected DC bias: {path}")
    if stats["last_5ms_peak"] > 0.0001:
        raise ValueError(f"Audible final boundary: {path}")
    return {"file": str(path.relative_to(OUTPUT)), "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(), **stats}


def build_previews(masters):
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    montage = [0.0] * round(RATE * 0.5)
    timeline = []
    for key, label, _, _, preview_gain in CUES:
        samples = masters[key]
        write_wav(PREVIEWS / f"{key}.wav", samples)
        timeline.append({"key": key, "label": label,
                         "start_seconds": round(len(montage) / RATE, 3),
                         "gain_percent": preview_gain})
        montage.extend(sample * preview_gain / 100 for sample in samples)
        montage.extend([0.0] * round(RATE * 0.7))
    write_wav(PREVIEWS / "quiet-preview.wav", montage)
    (PREVIEWS / "quiet-preview.json").write_text(json.dumps(timeline, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=2,
                        help="Concurrent single-thread encodes/decodes (default: 2)")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--previews-only", action="store_true")
    args = parser.parse_args()
    if not shutil.which("ffmpeg"):
        parser.error("ffmpeg with libvorbis is required for asset development")

    masters = {key: synthesize(key, duration, peak) for key, _, duration, peak, _ in CUES}
    build_previews(masters)
    if args.previews_only:
        print(f"Wrote originals and quiet preview to {PREVIEWS}")
        return
    if not args.verify_only:
        for key in masters:
            (OUTPUT / key).mkdir(parents=True, exist_ok=True)
        jobs = [(key, gain, samples) for key, samples in masters.items() for gain in range(1, 101)]
        with ThreadPoolExecutor(max_workers=args.jobs) as workers:
            for count, _ in enumerate(workers.map(encode, jobs), 1):
                if count % 100 == 0:
                    print(f"Encoded {count}/600 Ogg Vorbis recordings", flush=True)

    paths = [OUTPUT / key / f"{gain:03d}.ogg" for key in masters for gain in range(1, 101)]
    with ThreadPoolExecutor(max_workers=args.jobs) as workers:
        results = list(workers.map(verify_file, paths))
    by_file = {row["file"]: row for row in results}
    manifest = {
        "schema": 1,
        "copyright": "Copyright (c) 2026 QuestTogether",
        "notice_file": "Media/Audio/NOTICE.txt",
        "origin": "Original QuestTogether procedural synthesis; no external recordings or samples.",
        "source": "scripts/build_audio.py",
        "codec": "vorbis", "container": "ogg", "sample_rate": RATE, "channels": 1,
        "gain": {"minimum": 1, "maximum": 100, "step": 1,
                 "amplitude": "gain / 100", "zero": "Do not play a sound.",
                 "derivation": "Each gain is encoded directly from the same synthesized float PCM master."},
        "cues": {},
    }
    for key, label, _, _, preview_gain in CUES:
        variants = [by_file[f"{key}/{gain:03d}.ogg"] for gain in range(1, 101)]
        expected_duration = len(masters[key]) / RATE
        for variant in variants:
            if abs(variant["duration_seconds"] - expected_duration) > 0.020:
                raise ValueError(f"Incorrect decoded duration: {variant['file']}")
        # Lossy encoding may perturb samples, but the full gain range must stay
        # proportional. This catches silent, normalized, or misnamed variants.
        full_rms = variants[-1]["rms_amplitude"]
        for gain, variant in enumerate(variants, 1):
            ratio = variant["rms_amplitude"] / full_rms
            if abs(ratio - gain / 100) > 0.025:
                raise ValueError(f"Incorrect gain: {variant['file']}")
        manifest["cues"][key] = {"label": label, "master": statistics(masters[key]),
                                  "preview_gain_percent": preview_gain, "variants": variants}

    manifest_text = json.dumps(manifest, indent=2) + "\n"
    if args.verify_only:
        if (OUTPUT / "manifest.json").read_text() != manifest_text:
            raise ValueError("Audio files or synthesis no longer match the manifest; rebuild the assets")
    else:
        (OUTPUT / "manifest.json").write_text(manifest_text)
    size = sum(row["bytes"] for row in results)
    print(f"Verified {len(results)} mono {RATE} Hz Vorbis files; {size:,} bytes ({size / 1048576:.2f} MiB)")
    for key in masters:
        print(f"{key}: {by_file[f'{key}/100.ogg']}")
    print(f"Quiet preview: {PREVIEWS / 'quiet-preview.wav'}")


if __name__ == "__main__":
    main()
