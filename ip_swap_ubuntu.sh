#!/bin/bash
# ip_swap_ubuntu.sh
# Swaps this server's IPv4 address in a Netplan config, checks the network came
# back up, and puts the old config back on its own after a set time unless the
# change is kept.
#
# Usage: sudo ./ip_swap_ubuntu.sh <Netplan config file> <New IP> <Seconds before revert>

set -u
# Keep going if the SSH session drops when the address changes
trap '' HUP

if [ $# -ne 3 ]; then
    echo "Usage: $0 <Netplan config file> <New IP> <Seconds before revert>"
    exit 1
fi

CONFIG_FILE="$1"
NEW_IP="$2"
SLEEP_INTERVAL="$3"
APPLY_CMD="netplan apply"

STATE_DIR="/root/ip_swap"
BACKUP_FILE="$STATE_DIR/$(basename "$CONFIG_FILE").$(date +%Y%m%d-%H%M%S).bak"
# In /run so a sudo user can read it, and gone after a reboot along with the revert
PID_FILE="/run/ip_swap_revert.pid"
LOG_FILE="$STATE_DIR/ip_swap.log"

log() {
    echo "$1"
    echo "$(date): $1" >> "$LOG_FILE"
}

valid_ipv4() {
    local IFS=. octet
    [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    for octet in $1; do
        [ "$octet" -le 255 ] || return 1
    done
}

# Put the backup back now and stop the timed revert, which has nothing left to do
restore_now() {
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    $APPLY_CMD >> "$LOG_FILE" 2>&1
    kill "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null
    log "Restored $CONFIG_FILE from $BACKUP_FILE"
}

# Passes when the new address is on an interface and the default gateway answers
check_network() {
    local gateway
    if ! ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -qxF "$NEW_IP"; then
        log "Health check failed: $NEW_IP is not on any interface"
        return 1
    fi
    gateway=$(ip -4 route show default | awk '{print $3; exit}')
    if [ -z "$gateway" ]; then
        log "Health check: no default gateway found, so only the address was checked"
        return 0
    fi
    # Retry for about 30 seconds, as the other server may still be letting go of the address
    for _ in $(seq 1 10); do
        if ping -c 1 -W 2 "$gateway" > /dev/null 2>&1; then
            log "Health check passed: $NEW_IP is up and the gateway $gateway answers"
            return 0
        fi
        sleep 1
    done
    log "Health check failed: the gateway $gateway did not answer"
    return 1
}

# Checks before anything changes
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run this as root (sudo)."
    exit 1
fi
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: $CONFIG_FILE not found."
    exit 1
fi
if ! valid_ipv4 "$NEW_IP"; then
    echo "ERROR: '$NEW_IP' is not a valid IPv4 address."
    exit 1
fi
if [[ ! $SLEEP_INTERVAL =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: '$SLEEP_INTERVAL' is not a whole number of seconds."
    exit 1
fi

mkdir -p "$STATE_DIR"
# A second run while a revert is pending would back up the swapped config,
# leaving the revert nothing to go back to
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "ERROR: A revert from an earlier run is still pending."
    echo "Keep that change first with: sudo kill \$(cat $PID_FILE)"
    exit 1
fi
rm -f "$PID_FILE"

# Get all non-loopback IP addresses assigned to the host
IP_LIST=$(ip -o -4 addr show scope global | awk '{print $4}' | cut -d/ -f1)

if [ -z "$IP_LIST" ]; then
    echo "ERROR: No non-loopback IPv4 addresses found on this machine."
    exit 1
fi
if echo "$IP_LIST" | grep -qxF "$NEW_IP"; then
    echo "ERROR: $NEW_IP is already on this machine."
    exit 1
fi

# If only one IP, just use it
if [ "$(echo "$IP_LIST" | wc -w)" -eq 1 ]; then
    OLD_IP="$IP_LIST"
    echo "Only one IP detected: $OLD_IP"
    read -r -p "Are you sure you want to replace $OLD_IP with $NEW_IP? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted by user."
        exit 1
    fi
else
    # Present IP list for user selection with confirmation
    while true; do
        echo "Available IP addresses on this machine:"
        select OLD_IP in $IP_LIST; do
            if [ -n "$OLD_IP" ]; then
                echo "You selected: $OLD_IP"
                read -r -p "Are you sure you want to replace $OLD_IP with $NEW_IP? (y/n): " CONFIRM
                if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                    break 2   # Exit both loops
                else
                    echo "Okay, please select again."
                    break     # Re-run select menu
                fi
            else
                echo "Invalid selection, please try again."
            fi
        done
    done
fi

# Match the old IP only as a whole address, so 10.0.0.1 never touches 10.0.0.15
OLD_IP_RE="${OLD_IP//./\\.}"
MATCH_RE="(^|[^0-9.])${OLD_IP_RE}([^0-9.]|$)"
if ! grep -Eq "$MATCH_RE" "$CONFIG_FILE"; then
    echo "ERROR: $OLD_IP is not in $CONFIG_FILE, so there is nothing to swap."
    exit 1
fi

# Final confirmation before swapping
echo
echo "About to replace $OLD_IP with $NEW_IP in $CONFIG_FILE."
echo "It reverts on its own after $SLEEP_INTERVAL seconds. To keep the change, reconnect on $NEW_IP and run:"
echo
echo "    sudo kill \$(cat $PID_FILE)"
echo
read -r -p "Press Enter to proceed, or Ctrl+C to abort..."

# Backup the config
cp "$CONFIG_FILE" "$BACKUP_FILE" || { echo "ERROR: Backup failed"; exit 1; }
log "Swapping $OLD_IP -> $NEW_IP in $CONFIG_FILE (backup: $BACKUP_FILE)"

# Start the timed revert before touching the network, so the way back exists
# even if this session drops
CONFIG_FILE="$CONFIG_FILE" BACKUP_FILE="$BACKUP_FILE" PID_FILE="$PID_FILE" \
LOG_FILE="$LOG_FILE" SLEEP_INTERVAL="$SLEEP_INTERVAL" APPLY_CMD="$APPLY_CMD" \
nohup setsid bash -c '
    echo $$ > "$PID_FILE"
    sleep "$SLEEP_INTERVAL" &
    SLEEP_PID=$!
    cancel() {
        kill "$SLEEP_PID" 2>/dev/null
        rm -f "$PID_FILE"
        echo "$(date): Automatic revert cancelled" >> "$LOG_FILE"
        exit 0
    }
    trap cancel TERM
    wait "$SLEEP_PID"
    echo "$(date): Time is up, reverting $CONFIG_FILE from $BACKUP_FILE" >> "$LOG_FILE"
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    $APPLY_CMD >> "$LOG_FILE" 2>&1
    echo "$(date): Revert complete" >> "$LOG_FILE"
    rm -f "$PID_FILE"
' > /dev/null 2>&1 &

# Wait for the revert to be running before going any further
for _ in $(seq 1 50); do
    [ -s "$PID_FILE" ] && break
    sleep 0.1
done
if [ ! -s "$PID_FILE" ]; then
    log "ERROR: The automatic revert did not start, so nothing was changed"
    exit 1
fi
log "Automatic revert armed for $SLEEP_INTERVAL seconds (PID $(cat "$PID_FILE"))"

# Apply IP swap. The loop catches the old IP more than once on a line.
sed -E -i -e ':a' -e "s/${MATCH_RE}/\1${NEW_IP}\2/" -e 'ta' "$CONFIG_FILE"
if ! $APPLY_CMD; then
    log "ERROR: $APPLY_CMD failed, restoring the backup"
    restore_now
    exit 1
fi

if ! check_network; then
    log "Restoring the backup now rather than waiting for the timer"
    restore_now
    exit 1
fi

log "IP swap applied: $OLD_IP -> $NEW_IP"
echo "Reverts automatically in $SLEEP_INTERVAL seconds unless you keep the change:"
echo
echo "    sudo kill \$(cat $PID_FILE)"
echo
echo "Log: $LOG_FILE"
