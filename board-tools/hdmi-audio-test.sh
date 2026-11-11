#!/bin/bash
# Usage: board-tools/hdmi-audio-test.sh [freq-Hz=1000] [rate=48000] [seconds=6]
#
# Plays a sine tone on the board's HDMI sound card (ALSA, card id from aplay -l) and records the
# HDMI capture card on this machine at the same time (UGREEN, ALSA card "Capture"; only that
# device is ever opened, never a microphone or webcam). Prints the level and the dominant
# frequency of both channels; PASS when the dominant frequency is within 2% of the tone.
# Recording: logs/hdmi-audio-<freq>-<rate>.wav
set -euo pipefail
BOARD=${BOARD:-opvolger@192.168.2.33}
FREQ=${1:-1000}; RATE=${2:-48000}; SECS=${3:-6}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WAV=$ROOT/logs/hdmi-audio-$FREQ-$RATE.wav
mkdir -p "$ROOT/logs"

CARD=$(ssh -n "$BOARD" "aplay -l | sed -n 's/^card \([0-9]*\): .*HDMI.*/\1/p' | head -1")
[ -n "$CARD" ] || { echo "no HDMI sound card on the board" >&2; ssh -n "$BOARD" "aplay -l"; exit 1; }
echo "board HDMI card: $CARD"

# The capture card's USB audio input starts with its capture switch off (records silence).
amixer -q -c Capture sset 'Digital In' cap

# Record a bit longer than the tone, starting first.
timeout $((SECS + 10)) ffmpeg -hide_banner -loglevel error -f alsa -channels 2 -sample_rate 48000 \
	-i hw:CARD=Capture,DEV=0 -t $((SECS + 2)) -y "$WAV" &
REC=$!
sleep 1
ssh -n "$BOARD" "timeout $((SECS + 5)) speaker-test -D plughw:$CARD,0 -c 2 -r $RATE -t sine -f $FREQ -l 0 >/tmp/speaker-test.log 2>&1 & sleep $SECS; pkill -x speaker-test; tail -3 /tmp/speaker-test.log" || true
wait $REC || true

python3 -I - "$WAV" "$FREQ" <<'EOF'
import sys, wave, numpy as np
w = wave.open(sys.argv[1]); freq = float(sys.argv[2])
sr = w.getframerate(); ch = w.getnchannels()
a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(float)
ok = True
for c in range(ch):
    x = a[:, c]
    rms = np.sqrt((x ** 2).mean())
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / sr)
    dom = f[spec[1:].argmax() + 1]
    good = rms > 50 and abs(dom - freq) <= 0.02 * freq
    ok &= good
    print(f"channel {c}: rms={rms:8.1f}  peak={np.abs(x).max():6.0f}  dominant={dom:8.1f} Hz  {'ok' if good else 'NO'}")
print("PASS" if ok else "FAIL", f"({sr} Hz capture, tone {freq:.0f} Hz)")
EOF
