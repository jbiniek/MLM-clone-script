# --- START: Advanced Clone Cleanup & Prep ---
# Merges SUSE Manager 5.0 requirements with best-practice clone hygiene

# --- 1. Visual Helpers ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERR]${NC}  $1"; }

log_info "Starting Pre-Bootstrap Clone Cleanup..."

# --- 2. Stop Services ---
# We stop Salt to release locks. We do NOT stop SSH to avoid killing the bootstrap connection.
log_info "Stopping Salt services..."
systemctl stop venv-salt-minion 2>/dev/null || true
systemctl stop salt-minion 2>/dev/null || true

# --- 3. Clean Random Seed (Entropy) ---
# Borrowed from vzhestkov: Ensures cryptographic keys (like Salt's) are truly unique.
if [ -f /var/lib/systemd/random-seed ]; then
    log_info "Refreshing systemd random seed..."
    rm -f /var/lib/systemd/random-seed
    # We don't restart the service immediately to avoid delays, just clear the file.
fi

# --- 4. RHEL/CentOS/Oracle Specific: Subscription Manager ---
# If a RHEL clone thinks it's registered to Red Hat, it can cause package conflict issues.
if [ -d /etc/pki/consumer ]; then
    log_info "Detected RHEL identity. Cleaning Subscription Manager..."
    rm -rf /etc/pki/consumer/*
    rm -f /etc/pki/product/*
    rm -rf /etc/sysconfig/rhn/systemid
    log_info "RHEL identity cleaned."
fi

# --- 5. SSH Host Key Regeneration (Security Critical) ---
# Clones share SSH host keys by default, allowing MITM attacks.
# We remove them and regenerate them immediately without breaking the active session.
log_info "Regenerating SSH Host Keys..."
rm -f /etc/ssh/ssh_host_*

# Generate new keys without restarting sshd immediately (keeps your connection alive)
if command -v ssh-keygen >/dev/null 2>&1; then
    ssh-keygen -A
    log_info "New SSH host keys generated."
else
    log_warn "ssh-keygen not found. Keys will be generated on next reboot."
fi

# --- 6. Machine ID Regeneration (Universal) ---
log_info "Regenerating System Machine ID..."
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id

if command -v dbus-uuidgen >/dev/null 2>&1; then
    dbus-uuidgen --ensure
fi

systemd-machine-id-setup

# Fix for Debian/Ubuntu where dbus ID might not sync automatically
if [ ! -s /var/lib/dbus/machine-id ] && [ -s /etc/machine-id ]; then
    mkdir -p /var/lib/dbus
    ln -s /etc/machine-id /var/lib/dbus/machine-id
    log_info "Synced /etc/machine-id to /var/lib/dbus/machine-id"
fi

# --- 7. Salt Identity Cleanup (SUMA 5.0 Specific) ---
# This is the most important part for your SUSE Manager registration.
log_info "Cleaning Salt Bundle (venv) identity..."
rm -f /etc/venv-salt-minion/minion_id
rm -rf /etc/venv-salt-minion/pki/*

log_info "Cleaning Legacy Salt identity..."
rm -f /etc/salt/minion_id
rm -rf /etc/salt/pki/*

# --- 8. Journald Rotation ---
# Prevents log corruption after ID change.
if [ -d /var/log/journal ]; then
    log_info "Rotating systemd journal..."
    mv /var/log/journal /var/log/journal.backup_$(date +%s)
    mkdir -p /var/log/journal
    systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true
    # We restart journald to lock in the new machine-id
    systemctl restart systemd-journald
fi

log_info "Cleanup Complete. New Machine ID: $(cat /etc/machine-id)"
# --- END: Advanced Clone Cleanup ---
