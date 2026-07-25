#!/usr/bin/env bash
set -euo pipefail

# Bare-metal installer for Aalnase Miningcore on Ubuntu 24.04+.
# Installs:
#   - .NET 10 build/runtime dependencies
#   - PostgreSQL 18 and Miningcore schema/user
#   - Miningcore under /opt/miningcore with systemd service
#   - Multiflex Core from https://github.com/Aalnase/multiflexcoin under /opt/multiflexcoin
#   - simple static WebUI with HTTPS via Let's Encrypt
#
# Usage:
#   sudo ./contrib/install/install-ubuntu-24.04.sh
#   sudo POOL_MODE=public WEBUI_DOMAIN=pool.example.com LETSENCRYPT_EMAIL=admin@example.com ./contrib/install/install-ubuntu-24.04.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEBIAN_FRONTEND=noninteractive

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run this installer as root, for example: sudo $0" >&2
    exit 1
  fi
}

require_ubuntu_24_plus() {
  . /etc/os-release
  if [[ "${ID}" != "ubuntu" ]]; then
    echo "This installer is intended for Ubuntu 24.04 or newer. Detected: ${PRETTY_NAME:-unknown}" >&2
    exit 1
  fi
  local major minor
  major="${VERSION_ID%%.*}"
  minor="${VERSION_ID#*.}"
  minor="${minor%%.*}"
  if (( major < 24 || (major == 24 && minor < 4) )); then
    echo "Ubuntu 24.04 or newer is required. Detected: ${VERSION_ID}" >&2
    exit 1
  fi
}

