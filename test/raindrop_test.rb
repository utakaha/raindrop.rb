# frozen_string_literal: true

require_relative "test_helper"

class FakeConfig
  attr_reader :deleted

  def initialize(token: nil, path: "/tmp/raindrop-cli/config.yml", auth_type: "oauth", refresh_token: nil, token_type: "", expires_in: nil)
    @token = token
    @path = path
    @auth_type = auth_type
    @refresh_token = refresh_token
    @token_type = token_type
    @expires_in = expires_in
    @deleted = false
  end

  def path
    @path
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

  def expires_in
    @expires_in
  end

  def delete_access_token
    existed = !@token.nil?
    @token = nil
    @deleted = true
    existed
  end
end

class FakeTagClient
  attr_reader :rename_calls

  def initialize
    @rename_calls = []
  end

  def tags
    {
      "items" => [
        { "_id" => "ruby", "count" => 12 }
      ]
    }
  end

  def rename_tag(tag, replacement:, collection_id: 0)
    @rename_calls << {
      tag: tag,
      replacement: replacement,
      collection_id: collection_id
    }
    { "result" => true }
  end
end

class RaindropTest < Minitest::Test
  def run_cli(argv, stdin: "", config: FakeConfig.new)
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
    code, stdout, stderr, = run_cli(["auth", "token"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Test token authentication is not supported."
  end

  def test_run_handles_interrupt_without_backtrace
    config = FakeConfig.new(token: "stored-token")
    stdout = StringIO.new
    stderr = StringIO.new
    cli = Raindrop::CLI.new(["search", "ruby", "--all"], stdout: stdout, stderr: stderr, config: config)
    cli.define_singleton_method(:authenticated_client) { raise Interrupt }

    code = cli.run

    assert_equal 130, code
    assert_empty stdout.string
    assert_equal "\n", stderr.string
  end

  def test_auth_status_uses_config
    code, stdout, stderr, = run_cli(
      ["auth", "status"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 0, code
    assert_includes stdout, "Authenticated by /tmp/raindrop-cli/config.yml"
    assert_empty stderr
  end

  def test_auth_status_returns_failure_when_token_is_missing
    code, stdout, stderr, = run_cli(["auth", "status"])

    assert_equal 1, code
    assert_includes stdout, "Not authenticated."
    assert_empty stderr
  end

  def test_auth_status_rejects_test_token
    code, stdout, stderr, = run_cli(
      ["auth", "status"],
      config: FakeConfig.new(token: "stored-token", auth_type: "test_token")
    )

    assert_equal 1, code
    assert_includes stdout, "Test token authentication is not supported."
    assert_empty stderr
  end

  def test_auth_logout_deletes_stored_token
    store = FakeConfig.new(token: "stored-token")
    code, stdout, stderr, = run_cli(["auth", "logout"], config: store)

    assert_equal 0, code
    assert store.deleted
    assert_includes stdout, "Token removed from /tmp/raindrop-cli/config.yml"
    assert_empty stderr
  end

  def test_auth_login_parses_options
    cli = Raindrop::CLI.new([])
    argv = [
      "--client-id", "client-id",
      "--client-secret", "client-secret",
      "--code", "auth-code"
    ]

    options = cli.send(:parse_auth_login_options, argv)

    assert_equal "client-id", options.fetch(:client_id)
    assert_equal "client-secret", options.fetch(:client_secret)
    assert_nil options.fetch(:redirect_uri)
    assert_equal "auth-code", options.fetch(:code)
    assert_empty argv
  end

  def test_auth_login_requires_client_id
    code, stdout, stderr, = run_cli([
      "auth", "login",
      "--client-secret", "client-secret",
      "--code", "auth-code"
    ])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "missing argument: client-id"
  end

  def test_auth_login_rejects_invalid_redirect_uri
    code, stdout, stderr, = run_cli([
      "auth", "login",
      "--client-id", "client-id",
      "--client-secret", "client-secret",
      "--redirect-uri", "not-a-url",
      "--code", "auth-code"
    ])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: not-a-url"
  end

  def test_config_path_prints_config_path
    code, stdout, stderr, = run_cli(["config", "path"])

    assert_equal 0, code
    assert_equal "/tmp/raindrop-cli/config.yml\n", stdout
    assert_empty stderr
  end

  def test_config_prints_not_configured
    code, stdout, stderr, = run_cli(["config"])

    assert_equal 0, code
    assert_equal "Auth: not configured\n", stdout
    assert_empty stderr
  end

  def test_config_prints_masked_token
    code, stdout, stderr, = run_cli(
      ["config"],
      config: FakeConfig.new(
        token: "secret-token",
        refresh_token: "refresh-token",
        token_type: "Bearer",
        expires_in: 1_209_599
      )
    )

    assert_equal 0, code
    assert_equal <<~OUTPUT, stdout
      Auth: oauth
      Access token: [REDACTED]
      Refresh token: [REDACTED]
      Token type: Bearer
      Expires in: 1209599
    OUTPUT
    assert_empty stderr
    refute_includes stdout, "secret-token"
    refute_includes stdout, "refresh-token"
  end

  def test_config_prints_unsupported_auth_type
    code, stdout, stderr, = run_cli(
      ["config"],
      config: FakeConfig.new(token: "secret-token", auth_type: "test_token")
    )

    assert_equal 0, code
    assert_equal <<~OUTPUT, stdout
      Auth: unsupported
      Type: test_token
      Run `raindrop auth login`.
    OUTPUT
    assert_empty stderr
    refute_includes stdout, "secret-token"
  end

  def test_config_rejects_unknown_command
    code, stdout, stderr, = run_cli(["config", "unknown"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Unknown config command: unknown"
    assert_includes stderr, "Usage: raindrop config [command]"
  end

  def test_config_path_rejects_arguments
    code, stdout, stderr, = run_cli(["config", "path", "extra"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: extra"
  end

  def test_add_requires_url
    code, stdout, stderr, = run_cli(["add"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "missing argument: URL"
  end

  def test_add_requires_authentication
    code, stdout, stderr, = run_cli(["add", "https://example.com/ruby"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth login`."
  end

  def test_add_rejects_invalid_url
    code, stdout, stderr, = run_cli(["add", "not-a-url"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: not-a-url"
  end

  def test_add_rejects_non_http_url
    code, stdout, stderr, = run_cli(["add", "file:///tmp/example.html"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: file:///tmp/example.html"
  end

  def test_add_rejects_extra_arguments
    code, stdout, stderr, = run_cli(
      ["add", "https://example.com/ruby", "extra"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: extra"
  end

  def test_add_parses_json_option
    cli = Raindrop::CLI.new([])
    argv = ["--json", "https://example.com/ruby"]

    options = cli.send(:parse_add_options, argv)

    assert options.fetch(:json)
    assert_equal ["https://example.com/ruby"], argv
  end

  def test_add_parses_optional_fields
    cli = Raindrop::CLI.new([])
    argv = [
      "--title", "Ruby",
      "--description", "Ruby language",
      "--note", "Read later",
      "--tag", "ruby",
      "--tag", "docs",
      "--collection", "55596991",
      "https://example.com/ruby"
    ]

    options = cli.send(:parse_add_options, argv)

    assert_equal "Ruby", options.fetch(:title)
    assert_equal "Ruby language", options.fetch(:description)
    assert_equal "Read later", options.fetch(:note)
    assert_equal ["ruby", "docs"], options.fetch(:tags)
    assert_equal 55_596_991, options.fetch(:collection_id)
    assert_equal ["https://example.com/ruby"], argv
  end

  def test_add_rejects_empty_title
    code, stdout, stderr, = run_cli(
      ["add", "--title", "", "https://example.com/ruby"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: title"
  end

  def test_add_rejects_empty_tag
    code, stdout, stderr, = run_cli(
      ["add", "--tag", "", "https://example.com/ruby"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: tag"
  end

  def test_search_requires_query
    code, stdout, stderr, = run_cli(["search"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Search query is required."
  end

  def test_search_requires_authentication
    code, stdout, stderr, = run_cli(["search", "ruby"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth login`."
  end

  def test_search_rejects_limit_less_than_one
    code, stdout, stderr, = run_cli(["search", "ruby", "--limit", "0"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Search limit must be between 1 and 50."
  end

  def test_search_rejects_limit_greater_than_fifty
    code, stdout, stderr, = run_cli(["search", "ruby", "--limit", "51"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Search limit must be between 1 and 50."
  end

  def test_search_rejects_all_with_limit
    code, stdout, stderr, = run_cli(
      ["search", "ruby", "--all", "--limit", "20"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "`--all` cannot be used with `--limit`."
  end

  def test_search_rejects_all_with_explicit_default_limit
    code, stdout, stderr, = run_cli(
      ["search", "ruby", "--all", "--limit", "50"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "`--all` cannot be used with `--limit`."
  end

  def test_search_parses_collection_option
    cli = Raindrop::CLI.new([])
    argv = ["ruby", "--collection", "123"]

    options = cli.send(:parse_search_options, argv)

    assert_equal 123, options.fetch(:collection_id)
    assert_equal ["ruby"], argv
  end

  def test_search_accepts_system_collection_ids
    cli = Raindrop::CLI.new([])
    argv = ["ruby", "--collection", "-1"]

    options = cli.send(:parse_search_options, argv)

    assert_equal(-1, options.fetch(:collection_id))
  end

  def test_search_parses_json_option
    cli = Raindrop::CLI.new([])
    argv = ["ruby", "--json"]

    options = cli.send(:parse_search_options, argv)

    assert options.fetch(:json)
    assert_equal ["ruby"], argv
  end

  def test_search_parses_sort_option
    cli = Raindrop::CLI.new([])
    argv = ["ruby", "--sort", "-created"]

    options = cli.send(:parse_search_options, argv)

    assert_equal "-created", options.fetch(:sort)
    assert_equal ["ruby"], argv
  end

  def test_search_accepts_documented_sort_options
    cli = Raindrop::CLI.new([])

    Raindrop::CLI::SEARCH_SORTS.each do |sort|
      argv = sort == "score" ? ["ruby", "--sort", sort] : ["--collection", "123", "--sort", sort]

      options = cli.send(:parse_search_options, argv)

      assert_equal sort, options.fetch(:sort)
    end
  end

  def test_search_rejects_unknown_sort
    code, stdout, stderr, = run_cli(
      ["search", "ruby", "--sort", "unknown"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Search sort must be one of:"
  end

  def test_search_rejects_score_sort_without_query
    code, stdout, stderr, = run_cli(
      ["search", "--collection", "123", "--sort", "score"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "`--sort score` requires a search query."
  end

  def test_search_query_is_not_required_with_collection_option
    cli = Raindrop::CLI.new([])
    argv = ["--collection", "123"]

    options = cli.send(:parse_search_options, argv)

    refute cli.send(:search_query_required?, options)
    assert_empty argv
  end

  def test_search_uses_default_collection_without_collection_option
    cli = Raindrop::CLI.new([])
    argv = ["ruby"]

    options = cli.send(:parse_search_options, argv)

    assert cli.send(:search_query_required?, options)
    assert_equal 0, cli.send(:search_collection_id, options)
  end

  def test_search_builds_query_with_tag
    cli = Raindrop::CLI.new([])
    argv = ["ruby"]
    options = { tags: ["docs"] }

    assert_equal "ruby #docs", cli.send(:build_search_query, argv, options)
  end

  def test_search_builds_query_with_tag_only
    cli = Raindrop::CLI.new([])
    argv = []
    options = { tags: ["docs"] }

    assert_equal "#docs", cli.send(:build_search_query, argv, options)
  end

  def test_search_accepts_multiple_tags
    cli = Raindrop::CLI.new([])
    argv = ["ruby"]
    options = { tags: ["docs", "rails"] }

    assert_equal "ruby #docs #rails", cli.send(:build_search_query, argv, options)
  end

  def test_search_quotes_multi_word_tag
    cli = Raindrop::CLI.new([])
    argv = ["ruby"]
    options = { tags: ["coffee beans"] }

    assert_equal %(ruby #"coffee beans"), cli.send(:build_search_query, argv, options)
  end

  def test_search_rejects_empty_tag
    code, stdout, stderr, = run_cli(["search", "--tag", ""], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Search tag must not be empty."
  end

  def test_search_prints_human_readable_items
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    items = [
      {
        "_id" => 1668242775,
        "title" => "Example Ruby Documentation",
        "link" => "https://example.com/ruby-documentation"
      },
      {
        "_id" => 1667301016,
        "title" => "Example deployment guide with a long title that should be truncated in table output",
        "link" => "https://example.com/articles/example-deployment-guide"
      }
    ]

    cli.send(:print_search_items, items)

    assert_equal <<~OUTPUT, stdout.string
      Showing 2 of 2 raindrops

      ID          TITLE                                                         URL                                                           SAVED AT
      1668242775  Example Ruby Documentation                                    https://example.com/ruby-documentation
      1667301016  Example deployment guide with a long title that should be...  https://example.com/articles/example-deployment-guide
    OUTPUT
  end

  def test_table_helpers_count_wide_characters
    cli = Raindrop::CLI.new([])

    assert_equal 6, cli.send(:display_width, "Rubyあ")
    assert_equal 4, cli.send(:display_width, "“”─②")
    assert_equal 4, cli.send(:display_width, "👨‍💻👩‍💻")
    assert_equal "Rubyあ  ", cli.send(:ljust_display, "Rubyあ", 8)
    assert_equal "Ruby 👨‍💻...", cli.send(:truncate_table_value, "Ruby 👨‍💻👩‍💻XX", 10)
    assert_equal "日本...", cli.send(:truncate_table_value, "日本語Ruby", 7)
  end

  def test_search_prints_json_items
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    items = [
      {
        "_id" => 1668242775,
        "title" => "Example Ruby Documentation",
        "link" => "https://example.com/ruby-documentation"
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
    cli.define_singleton_method(:sleep) { |_seconds| }
    client = Object.new
    test_case = self
    client.define_singleton_method(:search_raindrops) do |_query, collection_id:, perpage:, page:, sort:|
      test_case.assert_equal 123, collection_id
      test_case.assert_equal 50, perpage
      test_case.assert_nil sort

      if page == 1
        test_case.assert_includes stdout.string, "First result"
        test_case.assert_includes stdout.string, "https://example.com/first"
      end

      items = [
        { "_id" => 1, "title" => "First result", "link" => "https://example.com/first" },
        { "_id" => 2, "title" => "Second result", "link" => "https://example.com/second" }
      ]
      { "count" => 2, "items" => [items.fetch(page)] }
    end

    cli.send(:search_all, client, "ruby", collection_id: 123, sort: nil, json: false)

    assert_equal 1, stdout.string.scan("ID").size
    assert_includes stdout.string, "Showing 2 of 2 raindrops"
    assert_includes stdout.string, "First result"
    assert_includes stdout.string, "Second result"
  end

  def test_get_requires_id
    code, stdout, stderr, = run_cli(["get"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "missing argument: ID"
  end

  def test_get_requires_authentication
    code, stdout, stderr, = run_cli(["get", "1668242775"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth login`."
  end

  def test_get_rejects_extra_arguments
    code, stdout, stderr, = run_cli(["get", "1668242775", "extra"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: extra"
  end

  def test_get_rejects_invalid_id
    code, stdout, stderr, = run_cli(["get", "abc"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: abc"
  end

  def test_get_rejects_non_positive_id
    code, stdout, stderr, = run_cli(["get", "0"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: 0"
  end

  def test_get_parses_json_option
    cli = Raindrop::CLI.new([])
    argv = ["--json", "1668242775"]

    options = cli.send(:parse_get_options, argv)

    assert options.fetch(:json)
    assert_equal ["1668242775"], argv
  end

  def test_get_prints_human_readable_item
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    item = {
      "_id" => 1668242775,
      "title" => "Example Ruby Documentation",
      "link" => "https://example.com/ruby-documentation",
      "tags" => ["ruby", "docs"],
      "created" => "2026-04-01T12:48:22.646Z",
      "lastUpdate" => "2026-04-01T12:48:22.646Z",
      "excerpt" => "Example documentation gets a fresh look."
    }

    cli.send(:print_raindrop_detail, item)

    assert_equal <<~OUTPUT, stdout.string
      ID: 1668242775
      Title: Example Ruby Documentation
      URL: https://example.com/ruby-documentation
      Tags: ruby, docs
      Saved: 2026-04-01T12:48:22.646Z
      Updated: 2026-04-01T12:48:22.646Z
      Description:
      Example documentation gets a fresh look.
    OUTPUT
  end

  def test_get_prints_json_item
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    item = {
      "_id" => 1668242775,
      "title" => "Example Ruby Documentation",
      "link" => "https://example.com/ruby-documentation"
    }

    cli.send(:print_json_item, item)

    assert_equal item, JSON.parse(stdout.string)
  end

  def test_update_requires_id
    code, stdout, stderr, = run_cli(["update", "--title", "Ruby"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "missing argument: ID"
  end

  def test_update_requires_authentication
    code, stdout, stderr, = run_cli(["update", "1668242775", "--title", "Ruby"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth login`."
  end

  def test_update_requires_update_option
    code, stdout, stderr, = run_cli(["update", "1668242775"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "missing argument: update option"
  end

  def test_update_rejects_extra_arguments
    code, stdout, stderr, = run_cli(
      ["update", "1668242775", "--title", "Ruby", "extra"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: extra"
  end

  def test_update_rejects_invalid_id
    code, stdout, stderr, = run_cli(["update", "abc", "--title", "Ruby"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: abc"
  end

  def test_update_parses_optional_fields
    cli = Raindrop::CLI.new([])
    argv = [
      "--title", "Ruby",
      "--description", "Ruby language",
      "--note", "Read later",
      "--tag", "ruby",
      "--tag", "docs",
      "--collection", "55596991",
      "--json",
      "1668242775"
    ]

    options = cli.send(:parse_update_options, argv)

    assert_equal "Ruby", options.fetch(:title)
    assert_equal "Ruby language", options.fetch(:description)
    assert_equal "Read later", options.fetch(:note)
    assert_equal ["ruby", "docs"], options.fetch(:tags)
    assert_equal 55_596_991, options.fetch(:collection_id)
    assert options.fetch(:json)
    assert_equal ["1668242775"], argv
  end

  def test_update_rejects_empty_title
    code, stdout, stderr, = run_cli(
      ["update", "1668242775", "--title", ""],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: title"
  end

  def test_update_rejects_empty_tag
    code, stdout, stderr, = run_cli(
      ["update", "1668242775", "--tag", ""],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: tag"
  end

  def test_update_tags_returns_nil_when_tags_are_not_specified
    cli = Raindrop::CLI.new([])

    assert_nil cli.send(:update_tags, { tags: [] })
  end

  def test_update_prints_human_readable_result
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)
    options = {
      title: "Ruby",
      description: nil,
      note: "Read later",
      tags: ["ruby"],
      collection_id: nil
    }

    cli.send(:print_update_result, 1_668_242_775, options)

    assert_equal <<~OUTPUT, stdout.string
      Updated raindrop: 1668242775
      Changed: title, note, tags

    OUTPUT
  end

  def test_delete_requires_id
    code, stdout, stderr, = run_cli(["delete"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "missing argument: ID"
  end

  def test_delete_requires_authentication
    code, stdout, stderr, = run_cli(["delete", "1668242775"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth login`."
  end

  def test_delete_rejects_extra_arguments
    code, stdout, stderr, = run_cli(["delete", "1668242775", "extra"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: extra"
  end

  def test_delete_rejects_invalid_id
    code, stdout, stderr, = run_cli(["delete", "abc"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: abc"
  end

  def test_delete_parses_json_option
    cli = Raindrop::CLI.new([])
    argv = ["--json", "1668242775"]

    options = cli.send(:parse_delete_options, argv)

    assert options.fetch(:json)
    assert_equal ["1668242775"], argv
  end

  def test_delete_prints_human_readable_result
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)

    cli.send(:print_delete_result, 1_668_242_775, { "result" => true })

    assert_equal "Deleted raindrop: 1668242775\n", stdout.string
  end

  def test_delete_prints_json_result
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)

    cli.send(:print_delete_result, 1_668_242_775, { "result" => true }, json: true)

    assert_equal({ "result" => true }, JSON.parse(stdout.string))
  end

  def test_tags_requires_authentication
    code, stdout, stderr, = run_cli(["tags"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth login`."
  end

  def test_tags_without_subcommand_still_lists_tags
    code, stdout, stderr = run_cli_with_client(["tags"], FakeTagClient.new)

    assert_equal 0, code
    assert_includes stdout, "ruby"
    assert_empty stderr
  end

  def test_tags_rename_calls_client_with_collection
    client = FakeTagClient.new

    code, stdout, stderr = run_cli_with_client(
      ["tags", "rename", "ruby-lang", "ruby", "--collection", "55596991"],
      client
    )

    assert_equal 0, code
    assert_equal(
      [
        {
          tag: "ruby-lang",
          replacement: "ruby",
          collection_id: 55_596_991
        }
      ],
      client.rename_calls
    )
    assert_equal "Renamed tag: ruby-lang -> ruby\n", stdout
    assert_empty stderr
  end

  def test_tags_rename_prints_json_result
    code, stdout, stderr = run_cli_with_client(
      ["tags", "rename", "ruby-lang", "ruby", "--json"],
      FakeTagClient.new
    )

    assert_equal 0, code
    assert_equal({ "result" => true }, JSON.parse(stdout))
    assert_empty stderr
  end

  def test_tags_rename_requires_old_and_new_names
    code, stdout, stderr = run_cli_with_client(
      ["tags", "rename", "ruby-lang"],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "missing argument: NEW"
  end

  def test_tags_rename_rejects_empty_name
    code, stdout, stderr = run_cli_with_client(
      ["tags", "rename", " ", "ruby"],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: OLD"
  end

  def test_tags_rename_rejects_same_name
    code, stdout, stderr = run_cli_with_client(
      ["tags", "rename", "ruby", "ruby"],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Tag names must be different."
  end

  def test_tags_rename_rejects_non_positive_collection
    code, stdout, stderr = run_cli_with_client(
      ["tags", "rename", "ruby-lang", "ruby", "--collection", "0"],
      FakeTagClient.new
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: collection"
  end

  def test_tags_help_lists_rename_subcommand
    code, stdout, stderr = run_cli_with_client(
      ["tags", "--help"],
      FakeTagClient.new
    )

    assert_equal 0, code
    assert_includes stdout, "rename"
    assert_empty stderr
  end

  def test_tags_rejects_unknown_subcommand
    code, stdout, stderr, = run_cli(["tags", "extra"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Unknown tags command: extra"
    assert_includes stderr, "Usage: raindrop tags [command]"
  end

  def test_tags_prints_human_readable_items
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)

    cli.send(:print_tags, [
      { "_id" => "ruby", "count" => 12 },
      { "_id" => "long tag name that should be truncated in table output", "count" => 3 }
    ])

    assert_equal <<~OUTPUT, stdout.string
      Showing 2 of 2 tags

      TAG                                       COUNT
      ruby                                      12
      long tag name that should be truncate...  3
    OUTPUT
  end

  def test_collections_requires_authentication
    code, stdout, stderr, = run_cli(["collections"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth login`."
  end

  def test_collections_rejects_arguments
    code, stdout, stderr, = run_cli(["collections", "extra"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: extra"
  end

  def test_collections_prints_human_readable_items
    stdout = StringIO.new
    cli = Raindrop::CLI.new([], stdout: stdout)

    cli.send(:print_collections, [
      { "_id" => 55596991, "title" => "Development", "count" => 42 },
      { "_id" => 123, "title" => "Ruby", "count" => 8 }
    ])

    assert_equal <<~OUTPUT, stdout.string
      Showing 2 of 2 collections

      ID        TITLE        COUNT
      55596991  Development  42
      123       Ruby         8
    OUTPUT
  end

  def test_collections_deduplicates_items_by_id
    cli = Raindrop::CLI.new([])
    items = [
      { "_id" => 55596991, "title" => "Pocket", "count" => 2368 },
      { "_id" => 55596991, "title" => "Pocket", "count" => 2368 },
      { "_id" => 123, "title" => "Ruby", "count" => 8 }
    ]

    deduplicated_items = cli.send(:unique_items_by_id, items)

    assert_equal [55596991, 123], deduplicated_items.map { |item| item.fetch("_id") }
  end
end
