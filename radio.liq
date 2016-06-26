# Als de studio er niet is, spelen we dit
noodband = drop_metadata(single("/var/audio/fallback.ogg"))

# De studio voert hier zijn audio in
radio = drop_metadata(input.harbor("studio",port=8080,buffer=8.,max=20.,password="---"))

# Hier halen we de metadata op
metacontent = list.hd(get_process_lines("wget -qO- http://www.zuidwesttv.nl/teksttv/rds_programma.php"))

# Fallback en live combineren
radio = fallback (track_sensitive=false, [ strip_blank(max_blank=15.,min_noise=30.,radio) , noodband ])

# Metadata van script in stream inseren (werkt nog niet)
radio = map_metadata(test - test, radio)

# STL
output.icecast(%ogg(%flac),
  host="icecast.zuidwestfm.nl", port=80, password="---", mount="/zuidwest.stl", name="ZuidWest FM", description="Studio to Transmitter (ongecomprimeerde audio)", radio)

# WEB
output.icecast(%mp3(bitrate=192),
  host="icecast.zuidwestfm.nl", port=80, password="---", mount="/zuidwest.mp3", name="ZuidWest FM", description="Hoge Kwaliteit Stream (192kbit MP3)", radio)

# APP
output.icecast(%aacplus(bitrate=64),
  host="icecast.zuidwestfm.nl", port=80, password="---", mount="/zuidwest.aac", name="ZuidWest FM", description="iPad/Mobile Stream (64kbit AAC)", radio)