backup_if_exists() {
  local file="$1"
  if [[ -e "$file" ]]; then
    cp -a "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

random_secret() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

default_build_jobs() {
  if [[ -n "${BUILD_JOBS:-}" ]]; then
    echo "$BUILD_JOBS"
    return
  fi

  local mem_kb cpus
  mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
  cpus="$(nproc)"
  if (( mem_kb < 4000000 )); then
    echo 1
  elif (( cpus < 2 )); then
    echo 1
  else
    echo 2
  fi
}

ensure_build_swap() {
  local mem_kb swap_kb total_kb swapfile
  mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
  swap_kb="$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)"
  total_kb=$((mem_kb + swap_kb))
  swapfile="${INSTALL_SWAPFILE:-/swapfile-aalnase-build}"

  if (( total_kb >= 6000000 )); then
    return
  fi
  if swapon --show=NAME --noheadings | grep -qx "$swapfile"; then
    return
  fi

  echo "Low build memory detected; creating temporary 4G swap at ${swapfile} for native library compilation..."
  if [[ ! -e "$swapfile" ]]; then
    fallocate -l 4G "$swapfile" 2>/dev/null || dd if=/dev/zero of="$swapfile" bs=1M count=4096 status=progress
    chmod 600 "$swapfile"
    mkswap "$swapfile" >/dev/null
  fi
  swapon "$swapfile"
}

print_console_avatar() {
  if [[ -t 1 ]]; then
    printf '\033[1;33m'
  fi
  cat <<'AVATAR'

        .--.        MFLEX POOL INSTALLER
       /_  _\       Miningcore + Multiflex + HTTPS WebUI
      | o  o |      mascot: penguin with the golden flex
      |  __  |__
      /\____/  `\
     /  /  \   _/)
    /__/____\_/`  
       /_||_\      ready to mine

AVATAR
  if [[ -t 1 ]]; then
    printf '\033[0m'
  fi
}

prompt_required() {
  local var_name="$1"
  local prompt="$2"
  local value="${!var_name:-}"
  while [[ -z "$value" ]]; do
    read -r -p "$prompt" value
  done
  export "$var_name=$value"
}

collect_install_inputs() {
  print_console_avatar
  cat <<'INTRO'

Aalnase Miningcore + MFLEX installer
------------------------------------
The installer asks for the few values that must be known before the
automated install starts. Passwords/RPC secrets are generated automatically
and printed once at the end. The WebUI is always installed and HTTPS is
always configured with Let's Encrypt, so the domain must already point to
this server before you start.
INTRO

  if [[ -n "${POOL_MODE:-}" ]]; then
    case "${POOL_MODE}" in
      public|home) ;;
      *) echo "POOL_MODE must be 'public' or 'home'" >&2; exit 1 ;;
    esac
  else
    echo
    echo "Pool mode:"
    echo "  public - internet-facing pool; payments enabled; production-style defaults"
    echo "  home   - LAN/home pool; payments disabled by default; conservative defaults"
    read -r -p "Pool mode [public]: " choice
    case "${choice:-public}" in
      home|Home|HOME|2) POOL_MODE="home" ;;
      *) POOL_MODE="public" ;;
    esac
  fi

  echo
  prompt_required WEBUI_DOMAIN "WebUI domain name, e.g. pool.example.com: "
  prompt_required LETSENCRYPT_EMAIL "Let's Encrypt email address for HTTPS renewal notices: "

  if [[ ! "$WEBUI_DOMAIN" =~ ^[A-Za-z0-9.-]+$ || "$WEBUI_DOMAIN" != *.* ]]; then
    echo "WEBUI_DOMAIN must be a fully qualified domain name, got: $WEBUI_DOMAIN" >&2
    exit 1
  fi
  if [[ ! "$LETSENCRYPT_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
    echo "LETSENCRYPT_EMAIL does not look like a valid email address: $LETSENCRYPT_EMAIL" >&2
    exit 1
  fi

  MININGCORE_POOL_PORT="${MININGCORE_POOL_PORT:-3333}"
  MFLEX_WALLET_NAME="${MFLEX_WALLET_NAME:-poolwallet}"
  export POOL_MODE WEBUI_DOMAIN LETSENCRYPT_EMAIL MININGCORE_POOL_PORT MFLEX_WALLET_NAME

  cat <<EOF

Install summary before automation starts:
  Pool mode:        ${POOL_MODE}
  WebUI domain:     ${WEBUI_DOMAIN}
  HTTPS email:      ${LETSENCRYPT_EMAIL}
  WebUI:            always installed
  HTTPS:            always enabled
  Stratum port:     ${MININGCORE_POOL_PORT}
  MFLEX wallet:     ${MFLEX_WALLET_NAME}
  MFLEX address:    generated automatically unless MFLEX_POOL_ADDRESS is set

EOF
}

install_base_packages() {
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release git sudo jq file nginx certbot python3-certbot-nginx rsync ufw

  if ! apt-cache show dotnet-sdk-10.0 >/dev/null 2>&1; then
    local ms_deb="/tmp/packages-microsoft-prod.deb"
    curl -fsSL "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb" -o "$ms_deb"
    dpkg -i "$ms_deb"
    rm -f "$ms_deb"
    apt-get update
  fi

  apt-get install -y --no-install-recommends \
    dotnet-sdk-10.0 aspnetcore-runtime-10.0 \
    build-essential cmake ninja-build pkg-config python3 \
    gperf bison flex automake libtool gettext zip unzip clang \
    libssl-dev libboost-all-dev libsodium-dev libzmq5 libzmq3-dev \
    libgmp-dev libc++-dev zlib1g-dev
}

install_postgresql18() {
  if ! apt-cache show postgresql-18 >/dev/null 2>&1; then
    install -d -m 0755 /usr/share/postgresql-common/pgdg
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list
    apt-get update
  fi

  apt-get install -y postgresql-18 postgresql-client-18
  systemctl enable --now postgresql
}

setup_users() {
  id -u miningcore >/dev/null 2>&1 || useradd --system --home /opt/miningcore --shell /usr/sbin/nologin miningcore
  id -u multiflex >/dev/null 2>&1 || useradd --system --home /var/lib/multiflexcoin --shell /usr/sbin/nologin multiflex
}

harden_tree_readonly() {
  local path="$1"
  chown -R root:root "$path"
  find "$path" -type d -exec chmod 755 {} \;
  find "$path" -type f -exec chmod 644 {} \;
  # Restore executable bits for published native binaries/scripts. Shared
  # libraries do not need to be executable, but keeping executable ELF/program
  # files executable avoids breaking dotnet apphost and coin daemon CLIs.
  while IFS= read -r -d '' file; do
    if file "$file" | grep -Eq 'ELF .* executable|ELF .* pie executable|POSIX shell script|Bourne-Again shell script'; then
      chmod 755 "$file"
    fi
  done < <(find "$path" -type f -print0)
}

setup_postgres_schema() {
  local db_name="${MININGCORE_DB_NAME:-miningcore}"
  local db_user="${MININGCORE_DB_USER:-miningcore}"
  local db_password="${MININGCORE_DB_PASSWORD:-$(random_secret)}"
  export MININGCORE_DB_NAME="$db_name" MININGCORE_DB_USER="$db_user" MININGCORE_DB_PASSWORD="$db_password"

  sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${db_user}') THEN
    CREATE ROLE ${db_user} LOGIN PASSWORD '${db_password}';
  ELSE
    ALTER ROLE ${db_user} LOGIN PASSWORD '${db_password}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${db_name} OWNER ${db_user}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}')\gexec
GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};
SQL

  # Load schema only if it is not present yet. createdb.sql starts with SET ROLE miningcore;
  # so keep the default role/database names unless the operator explicitly customizes later.
  if ! sudo -u postgres psql -d "$db_name" -tAc "SELECT to_regclass('public.shares')" | grep -q shares; then
    # The repository may live under /root, which the postgres system user cannot
    # traverse. Read the schema as root and pipe it into psql running as postgres
    # instead of asking postgres to open the file path directly.
    sudo -u postgres psql -d "$db_name" -v ON_ERROR_STOP=1 < "$REPO_ROOT/src/Miningcore/Persistence/Postgres/Scripts/createdb.sql"
  fi

  sudo -u postgres psql -d "$db_name" -v ON_ERROR_STOP=1 <<SQL
