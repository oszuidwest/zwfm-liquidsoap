# Shared HTTP endpoints
# Exposes machine-readable runtime status and accepts authenticated now-playing
# updates before the output fan-out.

let STREAM_METADATA_MAX_BODY_BYTES = 16_384

def read_stream_metadata_body(req) =
  def rec read_stream_metadata_chunks(body) =
    let chunk = req.data()

    if
      chunk == ""
    then
      {body = body, too_large = false}
    elsif
      string.bytes.length(body) + string.bytes.length(chunk) >
        STREAM_METADATA_MAX_BODY_BYTES
    then
      {body = "", too_large = true}
    else
      read_stream_metadata_chunks(body ^ chunk)
    end
  end

  read_stream_metadata_chunks("")
end

# Harbor lowercases incoming header names before handlers run
def request_authorized(req) =
  STREAM_METADATA_BEARER_TOKEN != ""
  and req.headers["authorization"] ==
    "Bearer #{STREAM_METADATA_BEARER_TOKEN}"
end

def status_snapshot(
  radio_source,
  active_source,
  ~sources,
  ~include_peer=false
) =
  let radio_ready = radio_source.is_ready()
  let active_source = active_source()
  let icecast_state = icecast_health()
  let dab_state = dab_ack_status()
  let hls_state = hls_health()
  let status =
    if
      not radio_ready
    then
      "down"
    elsif
      active_source == "fallback"
      or not list.for_all(
        status_healthy,
        [icecast_state.status, dab_state.status, hls_state.status]
      )
    then
      "degraded"
    else
      "ok"
    end

  {
    status = status,
    station_id = STATION_ID,
    timestamp = time(),
    radio =
      {ready = radio_ready, mode = radio_mode(), active_source = active_source},
    silence_detection_enabled = is_silence_detection_enabled(),
    sources =
      list.map(
        fun ((name, src)) -> {name = name, ready = source.is_ready(src)},
        sources
      ),
    studio_inputs =
      list.map(
        fun (get_status) -> get_status(include_peer=include_peer),
        studio_input_status_providers()
      ),
    outputs = {icecast = icecast_state, dab = dab_state, hls = hls_state}
  }
end

def register_http_endpoints(radio_source, active_source, ~sources) =
  # Out-of-range ports would silently bind port mod 65536.
  if
    STREAM_METADATA_PORT < 1 or STREAM_METADATA_PORT > 65535
  then
    error.raise(
      error.invalid,
      "STREAM_METADATA_PORT must be between 1 and 65535, got #{
        STREAM_METADATA_PORT
      }"
    )
  end

  # HTTP monitors and healthchecks alert on the status code: 503 when the
  # radio source is down, 200 otherwise (degraded is still on air). HEAD is
  # registered too because some monitors probe with it by default.
  def status_handler(req, res) =
    let snapshot =
      status_snapshot(
        radio_source,
        active_source,
        sources=sources,
        include_peer=request_authorized(req)
      )
    res.header("Cache-Control", "no-store")
    if snapshot.status == "down" then res.status_code(503) end
    res.json(compact=true, snapshot)
  end

  list.iter(
    fun (method) ->
      harbor.http.register(
        port=STREAM_METADATA_PORT,
        method=method,
        "/status",
        status_handler
      ),
    ["GET", "HEAD"]
  )
  log(
    label="status",
    "Status endpoint enabled on port #{STREAM_METADATA_PORT}",
    level=3
  )

  if
    STREAM_METADATA_BEARER_TOKEN == ""
  then
    log(
      label="metadata",
      "Stream metadata endpoint disabled - STREAM_METADATA_BEARER_TOKEN not \
       configured",
      level=3
    )
  else
    def stream_metadata_handler(req, res) =
      res.header("Cache-Control", "no-store")

      def reject(code, body, reason) =
        log(
          label="metadata",
          "Rejected metadata request: #{reason}",
          level=3
        )
        res.status_code(code)
        res.data(body)
      end

      if
        not request_authorized(req)
      then
        res.header(
          "WWW-Authenticate",
          "Bearer realm=\"metadata\""
        )
        reject(
          401,
          "Unauthorized\n",
          "bad or missing bearer token"
        )
      elsif
        # Liquidsoap buffers each chunked HTTP chunk before req.data() returns
        # it, so chunked bodies cannot be bounded inside the handler
        req.headers["transfer-encoding"] != ""
      then
        reject(
          413,
          "Payload Too Large\n",
          "unsupported transfer encoding"
        )
      else
        let request_body = read_stream_metadata_body(req)

        if
          request_body.too_large
        then
          reject(
            413,
            "Payload Too Large\n",
            "body exceeds #{STREAM_METADATA_MAX_BODY_BYTES} bytes"
          )
        else
          try
            let json.parse ({title, artist} :
              {title: string, artist: string?}
            ) = request_body.body
            let artist = artist ?? ""

            if
              title == ""
            then
              reject(
                400,
                "Missing title\n",
                "missing title"
              )
            else
              # An omitted artist sends a title-only update instead of an empty
              # artist tag
              let new_metadata =
                if
                  artist == ""
                then
                  [("title", title)]
                else
                  [("artist", artist), ("title", title)]
                end

              radio_source.insert_metadata(new_metadata)
              res.status_code(204)
              log(
                label="metadata",
                "Inserted stream metadata",
                level=3
              )
            end
          catch err : [error.json] do
            reject(
              400,
              "Invalid JSON body\n",
              "invalid JSON body: #{err.message}"
            )
          end
        end
      end
    end

    harbor.http.register(
      port=STREAM_METADATA_PORT,
      method="POST",
      "/metadata",
      stream_metadata_handler
    )
    log(
      label="metadata",
      "Stream metadata endpoint enabled on port #{STREAM_METADATA_PORT}",
      level=3
    )
  end
end
