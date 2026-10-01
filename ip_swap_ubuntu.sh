#!/bin/bash
# update_ip_ubuntu.sh
# Usage check
if [ $# -ne 3 ]; then
    echo "Usage: $0 <Netplan config file> <New IP> <Sleep interval in seconds>"
    exit 1
fi

NETPLAN_FILE="$1"
NEW_IP="$2"
SLEEP_INTERVAL="$3"

BACKUP_FILE="/root/$(basename "$NETPLAN_FILE")_bak"
LOG_FILE="/root/ip_swap_revert.log"

# Get all non-loopback IP addresses assigned to the host
IP_LIST=$(ip -o -4 addr show | awk '!/127.0.0.1/ {print $4}' | cut -d/ -f1)
#IP_LIST="10.0.0.16 10.0.0.22"

if [ -z "$IP_LIST" ]; then
    echo "ERROR: No non-loopback IPv4 addresses found on this machine."
    exit 1
fi

# If only one IP, just use it
if [ "$(echo "$IP_LIST" | wc -w)" -eq 1 ]; then
    OLD_IP="$IP_LIST"
    echo "Only one IP detected: $OLD_IP"
    read -p "Are you sure you want to replace $OLD_IP with $NEW_IP? (y/n): " CONFIRM
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
                read -p "Are you sure you want to replace $OLD_IP with $NEW_IP? (y/n): " CONFIRM
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

# Final confirmation before swapping
echo -e "About to replace $OLD_IP with $NEW_IP in $NETPLAN_FILE.\n\nEnsure to copy this command:\n\nps -f -C bash | grep 'sleep $3' | awk '{print \$2}' | sudo xargs kill -9\n"
read -p "Press Enter to proceed, or Ctrl+C to abort..."

# Backup netplan
cp "$NETPLAN_FILE" "$BACKUP_FILE" || { echo "ERROR: Backup failed"; exit 1; }

# Apply IP swap
sed -i "s/$OLD_IP/$NEW_IP/g" "$NETPLAN_FILE"
if ! netplan apply; then
    echo "ERROR: Netplan apply failed, restoring backup"
    cp "$BACKUP_FILE" "$NETPLAN_FILE"
    netplan apply
    exit 1
fi

echo "IP swap applied: $OLD_IP -> $NEW_IP"
echo "Will revert automatically in $SLEEP_INTERVAL seconds"

# Start detached background job to revert
nohup bash -c "
    sleep $SLEEP_INTERVAL
    echo \"Reverting IP swap at \$(date)\" >> $LOG_FILE
    cp $BACKUP_FILE $NETPLAN_FILE
    netplan apply >> $LOG_FILE 2>&1
    echo \"Revert complete at \$(date)\" >> $LOG_FILE
" >/dev/null 2>&1 &

echo "Background revert process started (logs: $LOG_FILE)"
