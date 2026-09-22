# Radio source factory
# Builds the main radio source from named inputs with fallback, force support,
# and server commands — all derived from a single source list

# Register server commands for the radio source (status, force, auto, skip)
def register_radio_commands(s, active_source, ~sources) =
  if
    SERVER_SOCKET_ENABLED
  then
    let source_id = source.id(s)

    # Get status command
    server.register(
      description="Show current mode and active source",
      "#{source_id}.status",
      fun (_) ->
        "Mode: #{radio_mode()}, Active: #{active_source()}"
    )

    # Derive valid source names from the sources list
    let source_names = list.map(fun (item) -> fst(item), sources)
    let source_names_str =
      string.concat(
        separator=", ",
        source_names
      )

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
def create_radio(~sources, ~studio_inputs) =
  # Build auto fallback chain from source priority order
  let source_list = list.map(fun (item) -> snd(item), sources)
  let auto_fallback =
    fallback(id="auto_fallback", track_sensitive=false, source_list)

  # Build switch entries: one force predicate per source + auto fallback
  let forced_entries =
    list.map(
      fun (item) ->
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

  # Ask the native switch/fallback operators which branch they selected. This
  # remains accurate when a requested forced source is unavailable.
  let names_by_id =
    list.map(fun ((name, src)) -> (source.id(src), name), sources)
  def active_source() =
    let selected = radio.selected()
    let selected =
      if
        null.defined(selected)
        and source.id(null.get(selected)) == source.id(auto_fallback)
      then
        auto_fallback.selected()
      else
        selected
      end
    null.case(
      selected,
      {"unknown"},
      fun (s) -> list.assoc(default="unknown", source.id(s), names_by_id)
    )
  end

  # Register server commands for source control
  register_radio_commands(radio, active_source, sources=sources)

  # Expose runtime status and accept optional external now-playing updates.
  register_http_endpoints(
    radio,
    active_source,
    sources=sources,
    studio_inputs=studio_inputs
  )

  radio
end
