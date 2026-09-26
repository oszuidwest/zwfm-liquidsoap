# Bearer-authenticated runtime status and now-playing endpoints.

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

# Harbor lowercases request header names.
def request_authorized(req, token) =
  token != ""
  and req.headers["authorization"] ==
    "Bearer #{token}"
end

def http_reject(res, label, code, body, reason) =
  log(
    label=label,
    "Rejected #{label} request: #{reason}",
    level=3
  )
  res.status_code(code)
  res.data(body)
end

# Every handler registered here requires its token; an empty token disables it.
def register_bearer_endpoint(
  ~label,
  ~token,
  ~token_name,
  ~method,
  path,
  handler
) =
  if
    token == ""
  then
    log(
      label=label,
      "#{method} #{path} disabled - #{token_name} not configured",
      level=3
    )
  else
    harbor.http.register(
      port=HTTP_PORT,
      method=method,
      path,
      fun (req, res) ->
        begin
          res.header("Cache-Control", "no-store")
          if
            request_authorized(req, token)
          then
            handler(req, res)
          else
            res.header(
              "WWW-Authenticate",
              "Bearer realm=\"#{label}\""
            )
            http_reject(
              res,
              label,
              401,
              "Unauthorized\n",
              "bad or missing bearer token"
            )
          end
        end
    )
    log(
      label=label,
      "#{method} #{path} enabled on port #{HTTP_PORT}",
      level=3
    )
  end
end

# Keep the schema stable by representing unavailable values as null.
def status_snapshot(radio_source, active_source, ~sources) =
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
        fun (get_status) -> get_status(),
        studio_input_status_providers()
      ),
    outputs = {icecast = icecast_state, dab = dab_state, hls = hls_state}
  }
end

def register_http_endpoints(radio_source, active_source, ~sources) =
  # Out-of-range ports would silently bind port mod 65536.
  if
    HTTP_PORT < 1 or HTTP_PORT > 65535
  then
    error.raise(
      error.invalid,
      "HTTP_PORT must be between 1 and 65535, got #{HTTP_PORT}"
    )
  end

  # Degraded is on air (200); only down is 503.
  def status_handler(_, res) =
    let snapshot = status_snapshot(radio_source, active_source, sources=sources)
    if snapshot.status == "down" then res.status_code(503) end
    res.json(compact=true, snapshot)
  end

  def stream_metadata_handler(req, res) =
    def reject(code, body, reason) =
      http_reject(res, "metadata", code, body, reason)
    end

    if
      # Harbor reads each chunk whole before req.data() returns, so the body
      # size cap cannot bound chunked requests.
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
          let json.parse ({title, artist} : {title: string, artist: string?}) =
            request_body.body
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
            # Omit the artist tag instead of sending an empty value.
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

  register_bearer_endpoint(
    label="status",
    token=STATUS_BEARER_TOKEN,
    token_name="STATUS_BEARER_TOKEN",
    method="GET",
    "/status",
    status_handler
  )
  register_bearer_endpoint(
    label="metadata",
    token=STREAM_METADATA_BEARER_TOKEN,
    token_name="STREAM_METADATA_BEARER_TOKEN",
    method="POST",
    "/metadata",
    stream_metadata_handler
  )
end
