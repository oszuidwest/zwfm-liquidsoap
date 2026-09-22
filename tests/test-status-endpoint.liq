# Minimal state required to load and exercise the shared HTTP status helpers.
let STATION_ID = "test"
let STREAM_METADATA_PORT = 7000
let STREAM_METADATA_BEARER_TOKEN = ""

def radio_mode() =
  "auto"
end
def is_silence_detection_enabled() =
  true
end
def icecast_health() =
  {
    status = "down",
    streams =
      [
        {
          id = "icecast_test_127_0_0_1",
          status = "down",
          host = "127.0.0.1",
          port = 8000,
          mount = "/test.mp3",
          description =
            "Test stream",
          started = true,
          ready = true,
          connected = false
        }
      ]
  }
end
def dab_ack_status() =
  {status = "disabled", destinations = []}
end
def dab_ack_healthy(_) =
  true
end
def hls_health() =
  {
    status = "disabled",
    local =
      {
        status = "disabled",
        error = null,
        playlist_count = 0,
        segment_count = 0,
        last_update_at = null,
        update_age_seconds = null
      },
    mirror =
      {
        status = "disabled",
        error = null,
        host = "storage.example.test",
        storage_zone = "",
        last_sync_at = null,
        sync_age_seconds = null,
        synced_segments = 0,
        pending_segments = 0,
        synced_playlists = 0,
        pending_playlists = 0
      }
  }
end
let studio_input_status_providers =
  ref(
    [
      fun (~include_peer) ->
        {
          name = "studio_a",
          ready = true,
          buffer_seconds = 1.03,
          audio =
            {
              window_seconds = 0.5,
              rms_dbfs = {left = -18.4, right = -17.9},
              peak_dbfs = {left = -6.2, right = -5.8}
            },
          srt =
            {
              connected = true,
              connections =
                [
                  {
                    peer = if include_peer then "192.0.2.1" else null end,
                    latency_ms = 2000,
                    receive_buffer_ms = 1876,
                    rtt_ms = 20.57,
                    dropped_packets_total = 0
                  }
                ]
            }
        }
    ]
  )

%include "../conf/lib/70_http.liq"

let radio = blank()

let radio_sink = output.dummy(start=false, register_telnet=false, radio)
radio_sink.on_start(
  synchronous=true,
  fun () ->
    begin
      let snapshot =
        status_snapshot(
          radio,
          (fun () -> "studio_a"),
          sources=[("studio_a", radio)],
          include_sensitive=true
        )

      assert(snapshot.radio.ready)
      assert(snapshot.status == "degraded")
      let studio = list.hd(snapshot.studio_inputs)
      assert(studio.name == "studio_a")
      assert(studio.ready)
      assert(studio.buffer_seconds == 1.03)
      assert(studio.audio.window_seconds == 0.5)
      assert(studio.audio.rms_dbfs.left == -18.4)
      assert(studio.audio.rms_dbfs.right == -17.9)
      assert(studio.audio.peak_dbfs.left == -6.2)
      assert(studio.audio.peak_dbfs.right == -5.8)
      assert(studio.srt.connected)
      let connection = list.hd(studio.srt.connections)
      assert(null.get(connection.peer) == "192.0.2.1")
      assert(connection.latency_ms == 2000)
      assert(connection.receive_buffer_ms == 1876)
      assert(connection.rtt_ms == 20.57)
      assert(connection.dropped_packets_total == 0)
      assert(snapshot.outputs.icecast.status == "down")
      let icecast = list.hd(snapshot.outputs.icecast.streams)
      assert(icecast.id == "icecast_test_127_0_0_1")
      assert(icecast.status == "down")
      assert(icecast.host == "127.0.0.1")
      assert(icecast.port == 8000)
      assert(icecast.mount == "/test.mp3")
      assert(icecast.started)
      assert(icecast.ready)
      assert(not icecast.connected)
      assert(list.is_empty(snapshot.outputs.dab.destinations))
      let encoded_dab = json.stringify(compact=true, snapshot.outputs.dab)
      assert(not string.contains(substring="\"detail\"", encoded_dab))
      assert(snapshot.outputs.hls.local.status == "disabled")
      assert(snapshot.outputs.hls.mirror.status == "disabled")

      # The public snapshot redacts peers; authenticated snapshots keep them.
      let public_snapshot =
        status_snapshot(
          radio,
          (fun () -> "studio_a"),
          sources=[("studio_a", radio)]
        )
      let public_studio = list.hd(public_snapshot.studio_inputs)
      let public_connection = list.hd(public_studio.srt.connections)
      assert(not null.defined(public_connection.peer))

      # Ensure the complete snapshot, including nested health, is JSON-safe.
      let encoded_snapshot = json.stringify(compact=true, snapshot)
      assert(string.contains(substring="\"studio_inputs\"", encoded_snapshot))
      assert(
        string.contains(
          substring="\"dropped_packets_total\":0",
          encoded_snapshot
        )
      )
      assert(string.contains(substring="\"rms_dbfs\"", encoded_snapshot))
      assert(string.contains(substring="\"peak_dbfs\"", encoded_snapshot))
      assert(string.contains(substring="\"icecast\"", encoded_snapshot))
      let encoded_public = json.stringify(compact=true, public_snapshot)
      assert(string.contains(substring="\"peer\":null", encoded_public))
      thread.run(delay=0.1, shutdown)
    end
)
radio_sink.start()
