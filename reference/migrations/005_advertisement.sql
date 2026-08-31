-- 005 · advertisement
--
-- Runtime state, its own table rather than columns on fetchpoint: config
-- is owner intent and arrives by PATCH; this row is written by the
-- rendezvous dns verb OBSERVING a caller (advertise-by-showing-up), and
-- is what the DNS publisher — and one day the nameserver — reads.
-- Different write paths, different tables. A new table also needs no
-- ALTER, which matters because migrations 1–4 are frozen on fetch1 and
-- SQLite has no idempotent ADD COLUMN.

CREATE TABLE IF NOT EXISTS advertisement (
  fetchpoint_id  INTEGER PRIMARY KEY REFERENCES fetchpoint(id),
  address        TEXT    NOT NULL,
  at             INTEGER NOT NULL
) STRICT
;
