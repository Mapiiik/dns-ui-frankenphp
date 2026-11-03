# Opera DNS UI on FrankenPHP

Docker image for running **[Opera DNS UI](https://github.com/operasoftware/dns-ui)**, a web interface
for the PowerDNS API, on **FrankenPHP**.

This repository provides:
- a Docker build of the current `master` of Opera DNS UI with the PHP extensions it needs
- login through Caddy `basic_auth` or authentik (forward auth), the DNS UI takes the user name from it
- production Docker Compose setup with its own PostgreSQL
- automated CI that rebuilds the image on new commits of the DNS UI and base image updates

---

## 🚀 Features

- **FrankenPHP** runtime (Caddy + PHP in one process), automatic HTTPS
- **Non-root runtime**
- **Login required**: the container does not start without accounts in `users.caddy`, or without
  `AUTHENTIK_URL` with `AUTH_MODE=authentik`
- Notifications of the DNS UI delivered by **msmtp** (`mail()`), configured from the environment
- **Commit-driven CI**
  - scheduled builds only when Opera DNS UI has a new commit on `master` or `dunglas/frankenphp` a new image
  - forced rebuilds on pushes to `main`
- Images published to **GitHub Container Registry**

---

## 📦 Docker Images

Images are published to:
```
ghcr.io/mapiiik/dns-ui-frankenphp
```

Available tags:
- `latest` – latest build of Opera DNS UI `master`
- `master-<commit>` – specific commit of Opera DNS UI (e.g. `master-5309acd4cc5e`)
- `build-<commit>-<base>` – commit and base image digest, used by CI to skip unchanged builds
- `sha-<commit>` – infrastructure build reference

---

## 🐳 Usage (Production)

1. Copy the environment template:

```bash
cp .env.example .env
```

2. Set `SERVER_NAME` and `POSTGRES_PASSWORD`, and put two files in `DATA_DIR`:
   - `config.ini`, the configuration of the DNS UI; the template is in the image:
     ```bash
     docker run --rm --entrypoint cat ghcr.io/mapiiik/dns-ui-frankenphp /app/config/config-sample.ini > data/config.ini
     ```
     Keep `[php_auth] enabled = 1`, the login comes from Caddy. In `[database]` use
     `dsn = "pgsql:host=database dbname=dnsui"` and the user and password from `.env`.
   - `users.caddy` with the logins, made by `./add_user.sh` (see Users below). On a new installation the
     DNS UI creates its tables on the first request: start the stack, open the DNS UI once (it fails, the
     user is not in the database yet), and run `./add_user.sh` again for the same user. With
     `AUTH_MODE=authentik` an empty file is enough, Caddy does not read it.

3. Start the stack:

```bash
docker compose -f compose.production.yaml up -d
```
or
```bash
cp compose.production.yaml compose.yaml
docker compose up -d
```

## 👤 Users
The login name is the user of the DNS UI. Add a login, or set a new password, with `add_user.sh` next to the
compose file (with `compose.production.yaml`, set `COMPOSE_FILE=compose.production.yaml`):

```bash
./add_user.sh
```

It asks for the user name and the password (at least 17 characters, `MIN_PASSWORD_LENGTH` changes it),
writes the bcrypt hash to `users.caddy`, makes the file readable by the container user, and restarts the web
container. The DNS UI creates an unknown user only from `PHP_AUTH_NAME`, `PHP_AUTH_EMAIL` and
`PHP_AUTH_GROUPS`, which basic auth does not provide, so for a new user the script asks for the name and
e-mail and adds the user to the database.

To remove a login, delete its line from `users.caddy`, restart, and deactivate the user in the DNS UI.

### Login through authentik
With `AUTH_MODE=authentik` Caddy asks an authentik outpost about every request (forward auth) and passes
the user name, full name and e-mail to the DNS UI. `AUTHENTIK_URL` is the outpost; the embedded outpost
is authentik's own address, e.g. `https://login.example.com`. In authentik:

- a proxy provider in the mode *Forward auth (single application)* with the address of the DNS UI as the
  external host, added to that outpost, and an application with it; who may log in is set on the
  application (a group binding),
- the outpost finds the provider by `X-Forwarded-Host`. When authentik itself runs behind a proxy, that
  proxy has to trust the address the DNS UI connects from (Caddy: `trusted_proxies`), or it puts its own
  name in the header and the outpost does not find the provider.

The user name in authentik is the user of the DNS UI (`uid`). A user it does not know yet the DNS UI creates
on the first login, active but without admin rights; an administrator grants them on the user's page.
Users from basic auth keep their history when their `uid` is renamed to the authentik name, the change log
refers to the user by `id`. The DNS UI has no session of its own, the login lasts as long as the outpost's
(the provider's token validity), and `/outpost.goauthentik.io/sign_out` signs out.

`add_user.sh` and `users.caddy` are only for `AUTH_MODE=basic`, which stays the way back when authentik is
not available.

## ⚙️ Configuration
- `SERVER_NAME` (automatic ACME certificates; otherwise self-signed HTTPS)
- `LISTENER_MODE` (`direct` by default; `behind-proxy` behind an SNI proxy such as HAProxy, which owns
  port 80, so certificates come by the TLS-ALPN challenge; `internal` only on an internal network: Caddy
  issues the certificate from its own CA and `SERVER_NAME` can be the server's IP address. Browsers warn
  until they trust its root certificate, `/data/caddy/pki/authorities/local/root.crt` in the container)
- `PROXY_ALLOW` (where the PROXY protocol header is trusted from: the proxy's network; by default
  only this machine. The header is optional, so it works with or without a proxy)
- `AUTH_MODE` (`basic` by default, the accounts in `users.caddy`; `authentik` with `AUTHENTIK_URL`, see
  Login through authentik)
- `DATA_DIR` (default `./data`) holds `config.ini` and `users.caddy`, the database has its own Docker
  volume
- `POSTGRES_DB`, `POSTGRES_USER` (default `dnsui`), `POSTGRES_PASSWORD` for the bundled PostgreSQL
- `SMTP_HOST`, `SMTP_PORT` (default `25`, STARTTLS) for the notifications; without them set
  `[email] enabled = 0` in `config.ini`. msmtp has no queue: a server that greylists this address
  loses the message, so let it accept mail from here without greylisting
- `PGTZ` (default `UTC`), the time zone the change log is stored in; the DNS UI uses `NOW()`, so when
  moving an existing database keep the time zone of its old server

The DNS UI needs the PowerDNS API (`webserver-allow-from` must include the address this container
connects from). Expose it only to the networks of your administrators.

## 🧠 CI Behavior
- Scheduled runs read the head of `master` of Opera DNS UI and the base image digest, and build only
  when one of them changed.
- Pushes to main always trigger a rebuild.
- No repository changes are made by CI.

## 📄 License
See individual components for their respective licenses.
