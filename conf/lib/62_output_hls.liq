# HLS writes locally and mirrors to Bunny Edge Storage.

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

# Store stable API codes per component; log full failure details.
let hls_local_error = ref("")
let hls_mirror_error = ref("")
let hls_local_file_names = ref([])

# Null timestamps mean no local update or acknowledged publication yet.
let hls_local_last_update_at = ref(null)
let hls_mirror_last_published_at = ref(null)
let hls_mirror_recovered_uploads = ref(0)
let hls_mirror_expired_segments = ref(0)
let hls_started_at = ref(time())

let hls_mirror_pending = ref({segments = 0, playlists = 0})

# Allow at least four segment intervals for scheduling and upload jitter.
let hls_stale_after_seconds = max(15.0, HLS_SEGMENT_DURATION * 4.0)

let hls_mirror_cleanup_interval = 30.0
let hls_mirror_retry_delay_initial = 1.0
let hls_mirror_retry_delay_max = 30.0

# Publication must recover within a live window; cleanup may back off longer.
let hls_publication_retry_delay_max = max(0.1, min(4.0, HLS_SEGMENT_DURATION))
let hls_publication_timeout = max(0.1, min(10.0, HLS_SEGMENT_DURATION))

def hls_log(level, message) =
  log(label="hls", level=level, message)
end

def hls_progress_age(last_progress_at) =
  null.map(
    fun (progress_at) -> max(0.0, time() - progress_at),
    last_progress_at
  )
end

# Explicit errors take precedence; startup uses the same stall threshold.
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

def hls_put_data(remote_name, data, ~on_error) =
  try
    let response =
      http.put(
        timeout=hls_publication_timeout,
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

def hls_put_file(local_path, ~on_error) =
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

def hls_delete_file(remote_name, ~on_error) =
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
  let published_age = hls_progress_age(hls_mirror_last_published_at())
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
  let mirror = hls_component_health(hls_mirror_error(), published_age)
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
        published_age_seconds = published_age,
        recovered_uploads = hls_mirror_recovered_uploads(),
        expired_segments = hls_mirror_expired_segments(),
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

# Read generation time from the last segment name; unknown times stay null.
def hls_newest_segment_time(segments) =
  let match =
    r/_([0-9]+)_[0-9]+\.(aac|ts)$/.exec(list.last(default="", segments))
  null.map(float_of_string, list.assoc.nullable(1, match))
end

# An empty result prevents cleanup after a listing failure.
def hls_remote_segments(~on_error) =
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
      list.filter(hls_is_segment_name, names)
    elsif
      response.status_code == 404
    then
      log(
        label="hls",
        "Bunny HLS prefix #{STATION_ID}/ does not exist yet; local files will \
         create it",
        level=3
      )
      []
    else
      on_error(
        "listing_failed",
        "HLS mirror listing failed: HTTP #{response.status_code} #{
          response.status_message
        }"
      )
      []
    end
  catch err do
    on_error(
      "listing_failed",
      "HLS mirror listing exception: #{err.kind}: #{err.message}"
    )
    []
  end
end

# Retry failures with bounded exponential backoff.
def hls_create_mirror_worker(
  what,
  ~retry_delay_max=hls_mirror_retry_delay_max,
  ~now=fun () -> time(),
  ~report=hls_log,
  pass
) =
  let last_error = ref("")
  let retry_at = ref(0.0)
  let initial_delay = min(hls_mirror_retry_delay_initial, retry_delay_max)
  let retry_delay = ref(initial_delay)

  def run() =
    if
      now() >= retry_at()
    then
      let pass_error = ref("")
      def on_error(code, reason) =
        pass_error := code
        report(2, reason)
      end

      # Uncaught exceptions stop the recurring task.
      try
        pass(on_error)
      catch err do
        on_error(
          "worker_failed",
          "HLS #{what} error: #{err.kind}: #{err.message}"
        )
      end

      last_error := pass_error()
      if
        pass_error() != ""
      then
        retry_at := now() + retry_delay()
        retry_delay := min(retry_delay() * 2.0, retry_delay_max)
      else
        retry_delay := initial_delay
      end
    end
  end

  {run = run, error = last_error}
end

def hls_start_worker(every, worker) =
  thread.run(fast=false, delay=every, every=every, worker.run)
  worker
end

