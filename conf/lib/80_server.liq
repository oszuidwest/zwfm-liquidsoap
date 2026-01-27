# Server socket infrastructure and global runtime commands
# Connect with: socat - UNIX-CONNECT:/tmp/liquidsoap/liquidsoap.sock

# Server socket configuration
let SERVER_SOCKET_ENABLED =
  environment.get("SERVER_SOCKET_ENABLED", default="true") == "true"
let SERVER_SOCKET_PATH =
  environment.get(
    "SERVER_SOCKET_PATH",
    default="/tmp/liquidsoap/liquidsoap.sock"
  )

# Initialize server socket if enabled
if
  SERVER_SOCKET_ENABLED
then
  log(
    "Server socket enabled at #{SERVER_SOCKET_PATH}",
    level=3
  )
  settings.server.socket := true
  settings.server.socket.path := SERVER_SOCKET_PATH

  # Register silence detection commands
  server.register(
    description="Enable silence detection",
    "silence.enable",
    fun (_) ->
      begin
        set_silence_detection(true)
        "Silence detection enabled"
      end
  )

  server.register(
    description="Disable silence detection",
    "silence.disable",
    fun (_) ->
      begin
        set_silence_detection(false)
        "Silence detection disabled"
      end
  )

  server.register(
    description="Get silence detection status",
    "silence.status",
    fun (_) ->
      begin
        if is_silence_detection_enabled() then "enabled" else "disabled" end
      end
  )
else
  log(
    "Server socket disabled",
    level=3
  )
end
