!/bin/bash
# --- START: Clone Cleanup ---
echo "Regenerating Machine ID and cleaning Salt identity..."

# 1. Stop services to prevent locking files
systemctl stop venv-salt-minion || true
systemctl stop salt-minion || true

# 2. Regenerate System Machine ID (Systemd)
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id
dbus-uuidgen --ensure
systemd-machine-id-setup

# 3. Clean up Salt Bundle Identity (SUSE Manager 5.0+ default)
# The server will see systems as the same minion unless this is cleaned
rm -f /etc/venv-salt-minion/minion_id
rm -rf /etc/venv-salt-minion/pki/*

# 4. Clean up Legacy Salt Identity
rm -f /etc/salt/minion_id
rm -rf /etc/salt/pki/*

# 5. Fix Journald (Prevent log corruption until reboot)
# This moves the old journal catalog aside so a new one starts with the new ID
if [ -d /var/log/journal ]; then
    mv /var/log/journal /var/log/journal.backup_$(date +%s)
    mkdir -p /var/log/journal
    systemd-tmpfiles --create --prefix /var/log/journal
    systemctl restart systemd-journald
fi

echo "Identity regeneration complete."
# --- END: Clone Cleanup ---
