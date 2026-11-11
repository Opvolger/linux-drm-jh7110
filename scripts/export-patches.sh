#!/bin/bash
# Usage: scripts/export-patches.sh <version>
#
# Writes the commits $TAG..HEAD of linux-<version>/ back out as
# linux-<version>-patches/NNNN-*.patch. Workflow: change the kernel in linux-<version>/,
# commit (or `git commit --fixup` + `git rebase -i --autosquash $TAG`), then run
# this script. Old .patch files in the directory are removed first.
set -euo pipefail

V=${1:?usage: $0 <version>}
TAG=${TAG:-v$V}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TREE=$ROOT/linux-$V
PATCHES=$ROOT/linux-$V-patches

[ -e "$TREE/.git" ] || { echo "no kernel tree $TREE" >&2; exit 1; }
if [ -n "$(git -C "$TREE" status --porcelain --untracked-files=no)" ]; then
	echo "linux-$V has uncommitted changes; commit them first" >&2
	exit 1
fi

git -C "$TREE" rev-parse -q --verify "$TAG^{commit}" >/dev/null || {
	echo "tag $TAG not found in linux-$V (set TAG=..., e.g. TAG=v$V-rc1)" >&2
	exit 1
}

mkdir -p "$PATCHES"
rm -f "$PATCHES"/*.patch
git -C "$TREE" format-patch --quiet --zero-commit --no-signature \
	-o "$PATCHES" "$TAG..HEAD"
ls "$PATCHES"
