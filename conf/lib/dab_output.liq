# DAB+ output configuration using ODR-AudioEnc
# This library provides a reusable function for DAB+ encoding

# Function to create DAB+ output
# @param source The audio source to encode
def output_dab_stream(source) =
  # Check if DAB+ is configured
  if ODR_AUDIOENC_BITRATE != "" and ODR_AUDIOENC_EDI_URL != "" then
    log("DAB+ output enabled - Bitrate: #{ODR_AUDIOENC_BITRATE}kbps, EDI: #{ODR_AUDIOENC_EDI_URL}", level=3)
    
    # Create a clock for DAB+ output
    audio_to_dab = mksafe(buffer(source))
    clock.assign_new(id="dab_clock", [audio_to_dab])

    # Build command with optional pad-socket parameter
    odr_command = ref("/bin/odr-audioenc -i - --bitrate=#{ODR_AUDIOENC_BITRATE}")
    if ODR_PADENC_SOCK != "" then
      odr_command := "#{odr_command()} --pad-socket=#{ODR_PADENC_SOCK}"
    end
    odr_command := "#{odr_command()} --edi=\"#{ODR_AUDIOENC_EDI_URL}\""

    # Feed the audio to ODR-AudioEnc
    output.external(
      %wav(channels = 2, samplerate = 48000),
      odr_command(),
      audio_to_dab
    )
  else
    log("DAB+ output disabled - ODR_AUDIOENC_BITRATE and/or ODR_AUDIOENC_EDI_URL not configured", level=3)
  end
end