#!/bin/bash
# Usage: board-tools/hl2-kms-fps.sh <label> [seconds=150] [extra hl2 args...]
# Runs the ToGL HL2 build directly on KMS (SDL kmsdrm, no compositor; SDDM must be stopped) at the
# start of d1_canals_01 (1280x720), prints the fps from Mesa's GALLIUM_HUD dump and the GPU job
# durations (drm_sched_job_run -> drm_sched_job_done) over 2 s of the run, sorted, in ms.
# Note: the KMS page flips fail (ENOSPC), so nothing is shown on screen; measurement only.
set -euo pipefail
BOARD=${BOARD:-opvolger@192.168.2.33}
LABEL=${1:?label}; SECS=${2:-150}; shift 2 || true
ARGS="$*"
ssh -n "$BOARD" "sudo pkill -x hl2_launcher; sleep 2; cd ~/games/hl2-source-togl && sudo rm -rf /tmp/hud-$LABEL && sudo mkdir -p /tmp/hud-$LABEL &&
 sudo sh -c '. /opt/mesa-jh7110/env.sh; export SDL_VIDEODRIVER=kmsdrm GALLIUM_HUD=fps GALLIUM_HUD_VISIBLE=false GALLIUM_HUD_DUMP_DIR=/tmp/hud-$LABEL GALLIUM_HUD_PERIOD=1 HOME=/home/opvolger ${HL2ENV:-}; timeout $SECS ./hl2_launcher -game hl2 ${RES:--w 1280 -h 720} -novid $ARGS +map d1_canals_01 > /tmp/hl2-kms-$LABEL.log 2>&1 &'
 sleep $((SECS - 25))
 T=/sys/kernel/tracing; echo 0 | sudo tee \$T/tracing_on >/dev/null; echo | sudo tee \$T/trace >/dev/null
 for e in drm_sched_job_run drm_sched_job_done; do echo 1 | sudo tee \$T/events/gpu_scheduler/\$e/enable >/dev/null; done
 echo 1 | sudo tee \$T/tracing_on >/dev/null; sleep 2; echo 0 | sudo tee \$T/tracing_on >/dev/null
 for e in drm_sched_job_run drm_sched_job_done; do echo 0 | sudo tee \$T/events/gpu_scheduler/\$e/enable >/dev/null; done
 sudo cat \$T/trace | awk '/drm_sched_job_run/ { match(\$0, /fence=[0-9]+:[0-9]+/); f=substr(\$0,RSTART+6,RLENGTH-6); t=\$4; sub(/:/,\"\",t); r[f]=t }
   /drm_sched_job_done/ { match(\$0, /fence=[0-9]+:[0-9]+/); f=substr(\$0,RSTART+6,RLENGTH-6); t=\$4; sub(/:/,\"\",t); if (f in r) printf \"%.1f \", (t-r[f])*1000 }' | tr ' ' '\n' | sort -n | tail -12 | tr '\n' ' '; echo ' <- slowest GPU jobs (ms) in 2 s'
 sleep 25; f=\$(ls /tmp/hud-$LABEL/* | head -1); echo \"$LABEL fps (last 8 s): \$(tail -8 \$f | awk '{print \$NF}' | tr '\n' ' ')\""
