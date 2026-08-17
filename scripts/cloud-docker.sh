#!/usr/bin/env bash
# Make Docker usable on Cursor cloud VMs (nested Linux, often no systemd).
# No-op on macOS/Windows and on Linux where Docker + container networking already work.
#
# Nested Docker typically publishes host ports but drops bridge FORWARD, so
# compose services cannot reach each other or CubeAPM/ngrok. This script
# installs/starts dockerd if needed and opens FORWARD + MASQUERADE.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_JSON="${DAEMON_JSON:-/etc/docker/daemon.json}"
DOCKERD_LOG="${DOCKERD_LOG:-/tmp/cube-dockerd.log}"
DOCKERD_PID_FILE="${DOCKERD_PID_FILE:-/tmp/cube-dockerd.pid}"
VERIFY_NET_NAME="${VERIFY_NET_NAME:-cube-cloud-netcheck}"
VERIFY_CTR="${VERIFY_CTR:-cube-cloud-netcheck-a}"

usage() {
  cat <<'EOF'
Usage: ./scripts/cloud-docker.sh <ensure|status|net|verify|is-cloud>

  ensure   Install Docker if missing, start dockerd, fix bridge NAT/FORWARD
  status   Docker daemon + forwarding + is-cloud
  net      Apply ip_forward / FORWARD ACCEPT / MASQUERADE only
  verify   Two-container ping + egress smoke test
  is-cloud Exit 0 if this looks like a nested/cloud Linux VM
EOF
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "ERROR: need root for: $*"
    return 1
  fi
}

is_linux() {
  [ "$(uname -s)" = Linux ]
}

pid1_comm() {
  ps -p 1 -o comm= 2>/dev/null | tr -d ' ' || true
}

# Cursor cloud VMs are nested Linux pods without systemd as PID 1.
is_cloud() {
  is_linux || return 1
  case "$(pid1_comm)" in
    systemd|init) return 1 ;;
    *) return 0 ;;
  esac
}

# Daemon answers on the socket (root or current user).
daemon_up() {
  command -v docker >/dev/null 2>&1 || return 1
  docker info >/dev/null 2>&1 && return 0
  as_root docker info >/dev/null 2>&1
}

# stack.sh runs docker as the current user in this same process. usermod
# does not affect the current login, so on cloud VMs open the socket.
fix_cli_access() {
  local user
  user="$(id -un)"
  as_root groupadd -f docker >/dev/null 2>&1 || true
  as_root usermod -aG docker "$user" 2>/dev/null || true
  if [ -S /var/run/docker.sock ]; then
    as_root chown root:docker /var/run/docker.sock 2>/dev/null || true
    as_root chmod 660 /var/run/docker.sock 2>/dev/null || true
  fi
  if docker info >/dev/null 2>&1; then
    return 0
  fi
  if [ -S /var/run/docker.sock ]; then
    echo "docker.sock not usable as ${user}; chmod 666 for this VM"
    as_root chmod 666 /var/run/docker.sock
  fi
  docker info >/dev/null 2>&1
}

# Unprivileged CLI — what compose in stack.sh needs.
docker_ok() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

compose_ok() {
  docker compose version >/dev/null 2>&1
}

ip_forward_on() {
  [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)" = 1 ]
}

forward_policy() {
  iptables -S FORWARD 2>/dev/null | awk '/^-P FORWARD/ {print $3; exit}'
}

cmd_is_cloud() {
  if is_cloud; then
    echo "cloud: yes (linux pid1=$(pid1_comm))"
    return 0
  fi
  echo "cloud: no ($(uname -s) pid1=$(pid1_comm))"
  return 1
}

cmd_status() {
  echo "os: $(uname -s) $(uname -r)"
  echo "pid1: $(pid1_comm)"
  if is_cloud; then echo "cloud: yes"; else echo "cloud: no"; fi
  if command -v docker >/dev/null 2>&1; then
    echo "docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'cli-only')"
  else
    echo "docker: missing"
  fi
  if docker_ok; then echo "daemon: up (user)"; elif daemon_up; then echo "daemon: up (root only)"; else echo "daemon: down"; fi
  if compose_ok; then echo "compose: ok"; else echo "compose: missing"; fi
  echo "ip_forward: $(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo n/a)"
  echo "forward_policy: $(forward_policy || echo n/a)"
  if [ -S /var/run/docker.sock ]; then
    echo "docker.sock: $(ls -l /var/run/docker.sock | awk '{print $1,$3,$4}')"
  else
    echo "docker.sock: no"
  fi
}

