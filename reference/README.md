# reference

Not part of the package. Nothing here is delivered by `dollup add` — these are
the two things an operator needs beside the code and neither belongs inside a
package.

## `discofetch-api.config.json` — the deployment

A working DRT config for the delivered package, copied from discofetch's
`api/api.dev.config.json` with one line changed: `program` names what dollup
materializes rather than a file in a checkout.

**Copy it; do not consume it in place.** Installing never grants — what the
program may do lives in this file, which is why dollup does not write it and
this repo only offers an example of one. It is the operator's file.

The lines a real deployment always edits:

| line | why |
|---|---|
| `sql.scope` | `data/` is relative to the host's cwd. Fine locally; wrong for a service — use an absolute path that systemd's `StateDirectory=` creates before `ExecStart`. |
| `crypto.key_file` | Must exist and hold at least 16 bytes, or the connector refuses to open and the deployment does not start. The host derives two subkeys and forgets the master; the guest never sees any of it. |
| `listeners[0].address` | Host topology. The program does not know what port it is on and cannot bind one. |
| `program` | Correct for the default code root (`code/`). If `dollup.json` names another, this must match. A relative path resolves against the CONFIG's own directory since drt v0.6.0rc1, not the working directory. |

Before the first start, create the database **out of band, with WAL** —
`create = false` refuses to conjure one, deliberately, because a database the
connector creates comes up `journal_mode=delete`, which Litestream cannot
replicate and nothing can retrofit in place:

```sh
mkdir -p data
python3 -c "import sqlite3;c=sqlite3.connect('data/discofetch.sqlite');\
            c.execute('PRAGMA journal_mode=WAL');c.close()"
head -c 32 /dev/urandom > data/crypto.key && chmod 600 data/crypto.key
drt --config reference/discofetch-api.config.json start
```

### Keep the flat connector spelling

A connector's block sits inside `scope`, and that is the one shape change
worth knowing when editing this file:

```json
"sql": { "scope": { "scope": "/var/lib/discofetch", "access": "readwrite",
                    "create": false } }
```

The outer `scope` is what DRT passes to the connector **verbatim**; the inner
one is the sql connector's own word for a directory. Two consequences. A flat
block — `"sql": { "scope": "/var/lib/discofetch", … }` — is the shape a
`.host.lua` took, and copying one straight across reads as `missing field
host` or `scope does not parse`. And an underscore key inside that outer
`scope` is **data**, not a comment: the notes in this file's JSON all sit one
level out for that reason.

`.host.lua` itself is gone as of drt v0.6.0rc1, along with the `relay`, `stun`
and `turn` verbs and bare `drt wg`. If you are holding an old Lua config, the
keys are the same words — it is the connector blocks that move inside `scope`,
and `supervisor` that becomes `program: { "path": … }`.

The config below sidesteps this entirely by using `readwrite`, which every
version accepts. Only a read-only scope has to care.

### The connectors

The four the program needs wired — `sql`, `crypto`, `time`, and a
`listen` listener on the `http_in`/`http_out` queue pair. They are named here
rather than in the manifest's `requires.connectors` because that field wants a
call-shape version per connector and none is published yet; see the root
README.

Two allowlists in that file are load-bearing and easy to trim by accident:

- **`listen.headers`** — a header the deployment does not name never reaches
  the program, which cannot then learn it existed. `host` is how the one
  listener tells the API from a FetchPoint, so **dropping it makes every
  FetchPoint indistinguishable from every other**. `x-df-sub` is the gateway's
  verified assertion; `act-as` is the client's mere request, deliberately
  outside the `x-df-` namespace so nothing about the name suggests it was
  checked.
- **`listen.response_headers`** — what a reply may set. `location` serves the
  redirect kind, `cache-control` keeps a reflect answer from being cached into
  a wrong answer, `allow` and `www-authenticate` are what the 405 and 401 owe,
  `retry-after` rides every 429. An off-list name is dropped whole by the
  host, never cleaned — so a trimmed list fails silently, as a missing header
  rather than an error.

The production deployment (an absolute sql scope, `/etc/discofetch/crypto.key`)
is discofetch's `api/api.config.json`. It is not copied here: one example is
enough, and two would drift.

## `migrations/` — the readable schema

The `.sql` files that are the readable source of the program's embedded
`MIGRATIONS` table. The program does **not** read them: it has no `fs`
capability, and the statements are carried in the code pre-split, because the
connector prepares exactly one statement per call and splitting a blob at
runtime works until the first semicolon inside a string literal.

They are here to be read by a person, and to be diffed when the table changes.
Shipping them as package assets would mean granting an `fs` scope to a program
that does not want one.
