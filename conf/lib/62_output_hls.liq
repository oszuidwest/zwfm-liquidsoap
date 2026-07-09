# HLS output configuration
# Writes a local HLS window and mirrors it to Bunny Edge Storage.

let HLS_UPLOAD_QUEUE_MAX = 100
let HLS_UPLOAD_SEGMENT_KEEP =
  3 * (HLS_SEGMENTS + HLS_SEGMENTS_OVERHEAD + 2)
let hls_upload_queue = ref([])
let hls_bunny_headers = [("AccessKey", HLS_BUNNY_ACCESS_KEY)]

def hls_enabled() =
  HLS_BUNNY_STORAGE_ZONE != "" and HLS_BUNNY_ACCESS_KEY != ""
end

def hls_endpoint_host() =
  let endpoint = string.trim(HLS_BUNNY_ENDPOINT)
  let endpoint = string.residual(prefix="https://", endpoint) ?? endpoint
  let endpoint = string.residual(prefix="http://", endpoint) ?? endpoint
  r/\/+$/.replace(fun (_) -> "", endpoint)
end

def hls_remote_dir_url() =
  "https://#{hls_endpoint_host()}/#{HLS_BUNNY_STORAGE_ZONE}/#{STATION_ID}/"
end

def hls_remote_url(remote_name) =
  "#{hls_remote_dir_url()}#{remote_name}"
end

def hls_is_success(status_code) =
  200 <= status_code and status_code < 300
end

def hls_is_sync_file_name(name) =
  r/\.m3u8$/.test(name) or r/\.aac$/.test(name)
end

def hls_is_segment_upload(item) =
  item.state != "deleted" and r/\.aac$/.test(path.basename(item.path))
end

def hls_trim_queue(queue) =
  if
    list.length(queue) <= HLS_UPLOAD_QUEUE_MAX
  then
    queue
  else
    let newest_first = list.rev(queue)
    let (kept, segment_count, dropped_count) =
      list.fold(
        fun (state, item) ->
          begin
            let (kept, segment_count, dropped_count) = state
            if
              hls_is_segment_upload(item)
            then
              if
                segment_count < HLS_UPLOAD_SEGMENT_KEEP
              then
                (item::kept, segment_count + 1, dropped_count)
              else
                (kept, segment_count, dropped_count + 1)
              end
            else
              (item::kept, segment_count, dropped_count)
            end
          end,
        ([], 0, 0),
        newest_first
      )
    ignore(segment_count)

    let kept =
      if
        list.length(kept) > HLS_UPLOAD_QUEUE_MAX
      then
        list.rev(list.prefix(HLS_UPLOAD_QUEUE_MAX, list.rev(kept)))
      else
        kept
      end

    log(
      label="hls",
      "HLS upload queue exceeded #{HLS_UPLOAD_QUEUE_MAX}; dropped #{
        dropped_count
      } stale segment upload(s), kept #{list.length(kept)} event(s)",
      level=2
    )
    kept
  end
end

def hls_upload_enqueue({state, path = changed_path}) =
  let remote_name = path.basename(changed_path)
  if
    remote_name == "state.json" or not hls_is_sync_file_name(remote_name)
  then
    ()
  else
    hls_upload_queue :=
      hls_trim_queue([
        ...hls_upload_queue(),
        {state=state, path=changed_path}
      ])
  end
end

def hls_put_file(local_path, remote_name) =
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
      let response =
        http.put(
          timeout=10.0,
          headers=hls_bunny_headers,
          data=file.contents(local_path),
          hls_remote_url(remote_name)
        )

      if
        hls_is_success(response.status_code)
      then
        true
      else
        log(
          label="hls",
          "HLS upload failed for #{remote_name}: HTTP #{
            response.status_code
          } #{response.status_message}",
          level=2
        )
        false
      end
    catch err do
      log(
        label="hls",
        "HLS upload exception for #{remote_name}: #{err.kind}: #{err.message}",
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
      log(
        label="hls",
        "HLS delete failed for #{remote_name}: HTTP #{response.status_code} #{
          response.status_message
        }",
        level=2
      )
      false
    end
  catch err do
    log(
      label="hls",
      "HLS delete exception for #{remote_name}: #{err.kind}: #{err.message}",
      level=2
    )
    false
  end
end

def hls_retry_once(description, op) =
  if
    not op()
  then
    log(
      label="hls",
      "Retrying HLS #{description} once",
      level=3
    )

    if
      not op()
    then
      log(
        label="hls",
        "Giving up HLS #{description} after retry",
        level=2
      )
    end
  end
end

def hls_upload_with_retry(local_path) =
  let remote_name = path.basename(local_path)
  hls_retry_once(
    "upload for #{remote_name}",
    fun () -> hls_put_file(local_path, remote_name)
  )
end

def hls_delete_with_retry(remote_name) =
  hls_retry_once(
    "delete for #{remote_name}",
    fun () -> hls_delete_file(remote_name)
  )
end

def hls_process_event(item) =
  let remote_name = path.basename(item.path)
  if
    item.state == "deleted"
  then
    hls_delete_with_retry(remote_name)
  elsif
    item.state == "created" or item.state == "updated"
  then
    hls_upload_with_retry(item.path)
  else
    log(
      label="hls",
      "Ignoring unknown HLS file event #{item.state} for #{item.path}",
      level=3
    )
  end
