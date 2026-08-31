-- 004 · waitlist
--
-- Registration is closed, so the front page takes an email instead. The
-- UNIQUE is the dedupe — there are no transactions, so INSERT OR IGNORE
-- against it is the whole concurrency story.
--
-- Emails only ever LEAVE this table through the operator's sqlite3. There
-- is deliberately no HTTP route that reads it: a public write endpoint is
-- a small risk, a public read endpoint here would be a breach of the one
-- promise a waitlist makes.

CREATE TABLE IF NOT EXISTS waitlist (
  id          INTEGER PRIMARY KEY,
  email       TEXT    NOT NULL UNIQUE,
  created_at  INTEGER NOT NULL,
  source      TEXT
) STRICT
;
