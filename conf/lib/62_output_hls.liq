# HLS output configuration
# Writes a local HLS window and mirrors it to Bunny Edge Storage.
#
# Failure isolation: the HLS chain runs on its own clock with an on_error
# handler, so filesystem failures (permission denied, read-only, disk full)
# degrade HLS instead of shutting down the whole Liquidsoap process. A
# crashed output is detached by Liquidsoap and can never be restarted, so a
# watchdog creates a fresh output once HLS_DIR is writable again. Do NOT add
# persist_at to the output: writing state during the error-detach path
# re-raises on the dead clock thread and takes the process down with it.

let hls_bunny_headers = [("AccessKey", HLS_BUNNY_ACCESS_KEY), ("Expect", "")]
let hls_main_playlist_name = "live.m3u8"

let hls_enabled = HLS_BUNNY_STORAGE_ZONE != "" and HLS_BUNNY_ACCESS_KEY != ""

let hls_endpoint_trimmed = string.trim(HLS_BUNNY_ENDPOINT)
let hls_endpoint_without_https =
  string.residual(prefix="https://", hls_endpoint_trimmed)
    ?? hls_endpoint_trimmed
let hls_endpoint_without_scheme =
  string.residual(prefix="http://", hls_endpoint_without_https)
    ?? hls_endpoint_without_https
let hls_endpoint_host =
  r/\/+$/.replace(fun (_) -> "", hls_endpoint_without_scheme)

let hls_remote_dir_url =
  "https://#{hls_endpoint_host}/#{HLS_BUNNY_STORAGE_ZONE}/#{STATION_ID}/"

# Local output and Bunny mirroring fail independently, so each keeps its own
# error ("" means healthy) and recovering one cannot hide a failure in the other.
let hls_local_error = ref("")
let hls_mirror_error = ref("")

# Local progress comes from the writer's own playlist updates; mirror progress
# from the tick, where a complete successful pass proves the remote copy is
# current. Both stay null until the first progress.
let hls_local_last_update_at = ref(null)
let hls_mirror_last_sync_at = ref(null)

# The last mirror tick's local files and mirror state; GET /status derives its
# counts from it.
let hls_mirror_state =
  ref(
    {
      playlists = [],
      segment_names = [],
      synced_segments = [],
      synced_playlists = []
    }
  )

# Allow several segment intervals for scheduler and upload jitter before a
# writer or mirror that stopped making progress becomes degraded.
let hls_stale_after_seconds = max(15.0, HLS_SEGMENT_DURATION * 4.0)

# Set by any failed mirror call; the tick clears hls_mirror_error only after a
# full pass with content had no failure.
let hls_mirror_tick_failed = ref(false)

def hls_mark_mirror_degraded(reason) =
  hls_mirror_tick_failed := true
  hls_mirror_error := reason
  log(label="hls", reason, level=2)
end

def hls_progress_age(last_progress_at) =
  null.map(
    fun (progress_at) -> max(0.0, time() - progress_at),
    last_progress_at
  )
end

# An explicit failure wins over a stall; a component without any progress yet
# is still starting.
def hls_component_health(label, failure, age) =
  let failure =
    if
      failure == "" and (age ?? 0.0) > hls_stale_after_seconds
    then
      "#{label} has not advanced for #{int_of_float(null.get(age))}s"
    else
      failure
    end
  let status =
    if
      not hls_enabled
    then
      "disabled"
    elsif
      failure != ""
    then
      "degraded"
    elsif
      null.defined(age)
    then
      "ok"
    else
      "starting"
    end
  {status = status, error = if failure == "" then null else failure end}
end

def hls_health() =
  let local_age = hls_progress_age(hls_local_last_update_at())
  let mirror_age = hls_progress_age(hls_mirror_last_sync_at())
  let mirror_state = hls_mirror_state()
  let local =
    hls_component_health(
      "HLS local playlists",
      hls_local_error(),
      local_age
    )
  let mirror =
    hls_component_health(
      "HLS mirror",
      hls_mirror_error(),
      mirror_age
    )
  let statuses = [local.status, mirror.status]
  let status =
    if
      not hls_enabled
    then
      "disabled"
    elsif
      list.mem("degraded", statuses)
    then
      "degraded"
    elsif
      list.mem("starting", statuses)
    then
      "starting"
    else
      "ok"
    end

  {
    status = status,
    local =
      {
        ...local,
        playlist_count = list.length(mirror_state.playlists),
        segment_count = list.length(mirror_state.segment_names),
        update_age_seconds = local_age
      },
    mirror =
      {
        ...mirror,
        host = hls_endpoint_host,
        storage_zone = HLS_BUNNY_STORAGE_ZONE,
        sync_age_seconds = mirror_age,
        pending_segments =
          list.length(
            list.filter(
              fun (name) -> not list.mem(name, mirror_state.synced_segments),
              mirror_state.segment_names
            )
          ),
        pending_playlists =
          list.length(
            list.filter(
              fun (snapshot) ->
                not list.mem(
                  (snapshot.name, snapshot.content),
                  mirror_state.synced_playlists
                ),
              mirror_state.playlists
            )
          )
      }
  }
