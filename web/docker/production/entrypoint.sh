#!/usr/bin/env bash
set -euo pipefail

cd /var/www/html

# Configuration comes from real environment variables (see the
# `environment:` blocks in docker-compose.prod.yml), not from a .env file
# baked into the image. Laravel falls back to process env vars when no
# .env file exists.
if [ -z "${APP_KEY:-}" ]; then
    echo "APP_KEY is not set. Generate one with 'php artisan key:generate --show' and set it in your stack's environment variables." >&2
    exit 1
fi

# The named volume mounted at storage/ starts empty on a fresh deployment,
# so make sure Laravel's expected subdirectories exist.
mkdir -p storage/app/public storage/framework/cache storage/framework/sessions \
         storage/framework/views storage/logs bootstrap/cache

php artisan storage:link --force || true

php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan event:cache

if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    php artisan migrate --force
fi

# The artisan commands above run as root; hand the caches back to the user
# php-fpm, reverb and the queue workers actually run as.
chown -R www-data:www-data storage bootstrap/cache

exec "$@"
