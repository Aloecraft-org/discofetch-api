# disco-fetchpoint

The FetchPoint program, packaged for [dollup](https://github.com/Aloecraft-org/dollup).

This repository is a **dollup repo**: an index, a signature and a package
tree. It carries one package, `discofetch-api`, whose guest face is the
[Diluvium](https://github.com/Aloecraft-org/diluvium) program that serves the
discofetch API and every FetchPoint on it — accounts, labels, tokens, the kind
registry, the rendezvous surface, quotas and traffic.

The code is extracted from [discofetch](https://github.com/Aloecraft-org/discofetch)
`api/supervisor.lua`, **byte for byte**. That is the discipline, not a
coincidence: see [Provenance](#provenance).

## Consuming it

```sh
dollup init
dollup source add https://dollup.aloecraft.org/disco-fetchpoint/ --key ed25519:…
dollup add discofetch-api
```

Three files arrive and nothing runs:

```
code/discofetch-api/manifest.json
code/discofetch-api/guest/api.dlua
dollup.lock
```

Installing never grants. What the program may do lives in your DRT config, and
writing that config is yours — dollup does not write it and neither does this
repo. [`reference/discofetch-api.host.lua`](reference/discofetch-api.host.lua) is a
working example to copy and edit; [`reference/README.md`](reference/README.md)
says which lines a real deployment always changes.

```sh
drt run reference/discofetch-api.host.lua     # after editing the scopes
curl -s localhost:8080/health
```

## The package

| | |
|---|---|
| name | `discofetch-api` |
| version | `0.1.0` |
| faces | guest only |
| entry module | `api` → `guest/api.dlua` |
| runnable | yes |

The package name is what the program already calls itself: `GET /health`
answers `{"service":"discofetch-api"}`. Keeping the two in step means a
running process and the package it was installed from say the same word.

```json
"requires": {
  "capabilities": ["queue:*", "host:sql/*", "host:time", "host:crypto/*"],
  "diluvium": ">=5.5.1"
}
```

Those four names are exactly `api.host.lua`'s `caps` line in discofetch — the
ceiling fetch1 serves production with, so the one the program is *known* to
run under.

**Nothing enforces this field today.** It is declarative: `dollup info` prints
it, and that is the whole of its current effect. Nothing checks it at add time
and nothing checks it at run time — the admission checks that will read it are
Phase 1 of an ask still open against DRT
([CodeResolution.md §5](https://github.com/Aloecraft-org/dollup/blob/main/doc/CodeResolution.md)).
A deployment that grants less than the manifest names therefore **starts**,
and then faults at the first call that needs what is missing. Measured, by
dropping `host:time` from the ceiling above:

```
drt start: http listening on 0.0.0.0:8080
bootstrap: agent:42: host.time: denied: 'time' is outside this instance's grants
drt: instance 1 faulted: agent:42: host.time: denied: 'time' is outside this
     instance's grants
```

Correct, and by name — but at the first call, not at admission. That is worth
knowing before you trim a ceiling.

It is written the way the deployment writes it rather than narrowed to
individual calls for the same reason: when the subset test does land it is a
test against the ceiling, and the glob semantics that would let
`host:sql/query` read as a subset of `host:sql/*` do not exist yet. The proven
ceiling cannot be wrong; the narrowed form could be.

**`requires.connectors` is deliberately absent.** The program needs four
connectors wired — `sql`, `crypto`, `time` and a `listen` listener — but that
field takes a *call-shape version requirement* per connector, and no such
version is published anywhere yet. An invented `^1` would be a fact this repo
does not have. The connectors are named in `reference/` instead, where an
operator needs them anyway, and the field lands the day the shapes are
versioned.

`diluvium: ">=5.5.1"` understates a real constraint: the program wants
**5.5.1_build11**, and specifically build10's reply-`headers` support, without
which the redirect kind cannot send `Location` and every refusal loses its
`Allow` / `WWW-Authenticate` / `Retry-After`. A build suffix is not semver and
`requires.diluvium` is a semver range, so the range says what it can and this
paragraph says the rest.

## One module, and why

The dollup format has a module map, and this package uses one entry in it.
That is upstream's constraint, quoted from discofetch's `api/README.md`:

> Guests have no `require` and no `dofile`, so the server is deliberately one
> file.

Splitting the program into `label.dlua`, `rooms.dlua`, `admin.dlua` and the
rest is the obvious next move and it is **not available yet**: a guest runs
sealed with no `package` library, so `require` and `dofile` are *nil* — not
merely unable to find a file. The pre-registered module set that would make
`require` resolvable is Phase 1 of an ask still open against DRT. Until that
lands, a multi-module package here would be a package that does not run.

`grep require` on the module finds 75 hits and **zero** real calls: they are
identifiers — `require_session`, `require_role`, `admin_required`. Worth
knowing before one of them is read as a module load.

The same constraint has a second half worth knowing, because it explains why
this package serves FetchPoints rather than delegating them: the listener
lands on the root instance only, so a spawned child cannot serve a route —
which is why `serve_fetchpoint` lives in this file rather than in per-
FetchPoint guests.

## Provenance

`packages/discofetch-api/0.1.0/guest/api.dlua` is `sha256` identical to
discofetch's `api/supervisor.lua` at the commit it was taken from. The only
change is the filename, because the dollup format's guest face uses `.dlua`.

Byte-identity is worth keeping. It turns "has this fork drifted?" into a
`cmp`, and it stops this repo becoming a second, divergent implementation of
an API that already exists and is deployed:

```sh
./sync-from-discofetch.sh --from ../discofetch     # report drift
./sync-from-discofetch.sh --from ../discofetch --update
```

Edits belong upstream and arrive here through that script. Wanting to patch
the `.dlua` directly is the signal that the code should move here for real —
a decision to make deliberately rather than to drift into.

Two consequences of copying the file unchanged, both intentional:

- Its comments reference `doc/…` and `deploy/…` paths. Those are **discofetch's**
  tree, not this one, and they were left alone rather than rewritten — a
  rewrite would break `cmp` on every sync for no gain in a comment.
- `reference/migrations/` carries the `.sql` files that are the readable
  source of the program's embedded `MIGRATIONS` table. They are reference, not
  package: the program has no `fs` capability and never reads them, and
  shipping them as package assets would mean granting one to a program that
  does not want it.

## Publishing

The repo is signed and consumers pin the public half. **The private key is not
in this repository and must never be** — a key in a git repo is not a key.

```sh
dollup repo keygen --out ~/.dollup/disco-fetchpoint.key    # 0600, refuses to overwrite
./publish.sh --key-file ~/.dollup/disco-fetchpoint.key           # build + self-check
./publish.sh --key-file ~/.dollup/disco-fetchpoint.key --deploy  # and rsync
```

`publish.sh` seals every package, indexes, signs, projects blobs, and then
**resolves the staged repo in a throwaway deployment before it will deploy
anything**. A repo that cannot be added is not published. It finds a `dollup`
binary at `../dollup/target/release/dollup` or on `PATH`; set `DOLLUP_BIN` to
override.

`index.json` **is** committed — a git or zipball source reads the tree
directly, and without an index in it there is no repo to read. It is
deterministic (hashes and paths only), so it diffs cleanly.

`index.json.sig` is **not** committed yet, for the reason dollup's own
std-repo gives: it would have to be signed with a key that does not exist.
Once the real key is minted, commit the signature beside the index so the git
and zipball sources verify the same way a mirror does.

Until then, add this repo as a source **without** `--key`. `dollup init`
writes `require_signatures: true`, but that rule is for *network* sources —
`file://` is exempt by design, so an unsigned local or rsynced copy resolves
fine. Pinning a key against a tree that carries no signature is refused, which
is the right answer and an easy one to walk into:

```
Error: file:///…: keys are pinned but the repo carries no index.json.sig
```

An unsigned `https://` source, by contrast, is refused at resolve time until
you pin a key or clear the flag — so sign before serving this over HTTPS. The
signature travels with the tree, so signing once covers all four transports.

`blobs/` is not committed either: it is a projection of the tree that
`publish.sh` rebuilds from empty.

## Changing the package

```sh
$EDITOR packages/discofetch-api/0.1.0/guest/api.dlua   # (but see Provenance)
dollup repo seal packages/discofetch-api/0.1.0                # rehash, rewrite `files`
dollup repo index .                                       # re-index, independently
```

Never hand-compute a hash: `seal` walks the directory and writes the `files`
map, and `index` re-hashes independently, so a stale seal is caught rather
than believed. Versions are directories, so several may coexist and a
consumer's requirement picks one.

## Verified

On **both runtimes**, from the package as dollup delivers it — resolved into a
deployment, then started from `code/` with `reference/discofetch-api.host.lua`:

- **DRT 0.1.0** (`drt --config … start`), which is what fetch1 runs — binary
  from the published release, sha256 checked against its `SHA256SUMS.txt`
- **diluvium-host 5.5.1_build11**, the C host

Identical results on both:

- `dollup add discofetch-api` → materialized; `dollup verify` → clean
- the delivered module is `sha256` identical to upstream `api/supervisor.lua`
- it starts, migrations apply, `GET /health` → `200 {"db":"ready"}`
- refusals are real: `404 no_route`, `401 unauthenticated`
- `GET /v1/me` → the account's quota and tier; `GET /v1/kinds` → the registry
- `POST /v1/fetchpoints` → a claimed label, and serving it by `Host` header
  answers for real: the redirect kind `302` carrying `location` and
  `cache-control`, the reflect kind the full `observed` address/port/edge
- reply headers work, which is the build10 dependency `requires.diluvium`
  cannot express: `405` carries `allow: GET, PATCH`

The negative case was measured too — see the capability note above.

## License

Apache-2.0, same as diluvium, DRT and dollup.
