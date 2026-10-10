#!/usr/bin/env bash
# Trains a custom openWakeWord "Haku" model and installs it into Haku.
#
#   ./tools/wakeword/train_haku.sh [workdir]
#
# Needs Python 3.10/3.11 and ~25 GB of disk. Downloads (~20 GB): the Piper sample generator
# + LibriTTS voice, ACAV100M negative features, the false-positive validation set,
# MIT room impulse responses, and some AudioSet/FMA background audio.
# Training takes a few hours on Apple silicon (much faster on a CUDA GPU; you can run this
# same script on a Linux box/Colab and copy out/haku.onnx back).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-$HOME/haku-wakeword}"
DEST="$HOME/Library/Application Support/Haku/wakeword"
mkdir -p "$WORK" "$DEST"
cd "$WORK"
cp "$HERE/haku.yml" .

python3 -m venv .venv
source .venv/bin/activate
pip install -U pip
pip install "openwakeword[full]==0.6.0" torch torchaudio torchinfo torchmetrics speechbrain==0.5.16 \
  audiomentations==0.33.0 torch-audiomentations==0.11.0 acoustics==0.2.6 pronouncing datasets==2.14.6 \
  deep-phonemizer==0.0.19 mutagen tqdm pyyaml scipy soundfile "numpy<2"

# Piper sample generator (synthetic "haku" clips in many voices).
[ -d piper-sample-generator ] || git clone https://github.com/rhasspy/piper-sample-generator
mkdir -p piper-sample-generator/models
[ -f piper-sample-generator/models/en_US-libritts_r-medium.pt ] || \
  curl -L -o piper-sample-generator/models/en_US-libritts_r-medium.pt \
  https://github.com/rhasspy/piper-sample-generator/releases/download/v2.0.0/en_US-libritts_r-medium.pt
pip install -r piper-sample-generator/requirements.txt || true

# Negative features + validation set.
[ -f openwakeword_features_ACAV100M_2000_hrs_16bit.npy ] || curl -L -O \
  https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main/openwakeword_features_ACAV100M_2000_hrs_16bit.npy
[ -f validation_set_features.npy ] || curl -L -O \
  https://huggingface.co/datasets/davidscripka/openwakeword_features/resolve/main/validation_set_features.npy

# Room impulse responses and background audio.
python3 "$HERE/fetch_audio.py"

# Shared front-end models (melspectrogram + embedding) that Haku runs at inference time.
python3 -c "import openwakeword.utils as u; u.download_models(model_names=['hey_jarvis'])"
RES="$(python3 -c 'import openwakeword, os; print(os.path.join(os.path.dirname(openwakeword.__file__), "resources", "models"))')"

python3 -m openwakeword.train --training_config haku.yml --generate_clips
python3 -m openwakeword.train --training_config haku.yml --augment_clips
python3 -m openwakeword.train --training_config haku.yml --train_model

cp out/haku.onnx "$DEST/haku.onnx"
cp "$RES/melspectrogram.onnx" "$DEST/melspectrogram.onnx"
cp "$RES/embedding_model.onnx" "$DEST/embedding_model.onnx"
echo "Installed to $DEST — Haku switches to the custom model within a few seconds (Settings › Hotkeys & voice shows it)."
