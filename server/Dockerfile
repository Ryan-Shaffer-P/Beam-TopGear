# Local BeamMP server for testing the Top Gear plugin.
# The repo's Resources/ folder is mounted in at runtime (see compose.yaml), so plugin
# edits only need a restart, not a rebuild.
FROM ubuntu:24.04

ARG BEAMMP_VERSION=v3.9.3
ARG TARGETARCH

# liblua5.3-0 + curl are BeamMP's runtime deps (scripts/ubuntu-24.04/4-install-runtime-deps.sh).
# lua5.3 is extra: the standalone interpreter/compiler, for exact-version syntax checks.
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends liblua5.3-0 lua5.3 curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /beammp
RUN case "$TARGETARCH" in \
      arm64) ARCH=arm64 ;; \
      amd64) ARCH=x86_64 ;; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o BeamMP-Server \
      "https://github.com/BeamMP/BeamMP-Server/releases/download/${BEAMMP_VERSION}/BeamMP-Server.ubuntu.24.04.${ARCH}" \
 && chmod +x BeamMP-Server

EXPOSE 30814/tcp 30814/udp
ENTRYPOINT ["./BeamMP-Server"]
