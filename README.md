# liquidsoap-ubuntu
Liquidsoap + fdkaac + Icecast2 + StereoTool on Ubuntu 22.04 LTS or Debian 12. Used for internet streaming and feeding transmitters a source that's never silent.

## What's here?
This repository contains the audio streaming stack for [ZuidWest FM](https://www.zuidwestfm.nl/) in the Netherlands. It uses [Liquidsoap](https://www.liquidsoap.info) as audio router and transcoder, [Icecast](https://www.icecast.org) as public server and recently [StereoTool](https://www.thimeo.com/stereo-tool/) for feeding [MicroMPX](https://www.thimeo.com/micrompx/) to transmitters.

### Scripts
`icecast2.sh` Script that installs Icecast 2 with optional SSL via Let's Encrypt/Certbot.

`install.sh` Script that installs Liquidsoap 2.2.1 with fdkaac support. It also enables Liquidsoap as service that automatically starts. The configuration is in `/etc/liquidsoap/radio.liq`.

### Liquidsoap configurations
`radio.liq` Production ready Liquidsoap transcoder. Accepts a high quality (preferably ogg/flac) stream over SRT and transcodes it to mp3, aac and ogg/flac. Also integrates a silence detector that fires after 15 seconds of silence. Integrates StereoTool as audio processor (commented out by default)

## A word on ARM platforms
This system should be able to run on an ARM platform, like Ampere Altra of Raspberry Pi. We will eventually run this on an ARM instance, but it's not tested very thorough.

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
