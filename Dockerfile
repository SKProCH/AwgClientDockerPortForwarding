# --- Stage 1: Build amneziawg-go (Userspace implementation) ---
FROM golang:alpine AS builder-go
RUN apk add --no-cache git
RUN go install github.com/amnezia-vpn/amneziawg-go@latest

# --- Stage 2: Build amneziawg-tools (awg command-line utility) ---
FROM alpine:3.19 AS builder-tools
RUN apk add --no-cache git make build-base libmnl-dev bash
RUN git clone https://github.com/amnezia-vpn/amneziawg-tools.git /tmp/tools
WORKDIR /tmp/tools/src
# Compile and install the awg binary to a temporary directory
RUN make install DESTDIR=/install

# --- Stage 3: Final runtime image ---
FROM alpine:3.19

# Install runtime dependencies
# bash: required for the awg-quick script to function
# openresolv: needed for DNS resolution handling
RUN apk add --no-cache bash iproute2 iptables libmnl iputils grep sed openresolv

# 1. Copy amneziawg-go (Go userspace implementation)
COPY --from=builder-go /go/bin/amneziawg-go /usr/bin/amneziawg-go

# 2. Copy awg binary (C implementation of the management utility)
COPY --from=builder-tools /install/usr/bin/awg /usr/bin/awg

# 3. Manually copy wg-quick script from sources and rename to awg-quick
# This resolves the "file not found" issue
COPY --from=builder-tools /tmp/tools/src/wg-quick/linux.bash /usr/bin/awg-quick

# 4. Create symlinks for compatibility
# The script internally may call 'wg', so we create a symlink wg -> awg
RUN chmod +x /usr/bin/amneziawg-go /usr/bin/awg /usr/bin/awg-quick && \
    ln -s /usr/bin/awg /usr/bin/wg && \
    ln -s /usr/bin/awg-quick /usr/bin/wg-quick

COPY start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]