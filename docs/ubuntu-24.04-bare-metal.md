# Ubuntu 24.04+ bare-metal install

This fork can run without Docker. The supported bare-metal target is Ubuntu 24.04 or newer with .NET 10 and PostgreSQL 18+.

## What the installer does

`contrib/install/install-ubuntu-24.04.sh` installs and configures:

- .NET 10 SDK/runtime and native build dependencies
- PostgreSQL 18 from the official PostgreSQL APT repository when Ubuntu does not provide it
- the Miningcore PostgreSQL role/database/schema
- Aalnase Miningcore published to `/opt/miningcore`
- Multiflex Core from `https://github.com/Aalnase/multiflexcoin` built from source and installed to `/opt/multiflexcoin`
- `multiflexd.service` and `miningcore.service`
- a generated MFLEX pool config at `/etc/miningcore/config.json`
- the simple static WebUI with Nginx and Let's Encrypt HTTPS

The installer must be run with root privileges because it installs packages, writes `/etc` configs, installs binaries under `/opt`, and registers systemd units. The long-running services do **not** run as root: Miningcore runs as the `miningcore` system user and Multiflex Core runs as the `multiflex` system user.

At the beginning, the installer asks for:

- pool mode: `public` or `home`
- WebUI domain name; this domain must already point to the server
- Let's Encrypt email address for HTTPS certificate registration/renewal notices

The WebUI is always installed and HTTPS is always enabled. The installer keeps Stratum on port `3333`, generates PostgreSQL/RPC passwords automatically, starts Multiflex Core, creates/loads the local `poolwallet` wallet, generates the MFLEX pool payout address from that wallet, writes the Miningcore config, starts Miningcore, and prints the generated credentials once at the end.

`coins.json` is intentionally left untouched. It remains a broad example catalog from which operators can copy the coin definitions they actually need.

## Public pool vs home pool

The installer asks for one of two profiles:

- `public`: intended for a public internet pool. Payment processing is enabled, API rate limiting is enabled, the pool uses higher default difficulty, and the Miningcore API stays bound to localhost behind the HTTPS WebUI reverse proxy.
- `home`: intended for a home/LAN pool. Payment processing is disabled by default, API binds to localhost, and the pool starts with lower difficulty.

Run interactively:

```bash
sudo ./contrib/install/install-ubuntu-24.04.sh
```

Or non-interactively:

```bash
sudo POOL_MODE=home ./contrib/install/install-ubuntu-24.04.sh
sudo POOL_MODE=public WEBUI_DOMAIN=pool.example.com LETSENCRYPT_EMAIL=admin@example.com ./contrib/install/install-ubuntu-24.04.sh
```

## Important files

- Miningcore binary: `/opt/miningcore/Miningcore` (`root:root`, read-only to the service)
- Miningcore config: `/etc/miningcore/config.json` (`root:miningcore`, mode `640`; contains generated DB/RPC credentials)
- Miningcore data/logs: `/var/lib/miningcore`, `/var/log/miningcore` (`miningcore:miningcore`)
- Multiflex Core binary: `/opt/multiflexcoin/bin/bitcoind` (`root:root`, read-only to the service)
- MFLEX alias: `/usr/local/bin/multiflexd`
- Multiflex config: `/etc/multiflexcoin/multiflex.conf` (`root:multiflex`, mode `640`; contains generated RPC credentials)
- Multiflex data: `/var/lib/multiflexcoin` (`multiflex:multiflex`)
- WebUI root: `/var/www/miningcore-webui`
- WebUI URL: `https://<your-domain>/`
- Logs: `journalctl -u miningcore -f` and `journalctl -u multiflexd -f`

This layout keeps `/opt` binaries and `/etc` configs protected from the service users. Runtime write access is limited through systemd to the specific `/var/lib/...` and `/var/log/...` paths the daemons need.

## After install

1. Check Multiflex Core:

```bash
sudo systemctl status multiflexd --no-pager
```

2. Check Miningcore:

```bash
sudo systemctl status miningcore --no-pager
```

3. Follow logs if needed:

```bash
sudo systemctl status multiflexd --no-pager
sudo systemctl status miningcore --no-pager
journalctl -u miningcore -f
```

## Updating

Re-run the installer from an updated checkout. It rebuilds Miningcore and Multiflex Core, refreshes systemd units, and creates timestamped backups of existing config files before regenerating them.

## Notes

- PostgreSQL 18+ is enforced by Miningcore startup when PostgreSQL persistence is configured.
- The installer does not remove legacy/example coins from `coins.json` by design.
- Multiflex Core still uses upstream Bitcoin binary names internally (`bitcoind`, `bitcoin-cli`); the installer adds `multiflexd` and `multiflex-cli` symlinks for operator convenience.
