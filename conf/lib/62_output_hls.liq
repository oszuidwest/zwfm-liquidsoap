# HLS writes locally and mirrors to Bunny Edge Storage.
# The isolated clock contains filesystem failures; a watchdog replaces detached
# outputs. Do not add persist_at: writing state while a failed output detaches
# re-raises on the dead clock thread and stops the entire process.

let hls_bunny_headers = [("AccessKey", HLS_BUNNY_ACCESS_KEY), ("Expect", "")]
let hls_main_playlist_name = "live.m3u8"
let hls_variant_playlist_names = ["aac_96.m3u8", "aac_192.m3u8"]

let hls_enabled = HLS_BUNNY_STORAGE_ZONE != "" and HLS_BUNNY_ACCESS_KEY != ""

let hls_endpoint_trimmed = string.trim(HLS_BUNNY_ENDPOINT)
def hls_scheme_for_endpoint(endpoint) =
  if
    r/^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?\/?$/.test(endpoint)
  then
    "http"
  else
    "https"
  end
end

let hls_endpoint_scheme = hls_scheme_for_endpoint(hls_endpoint_trimmed)
let hls_endpoint_without_https =
  string.residual(prefix="https://", hls_endpoint_trimmed)
    ?? hls_endpoint_trimmed
let hls_endpoint_without_scheme =
  string.residual(prefix="http://", hls_endpoint_without_https)
    ?? hls_endpoint_without_https
let hls_endpoint_host =
  r/\/+$/.replace(fun (_) -> "", hls_endpoint_without_scheme)

let hls_remote_dir_url =
  "#{hls_endpoint_scheme}://#{hls_endpoint_host}/#{HLS_BUNNY_STORAGE_ZONE}/#{
    STATION_ID
  }/"

# Store stable API codes per component; log full failure details.
let hls_local_error = ref("")
let hls_mirror_error = ref("")
let hls_local_file_names = ref([])

# Null timestamps mean no local update or complete mirror pass yet.
let hls_local_last_update_at = ref(null)
let hls_mirror_last_sync_at = ref(null)
let hls_started_at = ref(time())

# Local files the last mirror pass left unsynced.
let hls_mirror_pending = ref({segments = 0, playlists = 0})

# Allow at least four segment intervals for scheduling and upload jitter.
let hls_stale_after_seconds = max(15.0, HLS_SEGMENT_DURATION * 4.0)

# Compatibility helpers and direct-call tests use this failure flag. Runtime
# workers keep independent failure state so one healthy variant cannot clear a
# concurrent failure from the other variant.
let hls_mirror_tick_failed = ref(false)

let hls_mirror_retry_delay_initial = 1.0
let hls_mirror_retry_delay_max = 30.0
let hls_mirror_cleanup_interval = 30.0

def hls_mark_mirror_degraded(code, reason) =
  hls_mirror_tick_failed := true
  hls_mirror_error := code
  log(label="hls", reason, level=2)
end

def hls_progress_age(last_progress_at) =
  null.map(
    fun (progress_at) -> max(0.0, time() - progress_at),
    last_progress_at
  )
end

# Explicit failures outrank stalls; missing progress starts the same grace.
def hls_component_health(failure, age) =
  let observed_age = age ?? max(0.0, time() - hls_started_at())
  let failure =
    if
      hls_enabled and failure == "" and observed_age > hls_stale_after_seconds
    then
      "stalled"
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

def hls_remote_url(remote_name) =
  "#{hls_remote_dir_url}#{remote_name}"
end

def hls_is_success(status_code) =
  200 <= status_code and status_code < 300
end

def hls_is_playlist_name(name) =
  r/\.m3u8$/.test(name)
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

# File events track local counts and progress independently of mirror latency.
def hls_track_local_progress(change) =
  let name = path.basename(change.path)
  if
    change.state == "deleted"
  then
    hls_local_file_names :=
      list.filter(fun (file_name) -> file_name != name, hls_local_file_names())
  elsif
    hls_is_sync_file_name(name)
  then
    hls_local_file_names := hls_add_unique(name, hls_local_file_names())
  end

  if
    change.state != "deleted" and hls_is_playlist_name(name)
  then
    hls_local_last_update_at := time()
  end
