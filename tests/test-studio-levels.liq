# Minimal settings and dependencies required to load the studio input helpers.
let SRT_PASSPHRASE = "test-passphrase"
let SILENCE_SWITCH_SECONDS = 15.0
let AUDIO_VALID_SECONDS = 15.0
let SILENCE_THRESHOLD = -40.0

%include "../conf/lib/10_logging.liq"
%include "../conf/lib/20_state.liq"
%include "../conf/lib/30_silence.liq"
%include "../conf/lib/41_source_studio.liq"

assert(studio_amplitude_to_dbfs(1.0) == 0.0)
assert(studio_amplitude_to_dbfs(0.1) == -20.0)
assert(studio_amplitude_to_dbfs(0.0) == studio_level_floor_dbfs)
assert(studio_amplitude_to_dbfs(0.0000001) == studio_level_floor_dbfs)
assert(null.get(studio_level_or_null(true, 0.1)) == -20.0)
assert(not null.defined(studio_level_or_null(false, 1.0)))

shutdown()
