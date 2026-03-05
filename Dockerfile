FROM apache/apisix:3.15.0-debian

USER root

# Install system dependencies for Test::Nginx and build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    cpanminus \
    build-essential \
    libpcre3-dev \
    libssl-dev \
    perl \
    curl \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Test::Nginx (Perl test framework used by APISIX)
RUN cpanm --notest Test::Nginx IPC::Run

USER apisix
