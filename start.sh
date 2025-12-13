#!/bin/bash

sysctl -w net.ipv4.conf.all.src_valid_mark=1

# Path to the original configuration file
ORIG_CONF="/config/awg0.conf"
# Path to the working copy
WORK_CONF="/etc/amnezia/amneziawg/awg0.conf"
# Routing table custom (random) number
RT_TABLE=51820
# PersistentKeepalive interval in seconds (default: 25)
# Set to 0 to disable, or configure via PERSISTENT_KEEPALIVE environment variable
PERSISTENT_KEEPALIVE="${PERSISTENT_KEEPALIVE:-25}"

if [ ! -f "$ORIG_CONF" ]; then
    echo "Config file not found at $ORIG_CONF"
    exit 1
fi

# 1. Preparation
mkdir -p $(dirname $WORK_CONF)
if ! mkdir -p /dev/net; then
    echo "Failed to create /dev/net directory"
    exit 1
fi
if [ ! -c /dev/net/tun ]; then
    if ! mknod /dev/net/tun c 10 200; then
        echo "Failed to create /dev/net/tun device"
        exit 1
    fi
fi

# 2. Copy config and disable built-in routing table
cp "$ORIG_CONF" "$WORK_CONF"
sed -i "/^Table/d" "$WORK_CONF"
sed -i "/\[Interface\]/a Table = $RT_TABLE" "$WORK_CONF"

# 3. Add PersistentKeepalive to [Peer] section if configured
if [ "$PERSISTENT_KEEPALIVE" -gt 0 ] 2>/dev/null; then
    # Remove any existing PersistentKeepalive settings
    sed -i "/^PersistentKeepalive/d" "$WORK_CONF"
    # Add PersistentKeepalive after [Peer] section
    sed -i "/\[Peer\]/a PersistentKeepalive = $PERSISTENT_KEEPALIVE" "$WORK_CONF"
    echo "Added PersistentKeepalive = $PERSISTENT_KEEPALIVE to config"
fi

# Parse Addresses and add PreUp/PostDown rules
grep -E '^\s*Address\s*=' "$WORK_CONF" | sed -E 's/^\s*Address\s*=\s*//' | tr ',' '\n' | while read -r ip_cidr; do
    IP=$(echo "$ip_cidr" | tr -d ' ' | cut -d/ -f1)
    if [ -n "$IP" ]; then
        if [[ "$IP" == *":"* ]]; then
            RULE_CMD="ip -6 rule"
        else
            RULE_CMD="ip rule"
        fi
        sed -i "/^Table = $RT_TABLE/a PostDown = $RULE_CMD del from $IP table $RT_TABLE priority 456" "$WORK_CONF"
        sed -i "/^Table = $RT_TABLE/a PreUp = $RULE_CMD add from $IP table $RT_TABLE priority 456" "$WORK_CONF"
    fi
done

echo "Config patched with Table = $RT_TABLE and policy rules. Starting AmneziaWG..."

# --- IMPORTANT: Specify to use amneziawg-go ---
# Set both variable variants for reliability
export WG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go
export AWG_QUICK_USERSPACE_IMPLEMENTATION=amneziawg-go
export WG_SUDO=1

# Bring up the interface
awg-quick up "$WORK_CONF"

# 5. Cleanup handler
cleanup() {
    echo "Stopping..."
    awg-quick down "$WORK_CONF"
    exit 0
}
trap cleanup SIGTERM SIGINT

tail -f /dev/null & wait