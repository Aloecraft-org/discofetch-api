-- 001 · account
--
-- Every statement is separated by a bare `;` on its own line and must be
-- runnable ALONE: the sql connector prepares exactly one statement per
-- call and refuses trailing text, so the runner splits this file and
-- executes the pieces one at a time.
--
-- Every statement is also idempotent. There are no transactions to wrap a
-- migration in (the connector's authorizer denies BEGIN), so a run can
-- stop half way -- and the only safe answer to that is a migration that
-- converges when re-run.

CREATE TABLE IF NOT EXISTS account (
  -- Internal only. Never appears in a URL or a response: /v1/me needs no
  -- identifier, and fetchpoints are addressed by their label.
  id            INTEGER PRIMARY KEY,

  -- The identity HAProxy injects as x-df-sub after verifying the JWT.
  -- An external key: nothing else in the schema foreign-keys to it, so a
  -- future identity provider changes this column and nothing else.
  auth0_sub     TEXT    NOT NULL UNIQUE,

  -- A cache of what the IdP last told us, refreshed at login. Auth0 owns
  -- the truth; this exists so the panel can show something without a
  -- round trip, and so support can find an account by email.
  email         TEXT,

  -- Quota limits are looked up FROM this, not stored per row -- the
  -- numbers are policy and belong in one place, the tier is the account's.
  tier          TEXT    NOT NULL DEFAULT 'free',

  -- 'user' | 'admin'. Authorization is ours, identity is Auth0's -- so this
  -- is a column here rather than a claim in the token, and the gateway goes
  -- on asserting exactly one thing (x-df-sub) and never a privilege.
  -- No endpoint sets it: granting admin is an UPDATE run by whoever holds
  -- the database. See doc/DATA-MODEL.md §5.
  role          TEXT    NOT NULL DEFAULT 'user',

  created_at    INTEGER NOT NULL,          -- unix seconds, everywhere
  last_seen_at  INTEGER,
  suspended_at  INTEGER                    -- abuse control; signup is open
) STRICT;
;
-- Support looks accounts up by email; it is not unique, because an IdP can
-- hand the same address to two subs (different connections) and refusing
-- the second login is worse than allowing two rows.
CREATE INDEX IF NOT EXISTS account_by_email ON account(email)
;
