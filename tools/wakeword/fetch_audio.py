"""Downloads room impulse responses and a small background-audio set for augmentation (16 kHz wavs)."""
import os
import numpy as np
import scipy.io.wavfile
from datasets import load_dataset, Audio
from tqdm import tqdm

def save(ds, out, limit=None):
    os.makedirs(out, exist_ok=True)
    if len(os.listdir(out)) > 0:
        return
    for i, row in enumerate(tqdm(ds, desc=out)):
        if limit and i >= limit:
            break
        a = row["audio"]
        name = os.path.basename(a.get("path") or f"{i}.wav").rsplit(".", 1)[0] + ".wav"
        scipy.io.wavfile.write(os.path.join(out, name), 16000, (np.array(a["array"]) * 32767).astype(np.int16))

rirs = load_dataset("davidscripka/MIT_environmental_impulse_responses", split="train", streaming=True)
save(rirs.cast_column("audio", Audio(sampling_rate=16000)), "mit_rirs")

audioset = load_dataset("agkphysics/AudioSet", "balanced", split="train", streaming=True)
save(audioset.cast_column("audio", Audio(sampling_rate=16000)), "audioset_16k", limit=3000)

fma = load_dataset("rudraml/fma", name="small", split="train", streaming=True)
save(fma.cast_column("audio", Audio(sampling_rate=16000)), "fma", limit=1500)
