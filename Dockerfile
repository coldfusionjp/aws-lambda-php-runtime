FROM coldfusionjp/amazonlinux-clang:2018.03.0.20190514-llvmorg-8.0.1

# lock OS release and library versions to 2018.03 to match the environment that Lambda runs in
# see: https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html
RUN sed -i 's;^releasever.*;releasever=2018.03;;' /etc/yum.conf && \
	yum clean all && \
	yum install -y \
		curl-devel \
		diffutils \
		file \
		xz

# download and decompress PHP source
ARG PHP_VERSION="php-7.3.6"
RUN cd /root && \
	curl -sL https://www.php.net/distributions/${PHP_VERSION}.tar.xz | tar xJv

# compile and strip final binary
ARG PHP_OPTIONS="--enable-json --enable-filter --enable-mysqlnd --with-curl --with-mysqli=mysqlnd --enable-mbstring --with-mhash"
ARG CFLAGS="-Oz -ffunction-sections -fdata-sections"
ARG LDFLAGS="-Wl,--plugin-opt=O2 -Wl,--gc-sections -Wl,--as-needed -Wl,--strip-all"
RUN cd /root/${PHP_VERSION} && \
	./configure --prefix=/opt/php --disable-cgi --disable-all ${PHP_OPTIONS} CC="clang" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" && \
	make -j $(nproc) && \
	make install && \
	echo "Before strip:" && \
	ls -l /opt/php/bin/php && \
	strip /opt/php/bin/php && \
	echo "After strip:" && \
	ls -l /opt/php/bin/php
