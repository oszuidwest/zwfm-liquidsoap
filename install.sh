# Update OS
sudo apt update -y 
sudo apt upgrade -y
sudo apt dist-upgrade -y
sudo apt autoremove -y
sudo apt install sudo opam -y

# Install the ocaml package manager
opam init -y

# Install dependencies and packages
opam install taglib mad lame vorbis cry flac samplerate ocurl liquidsoap liquidsoap-daemon fdkaac alsa --confirm-level unsafe-yes

#Set path
eval $(opam env)