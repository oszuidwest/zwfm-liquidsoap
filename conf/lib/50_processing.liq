# Audio processing configuration
# StereoTool integration for broadcast-quality audio

# Check if StereoTool is enabled via license key
let stereotool_enabled = STEREOTOOL_LICENSE != ""

# Create processed audio source
# Returns StereoTool-processed audio if licensed, otherwise returns input unchanged
def create_processed_audio(radio) =
  if
    stereotool_enabled
  then
    log(
      "StereoTool enabled - processing audio",
      level=3
    )

    let processed =
      stereotool(
        library_file="/var/cache/liquidsoap/st_plugin.so",
        license_key=STEREOTOOL_LICENSE,
        preset="/var/cache/liquidsoap/.st_plugin.so.rc",
        active=true,
        mksafe(radio)
      )

    # Validate license and warn if invalid
    if
      not processed.valid_license()
    then
      log(
        "WARNING: StereoTool license invalid! Audio will have artifacts. \
         Features: #{processed.unlincensed_used_features()}",
        level=2
      )
    end

    processed
  else
    log(
      "StereoTool disabled - radio_processed will contain unprocessed audio",
      level=3
    )
    radio
  end
end
