# Icecast output factory
# Creates Icecast outputs with automatic clock isolation

# Factory function to create an Icecast output
# Each output gets its own clock domain via buffer() for stability
def output_icecast_stream(
  ~format,
  ~description,
  ~mount,
  ~audio_source,
  ~icecast_host=null,
  ~icecast_port=null,
  ~icecast_user=null,
  ~icecast_password=null,
  ~stream_name=null
) =
  # Buffer provides clock isolation - each creates a new clock domain
  let clocked_source = mksafe(buffer(audio_source))

  # Use provided parameters or fall back to defaults
  let actual_host = icecast_host ?? ICECAST_HOST
  let actual_port = icecast_port ?? ICECAST_PORT
  let actual_user = icecast_user ?? "source"
  let actual_password = icecast_password ?? ICECAST_SOURCE_PASSWORD
  let actual_name = stream_name ?? STATION_NAME

  output.icecast(
    format,
    host=actual_host,
    port=actual_port,
    user=actual_user,
    password=actual_password,
    mount=mount,
    name=actual_name,
    description=description,
    clocked_source
  )
end
