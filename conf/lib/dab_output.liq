# DAB+ output configuration using ODR-AudioEnc
# This library provides a reusable function for DAB+ encoding

# Function to create DAB+ output
# @param source The audio source to encode
def output_dab_stream(source) =
  # Check if DAB+ is configured
  if
    ODR_AUDIOENC_BITRATE != "" and ODR_AUDIOENC_EDI_URL != ""
  then
    log(
      "DAB+ output enabled - Bitrate: #{ODR_AUDIOENC_BITRATE}kbps, EDI: #{
        ODR_AUDIOENC_EDI_URL
      }",
      level=3
    )

    # Create a clock for DAB+ output
    audio_to_dab = mksafe(buffer(source))
    clock.assign_new(id="dab_clock", [audio_to_dab])

    # Build command with optional parameters
    odr_command =
      ref(
        "/bin/odr-audioenc -i - --bitrate=#{ODR_AUDIOENC_BITRATE}"
      )
    
    # Add PAD configuration if socket is set
    if
      ODR_PADENC_SOCK != ""
    then
      # PAD socket requires PAD to be enabled
      odr_command :=
        "#{odr_command()} --pad=#{ODR_PAD_SIZE} --pad-socket=#{ODR_PADENC_SOCK}"
    elsif
      ODR_PAD_SIZE != "58"
    then
      # Only add PAD parameter if it's different from default and no socket
      odr_command :=
        "#{odr_command()} --pad=#{ODR_PAD_SIZE}"
    end
    
    odr_command :=
      "#{odr_command()} --edi=\"#{ODR_AUDIOENC_EDI_URL}\""

    # Feed the audio to ODR-AudioEnc
    output.external(
      %wav(channels = 2, samplerate = 48000), odr_command(), audio_to_dab
    )
  else
    log(
      "DAB+ output disabled - ODR_AUDIOENC_BITRATE and/or ODR_AUDIOENC_EDI_URL \
       not configured",
      level=3
    )
  end
end