end

def hls_remote_url(remote_name) =
  "#{hls_remote_dir_url}#{remote_name}"
end

def hls_is_success(status_code) =
  200 <= status_code and status_code < 300
end

def hls_is_playlist_name(name) =
  r/\.m3u8$/.test(name)
end

# output.file.hls on_file_change handler. Variant playlists are rewritten on
# every segment, so the writer's own events prove local progress even while a
# slow mirror tick runs.
def hls_track_local_progress(change) =
  if
    change.state != "deleted"
    and hls_is_playlist_name(path.basename(change.path))
  then
    hls_local_last_update_at := time()
  end
end

def hls_is_segment_name(name) =
  r/\.(aac|ts)$/.test(name)
end

def hls_is_sync_file_name(name) =
  hls_is_playlist_name(name) or hls_is_segment_name(name)
end

def hls_add_unique(name, names) =
  if list.mem(name, names) then names else [name, ...names] end
end

def hls_union(names, extra_names) =
  list.fold(fun (acc, name) -> hls_add_unique(name, acc), names, extra_names)
end

def hls_assoc_set(key, value, values) =
  [(key, value), ...list.assoc.remove.all(key, values)]
end

def hls_put_data(remote_name, data) =
  try
    let response =
      http.put(
        timeout=10.0,
        headers=hls_bunny_headers,
        data=data,
        hls_remote_url(remote_name)
      )

    if
      hls_is_success(response.status_code)
    then
      true
    else
      hls_mark_mirror_degraded(
        "HLS mirror upload failed for #{remote_name}: HTTP #{
          response.status_code
        } #{response.status_message}"
      )
      false
    end
  catch err do
    hls_mark_mirror_degraded(
      "HLS mirror upload exception for #{remote_name}: #{err.kind}: #{
        err.message
      }"
    )
    false
  end
end

def hls_put_file(local_path) =
  let remote_name = path.basename(local_path)
  if
    not file.exists(local_path)
  then
    log(
      label="hls",
      "Skipping HLS upload for missing local file #{local_path}",
      level=3
    )
    false
  else
    try
      hls_put_data(remote_name, file.contents(local_path))
    catch err do
      log(
        label="hls",
        "HLS upload read exception for #{remote_name}: #{err.kind}: #{
          err.message
        }",
        level=2
      )
      false
    end
  end
end

def hls_delete_file(remote_name) =
  try
    let response =
      http.delete(
        timeout=10.0,
        headers=hls_bunny_headers,
        hls_remote_url(remote_name)
      )

    if
      hls_is_success(response.status_code) or response.status_code == 404
    then
      true
    else
      hls_mark_mirror_degraded(
        "HLS mirror delete failed for #{remote_name}: HTTP #{
          response.status_code
        } #{response.status_message}"
      )
      false
    end
  catch err do
    hls_mark_mirror_degraded(
      "HLS mirror delete exception for #{remote_name}: #{err.kind}: #{
        err.message
      }"
    )
    false
  end
end

def hls_local_files(name_predicate) =
  if
    file.exists(HLS_DIR)
  then
    list.filter(
      fun (fname) ->
        begin
          not file.is_directory(fname) and name_predicate(path.basename(fname))
        end,
      file.ls(absolute=true, sorted=true, HLS_DIR)
    )
  else
    []
  end
end

def hls_local_segment_files() =
  hls_local_files(hls_is_segment_name)
end

def hls_read_playlist_snapshot(local_path) =
  try
    {name = path.basename(local_path), content = file.contents(local_path)}
  catch err do
    log(
      label="hls",
      "Skipping HLS playlist snapshot for #{local_path}: #{err.kind}: #{
        err.message
      }",
      level=2
    )
    null
  end
end

def hls_playlist_snapshots() =
  list.filter_map(
    hls_read_playlist_snapshot,
    hls_local_files(hls_is_playlist_name)
  )
end

