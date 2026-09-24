# Loads the real output health modules; only the studio provider is stubbed,
# because it needs a live SRT listener.
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

let STATION_ID = "test"
let STREAM_METADATA_PORT = 7000
let STREAM_METADATA_BEARER_TOKEN = ""
let ICECAST_HOST = "127.0.0.1"
let ICECAST_PORT = 65534
let ICECAST_SOURCE_PASSWORD = "test"
let STATION_NAME =
  "Test Station"
let DAB_ACK_POLL_SECONDS = 1.0
let DAB_ACK_WARN_SECONDS = 5
let DAB_ACK_DOWN_SECONDS = 15
let DAB_ACK_STARTUP_GRACE_SECONDS = 10
let DAB_ACK_MONITOR_ENABLED = true
let DAB_BITRATE = ""
let DAB_EDI_DESTINATIONS = ""
let DAB_METADATA_SOCKET = ""
let DAB_METADATA_SIZE = ""
let HLS_BUNNY_STORAGE_ZONE = ""
let HLS_BUNNY_ACCESS_KEY = ""
let HLS_BUNNY_ENDPOINT = "storage.example.test"
let HLS_DIR = "/hls"
let HLS_BITRATE_MID = 96
let HLS_BITRATE_HIGH = 192
let HLS_SEGMENT_DURATION = 4.0
let HLS_SEGMENTS = 10
let HLS_SEGMENTS_OVERHEAD = 5

%include "../conf/lib/10_logging.liq"
%include "../conf/lib/20_state.liq"
%include "../conf/lib/60_output_icecast.liq"
%include "../conf/lib/61_output_dab.liq"
%include "../conf/lib/62_output_hls.liq"

# An unreachable Icecast server keeps the stream disconnected.
output_icecast_stream(
  format=%ffmpeg(
    format = "mp3",
    %audio(codec = "libmp3lame", b = "64k", ar = 48000, ac = 2)
  ),
  description="Test stream",
  mount="/test.mp3",
  audio_source=blank()
)

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
      let private_snapshot =
        status_snapshot(
          radio,
          (fun () -> "studio_a"),
          sources=[("studio_a", radio)],
          include_peer=true
        )
      let public_snapshot =
        status_snapshot(
          radio,
          (fun () -> "studio_a"),
          sources=[("studio_a", radio)]
        )

      # A disconnected Icecast stream degrades an otherwise healthy station.
      assert(private_snapshot.radio.ready)
      assert(private_snapshot.status == "degraded")
      assert(private_snapshot.outputs.icecast.status == "down")
      let icecast = list.hd(private_snapshot.outputs.icecast.streams)
      assert(icecast.id == "icecast__test_mp3_127_0_0_1")
      assert(icecast.port == 65534)
      assert(not icecast.connected)
      assert(private_snapshot.outputs.dab.status == "disabled")
      assert(list.is_empty(private_snapshot.outputs.dab.destinations))
      assert(private_snapshot.outputs.hls.status == "disabled")

      # The stubbed provider hides its own peer, so this only proves that
      # status_snapshot passes the caller's authorization through.
      let private_studio = list.hd(private_snapshot.studio_inputs)
      let private_connection = list.hd(private_studio.srt.connections)
      assert(null.get(private_connection.peer) == "192.0.2.1")
      let public_studio = list.hd(public_snapshot.studio_inputs)
      let public_connection = list.hd(public_studio.srt.connections)
      assert(not null.defined(public_connection.peer))

      # The complete snapshot, including nested health, must be JSON-safe.
      let encoded_public = json.stringify(compact=true, public_snapshot)
      assert(string.contains(substring="\"peer\":null", encoded_public))

      # No output repeats its structured health in a human-readable field.
      assert(not string.contains(substring="\"detail\"", encoded_public))
      thread.run(delay=0.1, shutdown)
    end
)
radio_sink.start()
