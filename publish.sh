#!/usr/bin/env bash
# Publish disco-fetchpoint as a dollup repo.
#
#   ./publish.sh --key-file ~/.dollup/disco-fetchpoint.key            # build + self-check
#   ./publish.sh --key-file ~/.dollup/disco-fetchpoint.key \
#                --deploy --target user@host:/srv/repo/            # and rsync
#
# Build is local and offline: seal, index, sign, project blobs, then resolve
# the staged repo in a throwaway deployment. Deploy is one rsync of that tree.
# A repo that cannot be added is not published -- that check is the point of
# the script, and it is why the last thing before rsync is `dollup verify`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
stage="${DOLLUP_STAGE:-$repo_root/.publish}"
target="${DOLLUP_TARGET:-}"
dollup="${DOLLUP_BIN:-}"
key_file="${DOLLUP_KEY_FILE:-}"
deploy=0

while [ $# -gt 0 ]; do
    case "$1" in
        --key-file) key_file="$2"; shift 2 ;;
        --deploy)   deploy=1; shift ;;
        --target)   target="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# dollup is not built from this repo, so find it rather than assume it: a
# sibling checkout is the common case, PATH is the installed one.
if [ -z "$dollup" ]; then
    for cand in \
        "$repo_root/../dollup/target/release/dollup" \
        "$repo_root/../dollup/target/debug/dollup" \
        "$(command -v dollup 2>/dev/null || true)"
    do
        [ -n "$cand" ] && [ -x "$cand" ] && { dollup="$cand"; break; }
    done
fi
[ -n "$dollup" ] && [ -x "$dollup" ] || {
    echo "no dollup binary found" >&2
    echo "  set DOLLUP_BIN, or build one:" >&2
    echo "    git clone https://github.com/Aloecraft-org/dollup ../dollup" >&2
    echo "    (cd ../dollup && cargo build --release)" >&2
    exit 2
}

[ -n "$key_file" ] || { echo "need --key-file (or DOLLUP_KEY_FILE)" >&2; exit 2; }
[ -r "$key_file" ] || {
    echo "cannot read key file: $key_file" >&2
    echo "  mint one:  $dollup repo keygen --out $key_file" >&2
    exit 2
}
# keygen --out writes `<prefix without extension>.pub`; a prefix with no
# extension gets `<prefix>.pub`. Accept either, and say which is missing.
pub_file="${key_file%.*}.pub"
[ -r "$pub_file" ] || pub_file="$key_file.pub"
[ -r "$pub_file" ] || {
    echo "cannot find the public key beside $key_file" >&2
    echo "  looked for: ${key_file%.*}.pub and $key_file.pub" >&2
    exit 2
}
pubkey="$(tr -d '\n' < "$pub_file")"

echo "==> sealing packages"
# Sealing is idempotent; running it here means a hand-edited module can never
# ship with a stale hash. `index` re-hashes independently regardless, so a
# stale seal is caught rather than believed.
for pkg in "$repo_root"/packages/*/*/; do
    [ -f "$pkg/manifest.json" ] || continue
    "$dollup" repo seal "$pkg" | head -1
done

echo "==> indexing"
"$dollup" repo index "$repo_root"

echo "==> signing"
"$dollup" repo sign "$repo_root" --key-file "$key_file"

echo "==> projecting blobs"
rm -rf "$repo_root/blobs"
"$dollup" repo blobs "$repo_root"

echo "==> staging into $stage"
rm -rf "$stage"
mkdir -p "$stage"
for item in index.json index.json.sig packages blobs; do
    [ -e "$repo_root/$item" ] && cp -r "$repo_root/$item" "$stage/"
done

echo "==> verifying the staged repo resolves"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
(
    cd "$tmp"
    "$dollup" init >/dev/null
    "$dollup" source add "file://$stage" --key "$pubkey" >/dev/null
    # Every package in the tree, not a chosen one: the point is that the
    # published repo resolves, all of it.
    for pkg in "$repo_root"/packages/*/; do
        "$dollup" add "$(basename "$pkg")" >/dev/null
    done
    "$dollup" verify
)

if [ "$deploy" = 1 ]; then
    # No default target, and the guard is not politeness: this rsync carries
    # --delete, so an empty target is a footgun and not merely a no-op.
    if [ -z "$target" ]; then
        echo "--deploy needs a target: --target user@host:/path, or DOLLUP_TARGET" >&2
        exit 2
    fi
    echo "==> deploying to $target"
    rsync -avz --delete "$stage"/ "$target"
else
    echo "built in $stage — pass --deploy with --target to rsync it"
fi