def hls_playlist_segment_names(content) =
  list.filter_map(
    fun (line) ->
      begin
        let line = string.trim(line)
        if hls_is_segment_name(line) then path.basename(line) else null end
      end,
    r/\r?\n/.split(content)
  )
end

def hls_snapshot_segment_names(playlists) =
  list.fold(
    fun (names, snapshot) ->
      hls_union(names, hls_playlist_segment_names(snapshot.content)),
    [],
    playlists
  )
end

def hls_remote_listing() =
  try
    let response =
      http.get(timeout=10.0, headers=hls_bunny_headers, hls_remote_dir_url)

    if
      hls_is_success(response.status_code)
    then
      let json.parse (remote_entries :
        [{"ObjectName" as object_name: string}]
      ) = response
      let names =
        list.map(
          fun ({object_name}) -> path.basename(object_name),
          remote_entries
        )
      {ok = true, names = list.filter(hls_is_sync_file_name, names)}
    elsif
      response.status_code == 404
    then
      log(
        label="hls",
        "Bunny HLS prefix #{STATION_ID}/ does not exist yet; local files will \
         create it",
        level=3
      )
      {ok = true, names = []}
    else
      hls_mark_mirror_degraded(
        "HLS mirror listing failed: HTTP #{response.status_code} #{
          response.status_message
        }"
      )
      {ok = false, names = []}
    end
  catch err do
    hls_mark_mirror_degraded(
      "HLS mirror listing exception: #{err.kind}: #{err.message}"
    )
    {ok = false, names = []}
  end
end

def hls_seed_remote_segments((seeded:ref), (synced_segments:ref)) =
  if
    not seeded()
  then
    let listing = hls_remote_listing()
    if
      listing.ok
    then
      let remote_segments = list.filter(hls_is_segment_name, listing.names)
      synced_segments.set(hls_union(synced_segments(), remote_segments))
      seeded.set(true)
      log(
        label="hls",
        "Seeded HLS mirror state with #{list.length(remote_segments)} remote \
         segment(s)",
        level=3
      )
    end
  end
end

def hls_upload_segments((synced_segments:ref), segment_files) =
  list.iter(
    fun (local_path) ->
      begin
        let remote_name = path.basename(local_path)
        if
          not list.mem(remote_name, synced_segments())
        then
          if
            hls_put_file(local_path)
          then
            synced_segments.set(hls_add_unique(remote_name, synced_segments()))
          end
        end
      end,
    segment_files
  )
end

def hls_required_segments_ready(snapshot, (synced_segments:ref)) =
  let segment_names = hls_playlist_segment_names(snapshot.content)
  list.for_all(
    fun (segment_name) -> list.mem(segment_name, synced_segments()),
    segment_names
  )
end

def hls_upload_playlist_group(
  (synced_playlists:ref),
  (synced_segments:ref),
  playlists
) =
  let ok = ref(true)
  list.iter(
    fun (snapshot) ->
      begin
        if
          not list.mem((snapshot.name, snapshot.content), synced_playlists())
        then
          if
            hls_required_segments_ready(snapshot, synced_segments)
          then
            if
              hls_put_data(snapshot.name, snapshot.content)
            then
              synced_playlists.set(
                hls_assoc_set(
                  snapshot.name,
                  snapshot.content,
                  synced_playlists()
                )
              )
            else
              ok := false
            end
          else
            log(
              label="hls",
              "Deferring HLS playlist upload for #{snapshot.name}; at least one \
               referenced segment is not mirrored yet",
              level=3
            )
            ok := false
          end
        end
      end,
    playlists
  )
  ok()
end

def hls_upload_playlists(
  (synced_playlists:ref),
  (synced_segments:ref),
  playlists
) =
  let variant_playlists =
    list.filter(fun (p) -> p.name != hls_main_playlist_name, playlists)
  let main_playlists =
    list.filter(fun (p) -> p.name == hls_main_playlist_name, playlists)
  let variants_ok =
    hls_upload_playlist_group(
      synced_playlists,
      synced_segments,
      variant_playlists
    )
  if
    variants_ok
    and not list.is_empty(variant_playlists)
    and not list.is_empty(main_playlists)
  then
    hls_upload_playlist_group(synced_playlists, synced_segments, main_playlists)
  else
    if
      not list.is_empty(main_playlists)
    then
      log(
        label="hls",
        "Deferring HLS main playlist upload until variant playlists are ready",
        level=3
      )
    end
    false
  end
end

