# syntax=docker/dockerfile:1
FROM scratch AS composer-cache
COPY docker/composer-cache/ /

FROM composer:2 AS composer
FROM php:8.4-apache-bookworm AS development
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev libsqlite3-dev libzip-dev libpng-dev libonig-dev unzip git \
    && docker-php-ext-install -j2 pdo_pgsql pdo_sqlite bcmath zip gd mbstring \
    && rm -rf /var/lib/apt/lists/*
COPY --from=composer /usr/bin/composer /usr/local/bin/composer
RUN a2enmod rewrite \
    && sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf \
    && sed -i 's/:80>/:8080>/;s|/var/www/html|/var/www/html/public|' /etc/apache2/sites-available/000-default.conf \
    && printf '<Directory /var/www/html/public>\nAllowOverride All\nRequire all granted\n</Directory>\n' > /etc/apache2/conf-available/procash.conf \
    && a2enconf procash
WORKDIR /var/www/html
EXPOSE 8080

FROM development AS production
ARG COMPOSER_INSTALL_PREFERENCE=dist
COPY composer.json composer.lock ./
RUN --mount=type=cache,target=/tmp/composer-cache \
    --mount=type=bind,from=composer-cache,target=/opt/composer-cache \
    mkdir -p /tmp/composer-cache/files && cp -a /opt/composer-cache/. /tmp/composer-cache/files/ \
    && COMPOSER_CACHE_DIR=/tmp/composer-cache composer install --prefer-install="$COMPOSER_INSTALL_PREFERENCE" --no-dev --no-interaction --no-scripts --no-progress
COPY . .
RUN composer dump-autoload --optimize --no-dev --no-interaction \
    && chmod -R u=rwX,go=rX /var/www/html \
    && chown -R www-data:www-data storage bootstrap/cache /var/run/apache2 /var/lock/apache2
USER www-data
CMD ["apache2-foreground"]
