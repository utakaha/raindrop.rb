# frozen_string_literal: true

require_relative 'test_helper'

class FakeConfig
  attr_reader :deleted, :path, :expires_in

  def initialize(token: nil, path: '/tmp/raindrop-cli/config.yml', auth_type: 'oauth', refresh_token: nil,
                 token_type: '', expires_in: nil)
    @token = token
    @path = path
    @auth_type = auth_type
    @refresh_token = refresh_token
    @token_type = token_type
    @expires_in = expires_in
    @deleted = false
  end

  def access_token
    @token.to_s
  end

  def auth_type
    @auth_type.to_s
  end

  def refresh_token?
    !@refresh_token.to_s.empty?
  end

  def token_type
    @token_type.to_s
  end

  def delete_access_token
    existed = !@token.nil?
    @token = nil
    @deleted = true
    existed
  end
end

class FakeTagClient
  attr_reader :merge_calls, :rename_calls

  def initialize
    @merge_calls = []
    @rename_calls = []
  end

  def tags
    {
      'items' => [
        { '_id' => 'example', 'count' => 12 }
      ]
    }
  end

  def rename_tag(tag, replacement:, collection_id: 0)
    @rename_calls << {
      tag: tag,
      replacement: replacement,
      collection_id: collection_id
    }
    { 'result' => true }
  end

  def merge_tags(tags, replacement:, collection_id: 0)
    @merge_calls << {
      tags: tags,
      replacement: replacement,
      collection_id: collection_id
    }
    { 'result' => true }
  end
end

