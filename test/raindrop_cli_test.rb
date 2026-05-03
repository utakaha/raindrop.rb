# frozen_string_literal: true

require_relative "test_helper"

class FakeConfig
  attr_reader :written_token, :deleted

  def initialize(token: nil, path: "/tmp/raindrop-cli/config.yml")
    @token = token
    @path = path
    @deleted = false
  end

  def path
    @path
  end

  def access_token
    @token.to_s
  end

  def save_access_token(token)
    @written_token = token
    @token = token
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
