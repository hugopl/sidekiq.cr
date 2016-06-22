module Sidekiq
  # This could be extracted and genericized as a virtual filesystem macro.
  # This work is left as an exercise to the reader.
  module Filesystem
    struct StaticFile
      property! encoded : String
      property! size : Int32
      property! mime_type : String
      def initialize(@encoded, path)
        @size = Base64.decode(@encoded.not_nil!).size
        @mime_type = mime_type(path)
      end
      def content
        Base64.decode(encoded)
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

    {% for filename in `find web/assets -type f | cut -c11-`.stringify.split("\n") %}
      {% if filename.size > 0 %}
        WEB_ASSETS[{{filename}}] = StaticFile.new({{ `base64 web/assets#{filename.id}`.stringify }}, {{ filename }})
      {% end %}
    {% end %}

    def self.serve(filename, resp)
      file = WEB_ASSETS[filename]
      resp.status_code = 200
      resp.content_type = file.mime_type
      resp.content_length = file.size
      resp.write file.content
    end
  end
end
