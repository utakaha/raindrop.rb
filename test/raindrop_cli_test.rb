# frozen_string_literal: true

require_relative "test_helper"

class FakeConfig
  attr_reader :written_token, :deleted

  def initialize(token: nil, path: "/tmp/raindrop-cli/config.yml", auth_type: "test_token")
    @token = token
    @path = path
    @auth_type = auth_type
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

  def save_access_token(token)
    @written_token = token
    @token = token
    @auth_type = "test_token"
    true
  end

  def delete_access_token
    existed = !@token.nil?
    @token = nil
    @deleted = true
    existed
  end
end

class RaindropCliTest < Minitest::Test
  def run_cli(argv, stdin: "", config: FakeConfig.new)
    stdout = StringIO.new
    stderr = StringIO.new
    input = StringIO.new(stdin)

    code = RaindropCli::CLI.new(
      argv,
      stdin: input,
      stdout: stdout,
      stderr: stderr,
      config: config
    ).run

    [code, stdout.string, stderr.string, config]
  end

  def test_auth_token_saves_token_from_stdin
    code, stdout, stderr, store = run_cli(["auth", "token"], stdin: "secret-token\n")

    assert_equal 0, code
    assert_equal "secret-token", store.written_token
    assert_includes stdout, "Token saved to /tmp/raindrop-cli/config.yml"
    assert_empty stderr
  end

  def test_auth_token_rejects_empty_token
    code, stdout, stderr, = run_cli(["auth", "token"], stdin: "\n")

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Token is empty."
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

  def test_auth_logout_deletes_stored_token
    store = FakeConfig.new(token: "stored-token")
    code, stdout, stderr, = run_cli(["auth", "logout"], config: store)

    assert_equal 0, code
    assert store.deleted
    assert_includes stdout, "Token removed from /tmp/raindrop-cli/config.yml"
    assert_empty stderr
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
    code, stdout, stderr, = run_cli(["config"], config: FakeConfig.new(token: "secret-token"))

    assert_equal 0, code
    assert_equal <<~OUTPUT, stdout
      Auth: test_token
      Access token: [REDACTED]
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
    code, stdout, stderr, = run_cli(["add", "https://www.ruby-lang.org/"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth token`."
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
      ["add", "https://www.ruby-lang.org/", "extra"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: extra"
  end

  def test_add_parses_json_option
    cli = RaindropCli::CLI.new([])
    argv = ["--json", "https://www.ruby-lang.org/"]

    options = cli.send(:parse_add_options, argv)

    assert options.fetch(:json)
    assert_equal ["https://www.ruby-lang.org/"], argv
  end

  def test_add_parses_optional_fields
    cli = RaindropCli::CLI.new([])
    argv = [
      "--title", "Ruby",
      "--description", "Ruby language",
      "--note", "Read later",
      "--tag", "ruby",
      "--tag", "docs",
      "--collection", "55596991",
      "https://www.ruby-lang.org/"
    ]

    options = cli.send(:parse_add_options, argv)

    assert_equal "Ruby", options.fetch(:title)
    assert_equal "Ruby language", options.fetch(:description)
    assert_equal "Read later", options.fetch(:note)
    assert_equal ["ruby", "docs"], options.fetch(:tags)
    assert_equal 55_596_991, options.fetch(:collection_id)
    assert_equal ["https://www.ruby-lang.org/"], argv
  end

  def test_add_rejects_empty_title
    code, stdout, stderr, = run_cli(
      ["add", "--title", "", "https://www.ruby-lang.org/"],
      config: FakeConfig.new(token: "stored-token")
    )

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: title"
  end

  def test_add_rejects_empty_tag
    code, stdout, stderr, = run_cli(
      ["add", "--tag", "", "https://www.ruby-lang.org/"],
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
    assert_includes stderr, "Not authenticated. Run `raindrop auth token`."
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
    cli = RaindropCli::CLI.new([])
    argv = ["ruby", "--collection", "123"]

    options = cli.send(:parse_search_options, argv)

    assert_equal 123, options.fetch(:collection_id)
    assert_equal ["ruby"], argv
  end

  def test_search_accepts_system_collection_ids
    cli = RaindropCli::CLI.new([])
    argv = ["ruby", "--collection", "-1"]

    options = cli.send(:parse_search_options, argv)

    assert_equal(-1, options.fetch(:collection_id))
  end

  def test_search_parses_json_option
    cli = RaindropCli::CLI.new([])
    argv = ["ruby", "--json"]

    options = cli.send(:parse_search_options, argv)

    assert options.fetch(:json)
    assert_equal ["ruby"], argv
  end

  def test_search_query_is_not_required_with_collection_option
    cli = RaindropCli::CLI.new([])
    argv = ["--collection", "123"]

    options = cli.send(:parse_search_options, argv)

    refute cli.send(:search_query_required?, options)
    assert_empty argv
  end

  def test_search_uses_default_collection_without_collection_option
    cli = RaindropCli::CLI.new([])
    argv = ["ruby"]

    options = cli.send(:parse_search_options, argv)

    assert cli.send(:search_query_required?, options)
    assert_equal 0, cli.send(:search_collection_id, options)
  end

  def test_search_builds_query_with_tag
    cli = RaindropCli::CLI.new([])
    argv = ["ruby"]
    options = { tags: ["docs"] }

    assert_equal "ruby #docs", cli.send(:build_search_query, argv, options)
  end

  def test_search_builds_query_with_tag_only
    cli = RaindropCli::CLI.new([])
    argv = []
    options = { tags: ["docs"] }

    assert_equal "#docs", cli.send(:build_search_query, argv, options)
  end

  def test_search_accepts_multiple_tags
    cli = RaindropCli::CLI.new([])
    argv = ["ruby"]
    options = { tags: ["docs", "rails"] }

    assert_equal "ruby #docs #rails", cli.send(:build_search_query, argv, options)
  end

  def test_search_quotes_multi_word_tag
    cli = RaindropCli::CLI.new([])
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
    cli = RaindropCli::CLI.new([], stdout: stdout)
    items = [
      {
        "_id" => 1668242775,
        "title" => "Introducing Aliki: A Modern Theme for Ruby Documentation",
        "link" => "https://railsatscale.com/2025-12-22-introducing-aliki-a-modern-theme-for-ruby-documentation/"
      },
      {
        "_id" => 1667301016,
        "title" => "Rails 8.1 アプリ + SQLite3 を fly.io にデプロイして Litestream で Cloudflare R2 に...",
        "link" => "https://techracho.bpsinc.jp/hachi8833/2026_03_31/157035"
      }
    ]

    cli.send(:print_search_items, items)

    assert_equal <<~OUTPUT, stdout.string
      1668242775  Introducing Aliki: A Modern Theme for Ruby Documentation
                  https://railsatscale.com/2025-12-22-introducing-aliki-a-modern-theme-for-ruby-documentation/

      1667301016  Rails 8.1 アプリ + SQLite3 を fly.io にデプロイして Litestream で Cloudflare R2 に...
                  https://techracho.bpsinc.jp/hachi8833/2026_03_31/157035

    OUTPUT
  end

  def test_search_prints_json_items
    stdout = StringIO.new
    cli = RaindropCli::CLI.new([], stdout: stdout)
    items = [
      {
        "_id" => 1668242775,
        "title" => "Introducing Aliki: A Modern Theme for Ruby Documentation",
        "link" => "https://railsatscale.com/2025-12-22-introducing-aliki-a-modern-theme-for-ruby-documentation/"
      }
    ]

    cli.send(:print_search_items, items, json: true)

    assert_equal items, JSON.parse(stdout.string)
  end

  def test_search_prints_empty_json_items
    stdout = StringIO.new
    cli = RaindropCli::CLI.new([], stdout: stdout)

    cli.send(:print_search_items, [], json: true)

    assert_equal "[]\n", stdout.string
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
    assert_includes stderr, "Not authenticated. Run `raindrop auth token`."
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
    cli = RaindropCli::CLI.new([])
    argv = ["--json", "1668242775"]

    options = cli.send(:parse_get_options, argv)

    assert options.fetch(:json)
    assert_equal ["1668242775"], argv
  end

  def test_get_prints_human_readable_item
    stdout = StringIO.new
    cli = RaindropCli::CLI.new([], stdout: stdout)
    item = {
      "_id" => 1668242775,
      "title" => "Introducing Aliki: A Modern Theme for Ruby Documentation",
      "link" => "https://railsatscale.com/2025-12-22-introducing-aliki-a-modern-theme-for-ruby-documentation/",
      "tags" => ["ruby", "docs"],
      "created" => "2026-04-01T12:48:22.646Z",
      "lastUpdate" => "2026-04-01T12:48:22.646Z",
      "excerpt" => "Ruby's documentation gets a fresh look."
    }

    cli.send(:print_raindrop_detail, item)

    assert_equal <<~OUTPUT, stdout.string
      ID: 1668242775
      Title: Introducing Aliki: A Modern Theme for Ruby Documentation
      URL: https://railsatscale.com/2025-12-22-introducing-aliki-a-modern-theme-for-ruby-documentation/
      Tags: ruby, docs
      Created: 2026-04-01T12:48:22.646Z
      Updated: 2026-04-01T12:48:22.646Z
      Description:
      Ruby's documentation gets a fresh look.
    OUTPUT
  end

  def test_get_prints_json_item
    stdout = StringIO.new
    cli = RaindropCli::CLI.new([], stdout: stdout)
    item = {
      "_id" => 1668242775,
      "title" => "Introducing Aliki: A Modern Theme for Ruby Documentation",
      "link" => "https://railsatscale.com/2025-12-22-introducing-aliki-a-modern-theme-for-ruby-documentation/"
    }

    cli.send(:print_json_item, item)

    assert_equal item, JSON.parse(stdout.string)
  end

  def test_tags_requires_authentication
    code, stdout, stderr, = run_cli(["tags"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth token`."
  end

  def test_tags_rejects_arguments
    code, stdout, stderr, = run_cli(["tags", "extra"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: extra"
  end

  def test_collections_requires_authentication
    code, stdout, stderr, = run_cli(["collections"])

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "Not authenticated. Run `raindrop auth token`."
  end

  def test_collections_rejects_arguments
    code, stdout, stderr, = run_cli(["collections", "extra"], config: FakeConfig.new(token: "stored-token"))

    assert_equal 1, code
    assert_empty stdout
    assert_includes stderr, "invalid argument: extra"
  end

  def test_collections_deduplicates_items_by_id
    cli = RaindropCli::CLI.new([])
    items = [
      { "_id" => 55596991, "title" => "Pocket", "count" => 2368 },
      { "_id" => 55596991, "title" => "Pocket", "count" => 2368 },
      { "_id" => 123, "title" => "Ruby", "count" => 8 }
    ]

    deduplicated_items = cli.send(:unique_items_by_id, items)

    assert_equal [55596991, 123], deduplicated_items.map { |item| item.fetch("_id") }
  end
end