end

def hls_union(names, extra_names) =
  list.fold(fun (acc, name) -> hls_add_unique(name, acc), names, extra_names)
end

def hls_put_data(remote_name, data, ~on_error=hls_mark_mirror_degraded) =
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
      on_error(
        "upload_failed",
        "HLS mirror upload failed for #{remote_name}: HTTP #{
          response.status_code
        } #{response.status_message}"
      )
      false
    end
  catch err do
    on_error(
      "upload_failed",
      "HLS mirror upload exception for #{remote_name}: #{err.kind}: #{
        err.message
      }"
    )
    false
  end
end

def hls_put_file(local_path, ~on_error=hls_mark_mirror_degraded) =
  let remote_name = path.basename(local_path)
  if
    not file.exists(local_path)
  then
    on_error(
      "local_file_missing",
      "HLS mirror upload skipped; local file disappeared: #{remote_name}"
    )
    false
  else
    try
      hls_put_data(remote_name, file.contents(local_path), on_error=on_error)
    catch err do
      on_error(
        "read_failed",
        "HLS upload read exception for #{remote_name}: #{err.kind}: #{
          err.message
        }"
      )
      false
    end
  end
end

def hls_delete_file(remote_name, ~on_error=hls_mark_mirror_degraded) =
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
      on_error(
        "delete_failed",
        "HLS mirror delete failed for #{remote_name}: HTTP #{
          response.status_code
        } #{response.status_message}"
      )
      false
    end
  catch err do
    on_error(
      "delete_failed",
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

def hls_health() =
  let local_age = hls_progress_age(hls_local_last_update_at())
  let mirror_age = hls_progress_age(hls_mirror_last_sync_at())
  let hls_dir_present = file.is_directory(HLS_DIR)
  let local_file_names =
    if hls_dir_present then hls_local_file_names() else [] end
  let local =
    hls_component_health(
      if
        hls_local_error() != ""
      then
        hls_local_error()
      elsif
        hls_enabled and not hls_dir_present
      then
        "dir_missing"
      else
        ""
      end,
      local_age
    )
  let mirror = hls_component_health(hls_mirror_error(), mirror_age)
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
        playlist_count =
          list.length(list.filter(hls_is_playlist_name, local_file_names)),
        segment_count =
          list.length(list.filter(hls_is_segment_name, local_file_names)),
        update_age_seconds = local_age
      },
    mirror =
      {
        ...mirror,
        host = if hls_enabled then hls_endpoint_host else null end,
        storage_zone = if hls_enabled then HLS_BUNNY_STORAGE_ZONE else null end,
        sync_age_seconds = mirror_age,
        pending_segments = hls_mirror_pending().segments,
        pending_playlists = hls_mirror_pending().playlists
      }
  }
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

def hls_remote_listing(~on_error=hls_mark_mirror_degraded) =
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
      on_error(
        "listing_failed",
        "HLS mirror listing failed: HTTP #{response.status_code} #{
          response.status_message
        }"
      )
      {ok = false, names = []}
    end
  catch err do
    on_error(
      "listing_failed",
      "HLS mirror listing exception: #{err.kind}: #{err.message}"
    )
    {ok = false, names = []}
  end
end

