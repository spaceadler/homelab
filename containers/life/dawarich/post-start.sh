#!/usr/bin/env bash
# Dawarich's first start (db/seeds.rb, when there are no users yet) creates an
# admin, demo@dawarich.app, with the password "safepassword", which is in its
# public source. As soon as the app is up, swap that for the generated
# DAWARICH_ADMIN_PASSWORD. Does nothing once the password has been changed.
set -uo pipefail

for _ in $(seq 60); do
    [ "$($DOCKER inspect -f '{{.State.Health.Status}}' dawarich_app 2>/dev/null)" = healthy ] && break
    sleep 5
done

# shellcheck disable=SC2016 # Ruby code, expanded inside the container
if ! $DOCKER exec -e NEWPW="$DAWARICH_ADMIN_PASSWORD" dawarich_app bin/rails runner '
    u = User.find_by(email: "demo@dawarich.app")
    if u&.valid_password?("safepassword")
      u.update!(password: ENV["NEWPW"], password_confirmation: ENV["NEWPW"])
      puts "  Dawarich admin: demo@dawarich.app / DAWARICH_ADMIN_PASSWORD from .env"
      puts "  (change the email under Account once you are in)"
    end' 2>/dev/null; then
    echo "  ! Couldn't check Dawarich's default admin. If demo@dawarich.app / safepassword"
    echo "    logs in, change that password straight away."
fi
exit 0
