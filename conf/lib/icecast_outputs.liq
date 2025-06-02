# Function to create an Icecast output with its own clock for stability
def output_icecast_stream(
  ~format,
  ~description,
  ~mount,
  ~source,
  ~host=null(),
  ~port=null(),
  ~user=null(),
  ~password=null(),
  ~name=null()
) =
  # Create a buffered source with its own clock
  clocked_source = mksafe(buffer(source))
  clock_id = "icecast_clock_#{mount}"
  clock.assign_new(id=clock_id, [clocked_source])

  # Use provided parameters or defaults
  actual_host = host ?? ICECAST_SERVER
  actual_port = port ?? ICECAST_PORT
  actual_user = user ?? "source"
  actual_password = password ?? ICECAST_PASSWORD
  actual_name = name ?? STATION_NAME_FULL

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