def hls_delete_stale_segments((synced_segments:ref), protected_segment_names) =
  list.iter(
    fun (remote_name) ->
      begin
        if
          not list.mem(remote_name, protected_segment_names)
        then
          if
            hls_delete_file(remote_name)
          then
            synced_segments.set(
              list.filter(fun (name) -> name != remote_name, synced_segments())
            )
          end
        end
      end,
    synced_segments()
  )
end

def hls_mirror_tick(
  (seeded:ref),
  (synced_segments:ref),
  (synced_playlists:ref)
) =
  hls_mirror_tick_failed := false
  hls_seed_remote_segments(seeded, synced_segments)

  # Snapshot playlists before listing segments, then upload that exact content
  # after segment uploads. This preserves segment-before-playlist publication
  # even if Liquidsoap writes a newer playlist while this tick is running.
  let playlists = hls_playlist_snapshots()
  let segment_files = hls_local_segment_files()
  let local_segment_names =
    list.map(fun (fname) -> path.basename(fname), segment_files)
  let protected_segment_names =
    hls_union(local_segment_names, hls_snapshot_segment_names(playlists))

  hls_upload_segments(synced_segments, segment_files)

  let playlists_ok =
    not list.is_empty(playlists)
    and hls_upload_playlists(synced_playlists, synced_segments, playlists)

  if
    playlists_ok
  then
    hls_delete_stale_segments(synced_segments, protected_segment_names)
  end

  hls_mirror_state :=
    {
      playlists = playlists,
      segment_names = local_segment_names,
      synced_segments = synced_segments(),
      synced_playlists = synced_playlists()
    }

  if
    not hls_mirror_tick_failed() and playlists_ok
  then
    hls_mirror_last_sync_at := time()
    hls_mirror_error := ""
  end
end

# Timestamped segment names are never reused across restarts, so Bunny CDN
# can cache segments with a long TTL and no resume state is needed.
def hls_segment_name(segment_metadata) =
  let ts = int_of_float(time())
  "#{segment_metadata.stream_name}_#{ts}_#{segment_metadata.position}.#{
    segment_metadata.extname
  }"
end

# Retry backoff for recreating a degraded HLS output
let hls_retry_delay_initial = 5.0
let hls_retry_delay_max = 300.0
let hls_backoff_reset_seconds = 120.0

def hls_dir_writable() =
  let probe_path = "#{HLS_DIR}/.hls-write-probe"
  try
    file.write(data="probe", probe_path)
    file.remove(probe_path)
    true
  catch _ do
    false
  end
end

# Each (re)start begins a fresh timeline (timestamped segment names), so
# leftovers from the previous generation are dead weight: "liq...tmp" temp
# files from a crashed output plus its segments and playlists. Once removed
# locally, the mirror also retires them remotely.
def hls_remove_stale_local_files() =
  def is_stale(name) =
    r/^liq.*tmp$/.test(name) or hls_is_sync_file_name(name)
  end

  list.iter(
    fun (fname) ->
      try
        file.remove(fname)
      catch _ do
        ()
      end,
    try
      hls_local_files(is_stale)
    catch _ do
      []
    end
  )
end

# An error raised out of a recurring thread.run task stops that task for
# good (the on_error wrapper silences the error but never reschedules), so
# each tick catches and logs its own errors instead.
def hls_guard_task(what, task) =
  fun () ->
    try
      task()
    catch err do
      log(
        label="hls",
        "HLS #{what} error: #{err.kind}: #{err.message}",
        level=2
      )
    end
end

