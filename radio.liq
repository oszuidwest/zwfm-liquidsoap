# Server mag op alle ip-adressen luisteren
set("harbor.bind_addr","0.0.0.0")

# Als de studio er niet is, spelen we dit
noodband = single("/var/audio/fallback.ogg")

# De studio voert hier zijn audio in
radio = input.harbor("studio",port=8080,password="---")

radio = fallback(track_sensitive = false, [radio, noodband])

# STL
output.icecast(%vorbis.cbr(bitrate=320),
  host="icecast.zuidwestfm.nl", port=80, password="---", mount="/zuidwest.stl.test", radio)

# WEB
output.icecast(%mp3(bitrate=128),
  host="icecast.zuidwestfm.nl", port=80, password="---", mount="/zuidwest.mp3.test", radio)

# APP
output.icecast(%aacplus(bitrate=56),
  host="icecast.zuidwestfm.nl", port=80, password="---", mount="/zuidwest.aac.test", radio)
