# /// script
# requires-python = ">=3.11"
# ///
"""Sound as code: synthesize the game's sound effects into sfx/*.wav.

Standard library only. Each sound is a list of samples between -1 and 1;
change a frequency or a shape, run `deno task sfx`, and replay.
"""

import math
import random
import struct
import wave

RATE = 22050


def sweep(start_hz: float, end_hz: float, seconds: float, shape: str = "square") -> list[float]:
    """A tone gliding from start_hz to end_hz, fading out as it goes."""
    samples, phase, count = [], 0.0, int(RATE * seconds)
    for i in range(count):
        progress = i / count
        phase += (start_hz + (end_hz - start_hz) * progress) / RATE
        if shape == "square":
            value = 1.0 if phase % 1 < 0.5 else -1.0
        elif shape == "noise":
            value = random.uniform(-1, 1)
        else:
            value = math.sin(2 * math.pi * phase)
        samples.append(value * (1 - progress) ** 2)
    return samples


def save(name: str, samples: list[float], volume: float = 0.35) -> None:
    with wave.open(f"sfx/{name}.wav", "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * volume * 32767)) for s in samples))


random.seed(121)  # the same noise every build, so git sees no change unless you make one
save("eat", sweep(880, 440, 0.07) + sweep(660, 990, 0.06))
save("power", sweep(440, 880, 0.1, "sine") + sweep(660, 1320, 0.1, "sine") + sweep(880, 1760, 0.25, "sine"))
save("crash", sweep(300, 40, 0.5, "noise"), volume=0.5)
print("Built sfx/eat.wav, sfx/power.wav, sfx/crash.wav")
