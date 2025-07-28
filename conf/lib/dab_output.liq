# DAB+ output configuration using ODR-AudioEnc
# This library provides a reusable function for DAB+ encoding

# Function to create DAB+ output
# @param source The audio source to encode
def output_dab_stream(source) =
  # Check if DAB+ is configured
  if
    DAB_BITRATE != "" and DAB_EDI_DESTINATIONS != ""
  then
    log(
      "DAB+ output enabled - Bitrate: #{DAB_BITRATE}kbps, EDI: #{
        DAB_EDI_DESTINATIONS
      }",
      level=3
    )

    # Create a clock for DAB+ output
    audio_to_dab = mksafe(buffer(source))
    clock.assign_new(id="dab_clock", [audio_to_dab])

    # Build command with optional parameters
    odr_command =
      ref(
        "/bin/odr-audioenc -i - --bitrate=#{DAB_BITRATE} --sbr"
      )

    # Add PAD configuration if socket is set
    if
      DAB_METADATA_SOCKET != ""
    then
      # PAD socket requires PAD to be enabled - default to 8 if not specified
      pad_size = if DAB_METADATA_SIZE != "" then DAB_METADATA_SIZE else "8" end
      odr_command :=
        "#{odr_command()} --pad=#{pad_size} --pad-socket=#{DAB_METADATA_SOCKET}"
    end

    # Add EDI outputs - supports comma-separated list
    edi_urls = string.split(separator=",", DAB_EDI_DESTINATIONS)
    list.iter(
      fun (url) ->
        begin
          # Trim whitespace from URL
          trimmed_url = string.trim(url)
          odr_command :=
            "#{odr_command()} --edi=\"#{trimmed_url}\""
        end,
      edi_urls
    )

    # Feed the audio to ODR-AudioEnc
    output.external(
      %wav(channels = 2, samplerate = 48000), odr_command(), audio_to_dab
    )
  else
    log(
      "DAB+ output disabled - DAB_BITRATE and/or DAB_EDI_DESTINATIONS not \
       configured",
      level=3
    )
  end
end
