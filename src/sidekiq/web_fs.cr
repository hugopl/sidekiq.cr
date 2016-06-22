require "zlib"

module Sidekiq
  # This could be extracted and genericized as a virtual filesystem macro.
  # This work is left as an exercise to the reader.
  module Filesystem

    struct StaticFile
      property! encoded : String
      property! size : Int32
      property! mime_type : String

      @content : Slice(UInt8)?
      def initialize(@encoded, path)
        @mime_type = mime_type(path)
        @size = 0
      end

      def content
        @content ||= begin
          outt = MemoryIO.new
          io = MemoryIO.new(Base64.decode(encoded), false)
          Zlib::Inflate.gzip(io) do |gz|
            @size = IO.copy gz, outt
          end
          io.close
          outt.to_slice
        end
      end

      def mime_type(path)
        case File.extname(path)
        when ".txt"          then "text/plain"
        when ".htm", ".html" then "text/html"
        when ".css"          then "text/css"
        when ".js"           then "application/javascript"
        else                      "application/octet-stream"
        end
      end
    end

    WEB_ASSETS = Hash(String, StaticFile).new

    {% for filename in `cd #{__DIR__}/.. && find web/assets -type f | cut -c11-`.stringify.split("\n") %}
      {% if filename.size > 0 %}
        WEB_ASSETS[{{filename}}] = StaticFile.new({{ `cd #{__DIR__}/.. && gzip -c9 web/assets#{filename.id} | base64`.stringify }}, {{ filename }})
      {% end %}
    {% end %}

    def self.serve(filename, resp)
      file = WEB_ASSETS[filename]
      resp.status_code = 200
      bytes = file.content
      resp.content_type = file.mime_type
      resp.content_length = file.size
      resp.write bytes
    end
  end
end
