#!/bin/bash
set -euo pipefail

# Ubuntu 24.04+ build script for Miningcore targeting .NET 10.
# Requires PostgreSQL 18+ at runtime when persistence.postgres is configured.

sudo apt-get update
sudo apt-get -y install \
  dotnet-sdk-10.0 \
  git \
  cmake \
  clang \
  ninja-build \
  build-essential \
  libssl-dev \
  pkg-config \
  libboost-all-dev \
  libsodium-dev \
  libzmq5 \
  libzmq3-dev \
  libgmp-dev \
  libc++-dev \
  zlib1g-dev

(
  cd src/Miningcore
  BUILDIR=${1:-../../build}
  echo "Building into $BUILDIR"
  dotnet publish -c Release --framework net10.0 -o "$BUILDIR"
)
