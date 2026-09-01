# FetchPoint types

Every FetchPoint has exactly one **kind**, chosen when it is created and
**immutable afterwards** — a reflect cannot become a rendezvous. Changing your
mind means making a new one, and the old label is never reissued.

Seven kinds are registered. Three serve; four are declared and answer `501`
until their slices land.

## The list

| kind | title | status | what it does |
|---|---|---|---|
| `system:reflect` | Reflect | **serving** | Tells the caller what it looks like from outside: observed address, method, path. Stateless. |
| `system:rendezvous` | Rendezvous | **serving** | A meeting point. The owner advertises an observed address; readers find it there. Optionally holds rooms. |
| `system:redirect` | Redirect | **serving** | Answers every request with a redirect to a fixed URL. |
| `collab-draw` | Collaborative draw | roadmap | — |
| `collab-text` | Collaborative text | roadmap | — |
| `wireguard` | WireGuard | roadmap | — |
| `iot` | IoT rendezvous | roadmap | — |

The four roadmap kinds are **real registry entries**: they can be created and
rows may carry them. It is the serving surface that answers `501`, not the
create call. They declare no config fields yet.

## URL shapes

A FetchPoint is reached at its own name. Some kinds add **verbs**, which hang
off a reserved `--` separator — which is why user-facing labels never contain
one.

```
<label>.discofetch.link            the kind itself
<label>--<verb>.discofetch.link    one of that kind's verbs
```

---

## `system:reflect` — Reflect

Answers with what the caller looks like from outside. Stateless: it reads
nothing and stores nothing.

`reflect.discofetch.link` answers everyone for free. Your own named one adds
your traffic counters, your tier's rate limits, and a name your scripts can
keep. It exists from the first boot as an ordinary row owned by the system
account, which makes it the permanent end-to-end canary — if reflect answers,
then DNS, the edge, the hub, the listener and the database all work.

| config field | type | what it does |
|---|---|---|
| `format` | `json` \| `text` | `json` (default) answers the whole observation. `text` answers the bare address and a newline, for `ip=$(curl -s https://<name>.discofetch.link)` — because parsing JSON on a router's busybox is not a thing to ask of anyone. `?format=` overrides per request; `?format=addr-port` answers `ADDRESS PORT` for NAT diagnostics. |
| `debug_forwarded` | `false` \| `true` | Echo the raw relay chain, internal hops included. Off, the public answer drops private-range entries. |

No verbs. **Cannot redirect** — sending a caller to its own address is a loop.
**Has no rooms** — the field does not exist for this kind.

---

## `system:rendezvous` — Rendezvous

A meeting point: a stable name that points at an address which may move. The
owner advertises; readers look it up.

| config field | type | what it does |
|---|---|---|
| `advertise_key` | string, 16–128, secret | Bearer the owner presents on `--dns` to advertise. Generated at create. Send a new value to rotate, `""` to remove. |
| `address_override` | ip | Pin the name to this address. While set it wins over anything advertised; clear it to hand control back. |
| `serve` | `json` \| `redirect` \| `dns` | What the name does. `json` answers the address (default); `redirect` sends callers *to* it, so the name works in a browser before DNS does; `dns` publishes an A record and takes us out of the path entirely. |
| `serve_scheme` | `http` \| `https` | Scheme a redirect sends callers to. Default `http`. |
| `serve_port` | port | Port a redirect sends callers to. Default none. |
| `rooms` | `false` \| `true` | Allow `?room=` meeting rooms: many candidate lists under one name, held **in memory only**, expiring on their own. |
| `room_auth` | `key` \| `pin` \| `open` | Who may join and read a room. An unguessable room name plus `open` is the secret-meeting-id pattern; joins are rate limited per name either way. |
| `room_pin` | string, 4–32, secret | The short human-typeable secret, when `room_auth` is `pin`. |
| `room_capacity` | 4 \| 16 \| 64 | Candidates a room holds. Default 16. |
| `room_ttl` | 60 \| 300 \| 3600 | Seconds a candidate stays without re-joining. Default 300. Presence, not history. |

**Verbs**

| URL | what it does |
|---|---|
| `<label>--dns.discofetch.link` | **Advertise by showing up.** The owner presents `advertise_key` and the *observed* address — never a supplied one — is recorded. Same address again is a heartbeat, not history. |
| `<label>--join.discofetch.link` | **Enter a room as a candidate.** Address observed, `?port=` supplied (WireGuard needs one and the edge cannot observe UDP), `?name=` optional. Answers the current list — one round trip is a whole rendezvous. |
| `<label>.discofetch.link?room=` | **Read a room**, through the same door as joining: a meeting's membership is as private as its entrance. |

**Three tiers of address state**, deliberately in three places: `address_override`
is config (the owner's intent, durable, wins every read); `advertisement` is a
database row (the last report, durable, what the DNS publisher reads); **room
candidates are memory only and never touch disk** — presence, not history.

---

## `system:redirect` — Redirect

Answers every request with a redirect to a fixed URL.

| config field | type | what it does |
|---|---|---|
| `target` | url, **required**, ≤2048 | Where to send callers. `http://` or `https://` only. |
| `status` | 301 \| 302 \| 307 \| 308 | The redirect status. Default 302. |

No verbs, no rooms.

---

## What is *not* a type yet

**There is no ICE kind, and no ICE fetchpoint.** This is the question that gets
asked most, so it is worth stating plainly rather than leaving to inference:
the shipped code contains no `ufrag`, no ICE candidates, no `ice_servers`, no
TURN credential vending, and no `--ice` verb.

The nearest thing that exists is `system:rendezvous` with `rooms: true`, whose
room entries are keyed `address#port` and hold one candidate each. ICE would
invert that — one peer, many candidates, keyed by ufrag — which is a change to
this program, not a config setting.

The design for it is `doc/ICE.md` in the [discofetch](https://github.com/Aloecraft-org/discofetch)
repo, and its central decision is that ICE **grows `system:rendezvous` rather
than adding a kind** — precisely because `kind` is immutable, so a separate
`system:ice` would strand anyone who picked the meeting-place card and later
needed ICE.

## Where the truth lives

Three layers, each deferring upward:

1. **`packages/discofetch-api/0.1.0/guest/api.dlua`** — the `KINDS` table is the
   authority. Everything else is a transcription.
2. **`GET /v1/kinds`** — the registry at runtime, machine-readable. One
   definition with two consumers: the validator behind `POST`/`PATCH
   /v1/fetchpoints`, and the panel's create form. Prefer it over any document,
   including this one.
3. **This file**, and upstream's `doc/CONFIG-TRUTH-TABLE.md` — human-readable.
   `CONFIG-TRUTH-TABLE.md` additionally maps the five create-flow intents onto
   the three serving kinds and says which config controls the panel may show.

If this file and the registry ever disagree, **the registry wins and this file
is stale**. To check it against a running server:

```sh
curl -s -H "Authorization: Bearer $DFP_TOKEN" \
  https://api.discofetch.net/v1/kinds | jq '.kinds[] | {kind, implemented}'
```
