# Stub only the studio provider, which requires a live SRT listener; assigning
# into the real registry type-checks the stub against the real provider.
settings.frame.audio.channels := 2
settings.frame.audio.samplerate := 48000

let STATION_ID = "test"
let SRT_PASSPHRASE = "test-passphrase"
let SILENCE_SWITCH_SECONDS = 15.0
let AUDIO_VALID_SECONDS = 15.0
let SILENCE_THRESHOLD = -40.0
let STREAM_METADATA_PORT = 7000
let STREAM_METADATA_BEARER_TOKEN = "test-token"
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
%include "../conf/lib/30_silence.liq"
%include "../conf/lib/41_source_studio.liq"
%include "../conf/lib/60_output_icecast.liq"
%include "../conf/lib/61_output_dab.liq"
%include "../conf/lib/62_output_hls.liq"

let dab_fixture =
  dab_parse_ack_monitor(
    "ok\ntcp://192.0.2.10:9171\tok\tESTAB\t0\t100\t101\t1745\t1\t0\t"
  )
dab_set_ack_status(
  dab_fixture.status,
  dab_fixture.detail,
  destinations=dab_fixture.destinations
)

# Keep the Icecast stream disconnected.
output_icecast_stream(
  format=%ffmpeg(
    format = "mp3",
    %audio(codec = "libmp3lame", b = "64k", ar = 48000, ac = 2)
  ),
  description="Test stream",
  mount="/test.mp3",
  audio_source=blank()
)

studio_input_status_providers :=
  [
    fun (~include_peer) ->
      {
        name = "studio_a",
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
                  dropped_packets_total = 0,
                  statistics_error = null
                }
              ]
          }
      }
  ]

%include "../conf/lib/70_http.liq"

let radio = blank()

register_http_endpoints(
  radio,
  (fun () -> "studio_a"),
  sources=[("studio_a", radio)]
)

let radio_sink = output.dummy(start=false, register_telnet=false, radio)
radio_sink.on_start(
  synchronous=true,
  fun () ->
    begin
      let snapshot =
        status_snapshot(
          radio,
          (fun () -> "studio_a"),
          sources=[("studio_a", radio)]
        )

      # A disconnected Icecast stream degrades the station.
      assert(snapshot.radio.ready)
      assert(snapshot.status == "degraded")
      assert(snapshot.outputs.icecast.status == "down")
      let icecast = list.hd(snapshot.outputs.icecast.streams)
      assert(icecast.id == "icecast__test_mp3_127_0_0_1")
      assert(icecast.host == "127.0.0.1")
      assert(icecast.port == 65534)
      assert(icecast.mount == "/test.mp3")
      assert(
        icecast.description ==
          "Test stream"
      )
      assert(not icecast.connected)
      assert(snapshot.outputs.dab.status == "ok")
      assert(list.is_empty(snapshot.outputs.dab.destinations))
      assert(snapshot.outputs.hls.status == "disabled")

      # Structured output health must not be duplicated as detail text.
      assert(
        not string.contains(
          substring="\"detail\"",
          json.stringify(compact=true, snapshot)
        )
      )

      # Only the configured bearer token exposes peer addresses over HTTP.
      thread.run(
        delay=1.0,
        fun () ->
          begin
            # Started does not mean connected: Icecast connects lazily.
            let started_stream = list.hd(icecast_health().streams)
            assert(started_stream.started)
            assert(not started_stream.connected)

            def assert_sensitive(headers, expected_peer, expected_sensitive) =
              let body =
                http.get(
                  timeout=2.0,
                  headers=headers,
                  "http://127.0.0.1:7000/status"
                )
              assert(
                string.contains(substring="\"peer\":#{expected_peer}", body)
              )
              assert(
                string.contains(substring="tcp://192.0.2.10:9171", body) ==
                  expected_sensitive
              )
            end
            assert_sensitive([], "null", false)
            assert_sensitive([("Authorization", "Bearer wrong")], "null", false)
            assert_sensitive(
              [("Authorization", "Bearer test-token")],
              "\"192.0.2.1\"",
              true
            )
            shutdown()
          end
      )
    end
)
radio_sink.start()
