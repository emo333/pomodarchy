#!/usr/bin/env python3
"""Generate original, gentle Pomodarchy bell chimes as mono 48 kHz PCM WAVs.

The synthesized waveforms are original work, made without third-party samples,
and are released under the repository's MIT license.
"""

import math
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 48_000
PARTIALS = (
    (1.00, 0.72, 0.29),
    (2.00, 0.23, 0.21),
    (3.01, 0.10, 0.15),
    (4.16, 0.045, 0.11),
    (5.43, 0.018, 0.085),
)
ATTACK_SECONDS = 0.010
FADE_SECONDS = 0.040


def midi_frequency(note):
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def render_chime(notes, duration, peak_dbfs):
    """Render (start_seconds, MIDI_note, gain) events and normalize safely."""
    frame_count = round(duration * SAMPLE_RATE)
    signal = [0.0] * frame_count

    for start, midi_note, note_gain in notes:
        fundamental = midi_frequency(midi_note)
        partials = tuple(
            (fundamental * ratio, gain, decay)
            for ratio, gain, decay in PARTIALS
        )
        first_frame = round(start * SAMPLE_RATE)
        for frame in range(first_frame, frame_count):
            age = (frame - first_frame) / SAMPLE_RATE
            attack = 1.0 - math.exp(-age / ATTACK_SECONDS)
            tone = 0.0
            for frequency, gain, decay in partials:
                tone += gain * math.exp(-age / decay) * math.sin(
                    2.0 * math.pi * frequency * age
                )
            signal[frame] += note_gain * attack * tone

    fade_frames = round(FADE_SECONDS * SAMPLE_RATE)
    fade_start = frame_count - fade_frames
    for frame in range(fade_start, frame_count):
        remaining = (frame_count - 1 - frame) / fade_frames
        signal[frame] *= 0.5 - 0.5 * math.cos(math.pi * remaining)

    peak = max(abs(sample) for sample in signal)
    if peak == 0.0:
        raise ValueError("A chime must contain a non-silent signal")
    scale = (10.0 ** (peak_dbfs / 20.0)) / peak
    return [
        max(-32768, min(32767, round(sample * scale * 32767)))
        for sample in signal
    ]


def write_wav(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def main():
    project_root = Path(__file__).resolve().parent.parent
    chimes = (
        (
            "focus-complete.wav",
            ((0.00, 72, 1.00), (0.39, 79, 0.88)),  # C5 to G5: ascending perfect fifth.
            1.08,
            -4.5,
        ),
        (
            "break-complete.wav",
            ((0.00, 69, 0.78), (0.43, 65, 0.68)),  # A4 to F4: softer descending phrase.
            1.12,
            -5.5,
        ),
    )

    for filename, notes, duration, peak_dbfs in chimes:
        destination = project_root / "assets" / filename
        samples = render_chime(notes, duration, peak_dbfs)
        write_wav(destination, samples)
        print(f"Wrote {destination.relative_to(project_root)} ({duration:.2f} s)")


if __name__ == "__main__":
    main()
