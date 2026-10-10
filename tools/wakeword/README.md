# Haku wake word

Haku listens for its name on this Mac. Nothing leaves the machine, and it's on by default (Settings › Hotkeys & voice › Listen for “Haku”).

Two detectors:

1. **Custom openWakeWord model** (preferred: low power, few false starts). Haku runs
   `melspectrogram.onnx → embedding_model.onnx → haku.onnx` with ONNX Runtime, once the three files are in
   `~/Library/Application Support/Haku/wakeword/`.
2. **On-device speech fallback** (until the model exists). This uses macOS 26's SpeechAnalyzer to transcribe
   continuously and matches “Haku” plus common mishearings. It works with no setup, but uses more CPU and can
   fire on “haiku”.

## Training the custom model

```bash
./tools/wakeword/train_haku.sh            # work dir defaults to ~/haku-wakeword
```

The script:
- generates about 50k synthetic “haku” clips with Piper;
- augments them with room impulse responses and background audio;
- trains a small DNN with openWakeWord;
- copies the three `.onnx` files into Haku's folder.

Haku picks up the model on its own within about 5 s. Expect roughly 20 GB of downloads and a few hours on Apple
silicon. You can also run it on a CUDA machine or Colab, then copy `out/haku.onnx` plus the two front-end models over.

Tuning: `haku.yml` → `target_phrase` (spellings for the TTS), `custom_negative_phrases` (sound-alikes to reject),
`steps`, `target_false_positives_per_hour`. The in-app Sensitivity slider maps to a score threshold of 0.8 → 0.2.
