# Stub only the studio provider, which requires a live SRT listener; assigning
# into the real registry type-checks the stub against the real provider.

# Load the real settings; set only required and test-specific values.
environment.set("STATION_ID", "test")
environment.set("STATION_NAME", "Test Station")
environment.set("ICECAST_HOST", "127.0.0.1")
environment.set("ICECAST_PORT", "65534")
environment.set("ICECAST_SOURCE_PASSWORD", "test")
environment.set("SRT_PASSPHRASE", "test-passphrase")
environment.set("STREAM_METADATA_BEARER_TOKEN", "test-metadata-token")
environment.set("STATUS_BEARER_TOKEN", "test-status-token")

%include "../conf/lib/00_settings.liq"
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
dab_set_ack_status(dab_fixture.status, destinations=dab_fixture.destinations)

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
    fun () ->
      {
        name = "studio_a",
        status = "ok",
        error = null,
        buffer_seconds = 1.03,
        audio =
          {
            rms_dbfs = {left = -18.4, right = -17.9},
            peak_dbfs = {left = -6.2, right = -5.8}
          },
        srt =
          {
            connected = true,
            connections =
              [
                {
                  peer = "192.0.2.1",
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
      assert(not icecast.connected)
      let studio = list.hd(snapshot.studio_inputs)
      assert(studio.status == "ok")
      assert(not null.defined(studio.error))
      assert(snapshot.outputs.dab.status == "ok")
      assert(list.length(snapshot.outputs.dab.destinations) == 1)
      assert(snapshot.outputs.hls.status == "disabled")
      assert(not null.defined(snapshot.outputs.hls.mirror.host))
      assert(not null.defined(snapshot.outputs.hls.mirror.storage_zone))

      # The public schema excludes free-text detail.
      assert(
        not string.contains(
          substring="\"detail\"",
          json.stringify(compact=true, snapshot)
        )
      )

      # Verify token isolation and fail the process on test-thread errors.
      thread.run(
        delay=1.0,
        fun () ->
          try
            def bearer(token) =
              [
                (
                  "Authorization",
                  "Bearer #{token}"
                )
              ]
            end

            def get_status(headers) =
              http.get(
                timeout=2.0,
                headers=headers,
                "http://127.0.0.1:7000/status"
              )
            end

            def assert_unauthorized(response, realm) =
              assert(response.status_code == 401)
              assert(
                response.headers["www-authenticate"] ==
                  "Bearer realm=\"#{realm}\""
              )
              assert(not string.contains(substring="192.0.2", response))
            end
            assert_unauthorized(get_status([]), "status")
            assert_unauthorized(get_status(bearer("wrong")), "status")
            assert_unauthorized(
              get_status(bearer("test-metadata-token")),
              "status"
            )

            let response = get_status(bearer("test-status-token"))
            assert(response.status_code == 200)
            assert(
              string.contains(substring="\"peer\":\"192.0.2.1\"", response)
            )
            assert(
              string.contains(
                substring="\"destination\":\"tcp://192.0.2.10:9171\"",
                response
              )
            )

            # Reject the status token on the metadata endpoint.
            assert_unauthorized(
              http.post(
                timeout=2.0,
                headers=bearer("test-status-token"),
                data="{\"title\":\"x\"}",
                "http://127.0.0.1:7000/metadata"
              ),
              "metadata"
            )
            shutdown()
          catch err do
            print(
              "Status endpoint test failed: #{err}"
            )
            shutdown(code=1)
          end
      )
    end
)
radio_sink.start()
