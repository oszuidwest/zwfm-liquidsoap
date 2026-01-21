# Server commands for runtime control
# Enable with SERVER_SOCKET_ENABLED=true in .env
# Access via: socat - UNIX-CONNECT:/tmp/liquidsoap.sock

# Server socket configuration
SERVER_SOCKET_ENABLED =
  environment.get("SERVER_SOCKET_ENABLED", default="false") == "true"
SERVER_SOCKET_PATH =
  environment.get("SERVER_SOCKET_PATH", default="/tmp/liquidsoap.sock")

if
  SERVER_SOCKET_ENABLED
then
  settings.server.socket := true
  settings.server.socket.path := SERVER_SOCKET_PATH
  log(
    "Server socket enabled at #{SERVER_SOCKET_PATH}",
    level=3
  )
end

# Register silence control commands (when socket is enabled)
# Note: set_silence_detection() is defined in defaults.liq
if
  SERVER_SOCKET_ENABLED
then
  server.register(
    namespace="silence",
    description="Enable silence detection and fallback switching",
    usage="silence.enable",
    "enable",
    fun (_) ->
      begin
        set_silence_detection(true)
        "Silence detection enabled"
      end
  )

  server.register(
    namespace="silence",
    description="Disable silence detection (studio silence won't trigger failover)",
    usage="silence.disable",
    "disable",
    fun (_) ->
      begin
        set_silence_detection(false)
        "Silence detection disabled"
      end
  )

  server.register(
    namespace="silence",
    description="Show current silence detection status",
    usage="silence.status",
    "status",
    fun (_) ->
      if
        silence_detection_state()
      then
        "Silence detection is ENABLED"
      else
        "Silence detection is DISABLED"
      end
  )

  log(
    "Server commands registered: silence.enable, silence.disable, silence.status",
    level=3
  )
end

# Function to register the main radio source for server control
# Call this from station config after creating the fallback source
def register_radio_source(radio_source) =
  if
    SERVER_SOCKET_ENABLED
  then
    # Register status command using source's register_command method
    radio_source.register_command(
      description="Show currently active source and mode",
      "status",
      fun (_) ->
        begin
          selected = radio_source.selected()
          forced = get_forced_source()
          mode =
            if
              forced == ""
            then
              "AUTO"
            else
              "FORCED (#{forced})"
            end
          active =
            if
              null.defined(selected)
            then
              "#{null.get(selected)}"
            else
              "none"
            end
          "Mode: #{mode}, Active: #{active}"
        end
    )

    # Register skip command
    radio_source.register_command(
      description="Skip current track (force transition)",
      "skip",
      fun (_) ->
        begin
          radio_source.skip()
          "Skip requested"
        end
    )

    # Register auto command (return to automatic fallback)
    radio_source.register_command(
      description="Return to automatic source selection",
      "auto",
      fun (_) ->
        begin
          set_forced_source("")
          "Switched to AUTO mode"
        end
    )

    # Register force command
    radio_source.register_command(
      description=
        "Force a specific source (studio_a, studio_b, fallback)",
      "force",
      fun (arg) ->
        begin
          valid_sources = ["studio_a", "studio_b", "fallback"]
          if
            list.mem(arg, valid_sources)
          then
            begin
              set_forced_source(arg)
              "Forced source: #{arg}"
            end
          else
            "Invalid source. Use: studio_a, studio_b, or fallback"
          end
        end
    )

    log(
      "Server commands registered: radio_prod.status, radio_prod.skip, radio_prod.auto, radio_prod.force",
      level=3
    )
  end
end
