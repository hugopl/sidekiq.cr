require "zlib"
require "baked_file_system"

module Sidekiq
  module Filesystem
    BakedFileSystem.load("../web/assets", __DIR__)

    def self.serve(file, resp)
      resp.status_code = 200
      resp.content_type = file.mime_type
      resp.content_length = file.size
      resp.write file.to_slice
    end
  end
end
