# Function to create an Icecast output with its own clock for stability
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
  # Buffer provides clock isolation between sources
  # Each buffer creates a new clock domain automatically
  clocked_source = mksafe(buffer(audio_source))

  # Use provided parameters or defaults
  actual_host = icecast_host ?? ICECAST_HOST
  actual_port = icecast_port ?? ICECAST_PORT
  actual_user = icecast_user ?? "source"
  actual_password = icecast_password ?? ICECAST_SOURCE_PASSWORD
  actual_name = stream_name ?? STATION_NAME

  # Output to Icecast
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
