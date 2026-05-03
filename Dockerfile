# syntax=docker/dockerfile:1

# Build stage: Ubuntu 22.04 / Jammy with .NET SDK
FROM mcr.microsoft.com/dotnet/sdk:6.0-jammy AS build

WORKDIR /src

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      git \
      build-essential \
      cmake \
      ninja-build \
      ca-certificates \
      pkg-config \
      libssl-dev \
      libsodium-dev \
      libzmq3-dev \
      libboost-all-dev \
    && rm -rf /var/lib/apt/lists/*

COPY . .

RUN git submodule update --init --recursive || true

RUN dotnet publish src/Miningcore/Miningcore.csproj \
    -c Release \
    -p:UseAppHost=true \
    -o /app/build

# Runtime stage: Ubuntu 22.04 / Jammy with ASP.NET runtime
FROM mcr.microsoft.com/dotnet/aspnet:6.0-jammy AS runtime

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libssl3 \
      libsodium23 \
      libzmq5 \
      curl \
      tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/build/ /app/

EXPOSE 4000

ENTRYPOINT ["./Miningcore"]
CMD ["-c", "/config/config.json"]