def output_hls_stream(audio_source) =
  if
    hls_enabled
  then
    log(
      label="hls",
      "HLS output enabled - writing #{HLS_SEGMENTS}x#{HLS_SEGMENT_DURATION}s to #{
        HLS_DIR
      }, uploading to #{HLS_BUNNY_STORAGE_ZONE}/#{STATION_ID}/",
      level=3
    )

    # Buffer decouples the HLS chain from the live program chain; the
    # dedicated clock's on_error handler below contains streaming errors so
    # a failing HLS output is detached instead of stopping the process.
    let hls_source = mksafe(buffer(audio_source))

    let hls_retry_at = ref(0.0)
    let hls_retry_delay = ref(hls_retry_delay_initial)

    def hls_degraded() =
      hls_local_error() != ""
    end

    # Record the failure, log it, and arm the next recreation attempt.
    def hls_mark_degraded(reason) =
      let retry_in = hls_retry_delay()
      hls_retry_at := time() + retry_in
      hls_retry_delay := min(retry_in * 2.0, hls_retry_delay_max)
      hls_local_error := reason
      log(
        label="hls",
        "HLS output degraded (primary outputs unaffected): #{reason}; next \
         attempt in #{retry_in}s",
        level=2
      )
    end

    clock.assign_new(
      id="hls_clock",
      on_error=fun (err) ->
        hls_mark_degraded(
          "#{error.kind(err)}: #{error.message(err)}"
        ),
      [hls_source]
    )

    # Source metadata is emitted as timed ID3 (v2.3, replayed per segment)
    # in the MPEG-TS variants by default; no per-stream id3 settings needed.
    # The 48 kbps HE-AAC variant is disabled until Liquidsoap keeps mixed
    # AAC profile timelines aligned: https://github.com/savonet/liquidsoap/issues/5319
    let aac_mid =
      %ffmpeg(
        format = "mpegts",
        %audio(
          codec = "libfdk_aac",
          b = "#{HLS_BITRATE_MID}k",
          ar = 48000,
          ac = 2,
          profile = "aac_low"
        )
      ).{
        bandwidth = HLS_BITRATE_MID * 1000 + 8000,
        codecs = "mp4a.40.2",
        extname = "ts"
      }

    let aac_high =
      %ffmpeg(
        format = "mpegts",
        %audio(
          codec = "libfdk_aac",
          b = "#{HLS_BITRATE_HIGH}k",
          ar = 48000,
          ac = 2,
          profile = "aac_low"
        )
      ).{
        bandwidth = HLS_BITRATE_HIGH * 1000 + 8000,
        codecs = "mp4a.40.2",
        extname = "ts"
      }

    def try_start_hls_output() =
      if
        hls_dir_writable()
      then
        hls_remove_stale_local_files()

        # No persist_at: segment names are timestamped and never reused (see
        # hls_segment_name), and persist_at breaks the error containment
        # above.
        let hls_output =
          output.file.hls(
            id="hls",
            playlist=hls_main_playlist_name,
            segment_duration=HLS_SEGMENT_DURATION,
            segments=HLS_SEGMENTS,
            segments_overhead=HLS_SEGMENTS_OVERHEAD,
            segment_name=hls_segment_name,
            HLS_DIR,
            [("aac_96", aac_mid), ("aac_192", aac_high)],
            hls_source
          )
        hls_output.on_file_change(synchronous=true, hls_track_local_progress)
        hls_local_error := ""
        log(
          label="hls",
          "HLS output started",
          level=3
        )
        true
      else
        false
      end
    end

    # Preflight: start degraded instead of crashing when HLS_DIR is not
    # writable at startup; the watchdog below keeps retrying.
    if
      not try_start_hls_output()
    then
      hls_mark_degraded(
        "HLS_DIR #{HLS_DIR} is not writable"
      )
    end

    def hls_watchdog() =
      if
        hls_degraded() and time() >= hls_retry_at()
      then
        if
          try_start_hls_output()
        then
          log(
            label="hls",
            "HLS output recovered",
            level=2
          )
        else
          hls_mark_degraded(hls_local_error())
        end
      elsif
        not hls_degraded()
        and hls_retry_delay() != hls_retry_delay_initial
        and time() - hls_retry_at() > hls_backoff_reset_seconds
      then
        # Forget the backoff once the output has been stable for a while
        hls_retry_delay := hls_retry_delay_initial
      end
    end

    thread.run(
      fast=false,
      every=hls_retry_delay_initial,
      hls_guard_task("watchdog", hls_watchdog)
    )

    let hls_remote_seeded = ref(false)
    let hls_synced_segments = ref([])
    let hls_synced_playlists = ref([])

    thread.run(
      fast=false,
      delay=1.0,
      every=1.0,
      hls_guard_task(
        "mirror tick",
        fun () ->
          hls_mirror_tick(
            hls_remote_seeded,
            hls_synced_segments,
            hls_synced_playlists
          )
      )
    )
  else
    log(
      label="hls",
      "HLS output disabled - HLS_BUNNY_STORAGE_ZONE and/or HLS_BUNNY_ACCESS_KEY \
       not configured",
      level=3
    )
  end

  server.register(
    description="Show HLS output health",
    "hls.status",
    fun (_) ->
      begin
        let health = hls_health()
        let errors =
          list.filter_map(
            fun (reason) -> reason,
            [health.local.error, health.mirror.error]
          )
        if
          list.is_empty(errors)
        then
          health.status
        else
          let reasons =
            string.concat(
              separator="; ",
              errors
            )
          "#{health.status}: #{reasons}"
        end
      end
  )
end
