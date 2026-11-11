#!/bin/bash
# Usage: board-tools/hl2-fps.sh <label> <seconds> [hl2 args...]
#   e.g. board-tools/hl2-fps.sh 720p 90 -w 1280 -h 720
# Starts the ToGL HL2 build on the board (systemd user unit "hl2", Mesa from /opt via env.sh) at
# the start of d1_canals_01, lets it run <seconds>, stops it and prints the fps that Mesa's
# GALLIUM_HUD dumped (median of the last half of the samples; the first half is loading).
# Extra environment for the game: HL2ENV="VAR=x VAR2=y".
set -euo pipefail
BOARD=${BOARD:-opvolger@192.168.2.33}
LABEL=${1:?label}; SECS=${2:?seconds}; shift 2
ARGS=${*:--w 1280 -h 720}
MAP=${MAP:-d1_canals_01}
ssh -n "$BOARD" "export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
	systemctl --user stop hl2 2>/dev/null; sleep 2; rm -rf /tmp/hud-$LABEL; mkdir -p /tmp/hud-$LABEL
	systemd-run --user --unit=hl2 --collect -p WorkingDirectory=\$HOME/games/hl2-source-togl \
	  -E WAYLAND_DISPLAY=wayland-0 -E XDG_RUNTIME_DIR=/run/user/1000 sh -c '. /opt/mesa-jh7110/env.sh; \
	  export SDL_VIDEODRIVER=wayland GALLIUM_HUD=fps GALLIUM_HUD_VISIBLE=false GALLIUM_HUD_DUMP_DIR=/tmp/hud-$LABEL GALLIUM_HUD_PERIOD=1 ${HL2ENV:-}; \
	  exec ./hl2_launcher -game hl2 ${WINMODE:--windowed} $ARGS -novid +map $MAP > \$HOME/hl2-fps-$LABEL.log 2>&1' >/dev/null"
sleep "$SECS"
ssh -n "$BOARD" "XDG_RUNTIME_DIR=/run/user/1000 systemctl --user stop hl2; ls /tmp/hud-$LABEL; f=\$(ls /tmp/hud-$LABEL/* | head -1);
	n=\$(wc -l < \$f); echo \"$LABEL: \$n samples, last: \$(tail -5 \$f | awk '{print \$NF}' | tr '\n' ' ')\";
	tail -n \$((n/2)) \$f | awk '{print \$NF}' | sort -n | awk '{a[NR]=\$1}END{print \"median fps (2nd half): \" a[int((NR+1)/2)]}'"
