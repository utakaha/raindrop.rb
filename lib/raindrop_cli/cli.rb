# frozen_string_literal: true

require "io/console"
require "json"
require "optparse"
require "uri"

require_relative "client"
require_relative "config"
require_relative "errors"
require_relative "oauth"

module RaindropCli
  class CLI
    SUCCESS = 0
    FAILURE = 1
    DEFAULT_SEARCH_LIMIT = 50
    MAX_SEARCH_LIMIT = 50

    def initialize(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr, config: nil)
      @argv = argv.dup
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @config = config || Config.new
    end

    def run
      command = @argv.shift

      case command
      when "auth"
        run_auth(@argv)
      when "config"
        run_config(@argv)
      when "add"
        add(@argv)
      when "search"
        search(@argv)
      when "get"
        get(@argv)
      when "delete"
        delete(@argv)
      when "tags"
        tags(@argv)
      when "collections"
        collections(@argv)
      when "-h", "--help", nil
        print_usage
        SUCCESS
      else
        @stderr.puts "Unknown command: #{command}"
        print_usage(@stderr)
        FAILURE
      end
    rescue OptionParser::ParseError => e
      @stderr.puts e.message
      FAILURE
    rescue Error => e
      @stderr.puts e.message
      FAILURE
    end

    private

    def run_auth(argv)
      subcommand = argv.shift

      case subcommand
      when "login"
        auth_login(argv)
      when "token"
        reject_arguments!(argv)
        raise AuthenticationError, "Test token authentication is not supported. Run `raindrop auth login`."
      when "status"
        auth_status(argv)
      when "logout"
        auth_logout(argv)
      when "-h", "--help", nil
        print_auth_usage
        SUCCESS
      else
        @stderr.puts "Unknown auth command: #{subcommand}"
        print_auth_usage(@stderr)
        FAILURE
      end
    end

    def run_config(argv)
      subcommand = argv.shift

      case subcommand
      when "path"
        config_path(argv)
      when nil
        config_show(argv)
      when "-h", "--help"
        print_config_usage
        SUCCESS
      else
        @stderr.puts "Unknown config command: #{subcommand}"
        print_config_usage(@stderr)
        FAILURE
      end
    end

    def auth_login(argv)
      options = parse_auth_login_options(argv)
      reject_arguments!(argv)

      oauth = OAuth.new
      code = options.fetch(:code)
      redirect_uri = options.fetch(:redirect_uri) || OAuth::DEFAULT_REDIRECT_URI
      if code.to_s.strip.empty?
        @stdout.puts "Redirect URI:"
        @stdout.puts redirect_uri
        @stdout.puts
        @stdout.puts "Open this URL:"
        @stdout.puts oauth.authorization_url(
          client_id: options.fetch(:client_id),
          redirect_uri: redirect_uri
        )
        @stdout.puts "Waiting for OAuth callback on #{redirect_uri}"
        code = oauth.receive_authorization_code(redirect_uri: redirect_uri)
      end
      raise AuthenticationError, "Authorization code is empty." if code.to_s.strip.empty?

      payload = oauth.exchange_code(
        client_id: options.fetch(:client_id),
        client_secret: options.fetch(:client_secret),
        redirect_uri: redirect_uri,
        code: code.strip
      )
      @config.save_oauth_token(payload)
      @stdout.puts "OAuth token saved to #{@config.path}"
      SUCCESS
    end

    def auth_status(argv)
      reject_arguments!(argv)

      token = @config.access_token

      if token.empty?
        @stdout.puts "Not authenticated. Run `raindrop auth login`."
        FAILURE
      elsif @config.auth_type != "oauth"
        @stdout.puts "Test token authentication is not supported. Run `raindrop auth login`."
        FAILURE
      else
        @stdout.puts "Authenticated by #{@config.path}"
        SUCCESS
      end
    end

    def auth_logout(argv)
      reject_arguments!(argv)

      deleted = @config.delete_access_token
      if deleted
        @stdout.puts "Token removed from #{@config.path}"
      else
        @stdout.puts "No token found in #{@config.path}"
      end

      SUCCESS
    end

    def config_path(argv)
      reject_arguments!(argv)
      @stdout.puts @config.path
      SUCCESS
    end

    def config_show(argv)
      reject_arguments!(argv)

      type = @config.auth_type
      token = @config.access_token

      if type.empty? || token.empty?
        @stdout.puts "Auth: not configured"
      elsif type != "oauth"
        @stdout.puts "Auth: unsupported"
        @stdout.puts "Type: #{type}"
        @stdout.puts "Run `raindrop auth login`."
      else
        @stdout.puts "Auth: #{type}"
        @stdout.puts "Access token: [REDACTED]"
        @stdout.puts "Refresh token: #{@config.refresh_token? ? "[REDACTED]" : "not stored"}"
        @stdout.puts "Token type: #{@config.token_type.empty? ? "unknown" : @config.token_type}"
        @stdout.puts "Expires in: #{@config.expires_in || "unknown"}"
      end

      SUCCESS
    end

    def add(argv)
      options = parse_add_options(argv)
      link = parse_url(argv.shift)
      reject_arguments!(argv)

      payload = authenticated_client.create_raindrop(
        link,
        title: options.fetch(:title),
        excerpt: options.fetch(:description),
        note: options.fetch(:note),
        tags: options.fetch(:tags),
        collection_id: options.fetch(:collection_id)
      )
      item = payload.fetch("item", {})

      if options.fetch(:json)
        print_json_item(item)
      else
        print_raindrop_detail(item)
      end

      SUCCESS
    end

    def search(argv)
      options = parse_search_options(argv)
      query = build_search_query(argv, options)
      raise SearchError, "Search query is required." if query.empty? && search_query_required?(options)

      if options.fetch(:all)
        search_all(
          authenticated_client,
          query,
          collection_id: search_collection_id(options),
          json: options.fetch(:json)
        )
      else
        payload = authenticated_client.search_raindrops(
          query,
          collection_id: search_collection_id(options),
          perpage: options.fetch(:limit)
        )
        print_search_items(payload.fetch("items", []), json: options.fetch(:json))
      end

      SUCCESS
    end

    def get(argv)
      options = parse_get_options(argv)
      id = parse_raindrop_id(argv.shift)
      reject_arguments!(argv)

      payload = authenticated_client.get_raindrop(id)
      item = payload.fetch("item", {})

      if options.fetch(:json)
        print_json_item(item)
      else
        print_raindrop_detail(item)
      end

      SUCCESS
    end

    def delete(argv)
      options = parse_delete_options(argv)
      id = parse_raindrop_id(argv.shift)
      reject_arguments!(argv)

      payload = authenticated_client.delete_raindrop(id)
      print_delete_result(id, payload, json: options.fetch(:json))

      SUCCESS
    end

    def tags(argv)
      reject_arguments!(argv)

      payload = authenticated_client.tags
      items = payload.fetch("items", [])

      if items.empty?
        @stdout.puts "No tags found."
      else
        items.each do |item|
          @stdout.puts "#{item["_id"]}\t#{item["count"]}"
        end
      end

      SUCCESS
    end

    def collections(argv)
      reject_arguments!(argv)

      items = authenticated_client.root_collections.fetch("items", []) +
              authenticated_client.child_collections.fetch("items", [])
      items = unique_items_by_id(items)

      if items.empty?
        @stdout.puts "No collections found."
      else
        items.each do |item|
          @stdout.puts "#{item["_id"]}\t#{item["title"]}\t#{item["count"]}"
        end
      end

      SUCCESS
    end

    def authenticated_client
      @authenticated_client ||= begin
        token = @config.access_token
        raise AuthenticationError, "Not authenticated. Run `raindrop auth login`." if token.empty?
        raise AuthenticationError, "Test token authentication is not supported. Run `raindrop auth login`." unless @config.auth_type == "oauth"

        Client.new(token: token)
      end
    end

    def parse_auth_login_options(argv)
      options = { client_id: nil, client_secret: nil, redirect_uri: nil, code: nil }
      parser = OptionParser.new do |opts|
        opts.on("--client-id ID") do |client_id|
          options[:client_id] = client_id
        end

        opts.on("--client-secret SECRET") do |client_secret|
          options[:client_secret] = client_secret
        end

        opts.on("--redirect-uri URI") do |redirect_uri|
          options[:redirect_uri] = redirect_uri
        end

        opts.on("--code CODE") do |code|
          options[:code] = code
        end
      end
      parser.parse!(argv)
      validate_auth_login_options!(options)
      options
    end

    def parse_add_options(argv)
      options = { json: false, title: nil, description: nil, note: nil, tags: [], collection_id: nil }
      parser = OptionParser.new do |opts|
        opts.on("--json") do
          options[:json] = true
        end

        opts.on("--title TITLE") do |title|
          options[:title] = title
        end

        opts.on("--description DESCRIPTION") do |description|
          options[:description] = description
        end

        opts.on("--note NOTE") do |note|
          options[:note] = note
        end

        opts.on("--tag TAG") do |tag|
          options[:tags] << tag
        end

        opts.on("--collection ID", Integer) do |collection_id|
          options[:collection_id] = collection_id
        end
      end
      parser.parse!(argv)
      validate_add_options!(options)
      options
    end

    def parse_get_options(argv)
      options = { json: false }
      parser = OptionParser.new do |opts|
        opts.on("--json") do
          options[:json] = true
        end
      end
      parser.parse!(argv)
      options
    end

    def parse_delete_options(argv)
      options = { json: false }
      parser = OptionParser.new do |opts|
        opts.on("--json") do
          options[:json] = true
        end
      end
      parser.parse!(argv)
      options
    end

    def parse_raindrop_id(value)
      raise OptionParser::MissingArgument, "ID" if value.to_s.strip.empty?

      id = Integer(value, exception: false)
      raise OptionParser::InvalidArgument, value if id.nil? || id <= 0

      id
    end

    def parse_url(value)
      raise OptionParser::MissingArgument, "URL" if value.to_s.strip.empty?

      uri = URI.parse(value)
      return value if uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?

      raise OptionParser::InvalidArgument, value
    rescue URI::InvalidURIError
      raise OptionParser::InvalidArgument, value
    end

    def validate_add_options!(options)
      validate_optional_text!("title", options.fetch(:title))
      validate_optional_text!("description", options.fetch(:description))
      validate_optional_text!("note", options.fetch(:note))
      raise OptionParser::InvalidArgument, "tag" unless options.fetch(:tags).all? { |tag| !tag.to_s.strip.empty? }
    end

    def validate_optional_text!(name, value)
      return if value.nil? || !value.to_s.strip.empty?

      raise OptionParser::InvalidArgument, name
    end

    def validate_auth_login_options!(options)
      %i[client_id client_secret].each do |name|
        validate_required_text!(name.to_s.tr("_", "-"), options.fetch(name))
      end
      parse_url(options.fetch(:redirect_uri)) unless options.fetch(:redirect_uri).nil?
    end

    def validate_required_text!(name, value)
      raise OptionParser::MissingArgument, name if value.nil?
      raise OptionParser::InvalidArgument, name if value.to_s.strip.empty?
    end

    def parse_search_options(argv)
      options = { limit: DEFAULT_SEARCH_LIMIT, all: false, collection_id: nil, json: false, tags: [] }
      limit_option_used = false
      parser = OptionParser.new do |opts|
        opts.on("--all") do
          options[:all] = true
        end

        opts.on("--json") do
          options[:json] = true
        end

        opts.on("--collection ID", Integer) do |collection_id|
          options[:collection_id] = collection_id
        end

        opts.on("--limit LIMIT", Integer) do |limit|
          options[:limit] = limit
          limit_option_used = true
        end

        opts.on("--tag TAG") do |tag|
          options[:tags] << tag
        end
      end
      parser.parse!(argv)
      validate_search_options!(options, limit_option_used)
      options
    end

    def build_search_query(argv, options)
      query = argv.join(" ").strip
      tag_query = options.fetch(:tags).map { |tag| format_tag_query(tag) }.join(" ")
      [query, tag_query].reject(&:empty?).join(" ")
    end

    def validate_search_options!(options, limit_option_used)
      validate_limit!(options.fetch(:limit))
      validate_tags!(options.fetch(:tags))

      if options.fetch(:all) && limit_option_used
        raise SearchError, "`--all` cannot be used with `--limit`."
      end
    end

    def search_query_required?(options)
      options.fetch(:collection_id).nil?
    end

    def search_collection_id(options)
      options.fetch(:collection_id) || 0
    end

    def validate_limit!(limit)
      return if limit.between?(1, MAX_SEARCH_LIMIT)

      raise SearchError, "Search limit must be between 1 and #{MAX_SEARCH_LIMIT}."
    end

    def validate_tags!(tags)
      return if tags.all? { |tag| !tag.to_s.strip.empty? }

      raise SearchError, "Search tag must not be empty."
    end

    def format_tag_query(tag)
      tag = tag.strip
      return %(#"#{tag}") if tag.include?(" ")

      "##{tag}"
    end

    def search_all(client, query, collection_id:, json:)
      page = 0
      fetched = 0
      found = false
      collected_items = []

      loop do
        payload = client.search_raindrops(query, collection_id: collection_id, perpage: 50, page: page)
        items = payload.fetch("items", [])
        break if items.empty?

        if json
          collected_items.concat(items)
        else
          print_search_items(items)
        end
        found = true

        fetched += items.size
        count = payload["count"].to_i
        break if count.positive? && fetched >= count

        page += 1
        sleep 1
      end

      if json
        print_json_items(collected_items)
      else
        @stdout.puts "No raindrops found." unless found
      end
    end

    def print_search_items(items, json: false)
      return print_json_items(items) if json

      if items.empty?
        @stdout.puts "No raindrops found."
      else
        items.each do |item|
          id = item["_id"].to_s
          link = item["link"].to_s
          title = item["title"].to_s.strip
          title = link if title.empty?
          @stdout.puts "#{id}  #{title}"
          @stdout.puts "            #{link}"
          @stdout.puts
        end
      end
    end

    def print_json_items(items)
      @stdout.puts JSON.generate(items)
    end

    def print_json_item(item)
      @stdout.puts JSON.generate(item)
    end

    def print_delete_result(id, payload, json: false)
      if json
        print_json_item(payload)
      else
        @stdout.puts "Deleted raindrop: #{id}"
      end
    end

    def print_raindrop_detail(item)
      id = item["_id"].to_s
      link = item["link"].to_s
      title = item["title"].to_s.strip
      title = link if title.empty?
      tags = Array(item["tags"]).map(&:to_s)
      created = item["created"].to_s
      updated = item["lastUpdate"].to_s
      excerpt = item["excerpt"].to_s.strip
      note = item["note"].to_s.strip

      @stdout.puts "ID: #{id}" unless id.empty?
      @stdout.puts "Title: #{title}" unless title.empty?
      @stdout.puts "URL: #{link}" unless link.empty?
      @stdout.puts "Tags: #{tags.join(", ")}" unless tags.empty?
      @stdout.puts "Created: #{created}" unless created.empty?
      @stdout.puts "Updated: #{updated}" unless updated.empty?

      print_detail_text("Description", excerpt)
      print_detail_text("Note", note)
    end

    def print_detail_text(label, text)
      return if text.empty?

      @stdout.puts "#{label}:"
      @stdout.puts text
    end

    def unique_items_by_id(items)
      items.each_with_object({}) do |item, indexed_items|
        id = item["_id"]
        next if id.nil?

        indexed_items[id] ||= item
      end.values
    end

    def reject_arguments!(argv)
      raise OptionParser::InvalidArgument, argv.join(" ") unless argv.empty?
    end

    def print_usage(io = @stdout)
      io.puts <<~USAGE
        Usage: raindrop <command>

        Commands:
          add     Add a raindrop
          auth    Manage authentication
          config  Show configuration information
          delete  Delete a saved raindrop
          get     Show a saved raindrop
          search  Search saved raindrops
          tags    List tags
          collections
                  List collections
      USAGE
    end

    def print_auth_usage(io = @stdout)
      io.puts <<~USAGE
        Usage: raindrop auth <command>

        Commands:
          login   Login with OAuth
          status  Show authentication status
          logout  Remove the stored token
      USAGE
    end

    def print_config_usage(io = @stdout)
      io.puts <<~USAGE
        Usage: raindrop config [command]

        Commands:
          path    Show config file path
      USAGE
    end
  end
end
