# liquidsoap-ubuntu
This repository provides a comprehensive audio streaming stack tailored for [ZuidWest FM](https://www.zuidwestfm.nl/) in the Netherlands. Powered by [Liquidsoap](https://www.liquidsoap.info), this setup ensures seamless internet streaming and a continuous source for transmitters.

## Components:
1. **Liquidsoap**: The core audio router and transcoder.
2. **Icecast**: A public server for distributing the audio stream.
3. **StereoTool**: An optional integration for feeding [MicroMPX](https://www.thimeo.com/micrompx/) to transmitters.

## Scripts:
- **icecast2.sh**: Installs Icecast 2. Provides an option to use SSL via Let's Encrypt/Certbot.
- **install.sh**: Handles the installation of Liquidsoap 2.2.1 with fdkaac support. Enables Liquidsoap as a service that starts automatically.

## Configurations:
- **radio.liq**: A production-ready configuration for Liquidsoap. It integrates StereoTool as an audio processor (commented out by default).
- **liquidsoap.service**: A systemd service configuration for Liquidsoap.

## Compatibility:
This system is designed to run on Ubuntu 22.04 or Debian 12. It's made to be compatible with ARM platforms, including devices like Ampere Altra or Raspberry Pi. However, thorough testing on ARM is pending.

# MIT License

Copyright (c) 2023 Streekomroep ZuidWest

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
