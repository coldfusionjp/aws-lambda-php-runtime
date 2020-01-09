FROM coldfusionjp/amazonlinux-clang:2018.03.0.20190514-llvmorg-9.0.1

# lock OS release and library versions to 2018.03 to match the environment that Lambda runs in
# see: https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html
RUN sed -i 's;^releasever.*;releasever=2018.03;;' /etc/yum.conf && \
	yum clean all && \
	yum install -y \
		curl-devel \
		diffutils \
		file \
		findutils \
		libxml2-devel \
		xz

# setup compile and link flags
WORKDIR /root
ARG CFLAGS="-Oz -ffunction-sections -fdata-sections"
ARG LDFLAGS="-Wl,--gc-sections -Wl,--as-needed -Wl,--strip-all"

# build and install oniguruma from source as it's no longer included with PHP 7.4+ (this is required so we can statically link it to PHP)
ARG ONIGURUMA_VERSION="6.9.1"
RUN curl -sL https://github.com/kkos/oniguruma/releases/download/v${ONIGURUMA_VERSION}/onig-${ONIGURUMA_VERSION}.tar.gz | tar xzv && \
	cd /root/onig-${ONIGURUMA_VERSION} && \
	CC="clang" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" ./configure --disable-shared --enable-static && \
	make -j $(nproc) && \
	make install

# download and decompress php source
ARG PHP_VERSION="php-7.4.0"
RUN curl -sL https://www.php.net/distributions/${PHP_VERSION}.tar.xz | tar xJv

# FIXME: patch PHP configure script to remove page size setting passed during the link stage, which generates an invalid executable with clang/lld
# see php commit: https://github.com/php/php-src/commit/62ded6efbcb41e24a505117f8de5b70d56a98f57
RUN yum install -y autoconf && \
	cd /root/${PHP_VERSION} && \
	sed -i 's/-Wl,-zcommon-page-size=2097152 -Wl,-zmax-page-size=2097152//g' configure.ac && \
	./buildconf --force

# build and install PHP from source
ARG PHP_OPTIONS="--enable-json --enable-filter --enable-mysqlnd --with-curl --with-mysqli=mysqlnd --enable-mbstring --with-mhash --with-libxml --enable-simplexml"
RUN cd /root/${PHP_VERSION} && \
	CC="clang" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" ONIG_CFLAGS="/usr/local/include" ONIG_LIBS="-L/usr/local/lib -lonig" ./configure --prefix=/opt/php --disable-cgi --disable-all ${PHP_OPTIONS} && \
	make -j $(nproc) && \
	make install

# run PHP tests (NOTE: currently disabled as three specific tests seem to be not fully supported when running inside Docker)
#RUN cd /root/${PHP_VERSION} && \
#	make test

# FIXME: just test the php binary actually runs
RUN echo "<?php phpinfo();" | /opt/php/bin/php

# strip final binary
RUN echo "Before strip:" && \
	ls -l /opt/php/bin/php && \
	strip /opt/php/bin/php && \
	echo "After strip:" && \
	ls -l /opt/php/bin/php
