#!/usr/bin/env bash
# Keep the vendored guest module set in step with discofetch.
#
#   ./sync-from-discofetch.sh [--from PATH]    # report drift, change nothing
#   ./sync-from-discofetch.sh --update         # copy the upstream files in
#
# Every file here is a BYTE-FOR-BYTE copy of one in discofetch's `api/`,
# renamed only where the two conventions differ (`supervisor.lua` is the
# face's entry and the dollup format calls that `api.dlua`). Byte-identity
# is the whole discipline: it makes drift a `cmp` rather than a code
# review, and it means this repo can never quietly become a second,
# divergent implementation of the API.
#
# So: edits belong upstream, in discofetch, and arrive here through this
# script. If you find yourself wanting to patch a .dlua directly, that is
# the signal that the code should move here for real -- which is a decision
# to make deliberately, not by drifting into it.
#
# ── what a module is, and why this walks rather than lists ─────────────
#
# It was one file until discofetch split its 6,826-line supervisor into an
# entry plus `api/df/*.dlua`, reached by `require` (drt v0.6.0rc1 modules).
# A list of filenames here would have been right on the day it was written
# and silently short the first time upstream added a module -- and short is
# the bad direction: the package seals, publishes and verifies perfectly,
# and the node it stages fails at its first `require`.
#
# So the set is DERIVED: every tracked `.dlua` and `.lua` under upstream's
# `api/`, which is exactly the rule drt's loader applies to a node's own
# directory. Tracked, so a local experiment or a battery scratch file is
# not a module; from `git ls-files`, so it needs no knowledge of what is
# ignored. Adding a module upstream is then the whole action -- this picks
# it up, writes it into `guest.modules`, and `seal` hashes it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$here/packages/discofetch-api/0.1.0"
face="$pkg/guest"
manifest="$pkg/manifest.json"
# The entry, on both sides. Upstream's host config names it supervisor.lua;
# the face calls it api.dlua and `guest.main` calls that module `api`.
entry_upstream="api/supervisor.lua"
entry_face="guest/api.dlua"
# Upstream is the `discofetch` repo (this one is discofetch-api, the dollup
# package). A checkout may sit anywhere; DISCOFETCH or --from overrides.
upstream="${DISCOFETCH:-$here/../discofetch}"
update=0

while [ $# -gt 0 ]; do
    case "$1" in
        --from)   upstream="$2"; shift 2 ;;
        --update) update=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

[ -r "$upstream/$entry_upstream" ] || {
    echo "no discofetch checkout at '$upstream'" >&2
    echo "  pass --from PATH, or set DISCOFETCH" >&2
    exit 2
}

# ── depth: the upstream set, and the vendored set, as face paths ───────
# `git ls-files` from the repo root so a path is repo-relative whatever the
# caller's cwd is. The entry is mapped; everything else keeps its place
# under the face, so `df/model.dlua` beside the entry stays beside it.
face_path() {  # face_path <repo-relative upstream path> -> <face path>
    case "$1" in
        "$entry_upstream") printf '%s' "$entry_face" ;;
        api/*)             printf 'guest/%s' "${1#api/}" ;;
        *) echo "sync: '$1' is not under api/" >&2; exit 1 ;;
    esac
}

upstream_files=$(git -C "$upstream" ls-files 'api/*.dlua' 'api/*.lua' | sort)
[ -n "$upstream_files" ] || { echo "sync: upstream has no guest source at all" >&2; exit 1; }

want=""     # face paths the upstream set says should exist
drift=0
for u in $upstream_files; do
    f=$(face_path "$u")
    want="$want $f"
    if [ -r "$pkg/$f" ] && cmp -s "$upstream/$u" "$pkg/$f"; then
        continue
    fi
    drift=1
    if [ -r "$pkg/$f" ]; then
        echo "DRIFT  $f"
        echo "         upstream $u: $(sha256sum "$upstream/$u" | cut -c1-16)…"
        echo "         vendored:    $(sha256sum "$pkg/$f"      | cut -c1-16)…"
    else
        echo "NEW    $f  (from $u, $(wc -l < "$upstream/$u") lines)"
    fi
done

# A module upstream DELETED has to go, and this is the half a hand-written
# list never does: it lingers, seals, publishes, and is required by nothing
# -- until a stale one is required by something and answers with last
# month's code.
stale=""
for f in $(cd "$pkg" && git ls-files 'guest/*' | sort); do
    case " $want " in *" $f "*) continue ;; esac
    stale="$stale $f"
    drift=1
    echo "STALE  $f  (upstream has no such module)"
done

if [ "$drift" = 0 ]; then
    n=$(printf '%s\n' $want | wc -l | tr -d ' ')
    echo "in step: $n module file(s), $(cd "$pkg" && cat $want | sha256sum | cut -c1-16)… over the set"
    exit 0
fi

[ "$update" = 1 ] || {
    echo
    echo "pass --update to take the upstream copies, then re-seal:"
    echo "  dollup repo seal packages/discofetch-api/0.1.0 && dollup repo index ."
    exit 1
}

for u in $upstream_files; do
    f=$(face_path "$u")
    mkdir -p "$(dirname "$pkg/$f")"
    cp "$upstream/$u" "$pkg/$f"
done
for f in $stale; do rm -f "$pkg/$f"; done
find "$face" -type d -empty -delete 2>/dev/null || true

# ── depth: guest.modules, written from what was just vendored ──────────
# `seal` rebuilds `files` by walking the package, and `manifest.check()`
# refuses a module whose path is not in `files` -- but nothing fills in
# `modules` itself, so a vendored module that is not named here is a file
# the package carries and no `require` can reach. Written here, from the
# same list the copies came from, for the reason the set is derived at all.
python3 - "$manifest" $want <<'PY'
import json, io, sys
manifest, paths = sys.argv[1], sys.argv[2:]
m = json.load(open(manifest, encoding='utf-8'))
# A module's name is its path under the face, without the extension, dots
# for separators: guest/df/model.dlua -> df.model. That is drt's rule read
# backwards (drt_config::modules::name_for_path), and it has to be, or a
# name this package declares is one the loader would not answer to.
mods = {}
for p in paths:
    stem = p[len('guest/'):].rsplit('.', 1)[0]
    mods[stem.replace('/', '.')] = p
m.setdefault('guest', {})['modules'] = dict(sorted(mods.items()))
main = m['guest'].get('main')
if main and main not in mods:
    sys.exit("sync: guest.main is '%s' and the vendored set has no such module" % main)
io.open(manifest, 'w', encoding='utf-8').write(json.dumps(m, indent=2) + '\n')
print("manifest: guest.modules lists %d module(s), main is %s" % (len(mods), main))
PY

echo
echo "updated. Now re-seal, or the manifest ships stale hashes:"
echo "  dollup repo seal packages/discofetch-api/0.1.0"
echo "  dollup repo index ."
echo
echo "and bump the package version if this is going out to anyone."
