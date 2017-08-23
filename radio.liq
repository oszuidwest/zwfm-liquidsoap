# Als de studio en fallback er niet zijn, spelen we dit
noodband = drop_metadata(single('/var/audio/fallback.ogg'))

# De studio voert hier zijn audio in
studio = drop_metadata(input.harbor('studio',port=8080,buffer=8.,max=20.,password='---'))

# De NLPO stream heeft een ander aanvoerpad en is handig als eerste fallback
studiofallback = drop_metadata(input.http('http://icecast.streamone.net/ZhYMCIqSRcQS,buffer=8.,max=20.'))

# Fallback en live combineren
radio = fallback (track_sensitive=false, [ strip_blank(max_blank=15.,min_noise=30.,studio), strip_blank(max_blank=15.,min_noise=30.,studiofallback), noodband ])

# STL
output.icecast(%ogg(%flac),
  host='icecast.zuidwestfm.nl', port=80, password='---', mount='/zuidwest.stl', name='ZuidWest FM', description='Studio to Transmitter (ongecomprimeerde audio)', radio)

# WEB
output.icecast(%mp3(bitrate=192),
  host='icecast.zuidwestfm.nl', port=80, password='---', mount='/zuidwest.mp3', name='ZuidWest FM', description='Hoge Kwaliteit Stream (192kbit MP3)', radio)

# APP
output.icecast(%fdkaac(channels=2, samplerate=44100, bitrate=64, afterburner=false, aot='mpeg4_he_aac_v2', transmux='adts', sbr_mode=false),
  host='icecast.zuidwestfm.nl', port=80, password='---', mount='/zuidwest.aac', name='ZuidWest FM', description='iPad/Mobile Stream (64kbit AAC)', radio)
  

