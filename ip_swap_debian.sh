#!/bin/bash

# Ensure inputs are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <New IP> <Sleep interval in seconds>"
    exit 1
fi

NEW_IP="$1"
SLEEP_INTERVAL="$2"
LOG_FILE="/root/debian_ip_swap.log"
INTERFACES_FILE="/etc/network/interfaces"
BACKUP_FILE="/root/interfaces_bak"

# Detect all non-loopback IPv4 addresses
IP_LIST=$(ip -o -4 addr show | awk '!/127.0.0.1/ {print $4}' | cut -d/ -f1)

if [ -z "$IP_LIST" ]; then
    echo "ERROR: No non-loopback IPv4 addresses found."
    exit 1
fi

# Select IP to replace
if [ "$(echo "$IP_LIST" | wc -w)" -eq 1 ]; then
    OLD_IP="$IP_LIST"
    echo "Only one IP detected: $OLD_IP"
    read -p "Are you sure you want to replace $OLD_IP with $NEW_IP? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted by user."
        exit 1
    fi
else
    while true; do
        echo "Available IP addresses on this machine:"
        select OLD_IP in $IP_LIST; do
            if [ -n "$OLD_IP" ]; then
                echo "You selected: $OLD_IP"
                read -p "Are you sure you want to replace $OLD_IP with $NEW_IP? (y/n): " CONFIRM
                if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                    break 2
                else
                    echo "Okay, please select again."
                    break
                fi
            else
                echo "Invalid selection, please try again."
            fi
        done
    done
fi

# Final confirmation before swapping
echo -e "About to replace $OLD_IP with $NEW_IP in $INTERFACES_FILE.\n\nEnsure to copy this command:\n\nps -f -C bash | grep 'sleep $2' | awk '{print \$2}' | sudo xargs kill -9\n"
read -p "Press Enter to proceed, or Ctrl+C to abort..."

# Backup interfaces file
cp "$INTERFACES_FILE" "$BACKUP_FILE" || { echo "ERROR: Backup failed"; exit 1; }

# Apply IP swap
sed -i "s/$OLD_IP/$NEW_IP/g" "$INTERFACES_FILE"
if ! systemctl restart networking; then
    echo "ERROR: Restarting networking failed, restoring backup"
    cp "$BACKUP_FILE" "$INTERFACES_FILE"
    systemctl restart networking
    exit 1
fi

echo "IP swap applied: $OLD_IP -> $NEW_IP"
echo "Will revert automatically in $SLEEP_INTERVAL seconds"
echo "$(date): Swapped $OLD_IP -> $NEW_IP" >> "$LOG_FILE"

# Start background revert process
nohup bash -c "
    sleep $SLEEP_INTERVAL
    echo \"Reverting IP swap at \$(date)\" >> $LOG_FILE
    cp $BACKUP_FILE $INTERFACES_FILE
    systemctl restart networking >> $LOG_FILE 2>&1
    echo \"Revert complete at \$(date)\" >> $LOG_FILE
" >/dev/null 2>&1 &

echo "Background revert process started (logs: $LOG_FILE)"
