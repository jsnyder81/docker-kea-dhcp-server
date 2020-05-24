FROM alpine:latest as builder

ARG KEA_DHCP_VERSION=1.7.4
ARG LOG4_CPLUS_VERSION=2.0.5
ARG LOG4_CPLUS_TAG=REL_2_0_5

RUN apk add --no-cache --virtual .build-deps \
        alpine-sdk \
        bash \
        boost-dev \
        bzip2-dev \
        file \
        libressl-dev \
        mariadb-dev \
        zlib-dev && \
    curl -sL https://github.com/log4cplus/log4cplus/releases/download/${LOG4_CPLUS_TAG}/log4cplus-${LOG4_CPLUS_VERSION}.tar.gz | tar -zx -C /tmp && \
    cd /tmp/log4cplus-${LOG4_CPLUS_VERSION} && \
    ./configure && \
    make -s -j$(nproc) && \
    make install && \
    curl -sL https://ftp.isc.org/isc/kea/${KEA_DHCP_VERSION}/kea-${KEA_DHCP_VERSION}.tar.gz | tar -zx -C /tmp && \
    cd /tmp/kea-${KEA_DHCP_VERSION} && \
    ./configure \
        --enable-shell \
        --with-dhcp-mysql=/usr/bin/mysql_config && \
    make -s -j$(nproc) && \
    make install-strip && \
    apk del --purge .build-deps && \
    rm -rf /tmp/*

FROM alpine:latest
LABEL maintainer="jorin.vermeulen@gmail.com"
LABEL org.label-schema.schema-version="1.0"
LABEL org.label-schema.version=$KEA_DHCP_VERSION

RUN apk --no-cache add \
        bash \
        boost \
        bzip2 \
        libressl \
        mariadb-connector-c \
        mariadb-connector-c-dev \
        zlib

COPY --from=builder /usr/local /usr/local/

ENTRYPOINT ["/usr/local/sbin/kea-dhcp4"]
CMD ["-c", "/usr/local/etc/kea/kea-dhcp4.conf"]