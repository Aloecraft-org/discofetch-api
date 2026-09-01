#!/usr/bin/env bash
# Keep the vendored guest module in step with discofetch.
#
#   ./sync-from-discofetch.sh [--from PATH]    # report drift, change nothing
#   ./sync-from-discofetch.sh --update         # copy the upstream file in
#
# The module in this repo is a BYTE-FOR-BYTE copy of discofetch's
# `api/supervisor.lua`, renamed to the extension the dollup format uses for a
# guest face. Byte-identity is the whole discipline: it makes drift a `cmp`
# rather than a code review, and it means this repo can never quietly become
# a second, divergent implementation of the API.
#
# So: edits belong upstream, in discofetch, and arrive here through this
# script. If you find yourself wanting to patch the .dlua directly, that is
# the signal that the code should move here for real -- which is a decision
# to make deliberately, not by drifting into it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vendored="$here/packages/discofetch-api/0.1.0/guest/api.dlua"
# The upstream repo was renamed discofetch -> discofetch-api; a local
# checkout may sit under either name, so try the new one and fall back.
upstream="${DISCOFETCH:-}"
if [ -z "$upstream" ]; then
    for cand in "$here/../discofetch-api" "$here/../discofetch"; do
        [ -r "$cand/api/supervisor.lua" ] && { upstream="$cand"; break; }
    done
    upstream="${upstream:-$here/../discofetch-api}"
fi
update=0

while [ $# -gt 0 ]; do
    case "$1" in
        --from)   upstream="$2"; shift 2 ;;
        --update) update=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

src="$upstream/api/supervisor.lua"
[ -r "$src" ] || {
    echo "no discofetch checkout at '$upstream'" >&2
    echo "  pass --from PATH, or set DISCOFETCH" >&2
    exit 2
}

if cmp -s "$src" "$vendored"; then
    echo "in step: $(sha256sum "$vendored" | cut -c1-16)… ($(wc -l < "$vendored") lines)"
    exit 0
fi

echo "DRIFT between the vendored module and $src"
diff <(sed 's/[[:space:]]*$//' "$vendored") <(sed 's/[[:space:]]*$//' "$src") | head -40 || true
echo "  ..."
echo "  upstream: $(sha256sum "$src"      | cut -c1-16)…"
echo "  vendored: $(sha256sum "$vendored" | cut -c1-16)…"

[ "$update" = 1 ] || {
    echo
    echo "pass --update to take the upstream copy, then re-seal:"
    echo "  dollup repo seal packages/discofetch-api/0.1.0 && dollup repo index ."
    exit 1
}

cp "$src" "$vendored"
echo
echo "updated. Now re-seal, or the manifest ships a stale hash:"
echo "  dollup repo seal packages/discofetch-api/0.1.0"
echo "  dollup repo index ."
echo
echo "and bump the package version if this is going out to anyone."
