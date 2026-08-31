---discofetch API — a REFERENCE deployment for the dollup-delivered package.
---
---This is an EXAMPLE, not the deployment. Copy it, change the scopes, and
---keep your copy: dollup never writes a DRT config, and this repo does not
---either. What a program may do lives in your config, not in the package —
---so the file that grants is the one file dollup must not own.
---
---`supervisor` names what dollup materialized. A deployment's code root
---defaults to `code/`, and a package lands under its own name, so the
---module this repo ships arrives at exactly the path below. If you set
---`code_root` to something else in dollup.json, change this line to match.
---
---The sql scope and the crypto key_file are the two lines a real deployment
---always edits. `data/` is relative to the host's cwd, which is fine for a
---local run and wrong for a service; fetch1 uses an absolute path that
---systemd's StateDirectory= creates. A config runs with an empty environment
--- -- "a config declares, it does not compute" -- so there is no variable to
---switch on: two deployments are two files.
---
---Before the first start, the database must exist WITH WAL, because
---`create = false` below refuses to conjure one (see the comment there):
---
---  python3 -c "import sqlite3;c=sqlite3.connect('data/discofetch.sqlite');\
---              c.execute('PRAGMA journal_mode=WAL');c.close()"
---  head -c 32 /dev/urandom > data/crypto.key && chmod 600 data/crypto.key
---
---The port is host topology, never a guest's choice. The program does not
---know what port it is on and cannot bind one.
---@type diluvium.HostConfig
return {
  supervisor = "code/fetchpoint/guest/fetchpoint.dlua",

  -- sql and time both have a consumer now: the migration runner and /v1/me.
  -- `time` is easy to forget and is not part of sql -- created_at is NOT
  -- NULL, and wall time in a guest is a hostcall like any other.
  caps = { "queue:*", "host:sql/*", "host:time", "host:crypto/*" },

  connectors = {
    time = true,

    -- Needed for crypto/random, which draws the 80 bits behind every label.
    -- The connector refuses to open without a signing key of at least 16
    -- bytes even though random never uses one, so this is a startup
    -- dependency and not a lazy one: no key, no deployment.
    --
    -- The host reads the file, derives two subkeys and forgets the master.
    -- The guest never sees any of it -- it calls crypto/* and the key stays
    -- outside its heap and outside its snapshot, which is the point of the
    -- connector holding it rather than the program.
    crypto = {
      key_file = "data/crypto.key",
    },

    sql = {
      -- Relative to the host's cwd, which is api/ under run.sh. Created by
      -- run.sh, gitignored, and disposable: `rm -rf api/data` is how you
      -- reset local state.
      scope = "data",
      access = "readwrite",

      -- The database is created out of band, with WAL, by deploy.sh. Saying
      -- create = false here is what makes a typo'd name
      --
      --   no database named 'discofecth.sqlite' in this deployment's scope,
      --   and creating one is not granted
      --
      -- instead of a silently-empty second file that looks exactly like data
      -- loss. It is not paranoia: a database the connector creates comes up
      -- journal_mode=delete (measured, 5.5.1_build9), which Litestream
      -- cannot replicate and nothing can retrofit in place.
      create = false,

      -- The cap REFUSES past this; it does not truncate. So every list query
      -- carries LIMIT and anything wide is aggregated in SQL. 256 is roomy
      -- for the per-account reads this API makes and small enough that a
      -- missing LIMIT fails loudly in development rather than in a year.
      max_result_rows = 256,
    },
    listen = {
      port = 8080,
      bind = "0.0.0.0",          -- in a container; 127.0.0.1 is the default
      queue = "http_in",         -- {conn, method, path, body, headers}
      reply_queue = "http_out",  -- {conn, status, body, content_type?}
      max_body = 65536,
      deadline_ms = 5000,
      max_conns = 64,

      -- Lowercase, and an allowlist: a header the deployment does not name
      -- never reaches the program, which cannot then learn it existed. Three
      -- of them, and they are not equally trustworthy -- which is most of
      -- why they are worth naming one at a time:
      --
      --   authorization  the caller's credential. An Auth0 JWT today, an
      --                  opaque dfp_live_ token later. Reported as
      --                  present/absent and never by value.
      --   x-df-sub       the gateway's ASSERTION. HAProxy strips every
      --                  inbound x-df- header and re-adds this one only
      --                  after it has verified the JWT, so it is the one
      --                  thing arriving here that is already established.
      --                  That strip is the entire reason it can be trusted.
      --   act-as         the client's REQUEST, deliberately outside the
      --                  x-df- namespace so that nothing about the name
      --                  suggests it was checked. Honoured only when the
      --                  account named by x-df-sub has role 'admin', and
      --                  ignored -- not refused -- for everyone else.
      --                  doc/DATA-MODEL.md §5.
      --
      -- The host joins repeated headers into one value with ", ", so a
      -- second x-df-sub would arrive concatenated to the first rather than
      -- as something the program could tell apart. HAProxy's `set-header`
      -- replaces, which is what keeps that unreachable; `add-header` would
      -- not, and the program has no way to notice the difference.
      --   host           which FetchPoint is being addressed. The API and
      --                  every FetchPoint arrive on the SAME listener, on
      --                  the same port, from the same backend -- so without
      --                  this the program cannot tell a request for
      --                  api.discofetch.net from one for
      --                  <label>.discofetch.link, and every FetchPoint in
      --                  existence is indistinguishable from every other.
      --                  It is the routing key, and it is the ONE header
      --                  here that the client controls end to end: nothing
      --                  upstream verifies it, so it may select a
      --                  FetchPoint and must never confer authority.
      --   x-real-ip      the EDGE'S observation of the caller: gate1 SETS
      --                  it from the connection it terminated, so unlike
      --                  x-forwarded-for (which proxies append to and a
      --                  client can seed) its value has one writer we own.
      --                  reflect reports it; the rendezvous dns verb
      --                  publishes it — observation, never claim.
      --   x-forwarded-for the whole relay chain, informational only.
      headers = { "authorization", "x-df-sub", "act-as", "host",
                  "x-real-ip", "x-forwarded-for",
                  -- The NAT-observation pair (doc/REFLECT-NAT.md), set by
                  -- the edge like x-real-ip: the terminated connection's
                  -- source port, and which edge terminated it. Eight names
                  -- now, under the per-direction cap of sixteen.
                  "x-real-port", "x-edge" },

      -- What a reply's `headers` map may set (build10; an off-list name is
      -- dropped whole by the host, never cleaned). location serves the
      -- redirect kind; cache-control because a reflect or advertise answer
      -- cached is a wrong answer; the CORS name because reflect is only
      -- half useful if a browser on someone else's page cannot call it;
      -- allow and www-authenticate are the two the API's refusals have
      -- owed since the stub; retry-after rides on every 429 the meter
      -- answers, computed from the bucket rather than guessed. The framing
      -- names (content-length, connection, content-type) are the host's
      -- and would be refused here by name.
      response_headers = { "location", "cache-control",
                           "access-control-allow-origin", "allow",
                           "www-authenticate", "retry-after" },
    },
  },
}
