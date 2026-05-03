# Aalnase Miningcore

Custom Miningcore fork maintained by Aalnase.

This fork is based on Miningcore and includes additional coin-specific integrations and fixes for selected coins, especially MFLEX / Multiflex, XELIS, and ZANO.

Active branch:

    main

There is no separate dev branch required for normal use.

---

## Overview

This repository contains a customized Miningcore version with:

- MFLEX / Multiflex support
- MFLEX-specific pool switch for config.json
- XELIS support fixes
- XELIS HashV3 native library integration
- Automatic build and copy of libxelishashv3.so during dotnet publish
- ZANO-related Miningcore compatibility fixes
- Native source integration under src/Native/
- Repository cleanup to avoid committing production configs, wallets, secrets, logs or database dumps

This fork is intended for operators who need these additional coin integrations on top of Miningcore.

---

## Clone

Clone the repository including submodules:

    git clone --recurse-submodules -b main https://github.com/Aalnase/aalnase-miningcore.git miningcore

Or with SSH:

    git clone --recurse-submodules -b main git@github.com:Aalnase/aalnase-miningcore.git miningcore

Enter the directory:

    cd miningcore

If the repository was cloned without submodules, initialize them manually:

    git submodule update --init --recursive

---

## Requirements

Install typical build dependencies:

    sudo apt update
    sudo apt install -y git build-essential cmake

Install the .NET SDK required by this Miningcore version.

Check your installed .NET version:

    dotnet --version

---

## Build

Build and publish Miningcore:

    dotnet publish src/Miningcore/Miningcore.csproj \
      -c Release \
      -p:UseAppHost=true \
      -o build

After a successful build, the output directory should contain:

    build/Miningcore
    build/libxelishashv3.so

Check the build output:

    test -x build/Miningcore && echo "Miningcore OK"
    ls -lh build/libxelishashv3.so

---

## XELIS HashV3 native integration

This fork includes the XELIS HashV3 native library source under:

    src/Native/libxelishashv3/

During dotnet publish, the project automatically runs CMake and copies the resulting native library to the publish output:

    build/libxelishashv3.so

Manual copying is no longer required.

This is no longer needed:

    cp -a /tmp/xelis-hash/C/libxelishashv3.so build/

The build integration is handled by:

    src/Miningcore/Miningcore.csproj

---

## MFLEX / Multiflex support

This fork includes support for MFLEX, the ticker for Multiflex.

MFLEX requires coin-specific Miningcore behavior that is not part of standard upstream Miningcore. To keep this fork safe for other SHA256 coins, MFLEX-specific logic is enabled through a pool-level config switch.

For MFLEX pools, add this section to the pool object in config.json:

    "mflex": {
      "enabled": true
    }

Example pool section:

    {
      "id": "mflex",
      "enabled": true,
      "coin": "mflex",
      "address": "YOUR_POOL_WALLET_ADDRESS",

      "mflex": {
        "enabled": true
      }
    }

The important part is:

    "mflex": {
      "enabled": true
    }

When this switch is enabled, the fork applies MFLEX-specific behavior for that pool.

For non-MFLEX coins, do not add the mflex section, or set it to false:

    "mflex": {
      "enabled": false
    }

This keeps other coins compatible with normal Miningcore behavior.

---

A neutral example pool configuration is available at:

    examples/mflex_pool.json

This file contains placeholder values only. Replace wallet address, RPC user, RPC password, ports and payout settings with your own production values.

## MFLEX notes

MFLEX support is intended for Multiflex nodes and pools that require MFLEX-specific block construction, coinbase handling or block submission behavior.

Use the mflex.enabled switch only for MFLEX pools.

Before running MFLEX in production, test:

- daemon RPC connectivity
- wallet address configuration
- block template creation
- share validation
- block submission
- payouts
- pool startup
- miner connections
- error logs

If MFLEX-specific behavior is not enabled where required, standard Miningcore behavior may not be sufficient for the Multiflex network.

---

## ZANO notes

This fork also contains ZANO-related Miningcore changes.

The ZANO changes are intended to improve compatibility and runtime behavior for ZANO pool operation compared with the upstream base.

Before running ZANO in production, verify:

- daemon RPC configuration
- wallet RPC configuration
- pool address
- coin definition
- block template handling
- share validation
- block submission
- payout behavior

Useful check:

    grep -RIn "Zano\|ZANO\|zano" src examples || true

The exact production configuration depends on your local ZANO daemon, wallet and pool setup.

---

## Configuration

Production configuration files are not included in this repository.

Do not commit:

- config.json
- wallet files
- RPC usernames
- RPC passwords
- API keys
- database dumps
- runtime logs
- build output directories
- temporary files

Use your own local config.json on the server.

Example start command:

    cd /path/to/miningcore
    ./build/Miningcore -c config.json

---

## Security checks before committing

Before committing changes, check for secrets:

    git grep -n -i \
      -e 'rpcpass' \
      -e 'rpcuser' \
      -e 'wallet_pass' \
      -e 'api_key' \
      -e 'password' \
      || echo "No obvious secrets found"

Check for accidentally tracked runtime files:

    git ls-files | grep -Ei 'config\.json|wallet|wallet_pass|rpcpass|rpcuser|\.sql|\.dump|\.log' \
      && echo "WARNING: sensitive/runtime file tracked" \
      || echo "OK: no sensitive/runtime files tracked"

---

## Branch policy

Use only:

    main

The main branch is the active branch for cloning, building and deployment.

---

## Typical deployment flow

Clone:

    git clone --recurse-submodules -b main https://github.com/Aalnase/aalnase-miningcore.git miningcore
    cd miningcore

Build:

    dotnet publish src/Miningcore/Miningcore.csproj \
      -c Release \
      -p:UseAppHost=true \
      -o build

Check:

    test -x build/Miningcore && echo "Miningcore OK"
    ls -lh build/libxelishashv3.so

Run with your local config:

    ./build/Miningcore -c config.json

---

## Disclaimer

This is a custom Miningcore fork for selected coin integrations.

Before using it in production, always test your daemon, wallet, pool configuration, native libraries, block submission and payout behavior in a controlled environment.