def hls_new_mirror_worker(name) =
  let synced_segments = ref([])
  let synced_playlist = ref("")
  let desired_segments = ref([])
  let pending_segments = ref(0)
  let pending_playlist = ref(1)
  let worker_error = ref("")
  let retry_at = ref(0.0)
  let retry_delay = ref(hls_mirror_retry_delay_initial)
  let busy = ref(false)
  {
    name = name,
    synced_segments = synced_segments,
    set_synced_segments = fun (value) -> synced_segments := value,
    synced_playlist = synced_playlist,
    set_synced_playlist = fun (value) -> synced_playlist := value,
    desired_segments = desired_segments,
    set_desired_segments = fun (value) -> desired_segments := value,
    pending_segments = pending_segments,
    set_pending_segments = fun (value) -> pending_segments := value,
    pending_playlist = pending_playlist,
    set_pending_playlist = fun (value) -> pending_playlist := value,
    error = worker_error,
    set_error = fun (value) -> worker_error := value,
    retry_at = retry_at,
    set_retry_at = fun (value) -> retry_at := value,
    retry_delay = retry_delay,
    set_retry_delay = fun (value) -> retry_delay := value,
    busy = busy,
    set_busy = fun (value) -> busy := value
  }
end

def hls_schedule_mirror_retry(worker) =
  let retry_in = worker.retry_delay()
  worker.set_retry_at(time() + retry_in)
  worker.set_retry_delay(min(retry_in * 2.0, hls_mirror_retry_delay_max))
end

def hls_reset_mirror_retry(worker) =
  worker.set_retry_at(0.0)
  worker.set_retry_delay(hls_mirror_retry_delay_initial)
end

# A variant worker owns its mutable state. Separate recurring tasks can therefore
# upload both renditions concurrently without one rendition starving the other.
def hls_mirror_variant_tick(worker) =
  if
    time() >= worker.retry_at()
  then
    worker.set_busy(true)
    let snapshot = hls_read_playlist_snapshot("#{HLS_DIR}/#{worker.name}")

    if
      null.defined(snapshot)
    then
      let snapshot = null.get(snapshot)
      let required_segments = hls_playlist_segment_names(snapshot.content)
      worker.set_desired_segments(required_segments)
      worker.set_synced_segments(
        list.filter(
          fun (name) -> list.mem(name, required_segments),
          worker.synced_segments()
        )
      )

      let pass_error = ref("")
      def on_error(code, reason) =
        pass_error := code
        log(label="hls", reason, level=2)
      end

      let upload_ok = ref(true)
      list.iter(
        fun (segment_name) ->
          begin
            if
              upload_ok()
              and not list.mem(segment_name, worker.synced_segments())
            then
              if
                hls_put_file("#{HLS_DIR}/#{segment_name}", on_error=on_error)
              then
                worker.set_synced_segments(
                  hls_add_unique(segment_name, worker.synced_segments())
                )
              else
                upload_ok := false
              end
            end
          end,
        required_segments
      )

      worker.set_pending_segments(
        list.length(
          list.filter(
            fun (name) -> not list.mem(name, worker.synced_segments()),
            required_segments
          )
        )
      )

      if
        upload_ok()
        and worker.pending_segments() == 0
        and worker.synced_playlist() != snapshot.content
      then
        if
          hls_put_data(snapshot.name, snapshot.content, on_error=on_error)
        then
          worker.set_synced_playlist(snapshot.content)
        end
      end

      worker.set_pending_playlist(
        if worker.synced_playlist() == snapshot.content then 0 else 1 end
      )

      if
        pass_error() == ""
        and worker.pending_segments() == 0
        and worker.pending_playlist() == 0
      then
        worker.set_error("")
        hls_reset_mirror_retry(worker)
      elsif
        pass_error() != ""
      then
        worker.set_error(pass_error())
        hls_schedule_mirror_retry(worker)
      end
    else
      # Playlists do not exist until the HLS muxer has produced its first window.
      worker.set_pending_playlist(1)
    end
    worker.set_busy(false)
  end
end

def hls_variants_published(variant_workers) =
  list.for_all(fun (worker) -> worker.synced_playlist() != "", variant_workers)
end

