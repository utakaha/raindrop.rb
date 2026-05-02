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
      query = argv.join(" ").strip
      raise SearchError, "Search query is required." if query.empty?

      token = @config.access_token
      raise AuthenticationError, "Not authenticated. Run `raindrop auth token`." if token.empty?

      payload = Client.new(token: token).search_raindrops(query)
      items = payload.fetch("items", [])

      if items.empty?
        @stdout.puts "No raindrops found."
      else
        items.each do |item|
          id = item["_id"].to_s
          link = item["link"].to_s
          title = item["title"].to_s.strip
          title = link if title.empty?
          @stdout.puts "#{id}\t#{title}\t#{link}"
        end
      end

      SUCCESS
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
