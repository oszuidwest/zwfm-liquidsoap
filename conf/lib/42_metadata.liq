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
    def stream_metadata_handler(req, res) =
      res.header("Cache-Control", "no-store")

      # Harbor lowercases incoming header names before handlers run
      if
        req.headers["authorization"] !=
          "Bearer #{STREAM_METADATA_BEARER_TOKEN}"
      then
        res.status_code(401)
        res.data("Unauthorized\n")
      else
        let title = req.query["title"]
        let artist = req.query["artist"]

        if
          title == ""
        then
          res.status_code(400)
          res.data(
            "Missing title\n"
          )
        else
          radio_source.insert_metadata([("artist", artist), ("title", title)])
          res.status_code(204)
          log(
            label="metadata",
            "Inserted stream metadata",
            level=4
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
