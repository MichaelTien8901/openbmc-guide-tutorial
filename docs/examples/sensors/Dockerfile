FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    g++ meson ninja-build pkg-config \
    libsystemd-dev libboost-all-dev nlohmann-json3-dev \
    git ca-certificates python3 python3-yaml python3-mako python3-inflection \
    dbus \
    && rm -rf /var/lib/apt/lists/*

# Build and install sdbusplus from source
RUN git clone --depth 1 https://github.com/openbmc/sdbusplus /tmp/sdbusplus && \
    cd /tmp/sdbusplus && \
    meson setup builddir -Dexamples=disabled -Dtests=disabled && \
    meson compile -C builddir && \
    meson install -C builddir && \
    ldconfig && \
    rm -rf /tmp/sdbusplus

ENV PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig

COPY . /examples
WORKDIR /examples

RUN meson setup builddir && meson compile -C builddir

ENTRYPOINT ["/examples/entrypoint.sh"]
CMD ["demo"]
