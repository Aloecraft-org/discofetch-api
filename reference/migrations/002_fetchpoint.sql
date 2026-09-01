-- 002 · label and fetchpoint
--
-- Same two rules as 001: every statement runnable ALONE (the sql connector
-- prepares exactly one per call), and every statement idempotent, because
-- there are no transactions to wrap a migration in and a run can stop half
-- way. The only safe answer to that is a migration that converges when
-- re-run.
--
-- This file is the readable source. The statements the API actually applies
-- live pre-split in supervisor.lua's MIGRATIONS table -- see
-- api/migrations/README.md for why that duplication is the deliberate trade.

-- The allocator. A label's life is longer than its FetchPoint's: it is
-- claimed here and the row is NEVER deleted, so the PRIMARY KEY by itself
-- guarantees a name can never be handed to a second owner. That is the
-- quarantine window doc/DATA-MODEL.md asks for, obtained by not deleting
-- rather than by tracking a window -- a resolver still holding the old
-- answer cannot reach a new owner, because there is never a new owner.
--
-- released_at, published_at and published_target are the DNS reconciler's
-- columns: what was withdrawn, what was last published, and to where. All
-- unused until the publisher seam is real (doc/12FACTOR.md §IV).
CREATE TABLE IF NOT EXISTS label (
  label             TEXT    PRIMARY KEY,   -- 16 base32 chars, DATA-MODEL §3.1
  fetchpoint_id     INTEGER,               -- NULL once released, or not yet set
  allocated_at      INTEGER NOT NULL,
  released_at       INTEGER,
  published_at      INTEGER,
  published_target  TEXT
) STRICT
;
CREATE TABLE IF NOT EXISTS fetchpoint (
  id                INTEGER PRIMARY KEY,

  -- owner_account_id rather than account_id: the only speculative concession
  -- in the schema, and it still costs nothing.
  owner_account_id  INTEGER NOT NULL REFERENCES account(id),

  -- The public id, and the subdomain. REFERENCES is documentation here and
  -- not enforcement -- foreign keys are off and the guest cannot enable them
  -- -- so integrity is the application's job, which is survivable precisely
  -- because nothing cascades.
  label             TEXT    NOT NULL UNIQUE REFERENCES label(label),

  name              TEXT    NOT NULL,      -- the human's label, freely editable

  -- Immutable after creation: it selects the handler template, so changing it
  -- means a different program, which means a different FetchPoint. Validated
  -- on the way in for that reason.
  kind              TEXT    NOT NULL,

  config            TEXT    NOT NULL DEFAULT '{}',   -- kind-specific JSON
  host              TEXT    NOT NULL DEFAULT 'fetch1',  -- so a second is possible
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL,
  deleted_at        INTEGER                -- soft delete; the label survives it
) STRICT
;
-- Partial, so it covers live rows only. The dashboard's query is always
-- "mine, not deleted", which makes the index the size of the answer rather
-- than the size of the history.
CREATE INDEX IF NOT EXISTS fetchpoint_live_by_owner
  ON fetchpoint(owner_account_id) WHERE deleted_at IS NULL
;
