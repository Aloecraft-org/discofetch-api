-- 003 · api_token
--
-- Restored as the readable source of supervisor.lua's MIGRATIONS entry —
-- versions 3 and 4 landed there without their .sql counterparts, and the
-- README's rule is that these files are where a human reads the schema.
-- Same rules as 001: one statement per piece, every statement idempotent,
-- no transactions.
--
-- The token itself is NEVER stored. `hash` is sha256 of the secret and is
-- the lookup key, so a copy of this database lets nobody authenticate as
-- anybody. Plain sha256 rather than a slow KDF on purpose: the secret is
-- 160 bits from crypto/random, so there is no dictionary to run. `prefix`
-- is stored separately so the panel can show which token a row refers to
-- without holding anything usable.

CREATE TABLE IF NOT EXISTS api_token (
  id             INTEGER PRIMARY KEY,
  account_id     INTEGER NOT NULL REFERENCES account(id),
  fetchpoint_id  INTEGER REFERENCES fetchpoint(id),
  name           TEXT    NOT NULL DEFAULT '',
  prefix         TEXT    NOT NULL,
  hash           TEXT    NOT NULL UNIQUE,
  scopes         TEXT    NOT NULL DEFAULT '[]',
  created_at     INTEGER NOT NULL,
  last_used_at   INTEGER,
  expires_at     INTEGER,
  revoked_at     INTEGER
) STRICT
;
CREATE INDEX IF NOT EXISTS api_token_by_account ON api_token(account_id)
;
