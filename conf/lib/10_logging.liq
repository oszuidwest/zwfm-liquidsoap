# Logging utilities
# Centralized logging functions for consistent output format

# Log an event for a specific source/input
def log_event(source_id, event) =
  log(
    "#{source_id} #{event}",
    level=3
  )
end

# Log a state change with old and new values
def log_state_change(component, from_state, to_state) =
  log(
    "#{component}: #{from_state} -> #{to_state}",
    level=3
  )
end
