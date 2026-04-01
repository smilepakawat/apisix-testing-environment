# Dockerfile.test
# Debian-based test image for APISIX custom plugin development.
# Extends the official APISIX image and adds test-nginx + APISIX source tree.

FROM apache/apisix:3.15.0-debian

USER root

ENV DEBIAN_FRONTEND=noninteractive

# ── 1. System dependencies ──────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cpanminus \
        git \
        curl \
        wget \
        unzip \
        make \
        sudo \
        libyaml-dev \
        libtest-base-perl \
        libtext-diff-perl \
        liburi-perl \
        libwww-perl \
        liblist-moreutils-perl \
        libpcre3-dev \
        libpcre2-dev \
    && rm -rf /var/lib/apt/lists/*

# ── 2. Perl modules (Test::Nginx and dependencies) ─────────────────────────
RUN cpanm --notest \
        Test::Nginx::Socket::Lua \
        IPC::Run \
    && rm -rf /root/.cpanm

# ── 3. Clone test-nginx (openresty fork) ────────────────────────────────────
RUN git clone --depth 1 https://github.com/openresty/test-nginx.git \
        /usr/local/test-nginx

# ── 4. Clone APISIX source (provides t/APISIX.pm, t/lib/, t/certs/, conf/) ─
ARG APISIX_VERSION=release/3.15
RUN curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash - \
    && git clone --branch ${APISIX_VERSION} --recurse-submodules \
        https://github.com/apache/apisix.git /usr/local/apisix-src \
    && cd /usr/local/apisix-src \
    && git submodule update --init t/toolkit \
    && make deps \
    && chmod -R a+r deps

# ── 5. Environment ──────────────────────────────────────────────────────────
ENV APISIX_HOME=/usr/local/apisix-src
ENV PATH="/usr/local/openresty/nginx/sbin:/usr/local/openresty/luajit/bin:/usr/local/openresty/bin:${PATH}"
ENV LUA_PATH="/usr/local/openresty/lualib/?.lua;/usr/local/openresty/lualib/?/init.lua;/usr/local/apisix-src/?.lua;./?.lua;;"
ENV LUA_CPATH="/usr/local/openresty/lualib/?.so;/usr/local/openresty/lualib/?/init.so;./?.so;;"

# ── 6. Install Busted (unit-test runner for Lua) ─────────────────────────────
RUN luarocks install busted
