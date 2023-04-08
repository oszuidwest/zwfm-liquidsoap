# liquidsoap-ubuntu
Liquidsoap + fdkaac + icecast2 on Ubuntu 22.04 LTS. Used for feeding transmitters a source that's never silent.

## What's here?
This repository contains the audio streaming stack for [ZuidWest FM](https://www.zuidwestfm.nl/) in the Netherlands. It uses [Liquidsoap](https://www.liquidsoap.info) as audio router and transcoder, [Icecast](https://www.icecast.org) as public server and recently [StereoTool](https://www.thimeo.com/stereo-tool/) for feeding [MicroMPX](https://www.thimeo.com/micrompx/) to transmitters (this is still experimental and we are reporting lots of upstream bugs).

### Scripts
`icecast2.sh` Script that installs Icecast 2 with optional SSL via Let's Encrypt/Certbot

`install.sh` Script that installs Liquidsoap 2.2 with fdkaac support. It also enables Liquidsoap as service that automatically starts. The configuration is in `/etc/liquidsoap/radio.liq` but there are other more experimental `.liq` files included too.

`stereotool.sh` Script that installs StereoTool for audio processing. Work in progress. Not finished or integrated.

### Liquidsoap configurations
`radio.liq` Production ready Liquidsoap transcoder. Accepts a high quality (preferably ogg/flac) stream over SRT and transcodes it to mp3, aac and ogg/flac. Also integrates a silence detector that fires after 15 seconds of silence.

## A word on ARM platforms
This system should be able to run on an ARM platform, like Ampere Altra of Raspberry Pi. StereoTool and MicroMPX are still very shaky on ARM. For example only 48KHz audio is supported in MicroMPX on ARM. We will eventually run this on an ARM intance, but for now x86-64 is more stable.

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