def hls_mirror_main_tick(worker, variant_workers) =
  if
    time() >= worker.retry_at() and hls_variants_published(variant_workers)
  then
    worker.set_busy(true)
    let snapshot =
      hls_read_playlist_snapshot("#{HLS_DIR}/#{hls_main_playlist_name}")

    if
      null.defined(snapshot)
    then
      let snapshot = null.get(snapshot)
      let pass_error = ref("")
      def on_error(code, reason) =
        pass_error := code
        log(label="hls", reason, level=2)
      end

      if
        worker.synced_playlist() != snapshot.content
      then
        if
          hls_put_data(snapshot.name, snapshot.content, on_error=on_error)
        then
          worker.set_synced_playlist(snapshot.content)
        end
      end

      worker.set_pending_playlist(
        if worker.synced_playlist() == snapshot.content then 0 else 1 end
      )

      if
        pass_error() == "" and worker.pending_playlist() == 0
      then
        worker.set_error("")
        hls_reset_mirror_retry(worker)
      elsif
        pass_error() != ""
      then
        worker.set_error(pass_error())
        hls_schedule_mirror_retry(worker)
      end
    else
      worker.set_pending_playlist(1)
    end
    worker.set_busy(false)
  end
end

def hls_mirror_protected_segments(variant_workers) =
  list.fold(
    fun (protected, worker) ->
      begin
        let protected = hls_union(protected, worker.desired_segments())
        if
          worker.synced_playlist() == ""
        then
          protected
        else
          hls_union(
            protected,
            hls_playlist_segment_names(worker.synced_playlist())
          )
        end
      end,
    [],
    variant_workers
  )
end

# Cleanup is deliberately off the publication path. Protect both the currently
# published window and each worker's in-flight desired window from deletion.
def hls_mirror_cleanup_tick(worker, variant_workers) =
  if
    time() >= worker.retry_at() and hls_variants_published(variant_workers)
  then
    worker.set_busy(true)
    let pass_error = ref("")
    def on_error(code, reason) =
      pass_error := code
      log(label="hls", reason, level=2)
    end

    let listing = hls_remote_listing(on_error=on_error)
    if
      listing.ok
    then
      let protected_segments = hls_mirror_protected_segments(variant_workers)
      let delete_ok = ref(true)
      list.iter(
        fun (remote_name) ->
          begin
            if
              delete_ok()
              and hls_is_segment_name(remote_name)
              and not list.mem(remote_name, protected_segments)
            then
              if
                not hls_delete_file(remote_name, on_error=on_error)
              then
                delete_ok := false
              end
            end
          end,
        listing.names
      )
    end

    if
      pass_error() == ""
    then
      worker.set_error("")
      hls_reset_mirror_retry(worker)
    else
      worker.set_error(pass_error())
      hls_schedule_mirror_retry(worker)
    end
    worker.set_busy(false)
  end
end

def hls_mirror_health_tick(workers) =
  let pending_segments =
    list.fold(
      fun (count, worker) -> count + worker.pending_segments(),
      0,
      workers
    )
  let pending_playlists =
    list.fold(
      fun (count, worker) -> count + worker.pending_playlist(),
      0,
      workers
    )
  let mirror_error =
    list.fold(
      fun (code, worker) ->
        if
          code == "" and worker.error() != ""
        then
          worker.error()
        else
          code
        end,
      "",
      workers
    )
  let busy =
    list.fold(fun (busy, worker) -> busy or worker.busy(), false, workers)

  hls_mirror_pending :=
    {segments = pending_segments, playlists = pending_playlists}
  hls_mirror_error := mirror_error

  if
    not busy
    and mirror_error == ""
    and pending_segments == 0
    and pending_playlists == 0
  then
    hls_mirror_last_sync_at := time()
  end
end

# Unique names allow long CDN caching without persisted resume state.
def hls_segment_name(segment_metadata) =
  let ts = int_of_float(time())
  "#{segment_metadata.stream_name}_#{ts}_#{segment_metadata.position}.#{
    segment_metadata.extname
  }"
end

# Exponential restart backoff.
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

# A fresh timeline makes old local output disposable; the mirror prunes segments.
def hls_remove_stale_local_files() =
  hls_local_file_names := []

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

# Catch errors because an escaping exception permanently stops a recurring task.
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