end

def hls_queue_pop() =
  list.dcase(
    hls_upload_queue(),
    {null},
    fun (item, rest) ->
      begin
        hls_upload_queue := rest
        item
      end
  )
end

def hls_upload_worker() =
  let item = hls_queue_pop()
  if
    null.defined(item)
  then
    hls_process_event(null.get(item))
  end
end

def hls_local_files() =
  if
    file.exists(HLS_DIR)
  then
    list.filter(
      fun (fname) ->
        begin
          let name = path.basename(fname)
          not file.is_directory(fname) and hls_is_sync_file_name(name)
        end,
      file.ls(absolute=true, sorted=true, HLS_DIR)
    )
  else
    []
  end
end

def hls_local_names() =
  list.map(fun (fname) -> path.basename(fname), hls_local_files())
end

def hls_reconcile() =
  log(
    label="hls",
    "Reconciling local HLS window with Bunny Edge Storage prefix #{STATION_ID}/",
    level=3
  )

  let local_names = hls_local_names()
  try
    let response =
      http.get(
        timeout=10.0,
        headers=hls_bunny_headers,
        hls_remote_dir_url()
      )

    if
      hls_is_success(response.status_code)
    then
      let json.parse (remote_entries :
        [{"ObjectName" as object_name: string}]
      ) = response

      list.iter(
        fun ({object_name}) ->
          begin
            let remote_name = path.basename(object_name)
            if
              remote_name != ""
              and remote_name != "."
              and not list.mem(remote_name, local_names)
            then
              hls_delete_with_retry(remote_name)
            end
          end,
        remote_entries
      )
    elsif
      response.status_code == 404
    then
      log(
        label="hls",
        "Bunny HLS prefix #{STATION_ID}/ does not exist yet; local files \
         will create it",
        level=3
      )
    else
      log(
        label="hls",
        "HLS reconcile listing failed: HTTP #{response.status_code} #{
          response.status_message
        }",
        level=2
      )
    end
  catch err do
    log(
      label="hls",
      "HLS reconcile listing exception: #{err.kind}: #{err.message}",
      level=2
    )
  end

  list.iter(hls_upload_with_retry, hls_local_files())
end

def hls_segment_name(segment_metadata) =
  let ts = int_of_float(time())
  "#{segment_metadata.stream_name}_#{ts}_#{segment_metadata.position}.#{
    segment_metadata.extname
  }"
end

def output_hls_stream(audio_source) =
  if
    hls_enabled()
  then
    log(
      label="hls",
      "HLS output enabled - writing #{HLS_SEGMENTS}x#{
        HLS_SEGMENT_DURATION
      }s to #{HLS_DIR}, uploading to #{HLS_BUNNY_STORAGE_ZONE}/#{STATION_ID}/",
      level=3
    )

    file.mkdir(parents=true, HLS_DIR)

    # Buffer provides clock isolation from the live program chain.
    let hls_source = mksafe(buffer(audio_source))

    let aac_low =
      %fdkaac(
        channels = 2,
        samplerate = 48000,
        bitrate = HLS_BITRATE_LOW,
        afterburner = true,
        aot = 'mpeg4_he_aac',
        transmux = 'adts'
      ).{
        bandwidth=HLS_BITRATE_LOW * 1000 + 8000,
        codecs="mp4a.40.5",
        extname="aac"
      }

    let aac_mid =
      %fdkaac(
        channels = 2,
        samplerate = 48000,
        bitrate = HLS_BITRATE_MID,
        afterburner = true,
        aot = 'mpeg4_aac_lc',
        transmux = 'adts'
      ).{
        bandwidth=HLS_BITRATE_MID * 1000 + 8000,
        codecs="mp4a.40.2",
        extname="aac"
      }

    let aac_high =
      %fdkaac(
        channels = 2,
        samplerate = 48000,
        bitrate = HLS_BITRATE_HIGH,
        afterburner = true,
        aot = 'mpeg4_aac_lc',
        transmux = 'adts'
      ).{
        bandwidth=HLS_BITRATE_HIGH * 1000 + 8000,
        codecs="mp4a.40.2",
        extname="aac"
      }

    let hls_output =
      output.file.hls(
        playlist="live.m3u8",
        segment_duration=HLS_SEGMENT_DURATION,
        segments=HLS_SEGMENTS,
        segments_overhead=HLS_SEGMENTS_OVERHEAD,
        segment_name=hls_segment_name,
        persist_at="state.json",
        HLS_DIR,
        [("aac_48", aac_low), ("aac_96", aac_mid), ("aac_192", aac_high)],
        hls_source
      )

    hls_output.on_file_change(synchronous=true, hls_upload_enqueue)
    thread.run(fast=false, every=0.25, hls_upload_worker)
    thread.run(fast=false, delay=5.0, hls_reconcile)
  else
    log(
      label="hls",
      "HLS output disabled - HLS_BUNNY_STORAGE_ZONE and/or \
       HLS_BUNNY_ACCESS_KEY not configured",
      level=3
    )
  end
end
