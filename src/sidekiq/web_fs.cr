require "baked_file_system"

module Sidekiq
  module Filesystem
    BakedFileSystem.load("../web/assets", __DIR__)

    def self.serve(file, ctx)
      req = ctx.request
      resp = ctx.response
      resp.status_code = 200
      resp.content_type = file.mime_type
      if req.headers["Accept-Encoding"]? =~ /gzip/
        resp.headers["Content-Encoding"] = "gzip"
        resp.content_length = file.compressed_size
        file.write_to_io(resp, compressed: true)
      else
        resp.content_length = file.size
        file.write_to_io(resp, compressed: false)
      end
    end
  end
end
