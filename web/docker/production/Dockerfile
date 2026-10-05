# syntax=docker/dockerfile:1

#
# Production image for the OpenQDA web application.
#
# Builds frontend assets and PHP dependencies in isolated stages, then
# assembles a final runtime image running nginx + php-fpm + the Reverb
# websocket server + a queue worker, all supervised by supervisord.
#
# Build (from the `web` directory):
#   docker build -f docker/production/Dockerfile -t openqda-web:latest .
#

ARG PHP_VERSION=8.3
ARG NODE_VERSION=20

# ---------------------------------------------------------------------------
# Stage 1: build frontend assets (Vite/Vue)
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS frontend

WORKDIR /app

COPY package.json package-lock.json ./
COPY plugins ./plugins
RUN npm ci

COPY resources ./resources
COPY public ./public
COPY vite.config.js safarivite.config.js jsdoc.conf.json ./

RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2: install PHP dependencies
# ---------------------------------------------------------------------------
FROM composer:2 AS vendor

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-scripts \
    --no-autoloader \
    --no-interaction \
    --prefer-dist

COPY . .

RUN composer install \
    --no-dev \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    && composer clear-cache

# ---------------------------------------------------------------------------
# Stage 3: runtime image
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-fpm-alpine AS runtime

LABEL org.opencontainers.image.title="OpenQDA" \
      org.opencontainers.image.description="OpenQDA web application (Laravel + Vue)"

ARG WWWUSER=1000
ARG WWWGROUP=1000

ENV TZ=UTC \
    APP_ENV=production \
    SUPERVISOR_PHP_USER=www-data

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# System packages, nginx, supervisor and PHP build dependencies
RUN apk add --no-cache \
        nginx \
        supervisor \
        curl \
        bash \
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

# Align the www-data user/group with the host UID/GID when provided, so
# bind-mounted volumes (e.g. storage/) keep sane ownership.
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
