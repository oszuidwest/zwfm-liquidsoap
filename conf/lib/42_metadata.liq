# Shared stream metadata endpoint
# Inserts authenticated now-playing updates before the output fan-out.

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

def stream_metadata_body_too_large(req) =
  # Liquidsoap buffers each chunked HTTP chunk before req.data() returns it,
  # so chunked bodies cannot be bounded safely inside the handler.
  if
    req.headers["transfer-encoding"] != ""
  then
    true
  else
    try
      int_of_string(req.headers["content-length"]) >
        STREAM_METADATA_MAX_BODY_BYTES
    catch _ do
      false
    end
  end
end

def register_stream_metadata_endpoint(radio_source) =
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
    # Out-of-range ports would silently bind port mod 65536
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

      # Harbor lowercases incoming header names before handlers run
      if
        req.headers["authorization"] !=
          "Bearer #{STREAM_METADATA_BEARER_TOKEN}"
      then
        reject(
          401,
          "Unauthorized\n",
          "bad or missing bearer token"
        )
      elsif
        stream_metadata_body_too_large(req)
      then
        reject(
          413,
          "Payload Too Large\n",
          "body exceeds #{STREAM_METADATA_MAX_BODY_BYTES} bytes or uses \
           unsupported transfer encoding"
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
                "Inserted stream metadata: artist='#{artist}' title='#{title}'",
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
