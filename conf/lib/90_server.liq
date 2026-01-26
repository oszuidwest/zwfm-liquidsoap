# Server socket commands for runtime control
# Connect with: socat - UNIX-CONNECT:/tmp/liquidsoap/liquidsoap.sock

# Server socket configuration
let SERVER_SOCKET_ENABLED =
  environment.get("SERVER_SOCKET_ENABLED", default="true") == "true"
let SERVER_SOCKET_PATH =
  environment.get(
    "SERVER_SOCKET_PATH",
    default="/tmp/liquidsoap/liquidsoap.sock"
  )

# Register the main radio source for server commands
def register_radio_source(s) =
  # Register source-specific commands only when socket is enabled
  if SERVER_SOCKET_ENABLED then
    let source_id = source.id(s)

    # Get status command
    server.register(
      description="Show current mode and active source",
      "#{source_id}.status",
      fun (_) ->
        begin
          let mode = if is_auto_mode() then "auto" else "forced" end
          let forced = get_forced_source()
          "Mode: #{mode}, Forced: #{
            if forced == '' then 'none' else forced end
          }, Active: #{source_id}"
        end
    )

    # Force specific source command
    server.register(
      description="Force a specific source (studio_a, studio_b, fallback)",
      "#{source_id}.force",
      fun (arg) ->
        begin
          let valid_sources = ["studio_a", "studio_b", "fallback"]
          if list.mem(arg, valid_sources) then
            set_forced_source(arg)
            "Forced source: #{arg}"
          else
            "Invalid source. Use: studio_a, studio_b, or fallback"
          end
        end
    )

    # Return to auto mode command
    server.register(
      description="Return to automatic fallback mode",
      "#{source_id}.auto",
      fun (_) ->
        begin
          set_forced_source("")
          "Switched to AUTO mode"
        end
    )

    # Skip to next available source command
    server.register(
      description="Skip to next available source",
      "#{source_id}.skip",
      fun (_) ->
        begin
          source.skip(s)
          "Skipped to next source"
        end
    )
  end
end

# Initialize server socket if enabled
if SERVER_SOCKET_ENABLED then
  log("Server socket enabled at #{SERVER_SOCKET_PATH}", level=3)
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
  log("Server socket disabled", level=3)
end
