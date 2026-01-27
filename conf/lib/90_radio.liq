# Radio source factory
# Builds the main radio source from named inputs with fallback, force support,
# and server commands — all derived from a single source list

# Register server commands for the radio source (status, force, auto, skip)
def register_radio_commands(s, ~sources) =
  if
    SERVER_SOCKET_ENABLED
  then
    let source_id = source.id(s)

    # Determine which source is currently active
    def get_active_source() =
      if
        not is_auto_mode()
      then
        get_forced_source()
      else
        # In auto mode, the first ready source in priority order is active
        let active = ref("unknown")
        list.iter(
          fun(item) ->
            begin
              let (name, src) = item
              if
                active() == "unknown" and source.is_ready(src)
              then
                active := name
              end
            end,
          sources
        )
        active()
      end
    end

    # Get status command
    server.register(
      description="Show current mode and active source",
      "#{source_id}.status",
      fun (_) ->
        begin
          let mode = if is_auto_mode() then "auto" else "forced" end
          let active = get_active_source()
          "Mode: #{mode}, Active: #{active}"
        end
    )

    # Derive valid source names from the sources list
    let source_names = list.map(fun(item) -> fst(item), sources)
    let source_names_str = string.concat(separator=", ", source_names)

    # Force specific source command
    server.register(
      description="Force a specific source (#{source_names_str})",
      "#{source_id}.force",
      fun (arg) ->
        begin
          if
            list.mem(arg, source_names)
          then
            set_forced_source(arg)
            "Forced source: #{arg}"
          else
            "Invalid source. Use: #{source_names_str}"
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

# Build the main radio source from a list of named sources in priority order
# Creates fallback chain, switch with force support, and registers server commands
# Returns the wired radio source
def create_radio(~sources) =
  # Build auto fallback chain from source priority order
  let source_list = list.map(fun(item) -> snd(item), sources)
  let auto_fallback =
    fallback(
      id="auto_fallback",
      track_sensitive=false,
      source_list
    )

  # Build switch entries: one force predicate per source + auto fallback
  let forced_entries =
    list.map(
      fun(item) ->
        begin
          let (name, src) = item
          ({should_use_source(name)}, src)
        end,
      sources
    )
  let radio =
    switch(
      id="radio_prod",
      track_sensitive=false,
      list.append(forced_entries, [({is_auto_mode()}, auto_fallback)])
    )

  # Register server commands for source control
  register_radio_commands(radio, sources=sources)

  radio
end
