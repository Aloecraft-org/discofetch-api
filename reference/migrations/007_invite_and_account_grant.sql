-- 007 · invite, account_grant
--
-- Same two rules as everything before it: every statement runnable ALONE
-- (the sql connector prepares exactly one per call), and every statement
-- idempotent, because there are no transactions and a run can stop half
-- way. This file is the readable source; the statements the API applies
-- live pre-split in supervisor.lua's MIGRATIONS table — see
-- api/migrations/README.md for why that duplication is the deliberate
-- trade, and an edit that touches one must touch both.
--
-- The prelaunch mechanism, and BOTH tables land in ONE version on
-- purpose. Only `account_grant` has a reader today; `invite` has none
-- yet. They share a version anyway because a version that has run on
-- fetch1 can never be edited afterwards, so splitting them would cost the
-- invite slice a migration 008 for a table whose text is already settled
-- — and the two are one design: an invite CONFERS grants, and redeeming
-- one writes rows in the other.

-- `expires_at` and `revoked_at` are nullable and stay that way. The
-- connector refuses a nil bind ("SQL NULL is spelled NULL in the
-- statement text"), so every writer either leaves the column out of the
-- statement or spells NULL in the text — which is the same construction
-- log_event has always used for its optional columns.
--
-- `used_count` is read-modify-write with no transaction to protect it, so
-- two simultaneous redemptions of a code's last use can both succeed.
-- That is written down rather than discovered: the durable claim is the
-- account INSERT, protected by the UNIQUE on auth0_sub, so over-redemption
-- can never produce a duplicate account. `max_uses` is a throttle, not a
-- security boundary, and nothing in this design needs it to be one.
CREATE TABLE IF NOT EXISTS invite (
  code         TEXT    PRIMARY KEY,
  created_by   INTEGER REFERENCES account(id),   -- NULL: minted by the operator
  created_at   INTEGER NOT NULL,
  expires_at   INTEGER,
  max_uses     INTEGER NOT NULL DEFAULT 1,
  used_count   INTEGER NOT NULL DEFAULT 0,
  revoked_at   INTEGER,
  note         TEXT    NOT NULL DEFAULT '',
  confers      TEXT    NOT NULL DEFAULT '[]'     -- grants redeeming it creates
) STRICT
;
-- GET /v1/invites: "the codes I minted", newest first. The PRIMARY KEY
-- already serves the other access pattern — POST /v1/redeem looking a code
-- up whole — so this is the only index the table needs.
CREATE INDEX IF NOT EXISTS invite_by_creator ON invite(created_by, created_at DESC)
;

-- `account_grant`, not `grant`: SQLite would take the bare word, and a
-- reader who has used any other database would flinch at it.
--
-- One table for a tester's thank-you, a referral bonus and a paid pack,
-- because they differ only in `source`. Three tables each doing a third of
-- the job drift within a month, and the day billing lands it would be the
-- third of them that learns about expiry.
--
-- `spent` counts up for the countable kinds — name_credit, as names are
-- claimed. Nothing claims names yet: the column is modelled here with no
-- consumer, deliberately, because a balance is only honest if it was
-- counted from the day the grant was made.
CREATE TABLE IF NOT EXISTS account_grant (
  id           INTEGER PRIMARY KEY,
  account_id   INTEGER NOT NULL REFERENCES account(id),
  kind         TEXT    NOT NULL,   -- quota_bonus | tier_grant | name_credit
  quantity     INTEGER NOT NULL DEFAULT 0,
  detail       TEXT    NOT NULL DEFAULT '{}',
  source       TEXT    NOT NULL DEFAULT '',  -- operator | invite:<code> | offer:<name> | purchase
  offered_at   INTEGER NOT NULL,
  redeemed_at  INTEGER,
  expires_at   INTEGER,
  revoked_at   INTEGER,
  spent        INTEGER NOT NULL DEFAULT 0    -- for countable kinds
) STRICT
;
-- GET /v1/me's grants list and the account detail page: every grant on one
-- account, newest first. id DESC rather than offered_at DESC for the
-- reason both timelines page on id — two grants offered in the same second
-- are ordinary and `offered_at` cannot order them.
CREATE INDEX IF NOT EXISTS account_grant_by_account ON account_grant(account_id, id DESC)
;
-- quota_of's aggregate, which runs on the CREATE PATH: the sum of an
-- account's live bonuses, on every fetchpoint and every token minted.
-- Partial on the two clauses that are columns, so the index holds live
-- grants only — most rows here will be redeemed and unrevoked, but an
-- offered-and-never-accepted one is exactly what it must not scan. The
-- expiry clause stays in the query because it compares against now().
CREATE INDEX IF NOT EXISTS account_grant_live ON account_grant(account_id, kind)
  WHERE redeemed_at IS NOT NULL AND revoked_at IS NULL
;