GRANT USAGE ON SCHEMA public TO ${db_user};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${db_user};
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ${db_user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${db_user};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO ${db_user};
SQL
}

build_install_miningcore() {
  ensure_build_swap
  local jobs
  jobs="$(default_build_jobs)"
  install -d -o root -g root -m 0755 /opt/miningcore
  install -d -o root -g miningcore -m 0750 /etc/miningcore
  install -d -o miningcore -g miningcore -m 0750 /var/lib/miningcore /var/log/miningcore

  echo "Publishing Miningcore (.NET 10). This also builds native hashing libraries with BUILD_JOBS=${jobs}..."
  (cd "$REPO_ROOT" && BUILD_JOBS="$jobs" CMAKE_BUILD_PARALLEL_LEVEL="$jobs" dotnet publish src/Miningcore/Miningcore.csproj \
    -c Release --framework net10.0 -o /opt/miningcore)

  harden_tree_readonly /opt/miningcore
  chown -R miningcore:miningcore /var/lib/miningcore /var/log/miningcore
  chmod 750 /var/lib/miningcore /var/log/miningcore
}

build_install_multiflexcoin() {
  local src_dir="${MFLEX_SOURCE_DIR:-/usr/local/src/multiflexcoin}"
  local repo_url="${MFLEX_REPO_URL:-https://github.com/Aalnase/multiflexcoin.git}"
  local branch="${MFLEX_BRANCH:-main}"
  local jobs
  jobs="$(default_build_jobs)"

  install -d -o root -g root -m 0755 /usr/local/src /opt/multiflexcoin
  install -d -o root -g multiflex -m 0750 /etc/multiflexcoin
  install -d -o multiflex -g multiflex -m 0750 /var/lib/multiflexcoin

  if [[ ! -d "$src_dir/.git" ]]; then
    git clone --depth 1 --branch "$branch" "$repo_url" "$src_dir"
  else
    git -C "$src_dir" fetch --depth 1 origin "$branch"
    git -C "$src_dir" checkout "$branch"
    git -C "$src_dir" reset --hard "origin/$branch"
  fi

  echo "Building Multiflex Core from source with BUILD_JOBS=${jobs}. This can take a while..."
  (cd "$src_dir" && make -C depends -j"$jobs")
  local toolchain
  toolchain="$(find "$src_dir/depends" -path '*/toolchain.cmake' | head -n1)"
  if [[ -z "$toolchain" ]]; then
    echo "Could not locate Multiflex depends toolchain.cmake" >&2
    exit 1
  fi
  cmake -S "$src_dir" -B "$src_dir/build" --toolchain "$toolchain" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_GUI=OFF -DBUILD_TESTS=OFF -DBUILD_BENCH=OFF
  cmake --build "$src_dir/build" --parallel "$jobs" --target bitcoind bitcoin-cli
  # Install only the daemon and CLI components. Installing all components would
  # also try to install the optional wrapper binary, which is disabled in this
  # build and may not exist.
  cmake --install "$src_dir/build" --prefix /opt/multiflexcoin --strip --component bitcoind
  cmake --install "$src_dir/build" --prefix /opt/multiflexcoin --strip --component bitcoin-cli

  harden_tree_readonly /opt/multiflexcoin
  chown -R multiflex:multiflex /var/lib/multiflexcoin
  chmod 750 /var/lib/multiflexcoin

  # Provide convenient stable command names.
  ln -sf /opt/multiflexcoin/bin/multiflexd /usr/local/bin/multiflexd
  ln -sf /opt/multiflexcoin/bin/multiflex-cli /usr/local/bin/multiflex-cli
}