# Isolate each playlist and publish it only after its segments.
def hls_create_playlist_worker(
  name,
  ~ready=fun () -> true,
  ~now=fun () -> time(),
  ~put_file=hls_put_file,
  ~put_data=hls_put_data,
  ~report=hls_log
) =
  let synced_segments = ref([])
  let synced_playlist = ref("")
  let desired_segments = ref([])
  let published_at = ref(null)
  let recovered_uploads = ref(0)
  let expired_segments = ref(0)
  let failures = ref([])

  def read_snapshot() =
    let local_path = "#{HLS_DIR}/#{name}"
    if
      ready() and file.exists(local_path)
    then
      hls_read_playlist_snapshot(local_path)
    else
      null
    end
  end

  def failed_attempts(remote_name) =
    list.assoc(default=0, remote_name, failures())
  end

  # Uploaders report failures through on_error rather than raising.
  def attempt(remote_name, upload, on_error) =
    let previous = failed_attempts(remote_name)
    let ok =
      upload(
        fun (code, reason) ->
          on_error(
            code,
            "#{reason}; attempt=#{previous + 1}"
          )
      )
    failures := list.assoc.remove(remote_name, failures())
    if
      not ok
    then
      failures := [(remote_name, previous + 1), ...failures()]
    elsif
      previous > 0
    then
      recovered_uploads := recovered_uploads() + 1
      report(
        3,
        "HLS mirror upload recovered for #{remote_name} after #{previous} failed \
         attempt(s)"
      )
    end
    ok
  end

  # Sample the live window even during uploads.
  def pending() =
    let content =
      null.map(fun (snapshot) -> snapshot.content, read_snapshot()) ?? ""
    {
      segments =
        list.length(
          list.filter(
            fun (s) -> not list.mem(s, synced_segments()),
            hls_playlist_segment_names(content)
          )
        ),
      playlists =
        if content != "" and content == synced_playlist() then 0 else 1 end
    }
  end

  def pass(on_error) =
    let snapshot = read_snapshot()

    if
      null.defined(snapshot)
    then
      let snapshot = null.get(snapshot)
      let required = hls_playlist_segment_names(snapshot.content)
      let expired =
        list.filter(
          fun (s) ->
            not list.mem(s, required) and not list.mem(s, synced_segments()),
          desired_segments()
        )
      list.iter(
        fun (segment) ->
          begin
            expired_segments := expired_segments() + 1
            report(
              2,
              "HLS mirror segment expired for #{segment} after #{
                failed_attempts(segment)
              } failed attempt(s): left live playlist without confirmed upload; \
               remote delivery unknown"
            )
            failures := list.assoc.remove(segment, failures())
          end,
        expired
      )
      desired_segments := required
      synced_segments :=
        list.filter(fun (s) -> list.mem(s, required), synced_segments())

      def upload(segment) =
        list.mem(segment, synced_segments())
        or begin
          let ok =
            attempt(
              segment,
              fun (on_error) ->
                put_file("#{HLS_DIR}/#{segment}", on_error=on_error),
              on_error
            )
          if ok then synced_segments := [segment, ...synced_segments()] end
          ok
        end
      end

      if
        list.for_all(upload, required)
        and synced_playlist() != snapshot.content
        and attempt(
          snapshot.name,
          fun (on_error) ->
            put_data(snapshot.name, snapshot.content, on_error=on_error),
          on_error
        )
      then
        synced_playlist := snapshot.content
        published_at := hls_newest_segment_time(required)
      end
    end
  end

  hls_create_mirror_worker(
    "#{name} mirror",
    retry_delay_max=hls_publication_retry_delay_max,
    now=now,
    report=report,
    pass
  ).{
    synced_playlist = synced_playlist,
    desired_segments = desired_segments,
    pending = pending,
    published_at = published_at,
    recovered_uploads = recovered_uploads,
    expired_segments = expired_segments
  }
end

def hls_variants_published(variant_workers) =
  list.for_all(fun (worker) -> worker.synced_playlist() != "", variant_workers)
end

# Local overhead protects lagging clients per RFC 8216 section 6.2.2.
# List first so concurrent uploads cannot become deletion candidates.
def hls_mirror_cleanup_pass(variant_workers, on_error) =
  if
    hls_variants_published(variant_workers)
  then
    let remote_segments = hls_remote_segments(on_error=on_error)
    let protected =
      list.fold(
        fun (protected, worker) ->
          hls_union(
            hls_union(protected, worker.desired_segments()),
            hls_playlist_segment_names(worker.synced_playlist())
          ),
        hls_local_file_names(),
        variant_workers
      )
    ignore(
      list.for_all(
        fun (name) ->
          list.mem(name, protected) or hls_delete_file(name, on_error=on_error),
        remote_segments
      )
    )
  end
end

# Null until every timestamp is known; otherwise the oldest.
def hls_oldest(stamps) =
  if
    stamps != [] and list.for_all(null.defined, stamps)
  then
    list.fold(fun (oldest, s) -> min(oldest, null.get(s)), time(), stamps)
  else
    null
  end
end

