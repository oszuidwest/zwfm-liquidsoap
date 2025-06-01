# Icecast outputs configuration - common for all stations

# Function to output an icecast stream with common parameters
# Automatically creates a clock for each output to ensure stability
def output_icecast_stream(
  ~format,
  ~description,
  ~mount,
  ~source,
  ~clock_id=null(),
  ~host=null(),
  ~port=null(),
  ~password=null(),
  ~name=null(),
  ~user=null()
) =
  # Create a unique clock ID if not provided
  clock_name = if null.defined(clock_id) then null.get(clock_id) else "icecast_#{mount}" end

  # Create a clock-assigned source
  clocked_source = mksafe(buffer(source))
  clock.assign_new(id=clock_name, [clocked_source])

  # Use provided values or fall back to globals
  server_host = if null.defined(host) then null.get(host) else ICECAST_SERVER end
  server_port = if null.defined(port) then null.get(port) else ICECAST_PORT end
  server_password = if null.defined(password) then null.get(password) else ICECAST_PASSWORD end
  server_name = if null.defined(name) then null.get(name) else ICECAST_NAME end

  # Create the output with optional user parameter
  if
    null.defined(user)
  then
    output.icecast(
      format,
      fallible=false,
      host=server_host,
      port=server_port,
      password=server_password,
      name=server_name,
      description=description,
      mount=mount,
      user=null.get(user),
      clocked_source
    )
  else
    output.icecast(
      format,
      fallible=false,
      host=server_host,
      port=server_port,
      password=server_password,
      name=server_name,
      description=description,
      mount=mount,
      clocked_source
    )
  end
end