class RaindropTest < Minitest::Test
  def run_cli(argv, stdin: '', config: FakeConfig.new)
    stdout = StringIO.new
    stderr = StringIO.new
    input = StringIO.new(stdin)

    code = Raindrop::CLI.new(
      argv,
      stdin: input,
      stdout: stdout,
      stderr: stderr,
      config: config
    ).run

    [code, stdout.string, stderr.string, config]
  end

  def run_cli_with_client(argv, client)
    stdout = StringIO.new
    stderr = StringIO.new
    cli = Raindrop::CLI.new(argv, stdout: stdout, stderr: stderr)
    cli.define_singleton_method(:authenticated_client) { client }

    code = cli.run

    [code, stdout.string, stderr.string]
  end

  def test_auth_token_is_not_supported
    code, stdout, stderr, = run_cli(['auth', 'token'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Test token authentication is not supported.'
  end

  def test_run_handles_interrupt_without_backtrace
    config = FakeConfig.new(token: 'stored-token')
    stdout = StringIO.new
    stderr = StringIO.new
    cli = Raindrop::CLI.new(['search', 'example', '--all'], stdout: stdout, stderr: stderr, config: config)
    cli.define_singleton_method(:authenticated_client) { raise Interrupt }

    code = cli.run

    assert_equal 130, code
    assert_empty stdout.string
    assert_equal "\n", stderr.string
  end

  def test_auth_status_uses_config
    code, stdout, stderr, = run_cli(
      ['auth', 'status'],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 0, code
    assert_includes stdout, 'Authenticated by /tmp/raindrop-cli/config.yml'
    assert_empty stderr
  end

  def test_auth_status_returns_failure_when_token_is_missing
    code, stdout, stderr, = run_cli(['auth', 'status'])

    assert_equal 1, code
    assert_includes stdout, 'Not authenticated.'
    assert_empty stderr
  end

  def test_auth_status_rejects_test_token
    code, stdout, stderr, = run_cli(
      ['auth', 'status'],
      config: FakeConfig.new(token: 'stored-token', auth_type: 'test_token')
    )

    assert_equal 1, code
    assert_includes stdout, 'Test token authentication is not supported.'
    assert_empty stderr
  end

  def test_auth_logout_deletes_stored_token
    store = FakeConfig.new(token: 'stored-token')
    code, stdout, stderr, = run_cli(['auth', 'logout'], config: store)

    assert_equal 0, code
    assert store.deleted
    assert_includes stdout, 'Token removed from /tmp/raindrop-cli/config.yml'
    assert_empty stderr
  end

  def test_auth_login_parses_options
    cli = Raindrop::CLI.new([])
    argv = [
      '--client-id', 'client-id',
      '--client-secret', 'client-secret',
      '--code', 'auth-code'
    ]

    options = cli.send(:parse_auth_login_options, argv)

    assert_equal 'client-id', options.fetch(:client_id)
    assert_equal 'client-secret', options.fetch(:client_secret)
    assert_nil options.fetch(:redirect_uri)
    assert_equal 'auth-code', options.fetch(:code)
    assert_empty argv
  end

  def test_auth_login_requires_client_id
    code, stdout, stderr, = run_cli([
                                      'auth', 'login',
                                      '--client-secret', 'client-secret',
                                      '--code', 'auth-code'
                                    ])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'missing argument: client-id'
  end

  def test_auth_login_rejects_invalid_redirect_uri
    code, stdout, stderr, = run_cli([
                                      'auth', 'login',
                                      '--client-id', 'client-id',
                                      '--client-secret', 'client-secret',
                                      '--redirect-uri', 'not-a-url',
                                      '--code', 'auth-code'
                                    ])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: not-a-url'
  end

  def test_config_path_prints_config_path
    code, stdout, stderr, = run_cli(['config', 'path'])

    assert_equal 0, code
    assert_equal "/tmp/raindrop-cli/config.yml\n", stdout
    assert_empty stderr
  end

  def test_config_prints_not_configured
    code, stdout, stderr, = run_cli(['config'])

    assert_equal 0, code
    assert_equal "Auth: not configured\n", stdout
    assert_empty stderr
  end

  def test_config_prints_masked_token
    code, stdout, stderr, = run_cli(
      ['config'],
      config: FakeConfig.new(
        token: 'secret-token',
        refresh_token: 'refresh-token',
        token_type: 'Bearer',
        expires_in: 3600
      )
    )

    assert_equal 0, code
    assert_equal <<~OUTPUT, stdout
      Auth: oauth
      Access token: [REDACTED]
      Refresh token: [REDACTED]
      Token type: Bearer
      Expires in: 3600
    OUTPUT
    assert_empty stderr
    refute_includes stdout, 'secret-token'
    refute_includes stdout, 'refresh-token'
  end

  def test_config_prints_unsupported_auth_type
    code, stdout, stderr, = run_cli(
      ['config'],
      config: FakeConfig.new(token: 'secret-token', auth_type: 'test_token')
    )

    assert_equal 0, code
    assert_equal <<~OUTPUT, stdout
      Auth: unsupported
      Type: test_token
      Run `raindrop auth login`.
    OUTPUT
    assert_empty stderr
    refute_includes stdout, 'secret-token'
  end

  def test_config_rejects_unknown_command
    code, stdout, stderr, = run_cli(['config', 'unknown'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Unknown config command: unknown'
    assert_includes stderr, 'Usage: raindrop config [command]'
  end

  def test_config_path_rejects_arguments
    code, stdout, stderr, = run_cli(['config', 'path', 'extra'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: extra'
  end

  def test_add_requires_url
    code, stdout, stderr, = run_cli(['add'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'missing argument: URL'
  end

  def test_add_requires_authentication
    code, stdout, stderr, = run_cli(['add', 'https://example.com/article'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Not authenticated. Run `raindrop auth login`.'
  end

  def test_add_rejects_invalid_url
    code, stdout, stderr, = run_cli(['add', 'not-a-url'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: not-a-url'
  end

  def test_add_rejects_non_http_url
    code, stdout, stderr, = run_cli(['add', 'file:///tmp/example.html'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: file:///tmp/example.html'
  end

  def test_add_rejects_extra_arguments
    code, stdout, stderr, = run_cli(
      ['add', 'https://example.com/article', 'extra'],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: extra'
  end

  def test_add_parses_json_option
    cli = Raindrop::CLI.new([])
    argv = ['--json', 'https://example.com/article']

    options = cli.send(:parse_add_options, argv)

    assert options.fetch(:json)
    assert_equal ['https://example.com/article'], argv
  end

  def test_add_parses_optional_fields
    cli = Raindrop::CLI.new([])
    argv = [
      '--title', 'Example Article',
      '--description', 'Example article description',
      '--note', 'Read later',
      '--tag', 'example',
      '--tag', 'reference',
      '--collection', '12345678',
      'https://example.com/article'
    ]

    options = cli.send(:parse_add_options, argv)

    assert_equal 'Example Article', options.fetch(:title)
    assert_equal 'Example article description', options.fetch(:description)
    assert_equal 'Read later', options.fetch(:note)
    assert_equal ['example', 'reference'], options.fetch(:tags)
    assert_equal 12_345_678, options.fetch(:collection_id)
    assert_equal ['https://example.com/article'], argv
  end

  def test_add_rejects_empty_title
    code, stdout, stderr, = run_cli(
      ['add', '--title', '', 'https://example.com/article'],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: title'
  end

  def test_add_rejects_empty_tag
    code, stdout, stderr, = run_cli(
      ['add', '--tag', '', 'https://example.com/article'],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: tag'
  end

  def test_search_requires_query
    code, stdout, stderr, = run_cli(['search'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Search query is required.'
  end

  def test_search_requires_authentication
    code, stdout, stderr, = run_cli(['search', 'example'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Not authenticated. Run `raindrop auth login`.'
  end

  def test_search_rejects_limit_less_than_one
    code, stdout, stderr, = run_cli(['search', 'example', '--limit', '0'],
                                    config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Search limit must be between 1 and 50.'
  end

  def test_search_rejects_limit_greater_than_fifty
    code, stdout, stderr, = run_cli(['search', 'example', '--limit', '51'],
                                    config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Search limit must be between 1 and 50.'
  end

  def test_search_rejects_all_with_limit
    code, stdout, stderr, = run_cli(
      ['search', 'example', '--all', '--limit', '20'],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, '`--all` cannot be used with `--limit`.'
  end

  def test_search_rejects_all_with_explicit_default_limit
    code, stdout, stderr, = run_cli(
      ['search', 'example', '--all', '--limit', '50'],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, '`--all` cannot be used with `--limit`.'
  end

  def test_search_parses_collection_option
    cli = Raindrop::CLI.new([])
    argv = ['example', '--collection', '123']

    options = cli.send(:parse_search_options, argv)

    assert_equal 123, options.fetch(:collection_id)
    assert_equal ['example'], argv
  end

  def test_search_accepts_system_collection_ids
    cli = Raindrop::CLI.new([])
    argv = ['example', '--collection', '-1']

    options = cli.send(:parse_search_options, argv)

    assert_equal(-1, options.fetch(:collection_id))
  end

  def test_search_parses_json_option
    cli = Raindrop::CLI.new([])
    argv = ['example', '--json']

    options = cli.send(:parse_search_options, argv)

    assert options.fetch(:json)
    assert_equal ['example'], argv
  end

  def test_search_parses_sort_option
    cli = Raindrop::CLI.new([])
    argv = ['example', '--sort', '-created']

    options = cli.send(:parse_search_options, argv)

    assert_equal '-created', options.fetch(:sort)
    assert_equal ['example'], argv
  end

  def test_search_accepts_documented_sort_options
    cli = Raindrop::CLI.new([])

    Raindrop::CLI::SEARCH_SORTS.each do |sort|
      argv = sort == 'score' ? ['example', '--sort', sort] : ['--collection', '123', '--sort', sort]

      options = cli.send(:parse_search_options, argv)

      assert_equal sort, options.fetch(:sort)
    end
  end

  def test_search_rejects_unknown_sort
    code, stdout, stderr, = run_cli(
      ['search', 'example', '--sort', 'unknown'],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Search sort must be one of:'
  end

  def test_search_rejects_score_sort_without_query
    code, stdout, stderr, = run_cli(
      ['search', '--collection', '123', '--sort', 'score'],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, '`--sort score` requires a search query.'
  end

  def test_search_query_is_not_required_with_collection_option
    cli = Raindrop::CLI.new([])
    argv = ['--collection', '123']

    options = cli.send(:parse_search_options, argv)

    refute cli.send(:search_query_required?, options)
    assert_empty argv
  end

  def test_search_uses_default_collection_without_collection_option
    cli = Raindrop::CLI.new([])
    argv = ['example']

    options = cli.send(:parse_search_options, argv)

    assert cli.send(:search_query_required?, options)
    assert_equal 0, cli.send(:search_collection_id, options)
  end

  def test_search_builds_query_with_tag
    cli = Raindrop::CLI.new([])
    argv = ['example']
    options = { tags: ['reference'] }

    assert_equal 'example #reference', cli.send(:build_search_query, argv, options)
  end

  def test_search_builds_query_with_tag_only
    cli = Raindrop::CLI.new([])
    argv = []
    options = { tags: ['reference'] }

    assert_equal '#reference', cli.send(:build_search_query, argv, options)
  end

  def test_search_accepts_multiple_tags
    cli = Raindrop::CLI.new([])
    argv = ['example']
    options = { tags: ['reference', 'tutorial'] }

    assert_equal 'example #reference #tutorial', cli.send(:build_search_query, argv, options)
  end

  def test_search_quotes_multi_word_tag
    cli = Raindrop::CLI.new([])
    argv = ['example']
    options = { tags: ['coffee beans'] }

    assert_equal %(example #"coffee beans"), cli.send(:build_search_query, argv, options)
  end

  def test_search_rejects_empty_tag
    code, stdout, stderr, = run_cli(['search', '--tag', ''], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Search tag must not be empty.'
  end

  def test_search_prints_human_readable_items
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    items = [
      {
        '_id' => 1_234_567_890,
        'title' => 'Example Article',
        'link' => 'https://example.com/article'
      },
      {
        '_id' => 9_876_543_210,
        'title' => 'Example deployment guide with a long title that should be truncated in table output',
        'link' => 'https://example.com/articles/example-deployment-guide'
      }
    ]

    cli.send(:print_search_items, items)

    assert_equal <<~OUTPUT, stdout.string
      Showing 2 of 2 raindrops

      ID          TITLE                                                         URL                                                           SAVED AT
      1234567890  Example Article                                               https://example.com/article
      9876543210  Example deployment guide with a long title that should be...  https://example.com/articles/example-deployment-guide
    OUTPUT
  end

  def test_table_helpers_count_wide_characters
    cli = Raindrop::CLI.new([])

    assert_equal 6, cli.send(:display_width, 'Textあ')
    assert_equal 4, cli.send(:display_width, '“”─②')
    assert_equal 4, cli.send(:display_width, '👨‍💻👩‍💻')
    assert_equal 'Textあ  ', cli.send(:ljust_display, 'Textあ', 8)
    assert_equal 'Text 👨‍💻...', cli.send(:truncate_table_value, 'Text 👨‍💻👩‍💻XX', 10)
    assert_equal '日本...', cli.send(:truncate_table_value, '日本語Text', 7)
  end

  def test_search_prints_json_items
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    items = [
      {
        '_id' => 1_234_567_890,
        'title' => 'Example Article',
        'link' => 'https://example.com/article'
      }
    ]

    cli.send(:print_search_items, items, json: true)

    assert_equal items, JSON.parse(stdout.string)
  end

  def test_search_prints_empty_json_items
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)

    cli.send(:print_search_items, [], json: true)

    assert_equal "[]\n", stdout.string
  end

  def test_search_all_prints_each_page_as_it_is_loaded
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    cli.define_singleton_method(:sleep) { |_seconds| nil }
    client = Object.new
    test_case = self
    client.define_singleton_method(:search_raindrops) do |_query, collection_id:, perpage:, page:, sort:|
      test_case.assert_equal 123, collection_id
      test_case.assert_equal 50, perpage
      test_case.assert_nil sort

      if page == 1
        test_case.assert_includes stdout.string, 'First result'
        test_case.assert_includes stdout.string, 'https://example.com/first'
      end

      items = [
        { '_id' => 1, 'title' => 'First result', 'link' => 'https://example.com/first' },
        { '_id' => 2, 'title' => 'Second result', 'link' => 'https://example.com/second' }
      ]
      { 'count' => 2, 'items' => [items.fetch(page)] }
    end

    cli.send(:search_all, client, 'example', collection_id: 123, sort: nil, json: false)

    assert_equal 1, stdout.string.scan('ID').size
    assert_includes stdout.string, 'Showing 2 of 2 raindrops'
    assert_includes stdout.string, 'First result'
    assert_includes stdout.string, 'Second result'
  end

  def test_get_requires_id
    code, stdout, stderr, = run_cli(['get'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'missing argument: ID'
  end

  def test_get_requires_authentication
    code, stdout, stderr, = run_cli(['get', '1234567890'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Not authenticated. Run `raindrop auth login`.'
  end

  def test_get_rejects_extra_arguments
    code, stdout, stderr, = run_cli(['get', '1234567890', 'extra'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: extra'
  end

  def test_get_rejects_invalid_id
    code, stdout, stderr, = run_cli(['get', 'abc'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: abc'
  end

  def test_get_rejects_non_positive_id
    code, stdout, stderr, = run_cli(['get', '0'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: 0'
  end

  def test_get_parses_json_option
    cli = Raindrop::CLI.new([])
    argv = ['--json', '1234567890']

    options = cli.send(:parse_get_options, argv)

    assert options.fetch(:json)
    assert_equal ['1234567890'], argv
  end

  def test_get_prints_human_readable_item
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    item = {
      '_id' => 1_234_567_890,
      'title' => 'Example Article',
      'link' => 'https://example.com/article',
      'tags' => ['example', 'reference'],
      'created' => '2024-01-02T03:04:05.000Z',
      'lastUpdate' => '2024-01-02T03:04:05.000Z',
      'excerpt' => 'Example documentation gets a fresh look.'
    }

    cli.send(:print_raindrop_detail, item)

    assert_equal <<~OUTPUT, stdout.string
      ID: 1234567890
      Title: Example Article
      URL: https://example.com/article
      Tags: example, reference
      Saved: 2024-01-02T03:04:05.000Z
      Updated: 2024-01-02T03:04:05.000Z
      Description:
      Example documentation gets a fresh look.
    OUTPUT
  end

  def test_get_prints_json_item
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    item = {
      '_id' => 1_234_567_890,
      'title' => 'Example Article',
      'link' => 'https://example.com/article'
    }

    cli.send(:print_json_item, item)

    assert_equal item, JSON.parse(stdout.string)
  end

  def test_update_requires_id
    code, stdout, stderr, = run_cli(['update', '--title', 'Example Article'],
                                    config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'missing argument: ID'
  end

  def test_update_requires_authentication
    code, stdout, stderr, = run_cli(['update', '1234567890', '--title', 'Example Article'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Not authenticated. Run `raindrop auth login`.'
  end

  def test_update_requires_update_option
    code, stdout, stderr, = run_cli(['update', '1234567890'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'missing argument: update option'
  end

  def test_update_rejects_extra_arguments
    code, stdout, stderr, = run_cli(
      ['update', '1234567890', '--title', 'Example Article', 'extra'],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: extra'
  end

  def test_update_rejects_invalid_id
    code, stdout, stderr, = run_cli(['update', 'abc', '--title', 'Example Article'],
                                    config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: abc'
  end

  def test_update_parses_optional_fields
    cli = Raindrop::CLI.new([])
    argv = [
      '--title', 'Example Article',
      '--description', 'Example article description',
      '--note', 'Read later',
      '--tag', 'example',
      '--tag', 'reference',
      '--collection', '12345678',
      '--json',
      '1234567890'
    ]

    options = cli.send(:parse_update_options, argv)

    assert_equal 'Example Article', options.fetch(:title)
    assert_equal 'Example article description', options.fetch(:description)
    assert_equal 'Read later', options.fetch(:note)
    assert_equal ['example', 'reference'], options.fetch(:tags)
    assert_equal 12_345_678, options.fetch(:collection_id)
    assert options.fetch(:json)
    assert_equal ['1234567890'], argv
  end

  def test_update_rejects_empty_title
    code, stdout, stderr, = run_cli(
      ['update', '1234567890', '--title', ''],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: title'
  end

  def test_update_rejects_empty_tag
    code, stdout, stderr, = run_cli(
      ['update', '1234567890', '--tag', ''],
      config: FakeConfig.new(token: 'stored-token')
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: tag'
  end

  def test_update_tags_returns_nil_when_tags_are_not_specified
    cli = Raindrop::CLI.new([])

    assert_nil cli.send(:update_tags, { tags: [] })
  end

  def test_update_prints_human_readable_result
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    options = {
      title: 'Example Article',
      description: nil,
      note: 'Read later',
      tags: ['example'],
      collection_id: nil
    }

    cli.send(:print_update_result, 1_234_567_890, options)

    assert_equal <<~OUTPUT, stdout.string
      Updated raindrop: 1234567890
      Changed: title, note, tags

    OUTPUT
  end

  def test_delete_requires_id
    code, stdout, stderr, = run_cli(['delete'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'missing argument: ID'
  end

  def test_delete_requires_authentication
    code, stdout, stderr, = run_cli(['delete', '1234567890'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Not authenticated. Run `raindrop auth login`.'
  end

  def test_delete_rejects_extra_arguments
    code, stdout, stderr, = run_cli(['delete', '1234567890', 'extra'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: extra'
  end

  def test_delete_rejects_invalid_id
    code, stdout, stderr, = run_cli(['delete', 'abc'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: abc'
  end

  def test_delete_parses_json_option
    cli = Raindrop::CLI.new([])
    argv = ['--json', '1234567890']

    options = cli.send(:parse_delete_options, argv)

    assert options.fetch(:json)
    assert_equal ['1234567890'], argv
  end

  def test_delete_prints_human_readable_result
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)

    cli.send(:print_delete_result, 1_234_567_890, { 'result' => true })

    assert_equal "Deleted raindrop: 1234567890\n", stdout.string
  end

  def test_delete_prints_json_result
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)

    cli.send(:print_delete_result, 1_234_567_890, { 'result' => true }, json: true)

    assert_equal({ 'result' => true }, JSON.parse(stdout.string))
  end

  def test_tags_requires_authentication
    code, stdout, stderr, = run_cli(['tags'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Not authenticated. Run `raindrop auth login`.'
  end

  def test_tags_without_subcommand_still_lists_tags
    code, stdout, stderr = run_cli_with_client(['tags'], FakeTagClient.new)

    assert_equal 0, code
    assert_includes stdout, 'example'
    assert_empty stderr
  end

  def test_tags_rename_calls_client_with_collection
    client = FakeTagClient.new

    code, stdout, stderr = run_cli_with_client(
      ['tags', 'rename', 'old-tag', 'example', '--collection', '12345678'],
      client
    )

    assert_equal 0, code
    assert_equal(
      [
        {
          tag: 'old-tag',
          replacement: 'example',
          collection_id: 12_345_678
        }
      ],
      client.rename_calls
    )
    assert_equal "Renamed tag: old-tag -> example\n", stdout
    assert_empty stderr
  end

  def test_tags_rename_prints_json_result
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'rename', 'old-tag', 'example', '--json'],
      FakeTagClient.new
    )

    assert_equal 0, code
    assert_equal({ 'result' => true }, JSON.parse(stdout))
    assert_empty stderr
  end

  def test_tags_rename_requires_old_and_new_names
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'rename', 'old-tag'],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'missing argument: NEW'
  end

  def test_tags_rename_rejects_empty_name
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'rename', ' ', 'example'],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: OLD'
  end

  def test_tags_rename_rejects_same_name
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'rename', 'example', 'example'],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Tag names must be different.'
  end

  def test_tags_rename_rejects_non_positive_collection
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'rename', 'old-tag', 'example', '--collection', '0'],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: collection'
  end

  def test_tags_merge_calls_client_with_normalized_tags
    client = FakeTagClient.new

    code, stdout, stderr = run_cli_with_client(
      [
        'tags', 'merge', 'old-tag', 'old-tag', 'example', 'legacy-tag',
        '--into', 'example', '--collection', '12345678'
      ],
      client
    )

    assert_equal 0, code
    assert_equal(
      [
        {
          tags: ['old-tag', 'legacy-tag'],
          replacement: 'example',
          collection_id: 12_345_678
        }
      ],
      client.merge_calls
    )
    assert_equal "Merged tags into example: old-tag, legacy-tag\n", stdout
    assert_empty stderr
  end

  def test_tags_merge_prints_json_result
    client = FakeTagClient.new

    code, stdout, stderr = run_cli_with_client(
      ['tags', 'merge', 'old-tag', 'legacy-tag', '--into', 'example', '--json'],
      client
    )

    assert_equal 0, code
    assert_equal({ 'result' => true }, JSON.parse(stdout))
    assert_equal 0, client.merge_calls.first.fetch(:collection_id)
    assert_empty stderr
  end

  def test_tags_merge_requires_replacement
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'merge', 'old-tag', 'legacy-tag'],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'missing argument: --into'
  end

  def test_tags_merge_requires_two_source_tags
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'merge', 'old-tag', '--into', 'example'],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Merge requires at least two source tags.'
  end

  def test_tags_merge_rejects_empty_source_tag
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'merge', 'old-tag', ' ', '--into', 'example'],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: TAG'
  end

  def test_tags_merge_rejects_empty_replacement
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'merge', 'old-tag', 'legacy-tag', '--into', ' '],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: --into'
  end

  def test_tags_merge_rejects_too_few_tags_after_normalization
    code, stdout, stderr = run_cli_with_client(
      ['tags', 'merge', 'old-tag', 'old-tag', 'example', '--into', 'example'],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Merge requires at least two source tags.'
  end

  def test_tags_help_lists_management_subcommands
    code, stdout, stderr = run_cli_with_client(
      ['tags', '--help'],
      FakeTagClient.new
    )

    assert_equal 0, code
    assert_includes stdout, 'rename'
    assert_includes stdout, 'merge'
    assert_empty stderr
  end

  def test_tags_rejects_unknown_subcommand
    code, stdout, stderr, = run_cli(['tags', 'extra'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Unknown tags command: extra'
    assert_includes stderr, 'Usage: raindrop tags [command]'
  end

  def test_tags_prints_human_readable_items
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)

    cli.send(:print_tags, [
               { '_id' => 'example', 'count' => 12 },
               { '_id' => 'long tag name that should be truncated in table output', 'count' => 3 }
             ])

    assert_equal <<~OUTPUT, stdout.string
      Showing 2 of 2 tags

      TAG                                       COUNT
      example                                   12
      long tag name that should be truncate...  3
    OUTPUT
  end

  def test_collections_requires_authentication
    code, stdout, stderr, = run_cli(['collections'])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'Not authenticated. Run `raindrop auth login`.'
  end

  def test_collections_rejects_arguments
    code, stdout, stderr, = run_cli(['collections', 'extra'], config: FakeConfig.new(token: 'stored-token'))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, 'invalid argument: extra'
  end

  def test_collections_prints_human_readable_items
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)

    cli.send(:print_collections, [
               { '_id' => 12_345_678, 'title' => 'Sample Collection', 'count' => 42 },
               { '_id' => 123, 'title' => 'Example Collection', 'count' => 8 }
             ])

    assert_equal <<~OUTPUT, stdout.string
      Showing 2 of 2 collections

      ID        TITLE               COUNT
      12345678  Sample Collection   42
      123       Example Collection  8
    OUTPUT
  end

  def test_collections_deduplicates_items_by_id
    cli = Raindrop::CLI.new([])
    items = [
      { '_id' => 12_345_678, 'title' => 'Example Collection', 'count' => 2 },
      { '_id' => 12_345_678, 'title' => 'Example Collection', 'count' => 2 },
      { '_id' => 123, 'title' => 'Sample Collection', 'count' => 1 }
    ]

    deduplicated_items = cli.send(:unique_items_by_id, items)

    assert_equal([12_345_678, 123], deduplicated_items.map { |item| item.fetch('_id') })
  end
end
