# OpenBMC Docker Build Environment

This directory contains Docker configuration for building and testing OpenBMC.

## Quick Start

### 1. Clone OpenBMC Repository

```bash
# From the docker/ directory
cd ..
git clone https://github.com/openbmc/openbmc.git
cd docker
```

### 2. Build the Docker Image

```bash
docker-compose build openbmc-builder
```

### 3. Start the Build Environment

```bash
docker-compose run --rm openbmc-builder
```

### 4. Inside the Container

```bash
# Initialize the build environment
cd /workspace/openbmc
. setup romulus

# Build OpenBMC
bitbake obmc-phosphor-image
```

## Services

### openbmc-builder

The main build environment with all Yocto dependencies.

```bash
# Interactive shell
docker-compose run --rm openbmc-builder

# Run a single build command
docker-compose run --rm openbmc-builder bash -c ". setup romulus && bitbake obmc-phosphor-image"
```

### openbmc-qemu

Run the built image in QEMU for testing.

```bash
# Start QEMU (requires built image)
docker-compose up openbmc-qemu

# Access the emulated BMC
ssh root@localhost -p 2222

# Access Redfish API
curl -k https://localhost:2443/redfish/v1
```

## Volume Mounts

| Volume | Purpose |
|--------|---------|
| `../openbmc` | OpenBMC source code |
| `openbmc-sstate-cache` | Build cache (persisted) |
| `openbmc-downloads` | Downloaded sources (persisted) |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `UID` | 1000 | User ID for file permissions |
| `GID` | 1000 | Group ID for file permissions |
| `BB_NUMBER_THREADS` | 4 | BitBake parallel tasks |
| `PARALLEL_MAKE` | -j4 | Make parallelism |

## Tips

### Optimize Build Performance

Edit `docker-compose.yml` to adjust parallelism:

```yaml
environment:
  - BB_NUMBER_THREADS=8
  - PARALLEL_MAKE=-j8
```

### Preserve Build State

The named volumes persist sstate-cache and downloads between builds. To clean:

```bash
docker-compose down -v
```

### Windows/macOS Considerations

- Use WSL2 on Windows for best performance
- Allocate at least 8GB RAM to Docker Desktop
- Store the repository on the Linux filesystem (WSL2), not Windows

## Troubleshooting

### Build fails with permission errors

Ensure UID/GID match your host user:

```bash
UID=$(id -u) GID=$(id -g) docker-compose build
```

### Out of disk space

Clean old build artifacts:

```bash
# Inside container
cd /workspace/openbmc/build
rm -rf tmp/work/*
```

### Slow builds

- Increase BB_NUMBER_THREADS and PARALLEL_MAKE
- Ensure sstate-cache volume is mounted
- Use SSD storage for Docker volumes
