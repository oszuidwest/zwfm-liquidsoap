# Minimal settings and dependencies required to load the studio input helpers.
let SRT_PASSPHRASE = "test-passphrase"
let SILENCE_SWITCH_SECONDS = 15.0
let AUDIO_VALID_SECONDS = 15.0
let SILENCE_THRESHOLD = -40.0

%include "../conf/lib/10_logging.liq"
%include "../conf/lib/20_state.liq"
%include "../conf/lib/30_silence.liq"
%include "../conf/lib/41_source_studio.liq"

assert(null.get(studio_level_dbfs(true, 1.0)) == 0.0)
assert(null.get(studio_level_dbfs(true, 0.1)) == -20.0)
assert(null.get(studio_level_dbfs(true, 0.0)) == studio_level_floor_dbfs)
assert(null.get(studio_level_dbfs(true, 0.0000001)) == studio_level_floor_dbfs)
assert(not null.defined(studio_level_dbfs(false, 1.0)))

shutdown()
