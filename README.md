# zwfm-liquidsoap

[![CI](https://github.com/oszuidwest/zwfm-liquidsoap/actions/workflows/ci.yml/badge.svg)](https://github.com/oszuidwest/zwfm-liquidsoap/actions/workflows/ci.yml)
[![Docker Image](https://github.com/oszuidwest/zwfm-liquidsoap/actions/workflows/docker-image.yml/badge.svg)](https://github.com/oszuidwest/zwfm-liquidsoap/actions/workflows/docker-image.yml)

This repository contains an audio streaming solution tailored for [ZuidWest FM](https://www.zuidwestfm.nl/), [Radio Rucphen](https://www.rucphenrtv.nl/), and [BredaNu](https://www.bredanu.nl/) in the Netherlands. Leveraging [Liquidsoap](https://www.liquidsoap.info), it facilitates internet streaming with a reliable fallback mechanism and is capable of pushing MPX to broadcast transmitters via MicroMPX.

![liq-flow-fixed](https://github.com/user-attachments/assets/00b35131-5c30-418b-aea1-dd447ee12f49)

## System design
The system design involves delivering the broadcast through two pathways. Liquidsoap uses the main input (SRT 1) as much as possible. If it becomes unavailable or silent, the system switches to SRT 2. Should SRT 2 also become unavailable or silent, it then switches to an emergency track. Ideally, the broadcast is delivered synchronously over the two inputs via separate pathways.

### Components
1. **Liquidsoap**: Acts as the primary audio router and transcoder.
2. **Icecast**: Functions as a public server for distributing the audio stream.
3. **StereoTool**: Used as [MicroMPX](https://www.thimeo.com/micrompx/) encoder for feeding FM transmitters.
4. **ODR-AudioEnc**: Used as DAB+ audio encoder for feeding a DAB+ muxer.

### Satellites
1. **[rpi-audio-encoder](https://github.com/oszuidwest/rpi-audio-encoder)**: Software to turn a Raspberry Pi into a production grade SRT audio encoder.
2. **[rpi-umpx-decoder](https://github.com/oszuidwest/rpi-audio-encoder)**: Software to turn a Raspberry Pi into a production grade μMPX decoder.

## Installation & Usage

### Quick Install
```bash
# Install Liquidsoap
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/install.sh)"

# Optional: Install Icecast server
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/icecast2.sh)"
```

### Configuration
After installation, edit the environment file at `/opt/liquidsoap/.env` to configure your station settings.

Most configuration variables are centralized. Station-specific files only contain DME configuration (for Rucphen/BredaNu).

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
| **DAB+ Configuration** |
| `ODR_AUDIOENC_BITRATE` | DAB+ encoder bitrate | *(required)* | `128` | `conf/lib/defaults.liq` | All |
| `ODR_AUDIOENC_EDI_URL` | DAB+ EDI destination | *(required)* | `tcp://dab-mux.local:9001` | `conf/lib/defaults.liq` | All |
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
- **Station column**: "All" means used by all stations, "Rucphen/BredaNu" means used only by stations with DME
- **Default conventions**: `#{VARIABLE}` means the value is interpolated from another variable
- **File locations**: Most configuration variables are centralized in `conf/lib/defaults.liq`
- **Station-specific files**: Only contain DME configuration (for Rucphen/BredaNu) and station-specific logic

### Running with Docker
```bash
cd /opt/liquidsoap

# Start Liquidsoap
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
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
echo '1' > /opt/liquidsoap/silence_detection.txt

# Disable silence detection
echo '0' > /opt/liquidsoap/silence_detection.txt
```

Changes take effect immediately without restarting the service.

### Silence thresholds
The default silence detection parameters can be adjusted via environment variables:
- `MAX_BLANK`: Maximum silence duration in seconds (default: 15.0)
- `MIN_NOISE`: The minimum duration of continuous audio required for an input to be considered valid (default: 15.0)

## Streaming to SRT Inputs

The system accepts two SRT input streams on ports 8888 (primary) and 9999 (secondary). All connections must use encryption with the passphrase configured in `UPSTREAM_PASSWORD`.

### Live audio capture
```bash
# Stream from ALSA audio device (WAV in Matroska container)
ffmpeg -f alsa -channels 2 -sample_rate 48000 -i hw:0 \
  -codec:a pcm_s16le -vn -f matroska \
  "srt://liquidsoap.example.com:8888?passphrase=your_passphrase&mode=caller&transtype=live&latency=10000"
```

## Installation & Usage

### Quick Install
```bash
# Install Liquidsoap
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/install.sh)"

# Optional: Install Icecast server
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/oszuidwest/zwfm-liquidsoap/main/icecast2.sh)"
```

### Configuration
After installation, edit the environment file at `/opt/liquidsoap/.env` to configure:
- Stream passwords and mount points
- Server addresses
- StereoTool license key (if using)
- DAB+ encoder settings

### Running with Docker
```bash
cd /opt/liquidsoap

# Start Liquidsoap (without StereoTool)
docker-compose up -d

# OR start with StereoTool
docker-compose -f docker-compose.yml -f docker-compose.stereotool.yml up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### StereoTool GUI
If using StereoTool, access the web interface at: `http://localhost:8080`

### Emergency Broadcast Control
Control the emergency broadcast (noodband) fallback:
```bash
# Enable emergency broadcast
echo '1' > /opt/liquidsoap/use_noodband.txt

# Disable (use silence instead)
echo '0' > /opt/liquidsoap/use_noodband.txt
```

## Scripts
- **icecast2.sh**: Installs Icecast 2 with SSL support via Let's Encrypt/Certbot
- **install.sh**: Installs Liquidsoap with fdkaac and ODR tools support in Docker containers

## Configurations
- **radio.liq**: A production-ready Liquidsoap configuration that incorporates StereoTool as a MicroMPX encoder.
- **docker-compose.yml**: Docker Compose configuration including StereoTool support.

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

## Compatibility
1. Tested on Ubuntu 24.04 and Debian 12.
2. Supports x86_64 or ARM64 system architectures (e.g., Ampere Altra, Raspberry Pi). Note: StereoTool MicroMPX is currently not well-supported on ARM architectures.
3. Requires an internet connection for script dependencies.


# MIT License

Copyright 2025 Omroepstichting ZuidWest & Stichting BredaNu

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
