# Exposing the server over the internet (static IP + port forwarding)

The client side is done — TLS, certificate verification, a CA file and a
friendly offline notice all ship in the app. **None of it takes effect until
the server is configured**, and right now this server is not:

```
show ssl;   →  off
pg_hba.conf →  trust      (no password required at all)
```

`trust` means anything that reaches port 5432 is already inside, as any user,
before a password is ever discussed. On a loopback-only server that is
harmless. Forward that port and it is the entire database, public.

⚠️ **Do these three in order. Step 3 before step 1 locks you out.**

---

## 1. Give PostgreSQL a certificate

A self-signed CA is correct here: no public authority issues a certificate for
a bare IP address, and you do not need one — the app is told which CA to trust
(`PG_SSL_ROOT_CERT`), so it trusts exactly yours and nothing else.

Run on the server, in a scratch folder:

```bash
# The CA. This is what gets copied to every branch PC.
openssl req -new -x509 -days 3650 -nodes -out ca.crt -keyout ca.key \
  -subj "/CN=SL Customs SR CA"

# The server's own key and certificate, signed by that CA.
# ⚠️ CN must be EXACTLY what the branch PCs put in PG_HOST — the static IP or
#    the domain. verifyFull checks it, and a mismatch fails the handshake.
openssl req -new -nodes -out server.csr -keyout server.key \
  -subj "/CN=203.0.113.10"
openssl x509 -req -in server.csr -days 3650 \
  -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt
```

If the branch PCs will use a domain name, put the domain in `CN` instead, and
add both with a SAN extension if you need the IP as well.

Copy `server.crt` and `server.key` into the data directory (`PGDATA`), then:

```
# Windows: the service account must be able to read the key and nobody else.
icacls server.key /inheritance:r /grant:r "NT SERVICE\postgresql-x64-18:R"
```

## 2. Turn TLS on

In `postgresql.conf`:

```conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file  = 'server.key'

# Modern only. TLS 1.0/1.1 are broken and still offered by default.
ssl_min_protocol_version = 'TLSv1.2'

# The server picks the cipher, not the client.
ssl_prefer_server_ciphers = on

# Listen beyond loopback — but see step 4 before opening the router.
listen_addresses = '*'
```

Restart, then confirm:

```sql
show ssl;                      -- must be 'on'
select * from pg_stat_ssl;     -- 'ssl' true for a TLS-connected backend
```

## 3. Require TLS and a real password in `pg_hba.conf`

⚠️ **`hostssl`, not `host`.** `host` accepts a plaintext connection as
happily as a TLS one, so a client with `PG_SSL=false` silently gets exactly
what TLS was meant to prevent. `hostssl` refuses it server-side, which is the
half the client cannot be trusted to enforce on itself.

Replace the `trust` lines:

```conf
# TYPE      DATABASE        USER       ADDRESS          METHOD

# The server console itself.
local       all             all                         scram-sha-256
hostssl     all             all        127.0.0.1/32     scram-sha-256

# Branch offices. One line per branch, narrowest address you can get from the
# ISP. 0.0.0.0/0 works and means "the whole internet may attempt to log in".
hostssl     Customs_SR_DB   yard_app   198.51.100.7/32  scram-sha-256
hostssl     Customs_SR_DB   yard_app   198.51.100.8/32  scram-sha-256
```

Before reloading, make sure `yard_app` actually has a password —
`postgres/66_yard_app_role.sql` creates the role, but under `trust` it may
never have needed one:

```sql
alter role yard_app with password 'a-long-random-password';
-- and confirm the hash is SCRAM, not md5:
select rolname, substring(rolpassword for 14) from pg_authid
 where rolname = 'yard_app';   -- expect SCRAM-SHA-256
```

Then `select pg_reload_conf();` and test from another machine **before**
closing the old access.

## 4. The router, and what TLS does not cover

⚠️ TLS protects the traffic. It does not protect the port. A forwarded 5432 is
scanned continuously within hours of going live, and every scanner will try
`postgres/postgres` first.

- Forward to the **branch offices' own addresses** where the ISP gives them a
  static one. A source-restricted rule is worth more than everything above.
- Never forward as `postgres`. The app connects as `yard_app`, which is
  subject to the RLS policies that keep GL1 and GL2 apart; a superuser bypasses
  every one of them.
- Consider a non-standard external port (`56432 → 5432`). It stops nothing
  determined, but removes the app from the default scan.
- A VPN or an SSH tunnel is better than any of this. Port forwarding is the
  fallback when that is not available.

`fail2ban` or Windows Firewall rate-limiting on repeated auth failures is
worth adding — `log_connections = on` gives it something to read.

---

## 5. Each branch PC

In the `.env` beside the `.exe`:

```ini
PG_HOST=203.0.113.10          # exactly the certificate's CN
PG_PORT=5432
PG_DATABASE=Customs_SR_DB
PG_USER=yard_app
PG_PASSWORD=a-long-random-password

PG_SSL=true
PG_SSL_VERIFY=true
PG_SSL_ROOT_CERT=ca.crt       # ca.crt copied beside the .exe
PG_REQUIRE_TLS=true           # refuse to start rather than connect in clear

PG_CONNECT_TIMEOUT=20         # the internet is slower than a LAN
```

Copy **`ca.crt`** — never `ca.key`, and never `server.key`. The CA key signs
certificates; on a branch PC it is a key to forge the server's identity.

To verify a branch really has an encrypted, verified link:

```sql
select ssl, version, cipher, client_addr
  from pg_stat_ssl join pg_stat_activity using (pid)
 where usename = 'yard_app';
```

`ssl = false` for any row means that PC is connecting in clear and its `.env`
is wrong.

---

## What the app does on its own

- **Refuses to start** when `PG_REQUIRE_TLS=true` and the connection is not
  adequately secured — a mistyped `PG_SSL` becomes a startup failure instead
  of a silent plaintext connection.
- **Warns at startup** about plaintext to a remote host, about TLS without
  verification, and about a `PG_SSL_ROOT_CERT` that does not resolve.
- **Retries** transient failures (2 retries, backing off) and shows an offline
  strip naming the likely cause, clearing itself on the next successful query.
- **Normalises `PG_HOST`**, so a pasted connection string, a trailing `:5432`
  or a bare IPv6 literal all work.
