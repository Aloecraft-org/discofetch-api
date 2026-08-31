-- 006 · event
--
-- Same two rules as everything before it: every statement runnable ALONE
-- (the sql connector prepares exactly one per call), and every statement
-- idempotent, because there are no transactions and a run can stop half
-- way. This file is the readable source; the statements the API applies
-- live pre-split in supervisor.lua's MIGRATIONS table — see
-- api/migrations/README.md for why that duplication is the deliberate
-- trade, and an edit that touches one must touch both.
--
-- The event log: what was DONE, as against what was served. Two account
-- columns rather than one, because "who" splits in two the moment staff
-- can act on a customer's behalf. `account_id` is the SUBJECT — whose
-- timeline the row belongs to, and who is entitled to read it. `actor_id`
-- is WHO DID IT. They are equal for every action a person takes on their
-- own account, and the day they differ is exactly the day an impersonated
-- change would otherwise be invisible to the person it happened to. That
-- day is why both columns exist now rather than after impersonation
-- lands: a column added later cannot describe the rows written before it.
--
-- CONTROL PLANE ONLY: creates, deletes, mints, revokes, settings —
-- decisions someone made. Never reads, room joins or DNS advertisements.
-- Those are the in-memory meter's job (TRAFFIC) and must stay there: a
-- durable row per dns update, across every name, on a 30s cadence, is
-- millions of rows a week written to a sqlite file that does not yet have
-- backups.
--
-- `detail` is JSON on purpose. A new fact about an event then costs a key
-- rather than a migration, which matters more here than anywhere else in
-- the schema: this table has no ALTER available to it (SQLite has no
-- idempotent ADD COLUMN, and migrate() re-runs a migration that stopped
-- half way), so every column it will ever have is in this statement.
-- Nothing secret goes in it — these rows are read back by the customer
-- over GET /v1/events and by anyone holding an audit account.
--
-- Retention is 90 days, enforced by the program rather than by the
-- schema: log_event trims on one insert in two hundred, and the
-- supervisor trims once at startup because that counter is process-local
-- and this service is restarted more often than it writes two hundred
-- events.

CREATE TABLE IF NOT EXISTS event (
  id             INTEGER PRIMARY KEY,
  at             INTEGER NOT NULL,
  account_id     INTEGER REFERENCES account(id),
  actor_id       INTEGER REFERENCES account(id),
  actor_role     TEXT    NOT NULL DEFAULT 'user',
  kind           TEXT    NOT NULL,
  fetchpoint_id  INTEGER REFERENCES fetchpoint(id),
  label          TEXT,
  detail         TEXT    NOT NULL DEFAULT '{}',
  address        TEXT
) STRICT
;
-- The customer's own timeline, which is the only query with a WHERE on
-- this table that a person waits for: newest first, one account at a time.
CREATE INDEX IF NOT EXISTS event_by_account ON event(account_id, at DESC)
;
-- The operator's view over everyone, and the retention sweep's scan.
CREATE INDEX IF NOT EXISTS event_recent ON event(at DESC)
;
