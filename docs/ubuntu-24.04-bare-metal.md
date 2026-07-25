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

`coins.json` is intentionally left untouched. It remains a broad example catalog from which operators can copy the coin definitions they actually need.

## Public pool vs home pool

The installer asks for one of two profiles:

- `public`: intended for a public internet pool. Payment processing is enabled, API rate limiting is enabled, and the pool uses higher default difficulty.
- `home`: intended for a home/LAN pool. Payment processing is disabled by default, API binds to localhost, and the pool starts with lower difficulty.

Run interactively:

```bash
sudo ./contrib/install/install-ubuntu-24.04.sh
```

Or non-interactively:

```bash
sudo POOL_MODE=home ./contrib/install/install-ubuntu-24.04.sh
sudo POOL_MODE=public MFLEX_POOL_ADDRESS=M... ./contrib/install/install-ubuntu-24.04.sh
```

## Important files

- Miningcore binary: `/opt/miningcore/Miningcore`
- Miningcore config: `/etc/miningcore/config.json`
- Multiflex Core binary: `/opt/multiflexcoin/bin/bitcoind`
- MFLEX alias: `/usr/local/bin/multiflexd`
- Multiflex config: `/etc/multiflexcoin/multiflex.conf`
- Multiflex data: `/var/lib/multiflexcoin`
- Logs: `journalctl -u miningcore -f` and `journalctl -u multiflexd -f`

## After install

1. Edit `/etc/miningcore/config.json` and replace `YOUR_MFLEX_POOL_WALLET_ADDRESS` with your real MFLEX payout address.
2. Start Multiflex Core:

```bash
sudo systemctl start multiflexd
```

3. Wait until the node is synced enough for mining RPCs.
4. Start Miningcore:

```bash
sudo systemctl start miningcore
```

5. Check status:

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