generate_multiflex_conf() {
  local rpc_user="${MFLEX_RPC_USER:-mflexrpc}"
  local rpc_password="${MFLEX_RPC_PASSWORD:-$(random_secret)}"
  local rpc_port="${MFLEX_RPC_PORT:-26015}"
  local p2p_port="${MFLEX_P2P_PORT:-24200}"
  export MFLEX_RPC_USER="$rpc_user" MFLEX_RPC_PASSWORD="$rpc_password" MFLEX_RPC_PORT="$rpc_port" MFLEX_P2P_PORT="$p2p_port"

  backup_if_exists /etc/multiflexcoin/multiflex.conf
  cat > /etc/multiflexcoin/multiflex.conf <<EOF
server=1
daemon=0
listen=1
port=${p2p_port}
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=${rpc_port}
rpcuser=${rpc_user}
rpcpassword=${rpc_password}
zmqpubhashblock=tcp://127.0.0.1:26016
zmqpubhashtx=tcp://127.0.0.1:26017

# Home pools can keep pruning enabled to reduce disk usage. Public pools should
# generally run archival/full nodes.
prune=$([[ "${POOL_MODE}" == "home" ]] && echo 550 || echo 0)
EOF
  chown root:multiflex /etc/multiflexcoin/multiflex.conf
  chmod 640 /etc/multiflexcoin/multiflex.conf
}