write_daemon_json() {
  local driver="$1"
  as_root mkdir -p /etc/docker
  as_root tee "$DAEMON_JSON" >/dev/null <<EOF
{
  "storage-driver": "${driver}",
  "iptables": true,
  "ip-forward": true,
  "ip-masq": true,
  "icc": true
}
EOF
  echo "wrote $DAEMON_JSON storage-driver=${driver}"
}

systemd_usable() {
  command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1
}

kill_manual_dockerd() {
  if [ -f "$DOCKERD_PID_FILE" ]; then
    local pid
    pid=$(cat "$DOCKERD_PID_FILE" 2>/dev/null || true)
    if [ -n "${pid:-}" ]; then
      as_root kill "$pid" 2>/dev/null || true
      sleep 1
    fi
    as_root rm -f "$DOCKERD_PID_FILE"
  fi
}

wait_dockerd_ready() {
  local driver="$1"
  local i
  for i in $(seq 1 30); do
    if daemon_up; then
      fix_cli_access || true
      if docker_ok; then
        echo "dockerd ready (driver=${driver})"
        return 0
      fi
    fi
    sleep 1
  done
  echo "ERROR: dockerd did not become ready (driver=${driver}). last log:"
  tail -n 40 "$DOCKERD_LOG" 2>/dev/null || true
  return 1
}

start_dockerd_manual() {
  local driver="$1"
  write_daemon_json "$driver"
  as_root mkdir -p /var/lib/docker /var/run
  echo "starting dockerd (storage-driver=${driver})..."
  as_root sh -c "nohup dockerd --host=unix:///var/run/docker.sock --exec-opt native.cgroupdriver=cgroupfs >'$DOCKERD_LOG' 2>&1 & echo \$! >'$DOCKERD_PID_FILE'"
  wait_dockerd_ready "$driver"
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && compose_ok; then
    return 0
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: docker missing and no apt-get to install it"
    return 1
  fi
  echo "installing docker via apt..."
  as_root apt-get update -qq
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker.io docker-compose-v2 iptables ca-certificates curl iproute2
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker CLI still missing after apt install"
    return 1
  fi
  echo "installed $(docker --version)"
}

start_daemon() {
  if daemon_up; then
    fix_cli_access || true
    if docker_ok; then
      echo "daemon already up"
      return 0
    fi
  fi
  if systemd_usable; then
    echo "starting docker via systemd"
    as_root systemctl start docker || true
    local i
    for i in $(seq 1 20); do
      if daemon_up; then
        fix_cli_access || true
        docker_ok && return 0
      fi
      sleep 1
    done
  fi
  if daemon_up; then
    fix_cli_access || true
    docker_ok && return 0
  fi
  if ! command -v dockerd >/dev/null 2>&1; then
    echo "ERROR: dockerd binary not found"
    return 1
  fi
  kill_manual_dockerd
  if start_dockerd_manual overlay2; then
    return 0
  fi
  echo "overlay2 failed; retrying with vfs"
  kill_manual_dockerd
  as_root rm -rf /var/lib/docker 2>/dev/null || true
  start_dockerd_manual vfs
}

cmd_net() {
  echo "applying container forwarding/NAT (bridge-nf off so ICC is L2)..."
  as_root sysctl -w net.ipv4.ip_forward=1 >/dev/null
  as_root sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null 2>/dev/null || true
  # Nested Docker: sending bridge frames through iptables breaks ICC even when
  # FORWARD is ACCEPT. Switch on the linux bridge instead.
  as_root sysctl -w net.bridge.bridge-nf-call-iptables=0 >/dev/null 2>/dev/null || true
  as_root sysctl -w net.bridge.bridge-nf-call-ip6tables=0 >/dev/null 2>/dev/null || true
  if ! command -v iptables >/dev/null 2>&1; then
    echo "ERROR: iptables not found"
    return 1
  fi
  as_root iptables -P FORWARD ACCEPT
  as_root iptables -C FORWARD -j ACCEPT 2>/dev/null || as_root iptables -I FORWARD 1 -j ACCEPT
  local chain
  for chain in DOCKER-USER DOCKER-ISOLATION-STAGE-1 DOCKER-ISOLATION-STAGE-2; do
    as_root iptables -C "$chain" -j ACCEPT 2>/dev/null \
      || as_root iptables -I "$chain" 1 -j ACCEPT 2>/dev/null \
      || true
  done
  as_root iptables -t nat -C POSTROUTING -s 172.16.0.0/12 -j MASQUERADE 2>/dev/null \
    || as_root iptables -t nat -A POSTROUTING -s 172.16.0.0/12 -j MASQUERADE
  echo "ip_forward=$(cat /proc/sys/net/ipv4/ip_forward) forward_policy=$(forward_policy) bridge-nf=$(cat /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || echo n/a)"
}