# Unexpected worker exceptions must not leave health permanently marked busy.
def hls_guard_mirror_worker(what, worker, task) =
  fun () ->
    try
      task()
    catch err do
      worker.set_busy(false)
      worker.set_error("worker_failed")
      hls_schedule_mirror_retry(worker)
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

    # Isolate HLS failures from the live program clock.
    let hls_source = mksafe(buffer(audio_source))

    let hls_retry_at = ref(0.0)
    let hls_retry_delay = ref(hls_retry_delay_initial)

    def hls_degraded() =
      hls_local_error() != ""
    end

    # Record the failure and schedule the next attempt.
    def hls_mark_degraded(code, reason) =
      let retry_in = hls_retry_delay()
      hls_retry_at := time() + retry_in
      hls_retry_delay := min(retry_in * 2.0, hls_retry_delay_max)
      hls_local_error := code
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
          "clock_error",
          "#{error.kind(err)}: #{error.message(err)}"
        ),
      [hls_source]
    )

    # MPEG-TS repeats source metadata as timed ID3v2.3 in every segment.
    # Keep HE-AAC disabled until mixed profiles share a timeline:
    # https://github.com/savonet/liquidsoap/issues/5319
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

        # Omit persist_at to preserve clock-error containment (see header).
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
        hls_mark_degraded(
          "dir_not_writable",
          "HLS_DIR #{HLS_DIR} is not writable"
        )
        false
      end
    end

    # Start degraded when HLS_DIR is unwritable; the watchdog retries.
    ignore(try_start_hls_output())

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
        end
      elsif
        not hls_degraded()
        and hls_retry_delay() != hls_retry_delay_initial
        and time() - hls_retry_at() > hls_backoff_reset_seconds
      then
        # Restore fast retries after sustained health.
        hls_retry_delay := hls_retry_delay_initial
      end
    end

    thread.run(
      fast=false,
      every=hls_retry_delay_initial,
      hls_guard_task("watchdog", hls_watchdog)
    )

    let hls_variant_workers =
      list.map(hls_new_mirror_worker, hls_variant_playlist_names)
    let hls_main_worker = hls_new_mirror_worker(hls_main_playlist_name)
    let hls_cleanup_worker = hls_new_mirror_worker("cleanup")
    hls_cleanup_worker.set_pending_playlist(0)

    list.iter(
      fun (worker) ->
        thread.run(
          fast=false,
          delay=1.0,
          every=1.0,
          hls_guard_mirror_worker(
            "#{worker.name} mirror worker",
            worker,
            fun () -> hls_mirror_variant_tick(worker)
          )
        ),
      hls_variant_workers
    )

    thread.run(
      fast=false,
      delay=1.0,
      every=1.0,
      hls_guard_mirror_worker(
        "main playlist mirror worker",
        hls_main_worker,
        fun () -> hls_mirror_main_tick(hls_main_worker, hls_variant_workers)
      )
    )

    thread.run(
      fast=false,
      delay=hls_mirror_cleanup_interval,
      every=hls_mirror_cleanup_interval,
      hls_guard_mirror_worker(
        "mirror cleanup worker",
        hls_cleanup_worker,
        fun () ->
          hls_mirror_cleanup_tick(hls_cleanup_worker, hls_variant_workers)
      )
    )

    thread.run(
      fast=false,
      delay=1.0,
      every=1.0,
      hls_guard_task(
        "mirror health",
        fun () ->
          hls_mirror_health_tick(
            [hls_main_worker, hls_cleanup_worker, ...hls_variant_workers]
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
        let reasons =
          string.concat(
            separator="; ",
            list.filter_map(
              fun (reason) -> reason,
              [
                null.map(fun (code) -> "local=#{code}", health.local.error),
                null.map(fun (code) -> "mirror=#{code}", health.mirror.error)
              ]
            )
          )
        if
          reasons == ""
        then
          health.status
        else
          "#{health.status}: #{reasons}"
        end
      end
  )
end
