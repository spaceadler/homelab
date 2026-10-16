#!/usr/bin/env bash
# Radicale reads logins from a bcrypt htpasswd file (/data/users in the image's
# config). Hash the password with the Python already inside the Radicale
# image, so the host needs no extra tools. Leaves an existing file alone.
set -euo pipefail

[ -s data/users ] && exit 0
mkdir -p data
hash=$($DOCKER run --rm -e PW="$RADICALE_PASSWORD" --entrypoint python cupcakearmy/radicale:1 \
    -c 'import bcrypt, os; print(bcrypt.hashpw(os.environ["PW"].encode(), bcrypt.gensalt()).decode())')
printf '%s:%s\n' "$RADICALE_USER" "$hash" > data/users
chmod 600 data/users
