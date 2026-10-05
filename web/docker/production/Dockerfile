# syntax=docker/dockerfile:1

#
# Production image for the OpenQDA web application.
#
# Builds PHP dependencies and frontend assets in isolated stages, then
# assembles a final runtime image running nginx + php-fpm + the Reverb
# websocket server + a queue worker, all supervised by supervisord.
#
# Build (from the `web` directory):
#   docker build -f docker/production/Dockerfile -t openqda-web:latest .
#

ARG PHP_VERSION=8.3
ARG NODE_VERSION=20

# ---------------------------------------------------------------------------
# Stage 1: PHP base - the platform both Composer and the runtime use
#
# Composer resolves platform requirements against the PHP it runs on, so
# dependencies must be installed on the same PHP version and extension set
# that will actually serve the app. (The `composer:2` image tracks the
# newest PHP, which this project's lock file does not allow.)
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-fpm-alpine AS php-base

RUN apk add --no-cache \
        bash \
        curl \
        tzdata \
        icu-data-full \
        libzip \
        libpng \
        libjpeg-turbo \
        freetype \
        oniguruma \
        libxml2 \
    && apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        libzip-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        oniguruma-dev \
        icu-dev \
        libxml2-dev \
        linux-headers \
    && docker-php-ext-configure gd --with-jpeg --with-freetype \
    && docker-php-ext-install -j"$(nproc)" \
        pdo_mysql \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        zip \
        intl \
        soap \
        sockets \
        opcache \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps \
    && rm -rf /tmp/pear /var/cache/apk/*

# ---------------------------------------------------------------------------
# Stage 2: install PHP dependencies
#
# Runs before the frontend stage because the asset build reads from
# vendor/ (see below). The classic (non-BuildKit) builder that Portainer
# uses can only reference stages defined earlier, so the order matters.
# ---------------------------------------------------------------------------
FROM php-base AS vendor

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-scripts \
    --no-autoloader \
    --no-interaction \
    --prefer-dist

COPY . .

# --no-scripts: package:discover would need a bootable app and a writable
# bootstrap/cache. Laravel regenerates the package manifest on the first
# artisan call in the runtime image instead.
RUN composer install \
    --no-dev \
    --no-scripts \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    && composer clear-cache

# ---------------------------------------------------------------------------
# Stage 3: build frontend assets (Vite/Vue)
#
# This stage needs the Composer vendor directory: the frontend imports
# Ziggy's JS and Jetstream's Vue components straight out of vendor/, and
# Tailwind's @source globs scan Blade files there too.
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS frontend

WORKDIR /app

COPY package.json package-lock.json ./
COPY plugins ./plugins
RUN npm ci

COPY resources ./resources
COPY public ./public
# plugins.js is the client plugin registry, imported from
# resources/js/Pages/analysis/visualization/useVisualizerPlugins.js.
COPY vite.config.js safarivite.config.js jsdoc.conf.json plugins.js ./
COPY --from=vendor /app/vendor ./vendor

# Vite inlines VITE_* values into the JS bundle at build time, so the
# websocket (Reverb) client settings must be known here - setting them on
# the running container has no effect. Changing the public Reverb
# host/port/scheme therefore requires rebuilding this image.
ARG VITE_REVERB_APP_KEY
ARG VITE_REVERB_HOST
ARG VITE_REVERB_PORT=443
ARG VITE_REVERB_SCHEME=https
ARG VITE_DEBUG_CLIENT=false
ARG VITE_NOTIFICATION=""

ENV VITE_REVERB_APP_KEY=${VITE_REVERB_APP_KEY} \
    VITE_REVERB_HOST=${VITE_REVERB_HOST} \
    VITE_REVERB_PORT=${VITE_REVERB_PORT} \
    VITE_REVERB_SCHEME=${VITE_REVERB_SCHEME} \
    VITE_DEBUG_CLIENT=${VITE_DEBUG_CLIENT} \
    VITE_NOTIFICATION=${VITE_NOTIFICATION}

RUN npm run build

# ---------------------------------------------------------------------------
# Stage 4: runtime image
# ---------------------------------------------------------------------------
FROM php-base AS runtime

LABEL org.opencontainers.image.title="OpenQDA" \
      org.opencontainers.image.description="OpenQDA web application (Laravel + Vue)"

ARG WWWUSER=1000
ARG WWWGROUP=1000

ENV TZ=UTC \
    APP_ENV=production

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && apk add --no-cache nginx supervisor

# Align the www-data user/group with the host UID/GID when provided, so
# volume contents keep sane ownership.
RUN deluser www-data 2>/dev/null || true; \
    delgroup www-data 2>/dev/null || true; \
    addgroup -g ${WWWGROUP} www-data && \
    adduser -D -u ${WWWUSER} -G www-data -s /bin/bash www-data

WORKDIR /var/www/html

COPY --chown=www-data:www-data . .
COPY --from=vendor --chown=www-data:www-data /app/vendor ./vendor
COPY --from=frontend --chown=www-data:www-data /app/public/build ./public/build

COPY docker/production/php.ini /usr/local/etc/php/conf.d/99-openqda.ini
COPY docker/production/php-fpm.conf /usr/local/etc/php-fpm.d/zz-openqda.conf
COPY docker/production/nginx.conf /etc/nginx/nginx.conf
COPY docker/production/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/production/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /var/log/supervisor /run/nginx storage/logs storage/framework/{cache,sessions,testing,views} bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache /var/log/supervisor /run/nginx

EXPOSE 80 8080

ENTRYPOINT ["entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "-n"]
