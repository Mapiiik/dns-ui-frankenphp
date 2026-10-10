#!/bin/bash
# Adds a login to the DNS UI, or sets a new password for an existing one. Run it next to the compose file.
# The DNS UI cannot create users from basic auth on its own, so a new user also gets a row in its database.
set -euo pipefail
cd "$(dirname "$0")"

web=dns-ui-web
db=database
min_length=${MIN_PASSWORD_LENGTH:-17}

env_value() { sed -n "s/^$1=//p" .env 2>/dev/null | tail -1 | tr -d '"'; }
data_dir=$(env_value DATA_DIR)
file="${data_dir:-./data}/users.caddy"
image=$(docker compose config --images | grep -m1 dns-ui)
[ -n "$image" ] || { echo "No dns-ui image in the compose file here" >&2; exit 1; }

read -rp "User name: " user
[[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Only letters, digits, dot, dash and underscore" >&2; exit 1; }
read -rsp "Password: " pw; echo
read -rsp "Password again: " pw2; echo
[ "$pw" = "$pw2" ] || { echo "The passwords differ" >&2; exit 1; }
unset pw2
[ "${#pw}" -ge "$min_length" ] || { echo "The password needs at least $min_length characters" >&2; exit 1; }

# The password goes in on stdin, so it never shows in the process list
hash=$(printf '%s\n' "$pw" | docker run --rm -i "$image" frankenphp hash-password)
unset pw
[[ "$hash" == '$2'* ]] || { echo "No bcrypt hash came back: $hash" >&2; exit 1; }

# Rewritten in place: the container has the file mounted on its own and would keep seeing the old one
touch "$file"
{ awk -v u="$user" '$1 != u' "$file"; echo "$user $hash"; } > "$file.new"
cat "$file.new" > "$file"
rm -f "$file.new"

uid=$(docker run --rm --entrypoint id "$image" -u)
chown "$uid:$uid" "$file"
chmod 600 "$file"
if docker run --rm --entrypoint sh -v "$(realpath "$file"):/check:ro" "$image" -c 'test -r /check'; then
    echo "users.caddy: $(stat -c '%U:%G %a' "$file"), readable by the container user ($uid)"
else
    echo "users.caddy is not readable by the container user ($uid)" >&2
    exit 1
fi

if docker compose ps --status running --services | grep -qx "$db"; then
    sql() { docker compose exec -T "$db" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1 "$@" -f -' sh "$@"; }
    # The DNS UI creates its tables on the first request it serves
    tables=$(sql <<< "SELECT to_regclass('public.\"user\"') IS NOT NULL;")
    state=
    [ "$tables" = t ] && state=$(sql -v uid="$user" <<< "SELECT active FROM \"user\" WHERE uid = :'uid';")
    if [ "$tables" != t ]; then
        echo "The DNS UI has not created its tables yet: start it, open it once, then run this again for $user" >&2
    elif [ -z "$state" ]; then
        echo "$user is not in the DNS UI yet"
        read -rp "Full name: " name
        read -rp "E-mail: " email
        read -rp "Administrator? [y/N] " admin
        [[ "$admin" =~ ^[YyAa] ]] && admin=1 || admin=0
        sql -v uid="$user" -v name="$name" -v email="$email" -v admin="$admin" <<< \
            "INSERT INTO \"user\" (uid, name, email, active, admin, auth_realm) VALUES (:'uid', :'name', :'email', 1, :admin, 'PHP_AUTH');" >/dev/null
        echo "$user added to the DNS UI"
    elif [ "$state" = 0 ]; then
        read -rp "$user is deactivated in the DNS UI, activate? [y/N] " activate
        if [[ "$activate" =~ ^[YyAa] ]]; then
            sql -v uid="$user" <<< "UPDATE \"user\" SET active = 1 WHERE uid = :'uid';" >/dev/null
            echo "$user activated"
        fi
    fi
else
    echo "The database is not running, the user has to exist in the DNS UI before the first login" >&2
fi

if docker compose ps --status running --services | grep -qx "$web"; then
    docker compose restart "$web"
else
    echo "Start the DNS UI with: docker compose up -d"
fi
