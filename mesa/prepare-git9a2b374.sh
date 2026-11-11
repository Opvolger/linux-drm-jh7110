#!/bin/bash
# Usage: mesa/prepare-git9a2b374.sh
#
# Prepares mesa/mesa-git: Mesa main at 9a2b374 + the PowerVR performance series from
# https://github.com/ayiejosh/a733-powervr-fex (mesa/open-driver-series 0001-0105, copied into
# mesa/fork-ayiejosh-series/, source commit in SOURCE-COMMIT) + our patches
# (mesa/patches-git9a2b374/). Then build with:
#
#   SRCDIR=mesa-git PKGVER=26.3.0~git9a2b374+ayie PKGREV=<n> mesa/build.sh
#
# The fork series was written for a BXM-4-64 (Allwinner A733); on our BXE-4-32 it took HL2
# (ToGL/Zink) from ~4.5 to ~28 fps on KMS. See the plan document (README.md).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/mesa"
BASE=9a2b374656d
[ -d mesa-git ] || git clone --filter=blob:none --no-checkout https://gitlab.freedesktop.org/mesa/mesa.git mesa-git
cd mesa-git
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
	echo "mesa/mesa-git has uncommitted changes; commit or discard them first" >&2
	exit 1
fi
git checkout -q -B jh7110 "$BASE"
G="git -c user.name=build -c user.email=build@localhost"
$G am -q --keep-cr ../fork-ayiejosh-series/*.patch
$G am -q ../patches-git9a2b374/*.patch
git log --oneline -1
