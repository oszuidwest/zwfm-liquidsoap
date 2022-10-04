# liquidsoap-ubuntu
Liquidsoap + fdkaac + icecast2 on Ubuntu 22.04 LTS. Used for feeding transmitters an 'unfallable' source.

## What's here?

### Scripts
`icecast2.sh` Script that installs Icecast 2 with optional SSL via Let's Encrypt/Certbot

`install.sh` Script that installs Liquidsoap 2.1 with fdkaac support. It also enables Liquidsoap as service that automatically starts. The configuration is in `/etc/liquidsoap/radio.liq`

`stereotool.sh` Script that install StereoTool for audio processing. Work in progress. Not finished or integrated.

### Liquidsoap configurations
`radio.liq` Production ready Liquidsoap transcoder. Accepts a high quality (preferably ogg/flac) stream and transcodes it to mp3, aac and ogg/flac. Also integrates a silence detector that fires after 15 seconds of silence.

`radio_experimental` Like `radio.liq` but with integrated StereoTool processing on all the strams (very experimental)

`radio_micrompx.liq` Like `radio.liq` but with intergrated MicroMPX for feeding transmitters MPX data (experimental)

# MIT License

Copyright (c) 2022 Streekomroep ZuidWest

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
