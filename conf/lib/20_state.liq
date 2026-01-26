# Runtime state management
# Mutable state for silence detection and source forcing
# Controlled via server socket commands (see 90_server.liq)

# Silence detection state
# Default: enabled. Use silence.enable/silence.disable commands to change.
let silence_detection_enabled = ref(true)

# Check if silence detection is currently enabled
def is_silence_detection_enabled() =
  silence_detection_enabled()
end

# Set silence detection state
def set_silence_detection(enabled) =
  if
    enabled != silence_detection_enabled()
  then
    let old_state =
      if silence_detection_enabled() then "enabled" else "disabled" end
    let new_state = if enabled then "enabled" else "disabled" end
    silence_detection_enabled := enabled
    log_state_change("silence_detection", old_state, new_state)
  end
end

# Source forcing state
# Empty string = auto mode (normal fallback behavior)
# "studio_a", "studio_b", "fallback" = force that specific source
let forced_source_name = ref("")

# Get current forced source name (empty = auto)
def get_forced_source() =
  forced_source_name()
end

# Check if in auto mode (no forced source)
def is_auto_mode() =
  forced_source_name() == ""
end

# Check if a specific source should be forced
def should_use_source(name) =
  forced_source_name() == name
end

# Set forced source (or empty string for auto mode)
def set_forced_source(name) =
  forced_source_name := name
  if
    name == ""
  then
    log(
      "Source selection: AUTO mode",
      level=3
    )
  else
    log(
      "Source selection: FORCED to #{name}",
      level=3
    )
  end
end
