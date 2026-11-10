FROM debian:trixie-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates curl xz-utils && \
    curl -fsSL https://nim-lang.org/download/nim-2.2.0-linux_x64.tar.xz -o /tmp/nim.tar.xz && \
    tar -xJf /tmp/nim.tar.xz -C /opt && \
    ln -s /opt/nim-2.2.0/bin/nim /usr/local/bin/nim && \
    ln -s /opt/nim-2.2.0/bin/nimble /usr/local/bin/nimble && \
    rm -f /tmp/nim.tar.xz && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -m -u 1000 -s /bin/bash appuser
WORKDIR /work
COPY --chown=1000:1000 . /work
USER 1000:1000
RUN /bin/sh scripts/test-offline.sh && /bin/sh scripts/demo-offline.sh --assert

FROM debian:trixie-slim AS runtime
RUN useradd -m -u 1000 -s /bin/bash appuser && \
    test ! -x /usr/bin/gcc && test ! -x /usr/local/bin/nim
WORKDIR /work
COPY --from=builder /work/dist/bounded-canonical-prefix /usr/local/bin/bounded-canonical-prefix
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/bounded-canonical-prefix"]
CMD ["demo", "--assert"]
