# HLS output configuration
# Writes a local HLS window and mirrors it to Bunny Edge Storage.

let hls_bunny_headers = [("AccessKey", HLS_BUNNY_ACCESS_KEY)]
let hls_main_playlist_name = "live.m3u8"
let hls_endpoint_trimmed = string.trim(HLS_BUNNY_ENDPOINT)
let hls_endpoint_without_https =
  string.residual(prefix="https://", hls_endpoint_trimmed) ?? hls_endpoint_trimmed
let hls_endpoint_without_scheme =
  string.residual(prefix="http://", hls_endpoint_without_https) ??
    hls_endpoint_without_https
let hls_endpoint_host =
  r/\/+$/.replace(fun (_) -> "", hls_endpoint_without_scheme)

let hls_remote_dir_url =
  "https://#{hls_endpoint_host}/#{HLS_BUNNY_STORAGE_ZONE}/#{STATION_ID}/"

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
  r/\.aac$/.test(name)
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
      log(
        label="hls",
        "HLS upload failed for #{remote_name}: HTTP #{response.status_code} #{
          response.status_message
        }",
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

def hls_local_files(name_predicate) =
  if
    file.exists(HLS_DIR)
  then
    list.filter(
      fun (fname) ->
        begin
          not file.is_directory(fname)
          and name_predicate(path.basename(fname))
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
    {name=path.basename(local_path), content=file.contents(local_path)}
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
        if
          hls_is_segment_name(line)
        then
          path.basename(line)
        else
          null
        end
      end,
    r/\r?\n/.split(content)
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
      {ok=true, names=list.filter(hls_is_sync_file_name, names)}
    elsif
      response.status_code == 404
    then
      log(
        label="hls",
        "Bunny HLS prefix #{STATION_ID}/ does not exist yet; local files \
         will create it",
        level=3
      )
      {ok=true, names=[]}
    else
      log(
        label="hls",
        "HLS mirror listing failed: HTTP #{response.status_code} #{
          response.status_message
        }",
        level=2
      )
      {ok=false, names=[]}
    end
  catch err do
    log(
      label="hls",
      "HLS mirror listing exception: #{err.kind}: #{err.message}",
      level=2
    )
    {ok=false, names=[]}
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
        let previous = list.assoc.nullable(snapshot.name, synced_playlists())
        let changed =
          not null.defined(previous) or null.get(previous) != snapshot.content
        if
          changed
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
              "Deferring HLS playlist upload for #{snapshot.name}; at least \
               one referenced segment is not mirrored yet",
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

def hls_delete_stale_segments((synced_segments:ref), local_segment_names) =
  list.iter(
    fun (remote_name) ->
      begin
        if
          not list.mem(remote_name, local_segment_names)
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
  hls_seed_remote_segments(seeded, synced_segments)

  # Snapshot playlists before listing segments, then upload that exact content
  # after segment uploads. This preserves segment-before-playlist publication
  # even if Liquidsoap writes a newer playlist while this tick is running.
  let playlists = hls_playlist_snapshots()
  let segment_files = hls_local_segment_files()
  let local_segment_names =
    list.map(fun (fname) -> path.basename(fname), segment_files)

  hls_upload_segments(synced_segments, segment_files)

  let playlists_ok =
    not list.is_empty(playlists)
    and hls_upload_playlists(synced_playlists, synced_segments, playlists)

  if
    playlists_ok
  then
    hls_delete_stale_segments(synced_segments, local_segment_names)
  end
end

# Timestamped segment names are never reused, even if state.json is lost
# across restarts, so Bunny CDN can cache .aac segments with a long TTL.
def hls_segment_name(segment_metadata) =
  let ts = int_of_float(time())
  "#{segment_metadata.stream_name}_#{ts}_#{segment_metadata.position}.#{
    segment_metadata.extname
  }"
end

def output_hls_stream(audio_source) =
  if
    HLS_BUNNY_STORAGE_ZONE != "" and HLS_BUNNY_ACCESS_KEY != ""
  then
    log(
      label="hls",
      "HLS output enabled - writing #{HLS_SEGMENTS}x#{HLS_SEGMENT_DURATION}s to #{
        HLS_DIR
      }, uploading to #{HLS_BUNNY_STORAGE_ZONE}/#{STATION_ID}/",
      level=3
    )

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
        bandwidth = HLS_BITRATE_LOW * 1000 + 8000,
        codecs = "mp4a.40.5",
        extname = "aac"
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
        bandwidth = HLS_BITRATE_MID * 1000 + 8000,
        codecs = "mp4a.40.2",
        extname = "aac"
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
        bandwidth = HLS_BITRATE_HIGH * 1000 + 8000,
        codecs = "mp4a.40.2",
        extname = "aac"
      }

    let hls_output =
      output.file.hls(
        playlist=hls_main_playlist_name,
        segment_duration=HLS_SEGMENT_DURATION,
        segments=HLS_SEGMENTS,
        segments_overhead=HLS_SEGMENTS_OVERHEAD,
        segment_name=hls_segment_name,
        persist_at="state.json",
        HLS_DIR,
        [("aac_48", aac_low), ("aac_96", aac_mid), ("aac_192", aac_high)],
        hls_source
      )

    let hls_remote_seeded = ref(false)
    let hls_synced_segments = ref([])
    let hls_synced_playlists = ref([])
    thread.run(
      fast=false,
      delay=1.0,
      every=1.0,
      fun () ->
        hls_mirror_tick(
          hls_remote_seeded,
          hls_synced_segments,
          hls_synced_playlists
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
end
