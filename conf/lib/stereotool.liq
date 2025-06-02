# StereoTool audio processing configuration

# Get StereoTool license key
STEREOTOOL_LICENSE_KEY = environment.get("STEREOTOOL_LICENSE_KEY", default="")

# Check if StereoTool is enabled
stereotool_enabled = STEREOTOOL_LICENSE_KEY != ""

# Function to create processed audio source
# Returns either StereoTool-processed audio or unprocessed audio depending on license key
def create_processed_audio(radio) =
  if
    stereotool_enabled
  then
    log(
      "StereoTool enabled - processing audio",
      level=3
    )
    processed =
      stereotool(
        library_file="/var/cache/liquidsoap/st_plugin.so",
        license_key=STEREOTOOL_LICENSE_KEY,
        preset="/var/cache/liquidsoap/.st_plugin.so.rc",
        radio
      )

    # Send processed audio to a dummy output (required for StereoTool to function)
    # This activates the StereoTool processing chain even though we don't use this output directly
    output.dummy(processed)
    processed
  else
    log(
      "StereoTool disabled - radio_processed will contain unprocessed audio",
      level=3
    )
    radio
  end
end
