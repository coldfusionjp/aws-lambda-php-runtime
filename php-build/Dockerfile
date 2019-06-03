FROM amazonlinux:2018.03.0.20190514

ARG PHP_VERSION="7.3.6"

# lock OS release and library versions to 2018.03 to match the environment that Lambda runs in
# see: https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html
RUN sed -i 's;^releasever.*;releasever=2018.03;;' /etc/yum.conf && \
	yum clean all && \
	yum install -y \
		diffutils \
		file \
		gcc-c++ \
		xz

# download PHP source, compile, and strip final binary
RUN cd /root && \
	curl -sL https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz | tar xJv && \
	cd php-${PHP_VERSION} && \
	./configure --prefix=/opt/php --disable-cgi --disable-all --enable-json --enable-mysqlnd --with-mysqli=mysqlnd --enable-mbstring --with-mhash CFLAGS="-Os" && \
	make -j4 install && \
	strip /opt/php/bin/php
