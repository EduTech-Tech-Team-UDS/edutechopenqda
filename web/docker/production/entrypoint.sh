#!/usr/bin/env bash
set -euo pipefail

cd /var/www/html

# Configuration is expected to come from real environment variables (see
# docker-compose.prod.yml's `env_file`), not a .env file baked into the
# image. Laravel falls back to process env vars when no .env file exists.
if [ -z "${APP_KEY:-}" ]; then
    echo "APP_KEY is not set. Generate one with 'php artisan key:generate --show' and set it in your env file." >&2
    exit 1
fi

php artisan storage:link --force || true

php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    php artisan migrate --force
fi

exec "$@"
