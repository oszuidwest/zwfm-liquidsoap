# Als de studio er niet is, spelen we dit
noodband = drop_metadata(single("/var/audio/fallback.ogg"))

# De studio voert hier zijn audio in
radio = drop_metadata(input.harbor("studio",port=8080,password="---"))

# Hier halen we de metadata op
metacontent = list.hd(get_process_lines("wget -qO- http://www.zuidwesttv.nl/teksttv/rds_programma.php"))

# Fallback en live combineren
radio = fallback (track_sensitive=false, [ strip_blank(max_blank=10.,min_noise=30.,radio) , noodband ])

# Metadata van script in stream inseren (werkt nog niet)
radio = map_metadata(test - test, radio)

# STL
output.icecast(%vorbis.cbr(bitrate=320),
  host="icecast.zuidwestfm.nl", port=80, password="---", mount="/zuidwest.stl.test", radio)

# WEB
output.icecast(%mp3(bitrate=128),
  host="icecast.zuidwestfm.nl", port=80, password="---", mount="/zuidwest.mp3.test", radio)

# APP
output.icecast(%aacplus(bitrate=56),
  host="icecast.zuidwestfm.nl", port=80, password="---", mount="/zuidwest.aac.test", radio)