def hls_mirror_health_tick(main_worker, variant_workers, cleanup_worker) =
  let workers = [main_worker, ...variant_workers]
  hls_mirror_error :=
    list.find(
      default="",
      fun (code) -> code != "",
      [
        cleanup_worker.error(),
        ...list.map(fun (worker) -> worker.error(), workers)
      ]
    )
  hls_mirror_pending :=
    list.fold(
      fun (total, pending) ->
        {
          segments = total.segments + pending.segments,
          playlists = total.playlists + pending.playlists
        },
      {segments = 0, playlists = 0},
      list.map(fun (worker) -> worker.pending(), workers)
    )
  hls_mirror_recovered_uploads :=
    list.fold(
      fun (total, worker) -> total + worker.recovered_uploads(),
      0,
      workers
    )
  hls_mirror_expired_segments :=
    list.fold(
      fun (total, worker) -> total + worker.expired_segments(),
      0,
      workers
    )

  # Published audio follows the stalest variant; the master playlist is static.
  hls_mirror_last_published_at :=
    hls_oldest(list.map(fun (worker) -> worker.published_at(), variant_workers))
end

# Unique names allow long CDN caching without persisted resume state.
def hls_segment_name(segment_metadata) =
  let ts = int_of_float(time())
  "#{segment_metadata.stream_name}_#{ts}_#{segment_metadata.position}.#{
    segment_metadata.extname
  }"
end

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

# Remote cleanup makes old local timelines disposable.
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

# Keep recurring tasks alive after exceptions.
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

    # Isolate HLS failures from the live program clock.
    let hls_source = mksafe(buffer(audio_source))

    let hls_retry_at = ref(0.0)
    let hls_retry_delay = ref(hls_retry_delay_initial)

    def hls_degraded() =
      hls_local_error() != ""
    end

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
    # HE-AAC and AAC-LC in one ladder needs Liquidsoap >= 2.4.6 (savonet/liquidsoap#5319).
    def hls_aac_variant(~bitrate, ~profile, ~codecs) =
      %ffmpeg(
        format = "mpegts",
        %audio(
          codec = "libfdk_aac",
          b = "#{bitrate}k",
          ar = 48000,
          ac = 2,
          profile = profile
        )
      ).{bandwidth = bitrate * 1000 + 8000, codecs = codecs, extname = "ts"}
    end

    # Stream ids also name the variant playlists the mirror publishes.
    let hls_streams =
      [
        (
          "aac_48",
          hls_aac_variant(
            bitrate=HLS_BITRATE_LOW,
            profile="aac_he",
            codecs="mp4a.40.5"
          )
        ),
        (
          "aac_96",
          hls_aac_variant(
            bitrate=HLS_BITRATE_MID,
            profile="aac_low",
            codecs="mp4a.40.2"
          )
        ),
        (
          "aac_192",
          hls_aac_variant(
            bitrate=HLS_BITRATE_HIGH,
            profile="aac_low",
            codecs="mp4a.40.2"
          )
        )
      ]

    def try_start_hls_output() =
      if
        hls_dir_writable()
      then
        hls_remove_stale_local_files()

        # Omit persist_at: a state-write failure during detach can stop the process.
        let hls_output =
          output.file.hls(
            id="hls",
            register_telnet=false,
            playlist=hls_main_playlist_name,
            segment_duration=HLS_SEGMENT_DURATION,
            segments=HLS_SEGMENTS,
            segments_overhead=HLS_SEGMENTS_OVERHEAD,
            segment_name=hls_segment_name,
            HLS_DIR,
            hls_streams,
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
        hls_retry_delay := hls_retry_delay_initial
      end
    end

    thread.run(
      every=hls_retry_delay_initial,
      hls_guard_task("watchdog", hls_watchdog)
    )

    let hls_variant_workers =
      list.map(
        fun (stream) ->
          hls_start_worker(
            1.0,
            hls_create_playlist_worker("#{fst(stream)}.m3u8")
          ),
        hls_streams
      )
    let hls_main_worker =
      hls_start_worker(
        1.0,
        hls_create_playlist_worker(
          hls_main_playlist_name,
          ready=fun () -> hls_variants_published(hls_variant_workers)
        )
      )
    let hls_cleanup_worker =
      hls_start_worker(
        hls_mirror_cleanup_interval,
        hls_create_mirror_worker(
          "mirror cleanup",
          fun (on_error) ->
            hls_mirror_cleanup_pass(hls_variant_workers, on_error)
        )
      )

    # Keep health sampling independent of blocked upload and cleanup workers.
    thread.run(
      fast=true,
      delay=1.0,
      every=1.0,
      hls_guard_task(
        "mirror health",
        fun () ->
          hls_mirror_health_tick(
            hls_main_worker,
            hls_variant_workers,
            hls_cleanup_worker
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
