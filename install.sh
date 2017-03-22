sudo apt-get -y install autoconf
sudo apt-get -y install libtool libtool-bin unzip
sudo apt-get -y install g++
sudo apt-get -y install make
sudo apt-get -y install libxml-dom-perl
sudo apt-get -y install festival
sudo apt-get -y install git
sudo apt-get -y install swh-plugins
sudo apt-get -y install libmagic-ocaml-dev
sudo apt-get -y install libcamomile-ocaml-dev
sudo apt-get -y install libxml-light-ocaml-dev
sudo apt-get -y install ocaml-compiler-libs
sudo apt-get -y install libfindlib-ocaml
sudo apt-get -y install libfindlib-ocaml-dev
sudo apt-get -y install libpulse-ocaml-dev
sudo apt-get -y install libmad-ocaml-dev
sudo apt-get -y install libtaglib-ocaml-dev
sudo apt-get -y install libvorbis-ocaml-dev
sudo apt-get -y install libsoundtouch-ocaml-dev
sudo apt-get -y install libsamplerate-ocaml-dev
sudo apt-get -y install libxmlplaylist-ocaml-dev
sudo apt-get -y install libdtools-ocaml-dev
sudo apt-get -y install libduppy-ocaml-dev
sudo apt-get -y install libpulse0 libpulse-dev
sudo apt-get -y install libasound2-dev
sudo apt-get -y install liblo liblo-dev
sudo apt-get -y install libmad0 libmad0-dev 
sudo apt-get -y install libspeex1 libspeex-dev
sudo apt-get -y install libtheora0 libtheora-dev
sudo apt-get -y install libvo-aacenc0 libvo-aacenc-dev
sudo apt-get -y install libfdk-aac0 libfdk-aac-dev
sudo apt-get -y install libsoundtouch0 libsoundtouch-dev
sudo apt-get -y install libsamplerate0 libsamplerate0-dev
sudo apt-get -y install libflac++-dev libflac++6 libflac8
sudo apt-get -y install liblame0 libmp3lame-dev
sudo apt-get -y install libmp3lame0 libmp3lame-dev
sudo apt-get -y install dssi-dev
sudo apt-get -y install libpulse0 libpulse-dev
sudo apt-get -y install libtag1c2a libtag1-dev
sudo apt-get -y install libvorbis0a libvorbis-dev
sudo apt-get -y install libopus0 libopus-dev
sudo apt-get -y install libfaad2 libfaad-dev
sudo apt-get -y install libao-dev
sudo apt-get -y install portaudio19-dev
sudo apt-get -y install libgstreamer0.10-dev libgstreamer-plugins-base0.10-dev
sudo apt-get -y install libshine-ocaml-dev
sudo apt-get -y install libflac-dev
sudo apt-get -y install liblo-dev

wget http://ffmpeg.gusari.org/uploads/libaacplus-2.0.2.tar.gz
tar xvf libaacplus-2.0.2.tar.gz
cd libaacplus-2.0.2
./autogen.sh
./configure
make
sudo make install
rm -rf libaacplus-2.0.2 libaacplus-2.0.2.tar.gz

wget https://github.com/savonet/liquidsoap/releases/download/1.2.1/liquidsoap-1.2.1-full.tar.gz
tar -xf liquidsoap-1.2.1-full.tar.gz
cd liquidsoap-1.2.1-full
wget https://raw.githubusercontent.com/rmens/liquidsoap-ubuntu/master/PACKAGES-for-audio -O PACKAGES
sudo useradd liquidsoap

./configure --disable-graphics --with-user=liquidsoap --with-group=liquidsoap --sysconfdir=/etc
make
sudo make install
cd liquidsoap-1.2.1
sudo make service-install
sudo update-rc.d liquidsoap defaults
sudo touch /etc/liquidsoap/radio.liq
