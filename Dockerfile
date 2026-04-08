# Dockerfile
# Debian-based test image for APISIX custom plugin development.
# Extends the official APISIX image and adds test-nginx + APISIX source tree.

FROM apache/apisix:3.15.0-debian

ARG APISIX_VERSION=release/3.15

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
RUN curl https://raw.githubusercontent.com/apache/apisix/master/utils/linux-install-luarocks.sh -sL | bash - \
    && git clone --branch ${APISIX_VERSION} --recurse-submodules \
        https://github.com/apache/apisix.git /usr/local/apisix-src \
    && cd /usr/local/apisix-src \
    && git submodule update --init t/toolkit \
    && make deps \
    && chmod -R a+r deps

# ── 5. etcd (bundled for single-container integration testing) ───────────────
ARG ETCD_VERSION=3.5.12
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    curl -fsSL "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${ARCH}.tar.gz" \
        -o /tmp/etcd.tar.gz; \
    tar -xzf /tmp/etcd.tar.gz --strip-components=1 \
        -C /usr/local/bin \
        "etcd-v${ETCD_VERSION}-linux-${ARCH}/etcd" \
        "etcd-v${ETCD_VERSION}-linux-${ARCH}/etcdctl"; \
    chmod +x /usr/local/bin/etcd /usr/local/bin/etcdctl; \
    rm /tmp/etcd.tar.gz

# ── 6. Environment ──────────────────────────────────────────────────────────
ENV APISIX_HOME=/usr/local/apisix-src
ENV PATH="/usr/local/openresty/nginx/sbin:/usr/local/openresty/luajit/bin:/usr/local/openresty/bin:${PATH}"

# ── 6. Standalone mode configuration ────────────────────────────────────────
# Override the default config.yaml with standalone (config_provider: yaml).
# apisix.yaml provides an empty-routes default so APISIX starts cleanly.
# Users may bind-mount their own apisix.yaml at runtime to supply routes.
COPY assets/conf/config.yaml /usr/local/apisix/conf/config.yaml
COPY assets/conf/apisix.yaml /usr/local/apisix/conf/apisix.yaml

# ── 7. Entrypoint & default command ─────────────────────────────────────────
# The entrypoint copies any custom plugins from the mounted volume before
# handing off to the command.  The default CMD starts APISIX in standalone
# mode; the test harness overrides this with `bash -c "prove …"`.
COPY assets/docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["apisix", "start"]
