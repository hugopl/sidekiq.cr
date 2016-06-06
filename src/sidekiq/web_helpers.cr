require "yaml"
require "uri"

module Sidekiq
  module WebHelpers
    LANGS = %w(cs da de el en es fr hi it ja ko nb nl pl pt-br pt ru sv ta uk xx zh-cn zh-tw)
    LOCALE_PATHS = ["../../web/locales"]

    @locale : String?
    macro included
      @@strings = {} of String => Hash(String, String)
      {% for lang in LANGS %}
        begin
          @@strings[{{lang}}] = text = Hash(String, String).new
        {% for path in LOCALE_PATHS %}
          io = {{ system("cat #{__DIR__}/#{path.id}/#{lang.id}.yml 2>/dev/null || true").stringify }}
          text.merge! YAML.parse(io)[{{lang}}].as(Hash(String, String))
        {% end %}
        end
      {% end %}
    end

    # This is a hook for a Sidekiq Pro feature.  Please don"t touch.
    def filtering(*args)
    end

    # Given a browser request Accept-Language header like
    # "fr-FR,fr;q=0.8,en-US;q=0.6,en;q=0.4,ru;q=0.2", this function
    # will return "fr" since that"s the first code with a matching
    # locale in web/locales
    def locale
      @locale ||= begin
        locale = "en"
        languages = request.headers["HTTP_ACCEPT_LANGUAGE"] || "en"
        languages.downcase.split(",").each do |lang|
          next if lang == "*"
          lang = lang.split(";")[0]
          break locale = lang if @@strings[lang]?
        end
        locale
      end
    end

    def get_locale
      @@strings[locale]
    end

    def t(msg, options={} of String => String)
      string = get_locale[msg] || msg
      if options.empty?
        string
      else
        string % options
      end
    end

    def workers
      @workers ||= Sidekiq::Workers.new
    end

    def processes
      @processes ||= Sidekiq::ProcessSet.new
    end

    def stats
      @stats ||= Sidekiq::Stats.new
    end

    def retries_with_score(score)
      Sidekiq.redis do |conn|
        conn.zrangebyscore("retry", score, score)
      end.map { |msg| JSON.parse(msg).as_h }
    end

    def location
      Sidekiq.redis { |conn| conn.client.location }
    end

    def redis_connection
      Sidekiq.redis { |conn| conn.client.id }
    end

    def namespace
      nil
    end

    def redis_info
      Sidekiq.redis_info
    end

    def root_path
      "/"
    end

    #def current_path
      #request.path_info.gsub(/^\//,"")
    #end

    def current_status
      workers.size == 0 ? "idle" : "active"
    end

    def relative_time(time)
      %{<time datetime="#{time.to_utc.to_s("%Y-%m-%dT%H:%M:%SZ")}">#{time}</time>}
    end

    def job_params(job, score)
      "#{score}-#{job["jid"]}"
    end

    def parse_params(params)
      score, jid = params.split("-")
      [score.to_f, jid]
    end

    SAFE_QPARAMS = %w(page poll)

    # Merge options with current params, filter safe params, and stringify to query string
    def qparams(options)
      options = options.stringify_keys
      params.merge(options).map do |key, value|
        SAFE_QPARAMS.include?(key) ? "#{key}=#{value}" : next
      end.compact.join("&")
    end

    def truncate(text, truncate_after_chars = 2000)
      truncate_after_chars && text.size > truncate_after_chars ? "#{text[0..truncate_after_chars]}..." : text
    end

    def display_args(args, truncate_after_chars = 2000)
      args.map do |arg|
        h(truncate(to_display(arg), truncate_after_chars))
      end.join(", ")
    end

    def csrf_tag
      #"<input type='hidden' name='authenticity_token' value='#{session[:csrf]}'/>"
      ""
    end

    def to_display(arg)
      begin
        arg.inspect
      rescue
        begin
          arg.to_s
        rescue ex
          "Cannot display argument: [#{ex.class.name}] #{ex.message}"
        end
      end
    end

    RETRY_JOB_KEYS = Set.new(%w(
      queue class args retry_count retried_at failed_at
      jid error_message error_class backtrace
      error_backtrace enqueued_at retry wrapped
      created_at
    ))

    def retry_extra_items(retry_job)
      @retry_extra_items ||= Hash(String, JSON::Type).new.tap do |extra|
        retry_job.item.each do |key, value|
          extra[key] = value unless RETRY_JOB_KEYS.include?(key)
        end
      end
    end

    def number_with_delimiter(number)
      number.to_s
    end

    def h(text)
      HTML.escape(text)
    end

    # Any paginated list that performs an action needs to redirect
    # back to the proper page after performing that action.
    def redirect_with_query(url)
      r = request.referer
      if r && r =~ /\?/
        ref = URI.parse(r)
        redirect("#{url}?#{ref.query}")
      else
        redirect url
      end
    end

    def environment_title_prefix
      ENV["APP_ENV"] || "development"
    end

    def product_version
      "Sidekiq v#{Sidekiq::VERSION}"
    end

    def redis_connection_and_namespace
      @redis_connection_and_namespace ||= begin
        namespace_suffix = namespace == nil ? "" : "##{namespace}"
        "#{redis_connection}#{namespace_suffix}"
      end
    end

    def page(key, pageidx=1, page_size=25, opts=nil)
      current_page = pageidx.to_i < 1 ? 1 : pageidx.to_i
      pageidx = current_page - 1
      total_size = 0
      items = [] of String
      starting = pageidx * page_size
      ending = starting + page_size - 1

      Sidekiq.redis do |conn|
        type = conn.type(key)

        case type
        when "zset"
          rev = opts && opts[:reverse]
          total_size, items = conn.multi do |m|
            m.zcard(key)
            if rev
              m.zrevrange(key, starting, ending, {"with_scores": true})
            else
              m.zrange(key, starting, ending, {"with_scores": true})
            end
          end
          [current_page, total_size, items]
        when "list"
          total_size, items = conn.multi do |m|
            m.llen(key)
            m.lrange(key, starting, ending)
          end
          [current_page, total_size, items]
        when "none"
          [1, 0, [] of String]
        else
          raise "can't page a #{type}"
        end
      end
    end

  end
end
