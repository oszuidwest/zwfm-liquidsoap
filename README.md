# zwfm-liquidsoap

[![CI](https://github.com/oszuidwest/zwfm-liquidsoap/actions/workflows/ci.yml/badge.svg)](https://github.com/oszuidwest/zwfm-liquidsoap/actions/workflows/ci.yml)
[![Docker Image](https://github.com/oszuidwest/zwfm-liquidsoap/actions/workflows/docker-image.yml/badge.svg)](https://github.com/oszuidwest/zwfm-liquidsoap/actions/workflows/docker-image.yml)

This repository contains a professional-grade audio streaming solution originally built for [ZuidWest FM](https://www.zuidwestfm.nl/), [Radio Rucphen](https://www.rucphenrtv.nl/), and [BredaNu](https://www.bredanu.nl/) in the Netherlands. Using [Liquidsoap](https://www.liquidsoap.info) as its core, it provides:

- **High-availability streaming** with automatic failover between multiple inputs
- **Professional audio processing** via StereoTool (optional)
- **Multiple output formats**: Icecast streaming (MP3/AAC), DAB+ encoding, and MicroMPX for FM transmitters
- **Docker-based deployment** for easy installation and management

While originally designed for these three Dutch radio stations, the system is fully configurable for any radio station's needs.

![Image](https://github.com/user-attachments/assets/e5bc7888-fb5d-4649-b42b-1474f0bd55f9)

## System Design
The system delivers audio through dual redundant pathways. Liquidsoap prioritizes the main input (SRT 1). If it becomes unavailable or silent, the system automatically switches to SRT 2. Should both inputs fail, it falls back to an emergency audio file. For maximum reliability, both inputs should receive the same broadcast via separate network paths.

### Components
1. **Liquidsoap**: Core audio processing engine - handles input switching, fallback logic, and encoding
2. **Icecast**: Public streaming server for distributing MP3/AAC streams to listeners
3. **StereoTool**: Professional audio processor and [MicroMPX](https://www.thimeo.com/micrompx/) encoder for FM transmitters (optional, requires license)
4. **ODR-AudioEnc**: DAB+ audio encoder for digital radio broadcasting (optional)

### Related Projects
1. **[rpi-audio-encoder](https://github.com/oszuidwest/rpi-audio-encoder)**: Turn a Raspberry Pi into a production-grade SRT audio encoder for studio connections
2. **[rpi-umpx-decoder](https://github.com/oszuidwest/rpi-umpx-decoder)**: Turn a Raspberry Pi into a μMPX decoder for FM transmitter sites
3. **[ODR-PadEnc](https://github.com/Opendigitalradio/ODR-PadEnc)**: Programme Associated Data encoder for DAB+ metadata
4. **[padenc-api](https://github.com/oszuidwest/padenc-api)**: REST API server for managing DAB+ metadata
5. **[zwfm-metadata](https://github.com/oszuidwest/zwfm-metadata)**: Metadata routing middleware for now-playing information

## Getting Started

### Requirements
- Linux server (Ubuntu 24.04 or Debian 12 recommended)
- Docker and Docker Compose installed
- x86_64 or ARM64 architecture
- At least 2GB RAM and 10GB disk space
- Network connectivity for SRT streams

### Quick Install
```bash
# Install Liquidsoap
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/install.sh)"

# Optional: Install Icecast server
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/icecast2.sh)"
```

### Configuration
After installation, edit the environment file at `/opt/liquidsoap/.env` to configure your station settings. Example configuration files are provided:
- `.env.zuidwest.example` - Basic configuration without DME
- `.env.rucphen.example` - Configuration with DME output
- `.env.bredanu.example` - Configuration with DME output

Copy the appropriate example file to `.env` and customize it for your station. Most configuration variables are centralized in `conf/lib/defaults.liq`. Station-specific files only contain DME configuration (for Rucphen/BredaNu).

## Environment Variables Reference

This table lists ALL environment variables used in the system. Variables without defaults are **required** and will cause Liquidsoap to fail if not set.

| Variable | Description | Default | Example | Used In | Station |
|----------|-------------|---------|---------|---------|---------|
| **Station Configuration** |
| `STATION_NAME_SHORT` | Short station name | *(required)* | `ZuidWest` | `conf/lib/defaults.liq` | All |
| `STATION_NAME_FULL` | Full station name for metadata | *(required)* | `Radio Rucphen` | `conf/lib/defaults.liq` | All |
| **Icecast Configuration** |
| `ICECAST_SERVER` | Icecast server hostname | *(required)* | `icecast.bredanu.nl` | `conf/lib/defaults.liq` | All |
| `ICECAST_PORT` | Icecast server port | *(required)* | `8000` | `conf/lib/defaults.liq` | All |
| `ICECAST_PASSWORD` | Icecast source password | *(required)* | `s3cur3p4ss` | `conf/lib/defaults.liq` | All |
| `ICECAST_MOUNTPOINT` | Base mount point name | lowercase(`STATION_NAME_SHORT`) | `zuidwest` | `conf/lib/defaults.liq` | All |
| **Stream Mount Points** |
| `HIGH_QUALITY_MOUNT` | MP3 stream mount | `/#{ICECAST_MOUNTPOINT}.mp3` | `/rucphen.mp3` | `conf/lib/defaults.liq` | All |
| `MOBILE_MOUNT` | AAC mobile stream mount | `/#{ICECAST_MOUNTPOINT}.aac` | `/bredanu.aac` | `conf/lib/defaults.liq` | All |
| `TRANSPORT_MOUNT` | AAC STL stream mount | `/#{ICECAST_MOUNTPOINT}.stl` | `/zuidwest.stl` | `conf/lib/defaults.liq` | All |
| **Audio Processing** |
| `UPSTREAM_PASSWORD` | SRT encryption passphrase | *(required)* | `alpha-bravo-charlie-delta` | `conf/lib/studio_inputs.liq` | All |
| `STEREOTOOL_LICENSE_KEY` | StereoTool license key | *(none)* | `ABC123DEF456...` | `conf/lib/stereotool.liq` | All |
| **Fallback & Control** |
| `FALLBACK_FILE` | Path to emergency audio file | `/audio/fallback.ogg` | `/audio/noodband.mp3` | `conf/lib/defaults.liq` | All |
| `SILENCE_DETECTION_FILE` | Silence detection control file | `/silence_detection.txt` | `/opt/silence.txt` | `conf/lib/defaults.liq` | All |
| `MAX_BLANK` | Max silence duration (seconds) | `15.0` | `20.0` | `conf/lib/defaults.liq` | All |
| `MIN_NOISE` | Min noise duration (seconds) | `15.0` | `10.0` | `conf/lib/defaults.liq` | All |
| **DAB+ Configuration (Optional)** |
| `ODR_AUDIOENC_BITRATE` | DAB+ encoder bitrate | *(none)* | `128` | `conf/lib/defaults.liq` | All |
| `ODR_AUDIOENC_EDI_URL` | DAB+ EDI destination(s) | *(none)* | `tcp://dab-mux.local:9001` or `tcp://dab1:9001,tcp://dab2:9002` | `conf/lib/defaults.liq` | All |
| `ODR_PAD_SIZE` | PAD size in bytes (0-255) | `58` when socket is set | `128` | `conf/lib/defaults.liq` | All |
| `ODR_PADENC_SOCK` | PAD metadata socket path | *(none)* | `padenc.sock` | `conf/lib/defaults.liq` | All |
| **DME Configuration** |
| `DME_INGEST_A_HOST` | Primary DME server | *(required)* | `ingest1.dme.nl` | `conf/rucphen.liq`, `conf/bredanu.liq` | Rucphen/BredaNu |
| `DME_INGEST_A_PORT` | Primary DME port | *(required)* | `8010` | `conf/rucphen.liq`, `conf/bredanu.liq` | Rucphen/BredaNu |
| `DME_INGEST_A_USER` | Primary DME username | *(required)* | `rucphen-live` | `conf/rucphen.liq`, `conf/bredanu.liq` | Rucphen/BredaNu |
| `DME_INGEST_A_PASSWORD` | Primary DME password | *(required)* | `dme123pass` | `conf/rucphen.liq`, `conf/bredanu.liq` | Rucphen/BredaNu |
| `DME_INGEST_B_HOST` | Secondary DME server | *(required)* | `ingest2.dme.nl` | `conf/rucphen.liq`, `conf/bredanu.liq` | Rucphen/BredaNu |
| `DME_INGEST_B_PORT` | Secondary DME port | *(required)* | `8020` | `conf/rucphen.liq`, `conf/bredanu.liq` | Rucphen/BredaNu |
| `DME_INGEST_B_USER` | Secondary DME username | *(required)* | `bredanu-backup` | `conf/rucphen.liq`, `conf/bredanu.liq` | Rucphen/BredaNu |
| `DME_INGEST_B_PASSWORD` | Secondary DME password | *(required)* | `backup456pwd` | `conf/rucphen.liq`, `conf/bredanu.liq` | Rucphen/BredaNu |
| `DME_MOUNT` | DME mount point | *(required)* | `/live-stream` | `conf/rucphen.liq`, `conf/bredanu.liq` | Rucphen/BredaNu |
| **Docker Configuration** |
| `TZ` | Container timezone | `Europe/Amsterdam` | `Europe/Amsterdam` | `docker-compose.yml` | All |

### Notes:
- **Required variables**: Must be set in `.env` file or Liquidsoap will fail to start
- **Optional features**: DAB+ output is optional - set both `ODR_AUDIOENC_BITRATE` and `ODR_AUDIOENC_EDI_URL` to enable. PAD metadata requires `ODR_PADENC_SOCK`
- **Multiple EDI outputs**: `ODR_AUDIOENC_EDI_URL` supports comma-separated values for sending to multiple DAB+ destinations simultaneously
- **Station column**: "All" means used by all stations, "Rucphen/BredaNu" means used only by stations with DME
- **Default conventions**: `#{VARIABLE}` means the value is interpolated from another variable
- **PAD sizes**: Valid range 0-255 bytes. Common values: 16 (text only), 58 (text + logo), 128 (text + album art)
- **File locations**: Most configuration variables are centralized in `conf/lib/defaults.liq`
- **Station-specific files**: Only contain DME configuration (for Rucphen/BredaNu) and station-specific logic

### Running with Docker
```bash
cd /opt/liquidsoap

# Start services
docker compose up -d

# View logs
docker compose logs -f

# Stop services
docker compose down
```

### StereoTool GUI
When StereoTool is enabled (by providing a `STEREOTOOL_LICENSE_KEY` in the `.env` file), access the web interface at: `http://localhost:8080`

### Audio Processing with StereoTool

StereoTool is always included in the installation. When enabled (by providing a `STEREOTOOL_LICENSE_KEY`), the system creates two audio paths:

1. **Unprocessed audio (`radio`)**: The raw combined audio from studios/fallback

2. **Processed audio (`radio_processed`)**: Audio processed by StereoTool
   - Audio processing (AGC, compression, limiting, EQ, etc.)
   - MicroMPX encoding for FM transmitters (available via StereoTool's separate output)

**Note**: The `output.dummy()` call is required to activate StereoTool's processing chain, even though this output isn't used directly.

## Silence Detection

The system includes automatic silence detection that monitors studio inputs and manages fallback behavior. This feature is **enabled by default**.

### How it works
When silence detection is **enabled** (default):
- Studio inputs automatically switch away when silent for more than 15 seconds
- If both studios are silent/disconnected, the system plays the fallback file
- If no fallback file exists, the system plays silence
- Provides automatic redundancy for unattended operation

When silence detection is **disabled**:
- Studio inputs continue playing even when silent
- No automatic switching between sources
- Fallback file is never used
- Useful for testing or when manual control is preferred

### Configuration
Control silence detection via the control file:
```bash
# Enable silence detection (default)
echo '1' > /silence_detection.txt

# Disable silence detection
echo '0' > /silence_detection.txt
```

Note: The actual path depends on your container volume mapping. By default, this file is located at `/silence_detection.txt` inside the container.

Changes take effect immediately without restarting the service.

### Silence thresholds
The default silence detection parameters can be adjusted via environment variables:
- `MAX_BLANK`: Maximum silence duration in seconds (default: 15.0)
- `MIN_NOISE`: The minimum duration of continuous audio required for an input to be considered valid (default: 15.0)

## Streaming to SRT Inputs

The system accepts two SRT input streams:
- **Port 8888**: Primary studio input (Studio A)
- **Port 9999**: Secondary studio input (Studio B)

All connections require encryption using the passphrase configured in `UPSTREAM_PASSWORD`.

### Example: Stream from Audio Device
```bash
# Stream from ALSA audio device (Linux)
ffmpeg -f alsa -channels 2 -sample_rate 48000 -i hw:0 \
  -codec:a pcm_s16le -vn -f matroska \
  "srt://liquidsoap.example.com:8888?passphrase=your_passphrase&mode=caller&transtype=live&latency=10000"

# Stream from file (for testing)
ffmpeg -re -i input.mp3 -c copy -f mpegts \
  "srt://liquidsoap.example.com:8888?passphrase=your_passphrase&mode=caller"
```

For production use, consider using [rpi-audio-encoder](https://github.com/oszuidwest/rpi-audio-encoder) for a dedicated hardware encoder.


## Scripts
- **icecast2.sh**: Installs Icecast 2 with SSL support via Let's Encrypt/Certbot
- **install.sh**: Installs Liquidsoap with fdkaac and ODR tools support in Docker containers

## Configurations
- **conf/zuidwest.liq**: Configuration for ZuidWest FM
- **conf/rucphen.liq**: Configuration for Radio Rucphen (includes DME output)
- **conf/bredanu.liq**: Configuration for BredaNu (includes DME output)
- **conf/lib/**: Shared library modules for all stations
- **docker-compose.yml**: Docker Compose configuration including StereoTool support

## Development

### CI/CD Pipeline

The project uses GitHub Actions for automated quality control and builds:

#### Continuous Integration (`ci.yml`)
Runs on all pushes to `main` and pull requests:
1. **Linting** - All checks run in parallel:
   - **ShellCheck**: Shell script analysis with warning-level severity
   - **Hadolint**: Dockerfile linting (ignores DL3008/DL3009 for apt packages)
   - **yamllint**: YAML validation with 120-char line limit
   - **Docker Compose**: Syntax validation with test environment
   - **Liquidsoap**: Syntax checking for all `.liq` files

2. **Auto-formatting** (main branch only, after linting passes):
   - **Prettier**: Formats YAML files
   - **liquidsoap-prettier**: Formats Liquidsoap `.liq` files
   - **dclint**: Formats Docker Compose files
   - Auto-commits changes with `[skip ci]` to prevent loops

3. **Build Test**: Multi-platform Docker build validation (amd64/arm64)

#### Docker Image Builds (`docker-image.yml`)
- **Schedule**: Daily at 3:00 AM UTC
- **Triggers**: Dockerfile changes or manual dispatch
- **Features**:
  - Automatically detects new versions of Liquidsoap and ODR-AudioEnc
  - Only builds when new version combinations are available
  - Multi-platform support (linux/amd64, linux/arm64)
  - Combined version tagging: `liquidsoap_version-odr_version`
  - Pushes to GitHub Container Registry (ghcr.io)

#### Maintenance
- **Workflow Cleanup** (`clean.yml`): Weekly cleanup of old workflow runs
- **Dependabot**: Automated updates for GitHub Actions and Docker base images

### Workflow Status
Check the badges at the top of this README for current CI/CD status. The pipeline uses concurrency control to cancel duplicate runs and caching for faster builds.

## Troubleshooting

### Common Issues

**Liquidsoap won't start**
- Check that all required environment variables are set in `.env`
- Verify Docker is running: `systemctl status docker`
- Check logs: `docker compose logs liquidsoap`

**No audio output**
- Verify SRT streams are reaching the server (check firewall rules for ports 8888/9999)
- Check silence detection status in `/silence_detection.txt`
- Ensure `UPSTREAM_PASSWORD` matches between encoder and server
- Test with a local file: `ffmpeg -re -i test.mp3 -c copy -f mpegts "srt://localhost:8888?passphrase=YOUR_PASSWORD&mode=caller"`

**StereoTool not working**
- Verify license key is correctly set in `STEREOTOOL_LICENSE_KEY`
- Check if web interface is accessible at port 8080
- For ARM systems, StereoTool support is limited

## Compatibility
- **OS**: Tested on Ubuntu 24.04 and Debian 12
- **Architecture**: x86_64 and ARM64 (e.g., Ampere Altra, Raspberry Pi)
- **Docker**: Requires Docker Engine and Docker Compose v2
- **Internet**: Required during installation for downloading dependencies

**Note**: StereoTool's MicroMPX encoder has limited support on ARM architectures. For ARM-based FM transmission, consider using external hardware encoders.


# MIT License

Copyright 2025 Omroepstichting ZuidWest & Stichting BredaNu

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
