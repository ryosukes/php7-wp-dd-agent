FROM php:7.2.4-apache
INCLUDE PHP_INSTRUCTIONS
INCLUDE PHP_OPCACHE_INSTRUCTIONS

RUN docker-php-ext-install mysqli

RUN a2enmod ssl rewrite headers \
    && a2dismod -f autoindex

RUN set -ex \
    && . "$APACHE_ENVVARS" \
    && rm -rvf /var/app/current \
    && mkdir -p /var/app/current \
    && chown -R "$APACHE_RUN_USER:$APACHE_RUN_GROUP" /var/app/current

RUN a2enmod cache cache_disk

RUN set -ex \
    && rm -rvf /var/cache/apache2/mod_cache_disk \
    && mkdir -p /var/cache/apache2/mod_cache_disk \
    && chown -R root:root /var/cache/apache2/mod_cache_disk \
    && chmod 775 /var/cache/apache2/mod_cache_disk

RUN pecl install xdebug-2.9.1 \
    && docker-php-ext-enable xdebug

RUN set -ex \
  && curl -Lo datadog-php-tracer.apk https://github.com/DataDog/dd-trace-php/releases/download/0.47.0/datadog-php-tracer_0.47.0_noarch.apk \
  && apk add --no-cache datadog-php-tracer.apk --allow-untrusted \
  && rm datadog-php-tracer.apk

WORKDIR /var/app/current

ENTRYPOINT ["/root/run-script.sh"]
CMD ["apache2-foreground"]
