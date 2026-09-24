# Runtime controls and shared output-health classification.

# Enabled by default; server commands can change it at runtime.
let silence_detection_enabled = ref(true)

# Read the current silence-detection state.
def is_silence_detection_enabled() =
  silence_detection_enabled()
end

# Log only actual silence-detection changes.
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

# Empty selects automatic fallback; otherwise the value is a source id.
let forced_source_name = ref("")

# Read the forced source name.
def get_forced_source() =
  forced_source_name()
end

# Check whether source selection is automatic.
def is_auto_mode() =
  forced_source_name() == ""
end

# Check whether a source is forced.
def should_use_source(name) =
  forced_source_name() == name
end

# Return the public source-selection mode.
def radio_mode() =
  if is_auto_mode() then "auto" else "forced" end
end

# Update the forced source; empty restores automatic selection.
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

# These states do not degrade aggregate health.
def status_healthy(status) =
  list.mem(status, ["ok", "starting", "unmonitored", "disabled"])
end
