# Shared stream metadata endpoint
# Inserts authenticated now-playing updates before the output fan-out.

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

      # Harbor lowercases incoming header names before handlers run
      if
        req.headers["authorization"] !=
          "Bearer #{STREAM_METADATA_BEARER_TOKEN}"
      then
        log(
          label="metadata",
          "Rejected metadata request: bad or missing bearer token",
          level=3
        )
        res.status_code(401)
        res.data("Unauthorized\n")
      else
        let title = req.query["title"]
        let artist = req.query["artist"]

        if
          title == ""
        then
          log(
            label="metadata",
            "Rejected metadata request: missing title",
            level=3
          )
          res.status_code(400)
          res.data(
            "Missing title\n"
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
      end
    end

    harbor.http.register(
      port=STREAM_METADATA_PORT,
      method="GET",
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
