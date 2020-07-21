FROM php:7.2.4-apache

# php instructions

ENV NVM_DIR      /root/.nvm
ENV NVM_VERSION  0.33.9
ENV NODE_VERSION 8.11.1
ENV NODE_PATH    $NVM_DIR/versions/node/v$NODE_VERSION/lib/node_modules
ENV PATH         $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH
ENV COMPOSER_ALLOW_SUPERUSER 1
ENV LC_CTYPE C.UTF-8

RUN apt-get update && apt-get install -y \
        curl \
        gnupg2 \
        git \
        procps \
        ffmpeg \
        tmux \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
    && docker-php-ext-install -j$(nproc) iconv \
    && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install pdo_mysql \
    && docker-php-ext-install zip \
    && docker-php-ext-install bcmath \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
RUN set -ex \
  && php -r "copy('https://raw.githubusercontent.com/composer/getcomposer.org/master/web/installer', 'composer-setup.php');" \
  && php composer-setup.php \
  && php -r "unlink('composer-setup.php');" \
  && mv composer.phar /usr/local/bin/composer \
  && chmod 755 /usr/local/bin/composer

# Install NVM and Node
RUN mkdir -p $NVM_DIR \
    && curl -o- https://raw.githubusercontent.com/creationix/nvm/v$NVM_VERSION/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION

# Add www-data to root group, so that it has write permissions to storage/framework/views
RUN usermod -a -G root www-data

# Increase upload size limit to 4 MB
COPY ./upload_limit.ini /usr/local/etc/php/conf.d/uploads.ini

# Install New Relic PHP agent
RUN echo 'deb http://apt.newrelic.com/debian/ newrelic non-free' | tee /etc/apt/sources.list.d/newrelic.list \
    && curl -o- https://download.newrelic.com/548C16BF.gpg | apt-key add - \
    && apt-get update \
    && apt-get install -y newrelic-php5 \
    && NR_INSTALL_SILENT=true newrelic-install install \
    && rm -rf /var/lib/apt/lists/*

# Other shell scripts
RUN echo '#!/bin/bash\nls -lah "$@"' > /usr/local/bin/ll \
    && chmod 755 /usr/local/bin/ll

RUN { \
        echo '#!/bin/sh'; \
        echo 'sed -i.bak s/PHP\ Application/$NEWRELIC_APPNAME/g /usr/local/etc/php/conf.d/newrelic.ini'; \
        echo 'sed -i.bak s/REPLACE_WITH_REAL_KEY/$NEWRELIC_LICENSE/g /usr/local/etc/php/conf.d/newrelic.ini'; \
        echo 'usermod -u 500 www-data'; \
        echo 'groupmod -g 500 www-data'; \
    } > /root/run-script.sh \
    && chmod +x /root/run-script.sh


# php opcache instructions

RUN docker-php-ext-install opcache

RUN { \
        echo 'opcache.enable=1'; \
        echo 'opcache.validate_timestamps=VALIDATE_TIMESTAMPS'; \
        echo 'opcache.revalidate_freq=REVALIDATE_FREQ'; \
        echo 'opcache.save_comments=1'; \
        echo 'opcache.fast_shutdown=0'; \
    } >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini

RUN { \
        head -n -1 /root/run-script.sh; \
        echo 'sed -i.bak s/VALIDATE_TIMESTAMPS/${VALIDATE_TIMESTAMPS:-0}/g /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini'; \
        echo 'sed -i.bak s/REVALIDATE_FREQ/${REVALIDATE_FREQ:-2}/g /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini'; \
        echo 'exec $@'; \
    } > /root/run-script-opcache.sh \
    && mv /root/run-script-opcache.sh /root/run-script.sh \
    && chmod +x /root/run-script.sh


# other php extensions

RUN docker-php-ext-install mysqli

RUN a2enmod ssl rewrite headers \
    && a2dismod -f autoindex

RUN a2enmod cache cache_disk

RUN set -ex \
    && rm -rvf /var/cache/apache2/mod_cache_disk \
    && mkdir -p /var/cache/apache2/mod_cache_disk \
    && chown -R root:root /var/cache/apache2/mod_cache_disk \
    && chmod 775 /var/cache/apache2/mod_cache_disk

RUN pecl install xdebug-2.9.1 \
    && docker-php-ext-enable xdebug

# datadog php tracer

RUN set -ex \
  && curl -Lo datadog-php-tracer.apk https://github.com/DataDog/dd-trace-php/releases/download/0.47.0/datadog-php-tracer_0.47.0_noarch.apk \
  && apk add --no-cache datadog-php-tracer.apk --allow-untrusted \
  && rm datadog-php-tracer.apk

RUN set -ex \
    && . "$APACHE_ENVVARS" \
    && rm -rvf /var/app/current \
    && mkdir -p /var/app/current \
    && chown -R "$APACHE_RUN_USER:$APACHE_RUN_GROUP" /var/app/current

WORKDIR /var/app/current

ENTRYPOINT ["/root/run-script.sh"]
CMD ["apache2-foreground"]
