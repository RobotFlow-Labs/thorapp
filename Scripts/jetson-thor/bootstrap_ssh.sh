#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
PUBKEY="${2:-}"
DISABLE_PASSWORD_AUTH="${DISABLE_PASSWORD_AUTH:-0}"
SSH_OPTS=(-tt -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2)

usage() {
  cat <<'EOF'
Usage:
  bootstrap_ssh.sh <user@host> [public-key-path]

Examples:
  bootstrap_ssh.sh nvidia@192.168.55.1
  bootstrap_ssh.sh anima@anima-thor.local ~/.ssh/id_ed25519.pub

Behavior:
  1. Appends the selected public key to authorized_keys
  2. Enables passwordless sudo for the remote user
  3. Optionally disables SSH password auth if DISABLE_PASSWORD_AUTH=1
EOF
}

if [[ -z "$TARGET" ]]; then
  usage
  exit 1
fi

if [[ "$TARGET" != *@* ]]; then
  echo "Target must be in user@host form."
  exit 1
fi

select_pubkey() {
  local preferred=(
    "$HOME/.ssh/id_ed25519.pub"
    "$HOME/.ssh/id_ecdsa.pub"
    "$HOME/.ssh/id_rsa.pub"
  )

  for candidate in "${preferred[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  local generated
  generated=$(ls "$HOME"/.ssh/thor_jetson_*.pub 2>/dev/null | head -n 1 || true)
  if [[ -n "$generated" ]]; then
    echo "$generated"
    return 0
  fi

  return 1
}

if [[ -z "$PUBKEY" ]]; then
  PUBKEY="$(select_pubkey || true)"
fi

if [[ -z "$PUBKEY" || ! -f "$PUBKEY" ]]; then
  echo "No usable public key found. Pass one explicitly as the second argument."
  exit 1
fi

REMOTE_USER="${TARGET%@*}"

echo "[1/3] Installing public key from $PUBKEY on $TARGET"
ssh "${SSH_OPTS[@]}" "$TARGET" 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys' < "$PUBKEY"

echo "[2/3] Enabling passwordless sudo for $REMOTE_USER"
ssh "${SSH_OPTS[@]}" "$TARGET" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
REMOTE_USER="${SUDO_USER:-}"
if [[ -z "$REMOTE_USER" ]]; then
  echo "Unable to determine remote user for sudoers entry." >&2
  exit 1
fi
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$REMOTE_USER" > /etc/sudoers.d/90-thor-bootstrap
chmod 440 /etc/sudoers.d/90-thor-bootstrap
REMOTE

if [[ "$DISABLE_PASSWORD_AUTH" == "1" ]]; then
  echo "[3/3] Disabling SSH password authentication"
  ssh "${SSH_OPTS[@]}" "$TARGET" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh || systemctl restart sshd
REMOTE
else
  echo "[3/3] Leaving SSH password authentication enabled (set DISABLE_PASSWORD_AUTH=1 to harden it)"
fi

echo
echo "Bootstrap complete."
echo "Next:"
echo "  ssh $TARGET"
echo "  ssh $TARGET 'sudo -n true && echo sudo-ready'"
