# Migrations

> Copied from discofetch `api/migrations/`. It says `supervisor.lua`; in this
> repo that file is the package's guest module,
> `packages/discofetch-api/0.1.0/guest/api.dlua` — the same bytes under the
> extension the dollup format uses for a guest face.

Numbered `.sql` files, applied in order at startup, recorded in
`schema_migration`. No tooling — the API applies them itself (the runner
sketched below now lives at the top of `supervisor.lua`), which is
factor XII's "admin tasks run against the same release" with the
smallest possible machinery. The sandbox cannot read these files, so the
supervisor carries the SQL in a Lua table — **these files remain the
readable source of that table**, and an edit that touches one must touch
both.

Three rules, all forced by the sql connector rather than chosen:

**One statement per call.** The connector prepares exactly one statement
and refuses anything after it, so the runner splits each file and
executes the pieces separately. The runner strips `--` comments *before*
splitting on `;` — otherwise a semicolon inside a comment silently cuts a
statement in half, which is the kind of thing that works until the day
someone writes prose with a semicolon in it.

**Every statement idempotent.** There are no transactions — the
authorizer denies `BEGIN` — so a migration can stop half applied and
there is nothing to roll back. `CREATE TABLE IF NOT EXISTS`,
`CREATE INDEX IF NOT EXISTS`, and the version row written **only after
every statement in the file succeeded**. A re-run then converges instead
of failing on what already exists.

**Forward only.** No down migrations. Reverting a schema change means
writing the next one.

The corollary: **a migration may be edited only while it has never been
applied anywhere that matters.** `001` and `002` are in that state today —
the runner exists (see below) and local test databases are created and
thrown away by `./run.sh`, but no deployment on fetch1 has opened a real
database yet. That editability is why `002` could absorb the
live-rows-only unique index (`fetchpoint_label_live`) the day the
soft-delete/label-reuse collision was found, rather than costing an `003`.
The day fetch1 first runs, both freeze. The distinction matters here more
than in most projects: SQLite has no `ADD COLUMN IF NOT EXISTS`, so an
`ALTER` cannot be made idempotent, and idempotence is not optional when
there are no transactions. After the freeze, the next change costs a
numbered migration with that wrinkle to solve.

## The runner

Bootstrap first — the runner cannot consult a table it has not created:

```sql
CREATE TABLE IF NOT EXISTS schema_migration (
  version    INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL
) STRICT
```

Then, for each file in numeric order whose version is absent from that
table: split on `\n;\n`, `db.exec` each non-empty piece, and only then
insert the version row.

```lua
local db = host.sql.open('discofetch.sqlite')
db.exec([[CREATE TABLE IF NOT EXISTS schema_migration (
  version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL) STRICT]])

local done = {}
for _, r in ipairs(db.query('SELECT version FROM schema_migration').rows) do
  done[r[1]] = true
end

for _, m in ipairs(MIGRATIONS) do    -- {version=1, statements={[[...]], ...}}
  if not done[m.version] then
    for _, stmt in ipairs(m.statements) do db.exec(stmt) end
    db.exec('INSERT INTO schema_migration (version, applied_at) VALUES (?, ?)',
            m.version, now())
  end
end
```

**Statements are stored pre-split, not split at runtime.** An earlier draft of
this file carried a splitter that stripped `--` comments and then split on
`;`. It works on `001` and on most of what follows it, and then one day a
migration contains a semicolon or a double dash inside a string literal and it
cuts a statement in half — silently, because both halves are plausible SQL
right up until one fails. A Lua array of statements has no such day, and the
`.sql` files remain the readable source of the table either way.

The cost is that the SQL exists twice: here, and in `supervisor.lua`. That is
a real drift risk and the honest trade against granting `fs` to read these
files at startup, which would be a capability wired for one consumer that the
release could carry instead.

The files are not readable from inside the sandbox unless the `fs`
connector is wired at a scope containing them, so the simplest thing is
to keep the SQL in a Lua table the program carries — the migration text
is part of the release, which is where factor V wants it anyway. These
`.sql` files stay the readable source of that table.

## SQLite version

`STRICT` needs SQLite 3.37+, and **nothing in the runtime image supplies
SQLite**: `diluvium-host` is built on alpine 3.20 and statically linked
against `sqlite-static`, so it carries its own regardless of what the box
has. That was load-bearing while fetch1 was Alpine 3.15, whose system
sqlite is 3.36 — one release short of `STRICT`, so the CLI could not have
read what the API wrote. On Debian 12 the box's own `sqlite3` is well past
3.37 and the two agree, which makes hand-inspection work again.

The property is worth keeping even though the conflict is gone: the
version the API sees is a property of the pinned release, not of the box,
so `STRICT` cannot break under a distro upgrade. A glibc host build would
give that up — `make build_host` links `-lsqlite3` dynamically — which is
the trade to weigh if one is ever cut.

## WAL

Set it once, out of band, before the API opens the file:

```sh
sqlite3 /var/lib/discofetch/discofetch.sqlite 'PRAGMA journal_mode=WAL'
```

The connector denies `PRAGMA` to guests and sets only `busy_timeout`, so
the program cannot do this itself — and Litestream requires WAL. Journal
mode persists in the file, so once is enough.

**Once per database, not once per box.** A database the connector creates
itself comes up `journal_mode=delete`; that is measured against
5.5.1_build9, not assumed. Since the guest can never change it, every
database this deployment will ever name has to be created in the
provisioning step, and the deployment then says `create = false` so a
typo'd name is a refusal rather than a fresh un-replicated file.
