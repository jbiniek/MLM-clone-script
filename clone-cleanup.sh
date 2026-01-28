#!/bin/bash
# --- START: Universal Clone Cleanup (SLES/RHEL/Debian/Ubuntu) ---
echo "INFO: Starting Clone Cleanup for SUSE Manager 5.0 Registration..."

# 0. Safety Check: Ensure we are running on a systemd system
if [ ! -d /run/systemd/system ]; then
    echo "ERROR: This cleanup script requires systemd. Skipping ID regeneration."
else
    # 1. Stop Salt Services to release file locks
    # We stop both the bundle (venv) and classic service just in case
    echo "INFO: Stopping Salt services..."
    systemctl stop venv-salt-minion 2>/dev/null || true
    systemctl stop salt-minion 2>/dev/null || true

    # 2. Identify Distribution Family (for logging/debugging purposes)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_FAMILY=$ID
        echo "INFO: Detected OS: $NAME ($OS_FAMILY)"
    fi

    # 3. Regenerate System Machine ID
    # This logic works for SLES, RHEL, CentOS, Rocky, Oracle, Debian, and Ubuntu
    echo "INFO: Regenerating System Machine ID..."
    
    # Remove existing IDs
    rm -f /etc/machine-id
    rm -f /var/lib/dbus/machine-id
    
    # RHEL/SLES/CentOS usually need dbus-uuidgen first
    if command -v dbus-uuidgen >/dev/null 2>&1; then
        dbus-uuidgen --ensure
    fi
    
    # Universal systemd generation
    systemd-machine-id-setup
    
    # Debian/Ubuntu Specific Fix:
    # Sometimes Debian/Ubuntu leaves /var/lib/dbus/machine-id empty or missing after setup.
    # We allow the systemd ID to propagate to dbus if missing.
    if [ ! -s /var/lib/dbus/machine-id ] && [ -s /etc/machine-id ]; then
        mkdir -p /var/lib/dbus
        ln -s /etc/machine-id /var/lib/dbus/machine-id
        echo "INFO: Linked /etc/machine-id to /var/lib/dbus/machine-id (Debian/Ubuntu fix)"
    fi

    # 4. Clean Salt Bundle Identity (Critical for SUSE Manager 5.0)
    echo "INFO: Cleaning venv-salt-minion identity..."
    rm -f /etc/venv-salt-minion/minion_id
    rm -rf /etc/venv-salt-minion/pki/*

    # 5. Clean Legacy Salt Identity
    echo "INFO: Cleaning legacy salt-minion identity..."
    rm -f /etc/salt/minion_id
    rm -rf /etc/salt/pki/*

    # 6. Fix Journald
    # Changing machine-id breaks logging until restart, this needs fixing
    echo "INFO: Rotating systemd journal..."
    if [ -d /var/log/journal ]; then
        # We rename the folder so a new one is created with the new ID
        mv /var/log/journal /var/log/journal.backup_$(date +%s)
        mkdir -p /var/log/journal
        systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true
        systemctl restart systemd-journald
    fi
    
    # 7. (Optional) SSH Host Keys
    # Clones usually share SSH keys, which is a security risk. 
    # Uncomment the following lines if you want to regenerate SSH keys too.
    # rm -f /etc/ssh/ssh_host_*
    # systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
    
    echo "INFO: Identity regeneration complete. New Machine ID: $(cat /etc/machine-id)"
fi
# --- END: Universal Clone Cleanup ---
