# reference

Not part of the package. Nothing here is delivered by `dollup add` — these are
the two things an operator needs beside the code and neither belongs inside a
package.

## `fetchpoint.host.lua` — the deployment

A working DRT config for the delivered package, copied from discofetch's
`api/api.dev.host.lua` with one line changed: `supervisor` names what dollup
materializes rather than a file in a checkout.

**Copy it; do not consume it in place.** Installing never grants — what the
program may do lives in this file, which is why dollup does not write it and
this repo only offers an example of one. It is the operator's file.

The lines a real deployment always edits:

| line | why |
|---|---|
| `sql.scope` | `data/` is relative to the host's cwd. Fine locally; wrong for a service — fetch1 uses an absolute path that systemd's `StateDirectory=` creates before `ExecStart`. |
| `crypto.key_file` | Must exist and hold at least 16 bytes, or the connector refuses to open and the deployment does not start. The host derives two subkeys and forgets the master; the guest never sees any of it. |
| `listen.port` | Host topology. The program does not know what port it is on and cannot bind one. |
| `supervisor` | Correct for the default code root (`code/`). If `dollup.json` names another, this must match. |

Before the first start, create the database **out of band, with WAL** —
`create = false` refuses to conjure one, deliberately, because a database the
connector creates comes up `journal_mode=delete`, which Litestream cannot
replicate and nothing can retrofit in place:

```sh
mkdir -p data
python3 -c "import sqlite3;c=sqlite3.connect('data/discofetch.sqlite');\
            c.execute('PRAGMA journal_mode=WAL');c.close()"
head -c 32 /dev/urandom > data/crypto.key && chmod 600 data/crypto.key
drt run reference/fetchpoint.host.lua
```

### Keep the flat connector spelling

Two spellings of a connector's scope exist and only one works from Lua. This
file already has the right one — it is discofetch's, and it is what runs on
fetch1 — so the trap is only in *editing* it:

```lua
-- CORRECT, and what is below: the C host's flat shape, which DRT also takes
sql = { scope = "/var/lib/discofetch", access = "readwrite", create = false },
```

```lua
-- WRONG from a .host.lua. This is DRT's JSON form, and from Lua it fails:
--   'host:fs': scope does not parse: invalid type: map, expected path string
sql = { scope = { scope = "/var/lib/discofetch", access = "readwrite" } },
```

The nested form is valid in a **JSON** config and invalid in a **`.host.lua`**,
so do not hand-translate DRT's `examples/deployment.json` into Lua. And
`access` is `"read"` or `"readwrite"` — never `"readonly"`.

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
is discofetch's `api/api.host.lua`. It is not copied here: one example is
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
