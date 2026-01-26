# DAB+ output configuration
# Uses ODR-AudioEnc for DAB+ encoding with EDI output

# Create DAB+ output stream
# Requires both DAB_BITRATE and DAB_EDI_DESTINATIONS to be configured
def output_dab_stream(audio_source) =
  if
    DAB_BITRATE != "" and DAB_EDI_DESTINATIONS != ""
  then
    log(
      "DAB+ output enabled - Bitrate: #{DAB_BITRATE}kbps, EDI: #{
        DAB_EDI_DESTINATIONS
      }",
      level=3
    )

    # Buffer provides clock isolation
    let audio_to_dab = mksafe(buffer(audio_source))

    # Build ODR-AudioEnc command
    let odr_command =
      ref(
        "/bin/odr-audioenc -i - --bitrate=#{DAB_BITRATE} --sbr"
      )

    # Add PAD configuration if socket is set
    if
      DAB_METADATA_SOCKET != ""
    then
      let pad_size =
        if DAB_METADATA_SIZE != "" then DAB_METADATA_SIZE else "8" end
      odr_command :=
        "#{odr_command()} --pad=#{pad_size} --pad-socket=#{DAB_METADATA_SOCKET}"
    end

    # Add EDI outputs - supports comma-separated list
    let edi_urls = string.split(separator=",", DAB_EDI_DESTINATIONS)
    list.iter(
      fun (edi_url) ->
        begin
          let trimmed_url = string.trim(edi_url)
          odr_command :=
            "#{odr_command()} --edi=\"#{trimmed_url}\""
        end,
      edi_urls
    )

    # Feed audio to ODR-AudioEnc
    output.external(
      %wav(channels = 2, samplerate = 48000),
      odr_command(),
      audio_to_dab
    )
  else
    log(
      "DAB+ output disabled - DAB_BITRATE and/or DAB_EDI_DESTINATIONS not \
       configured",
      level=3
    )
  end
end