cleanup_verify() {
  docker rm -f "$VERIFY_CTR" >/dev/null 2>&1 || true
  docker network rm "$VERIFY_NET_NAME" >/dev/null 2>&1 || true
}

cmd_verify() {
  if ! docker_ok; then
    echo "ERROR: docker daemon not up"
    return 1
  fi
  cleanup_verify
  docker network create "$VERIFY_NET_NAME" >/dev/null
  docker run -d --name "$VERIFY_CTR" --network "$VERIFY_NET_NAME" alpine:3.20 \
    sh -c 'echo ok > /tmp/index.html && exec httpd -f -p 8080 -h /tmp' >/dev/null
  local icc=0 egress=0 ip
  ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$VERIFY_CTR" 2>/dev/null || true)
  echo "verify icc target: name=$VERIFY_CTR ip=${ip:-unknown}"
  if docker run --rm --network "$VERIFY_NET_NAME" alpine:3.20 ping -c 1 -W 2 "$VERIFY_CTR" >/dev/null 2>&1; then
    echo "verify icc ping: ok"
  else
    echo "verify icc ping: FAIL"
  fi
  if docker run --rm --network "$VERIFY_NET_NAME" alpine:3.20 wget -q -O- --timeout=5 "http://${VERIFY_CTR}:8080/" 2>/dev/null | grep -q ok \
    || { [ -n "${ip:-}" ] && docker run --rm --network "$VERIFY_NET_NAME" alpine:3.20 wget -q -O- --timeout=5 "http://${ip}:8080/" 2>/dev/null | grep -q ok; }; then
    echo "verify icc tcp: ok"
    icc=1
  else
    echo "verify icc tcp: FAIL (containers cannot reach each other on the compose bridge)"
  fi
  if docker run --rm alpine:3.20 ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 \
    || docker run --rm alpine:3.20 wget -q -O /dev/null --timeout=5 https://example.com >/dev/null 2>&1; then
    echo "verify egress: ok"
    egress=1
  else
    echo "verify egress: FAIL (containers cannot reach the internet / ngrok)"
  fi
  cleanup_verify
  if [ "$icc" -eq 1 ] && [ "$egress" -eq 1 ]; then
    return 0
  fi
  return 1
}

cmd_ensure() {
  if ! is_linux; then
    echo "cloud-docker: skip ($(uname -s); Docker Desktop is enough)"
    return 0
  fi

  install_docker || return 1
  start_daemon || return 1
  if ! compose_ok; then
    echo "ERROR: docker compose plugin missing"
    return 1
  fi

  if is_cloud; then
    cmd_net || return 1
  fi

  if cmd_verify; then
    echo "cloud-docker: ready"
    return 0
  fi

  echo "container networking broken; applying FORWARD/NAT"
  cmd_net || return 1
  if cmd_verify; then
    echo "cloud-docker: ready (after net fix)"
    return 0
  fi

  echo "ERROR: Docker is up but compose-bridge networking still fails."
  echo "Apps will not reach mysql/redis/kafka or CubeAPM/ngrok from inside containers."
  return 1
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    ensure) cmd_ensure ;;
    status) cmd_status ;;
    net) cmd_net ;;
    verify) cmd_verify ;;
    is-cloud) cmd_is_cloud ;;
    -h|--help|help|"") usage; [ -n "$cmd" ] ;;
    *) echo "Unknown command: $cmd"; usage; return 1 ;;
  esac
}

main "$@"
