FROM php:8.3-cli

WORKDIR /app

# Datadog PHP Kafka integration requires ext-rdkafka (RdKafka\ProducerTopic::producev).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         curl ca-certificates unzip $PHPIZE_DEPS librdkafka-dev libpq-dev \
    && pecl install rdkafka-6.0.5 \
    && printf '\n\n\n\n\n' | pecl install redis \
    && docker-php-ext-enable rdkafka redis \
    && docker-php-ext-install sockets pdo pdo_mysql pdo_pgsql \
    && curl -LO https://github.com/DataDog/dd-trace-php/releases/latest/download/datadog-setup.php \
    && php datadog-setup.php --php-bin=all \
    && rm -f datadog-setup.php \
    && curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && apt-get purge -y --auto-remove $PHPIZE_DEPS \
    && rm -rf /var/lib/apt/lists/* /tmp/pear

COPY composer.json ./
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress \
    && rm -rf /root/.composer/cache

COPY index.php /app/index.php

EXPOSE 8003

CMD ["php", "-S", "0.0.0.0:8003", "index.php"]
