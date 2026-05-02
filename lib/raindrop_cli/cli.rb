# frozen_string_literal: true

require "io/console"
require "optparse"

require_relative "client"
require_relative "config"
require_relative "errors"

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
      when "search"
        search(@argv)
      when "tags"
        tags(@argv)
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
      when "token"
        auth_token(argv)
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

    def auth_token(argv)
      reject_arguments!(argv)

      token = read_token_input
      raise AuthenticationError, "Token is empty." if token.empty?

      @config.save_access_token(token)
      @stdout.puts "Token saved to #{@config.path}"
      SUCCESS
    end

    def auth_status(argv)
      reject_arguments!(argv)

      token = @config.access_token

      if token.empty?
        @stdout.puts "Not authenticated. Run `raindrop auth token`."
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

    def search(argv)
      options = parse_search_options(argv)
      query = build_search_query(argv, options)
      raise SearchError, "Search query is required." if query.empty?

      token = @config.access_token
      raise AuthenticationError, "Not authenticated. Run `raindrop auth token`." if token.empty?

      client = Client.new(token: token)
      if options.fetch(:all)
        search_all(client, query)
      else
        payload = client.search_raindrops(query, perpage: options.fetch(:limit))
        print_search_items(payload.fetch("items", []))
      end

      SUCCESS
    end

    def tags(argv)
      reject_arguments!(argv)

      token = @config.access_token
      raise AuthenticationError, "Not authenticated. Run `raindrop auth token`." if token.empty?

      payload = Client.new(token: token).tags
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

    def parse_search_options(argv)
      options = { limit: DEFAULT_SEARCH_LIMIT, all: false, tags: [] }
      limit_option_used = false
      parser = OptionParser.new do |opts|
        opts.on("--all") do
          options[:all] = true
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

    def search_all(client, query)
      page = 0
      fetched = 0
      printed_any = false

      loop do
        payload = client.search_raindrops(query, perpage: 50, page: page)
        items = payload.fetch("items", [])
        break if items.empty?

        print_search_items(items)
        printed_any = true

        fetched += items.size
        count = payload["count"].to_i
        break if count.positive? && fetched >= count

        page += 1
      end

      @stdout.puts "No raindrops found." unless printed_any
    end

    def print_search_items(items)
      if items.empty?
        @stdout.puts "No raindrops found."
      else
        items.each do |item|
          id = (item["_id"] || item["id"]).to_s
          link = item["link"].to_s
          title = item["title"].to_s.strip
          title = link if title.empty?
          @stdout.puts "#{id}\t#{title}\t#{link}"
        end
      end
    end

    def reject_arguments!(argv)
      raise OptionParser::InvalidArgument, argv.join(" ") unless argv.empty?
    end

    def read_token_input
      if @stdin.tty?
        @stdout.print "Test token: "
        token = @stdin.noecho(&:gets).to_s
        @stdout.puts
        token.strip
      else
        @stdin.read.to_s.strip
      end
    end

    def print_usage(io = @stdout)
      io.puts <<~USAGE
        Usage: raindrop <command>

        Commands:
          auth    Manage authentication
          search  Search saved raindrops
          tags    List tags
      USAGE
    end

    def print_auth_usage(io = @stdout)
      io.puts <<~USAGE
        Usage: raindrop auth <command>

        Commands:
          token   Save a Test token to the config file
          status  Show authentication status
          logout  Remove the stored token
      USAGE
    end
  end
end
