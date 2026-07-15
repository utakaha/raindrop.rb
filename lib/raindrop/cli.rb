# frozen_string_literal: true

require 'io/console'
require 'json'
require 'optparse'
require 'time'
require 'uri'

require_relative 'client'
require_relative 'config'
require_relative 'errors'
require_relative 'oauth'

module Raindrop
  class CLI
    SUCCESS = 0
    FAILURE = 1
    INTERRUPTED = 130
    DEFAULT_SEARCH_LIMIT = 50
    MAX_SEARCH_LIMIT = 50
    SEARCH_TABLE_COLUMNS = [
      { key: :id, label: 'ID', max_width: 10 },
      { key: :title, label: 'TITLE', max_width: 60 },
      { key: :url, label: 'URL', max_width: 60 },
      { key: :saved_at, label: 'SAVED AT', max_width: 20 }
    ].freeze
    TAG_TABLE_COLUMNS = [
      { key: :name, label: 'TAG', max_width: 40 },
      { key: :count, label: 'COUNT', max_width: 10 }
    ].freeze
    COLLECTION_TABLE_COLUMNS = [
      { key: :id, label: 'ID', max_width: 10 },
      { key: :title, label: 'TITLE', max_width: 60 },
      { key: :count, label: 'COUNT', max_width: 10 }
    ].freeze
    SEARCH_SORTS = %w[
      -created
      created
      score
      -sort
      title
      -title
      domain
      -domain
    ].freeze

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
      when 'auth'
        run_auth(@argv)
      when 'config'
        run_config(@argv)
      when 'add'
        add(@argv)
      when 'search'
        search(@argv)
      when 'get'
        get(@argv)
      when 'update'
        update(@argv)
      when 'delete'
        delete(@argv)
      when 'tags'
        run_tags(@argv)
      when 'collections'
        collections(@argv)
      when '-h', '--help', nil
        print_usage
        SUCCESS
      else
        @stderr.puts "Unknown command: #{command}"
        print_usage(@stderr)
        FAILURE
      end
    rescue OptionParser::ParseError, Error => e
      @stderr.puts e.message
      FAILURE
    rescue Interrupt
      @stderr.puts
      INTERRUPTED
    end

    private

    def run_auth(argv)
      subcommand = argv.shift

      case subcommand
      when 'login'
        auth_login(argv)
      when 'token'
        reject_arguments!(argv)
        raise AuthenticationError, 'Test token authentication is not supported. Run `raindrop auth login`.'
      when 'status'
        auth_status(argv)
      when 'logout'
        auth_logout(argv)
      when '-h', '--help', nil
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
      when 'path'
        config_path(argv)
      when nil
        config_show(argv)
      when '-h', '--help'
        print_config_usage
        SUCCESS
      else
        @stderr.puts "Unknown config command: #{subcommand}"
        print_config_usage(@stderr)
        FAILURE
      end
    end

    def run_tags(argv)
      subcommand = argv.shift

      case subcommand
      when nil
        tags(argv)
      when 'rename'
        tags_rename(argv)
      when 'merge'
        tags_merge(argv)
      when 'remove'
        tags_remove(argv)
      when '-h', '--help'
        reject_arguments!(argv)
        print_tags_usage
        SUCCESS
      else
        @stderr.puts "Unknown tags command: #{subcommand}"
        print_tags_usage(@stderr)
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
        @stdout.puts 'Redirect URI:'
        @stdout.puts redirect_uri
        @stdout.puts
        @stdout.puts 'Open this URL:'
        @stdout.puts oauth.authorization_url(
          client_id: options.fetch(:client_id),
          redirect_uri: redirect_uri
        )
        @stdout.puts "Waiting for OAuth callback on #{redirect_uri}"
        code = oauth.receive_authorization_code(redirect_uri: redirect_uri)
      end
      raise AuthenticationError, 'Authorization code is empty.' if code.to_s.strip.empty?

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
        @stdout.puts 'Not authenticated. Run `raindrop auth login`.'
        FAILURE
      elsif @config.auth_type != 'oauth'
        @stdout.puts 'Test token authentication is not supported. Run `raindrop auth login`.'
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
        @stdout.puts 'Auth: not configured'
      elsif type != 'oauth'
        @stdout.puts 'Auth: unsupported'
        @stdout.puts "Type: #{type}"
        @stdout.puts 'Run `raindrop auth login`.'
      else
        @stdout.puts "Auth: #{type}"
        @stdout.puts 'Access token: [REDACTED]'
        @stdout.puts "Refresh token: #{@config.refresh_token? ? '[REDACTED]' : 'not stored'}"
        @stdout.puts "Token type: #{@config.token_type.empty? ? 'unknown' : @config.token_type}"
        @stdout.puts "Expires in: #{@config.expires_in || 'unknown'}"
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
      item = payload.fetch('item', {})

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
      raise SearchError, 'Search query is required.' if query.empty? && search_query_required?(options)

      if options.fetch(:all)
        search_all(
          authenticated_client,
          query,
          collection_id: search_collection_id(options),
          sort: options.fetch(:sort),
          json: options.fetch(:json)
        )
      else
        payload = authenticated_client.search_raindrops(
          query,
          collection_id: search_collection_id(options),
          perpage: options.fetch(:limit),
          sort: options.fetch(:sort)
        )
        print_search_items(payload.fetch('items', []), json: options.fetch(:json), total: payload['count'])
      end

      SUCCESS
    end

    def get(argv)
      options = parse_get_options(argv)
      id = parse_raindrop_id(argv.shift)
      reject_arguments!(argv)

      payload = authenticated_client.get_raindrop(id)
      item = payload.fetch('item', {})

      if options.fetch(:json)
        print_json_item(item)
      else
        print_raindrop_detail(item)
      end

      SUCCESS
    end

    def update(argv)
      options = parse_update_options(argv)
      id = parse_raindrop_id(argv.shift)
      reject_arguments!(argv)

      payload = authenticated_client.update_raindrop(
        id,
        title: options.fetch(:title),
        excerpt: options.fetch(:description),
        note: options.fetch(:note),
        tags: update_tags(options),
        collection_id: options.fetch(:collection_id)
      )
      item = payload.fetch('item', {})

      if options.fetch(:json)
        print_json_item(item)
      else
        print_update_result(id, options)
        print_raindrop_detail(item) unless item.empty?
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
      items = payload.fetch('items', [])

      if items.empty?
        @stdout.puts 'No tags found.'
      else
        print_tags(items)
      end

      SUCCESS
    end

    def tags_rename(argv)
      options = parse_tags_rename_options(argv)
      old_name = parse_tag_name(argv.shift, 'OLD')
      new_name = parse_tag_name(argv.shift, 'NEW')
      reject_arguments!(argv)
      raise OptionParser::InvalidArgument, 'Tag names must be different.' if old_name == new_name

      payload = authenticated_client.rename_tag(
        old_name,
        replacement: new_name,
        collection_id: options.fetch(:collection_id) || 0
      )

      if options.fetch(:json)
        print_json_item(payload)
      else
        @stdout.puts "Renamed tag: #{old_name} -> #{new_name}"
      end

      SUCCESS
    end

    def tags_merge(argv)
      options = parse_tags_merge_options(argv)
      replacement = parse_tag_name(options.fetch(:replacement), '--into')
      tags = argv.map { |tag| parse_tag_name(tag, 'TAG') }.uniq
      tags.delete(replacement)
      raise OptionParser::InvalidArgument, 'Merge requires at least two source tags.' if tags.size < 2

      payload = authenticated_client.merge_tags(
        tags,
        replacement: replacement,
        collection_id: options.fetch(:collection_id) || 0
      )

      if options.fetch(:json)
        print_json_item(payload)
      else
        @stdout.puts "Merged tags into #{replacement}: #{tags.join(', ')}"
      end

      SUCCESS
    end

    def tags_remove(argv)
      options = parse_tags_remove_options(argv)
      raise OptionParser::MissingArgument, 'TAG' if argv.empty?

      tags = argv.map { |tag| parse_tag_name(tag, 'TAG') }.uniq
      payload = authenticated_client.remove_tags(
        tags,
        collection_id: options.fetch(:collection_id) || 0
      )

      if options.fetch(:json)
        print_json_item(payload)
      else
        @stdout.puts "Removed tags: #{tags.join(', ')}"
      end

      SUCCESS
    end

    def collections(argv)
      reject_arguments!(argv)

      items = authenticated_client.root_collections.fetch('items', []) +
              authenticated_client.child_collections.fetch('items', [])
      items = unique_items_by_id(items)

      if items.empty?
        @stdout.puts 'No collections found.'
      else
        print_collections(items)
      end

      SUCCESS
    end

    def authenticated_client
      @authenticated_client ||= begin
        token = @config.access_token
        raise AuthenticationError, 'Not authenticated. Run `raindrop auth login`.' if token.empty?
        unless @config.auth_type == 'oauth'
          raise AuthenticationError,
                'Test token authentication is not supported. Run `raindrop auth login`.'
        end

        Client.new(token: token)
      end
    end

    def parse_auth_login_options(argv)
      options = { client_id: nil, client_secret: nil, redirect_uri: nil, code: nil }
      parser = OptionParser.new do |opts|
        opts.on('--client-id ID') do |client_id|
          options[:client_id] = client_id
        end

        opts.on('--client-secret SECRET') do |client_secret|
          options[:client_secret] = client_secret
        end

        opts.on('--redirect-uri URI') do |redirect_uri|
          options[:redirect_uri] = redirect_uri
        end

        opts.on('--code CODE') do |code|
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
        opts.on('--json') do
          options[:json] = true
        end

        opts.on('--title TITLE') do |title|
          options[:title] = title
        end

        opts.on('--description DESCRIPTION') do |description|
          options[:description] = description
        end

        opts.on('--note NOTE') do |note|
          options[:note] = note
        end

        opts.on('--tag TAG') do |tag|
          options[:tags] << tag
        end

        opts.on('--collection ID', Integer) do |collection_id|
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
        opts.on('--json') do
          options[:json] = true
        end
      end
      parser.parse!(argv)
      options
    end

    def parse_update_options(argv)
      options = { json: false, title: nil, description: nil, note: nil, tags: [], collection_id: nil }
      parser = OptionParser.new do |opts|
        opts.on('--json') do
          options[:json] = true
        end

        opts.on('--title TITLE') do |title|
          options[:title] = title
        end

        opts.on('--description DESCRIPTION') do |description|
          options[:description] = description
        end

        opts.on('--note NOTE') do |note|
          options[:note] = note
        end

        opts.on('--tag TAG') do |tag|
          options[:tags] << tag
        end

        opts.on('--collection ID', Integer) do |collection_id|
          options[:collection_id] = collection_id
        end
      end
      parser.parse!(argv)
      validate_update_options!(options)
      options
    end

    def parse_delete_options(argv)
      options = { json: false }
      parser = OptionParser.new do |opts|
        opts.on('--json') do
          options[:json] = true
        end
      end
      parser.parse!(argv)
      options
    end

    def parse_tags_rename_options(argv)
      parse_tag_action_options(argv)
    end

    def parse_tags_merge_options(argv)
      parse_tag_action_options(argv, replacement: nil) do |parser, options|
        parser.on('--into TAG') do |replacement|
          options[:replacement] = replacement
        end
      end
    end

    def parse_tags_remove_options(argv)
      parse_tag_action_options(argv)
    end

    def parse_tag_action_options(argv, **additional_options)
      options = { json: false, collection_id: nil }.merge(additional_options)
      parser = OptionParser.new do |option_parser|
        option_parser.on('--json') do
          options[:json] = true
        end

        option_parser.on('--collection ID', Integer) do |collection_id|
          options[:collection_id] = collection_id
        end

        yield option_parser, options if block_given?
      end
      parser.parse!(argv)
      validate_tag_collection_id!(options.fetch(:collection_id))
      options
    end

    def parse_raindrop_id(value)
      raise OptionParser::MissingArgument, 'ID' if value.to_s.strip.empty?

      id = Integer(value, exception: false)
      raise OptionParser::InvalidArgument, value if id.nil? || id <= 0

      id
    end

    def parse_url(value)
      raise OptionParser::MissingArgument, 'URL' if value.to_s.strip.empty?

      uri = URI.parse(value)
      return value if uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?

      raise OptionParser::InvalidArgument, value
    rescue URI::InvalidURIError
      raise OptionParser::InvalidArgument, value
    end

    def parse_tag_name(value, argument_name)
      raise OptionParser::MissingArgument, argument_name if value.nil?

      tag = value.strip
      raise OptionParser::InvalidArgument, argument_name if tag.empty?

      tag
    end

    def validate_tag_collection_id!(collection_id)
      return if collection_id.nil? || collection_id.positive?

      raise OptionParser::InvalidArgument, 'collection'
    end

    def validate_add_options!(options)
      validate_optional_text!('title', options.fetch(:title))
      validate_optional_text!('description', options.fetch(:description))
      validate_optional_text!('note', options.fetch(:note))
      raise OptionParser::InvalidArgument, 'tag' unless options.fetch(:tags).all? { |tag| !tag.to_s.strip.empty? }
    end

    def validate_update_options!(options)
      validate_optional_text!('title', options.fetch(:title))
      validate_optional_text!('description', options.fetch(:description))
      validate_optional_text!('note', options.fetch(:note))
      raise OptionParser::InvalidArgument, 'tag' unless options.fetch(:tags).all? { |tag| !tag.to_s.strip.empty? }

      return if update_requested?(options)

      raise OptionParser::MissingArgument, 'update option'
    end

    def update_requested?(options)
      !options.fetch(:title).nil? ||
        !options.fetch(:description).nil? ||
        !options.fetch(:note).nil? ||
        !options.fetch(:tags).empty? ||
        !options.fetch(:collection_id).nil?
    end

    def update_tags(options)
      tags = options.fetch(:tags)
      return nil if tags.empty?

      tags
    end

    def validate_optional_text!(name, value)
      return if value.nil? || !value.to_s.strip.empty?

      raise OptionParser::InvalidArgument, name
    end

    def validate_auth_login_options!(options)
      %i[client_id client_secret].each do |name|
        validate_required_text!(name.to_s.tr('_', '-'), options.fetch(name))
      end
      parse_url(options.fetch(:redirect_uri)) unless options.fetch(:redirect_uri).nil?
    end

    def validate_required_text!(name, value)
      raise OptionParser::MissingArgument, name if value.nil?
      raise OptionParser::InvalidArgument, name if value.to_s.strip.empty?
    end

    def parse_search_options(argv)
      options = { limit: DEFAULT_SEARCH_LIMIT, all: false, collection_id: nil, json: false, tags: [], sort: nil }
      limit_option_used = false
      parser = OptionParser.new do |opts|
        opts.on('--all') do
          options[:all] = true
        end

        opts.on('--json') do
          options[:json] = true
        end

        opts.on('--collection ID', Integer) do |collection_id|
          options[:collection_id] = collection_id
        end

        opts.on('--limit LIMIT', Integer) do |limit|
          options[:limit] = limit
          limit_option_used = true
        end

        opts.on('--tag TAG') do |tag|
          options[:tags] << tag
        end

        opts.on('--sort SORT') do |sort|
          options[:sort] = sort
        end
      end
      parser.parse!(argv)
      validate_search_options!(options, limit_option_used, argv)
      options
    end

    def build_search_query(argv, options)
      query = argv.join(' ').strip
      tag_query = options.fetch(:tags).map { |tag| format_tag_query(tag) }.join(' ')
      [query, tag_query].reject(&:empty?).join(' ')
    end

    def validate_search_options!(options, limit_option_used, argv)
      validate_limit!(options.fetch(:limit))
      validate_tags!(options.fetch(:tags))
      validate_search_sort!(options.fetch(:sort), argv)

      return unless options.fetch(:all) && limit_option_used

      raise SearchError, '`--all` cannot be used with `--limit`.'
    end

    def validate_search_sort!(sort, argv)
      return if sort.nil?

      raise SearchError, "Search sort must be one of: #{SEARCH_SORTS.join(', ')}." unless SEARCH_SORTS.include?(sort)

      return unless sort == 'score'

      query = argv.join(' ').strip
      return unless query.empty?

      raise SearchError, '`--sort score` requires a search query.'
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

      raise SearchError, 'Search tag must not be empty.'
    end

    def format_tag_query(tag)
      tag = tag.strip
      return %(#"#{tag}") if tag.include?(' ')

      "##{tag}"
    end

    def search_all(client, query, collection_id:, sort:, json:)
      return print_all_search_items_as_json(client, query, collection_id: collection_id, sort: sort) if json

      print_all_search_items(client, query, collection_id: collection_id, sort: sort)
    end

    def print_all_search_items_as_json(client, query, collection_id:, sort:)
      collected_items = []
      each_search_page(client, query, collection_id: collection_id, sort: sort) do |items, _total, _fetched|
        collected_items.concat(items)
      end
      print_json_items(collected_items)
    end

    def print_all_search_items(client, query, collection_id:, sort:)
      printed = false
      each_search_page(client, query, collection_id: collection_id, sort: sort) do |items, total, fetched|
        print_search_items(items, total: total, summary_count: total || fetched, header: !printed)
        printed = true
      end
      print_search_items([], total: nil) unless printed
    end

    def each_search_page(client, query, collection_id:, sort:)
      page = 0
      fetched = 0
      total = nil

      loop do
        payload = client.search_raindrops(query, collection_id: collection_id, perpage: 50, page: page, sort: sort)
        items = payload.fetch('items', [])
        break if items.empty?

        fetched += items.size
        count = payload['count'].to_i
        total = count if count.positive?
        yield items, total, fetched
        break if total && fetched >= total

        page += 1
        sleep 1
      end
    end

    def print_search_items(items, json: false, total: nil, summary_count: nil, header: true)
      return print_json_items(items) if json

      if items.empty?
        @stdout.puts 'No raindrops found.'
      else
        rows = items.map { |item| search_table_row(item) }
        print_table_summary('raindrops', summary_count || rows.size, total) if header
        print_table(rows, SEARCH_TABLE_COLUMNS, header: header, fixed_width: true)
      end
    end

    def print_tags(items)
      rows = items.map do |item|
        {
          name: item['_id'].to_s,
          count: item['count'].to_s
        }
      end
      print_table_summary('tags', rows.size)
      print_table(rows, TAG_TABLE_COLUMNS)
    end

    def print_collections(items)
      rows = items.map do |item|
        {
          id: item['_id'].to_s,
          title: item['title'].to_s,
          count: item['count'].to_s
        }
      end
      print_table_summary('collections', rows.size)
      print_table(rows, COLLECTION_TABLE_COLUMNS)
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

    def print_update_result(id, options)
      @stdout.puts "Updated raindrop: #{id}"
      @stdout.puts "Changed: #{update_change_labels(options).join(', ')}"
      @stdout.puts
    end

    def update_change_labels(options)
      labels = []
      labels << 'title' unless options.fetch(:title).nil?
      labels << 'description' unless options.fetch(:description).nil?
      labels << 'note' unless options.fetch(:note).nil?
      labels << 'tags' unless options.fetch(:tags).empty?
      labels << 'collection' unless options.fetch(:collection_id).nil?
      labels
    end

    def print_raindrop_detail(item)
      id = item['_id'].to_s
      link = item['link'].to_s
      title = item['title'].to_s.strip
      title = link if title.empty?
      tags = Array(item['tags']).map(&:to_s)
      created = item['created'].to_s
      updated = item['lastUpdate'].to_s
      excerpt = item['excerpt'].to_s.strip
      note = item['note'].to_s.strip

      @stdout.puts "ID: #{id}" unless id.empty?
      @stdout.puts "Title: #{title}" unless title.empty?
      @stdout.puts "URL: #{link}" unless link.empty?
      @stdout.puts "Tags: #{tags.join(', ')}" unless tags.empty?
      @stdout.puts "Saved: #{created}" unless created.empty?
      @stdout.puts "Updated: #{updated}" unless updated.empty?

      print_detail_text('Description', excerpt)
      print_detail_text('Note', note)
    end

    def print_detail_text(label, text)
      return if text.empty?

      @stdout.puts "#{label}:"
      @stdout.puts text
    end

    def search_table_row(item)
      link = item['link'].to_s
      title = item['title'].to_s.strip
      title = link if title.empty?
      {
        id: item['_id'].to_s,
        title: title,
        url: link,
        saved_at: relative_time(item['created'])
      }
    end

    def print_table_summary(name, shown, total = nil)
      total = shown if total.nil? || total.to_s.empty?
      @stdout.puts "Showing #{shown} of #{total} #{name}"
      @stdout.puts
    end

    def print_table(rows, columns, header: true, fixed_width: false)
      normalized_rows = normalize_table_rows(rows, columns)
      widths = table_widths(normalized_rows, columns, fixed_width: fixed_width)
      print_table_line(columns.map { |column| column.fetch(:label) }, widths) if header
      normalized_rows.each do |row|
        print_table_line(columns.map { |column| row.fetch(column.fetch(:key)) }, widths)
      end
    end

    def normalize_table_rows(rows, columns)
      rows.map do |row|
        columns.each_with_object({}) do |column, normalized_row|
          key = column.fetch(:key)
          normalized_row[key] = truncate_table_value(row.fetch(key, ''), column.fetch(:max_width))
        end
      end
    end

    def table_widths(rows, columns, fixed_width: false)
      columns.map do |column|
        next [display_width(column.fetch(:label)), column.fetch(:max_width)].max if fixed_width

        key = column.fetch(:key)
        values = rows.map { |row| row.fetch(key) }
        ([column.fetch(:label)] + values).map { |value| display_width(value) }.max
      end
    end

    def print_table_line(values, widths)
      line = values.each_with_index.map do |value, index|
        index == values.size - 1 ? value : ljust_display(value, widths.fetch(index))
      end.join('  ')
      @stdout.puts line.rstrip
    end

    def truncate_table_value(value, max_width)
      value = value.to_s.gsub(/\s+/, ' ').strip
      return value if display_width(value) <= max_width
      return truncate_display(value, max_width) if max_width <= 3

      "#{truncate_display(value, max_width - 3)}..."
    end

    def truncate_display(value, max_width)
      width = 0
      value.grapheme_clusters.each_with_object(+'') do |cluster, truncated|
        cluster_width = display_cluster_width(cluster)
        break truncated if width + cluster_width > max_width

        truncated << cluster
        width += cluster_width
      end
    end

    def ljust_display(value, width)
      value = value.to_s
      value + (' ' * [width - display_width(value), 0].max)
    end

    def display_width(value)
      value.to_s.grapheme_clusters.sum { |cluster| display_cluster_width(cluster) }
    end

    def display_cluster_width(cluster)
      return 2 if emoji_display_cluster?(cluster)

      cluster.each_char.sum { |char| display_char_width(char) }
    end

    def emoji_display_cluster?(cluster)
      cluster.each_char.any? do |char|
        codepoint = char.ord
        emoji_display_codepoint?(codepoint) || codepoint == 0xFE0F
      end
    end

    def display_char_width(char)
      return 0 if char.match?(/[\p{Cf}\p{Mn}]/)

      codepoint = char.ord
      return 2 if wide_display_codepoint?(codepoint)

      1
    end

    def wide_display_codepoint?(codepoint)
      [
        (0x1100..0x115F),   # Hangul Jamo init. consonants.
        (0x2329..0x232A),   # Wide angle brackets.
        (0x2E80..0xA4CF),   # CJK radicals, kana, bopomofo, hangul, and ideographs.
        (0xAC00..0xD7A3),   # Hangul syllables.
        (0xF900..0xFAFF),   # CJK compatibility ideographs.
        (0xFE10..0xFE19),   # Vertical punctuation.
        (0xFE30..0xFE6F),   # CJK compatibility forms and small variants.
        (0xFF00..0xFF60),   # Fullwidth ASCII variants.
        (0xFFE0..0xFFE6),   # Fullwidth symbol variants.
        (0x1F300..0x1FAFF)  # Emoji and pictographs commonly rendered double-width.
      ].any? { |range| range.cover?(codepoint) }
    end

    def emoji_display_codepoint?(codepoint)
      [
        (0x1F1E6..0x1F1FF), # Regional indicator symbols used for flags.
        (0x1F300..0x1FAFF)  # Emoji and pictographs.
      ].any? { |range| range.cover?(codepoint) }
    end

    def relative_time(value, now: Time.now)
      time = Time.parse(value.to_s)
      seconds = (now - time).to_i
      suffix = seconds.negative? ? 'from now' : 'ago'
      seconds = seconds.abs

      amount, unit = relative_time_amount(seconds)
      "about #{amount} #{unit} #{suffix}"
    rescue ArgumentError
      ''
    end

    def relative_time_amount(seconds)
      return [seconds, pluralize_time_unit(seconds, 'second')] if seconds < 60

      minutes = seconds / 60
      return [minutes, pluralize_time_unit(minutes, 'minute')] if minutes < 60

      hours = minutes / 60
      return [hours, pluralize_time_unit(hours, 'hour')] if hours < 24

      days = hours / 24
      return [days, pluralize_time_unit(days, 'day')] if days < 30

      months = days / 30
      return [months, pluralize_time_unit(months, 'month')] if months < 12

      years = days / 365
      [years, pluralize_time_unit(years, 'year')]
    end

    def pluralize_time_unit(amount, unit)
      amount == 1 ? unit : "#{unit}s"
    end

    def unique_items_by_id(items)
      items.each_with_object({}) do |item, indexed_items|
        id = item['_id']
        next if id.nil?

        indexed_items[id] ||= item
      end.values
    end

    def reject_arguments!(argv)
      raise OptionParser::InvalidArgument, argv.join(' ') unless argv.empty?
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
          update  Update a saved raindrop
          tags    List and manage tags
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

    def print_tags_usage(io = @stdout)
      io.puts <<~USAGE
        Usage: raindrop tags [command]

        Commands:
          rename OLD NEW [--collection ID] [--json]
                  Rename a tag
          merge TAG... --into NEW [--collection ID] [--json]
                  Merge tags
          remove TAG... [--collection ID] [--json]
                  Remove tags
      USAGE
    end
  end
end
