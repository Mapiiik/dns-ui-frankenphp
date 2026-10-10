# Opera DNS UI on FrankenPHP

Docker image for running **[Opera DNS UI](https://github.com/operasoftware/dns-ui)**, a web interface
for the PowerDNS API, on **FrankenPHP**.

This repository provides:
- a Docker build of the current `master` of Opera DNS UI with the PHP extensions it needs
- login through Caddy `basic_auth`, the DNS UI takes the user name from it
- production Docker Compose setup with its own PostgreSQL
- automated CI that rebuilds the image on new commits of the DNS UI and base image updates

---

## 🚀 Features

- **FrankenPHP** runtime (Caddy + PHP in one process), automatic HTTPS
- **Non-root runtime**
- **Login required**: the container does not start without accounts in `users.caddy`
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
     user is not in the database yet), and run `./add_user.sh` again for the same user.

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

## ⚙️ Configuration
- `SERVER_NAME` (automatic ACME certificates; otherwise self-signed HTTPS)
- `LISTENER_MODE` (`direct` by default; `behind-proxy` behind an SNI proxy such as HAProxy, which owns
  port 80, so certificates come by the TLS-ALPN challenge)
- `PROXY_ALLOW` (where the PROXY protocol header is trusted from: the proxy's network; by default
  only this machine. The header is optional, so it works with or without a proxy)
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
