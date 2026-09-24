# Icecast output factory
# Creates Icecast outputs with automatic clock isolation

# Runtime health providers registered by each Icecast output, read by GET /status.
let icecast_output_health_providers = ref([])

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
  # Use provided parameters or fall back to defaults
  let actual_host = icecast_host ?? ICECAST_HOST
  let actual_port = icecast_port ?? ICECAST_PORT
  let actual_user = icecast_user ?? "source"
  let actual_password = icecast_password ?? ICECAST_SOURCE_PASSWORD
  let actual_name = stream_name ?? STATION_NAME

  # Unique id so clock warnings name the stream (host disambiguates shared mounts)
  def slug(s) =
    string.replace(pattern="[^A-Za-z0-9]+", (fun (_) -> "_"), s)
  end
  let stream_id = "icecast_#{slug(mount)}_#{slug(actual_host)}"

  # Buffer provides clock isolation - each creates a new clock domain
  let clocked_source = mksafe(buffer(id="buf_#{stream_id}", audio_source))
  let connected = ref(false)

  let icecast_output =
    output.icecast(
      id=stream_id,
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
  icecast_output.on_connect(synchronous=true, fun () -> connected := true)
  icecast_output.on_disconnect(synchronous=true, fun () -> connected := false)

  def health() =
    let started = icecast_output.is_started()
    let is_connected = connected()
    {
      id = stream_id,
      status =
        if is_connected then "ok" elsif started then "down" else "stopped" end,
      host = actual_host,
      port = actual_port,
      mount = mount,
      description = description,
      started = started,
      connected = is_connected
    }
  end

  icecast_output_health_providers :=
    list.append(icecast_output_health_providers(), [health])
  icecast_output
end

# Defined after the factory so the provider list carries health()'s full
# record type; defined earlier, the fields it does not touch become optional.
def icecast_health() =
  let streams =
    list.map(
      fun (get_health) -> get_health(),
      icecast_output_health_providers()
    )
  let status =
    if
      list.is_empty(streams)
    then
      "disabled"
    elsif
      list.for_all(fun (item) -> item.connected, streams)
    then
      "ok"
    elsif
      list.exists(fun (item) -> item.connected, streams)
    then
      "degraded"
    else
      "down"
    end
  {status = status, streams = streams}
end