generate_miningcore_config() {
  local pool_wallet="${MFLEX_POOL_ADDRESS:?MFLEX_POOL_ADDRESS must be generated before Miningcore config is written}"
  local pool_port="${MININGCORE_POOL_PORT:-3333}"
  local api_address api_rate_disabled payment_enabled min_diff start_diff max_diff

  if [[ "${POOL_MODE}" == "public" ]]; then
    api_address="127.0.0.1"
    api_rate_disabled="false"
    payment_enabled="true"
    min_diff=512
    start_diff=1024
    max_diff=1048576
  else
    api_address="127.0.0.1"
    api_rate_disabled="true"
    payment_enabled="false"
    min_diff=1
    start_diff=16
    max_diff=65536
  fi

  backup_if_exists /etc/miningcore/config.json
  python3 - "$REPO_ROOT/examples/multiflex_pool.json" "/etc/miningcore/config.json" <<PY
import json, os, sys
src, dst = sys.argv[1:]
with open(src) as f:
    data = json.load(f)
# Add the global sections normally expected by Miningcore examples.
data.setdefault('logging', {
    'level': 'info',
    'enableConsoleLog': True,
    'enableConsoleColors': True,
    'logFile': '/var/log/miningcore/miningcore.log',
    'apiLogFile': '/var/log/miningcore/api.log',
    'logBaseDirectory': '/var/log/miningcore',
    'perPoolLogFile': True,
})
data.setdefault('banning', {'manager': 'Integrated', 'banOnJunkReceive': True, 'banOnInvalidShares': False})
data.setdefault('notifications', {'enabled': False})
data['persistence'] = {'postgres': {
    'host': '127.0.0.1',
    'port': 5432,
    'user': os.environ['MININGCORE_DB_USER'],
    'password': os.environ['MININGCORE_DB_PASSWORD'],
    'database': os.environ['MININGCORE_DB_NAME'],
}}
data['paymentProcessing'] = {
    'enabled': '${payment_enabled}' == 'true',
    'interval': 600,
    'shareRecoveryFile': '/var/lib/miningcore/recovered-shares.txt',
}
data['api'] = {
    'enabled': True,
    'listenAddress': '${api_address}',
    'port': 4000,
    'metricsIpWhitelist': ['127.0.0.1'],
    'rateLimiting': {
        'disabled': '${api_rate_disabled}' == 'true',
        'rules': [{'Endpoint': '*', 'Period': '1s', 'Limit': 10}],
        'ipWhitelist': ['127.0.0.1'],
    },
}
pool = data['pools'][0]
pool['id'] = 'mflex'
pool['enabled'] = True
pool['coin'] = 'multiflex'
pool['address'] = '${pool_wallet}'
pool['ports'] = {'${pool_port}': {
    'listenAddress': '0.0.0.0',
    'difficulty': ${start_diff},
    'name': 'MFLEX ${POOL_MODE} mining',
    'varDiff': {
        'minDiff': ${min_diff},
        'maxDiff': ${max_diff},
        'targetTime': 15,
        'retargetTime': 90,
        'variancePercent': 30,
        'maxDelta': 200000,
    },
}}
pool['daemons'] = [{
    'host': '127.0.0.1',
    'port': int(os.environ['MFLEX_RPC_PORT']),
    'user': os.environ['MFLEX_RPC_USER'],
    'password': os.environ['MFLEX_RPC_PASSWORD'],
    'httpPath': '/wallet/' + os.environ.get('MFLEX_WALLET_NAME', 'poolwallet'),
}]
pool['paymentProcessing']['enabled'] = '${payment_enabled}' == 'true'
with open(dst, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PY
  install -d -o miningcore -g miningcore -m 0750 /var/lib/miningcore
  chown root:miningcore /etc/miningcore/config.json
  chmod 640 /etc/miningcore/config.json
}

install_systemd_units() {
  install -m 0644 "$REPO_ROOT/contrib/install/miningcore.service" /etc/systemd/system/miningcore.service
  install -m 0644 "$REPO_ROOT/contrib/install/multiflexd.service" /etc/systemd/system/multiflexd.service
  systemctl daemon-reload
  systemctl enable multiflexd miningcore
}

multiflex_cli() {
  /opt/multiflexcoin/bin/multiflex-cli -conf=/etc/multiflexcoin/multiflex.conf -datadir=/var/lib/multiflexcoin "$@"
}

multiflex_wallet_cli() {
  /opt/multiflexcoin/bin/multiflex-cli -conf=/etc/multiflexcoin/multiflex.conf -datadir=/var/lib/multiflexcoin -rpcwallet="${MFLEX_WALLET_NAME}" "$@"
}

start_multiflex_and_generate_pool_address() {
  systemctl start multiflexd
  echo "Waiting for Multiflex RPC..."
  local i
  for i in $(seq 1 120); do
    if multiflex_cli getblockchaininfo >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  if ! multiflex_cli getblockchaininfo >/dev/null 2>&1; then
    echo "Multiflex RPC did not become ready within 240 seconds" >&2
    journalctl -u multiflexd -n 80 --no-pager || true
    exit 1
  fi

  if [[ -n "${MFLEX_POOL_ADDRESS:-}" ]]; then
    echo "Using operator-provided MFLEX pool address: ${MFLEX_POOL_ADDRESS}"
    export MFLEX_POOL_ADDRESS
    return
  fi

  if ! multiflex_wallet_cli getwalletinfo >/dev/null 2>&1; then
    echo "Creating/loading MFLEX wallet '${MFLEX_WALLET_NAME}' for pool payouts..."
    multiflex_cli loadwallet "${MFLEX_WALLET_NAME}" >/dev/null 2>&1 \
      || multiflex_cli createwallet "${MFLEX_WALLET_NAME}" false false "" false true >/dev/null 2>&1 \
      || multiflex_cli createwallet "${MFLEX_WALLET_NAME}" >/dev/null
  fi

  MFLEX_POOL_ADDRESS="$(multiflex_wallet_cli getnewaddress "" legacy 2>/dev/null || multiflex_wallet_cli getnewaddress)"
  export MFLEX_POOL_ADDRESS

  if ! multiflex_wallet_cli getaddressinfo "$MFLEX_POOL_ADDRESS" | jq -e '.ismine == true' >/dev/null 2>&1; then
    echo "Generated MFLEX address is not reported as wallet-owned: ${MFLEX_POOL_ADDRESS}" >&2
    exit 1
  fi
  echo "Generated MFLEX pool payout address: ${MFLEX_POOL_ADDRESS}"
}

configure_firewall() {
  ufw allow "${MININGCORE_POOL_PORT:-3333}/tcp" comment "Miningcore MFLEX stratum" >/dev/null || true
  ufw allow "${MFLEX_P2P_PORT:-24200}/tcp" comment "Multiflex P2P" >/dev/null || true
}

install_webui_https() {
  DOMAIN="$WEBUI_DOMAIN" LETSENCRYPT_EMAIL="$LETSENCRYPT_EMAIL" WEBROOT="${WEBROOT:-/var/www/miningcore-webui}" \
    "$REPO_ROOT/contrib/install/install-webui-simple.sh"
}

start_miningcore() {
  systemctl start miningcore
}

print_summary() {
  cat <<EOF

Installation complete.

WebUI URL: https://${WEBUI_DOMAIN}/
Pool mode: ${POOL_MODE}
Miningcore: /opt/miningcore
Miningcore config: /etc/miningcore/config.json
Multiflex Core: /opt/multiflexcoin
Multiflex config: /etc/multiflexcoin/multiflex.conf

Generated values printed once for operator handoff:
  PostgreSQL database: ${MININGCORE_DB_NAME}
  PostgreSQL user:     ${MININGCORE_DB_USER}
  PostgreSQL password: ${MININGCORE_DB_PASSWORD}
  MFLEX RPC user:      ${MFLEX_RPC_USER}
  MFLEX RPC password:  ${MFLEX_RPC_PASSWORD}
  MFLEX RPC port:      ${MFLEX_RPC_PORT}
  MFLEX wallet name:   ${MFLEX_WALLET_NAME}
  MFLEX pool address:  ${MFLEX_POOL_ADDRESS}
  Miningcore port:     ${MININGCORE_POOL_PORT:-3333}

Services:
  sudo systemctl status multiflexd --no-pager
  sudo systemctl status miningcore --no-pager
  journalctl -u multiflexd -f
  journalctl -u miningcore -f

Important: copy these generated passwords now if you need them. They are
also present in root-readable service config files, but this summary is the
only place the installer intentionally prints them.
EOF
}

main() {
  require_root
  require_ubuntu_24_plus
  collect_install_inputs
  install_base_packages
  install_postgresql18
  setup_users
  setup_postgres_schema
  build_install_miningcore
  build_install_multiflexcoin
  generate_multiflex_conf
  install_systemd_units
  start_multiflex_and_generate_pool_address
  generate_miningcore_config
  configure_firewall
  start_miningcore
  install_webui_https
  print_summary
}

main "$@"
