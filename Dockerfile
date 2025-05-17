# supported runtimes and deprecation dates: https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html
# os-only runtimes: https://docs.aws.amazon.com/lambda/latest/dg/runtimes-provided.html

ARG LAMBDA_ARCH="arm64"
ARG LAMBDA_RUNTIME="al2023"
FROM public.ecr.aws/lambda/provided:${LAMBDA_RUNTIME}-${LAMBDA_ARCH}

ARG PHP_VERSION="8.4.7"
ARG PHP_REQUIRED_PACKAGES="libcurl-devel libxml2-devel openssl-devel sqlite-devel bzip2-devel libpng-devel libwebp-devel libjpeg-devel libicu-devel oniguruma-devel libxslt-devel libzip-devel"
ARG PHP_OPTIONS="--disable-cgi --disable-phpdbg --enable-bcmath --with-bz2 --with-curl --enable-exif --enable-filter --enable-ftp --with-gettext --enable-gd --with-jpeg --with-webp --with-iconv --enable-json --enable-mbstring --enable-mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --enable-opcache --with-openssl --enable-sockets --with-xsl --with-zip --with-zlib"

# setup environment to build php
RUN dnf install -y \
	${PHP_REQUIRED_PACKAGES} \
	bzip2 \
	g++ \
	tar

# download and decompress php source
WORKDIR /root
RUN curl -sL https://www.php.net/distributions/php-${PHP_VERSION}.tar.bz2 | tar xjv

# build from source and install
RUN cd php-${PHP_VERSION} && \
	./configure --prefix=/opt/php ${PHP_OPTIONS} && \
    make -j $(nproc) && \
    make install

# just test the php binary actually runs
RUN echo "<?php phpinfo();" | /opt/php/bin/php

# copy php binary and required dynamic libraries
RUN mkdir -p /root/php-runtime/bin /root/php-runtime/lib && \
	cp /opt/php/bin/php /root/php-runtime/bin && \
	ldd /root/php-runtime/bin/php | grep '=>' | awk '{ print $3 }' | \
	while read -r lib; do \
		realpath=$(readlink -f "$lib"); \
		linkname=$(basename "$lib"); \
		case "$linkname" in \
			ld-*.so*|libc.so*|libm.so*|libdl.so*|librt.so*|libpthread.so*|libgcc_s*.so*|libstdc++.so*) continue ;; \
		esac; \
		cp -u "$realpath" "/root/php-runtime/lib/$linkname"; \
	done

# strip debug info
RUN find /root/php-runtime -type f -exec strip --strip-all -- {} + || true

# build a .zip of the php binary and all dynamic libraries
RUN zip -v -9 -r -D php-runtime.zip php-runtime/*

ENTRYPOINT [ "/bin/bash" ]
